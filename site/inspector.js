/* Optional real geometry inspection. Neither the runtime nor GLBs load on entry. */
(() => {
  const dialog = document.querySelector('#model-inspector');
  const launch = document.querySelector('#open-inspector');
  const close = document.querySelector('#close-inspector');
  const mount = document.querySelector('#model-mount');
  const select = document.querySelector('#inspect-aircraft');
  const title = document.querySelector('#inspector-title');
  const loading = document.querySelector('.inspector-loading');
  const state = document.querySelector('#inspector-state');
  const bar = document.querySelector('.inspector-load-track>span');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const names = {stik:'Jensen Das Ugly Stik 60',extra:'Great Planes Extra 300S .60',mustang:'P-51D Mustang 1/4',jet:'VANTAGE',timber:'LUMBER',heli:'RC Helicopter / HX-700'};
  const detailPanel = document.querySelector('.inspector-details');
  // WEB-04 camera poses come from the native studio capture, in centered GLB coordinates.
  let jetViews = null, viewsRequest = null;
  let returnFocus = launch;
  let viewer = null, ready = false, failed = false, generation = 0, runtime = null, timeout = 0;

  function cameraOrbit(key) {
    const portrait = mount.clientWidth / Math.max(1,mount.clientHeight) < .9;
    return {perspective:`140deg 68deg ${portrait ? 110 : 75}%`,side:`90deg 78deg ${portrait ? 110 : 85}%`,top:`180deg 0deg ${portrait ? 115 : 100}%`}[key];
  }

  function loadViews() {
    viewsRequest ??= fetch('assets/cinema/jet-views.json').then(response => {
      if(!response.ok) throw new Error('Jet views unavailable');
      return response.json();
    }).then(views => {
      for(const key of ['cockpit','wing','tail']) {
        if(!['target','orbit'].every(property => Array.isArray(views[key]?.[property]) && views[key][property].length === 3 && views[key][property].every(Number.isFinite)) || views[key].orbit[2] <= 0) throw new Error('Invalid jet camera');
      }
      return views;
    }).catch(() => {viewsRequest = null;return null;});
    return viewsRequest;
  }

  function localize() {
    document.querySelector('.camera-presets').setAttribute('aria-label',siteText.cameraViews);
    document.querySelector('#inspect-zoom-in').setAttribute('aria-label',siteText.zoomIn);
    document.querySelector('#inspect-zoom-out').setAttribute('aria-label',siteText.zoomOut);
    detailPanel.querySelector('[role=group]').setAttribute('aria-label',siteText.jetDetails);
    const detailStatus = document.querySelector('#detail-unavailable');
    detailStatus.hidden = !ready || select.value !== 'jet' || Boolean(jetViews);
    detailStatus.textContent = siteText.detailUnavailable;
    state.textContent = failed ? siteText.modelFailed : siteText.modelPreparing;
    if (viewer) {
      viewer.alt = `${names[select.value]} — ${siteText.interactiveModel}`;
      const views = {front:siteText.front,back:siteText.back,left:siteText.left,right:siteText.right};
      const descriptions = {};
      for (const [key,value] of Object.entries(views)) {
        descriptions[key] = `${value}: ${names[select.value]}`;
        descriptions[`upper-${key}`] = `${siteText.above}. ${descriptions[key]}`;
        descriptions[`lower-${key}`] = `${siteText.below}. ${descriptions[key]}`;
      }
      descriptions['interaction-prompt'] = siteText.interactionPrompt;
      viewer.a11y = descriptions;
    }
  }

  function controls(enabled) {
    document.querySelectorAll('.camera-presets button,.inspector-zoom button,[data-jet-focus]').forEach(button => {button.disabled = !enabled;});
    if(!jetViews) document.querySelectorAll('[data-jet-focus]:not([data-jet-focus=overview])').forEach(button => {button.disabled = true;});
  }
  function fail(current) {
    if (current !== generation || !dialog.open) return;
    clearTimeout(timeout);failed = true;ready = false;loading.hidden = false;
    document.querySelector('.inspector-load-track').hidden = true;
    controls(false);localize();
  }

  async function loadModel(key,initialDetail='overview') {
    const current = ++generation;
    clearTimeout(timeout);ready = false;failed = false;
    title.textContent = names[key];
    detailPanel.hidden = key !== 'jet';
    loading.hidden = false;bar.style.transform = 'scaleX(0)';
    document.querySelector('.inspector-load-track').hidden = false;
    controls(false);mount.replaceChildren();viewer = null;localize();
    timeout = setTimeout(() => fail(current),45000);
    try {
      runtime ??= import('./assets/vendor/model-viewer-4.4.0.min.js').catch(error => {runtime = null;throw error;});
      const [,views] = await Promise.all([runtime,key === 'jet' ? loadViews() : Promise.resolve(jetViews)]);
      if (current !== generation || !dialog.open) return;
      jetViews = views;
      const ModelViewer = customElements.get('model-viewer');
      ModelViewer.modelCacheSize = 0;
      const element = document.createElement('model-viewer');
      viewer = element;
      for (const [name,value] of Object.entries({
        'camera-controls':'','touch-action':'none','disable-pan':'','interaction-prompt':'none',
        'environment-image':'neutral','shadow-intensity':'.8','shadow-softness':'1',
        'exposure':'1','tone-mapping':'neutral','camera-orbit':cameraOrbit('perspective'),
        'min-camera-orbit':'auto 0deg 25%','max-camera-orbit':'auto 180deg 180%',
        'field-of-view':'30deg','min-field-of-view':'15deg','max-field-of-view':'45deg','loading':'eager','reveal':'auto',
        'interpolation-decay':reduced.matches ? '0' : '70'
      })) element.setAttribute(name,value);
      element.addEventListener('progress', event => {
        if(current === generation) bar.style.transform = `scaleX(${event.detail.totalProgress})`;
      });
      element.addEventListener('load', () => {
        if(current !== generation || !dialog.open) return;
        clearTimeout(timeout);ready = true;failed = false;loading.hidden = true;
        controls(true);localize();
        if(key === 'jet' && initialDetail !== 'overview') focusDetail(initialDetail);
        else setCamera('perspective');
      });
      element.addEventListener('error', () => fail(current));
      element.addEventListener('camera-change', event => {
        if(event.detail.source === 'user-interaction') document.querySelectorAll('[data-camera],[data-jet-focus]').forEach(button => button.setAttribute('aria-pressed','false'));
      });
      element.src = `assets/models/${key}.glb`;
      localize();mount.append(element);
    } catch { fail(current); }
  }

  function setCamera(key) {
    if(!ready || !viewer) return;
    viewer.interpolationDecay = reduced.matches ? 0 : 90;
    viewer.fieldOfView = '30deg';viewer.cameraTarget = 'auto auto auto';viewer.cameraOrbit = cameraOrbit(key);
    if(reduced.matches) viewer.jumpCameraToGoal();
    document.querySelectorAll('[data-camera]').forEach(button => button.setAttribute('aria-pressed',String(button.dataset.camera === key)));
    document.querySelectorAll('[data-jet-focus]').forEach(button => button.setAttribute('aria-pressed',String(button.dataset.jetFocus === 'overview')));
  }
  function focusDetail(key) {
    if(!ready || !viewer || select.value !== 'jet') return;
    const view = jetViews?.[key];
    if(!view) {setCamera('perspective');return;}
    const portrait = mount.clientWidth / Math.max(1,mount.clientHeight) < .9;
    viewer.interpolationDecay = reduced.matches ? 0 : 125;
    viewer.fieldOfView = `${Number.isFinite(view.fov) ? view.fov : 38}deg`;
    viewer.cameraTarget = view.target.map(value => `${value}m`).join(' ');
    viewer.cameraOrbit = `${view.orbit[0]}deg ${view.orbit[1]}deg ${view.orbit[2] * (portrait ? 1.55 : 1)}m`;
    if(reduced.matches) viewer.jumpCameraToGoal();
    document.querySelectorAll('[data-camera]').forEach(button => button.setAttribute('aria-pressed','false'));
    document.querySelectorAll('[data-jet-focus]').forEach(button => button.setAttribute('aria-pressed',String(button.dataset.jetFocus === key)));
  }
  function zoom(factor) {
    if(!ready || !viewer) return;
    const orbit = viewer.getCameraOrbit();
    viewer.cameraOrbit = `${orbit.theta}rad ${orbit.phi}rad ${orbit.radius * factor}m`;
    if(reduced.matches) viewer.jumpCameraToGoal();
    document.querySelectorAll('[data-camera],[data-jet-focus]').forEach(button => button.setAttribute('aria-pressed','false'));
  }

  if(typeof dialog.showModal !== 'function') return;
  launch.hidden = false;
  function openInspector(key,detail,trigger) {
    if(dialog.open || !names[key]) return;
    returnFocus = trigger;
    select.value = key;
    dialog.showModal();document.documentElement.classList.add('inspection-open');
    document.dispatchEvent(new CustomEvent('openrc-inspection',{detail:{open:true}}));
    document.querySelector(`[data-aircraft="${key}"]`).click();
    loadModel(key,detail);
  }
  launch.addEventListener('click', () => {
    openInspector(document.querySelector('[data-aircraft][aria-pressed=true]').dataset.aircraft,'overview',launch);
  });
  document.querySelectorAll('[data-inspect-aircraft]').forEach(button => {
    button.hidden = false;
    button.addEventListener('click', () => openInspector(button.dataset.inspectAircraft,button.dataset.inspectDetail || 'overview',button));
  });
  close.addEventListener('click', () => dialog.close());
  dialog.addEventListener('close', () => {
    generation++;clearTimeout(timeout);ready = false;
    mount.replaceChildren();viewer = null;
    document.documentElement.classList.remove('inspection-open');
    document.dispatchEvent(new CustomEvent('openrc-inspection',{detail:{open:false}}));
    returnFocus?.focus({preventScroll:true});
  });
  select.addEventListener('change', () => {
    document.querySelector(`[data-aircraft="${select.value}"]`).click();
    loadModel(select.value);
  });
  document.querySelectorAll('[data-camera]').forEach(button => button.addEventListener('click', () => setCamera(button.dataset.camera)));
  document.querySelectorAll('[data-jet-focus]').forEach(button => button.addEventListener('click', () => focusDetail(button.dataset.jetFocus)));
  document.querySelector('#inspect-zoom-in').addEventListener('click', () => zoom(.8));
  document.querySelector('#inspect-zoom-out').addEventListener('click', () => zoom(1.25));
  document.addEventListener('openrc-language',localize);
  if ('ResizeObserver' in window) new ResizeObserver(() => {
    const preset = document.querySelector('[data-camera][aria-pressed=true]');
    if(dialog.open && preset) setCamera(preset.dataset.camera);
    else if(dialog.open) {
      const detail = document.querySelector('[data-jet-focus][aria-pressed=true]');
      if(detail) focusDetail(detail.dataset.jetFocus);
    }
  }).observe(mount);
  reduced.addEventListener('change', () => { if(viewer) viewer.interpolationDecay = reduced.matches ? 0 : 70; });
  localize();
})();
