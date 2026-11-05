// Lists a category's own page, its folder's README, as its first item.
// That item is "Overview", unless the folder names itself in
// _category_.json: then the README isn't an overview, and keeps its own
// title, `labelOf(id)`. A category with only its own page is that doc
// directly: an expandable category containing only "Overview" adds nothing.
module.exports = function indexFirst(items, labelOf = () => 'Overview') {
  return items.map((item) => {
    if (item.type !== 'category') return item;
    if (item.link?.type === 'doc' && item.items.length === 0) {
      return {type: 'doc', id: item.link.id, label: item.label};
    }
    const {link, ...category} = item;
    const own = link && link.type === 'doc' ? [{type: 'doc', id: link.id, label: labelOf(link.id)}] : [];
    return {...category, items: [...own, ...indexFirst(item.items, labelOf)]};
  });
};
