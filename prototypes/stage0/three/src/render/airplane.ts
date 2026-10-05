// Das Ugly Stik 60 blockout, built from SPEC.md part tables.
import { BoxGeometry, CylinderGeometry, Group, Mesh, MeshLambertMaterial, Object3D } from 'three';
import { BOXES, SURFACES, WHEELS, WINGS } from '../spec';

const mat = (color: number) => new MeshLambertMaterial({ color });

export interface Airplane {
  root: Group;
  propeller: Object3D;
  /** Hinge pivots, ready for Stage 1 deflections. */
  hinges: Record<string, Group>;
}

export function buildAirplane(): Airplane {
  const root = new Group();
  root.name = 'airplane';

  for (const p of BOXES) {
    const mesh = new Mesh(new BoxGeometry(...p.size), mat(p.color));
    mesh.name = p.name;
    mesh.position.set(...p.center);
    root.add(mesh);
  }

  // BoxGeometry face order: +x, -x, +y, -y, +z, -z.
  for (const w of WINGS) {
    const top = mat(w.top);
    const mesh = new Mesh(new BoxGeometry(...w.size), [top, top, top, mat(w.bottom), top, top]);
    mesh.name = w.name;
    mesh.position.set(...w.center);
    root.add(mesh);
  }

  const hinges: Record<string, Group> = {};
  for (const s of SURFACES) {
    const depth = s.size[2];
    const pivot = new Group();
    pivot.name = `${s.name}_hinge`;
    pivot.position.set(s.center[0], s.center[1], s.center[2] - depth / 2);
    const mesh = new Mesh(new BoxGeometry(...s.size), mat(s.color));
    mesh.name = s.name;
    mesh.position.set(0, 0, depth / 2);
    pivot.add(mesh);
    root.add(pivot);
    hinges[s.name] = pivot;
  }

  for (const w of WHEELS) {
    const r = w.diameter / 2;
    const mesh = new Mesh(new CylinderGeometry(r, r, w.width, 16), mat(w.color));
    mesh.name = w.name;
    mesh.rotation.z = Math.PI / 2; // cylinder axis along x (the axle)
    mesh.position.set(...w.center);
    root.add(mesh);
  }

  return { root, propeller: root.getObjectByName('propeller')!, hinges };
}
