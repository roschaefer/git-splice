const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const build = path.resolve(__dirname, '..', 'build');

function htmlFiles(dir) {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap((entry) => {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) return htmlFiles(file);
    return entry.name.endsWith('.html') ? [file] : [];
  });
}

test('no image alt or title text on a built page is HTML-escaped twice', () => {
  const pages = htmlFiles(build);
  assert.ok(pages.length > 0, `no pages in ${build}; run the site build first`);
  const doubled = pages.flatMap((page) =>
    [...fs.readFileSync(page, 'utf8').matchAll(/<img\b[^>]*>/g)]
      .flatMap(([img]) => [...img.matchAll(/\b(?:alt|title)="([^"]*&amp;(?:#\d+|#x[0-9a-f]+|[a-z]+);[^"]*)"/gi)])
      .map(([, text]) => `${path.relative(build, page)}: ${text}`));
  assert.deepEqual(doubled, []);
});
