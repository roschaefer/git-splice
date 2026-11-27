// Docusaurus's transformImage turns local images into <img> JSX and
// HTML-escapes their alt and title into the JSX attribute, which React
// escapes again: "Bob's" reaches the page as "Bob&amp;#39;s". It keeps the
// node object when it does, so `record` (before the default plugins) notes
// each image's text and `restore` (after them) puts it back unescaped.
const texts = new WeakMap();

function record() {
  return (tree) => {
    const visit = (node) => {
      if (node.type === 'image') texts.set(node, {alt: node.alt, title: node.title});
      (node.children || []).forEach(visit);
    };
    visit(tree);
  };
}

function restore() {
  return (tree) => {
    const visit = (node) => {
      const text = texts.get(node);
      if (text && node.type === 'mdxJsxTextElement' && node.name === 'img') {
        for (const attribute of node.attributes) {
          if (attribute.name in text && typeof attribute.value === 'string') {
            attribute.value = text[attribute.name];
          }
        }
      }
      (node.children || []).forEach(visit);
    };
    visit(tree);
  };
}

module.exports = {record, restore};
