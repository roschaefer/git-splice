const fs = require('fs');
const path = require('path');
const {plainCopy} = require('../drawings');

// Points each image of a .drawio.svg at its plain copy, which the
// drawings plugin, src/drawings.js, writes.
module.exports = function drawioPlain({siteDir, repoRoot}) {
  return (tree, file) => {
    const visit = (node) => {
      if (node.type === 'image' && isLocalDrawing(node.url)) {
        const plain = plainCopy(siteDir, repoRoot, path.resolve(path.dirname(file.path), decodeURIComponent(node.url)));
        if (fs.existsSync(plain)) {
          node.url = '@site/' + path.relative(siteDir, plain).split(path.sep).join('/');
        }
      }
      (node.children || []).forEach(visit);
    };
    visit(tree);
  };
};

function isLocalDrawing(url) {
  return /\.drawio\.svg$/.test(url) && !/^([a-z][a-z0-9+.-]*:|\/)/i.test(url);
}
