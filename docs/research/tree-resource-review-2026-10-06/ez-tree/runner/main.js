import * as THREE from 'three';
import { Tree, TreePreset } from '@dgreenheck/ez-tree';

window.measureTreePresets = (presetNames) => presetNames.map((name) => {
  const options = structuredClone(TreePreset[name]);
  // Geometry is unchanged by bark texturing; leave it disabled for this count-only run.
  options.bark.textured = false;

  const tree = new Tree();
  tree.loadFromJson(options);

  const bounds = new THREE.Box3().setFromObject(tree);
  const size = bounds.getSize(new THREE.Vector3());
  const branchTriangles = tree.branchesMesh.geometry.index.count / 3;
  const leafTriangles = tree.leavesMesh.geometry.index.count / 3;

  return {
    preset: name,
    generator_units_bounds: {
      min: bounds.min.toArray(),
      max: bounds.max.toArray(),
      size: size.toArray(),
    },
    vertices: tree.vertexCount,
    branch_triangles: branchTriangles,
    leaf_triangles: leafTriangles,
    total_triangles: branchTriangles + leafTriangles,
  };
});

window.ezTreeMetricsReady = true;
