// Lists a category's own page as its first item, "Overview", when the
// category has more pages. A category with only its own page is that doc
// directly: an expandable category containing only "Overview" adds nothing.
module.exports = function indexFirst(items) {
  return items.map((item) => {
    if (item.type !== 'category') return item;
    if (item.link?.type === 'doc' && item.items.length === 0) {
      return {type: 'doc', id: item.link.id, label: item.label};
    }
    const {link, ...category} = item;
    const overview = link && link.type === 'doc' ? [{type: 'doc', id: link.id, label: 'Overview'}] : [];
    return {...category, items: [...overview, ...indexFirst(item.items)]};
  });
};
