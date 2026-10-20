// Lists a category's own page as its first item, "Overview", instead of
// linking it from the category's label. Readers open a category with the
// arrow and click the first item they see; a page behind the label went
// unnoticed.
module.exports = function indexFirst(items) {
  return items.map((item) => {
    if (item.type !== 'category') return item;
    const {link, ...category} = item;
    const overview = link && link.type === 'doc' ? [{type: 'doc', id: link.id, label: 'Overview'}] : [];
    return {...category, items: [...overview, ...indexFirst(item.items)]};
  });
};
