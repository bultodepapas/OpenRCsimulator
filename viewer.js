/* True orbit photographs of the project's models; no 3D runtime dependency. */
(() => {
  const canvas = document.querySelector('#aircraft-canvas');
  const context = canvas.getContext('2d', {alpha:false});
  const poster = document.querySelector('#aircraft-image');
  const controls = document.querySelector('.viewer-controls');
  const mode = document.querySelector('.stage-mode');
  const slider = document.querySelector('#spin-angle');
  const degrees = document.querySelector('#spin-degrees');
  const toggle = document.querySelector('#spin-toggle');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let selected = '', modelName = '', frame = 4, sheet = null, sheetVariant = null, metadata = null;
  let visible = false, playing = !reduced.matches, request = 0, animationTimer = 0, lastFrameTime = 0;
  let generation = 0, drag = null, metadataRequest = null, activeLoad = null, failed = false, inspecting = false;
  const images = new Map();
  const frameInterval = 125;
  // Bump when publishing a new manifest; sheet URLs use their manifest hashes.
  const manifestURL = 'assets/turntables.json?v=web15-responsive-20261102';
  mode.hidden = true;
  degrees.setAttribute('aria-live','off');

  function localize() {
    const caption = reduced.matches ? siteText.nextView : playing ? siteText.pause : siteText.rotate;
    toggle.innerHTML = `<span>${caption}</span><span aria-hidden="true">${reduced.matches ? '→' : playing ? 'Ⅱ' : '↻'}</span>`;
    toggle.removeAttribute('aria-pressed');
    canvas.setAttribute('aria-label',`${modelName} — ${siteText.studio360}`);
    document.querySelector('#viewer-hint').textContent = failed ? siteText.viewerFailed : siteText.viewerHint;
    updateFrameUI();
  }

  function updateFrameUI() {
    slider.value = String(frame);
    slider.setAttribute('aria-valuetext',`${Math.round(frame * 360 / (metadata?.frame_count || 36))} ${siteText.degrees}`);
    degrees.value = `${String(Math.round(frame * 360 / (metadata?.frame_count || 36))).padStart(3,'0')}°`;
  }

  function draw() {
    if (!sheet || !metadata || !context) return;
    const {frame_width:w, frame_height:h} = sheetVariant;
    const {columns, frame_count:count} = metadata;
    frame = ((frame % count) + count) % count;
    context.drawImage(sheet,(frame % columns)*w,Math.floor(frame/columns)*h,w,h,0,0,canvas.width,canvas.height);
    updateFrameUI();
  }

  function canAnimate() {
    return playing && visible && sheet && !document.hidden && !reduced.matches && !inspecting;
  }

  function cancelAnimation() {
    if(animationTimer) clearTimeout(animationTimer);
    if(request) cancelAnimationFrame(request);
    animationTimer=0;request=0;
  }

  function scheduleNextFrame() {
    if(!canAnimate() || animationTimer || request) return;
    const delay=Math.max(0,frameInterval-(performance.now()-lastFrameTime));
    animationTimer=setTimeout(() => {
      animationTimer=0;
      if(!canAnimate()) return;
      request=requestAnimationFrame(time => {
        request=0;
        if(!canAnimate()) return;
        frame++;draw();lastFrameTime=time;
        scheduleNextFrame();
      });
    },delay);
  }

  function synchronize() {
    cancelAnimation();
    localize();
    scheduleNextFrame();
  }

  function cancelActiveLoad() {
    const load=activeLoad;
    if(!load) return;
    activeLoad=null;
    if(load.image) {
      // Removing src cancels a pending image request without starting an empty-URL request.
      load.image.removeAttribute('src');
      load.image=null;
    }
  }

  function isCurrentLoad(load) {
    return activeLoad===load && load.generation===generation && selected===load.key && visible && !inspecting;
  }

  function cacheImage(key, asset) {
    images.delete(key);
    images.set(key,asset);
    while(images.size>2) images.delete(images.keys().next().value);
  }

  function desiredVariant(model) {
    const full={src:model.src,sha256:model.sha256,frame_width:metadata.frame_width,frame_height:metadata.frame_height};
    const small=model.variants?.small;
    const width=canvas.parentElement.getBoundingClientRect().width;
    const ratio=window.devicePixelRatio;
    if(small && Number.isFinite(width) && width>0 && Number.isFinite(ratio) && ratio>0 &&
       width*ratio<=small.frame_width && width*ratio*full.frame_height/full.frame_width<=small.frame_height) return small;
    return full;
  }

  function covers(actual, desired) {
    return actual && actual.frame_width>=desired.frame_width && actual.frame_height>=desired.frame_height;
  }

  function versionedURL(variant) {
    const url=new URL(variant.src,document.baseURI);
    if(variant.sha256) url.searchParams.set('v',variant.sha256);
    return url.href;
  }

  function ensureVariant() {
    if(!context || !selected || !visible || inspecting) return;
    const model=metadata?.models?.[selected];
    if(!model) {if(!sheet && !activeLoad) load();return;}
    const desired=desiredVariant(model);
    // Keep a larger decoded sheet when the stage shrinks; do not spend another request.
    if(covers(sheetVariant,desired)) return;
    if(activeLoad) {
      if(!activeLoad.variant || covers(activeLoad.variant,desired)) return;
      generation++;cancelActiveLoad();
    }
    load();
  }

  async function load() {
    if(!context || !selected || !visible || inspecting) return;
    const key = selected;
    if(activeLoad?.key===key && activeLoad.generation===generation) return;
    const current = generation;
    const loadState={key,generation:current,image:null};
    activeLoad=loadState;
    failed=false;
    localize();
    try {
      metadataRequest ??= fetch(manifestURL).then(response => {
        if(!response.ok) throw new Error('Turntable metadata unavailable');
        return response.json();
      }).catch(error => {metadataRequest=null;throw error;});
      metadata = await metadataRequest;
      if(!isCurrentLoad(loadState)) return;
      const model = metadata.models[key];
      if(!model) throw new Error('Model unavailable');
      const variant=desiredVariant(model);
      if(covers(sheetVariant,variant)) return;
      loadState.variant=variant;
      const assetURL=versionedURL(variant);
      let asset = images.get(assetURL);
      if(asset) {
        cacheImage(assetURL,asset);
      } else {
        if(!isCurrentLoad(loadState)) return;
        asset = new Image();loadState.image=asset;asset.src = assetURL;await asset.decode();
        if(!isCurrentLoad(loadState)) return;
        cacheImage(assetURL,asset);
        loadState.image=null;
      }
      if(!isCurrentLoad(loadState)) return;
      const replacing=!!sheet;
      sheet = asset;sheetVariant=variant;if(!replacing) frame=4;failed=false;
      canvas.width=variant.frame_width;canvas.height=variant.frame_height;
      slider.max=metadata.frame_count-1;
      lastFrameTime=performance.now();
      draw();poster.hidden=true;canvas.hidden=false;controls.hidden=false;mode.hidden=false;
      synchronize();
    } catch {
      if(!isCurrentLoad(loadState)) return;
      if(loadState.image) {loadState.image.removeAttribute('src');loadState.image=null;}
      // A failed upgrade leaves the existing view and controls usable.
      if(sheet) {failed=false;localize();return;}
      sheetVariant=null;failed=true;canvas.hidden=true;poster.hidden=false;controls.hidden=true;mode.hidden=true;localize();
    } finally {
      if(activeLoad===loadState) activeLoad=null;
    }
  }

  window.OpenRCViewer = {
    select(key,name) {
      modelName=name;
      if(selected===key){localize();ensureVariant();return;}
      generation++;cancelActiveLoad();
      selected=key;sheet=null;sheetVariant=null;failed=false;synchronize();
      canvas.hidden=true;poster.hidden=false;controls.hidden=true;mode.hidden=true;
      if(visible && !inspecting) load();
    }
  };
  toggle.addEventListener('click', () => {
    // Reduced motion allows deliberate single-frame control, never autoplay.
    if(reduced.matches) {frame++;draw();return;}
    playing=!playing;synchronize();
  });
  slider.addEventListener('input', () => {playing=false;frame=Number(slider.value);draw();synchronize();});
  canvas.addEventListener('pointerdown', event => {
    if(event.button !== 0 || !sheet) return;
    drag={id:event.pointerId,x:event.clientX,y:event.clientY,frame};
    playing=false;synchronize();canvas.setPointerCapture(event.pointerId);canvas.classList.add('is-dragging');
  });
  canvas.addEventListener('pointermove', event => {
    if(!drag || drag.id !== event.pointerId) return;
    const dx=event.clientX-drag.x;
    if(event.pointerType==='touch' && Math.abs(event.clientY-drag.y)>Math.abs(dx)+8) return;
    frame=drag.frame+Math.round(dx/(canvas.clientWidth/metadata.frame_count));draw();
  });
  const endDrag=()=>{drag=null;canvas.classList.remove('is-dragging');};
  canvas.addEventListener('pointerup',endDrag);canvas.addEventListener('pointercancel',endDrag);canvas.addEventListener('lostpointercapture',endDrag);
  document.addEventListener('visibilitychange',synchronize);
  document.addEventListener('openrc-inspection',event=>{
    inspecting=event.detail.open;
    if(inspecting && activeLoad) {generation++;cancelActiveLoad();}
    if(!inspecting && visible) ensureVariant();
    synchronize();
  });
  document.addEventListener('openrc-language',localize);
  reduced.addEventListener('change',()=>{if(reduced.matches)playing=false;synchronize();});
  if('ResizeObserver' in window) new ResizeObserver(ensureVariant).observe(canvas.parentElement);
  window.addEventListener('resize',ensureVariant);
  let resolutionQuery;
  function resolutionChanged() {watchResolution();ensureVariant();}
  function watchResolution() {
    resolutionQuery?.removeEventListener('change',resolutionChanged);
    resolutionQuery=matchMedia(`(resolution: ${window.devicePixelRatio || 1}dppx)`);
    resolutionQuery.addEventListener('change',resolutionChanged);
  }
  watchResolution();
  if('IntersectionObserver' in window){
    new IntersectionObserver(entries=>{
      const nextVisible=entries[0].isIntersecting;
      if(visible===nextVisible) return;
      visible=nextVisible;
      if(!visible && activeLoad) {generation++;cancelActiveLoad();}
      if(visible && !inspecting) ensureVariant();
      synchronize();
    },{rootMargin:'160px',threshold:0}).observe(canvas.parentElement);
  }else{visible=true;}
  localize();
})();
