# GoatCounter on Netlify

A same-origin collection endpoint for hosted GoatCounter. GoatCounter still
runs the analytics service; Netlify forwards browser hits through the official
API with the visitor's IP, user agent, and language. No package installation
or build step is required for the function.

Mount this repository at `integrations/goatcounter` using git-splice. Add
`netlify/edge-functions/goatcounter.ts` in the consuming repository:

```ts
export {default} from "../../integrations/goatcounter/goatcounter.ts";
```

Add these rules to the consuming repository's `netlify.toml`:

```toml
[[redirects]]
from = "/gc/count.js"
to = "https://gc.zgo.at/count.js"
status = 200
force = true

[[edge_functions]]
function = "goatcounter"
path = "/gc/count"
```

Set `GOATCOUNTER_SITE` to your GoatCounter site code, such as `git-splice`,
and `GOATCOUNTER_API_TOKEN` to a token with permission to count pageviews.
Configure these in Netlify's UI or CLI with Functions scope, for production
only. Variables in `netlify.toml` are unavailable to Edge Functions.
Never place the token in browser code.

```html
<script async src="/gc/count.js" data-goatcounter="/gc/count"></script>
```

For single-page applications, call `window.goatcounter.count({path: ...})`
after navigation; the script counts its initial page automatically. Avoid
loading the script on local development and deploy previews.

The exported `send(hit, token, site)` helper can also record server-side
events, such as downloads. Use trusted request metadata for `ip` and
`user_agent`. The site argument is a GoatCounter site code.

Run `node --experimental-strip-types --test goatcounter.test.ts` with Node 24.
Tests use a mocked API and never submit real pageviews.

This reduces blocking of shared analytics domains. It cannot guarantee
collection in browsers that block analytics. See the
[GoatCounter API](https://www.goatcounter.com/api.html) and
[Netlify Edge Function environment documentation](https://docs.netlify.com/build/edge-functions/environment-variables/).
