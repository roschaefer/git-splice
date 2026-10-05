const fs = require('fs');
const path = require('path');

// Points relative links to repository files that aren't pages (setup.bash,
// LICENSE, ...) at the file on GitHub, so they work on the site as they do
// when browsing the repository.
module.exports = function repoFileLinks({repoUrl, repoRoot}) {
  return (tree, file) => {
    const visit = (node) => {
      if (node.type === 'link' && isRepoFile(node.url, file.path)) {
        const target = path.relative(repoRoot, path.resolve(path.dirname(file.path), node.url));
        node.url = `${repoUrl}/blob/main/${target.split(path.sep).join('/')}`;
      }
      (node.children || []).forEach(visit);
    };
    visit(tree);
  };
};

function isRepoFile(url, from) {
  if (/^([a-z][a-z0-9+.-]*:|#|\/)/i.test(url) || /\.mdx?(#|$)/.test(url)) {
    return false;
  }
  const target = path.resolve(path.dirname(from), url.split('#')[0]);
  return fs.existsSync(target) && fs.statSync(target).isFile();
}
