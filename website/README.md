# Documentation website

Run `just site-dev` or `just site-build` from the repository root.
The Nix dev shell provides Node.js and pnpm; `package.json` pins pnpm for Netlify.

In Netlify, select `main` as the production branch and set **Base directory**
to `website`; leave **Package directory** unset. Netlify reads
[`netlify.toml`](netlify.toml), installs dependencies, and publishes `build/`.
Disable Deploy Previews and branch deploys; GitHub CI validates pull requests.
Set the custom domain to `git-splice.roschaefer.de`.

For analytics environment variables, token permissions, and tests, see the
[shared integration documentation](integrations/goatcounter/README.md).
The [Edge Function entry point](netlify/edge-functions/goatcounter.ts) re-exports
that splice. The browser integration counts Docusaurus navigation and only
loads on the canonical production hostname.

At cutover, disable or replace GitHub Pages. Preserving old github.io links
requires a separate redirect-only Pages deployment.
