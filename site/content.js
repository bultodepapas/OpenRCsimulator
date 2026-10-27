// Shared website copy and catalogue data. Used by build_locales.py and the browser.
const websiteCopy = {
  exploreJet:'Explore the jet',jetStudyKicker:'VANTAGE / A CLOSER LOOK',jetStudyHeading:'VANTAGE.<br>Up close.',jetStudyIntro:'Canopy, wing and empennage. Three views of the model that you can explore in 3D.',jetCockpit:'Canopy',jetWing:'Wing',jetTail:'Empennage',jetOverview:'Overview',jetStudyCta:'Explore this detail in 3D',jetStudyNote:'PROJECT MODEL · STUDIO RENDER',jetDetailsLabel:'DETAIL VIEWS',
  inspectCta:'Closer. Explore in 3D.',inspectSub:'Orbit freely, change the view and discover the details.',inspectKicker:'THE HANGAR / 3D STUDIO',inspectClose:'Close',inspectAircraft:'Aircraft',viewPerspective:'Perspective',viewSide:'Side',viewTop:'Top',inspectHelp:'Drag to orbit · Scroll or pinch to zoom · Arrow keys to rotate',inspectNote:'PROJECT MODEL · VISUALIZATION, NOT FLIGHT',
  helicopterTab:'Helicopter',
  navPartners:'Partners', supportedBy:'SUPPORTED BY', supportKicker:'THE SUPPORT BEHIND THE PROJECT', mainSponsor:'PRINCIPAL SPONSOR',
  supportHeading:'Thank you for supporting<br>what we build in the open.', supportCopy:'OpenAI supports this project with a ChatGPT Pro subscription. That support gives us more room to research, build and share OpenRC with the model aviation community.', supportLink:'Thank you, OpenAI ↗',
  supportProducts:'Ideas to explore.<br>Code to share.', chatgptRole:'Support for open-source development', codexRole:'AI development contributor', alongside:'ALSO ALONG FOR THE FLIGHT', savoxEarly:'Thank you, Savox, for welcoming your products into the project.',
  hangarHeading:'Every aircraft.<br>A different character.',hangarIntro:'Five airplanes and an experimental helicopter.<br>Choose a model and explore it from every angle.', actualModel:'RENDERS OF THE PROJECT MODEL',
  spinPlay:'Rotate', spinAngle:'Camera angle', spinHint:'Drag to explore · Use the slider to change the angle.',stikVariants:'ALSO IN THE STIK: MAX-61FX · MAX-55AX · FS-64V. Three experimental two- and four-stroke glow installations.',
  fieldKicker:'03 / SEE YOU AT THE FIELD',projectKicker:'04 / UNDER THE COWLING',downloadKicker:'02 / YOUR NEXT TAKEOFF',
  systemsKicker:'ANATOMY OF THE SIMULATION',systemsHeading:'From a movement of the stick<br>to the response of the aircraft.',systemsIntro:'Explore the systems already in the source. Each area links to its documentation and current limits.',
  aeroTitle:'Aerodynamics and flight dynamics',aeroBody:'A custom six-degree-of-freedom solver with RK4 integration at 240 Hz and float64 state. Local wing and tail loads, trim, stalls, spins and control-surface dynamics.',aeroDetail1:'Downwash, pitch damping and propeller wake where configured.',aeroDetail2:'Optional wing and tail ground effect, declared for the Stik.',aeroDetail3:'A dedicated helicopter session for the fuselage, rotor, rotor inflow and controls.',architectureLink:'Simulator architecture ↗',
  propTitle:'Four ways to make power',propBody:'Two- and four-stroke glow engines, gasoline, electric propulsion and a spooling turbine. Torque, gyroscopic effects, P-factor and propwash depend on each aircraft’s modules.',propDetail1:'Experimental glow installations: finite fuel, mixture and tank feed.',propDetail2:'Coupled motor, ESC and battery models; LUMBER uses a prescribed 4S bus without depletion.',propDetail3:'Estimated and borrowed parameters are documented as such.',glowLink:'Glow engines and limits ↗',electricLink:'Electric propulsion ↗',
  groundTitle:'Flight starts on the ground, too',groundBody:'Individual wheel rotation, suspension, steering, rolling resistance and tire slip. Maintained grass and rough ground have different surface profiles.',groundDetail1:'Experimental runway starts for the Stik and LUMBER.',groundDetail2:'Skid contacts and ground-pad startup for the helicopter.',groundDetail3:'Simplified scenery collision models, wreckage, marks and effects; physical calibration remains open.',groundLink:'Ground contact model ↗',
  airTitle:'Air, light and flying conditions',airBody:'Uniform wind, repeating gusts and seeded turbulence. Configurable elevation, temperature, QNH pressure and humidity for the physical atmosphere.',airDetail1:'Dawn, day, dusk, night and passing evening; editable date, time and location.',airDetail2:'Clouds, rain and lightning are visual effects; they do not apply spatially varying storm forces.',airDetail3:'Field lights, stars, moonlight and the helicopter’s night kit.',airLink:'Atmosphere ↗',lightLink:'Time and lighting ↗',
  controlTitle:'Transmitters, instruments and practice',controlBody:'USB transmitter, gamepad and keyboard, with calibration, arming and failsafe. Aircraft-specific rates and expo for keyboard and gamepad; radios retain their own settings.',controlDetail1:'Pilot, chase, orbit and close-up cameras, with manual or automatic zoom.',controlDetail2:'Independent flight data, sticks, trims, wind, telemetry and diagnostic panels.',controlDetail3:'Aircraft Workshop variants, repeatable randomized conditions and optional emergency practice.',controlsLink:'Controls and first flight ↗',workshopLink:'Aircraft Workshop ↗',
  worldTitle:'A field you can see and hear',worldBody:'Grass, trees, a lake, club buildings, vehicles, people and birds. Positional engine, propeller, wind, foliage and wildlife sound, with motion-dependent Doppler.',worldDetail1:'Glow exhaust and optional smoke drifting with the wind.',worldDetail2:'Impact effects, debris and visual damage persist until restart.',worldDetail3:'Water does not simulate buoyancy; in-flight aircraft structural failure is not implemented.',worldLink:'World and scenery ↗',audioLink:'Audio ↗',
  evidenceTitle:'Sourced data. Repeatable flights.',evidenceBody:'The openrc-aircraft v2 contract requires units, evidence type and source. Invalid configurations cannot fly. Geometry and physical data are regenerated from their sources.',evidenceDetail1:'F10 records fixed-wing flights; F11 marks maneuvers. CSV export and comparisons use the same input tape.',evidenceDetail2:'Regression tests, golden flights, captures and export checks.',evidenceDetail3:'Software equivalence does not demonstrate physical realism: measurements and pilots are needed.',contractLink:'Aircraft data contract ↗',logLink:'Flight logging and replay ↗',
  inventoryKicker:'05 / THE OPENRC WORLD',inventoryHeading:'Much more<br>than a runway.',inventoryIntro:'Models, scenery, sounds and instruments. Original and freely available resources with their sources and licenses.',
  clubKicker:'THE FIELD / GODOT CAPTURE',clubHeading:'A small world of model aviation.',clubCopy:'Clubhouse, pits, parked aircraft, vehicles, people, trees and a lake. Vegetation and materials from free sources, with credits preserved.',assetCredits:'Explore assets and credits ↗',
  truckKicker:'ALSO ON WHEELS / MODEL RENDER',truckCopy:'Two experimental RC vehicles in current source: a garage, driving course, suspension and separate physics. Bisonte is shown here; Monster Car 2 extends the activity with nitro propulsion.',truckLink:'Explore the RC vehicle activity ↗',
  assetModels:'Models and geometry',assetModelsSub:'Sources, generators and articulation',assetAudio:'The soundscape',assetAudioSub:'Engines, wind, foliage and wildlife',assetInstruments:'Flight instrumentation',assetInstrumentsSub:'Telemetry, sticks, warnings and diagnostics',
  partnersKicker:'06 / PROJECT PARTNERS',partnersHeading:'Support moves<br>the controls, too.',partnersIntro:'Thank you to the people who make room for an open project to keep growing.',savoxRole:'PARTNER / RC SERVOS',savoxCopy:'Savox has authorized us to include representations of its products in OpenRC Simulator. Thank you for supporting the project and connecting RC hardware with open simulation.',savoxStatus:'Servo catalogue selection is planned. This support does not establish validation of our physical models.',savoxLink:'Explore the planned integration ↗',
  developmentKicker:'07 / DEVELOPMENT IN THE OPEN',developmentHeading:'A project moving forward.<br>Without skipping the questions.',devAvailable:'AVAILABLE',devAvailableTitle:'Download and fly.',devAvailableCopy:'Stable desktop software release. Its notes describe exactly what the package contains.',devDownload:'Go to downloads ↑',devActive:'IN DEVELOPMENT',devActiveTitle:'Test and refine.',devActiveCopy:'Experimental aircraft, engines, ground, controls, helicopter and RC vehicles. Current source keeps evolving.',devChanges:'Project changes ↗',devOpen:'STILL TO DEMONSTRATE',devOpenTitle:'Measure in the real world.',devOpenCopy:'Mass, center of gravity, inertia, propulsion, maneuvers and pilot evaluation. The next step needs evidence.',devRoadmap:'Roadmap and acceptance gates ↗',droneNote:'IN RESEARCH: FPV racing. A flyable drone and race mode are not yet available.'
};

Object.assign(websiteCopy, {
  "savoxEarly": "Thanks to the manufacturers and community members helping OpenRC grow.",
  "partnersIntro": "Thank you to the manufacturers who have authorized representations of their products.",
  "savoxCopy": "Savox authorizes representations of its products. Thank you for opening the catalogue to simulation and offering an engineering contact.",
  "savoxStatus": "Servo catalogue selection is planned.",
  "sonicmodellRole": "PARTNER / FPV AIRCRAFT",
  "sonicmodellCopy": "SonicModell authorizes the appearance, names and branding of the models covered by our request, including Skyhunter models.",
  "sonicmodellStatus": "Permission is limited to the agreed use. Integration is pending.",
  "hitecRole": "PARTNER / RC SERVOS",
  "hitecCopy": "Hitec authorizes OpenRC Simulator to feature servos published on its websites, with references and official product links.",
  "hitecStatus": "Integration is pending. This permission does not announce radio compatibility.",
  "partnerVisit": "Visit the manufacturer ↗",
  "partnersNote": "Permissions have specific scopes. They do not imply financial sponsorship or validation of our physical models.",
  "partnerMoreTitle": "More participating brands",
  "flywingLogoScope": "Exterior model permission; integration pending.",
  "revocLogoScope": "Community support with approved logo and link.",
  "flywingScope": "Aircraft names and simplified exterior models; integration pending.",
  "gemfanScope": "Propeller names and simplified 3D representations; integration pending.",
  "kontronikScope": "Recreated propulsion products and name; integration pending.",
  "leomotionScope": "Selected products; renders require approval before publication.",
  "communityThanks": "Aloft Hobbies shared the project on its forum and offered knowledge and feedback."
});

Object.assign(websiteCopy, {alongside:'MANUFACTURERS ALONG FOR THE FLIGHT', alliesCopy:'Real products.<br> New possibilities in the simulator.', alliesLink:'Meet our partners ↗'});

const translations = {
  releaseHighlights: 'v0.1.8 adds the experimental F4U Corsair, a Scene detail setting, 3D field trees and far woods, and an optional High graphics profile. Flight behavior still needs real-world evaluation.',
  skip: 'Skip to content', navHangar: 'The hangar', navField: 'The field', navProject: 'The project', download: 'Download',
  heroEyebrow: 'MODEL AVIATION · OPEN SOURCE', renderNote: 'SIMULATOR MODEL · STUDIO VIEW',
  heroHeading: 'The flying field<br>is open.', heroCopy: 'A free, open-source RC flight simulator.<br>For Windows, Linux and macOS. Early alpha.', heroCta: 'Download',
  platforms: 'WINDOWS / LINUX / macOS', explore: 'EXPLORE THE PROJECT', free: 'FREE. FROM YOUR FIRST FLIGHT.',
  hangarKicker: '01 / THE HANGAR', hangarHeading: 'Every aircraft.<br>A different character.', hangarIntro: 'From a wooden classic to a jet.<br>Five fixed-wing aircraft in current source, each with its own configuration.',
  studio: 'AIRCRAFT SHOWCASE / OPENRC', actualModel: 'PROJECT MODEL RENDERS', span: 'Wingspan', power: 'Powerplant', gear: 'Landing gear', aircraftDetails: 'Explore the model',
  sourceNote: 'CURRENT SOURCE CATALOGUE. Models are experimental and still need measurements and pilot evaluation. The v0.1.8 download is its own snapshot and may differ from current source.',
  fieldKicker: '02 / SEE YOU AT THE FIELD', fieldHeading: 'That place<br>you always<br>come back to.', fieldCopy: 'The grass runway. The trees on the horizon.<br>Fly from the pilot’s position or follow your aircraft with the flight cameras.',
  capture: 'IN-SIMULATOR CAPTURE · GODOT', day: 'Day', night: 'Night',
  projectKicker: '03 / UNDER THE COWLING', projectHeading: 'Physics matters.<br>So does evidence.', projectIntro: 'We’re building an RC simulator one step at a time. With code you can read, flights you can repeat, and questions we’re still working through.', source: 'Explore the source', sourceKicker: 'IMPLEMENTED IN CURRENT SOURCE',
  physicsHeading: 'A flight solver of its own.', physicsCopy: 'Six degrees of freedom, calculated in float64. Local aerodynamic loads, servo dynamics and aircraft-specific propulsion.',
  radioHeading: 'Your controls, in the loop.', radioCopy: 'USB transmitter, gamepad or keyboard. Saved calibration, throttle arming and a disconnection failsafe.',
  replayHeading: 'Fly. Record. Compare.', replayCopy: 'Flight logs, exact replay and CSV export to study aircraft behavior with the same recorded inputs.',
  honesty: 'Software is checked. Realism must be demonstrated. Independent physical validation and pilot evaluation remain open.', roadmap: 'See what’s next',
  downloadKicker: '02 / YOUR NEXT TAKEOFF', downloadHeading: 'Less watching.<br>More flying.', downloadIntro: 'Download, extract the ZIP and launch.<br>No Godot installation needed.', downloadNote: 'Stable software release v0.1.8. The ZIPs have no installer or archive signature; the macOS app is ad-hoc signed but not notarized.<br>Aircraft and ground-vehicle models remain experimental and need independent measurements and pilot evaluation.', firstFlight: 'First-flight guide ↗', releaseNotes: 'Release notes ↗',
  gameLanguages: 'The simulator interface in current source is available in nine languages: <bdi dir="ltr">English · Español · 简体中文 · Português (Brasil) · Deutsch · Français · Italiano · Русский · 日本語</bdi>. The v0.1.8 download offers English and Spanish.',
  candidateKicker: 'LATEST STABLE SOFTWARE RELEASE · v0.1.8', candidateTitle: 'v0.1.8 is available', candidateIntro: 'Download v0.1.8 for Windows, Linux or macOS. This stable software release is an early-alpha simulator; aircraft and ground-vehicle models remain experimental.', candidateLimitsNote: 'Independent evaluation of some experimental aircraft remains open:', candidateStikLimit: 'The Stik’s 240 Hz sideslip-limit check remains open; it is an estimated boundary check.', candidateYawLimit: 'The R02 yaw-damping comparison remains open; its model comparison is not a physical measurement.', candidateRelease: 'v0.1.8 release notes ↗',
  communityKicker: 'AN OPEN PROJECT. A SHARED EFFORT.', communityHeading: 'The next improvement<br>could start with you.', communityCopy: 'A test with your transmitter. A real measurement. A code improvement. Every contribution helps build the next flight.', contribute: 'Contribute on GitHub', feedback: 'Share your experience',
  thanks: 'With OpenAI’s support for development.<br>Thanks to the participating manufacturers and RC community.', license: 'MIT CODE · ASSETS RETAIN THEIR OWN LICENSES', credits: 'Project imagery & credits ↗', sitemap: 'Sitemap', backTop: 'Back to top ↑'
};

const aircraft = {
  stik: {name:'Jensen Das<br>Ugly Stik 60',span:'1.52 m',power:'.61 glow',guide:'UGLY-STIK-PLAN',category:['EL CLÁSICO','THE CLASSIC'],description:['Ala alta, líneas sencillas y toda la personalidad del aeromodelismo. El avión de referencia con el que empieza OpenRC.','A high wing, simple lines and the unmistakable character of model aviation. The reference aircraft at the heart of OpenRC.'],gear:['Triciclo','Tricycle'],status:['Referencia · en evaluación','Reference · under evaluation']},
  extra: {name:'Great Planes<br>Extra 300S .60',span:'1.63 m',power:'.61 glow',guide:'EXTRA-300-PLAN',category:['ESPÍRITU ACROBÁTICO','AEROBATIC SPIRIT'],description:['Un ala baja acrobático con motor glow y tren de cola. Otra forma de explorar los mandos y el comportamiento en vuelo.','A low-wing aerobatic model with glow power and taildragger gear. A different way to explore the controls and flight behavior.'],gear:['Tren de cola','Taildragger']},
  mustang: {name:'P-51D Mustang<br>1/4',span:'2.82 m',power:'120 cc',guide:'P51-PLAN',category:['PRESENCIA A ESCALA','SCALE PRESENCE'],description:['Mustang experimental de gasolina a escala 1/4. Las comprobaciones de software no demuestran la precisión física del modelo.','Experimental 1/4-scale gasoline Mustang. Software checks do not establish physical accuracy.'],gear:['Tren de cola','Taildragger']},
  jet: {name:'VANTAGE',span:'2.00 m',power:'JetCat P100-RX',guide:'AVANTI-S-PLAN',category:['OTRO RITMO','A DIFFERENT PACE'],description:['Propulsión por turbina y una silueta limpia. La configuración experimental comienza en el aire, con flaps y tren recogidos.','Turbine propulsion and a clean silhouette. This experimental configuration starts airborne, with flaps and landing gear retracted.'],gear:['Recogido al inicio','Retracted at start']},
  timber: {name:'LUMBER',span:'1.55 m',power:'800 Kv / 4S',guide:'TIMBER-INTEGRATION-PLAN',category:['EL LADO ELÉCTRICO','THE ELECTRIC SIDE'],description:['Un ala alta eléctrico con ruedas fijas y sonido propio. Inicio en el aire o en pista, sin asistencias; su propulsión aún usa datos estimados.','An electric high-wing model with fixed wheels and its own sound. Airborne or runway starts, assists off; propulsion still uses estimated data.'],gear:['Ruedas fijas','Fixed wheels']}
};

Object.assign(translations, websiteCopy);
aircraft.heli = {name:'RC Helicopter<br>Research Trainer',span:'HX-700',power:'X-Cell .60',guide:'HELICOPTER',category:['ALAS QUE GIRAN','ROTATING WINGS'],description:['Visual HX-700 y física de referencia X-Cell .60 SE. Un entrenador experimental con arranque en plataforma, vuelo estacionario y kit nocturno; no es un modelo HX-700 calibrado.','HX-700 visuals with X-Cell .60 SE reference physics. An experimental trainer with ground-pad startup, hover practice and a night kit; not a calibrated HX-700 flight model.'],gear:['Patines','Skids']};

const labels = {navigation:['Principal','Main navigation'],aircraftSelect:['Seleccionar avión','Select an aircraft'],fieldSwitch:['Iluminación del campo','Field lighting'],savoxPartner:['Savox, aliados','Savox, project partners']};
const alts = {heroAlt:['VANTAGE naranja y violeta, render del modelo del simulador','Orange and violet VANTAGE, a render of the simulator model'],fieldDayAlt:['Vista aérea del campo de vuelo de OpenRC, con pista de césped y zona de pilotos','Aerial view of the OpenRC flying field, grass runway and pilot area'],fieldNightAlt:['Umbral de la pista y club iluminados de noche en OpenRC','Illuminated runway threshold and club at night in OpenRC']};
alts.clubAlt = ['Club de aeromodelismo, boxes, pilotos y vehículos en OpenRC','OpenRC model flying club, pits, pilots and parked vehicles'];
alts.truckAlt = ['Render del modelo naranja Bisonte MT8 con suspensión y neumáticos todoterreno','Orange Bisonte MT8 model render with suspension and off-road tires'];

const englishMetadata = {
  title: 'OpenRC Simulator | Free Open-Source RC Flight Simulator',
  description: 'Download OpenRC Simulator, a free, open-source RC flight simulator for Windows, Linux and macOS. Explore model aviation in an early-alpha desktop simulator.'
};
Object.assign(translations, {
  noScriptCatalogue: 'Explore the <a href="https://github.com/bultodepapas/OpenRCsimulator#aircraft">full aircraft catalogue on GitHub</a>.',
  filmPause: 'Pause scene', modelLoading: 'Loading model…',
  faqLink: 'Frequently asked questions', faqKicker: 'BEFORE YOUR FIRST FLIGHT',
  faqHeading: 'RC flight simulator:<br>your questions, answered.',
  faqFreeQuestion: 'Is OpenRC Simulator free?',
  faqFreeAnswer: 'Yes. OpenRC Simulator is free to download, and its source code is available under the MIT license. Aircraft, scenery and other assets retain their own licenses. You can inspect the code, report issues or contribute on <a href="https://github.com/bultodepapas/OpenRCsimulator">GitHub</a>.',
  faqInstallQuestion: 'How do I install it on Windows, Linux or macOS?',
  faqInstallAnswer: 'Download the ZIP for your operating system, extract it and launch the application. You do not need to install Godot. Compare the archive checksum with SHA256SUMS from the same release, and read the platform instructions and signing limitations in the <a href="https://github.com/bultodepapas/OpenRCsimulator/blob/main/docs/FIRST-LAUNCH.md">first-launch guide</a>. <a href="#download">Choose your download</a>.',
  faqControlsQuestion: 'Do I need an RC transmitter to fly?',
  faqControlsAnswer: 'No. You can use a keyboard or a gamepad. USB transmitters can be used as flight controls when the operating system detects them as a compatible joystick; axis setup and calibration may be required. Support is not guaranteed for every radio or adapter. See the <a href="https://github.com/bultodepapas/OpenRCsimulator/blob/main/docs/FIRST-LAUNCH.md">controls and calibration guide</a>.',
  faqBrowserQuestion: 'Can I fly in the browser?',
  faqBrowserAnswer: 'OpenRC is a desktop simulator. This website shows aircraft turntables and an optional 3D model viewer; these are previews, not playable flights. <a href="#download">Download the desktop app</a> to fly.',
  faqRealismQuestion: 'How realistic is the flight simulation?',
  faqRealismAnswer: 'OpenRC has its own flight solver and experimental aircraft models. Software tests and repeatable flight logs help detect regressions, but do not establish physical accuracy. Independent measurements and pilot evaluation remain necessary. Read the <a href="https://github.com/bultodepapas/OpenRCsimulator/blob/main/ROADMAP.md">validation roadmap</a> and the notes for the aircraft you choose.'
});

// Static accessible names not already covered by data-label/data-alt.
const englishAttributes = {
  'Activar modo noche': 'Switch to night theme',
  'VANTAGE, vista de estudio': 'VANTAGE, studio view',
  'Vista 360 del avión seleccionado': '360-degree view of the selected aircraft',
  'Primer plano de la cabina del VANTAGE': 'Close-up of the VANTAGE canopy',
  'Detalles del jet': 'Jet details', 'Vistas de cámara': 'Camera views',
  'Acercar': 'Zoom in', 'Alejar': 'Zoom out'
};

// A complete, page-specific dictionary is embedded at build time; no locale fetch.
const localeCopy = typeof document === "undefined" ? null : JSON.parse(document.querySelector("#locale-data").textContent);
const siteText = localeCopy?.ui;
