import {
  Color, DirectionalLight, HemisphereLight, Mesh, MeshLambertMaterial, PerspectiveCamera,
  PlaneGeometry, Scene, WebGLRenderer,
} from 'three';
import { buildAirplane } from './render/airplane';
import { attitudeToRender, nedToRender } from './render/frames';
import { poseAt } from './sim/scripted';
import { CAMERA, CAPTURE, COLORS, GROUND, RUNWAY, SUN } from './spec';

const params = new URLSearchParams(location.search);
const capture = params.has('capture');
// Inspection view: camera 4 m from the airplane, to check geometry the pilot view is too far to show.
const inspect = params.has('inspect');

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
camera.position.copy(nedToRender([0, 0, -CAMERA.eyeHeight]));

function resize(w: number, h: number) {
  renderer.setSize(w, h);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}

function renderAt(t: number) {
  const pose = poseAt(t);
  const pos = nedToRender(pose.ned);
  airplane.root.matrix.copy(attitudeToRender(pose.yaw, pose.pitch, pose.roll)).setPosition(pos);
  airplane.propeller.rotation.z = pose.prop;
  if (inspect) camera.position.copy(pos).add(nedToRender([-2.5, 2.5, -1.5]));
  camera.lookAt(pos);
  renderer.render(scene, camera);
}

if (capture) {
  resize(CAPTURE.width, CAPTURE.height);
  renderAt(Number(params.get('t') ?? CAPTURE.time));
  (window as unknown as { __captured: boolean }).__captured = true;
} else {
  resize(window.innerWidth, window.innerHeight);
  window.addEventListener('resize', () => resize(window.innerWidth, window.innerHeight));
  const t0 = performance.now();
  renderer.setAnimationLoop(() => renderAt((performance.now() - t0) / 1000));
}
