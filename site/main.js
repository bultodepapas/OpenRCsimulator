const language = document.documentElement.lang;
let currentAircraft = 'jet';
const aircraftOrder = [...document.querySelectorAll('[data-aircraft]')].map(button => button.dataset.aircraft);
let currentTime = 'day';
function renderAircraft() {
  const model = aircraft[currentAircraft];
  const index = language === 'es' ? 0 : 1;
  const image = document.querySelector('#aircraft-image');
  const source = `assets/turntables/${currentAircraft}-poster.webp`;
  if(image.getAttribute('src') !== source) image.src = source;
  image.alt = `${model.name.replace('<br>',' ')} — ${index ? 'studio view' : 'vista de estudio'}`;
  document.querySelector('#aircraft-name').innerHTML = model.name;
  document.querySelector('#aircraft-category').textContent = model.category[index];
  document.querySelector('#aircraft-description').textContent = model.description[index];
  document.querySelector('#aircraft-span').textContent = model.span;
  document.querySelector('[data-i18n="span"]').textContent = currentAircraft === 'heli' ? (index ? 'Visual model' : 'Modelo visual') : (index ? 'Wingspan' : 'Envergadura');
  document.querySelector('[data-i18n="power"]').textContent = currentAircraft === 'heli' ? (index ? 'Flight reference' : 'Referencia de vuelo') : (index ? 'Powerplant' : 'Propulsión');
  document.querySelector('#aircraft-power').textContent = model.power;
  document.querySelector('#aircraft-gear').textContent = model.gear[index];
  document.querySelector('#aircraft-status').textContent = model.status?.[index] ?? (index ? 'Experimental' : 'Experimental');
  document.querySelector('#aircraft-link').href = `https://github.com/bultodepapas/OpenRCsimulator/blob/main/docs/${model.guide}.md`;
  document.querySelector('#aircraft-number').textContent = `0${aircraftOrder.indexOf(currentAircraft)+1} / 06`;
  document.querySelectorAll('[data-aircraft]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.aircraft === currentAircraft)));
  window.OpenRCViewer?.select(currentAircraft,model.name.replace('<br>',' '));
}

document.querySelectorAll('[data-aircraft]').forEach(button => button.addEventListener('click', () => {
  currentAircraft = button.dataset.aircraft;
  renderAircraft();
}));
let fieldRequest = 0;
document.querySelectorAll('[data-time]').forEach(button => button.addEventListener('click', async () => {
  const nextTime = button.dataset.time;
  const request = ++fieldRequest;
  if (nextTime === currentTime) return;
  const next = new Image();
  next.src = `assets/field-${nextTime}.webp`;
  try { await next.decode(); } catch { return; }
  if (request !== fieldRequest) return;
  currentTime = nextTime;
  const image = document.querySelector('#field-image');
  image.src = next.src;
  image.dataset.alt = currentTime === 'day' ? 'fieldDayAlt' : 'fieldNightAlt';
  image.alt = alts[image.dataset.alt][language === 'es' ? 0 : 1];
  document.querySelector('#field-index').textContent = currentTime === 'day' ? '01 / 02' : '02 / 02';
  document.querySelectorAll('[data-time]').forEach(el => el.setAttribute('aria-pressed', String(el === button)));
  if (!matchMedia('(prefers-reduced-motion: reduce)').matches) image.animate([{opacity:.25},{opacity:1}],{duration:650,easing:'ease-out'});
}));
// Each locale has a static URL. Preserve section links when switching languages.
const languageLink = document.querySelector('.language');
function updateLanguageLink() {
  const target = new URL(languageLink.getAttribute('href'), location.href);
  target.hash = location.hash;
  languageLink.href = target.href;
}
window.addEventListener('hashchange', updateLanguageLink);
updateLanguageLink();
renderAircraft();
document.dispatchEvent(new CustomEvent('openrc-language'));

if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {if(entry.isIntersecting) {entry.target.classList.add('is-visible');observer.unobserve(entry.target);}});
  }, {threshold:0.12});
  document.querySelectorAll('.reveal').forEach(el => {el.classList.add('reveal-ready');observer.observe(el);});
}
