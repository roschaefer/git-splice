const {themes} = require('prism-react-renderer');

// The site renders the repository's own Markdown -- the README, walkthrough,
// scenarios, comparisons and design notes -- in place, so the pages are the
// same files `just docs-check` runs against real output.
const repoUrl = 'https://github.com/roschaefer/git-splice';
const siteUrl = 'https://roschaefer.github.io';
const baseUrl = '/git-splice/';
const repoFileLinks = require('./src/remark/repo-file-links');
const siteLinks = require('./src/remark/site-links');

/** @type {import('@docusaurus/types').Config} */
module.exports = {
  title: 'git-splice',
  tagline: 'Keep folders of your monorepo in sync with their own repositories',
  url: siteUrl,
  baseUrl,
  organizationName: 'roschaefer',
  projectName: 'git-splice',
  trailingSlash: true,
  onBrokenLinks: 'throw',
  onBrokenAnchors: 'throw',
  markdown: {
    // CommonMark for .md files, so the HTML comments around scrut's hidden
    // setup blocks stay comments instead of failing as MDX.
    format: 'detect',
    hooks: {onBrokenMarkdownLinks: 'throw'},
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          path: '..',
          include: [
            'README.md',
            'docs/**/*.md',
            'test/walkthrough/**/*.md',
            'test/scenarios/**/*.md',
            'test/comparisons/**/*.md',
          ],
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js'),
          editUrl: `${repoUrl}/edit/main/`,
          beforeDefaultRemarkPlugins: [
            [repoFileLinks, {repoUrl, repoRoot: require('path').resolve(__dirname, '..')}],
            [siteLinks, {siteUrl: siteUrl + baseUrl}],
          ],
        },
        blog: false,
        theme: {customCss: require.resolve('./src/css/custom.css')},
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      navbar: {
        title: 'git-splice',
        items: [
          {type: 'docSidebar', sidebarId: 'docs', position: 'left', label: 'Docs'},
          {href: repoUrl, label: 'GitHub', position: 'right'},
        ],
      },
      footer: {
        style: 'dark',
        copyright: `MIT licensed · <a href="${repoUrl}">${repoUrl.replace('https://', '')}</a>`,
      },
      prism: {
        theme: themes.github,
        darkTheme: themes.dracula,
      },
    }),
};
