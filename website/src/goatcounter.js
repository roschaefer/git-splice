import ExecutionEnvironment from '@docusaurus/ExecutionEnvironment';
import siteConfig from '@generated/docusaurus.config';

// GitHub Pages can't proxy the beacon through our own domain like the
// Netlify sites do, so visitors load GoatCounter's script and send their hits
// directly. Only the deployed site counts: not `docusaurus start` or `serve`.
const counting =
  ExecutionEnvironment.canUseDOM &&
  window.location.hostname === new URL(siteConfig.url).hostname;

if (counting) {
  const script = document.createElement('script');
  script.async = true;
  script.src = 'https://gc.zgo.at/count.js';
  script.dataset.goatcounter = 'https://git-splice.goatcounter.com/count';
  document.head.appendChild(script);
}

// count.js counts the page it loads on. Docusaurus then switches pages
// without reloading, so count each new page here; jumps to an anchor on the
// same page are not page views.
export function onRouteDidUpdate({location, previousLocation}) {
  if (counting && previousLocation && location.pathname !== previousLocation.pathname) {
    window.goatcounter?.count?.({path: location.pathname + location.search});
  }
}
