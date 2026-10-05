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

// A miniature elevator in the simulator's current local axes: +X right, +Y
// up, nose −Z, and the elevator trailing edge toward +Z from its hinge.
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
elevator.position.z = expectedSize.z / 2;
hinge.add(elevator);

const leadingEdgeProbe = new Object3D();
leadingEdgeProbe.name = 'elevator_hinge_probe';
hinge.add(leadingEdgeProbe);

const trailingEdgeProbe = new Object3D();
trailingEdgeProbe.name = 'elevator_trailing_probe';
trailingEdgeProbe.position.z = expectedSize.z;
hinge.add(trailingEdgeProbe);

const glb = await new GLTFExporter().parseAsync(airplane, { binary: true, trs: true });
writeFileSync(outputPath, Buffer.from(glb));

const loaded = await new GLTFLoader().parseAsync(glb, '');
const importedScene = loaded.scene;
const importedAirplane = importedScene.getObjectByName('airplane');
const importedHinge = importedScene.getObjectByName('elevator_hinge');
const importedElevator = importedScene.getObjectByName('elevator');
const importedLeadingProbe = importedScene.getObjectByName('elevator_hinge_probe');
const importedTrailingProbe = importedScene.getObjectByName('elevator_trailing_probe');

const requiredNodes = [
  importedAirplane,
  importedHinge,
  importedElevator,
  importedLeadingProbe,
  importedTrailingProbe,
];
const missingNodes = requiredNodes.some((node) => node === undefined || node === null);
const names = new Map();
importedScene.traverse((node) => {
  if (node.name) names.set(node.name, (names.get(node.name) ?? 0) + 1);
});
const uniqueRequiredNames = requiredNodes.every((node) => node && names.get(node.name) === 1);
const hierarchyPreserved =
  importedHinge?.parent === importedAirplane && importedElevator?.parent === importedHinge;

let measuredSize = null;
let hingeWorld = null;
let leadingWorld = null;
let trailingNeutralWorld = null;
let trailingUpWorld = null;

if (!missingNodes) {
  importedScene.updateMatrixWorld(true);
  const bounds = new Box3().setFromObject(importedElevator);
  measuredSize = bounds.getSize(new Vector3()).toArray();

  hingeWorld = importedHinge.getWorldPosition(new Vector3()).toArray();
  leadingWorld = importedLeadingProbe.getWorldPosition(new Vector3()).toArray();
  trailingNeutralWorld = importedTrailingProbe.getWorldPosition(new Vector3()).toArray();

  // Since the tail lies toward local +Z, a negative X rotation raises its
  // trailing edge. This is the positive-pitch elevator response in the
  // repository's current −Z-nose convention.
  importedHinge.rotation.x = -Math.PI / 6;
  importedScene.updateMatrixWorld(true);
  trailingUpWorld = importedTrailingProbe.getWorldPosition(new Vector3()).toArray();
}

const near = (a, b) => Math.abs(a - b) <= tolerance;
const sizePreserved = measuredSize?.every((value, index) => near(value, expectedSize.toArray()[index])) ?? false;
const pivotAtLeadingEdge =
  hingeWorld?.every((value, index) => near(value, leadingWorld[index])) ?? false;
const positivePitchRaisesTrailingEdge =
  trailingUpWorld !== null && trailingNeutralWorld !== null &&
  trailingUpWorld[1] > trailingNeutralWorld[1] + tolerance;

const result = {
  result: 'pass',
  tool: { three: '0.186.1', node: process.version },
  artifact: outputPath,
  artifactBytes: Buffer.byteLength(glb),
  sourceConvention: { nose: '-Z', right: '+X', up: '+Y' },
  conversionApplied: false,
  checks: {
    requiredNodesPresent: !missingNodes,
    requiredNamesUnique: uniqueRequiredNames,
    pivotHierarchyPreserved: hierarchyPreserved,
    dimensionsMeters: { expected: expectedSize.toArray(), afterImport: measuredSize, preserved: sizePreserved },
    hingeAtLeadingEdge: { hingeWorld, leadingEdgeWorld: leadingWorld, preserved: pivotAtLeadingEdge },
    positivePitchRaisesElevatorTrailingEdge: {
      neutralWorld: trailingNeutralWorld,
      commandedWorld: trailingUpWorld,
      commandRotationAboutLocalXRad: -Math.PI / 6,
      passed: positivePitchRaisesTrailingEdge,
    },
  },
};

console.log(JSON.stringify(result, null, 2));

if (
  missingNodes || !uniqueRequiredNames || !hierarchyPreserved || !sizePreserved ||
  !pivotAtLeadingEdge || !positivePitchRaisesTrailingEdge
) {
  throw new Error('The GLB round-trip failed one or more pivot contract checks.');
}
