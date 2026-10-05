import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

import {
  Box3,
  BoxGeometry,
  Group,
  Mesh,
  MeshStandardMaterial,
  Object3D,
  Vector3,
} from '../../../prototypes/stage0/three/node_modules/three/build/three.module.js';
import { GLTFExporter } from '../../../prototypes/stage0/three/node_modules/three/examples/jsm/exporters/GLTFExporter.js';
import { GLTFLoader } from '../../../prototypes/stage0/three/node_modules/three/examples/jsm/loaders/GLTFLoader.js';

// Three's GLTFExporter expects the browser FileReader API. These models have no
// textures, so Blob's built-in byte readers are enough for a Node-only check.
class NodeFileReader {
  result = null;
  onloadend = null;

  readAsArrayBuffer(blob) {
    blob.arrayBuffer().then((result) => {
      this.result = result;
      this.onloadend?.();
    });
  }

  readAsDataURL(blob) {
    blob.arrayBuffer().then((result) => {
      this.result = `data:${blob.type};base64,${Buffer.from(result).toString('base64')}`;
      this.onloadend?.();
    });
  }
}

globalThis.FileReader = NodeFileReader;

const outputPath = resolve(dirname(fileURLToPath(import.meta.url)), 'hinge-roundtrip.glb');
const expectedSize = new Vector3(0.8, 0.02, 0.25);
const tolerance = 1e-5;

// A miniature elevator in glTF coordinates: −X right, +Y up, nose +Z, and
// the elevator trailing edge toward −Z from its hinge.
const airplane = new Group();
airplane.name = 'airplane';

const hinge = new Group();
hinge.name = 'elevator_hinge';
airplane.add(hinge);

const elevator = new Mesh(
  new BoxGeometry(expectedSize.x, expectedSize.y, expectedSize.z),
  new MeshStandardMaterial({ color: 0xcc3333, roughness: 0.8 }),
);
elevator.name = 'elevator';
elevator.position.z = -expectedSize.z / 2;
hinge.add(elevator);

const leadingEdgeProbe = new Object3D();
leadingEdgeProbe.name = 'elevator_hinge_probe';
hinge.add(leadingEdgeProbe);

const trailingEdgeProbe = new Object3D();
trailingEdgeProbe.name = 'elevator_trailing_probe';
trailingEdgeProbe.position.z = -expectedSize.z;
hinge.add(trailingEdgeProbe);

const noseProbe = new Object3D();
noseProbe.name = 'airplane_nose_probe';
noseProbe.position.z = 0.5;
airplane.add(noseProbe);

const rightProbe = new Object3D();
rightProbe.name = 'airplane_right_probe';
rightProbe.position.x = -0.4;
airplane.add(rightProbe);

const glb = await new GLTFExporter().parseAsync(airplane, { binary: true, trs: true });
writeFileSync(outputPath, Buffer.from(glb));

const loaded = await new GLTFLoader().parseAsync(glb, '');
const importedScene = loaded.scene;
const importedAirplane = importedScene.getObjectByName('airplane');
const importedHinge = importedScene.getObjectByName('elevator_hinge');
const importedElevator = importedScene.getObjectByName('elevator');
const importedLeadingProbe = importedScene.getObjectByName('elevator_hinge_probe');
const importedTrailingProbe = importedScene.getObjectByName('elevator_trailing_probe');
const importedNoseProbe = importedScene.getObjectByName('airplane_nose_probe');
const importedRightProbe = importedScene.getObjectByName('airplane_right_probe');

const requiredNodes = [
  importedAirplane,
  importedHinge,
  importedElevator,
  importedLeadingProbe,
  importedTrailingProbe,
  importedNoseProbe,
  importedRightProbe,
];
const missingNodes = requiredNodes.some((node) => node === undefined || node === null);
const names = new Map();
importedScene.traverse((node) => {
  if (node.name) names.set(node.name, (names.get(node.name) ?? 0) + 1);
});
const uniqueRequiredNames = requiredNodes.every((node) => node && names.get(node.name) === 1);
const hierarchyPreserved =
  importedHinge?.parent === importedAirplane && importedElevator?.parent === importedHinge;
const near = (a, b) => Math.abs(a - b) <= tolerance;

let measuredSize = null;
let hingeWorld = null;
let leadingWorld = null;
let trailingNeutralWorld = null;
let trailingUpWorld = null;
let sourceNoseWorld = null;
let sourceRightWorld = null;
let appNoseWorld = null;
let appRightWorld = null;
let sourceAxesPreserved = false;
let convertedAppAxesCorrect = false;

if (!missingNodes) {
  importedScene.updateMatrixWorld(true);
  sourceNoseWorld = importedNoseProbe.getWorldPosition(new Vector3()).toArray();
  sourceRightWorld = importedRightProbe.getWorldPosition(new Vector3()).toArray();
  sourceAxesPreserved = near(sourceNoseWorld[2], 0.5) && near(sourceRightWorld[0], -0.4);

  // glTF's canonical right/front vectors are -X/+Z. Rotate the imported model
  // root by 180° about +Y to match the simulator's +X-right/−Z-nose body frame.
  importedAirplane.rotation.y = Math.PI;
  importedScene.updateMatrixWorld(true);
  appNoseWorld = importedNoseProbe.getWorldPosition(new Vector3()).toArray();
  appRightWorld = importedRightProbe.getWorldPosition(new Vector3()).toArray();
  convertedAppAxesCorrect = near(appNoseWorld[2], -0.5) && near(appRightWorld[0], 0.4);

  const bounds = new Box3().setFromObject(importedElevator);
  measuredSize = bounds.getSize(new Vector3()).toArray();

  hingeWorld = importedHinge.getWorldPosition(new Vector3()).toArray();
  leadingWorld = importedLeadingProbe.getWorldPosition(new Vector3()).toArray();
  trailingNeutralWorld = importedTrailingProbe.getWorldPosition(new Vector3()).toArray();

  // In glTF coordinates the tail lies toward local −Z, so positive local X
  // raises the trailing edge. Root yaw then maps that motion to app axes.
  importedHinge.rotation.x = Math.PI / 6;
  importedScene.updateMatrixWorld(true);
  trailingUpWorld = importedTrailingProbe.getWorldPosition(new Vector3()).toArray();
}

const sizePreserved = measuredSize?.every((value, index) => near(value, expectedSize.toArray()[index])) ?? false;
const pivotAtLeadingEdge =
  hingeWorld?.every((value, index) => near(value, leadingWorld[index])) ?? false;
const positivePitchRaisesTrailingEdge =
  trailingUpWorld !== null && trailingNeutralWorld !== null &&
  trailingUpWorld[1] > trailingNeutralWorld[1] + tolerance;
const passed =
  !missingNodes && uniqueRequiredNames && hierarchyPreserved && sizePreserved &&
  sourceAxesPreserved && convertedAppAxesCorrect && pivotAtLeadingEdge && positivePitchRaisesTrailingEdge;

const result = {
  result: passed ? 'pass' : 'fail',
  tool: { three: '0.186.1', node: process.version },
  artifact: outputPath,
  artifactBytes: Buffer.byteLength(glb),
  sourceConvention: { nose: '+Z', right: '-X', up: '+Y' },
  conversionApplied: true,
  checks: {
    requiredNodesPresent: !missingNodes,
    requiredNamesUnique: uniqueRequiredNames,
    pivotHierarchyPreserved: hierarchyPreserved,
    dimensionsMeters: { expected: expectedSize.toArray(), afterImport: measuredSize, preserved: sizePreserved },
    coordinateAxes: {
      sourceNoseProbeWorld: sourceNoseWorld,
      sourceRightProbeWorld: sourceRightWorld,
      sourceAxesPreserved,
      convertedAppNoseProbeWorld: appNoseWorld,
      convertedAppRightProbeWorld: appRightWorld,
      conversion: 'R_y(pi): (x, y, z) -> (-x, y, -z)',
      appAxesCorrect: convertedAppAxesCorrect,
    },
    hingeAtLeadingEdge: { hingeWorld, leadingEdgeWorld: leadingWorld, preserved: pivotAtLeadingEdge },
    positivePitchRaisesElevatorTrailingEdge: {
      neutralWorld: trailingNeutralWorld,
      commandedWorld: trailingUpWorld,
      commandRotationAboutLocalXRad: Math.PI / 6,
      passed: positivePitchRaisesTrailingEdge,
    },
  },
};

console.log(JSON.stringify(result, null, 2));

if (!passed) {
  throw new Error('The GLB round-trip failed one or more pivot contract checks.');
}
