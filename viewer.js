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
  let selected = '', modelName = '', frame = 4, sheet = null, metadata = null;
  let visible = false, playing = !reduced.matches, request = 0, lastFrameTime = 0;
  let generation = 0, drag = null, metadataRequest = null, failed = false;
  const images = new Map();
  mode.hidden = true;
  degrees.setAttribute('aria-live','off');

  function localize() {
    const english = document.documentElement.lang === 'en';
    const caption = reduced.matches ? (english ? 'Next view' : 'Avanzar') : playing ? (english ? 'Pause' : 'Pausar') : (english ? 'Rotate' : 'Girar');
    toggle.innerHTML = `<span>${caption}</span><span aria-hidden="true">${reduced.matches ? '→' : playing ? 'Ⅱ' : '↻'}</span>`;
    toggle.setAttribute('aria-pressed', String(playing));
    canvas.setAttribute('aria-label',`${modelName} — ${english ? '360 degree studio view' : 'vista de estudio de 360 grados'}`);
    slider.setAttribute('aria-valuetext',`${frame * 10} ${english ? 'degrees' : 'grados'}`);
    document.querySelector('#viewer-hint').textContent = failed ? (english ? 'Static model view. The 360° view could not load.' : 'Vista estática del modelo. No se pudo cargar la vista 360°.') : (english ? 'Drag to explore · Use the slider to change the angle.' : 'Arrastra para explorar · Usa el control para cambiar de ángulo.');
  }

  function draw() {
    if (!sheet || !metadata || !context) return;
    const {frame_width:w, frame_height:h, columns, frame_count:count} = metadata;
    frame = ((frame % count) + count) % count;
    context.drawImage(sheet,(frame % columns)*w,Math.floor(frame/columns)*h,w,h,0,0,canvas.width,canvas.height);
    slider.value = String(frame);
    degrees.value = `${String(Math.round(frame * 360 / count)).padStart(3,'0')}°`;
    localize();
  }

  function animate(time) {
    request = 0;
    if (!playing || !visible || !sheet || document.hidden || reduced.matches) return;
    if (time-lastFrameTime >= 125) {frame++;draw();lastFrameTime=time;}
    request = requestAnimationFrame(animate);
  }

  function synchronize() {
    if(request) cancelAnimationFrame(request);
    request = 0;
    localize();
    if(playing && visible && sheet && !document.hidden && !reduced.matches) request=requestAnimationFrame(animate);
  }

  async function load() {
    if(!context || !selected) return;
    const current = ++generation;
    const key = selected;
    try {
      metadataRequest ??= fetch('assets/turntables.json').then(response => {
        if(!response.ok) throw new Error('Turntable metadata unavailable');
        return response.json();
      }).catch(error => {metadataRequest=null;throw error;});
      metadata = await metadataRequest;
      const model = metadata.models[key];
      if(!model) throw new Error('Model unavailable');
      let asset = images.get(key);
      if(!asset) {
        asset = new Image();asset.src = model.src;await asset.decode();
        images.set(key,asset);
        // Bound decoded image memory; network responses remain browser-cacheable.
        while(images.size>2) images.delete(images.keys().next().value);
      }
      if(current !== generation) return;
      sheet = asset;frame=4;failed=false;
      canvas.width=metadata.frame_width;canvas.height=metadata.frame_height;
      slider.max=metadata.frame_count-1;
      draw();poster.hidden=true;canvas.hidden=false;controls.hidden=false;mode.hidden=false;
      synchronize();
    } catch {
      if(current !== generation) return;
      sheet=null;failed=true;canvas.hidden=true;poster.hidden=false;controls.hidden=true;mode.hidden=true;localize();
    }
  }

  window.OpenRCViewer = {
    select(key,name) {
      modelName=name;
      if(selected===key){localize();return;}
      selected=key;generation++;sheet=null;failed=false;synchronize();
      canvas.hidden=true;poster.hidden=false;controls.hidden=true;mode.hidden=true;
      if(visible) load();
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
  document.addEventListener('openrc-language',localize);
  reduced.addEventListener('change',()=>{if(reduced.matches)playing=false;synchronize();});
  if('IntersectionObserver' in window){
    new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;if(visible&&!sheet)load();synchronize();},{rootMargin:'160px',threshold:0}).observe(canvas.parentElement);
  }else{visible=true;}
})();
