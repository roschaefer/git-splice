import {test} from 'node:test';
import assert from 'node:assert/strict';
import count from './goatcounter.ts';

test('forwards visitor metadata and events to the configured site without exposing the token', async () => {
  const originalFetch = globalThis.fetch;
  const pending: Promise<unknown>[] = [];
  const requests: {url: Parameters<typeof fetch>[0]; init: Parameters<typeof fetch>[1]}[] = [];
  Object.assign(globalThis, {Netlify: {env: {get: (name: string) => ({GOATCOUNTER_SITE: 'git-splice', GOATCOUNTER_API_TOKEN: 'secret'})[name]}}});
  globalThis.fetch = async (url, init) => {
    requests.push({url, init});
    return new Response(null, {status: 202});
  };
  try {
    const response = await count(new Request('https://example.com/gc/count?p=%2Fdocs%2F&t=Docs&r=https%3A%2F%2Fexample.org%2F&e=true&s=1920,1080&q=campaign%3Ddocs&b=150', {
      headers: {'user-agent': 'visitor-browser', 'accept-language': 'de-DE,de;q=0.9'},
    }), {ip: '203.0.113.7', waitUntil: p => pending.push(p)});
    await Promise.all(pending);
    assert.equal(requests.length, 1);
    const {url, init} = requests[0];
    assert.equal(url, 'https://git-splice.goatcounter.com/api/v0/count');
    assert.equal(init?.headers?.['authorization'], 'Bearer secret');
    assert.deepEqual(JSON.parse(String(init?.body)), {hits: [{
      path: '/docs/', title: 'Docs', ref: 'https://example.org/', event: true,
      size: '1920,1080', query: 'campaign=docs', bot: 150,
      user_agent: 'visitor-browser', language: 'de-DE', ip: '203.0.113.7',
    }]});
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(response.headers.get('content-type'), 'image/gif');
    assert.equal(new TextDecoder().decode((await response.arrayBuffer()).slice(0, 6)), 'GIF89a');
  } finally {
    globalThis.fetch = originalFetch;
    Reflect.deleteProperty(globalThis, 'Netlify');
  }
});

test('ignores missing paths and configuration and survives upstream failures', async () => {
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  const pending: Promise<unknown>[] = [];
  const errors: unknown[] = [];
  let calls = 0;
  let configured = false;
  Object.assign(globalThis, {Netlify: {env: {get: (name: string) => configured ? ({GOATCOUNTER_SITE: 'example', GOATCOUNTER_API_TOKEN: 'secret'})[name] : undefined}}});
  console.error = (...args) => { errors.push(args); };
  globalThis.fetch = async () => { calls++; throw new Error('offline'); };
  const context = {ip: '203.0.113.7', waitUntil: (p: Promise<unknown>) => pending.push(p)};
  try {
    assert.equal((await count(new Request('https://example.com/gc/count?p=/'), context)).status, 200);
    configured = true;
    await count(new Request('https://example.com/gc/count'), context);
    assert.equal(calls, 0);
    assert.equal((await count(new Request('https://example.com/gc/count?p=/'), context)).status, 200);
    await Promise.all(pending);
    assert.equal(calls, 1);
    assert.equal(errors.length, 2);
  } finally {
    globalThis.fetch = originalFetch;
    console.error = originalError;
    Reflect.deleteProperty(globalThis, 'Netlify');
  }
});
