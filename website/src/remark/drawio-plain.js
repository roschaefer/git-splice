const fs = require('fs');
const path = require('path');

// Serves each .drawio.svg without the diagram draw.io embeds in it, its
// content attribute: the picture alone, as `drawio -x` without -e exports
// it. The attribute makes the root tag 5 to 19 KB long, longer than
// image-size reads, so Docusaurus would warn and leave out the drawing's
// width and height. GitHub shows the .drawio.svg itself.
module.exports = function drawioPlain({siteDir, repoRoot}) {
  const outDir = path.join(siteDir, '.drawings');
  return (tree, file) => {
    const visit = (node) => {
      if (node.type === 'image' && isLocalDrawing(node.url)) {
        const source = path.resolve(path.dirname(file.path), decodeURIComponent(node.url));
        if (fs.existsSync(source)) {
          const plain = path.join(outDir, path.relative(repoRoot, source).replace(/\.drawio\.svg$/, '.svg'));
          const picture = fs.readFileSync(source, 'utf8').replace(/ content="[^"]*"/, '');
          fs.mkdirSync(path.dirname(plain), {recursive: true});
          if (!fs.existsSync(plain) || fs.readFileSync(plain, 'utf8') !== picture) {
            fs.writeFileSync(plain, picture);
          }
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
