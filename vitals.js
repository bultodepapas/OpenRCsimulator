/* Sample coarse page experience metrics through the site's existing GA4 tag. */
(() => {
  if (location.hostname !== 'bultodepapas.github.io' || !globalThis.crypto?.getRandomValues) return;
  const sample = globalThis.crypto.getRandomValues(new Uint8Array(1))[0] < 26; // About 10% of page views.
  if (!sample) return;

  function report(metric) {
    const attribution = metric.attribution || {};
    const value = metric.name === 'CLS' ? Math.round(metric.value * 1000) : Math.round(metric.value);
    const parameters = {
      send_to: 'G-4Z11DSB2BV',
      metric_name: metric.name,
      metric_value: value,
      metric_unit: metric.name === 'CLS' ? 'milli_score' : 'ms',
      metric_rating: metric.rating,
      metric_navigation: metric.navigationType,
      page_locale: document.documentElement.lang,
    };
    const phases = metric.name === 'LCP'
      ? {lcp_ttfb_ms: attribution.timeToFirstByte,
         lcp_load_delay_ms: attribution.resourceLoadDelay,
         lcp_load_ms: attribution.resourceLoadDuration,
         lcp_render_delay_ms: attribution.elementRenderDelay}
      : metric.name === 'INP'
        ? {inp_input_delay_ms: attribution.inputDelay,
           inp_processing_ms: attribution.processingDuration,
           inp_presentation_ms: attribution.presentationDelay,
           inp_script_ms: attribution.totalScriptDuration,
           inp_style_layout_ms: attribution.totalStyleAndLayoutDuration}
        : {};
    for (const [name, duration] of Object.entries(phases)) {
      if (Number.isFinite(duration)) parameters[name] = Math.round(duration);
    }
    window.dataLayer = window.dataLayer || [];
    function gtag() { window.dataLayer.push(arguments); }
    gtag('event', 'web_vital', parameters);
  }

  import('./assets/vendor/web-vitals-6.2.3.attribution.js')
    .then(({onLCP, onINP, onCLS}) => {
      onLCP(report);
      onINP(report);
      onCLS(report);
    })
    .catch(() => {}); // The website stays usable when measurement is unavailable.
})();
