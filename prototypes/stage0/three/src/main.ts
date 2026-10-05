import {
  Color, DirectionalLight, HemisphereLight, Mesh, MeshLambertMaterial, PerspectiveCamera,
  PlaneGeometry, Scene, Vector3, WebGLRenderer,
} from 'three';
import { hingeRotations, neutralCommands, neutralRaw, propRevPerSec, stepCommands, type Commands } from './input/commands';
import { attachKeyboard, readRaw } from './input/keyboard';
import { applySurfaces, buildAirplane } from './render/airplane';
import { attitudeToRender, nedToRender } from './render/frames';
import { updatePanel } from './render/panel';
import { poseAt } from './sim/scripted';
import { CAMERA, CAPTURE, COLORS, GROUND, INSPECT_OFFSET, RUNWAY, SUN } from './spec';

const params = new URLSearchParams(location.search);
const capture = params.has('capture');
// Inspection view: camera fixed to the airplane, to check geometry the pilot view is too far to show.
let inspect = params.has('inspect');

const renderer = new WebGLRenderer({ antialias: true, preserveDrawingBuffer: capture });
renderer.setPixelRatio(capture ? 1 : window.devicePixelRatio);
document.body.appendChild(renderer.domElement);

const scene = new Scene();
scene.background = new Color(COLORS.sky);

const ground = new Mesh(new PlaneGeometry(GROUND.size, GROUND.size), new MeshLambertMaterial({ color: COLORS.grass }));
ground.rotation.x = -Math.PI / 2;
scene.add(ground);

const runway = new Mesh(
  new PlaneGeometry(RUNWAY.lengthEastWest, RUNWAY.widthNorthSouth),
  new MeshLambertMaterial({ color: COLORS.runway }),
);
runway.rotation.x = -Math.PI / 2;
runway.position.copy(nedToRender([RUNWAY.centerNorth, 0, -0.01]));
scene.add(runway);

scene.add(new HemisphereLight(COLORS.sky, COLORS.grass, 1.0));
const sun = new DirectionalLight(0xffffff, 2.0);
const az = (SUN.azimuthFromNorthDeg * Math.PI) / 180;
const el = (SUN.elevationDeg * Math.PI) / 180;
sun.position.copy(nedToRender([Math.cos(az) * Math.cos(el), Math.sin(az) * Math.cos(el), -Math.sin(el)]).multiplyScalar(100));
scene.add(sun);

const airplane = buildAirplane();
airplane.root.matrixAutoUpdate = false;
scene.add(airplane.root);

const camera = new PerspectiveCamera(CAMERA.fovDeg, 16 / 9, CAMERA.near, CAMERA.far);
const pilotEye = nedToRender([0, 0, -CAMERA.eyeHeight]);

function resize(w: number, h: number) {
  renderer.setSize(w, h);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}

function renderAt(t: number, c: Commands, propAngle: number) {
  const pose = poseAt(t);
  const pos = nedToRender(pose.ned);
  airplane.root.matrix.copy(attitudeToRender(pose.yaw, pose.pitch, pose.roll)).setPosition(pos);
  airplane.propeller.rotation.z = propAngle;
  applySurfaces(airplane, hingeRotations(c));
  if (inspect) camera.position.copy(new Vector3(...INSPECT_OFFSET).applyMatrix4(airplane.root.matrix));
  else camera.position.copy(pilotEye);
  camera.lookAt(pos);
  renderer.render(scene, camera);
}

if (capture) {
  // Settled commands from URL parameters (the limiter is skipped), so captures are deterministic.
  const num = (k: string, d: number) => Number(params.get(k) ?? d);
  const c: Commands = { roll: num('roll', 0), pitch: num('pitch', 0), yaw: num('yaw', 0), throttle: num('throttle', 0.5) };
  const t = num('t', CAPTURE.time);
  resize(CAPTURE.width, CAPTURE.height);
  updatePanel(neutralRaw(), c, inspect ? 'close-up' : 'pilot');
  renderAt(t, c, 2 * Math.PI * propRevPerSec(c) * t);
  (window as unknown as { __captured: boolean }).__captured = true;
} else {
  resize(window.innerWidth, window.innerHeight);
  window.addEventListener('resize', () => resize(window.innerWidth, window.innerHeight));
  let t = 0;
  let propAngle = 0;
  let c = neutralCommands();
  attachKeyboard({
    KeyR: () => { t = 0; c = neutralCommands(); },
    KeyC: () => { inspect = !inspect; },
  });
  let last = performance.now();
  renderer.setAnimationLoop((now: number) => {
    const dt = Math.min((now - last) / 1000, 0.1); // a stalled tab must not jump the controls
    last = now;
    const raw = readRaw();
    c = stepCommands(c, raw, dt);
    t += dt;
    propAngle += 2 * Math.PI * propRevPerSec(c) * dt;
    updatePanel(raw, c, inspect ? 'close-up' : 'pilot');
    renderAt(t, c, propAngle);
  });
}
