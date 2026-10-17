const fs = require('fs');
const path = require('path');

const scenarios = path.join(__dirname, '..', 'test', 'scenarios');

// A scenario folder, with its README as the page and its other documents and
// the given child scenarios below it.
function scenario(folder, ...children) {
  const id = `test/scenarios/${folder}`;
  const documents = fs
    .readdirSync(path.join(scenarios, folder))
    .filter((file) => file.endsWith('.md') && file !== 'README.md')
    .sort()
    .map((file) => `${id}/${file.slice(0, -'.md'.length)}`);
  const label = path.basename(folder);
  const items = [...documents, ...children];
  if (items.length === 0) return {type: 'doc', id: `${id}/README`, label};
  return {type: 'category', label, link: {type: 'doc', id: `${id}/README`}, items};
}

// The chapters list scenarios by hand, so a new scenario folder would be
// missing from the site without a word. Fail the build instead.
function everyScenario(items) {
  const listed = new Set(['test/scenarios/README']);
  const collect = (item) => {
    if (typeof item === 'string') listed.add(item);
    else if (item.type === 'doc') listed.add(item.id);
    if (item.link) listed.add(item.link.id);
    (item.items || []).forEach(collect);
  };
  items.forEach(collect);
  const missing = fs
    .readdirSync(scenarios, {recursive: true})
    .filter((file) => file.endsWith('.md'))
    .map((file) => `test/scenarios/${file.slice(0, -'.md'.length)}`)
    .filter((id) => !listed.has(id));
  if (missing.length > 0) {
    throw new Error(`website/sidebars.js: add these scenarios to a chapter: ${missing.join(', ')}`);
  }
  return items;
}

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
module.exports = {
  docs: [
    {type: 'doc', id: 'README', label: 'Overview'},
    {
      type: 'category',
      label: 'Installation',
      link: {type: 'doc', id: 'docs/installation'},
      items: ['docs/sandbox'],
    },
    {
      type: 'category',
      label: 'Walkthrough',
      link: {type: 'doc', id: 'test/walkthrough/README'},
      items: [
        'status', 'clone', 'fetch', 'log', 'merge', 'pull', 'diff', 'push', 'init', 'boundary', 'rebuild', 'key',
      ].map((command) => `test/walkthrough/${command}`),
    },
    {type: 'doc', id: 'test/concepts/sync-model/README', label: 'Sync model'},
    {type: 'doc', id: 'test/concepts/splice-file/README', label: 'The .splice file'},
    {type: 'doc', id: 'test/concepts/upstreams/README', label: 'Upstreams'},
    {type: 'doc', id: 'test/concepts/splice-identity/README', label: 'Splice identity'},
    {
      type: 'category',
      label: 'Nesting',
      link: {type: 'doc', id: 'test/concepts/nesting/README'},
      items: ['test/concepts/nesting/diamond', 'test/concepts/nesting/cycle'],
    },
    {
      type: 'category',
      label: 'Workflows',
      items: ['feature-branches', 'diverged', 'bump'].map((workflow) => `test/walkthrough/${workflow}`),
    },
    {
      type: 'category',
      label: 'Design',
      link: {type: 'doc', id: 'docs/design/README'},
      items: ['docs/design/name', 'docs/design/accidental-monorepo-push'],
    },
    {
      type: 'category',
      label: 'Comparisons',
      link: {type: 'doc', id: 'test/comparisons/README'},
      items: [
        'test/comparisons/git-submodule',
        'test/comparisons/git-subtree',
        {
          type: 'category',
          label: 'Third-party tools',
          link: {type: 'doc', id: 'test/comparisons/third-party/README'},
          items: ['git-subrepo', 'josh', 'copybara'].map((tool) => `test/comparisons/third-party/${tool}`),
        },
      ],
    },
    {
      type: 'category',
      label: 'Going forward',
      link: {type: 'doc', id: 'docs/going-forward/README'},
      items: ['docs/going-forward/package-managers', 'docs/going-forward/mirrors', 'docs/going-forward/jj', 'docs/going-forward/weak-parents'],
    },
    {
      type: 'category',
      label: 'Scenarios',
      link: {type: 'doc', id: 'test/scenarios/README'},
      items: everyScenario([
        {
          type: 'category',
          label: 'Everyday sync',
          items: [
            scenario('sync-model', scenario('sync-model/after-pull', scenario('sync-model/after-pull/pushed-and-bumped'))),
            scenario('up-to-date'),
            scenario('up-to-date/pull-ahead'),
            scenario('up-to-date/push-ahead'),
            scenario('up-to-date/diverged-then-pulled'),
            scenario('up-to-date/push-ahead/diverged-common-ancestor'),
            scenario('up-to-date/push-ahead/pushed-then-pulled', scenario('up-to-date/push-ahead/pushed-then-pulled/pushed-then-changed')),
            scenario('up-to-date/push-ahead/uncommitted-changes'),
            scenario('many-splices'),
            scenario('never-fetched'),
          ],
        },
        {
          type: 'category',
          label: 'Starting a splice',
          items: [
            scenario('clone-copied-content'),
            scenario('clone-differing-content'),
            scenario('clone-on-feature-branch'),
            scenario(
              'init-new-upstream',
              scenario('init-new-upstream/removed-before-init'),
              scenario('init-new-upstream/unspliced-then-cloned-again'),
            ),
            scenario('init-then-cloned'),
            scenario('clone-without-commits'),
            scenario('submodule-in-linked-worktree'),
          ],
        },
        {
          type: 'category',
          label: 'Branches and teamwork',
          items: [
            scenario(
              'up-to-date/feature-branch-unchanged',
              scenario(
                'up-to-date/feature-branch-unchanged/feature-branch-changed',
                scenario('up-to-date/feature-branch-unchanged/feature-branch-changed/stacked-branch'),
              ),
              scenario('up-to-date/feature-branch-unchanged/merge-in-monorepo'),
            ),
            scenario('up-to-date/push-ahead/feature-branch-from-main'),
            scenario('up-to-date/squash-merged-pull', scenario('up-to-date/squash-merged-pull/local-edit-in-the-squash')),
            scenario('concurrent-pulls'),
            scenario('bisect-into-a-pull', scenario('bisect-into-a-pull/after-a-push')),
          ],
        },
        {
          type: 'category',
          label: 'Upstreams',
          items: [
            scenario('default-branch'),
            scenario('several-upstreams'),
            scenario('up-to-date/shared-remote-url'),
            scenario('up-to-date/push-ahead/upstream-moved'),
            scenario('splice-refs'),
          ],
        },
        {
          type: 'category',
          label: 'Nested splices',
          items: [
            scenario('nested-splices', scenario('nested-splices/outer-fork'), scenario('nested-splices/three-levels')),
            scenario('nested-default-branch'),
          ],
        },
        {
          type: 'category',
          label: 'Rewritten history',
          items: [
            scenario('up-to-date/push-ahead/edited-before-push'),
            scenario('upstream-rewritten-equal-tree'),
            scenario('up-to-date/push-ahead/diverged-unrelated-history'),
          ],
        },
        {
          type: 'category',
          label: 'Moved folders',
          items: [scenario('up-to-date/push-ahead/moved-with-unpushed-commits'), scenario('swapped-splices')],
        },
        'test/scenarios/known-bugs',
      ]),
    },
    'docs/development',
    'docs/writing',
    'CONTRIBUTING',
  ],
};
