const language = document.documentElement.lang;
let currentAircraft = 'jet';
const aircraftOrder = [...document.querySelectorAll('[data-aircraft]')].map(button => button.dataset.aircraft);
let currentTime = 'day';
function renderAircraft() {
  const model = aircraft[currentAircraft];
  const localized = localeCopy.aircraft[currentAircraft];
  const image = document.querySelector('#aircraft-image');
  const source = `assets/turntables/${currentAircraft}-poster.webp`;
  if(image.getAttribute('src') !== source) image.src = source;
  image.alt = `${model.name.replace('<br>',' ')} — ${siteText.studioView}`;
  document.querySelector('#aircraft-name').innerHTML = model.name;
  document.querySelector('#aircraft-category').textContent = localized.category;
  document.querySelector('#aircraft-description').textContent = localized.description;
  document.querySelector('#aircraft-span').textContent = model.span;
  document.querySelector('[data-i18n="span"]').textContent = currentAircraft === 'heli' ? siteText.visualModel : siteText.wingspan;
  document.querySelector('[data-i18n="power"]').textContent = currentAircraft === 'heli' ? siteText.flightReference : siteText.powerplant;
  document.querySelector('#aircraft-power').textContent = model.power;
  document.querySelector('#aircraft-gear').textContent = localized.gear;
  document.querySelector('#aircraft-status').textContent = localized.status;
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
  image.alt = localeCopy.alts[image.dataset.alt];
  document.querySelector('#field-index').textContent = currentTime === 'day' ? '01 / 02' : '02 / 02';
  document.querySelectorAll('[data-time]').forEach(el => el.setAttribute('aria-pressed', String(el === button)));
  if (!matchMedia('(prefers-reduced-motion: reduce)').matches) image.animate([{opacity:.25},{opacity:1}],{duration:650,easing:'ease-out'});
}));
// Each locale has a static URL. Preserve section links when switching languages.
const languageMenu = document.querySelector('.language-menu');
function updateLanguageLinks() {
  document.querySelectorAll('[data-locale]').forEach(link => {
    const target = new URL(link.getAttribute('href'), location.href);
    target.hash = location.hash;
    link.href = target.href;
  });
}
window.addEventListener('hashchange', updateLanguageLinks);
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && languageMenu.open) {
    languageMenu.open = false;
    languageMenu.querySelector('summary').focus();
  }
});
document.addEventListener('click', event => {
  if (!languageMenu.contains(event.target)) languageMenu.open = false;
});
updateLanguageLinks();
renderAircraft();
document.dispatchEvent(new CustomEvent('openrc-language'));

if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {if(entry.isIntersecting) {entry.target.classList.add('is-visible');observer.unobserve(entry.target);}});
  }, {threshold:0.12});
  document.querySelectorAll('.reveal').forEach(el => {el.classList.add('reveal-ready');observer.observe(el);});
}
