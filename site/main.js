const translations = {
  releaseHighlights: 'Current source adds display and accessibility settings, P-51D flaps and retractable gear, and MONSTER CAR 2 nitro. These experimental features are not in the v0.1.1 download.',
  skip: 'Skip to content', navHangar: 'The hangar', navField: 'The field', navProject: 'The project', download: 'Download',
  heroEyebrow: 'MODEL AVIATION · OPEN SOURCE', renderNote: 'SIMULATOR MODEL · STUDIO VIEW',
  heroHeading: 'The flying field<br>is open.', heroCopy: 'Your transmitter. Your next flight.<br>An RC simulator we’re building in the open.', heroCta: 'Download',
  platforms: 'WINDOWS / LINUX / macOS', explore: 'EXPLORE THE PROJECT', free: 'FREE. FROM YOUR FIRST FLIGHT.',
  hangarKicker: '01 / THE HANGAR', hangarHeading: 'Every aircraft.<br>A different character.', hangarIntro: 'From a wooden classic to a jet.<br>Five fixed-wing aircraft in current source, each with its own configuration.',
  studio: 'AIRCRAFT STUDY / OPENRC', actualModel: 'ACTUAL PROJECT MODEL', span: 'Wingspan', power: 'Powerplant', gear: 'Landing gear', aircraftDetails: 'Explore the model',
  sourceNote: 'CURRENT SOURCE CATALOGUE. Models are experimental and still need measurements and pilot validation. The latest published download, v0.1.1, represents its own snapshot.',
  fieldKicker: '02 / SEE YOU AT THE FIELD', fieldHeading: 'That place<br>you always<br>come back to.', fieldCopy: 'The grass runway. The trees on the horizon.<br>Fly from the pilot’s position or follow your aircraft with the flight cameras.',
  capture: 'IN-SIMULATOR CAPTURE · GODOT', day: 'Day', night: 'Night',
  projectKicker: '03 / UNDER THE COWLING', projectHeading: 'Physics matters.<br>So does evidence.', projectIntro: 'We’re building an RC simulator one step at a time. With code you can read, flights you can repeat, and questions we’re still working through.', source: 'Explore the source', sourceKicker: 'IMPLEMENTED IN CURRENT SOURCE',
  physicsHeading: 'A flight solver of its own.', physicsCopy: 'Six degrees of freedom, calculated in float64. Local aerodynamic loads, servo dynamics and aircraft-specific propulsion.',
  radioHeading: 'Your controls, in the loop.', radioCopy: 'USB transmitter, gamepad or keyboard. Saved calibration, throttle arming and a disconnection failsafe.',
  replayHeading: 'Fly. Record. Compare.', replayCopy: 'Flight logs, exact replay and CSV export to study aircraft behavior with the same recorded inputs.',
  honesty: 'Software is checked. Realism must be demonstrated. Independent physical validation and pilot evaluation remain open.', roadmap: 'See what’s next',
  downloadKicker: '04 / YOUR NEXT TAKEOFF', downloadHeading: 'Less watching.<br>More flying.', downloadIntro: 'Download, extract the ZIP and launch.<br>No Godot installation needed.', downloadNote: 'Latest published release v0.1.1. Packages are unsigned.<br>Current-source features may not be included.', firstFlight: 'First-flight guide ↗', releaseNotes: 'Release notes ↗',
  candidateKicker: 'PRE-RELEASE CANDIDATE · IN PREPARATION', candidateTitle: 'v0.1.2-rc.1 / Candidate in preparation', candidateIntro: 'The candidate is not published yet. v0.1.1 remains the latest stable release and download.', candidateLimitsNote: 'These three physical acceptance checks are deferred for this prerelease; none counts as a pass.', candidateStikLimit: 'The Ugly Stik 15 m/s rudder doublet ends at 15.13°/s against the 15°/s limit.', candidateYawLimit: 'R02 yaw damping remains at 7.75% against the 7% limit.', candidateP51Limit: 'P-51D P51-22 powered takeoff and inside-loop acceptance remain pending.', candidateRelease: 'Candidate release page ↗',
  communityKicker: 'AN OPEN PROJECT. A SHARED EFFORT.', communityHeading: 'The next improvement<br>could start with you.', communityCopy: 'A test with your transmitter. A real measurement. A code improvement. Every contribution helps build the next flight.', contribute: 'Contribute on GitHub', feedback: 'Share your experience',
  thanks: 'With OpenAI’s support for development.<br>Thanks to Savox for permission to represent its products.', license: 'MIT CODE · ASSETS RETAIN THEIR OWN LICENSES', credits: 'Project imagery & credits ↗', backTop: 'Back to top ↑'
};

const aircraft = {
  stik: {name:'Jensen Das<br>Ugly Stik 60',image:'ugly-stik',span:'1.52 m',power:'.61 glow',guide:'UGLY-STIK-PLAN',category:['EL CLÁSICO','THE CLASSIC'],description:['Ala alta, líneas sencillas y toda la personalidad del aeromodelismo. El avión de referencia con el que empieza OpenRC.','A high wing, simple lines and the unmistakable character of model aviation. The reference aircraft at the heart of OpenRC.'],gear:['Triciclo','Tricycle'],status:['Referencia · en evaluación','Reference · under evaluation']},
  extra: {name:'Great Planes<br>Extra 300S .60',image:'extra-300s',span:'1.63 m',power:'.61 glow',guide:'EXTRA-300-PLAN',category:['ESPÍRITU ACROBÁTICO','AEROBATIC SPIRIT'],description:['Un ala baja acrobático con motor glow y tren de cola. Otra forma de explorar los mandos y el comportamiento en vuelo.','A low-wing aerobatic model with glow power and taildragger gear. A different way to explore the controls and flight behavior.'],gear:['Tren de cola','Taildragger']},
  mustang: {name:'P-51D Mustang<br>1/4',image:'p51d-mustang',span:'2.82 m',power:'120 cc',guide:'P51-PLAN',category:['PRESENCIA A ESCALA','SCALE PRESENCE'],description:['Mustang experimental de gasolina a escala 1/4. P51-22 sigue pendiente: el despegue y el looping con potencia no cumplen todavía los criterios de aceptación.','Experimental 1/4-scale gasoline Mustang. P51-22 remains pending: powered takeoff and loop behavior do not yet meet acceptance criteria.'],gear:['Tren de cola','Taildragger']},
  jet: {name:'Ventage<br>Jet',image:'avanti-s',span:'2.00 m',power:'JetCat P100-RX',guide:'AVANTI-S-PLAN',category:['OTRO RITMO','A DIFFERENT PACE'],description:['Propulsión por turbina y una silueta limpia. La configuración experimental comienza en el aire, con flaps y tren recogidos.','Turbine propulsion and a clean silhouette. This experimental configuration starts airborne, with flaps and landing gear retracted.'],gear:['Recogido al inicio','Retracted at start']},
  timber: {name:'Turbo Lumber<br>Evolution',image:'turbo-lumber-evolution',span:'1.55 m',power:'800 Kv / 4S',guide:'TIMBER-INTEGRATION-PLAN',category:['EL LADO ELÉCTRICO','THE ELECTRIC SIDE'],description:['Un ala alta eléctrico con ruedas fijas y sonido propio. Inicio en el aire o en pista, sin asistencias; su propulsión aún usa datos estimados.','An electric high-wing model with fixed wheels and its own sound. Airborne or runway starts, assists off; propulsion still uses estimated data.'],gear:['Ruedas fijas','Fixed wheels']}
};

Object.assign(translations, websiteCopy);
aircraft.heli = {name:'RC Helicopter<br>Research Trainer',image:'turntables/heli-poster',span:'HX-700',power:'X-Cell .60',guide:'HELICOPTER',category:['ALAS QUE GIRAN','ROTATING WINGS'],description:['Visual HX-700 y física de referencia X-Cell .60 SE. Un entrenador experimental con arranque en plataforma, vuelo estacionario y kit nocturno; no es un modelo HX-700 calibrado.','HX-700 visuals with X-Cell .60 SE reference physics. An experimental trainer with ground-pad startup, hover practice and a night kit; not a calibrated HX-700 flight model.'],gear:['Patines','Skids']};

const labels = {navigation:['Principal','Main navigation'],aircraftSelect:['Seleccionar avión','Select an aircraft'],fieldSwitch:['Iluminación del campo','Field lighting'],savoxPartner:['Savox, aliados','Savox, project partners']};
const alts = {heroAlt:['Ventage Jet naranja y violeta, render del modelo del simulador','Orange and violet Ventage Jet, a render of the simulator model'],fieldDayAlt:['Vista aérea del campo de vuelo de OpenRC, con pista de césped y zona de pilotos','Aerial view of the OpenRC flying field, grass runway and pilot area'],fieldNightAlt:['Umbral de la pista y club iluminados de noche en OpenRC','Illuminated runway threshold and club at night in OpenRC']};
alts.clubAlt = ['Club de aeromodelismo, boxes, pilotos y vehículos en OpenRC','OpenRC model flying club, pits, pilots and parked vehicles'];
alts.truckAlt = ['Render del modelo naranja Bisonte MT8 con suspensión y neumáticos todoterreno','Orange Bisonte MT8 model render with suspension and off-road tires'];
let language = 'es';
let currentAircraft = 'jet';
const aircraftOrder = [...document.querySelectorAll('[data-aircraft]')].map(button => button.dataset.aircraft);
let currentTime = 'day';
const languageButton = document.querySelector('.language');
const originalCopy = new Map([...document.querySelectorAll('[data-i18n]')].map(el => [el, el.innerHTML]));

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

function renderLanguage() {
  const index = language === 'es' ? 0 : 1;
  document.documentElement.lang = language;
  originalCopy.forEach((value, el) => {
    const copy = index ? translations[el.dataset.i18n] : value;
    if(el.innerHTML !== copy) el.innerHTML = copy;
  });
  document.querySelectorAll('[data-label]').forEach(el => el.setAttribute('aria-label',labels[el.dataset.label][index]));
  document.querySelectorAll('[data-alt]').forEach(el => {el.alt = alts[el.dataset.alt][index];});
  languageButton.textContent = index ? 'ES' : 'EN';
  languageButton.setAttribute('aria-label', index ? 'Cambiar a español' : 'Switch to English');
  document.title = index ? 'OpenRC Simulator — The flying field is open.' : 'OpenRC Simulator — El campo de vuelo está abierto.';
  document.querySelector('meta[property="og:title"]').content = document.title;
  const description = index ? 'An open-source RC simulator. Explore six aircraft in 360°, discover the simulation and download OpenRC for Windows, Linux and macOS.' : 'Un simulador RC de código abierto. Explora seis aeronaves en 360°, descubre la simulación y descarga OpenRC para Windows, Linux y macOS.';
  document.querySelector('meta[name="description"]').content = description;
  document.querySelector('meta[property="og:description"]').content = description;
  renderAircraft();
  document.dispatchEvent(new CustomEvent('openrc-language'));
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
languageButton.hidden = false;
languageButton.addEventListener('click', () => {
  language = language === 'es' ? 'en' : 'es';
  try {localStorage.setItem('openrc-language', language);} catch { /* Language works without storage. */ }
  renderLanguage();
});
try {if (localStorage.getItem('openrc-language') === 'en') language = 'en';} catch { /* Use Spanish by default. */ }
renderLanguage();

if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {if(entry.isIntersecting) {entry.target.classList.add('is-visible');observer.unobserve(entry.target);}});
  }, {threshold:0.12});
  document.querySelectorAll('.reveal').forEach(el => {el.classList.add('reveal-ready');observer.observe(el);});
}
