import ExecutionEnvironment from '@docusaurus/ExecutionEnvironment';
import siteConfig from '@generated/docusaurus.config';

const counting =
  ExecutionEnvironment.canUseDOM &&
  window.location.hostname === new URL(siteConfig.url).hostname;

if (counting) {
  const script = document.createElement('script');
  script.async = true;
  script.src = '/gc/count.js';
  script.dataset.goatcounter = '/gc/count';
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
