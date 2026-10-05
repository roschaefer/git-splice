// Turns absolute links to this site (as the README needs them on GitHub)
// into site-internal links, so they stay on whatever host serves the site
// -- localhost during `just site-serve` -- and the broken-link check covers
// them.
module.exports = function siteLinks({siteUrl}) {
  return (tree) => {
    const visit = (node) => {
      if (node.type === 'link' && node.url.startsWith(siteUrl)) {
        node.url = '/' + node.url.slice(siteUrl.length);
      }
      (node.children || []).forEach(visit);
    };
    visit(tree);
  };
};
