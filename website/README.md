# Documentation website

Run `just site-dev` or `just site-build` from the repository root.
The Nix dev shell provides Node.js and pnpm; `package.json` pins pnpm for Netlify.

In Netlify, select `main` as the production branch and set **Base directory**
to `website`; leave **Package directory** unset. Netlify reads
[`netlify.toml`](netlify.toml), installs dependencies, and publishes `build/`.
Set the custom domain to `git-splice.roschaefer.de`.

For analytics environment variables, token permissions, and tests, see the
[shared integration documentation](integrations/goatcounter/README.md).
The [Edge Function entry point](netlify/edge-functions/goatcounter.ts) re-exports
that splice. The browser integration counts Docusaurus navigation and only
loads on the canonical production hostname.

GitHub Pages serves a [redirect page](github-pages/index.html) for the old
github.io homepage and documentation paths. The `docs-site` workflow publishes
it as both `index.html` and `404.html`; keep Pages configured to use GitHub Actions.
