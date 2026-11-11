# Publishing the documentation on Netlify

Import `roschaefer/git-splice` into Netlify, selecting `main` as the production
branch. Keep the base directory at the repository root and leave the package
directory unset. The root `netlify.toml` installs the website's pinned pnpm
dependencies, builds Docusaurus, publishes `website/build`, and configures
the analytics Edge Function. No Rust or Nix build is needed.

Add `git-splice.roschaefer.de` as the production custom domain. Follow Netlify's
instructions to add its DNS record at your DNS provider; Netlify provisions
HTTPS. The canonical URL is configured in `website/docusaurus.config.js`.

In Netlify's environment settings, with Functions scope and production
context only, configure:

- `GOATCOUNTER_SITE`: `git-splice`
- `GOATCOUNTER_API_TOKEN`: a GoatCounter API token with count permission

Redeploy after setting the variables. Keep secrets out of Git. The browser
only loads analytics on the canonical production hostname, so local servers
and Netlify preview domains do not record pageviews.

Check a production page with browser network tools: `/gc/count.js` should
load and `/gc/count` should return a no-store GIF. Confirm the visit appears
in GoatCounter; a successful GIF alone does not prove upstream delivery.
Check Edge Function logs for configuration or API errors. Verify a subsequent
Docusaurus navigation records one more pageview.

The GitHub Pages deployment workflow is removed; CI still builds the site
and checks links. Disable Pages in GitHub repository settings at cutover.
Previously distributed github.io links need a separate redirect-only Pages
deployment if they must remain reachable; Netlify cannot redirect requests
sent to GitHub's hostname. Existing source links to that hostname are rewritten
to local paths when Docusaurus builds them.

The reusable analytics implementation is mounted at `integrations/goatcounter`.
See its README for reuse in the other websites.
