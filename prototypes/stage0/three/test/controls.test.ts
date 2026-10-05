// B5: rate limiter, throttle, and surface signs on the real airplane objects.
import { describe, expect, it } from 'vitest';
import { Vector3 } from 'three';
import { hingeRotations, neutralCommands, rateLimit, stepCommands, type Commands } from '../src/input/commands';
import { applySurfaces, buildAirplane } from '../src/render/airplane';
import { SURFACES } from '../src/spec';

const raw = (r: Partial<Record<'roll' | 'pitch' | 'yaw' | 'throttle', number>>) =>
  ({ roll: 0, pitch: 0, yaw: 0, throttle: 0, ...r });

describe('rate limiter', () => {
  it('reaches 0.5 after 0.125 s from 0 toward +1', () => {
    expect(rateLimit(0, 1, 4, 0.125)).toBeCloseTo(0.5, 12);
  });
  it('reaches the target exactly, never overshoots', () => {
    let v = 0;
    for (let i = 0; i < 100; i++) v = rateLimit(v, 1, 4, 1 / 60);
    expect(v).toBe(1);
    expect(rateLimit(0.99, 1, 4, 1)).toBe(1);
  });
  it('re-centers when the key is released', () => {
    let c: Commands = { ...neutralCommands(), roll: 1 };
    c = stepCommands(c, raw({}), 0.25);
    expect(c.roll).toBeCloseTo(0, 12);
  });
});

describe('throttle', () => {
  it('holds its value with no key', () => {
    expect(stepCommands(neutralCommands(), raw({}), 10).throttle).toBe(0.5);
  });
  it('clamps to 0..1', () => {
    expect(stepCommands(neutralCommands(), raw({ throttle: 1 }), 10).throttle).toBe(1);
    expect(stepCommands(neutralCommands(), raw({ throttle: -1 }), 10).throttle).toBe(0);
  });
});

describe('surface signs on the real airplane', () => {
  const depth = (name: string) => SURFACES.find((s) => s.name === name)!.size[2];
  // Trailing edge relative to the hinge, in model axes.
  function trailingEdge(c: Commands, name: string): Vector3 {
    const a = buildAirplane();
    applySurfaces(a, hingeRotations(c));
    a.root.updateMatrixWorld(true);
    const hinge = a.hinges[name];
    const mesh = hinge.children[0];
    const te = mesh.localToWorld(new Vector3(0, 0, depth(name) / 2));
    return te.sub(hinge.getWorldPosition(new Vector3()));
  }
  const full = { ...neutralCommands(), roll: 1, pitch: 1, yaw: 1 };

  it('neutral: every trailing edge is straight aft', () => {
    for (const s of SURFACES) {
      const te = trailingEdge(neutralCommands(), s.name);
      expect(te.x).toBeCloseTo(0, 12);
      expect(te.y).toBeCloseTo(0, 12);
    }
  });
  it('roll right: right aileron TE up 20°, left aileron TE down', () => {
    const r = trailingEdge(full, 'aileron_right');
    const l = trailingEdge(full, 'aileron_left');
    expect(r.y).toBeGreaterThan(0);
    expect(l.y).toBeLessThan(0);
    expect(Math.atan2(r.y, r.z) * 180 / Math.PI).toBeCloseTo(20, 9);
  });
  it('pitch up: elevator TE up', () => {
    expect(trailingEdge(full, 'elevator').y).toBeGreaterThan(0);
  });
  it('yaw right: rudder TE toward +x, 25°', () => {
    const te = trailingEdge(full, 'rudder');
    expect(te.x).toBeGreaterThan(0);
    expect(Math.atan2(te.x, te.z) * 180 / Math.PI).toBeCloseTo(25, 9);
  });
});
