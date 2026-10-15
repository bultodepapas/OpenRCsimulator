/* Studio motion stays subordinate to reading, user intent and motion preferences. */
(() => {
  const hero = document.querySelector('.hero');
  const field = document.querySelector('.field');
  const film = document.querySelector('#hero-video');
  const toggle = document.querySelector('#film-toggle');
  const progress = document.querySelector('.reading-progress');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const connection = navigator.connection;
  let visible = false, started = false, allowed = !reduced.matches && !connection?.saveData;
  let requested = 0, playback = 0, inspection = false;

  function filmLabel() {
    const english = document.documentElement.lang === 'en';
    const active = allowed && !film.paused;
    toggle.querySelector('.film-label').textContent = active ? (english ? 'Pause scene' : 'Pausar escena') : (english ? 'Play scene' : 'Reproducir escena');
    toggle.querySelector('.film-icon').textContent = active ? 'Ⅱ' : '▷';
  }

  async function synchronizeFilm() {
    const request = ++playback;
    if (!allowed || !visible || document.hidden || inspection) {
      film.pause();filmLabel();return;
    }
    if (!started) { film.src = film.dataset.src; started = true; }
    try {
      await film.play();
      if (request !== playback) return;
      film.classList.add('is-playing');
    } catch { /* A poster and explicit play control remain if autoplay is unavailable. */ }
    filmLabel();
  }

  toggle.hidden = false;
  toggle.addEventListener('click', () => {
    allowed = film.paused;
    synchronizeFilm();
  });
  film.addEventListener('error', () => {
    allowed = false;film.classList.remove('is-playing');toggle.hidden = true;
  });
  film.addEventListener('play', filmLabel);
  film.addEventListener('pause', filmLabel);
  document.addEventListener('openrc-language', filmLabel);
  document.addEventListener('visibilitychange', synchronizeFilm);
  document.addEventListener('openrc-inspection', event => {inspection = event.detail.open;synchronizeFilm();});
  reduced.addEventListener('change', () => {
    if (reduced.matches) allowed = false;
    synchronizeFilm();schedule();
  });
  connection?.addEventListener('change', () => {
    if (connection.saveData) allowed = false;
    synchronizeFilm();
  });
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(entries => {
      visible = entries[0].isIntersecting;
      synchronizeFilm();
    }, {threshold:.05}).observe(hero);
  } else { visible = true;synchronizeFilm(); }

  function updateDepth() {
    requested = 0;
    const viewport = window.innerHeight;
    const height = document.documentElement.scrollHeight - viewport;
    progress.style.transform = `scaleX(${height > 0 ? Math.min(1,scrollY / height) : 0})`;
    if (reduced.matches) {
      hero.style.removeProperty('--hero-drift');field.style.removeProperty('--field-drift');return;
    }
    const heroRect = hero.getBoundingClientRect();
    if (heroRect.bottom > 0 && heroRect.top < viewport) {
      hero.style.setProperty('--hero-drift',`${Math.max(-50,Math.min(70,-heroRect.top * .12))}px`);
    }
    const fieldRect = field.getBoundingClientRect();
    if (fieldRect.bottom > 0 && fieldRect.top < viewport) {
      const offset = (viewport / 2 - fieldRect.top - fieldRect.height / 2) * .08;
      field.style.setProperty('--field-drift',`${Math.max(-45,Math.min(45,offset))}px`);
    }
  }
  function schedule() { if (!requested) requested = requestAnimationFrame(updateDepth); }
  window.addEventListener('scroll', schedule, {passive:true});
  window.addEventListener('resize', schedule, {passive:true});
  if ('ResizeObserver' in window) new ResizeObserver(schedule).observe(document.body);
  schedule();filmLabel();
})();

/* One view at a time: a deliberate, keyboard-friendly study of the featured jet. */
(() => {
  const choices = document.querySelector('.jet-detail-choices');
  const image = document.querySelector('#jet-detail-image');
  const detailLink = document.querySelector('.jet-detail-open');
  const status = document.querySelector('#jet-study-status');
  const labels = {
    cockpit:['Primer plano de la cabina del Ventage Jet','Close-up of the Ventage Jet canopy'],
    wing:['Ala y unión al fuselaje del Ventage Jet','Ventage Jet wing and its fuselage junction'],
    tail:['Deriva y estabilizadores del Ventage Jet','Ventage Jet fin and stabilizers']
  };
  let selected = 'cockpit', generation = 0;
  function localize() {
    const english = document.documentElement.lang === 'en';
    image.alt = labels[selected][english ? 1 : 0];
    choices.setAttribute('aria-label',english ? 'Jet detail views' : 'Detalles del jet');
  }
  choices.hidden = false;
  choices.querySelectorAll('button').forEach(button => button.addEventListener('click',async () => {
    const current = ++generation;
    const key = button.dataset.jetShot;
    if(key === selected) {choices.removeAttribute('aria-busy');status.textContent='';return;}
    const next = new Image();next.src = `assets/cinema/jet-${key}.webp`;
    choices.setAttribute('aria-busy','true');status.textContent = '';
    try {
      await next.decode();
      if(current !== generation) return;
      selected = key;image.src = next.src;
      detailLink.dataset.inspectDetail = key;
      document.querySelector('#jet-detail-index').textContent = `0${Object.keys(labels).indexOf(key)+1} / 03`;
      choices.querySelectorAll('button').forEach(item => item.setAttribute('aria-pressed',String(item === button)));
      localize();
      if(!matchMedia('(prefers-reduced-motion:reduce)').matches) image.animate([{opacity:.15,transform:'scale(1.025)'},{opacity:1,transform:'scale(1)'}],{duration:650,easing:'cubic-bezier(.2,.7,.2,1)'});
    } catch {
      if(current === generation) status.textContent = document.documentElement.lang === 'en' ? 'This detail could not load. Please try another view.' : 'No se pudo cargar este detalle. Prueba otra vista.';
    } finally { if(current === generation) choices.removeAttribute('aria-busy'); }
  }));
  document.addEventListener('openrc-language',localize);localize();
})();
