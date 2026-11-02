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
// Offer a language route only on the Spanish landing URL. The URL and any
// explicit choice remain authoritative; do not redirect a shared link.
const languageChoiceKey = 'openrc-language-choice';
const languageDismissedKey = 'openrc-language-suggestion-dismissed';
function preferredSiteLocale(preferences) {
  const supported = new Set(['es','en','pt','de','ru','fr','it','ja','ko','ar']);
  for (const preference of preferences) {
    const tag = String(preference).toLowerCase().replaceAll('_','-');
    if (tag === 'zh-hans' || tag.startsWith('zh-hans-') || /^zh-(cn|sg)(-|$)/.test(tag)) return 'zh-Hans';
    const base = tag.split('-')[0];
    if (supported.has(base)) return base;
  }
  return null;
}
document.querySelectorAll('[data-locale]').forEach(link => link.addEventListener('click', () => {
  try { localStorage.setItem(languageChoiceKey, link.dataset.locale); } catch {}
}));
function offerLanguage() {
  if (language !== 'es' || location.search) return;
  if (!/(?:\/|\/index\.html)$/.test(location.pathname)) return;
  try {
    if (localStorage.getItem(languageChoiceKey) || localStorage.getItem(languageDismissedKey)) return;
  } catch {}
  const preferred = preferredSiteLocale(navigator.languages?.length ? navigator.languages : [navigator.language]);
  if (!preferred || preferred === 'es') return;
  const route = document.querySelector(`.language-options [data-locale="${preferred}"]`);
  if (!route) return;
  const notice = document.createElement('aside');
  notice.className = 'language-suggestion';
  notice.setAttribute('aria-label', siteText.languageMenu);
  const symbol = document.createElement('span');
  symbol.textContent = '🌐';
  symbol.setAttribute('aria-hidden', 'true');
  const link = document.createElement('a');
  link.href = route.href;
  link.lang = preferred;
  link.dir = preferred === 'ar' ? 'rtl' : 'auto';
  link.textContent = `${route.textContent.trim()} →`;
  link.addEventListener('click', () => {
    // The visitor may have changed sections since this notice was created.
    link.href = route.href;
    try { localStorage.setItem(languageChoiceKey, preferred); } catch {}
  });
  window.addEventListener('hashchange', () => { link.href = route.href; });
  const dismiss = document.createElement('button');
  dismiss.type = 'button';
  dismiss.textContent = '×';
  dismiss.setAttribute('aria-label', 'Cerrar sugerencia de idioma');
  dismiss.addEventListener('click', () => {
    try { localStorage.setItem(languageDismissedKey, '1'); } catch {}
    notice.remove();
  });
  notice.append(symbol, link, dismiss);
  document.body.append(notice);
}
offerLanguage();
renderAircraft();
document.dispatchEvent(new CustomEvent('openrc-language'));

if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {if(entry.isIntersecting) {entry.target.classList.add('is-visible');observer.unobserve(entry.target);}});
  }, {threshold:0.12});
  document.querySelectorAll('.reveal').forEach(el => {el.classList.add('reveal-ready');observer.observe(el);});
}
