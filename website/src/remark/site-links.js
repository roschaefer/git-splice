// Turns absolute links to this site (as the README needs them on GitHub)
// into site-internal links, so they stay on whatever host serves the site
// -- localhost during `just site-serve` -- and the broken-link check covers
// them.
module.exports = function siteLinks({siteUrl}) {
  return (tree) => {
    const visit = (node) => {
      if (node.type === 'link') {
        const prefix = [siteUrl, 'https://roschaefer.github.io/git-splice/']
          .find((url) => node.url.startsWith(url));
        if (prefix) node.url = '/' + node.url.slice(prefix.length);
      }
      (node.children || []).forEach(visit);
    };
    visit(tree);
  };
};
