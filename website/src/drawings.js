const fs = require('fs');
const path = require('path');
const {optimize} = require('svgo');

// Serves each .drawio.svg without the diagram draw.io embeds in it, its
// content attribute: the picture alone, as `drawio -x` without -e exports
// it. The attribute makes the root tag 5 to 19 KB long, longer than
// image-size reads, so Docusaurus would warn and leave out the drawing's
// width and height. GitHub shows the .drawio.svg itself.
//
// A plugin writes the plain copies and watches the drawings, so `just
// site-serve` writes a changed drawing's copy again, and the page using it
// reloads; src/remark/drawio-plain.js points the pages at the copies.
module.exports = function drawings(context, {repoRoot}) {
  return {
    name: 'drawings',
    getPathsToWatch() {
      return [path.join(repoRoot, '**/*.drawio.svg')];
    },
    async loadContent() {
      for (const drawing of findDrawings(repoRoot)) {
        const plain = plainCopy(context.siteDir, repoRoot, drawing);
        const picture = optimize(fs.readFileSync(drawing, 'utf8'), {plugins: [dropDiagram]}).data;
        fs.mkdirSync(path.dirname(plain), {recursive: true});
        if (!fs.existsSync(plain) || fs.readFileSync(plain, 'utf8') !== picture) {
          fs.writeFileSync(plain, picture);
        }
      }
    },
  };
};

// Where drawing's plain copy goes: website/.drawings/, under the
// drawing's path in the repository.
module.exports.plainCopy = function plainCopy(siteDir, repoRoot, drawing) {
  return path.join(siteDir, '.drawings', path.relative(repoRoot, drawing).replace(/\.drawio\.svg$/, '.svg'));
};
const {plainCopy} = module.exports;

// The drawings in the repository, outside the site's own folder.
function findDrawings(repoRoot) {
  return fs
    .readdirSync(repoRoot, {recursive: true})
    .filter((file) => file.endsWith('.drawio.svg') && !/^(\.git|website)(\/|$)/.test(file))
    .map((file) => path.join(repoRoot, file));
}

// An svgo plugin, and the only one run: the root <svg> loses its content
// attribute, and nothing else changes.
const dropDiagram = {
  name: 'dropDiagram',
  fn: () => ({
    element: {
      enter(node, parent) {
        if (parent.type === 'root' && node.name === 'svg') {
          delete node.attributes.content;
        }
      },
    },
  }),
};
