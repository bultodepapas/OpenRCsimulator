// B4: known-answer checks for the NED/FRD -> render conversion and the scripted pose.
import { describe, expect, it } from 'vitest';
import { Vector3 } from 'three';
import { attitudeToRender, nedToRender } from '../src/render/frames';
import { poseAt } from '../src/sim/scripted';

const deg = Math.PI / 180;
const NOSE = new Vector3(0, 0, -1); // model forward
const RIGHT_WING = new Vector3(1, 0, 0); // model right
const close = (v: Vector3, x: number, y: number, z: number) => {
  expect(v.x).toBeCloseTo(x, 12);
  expect(v.y).toBeCloseTo(y, 12);
  expect(v.z).toBeCloseTo(z, 12);
};

describe('nedToRender', () => {
  it('maps north to -z, east to +x, down to -y', () => {
    close(nedToRender([1, 0, 0]), 0, 0, -1);
    close(nedToRender([0, 1, 0]), 1, 0, 0);
    close(nedToRender([0, 0, 1]), 0, -1, 0);
  });
});

describe('attitudeToRender', () => {
  it('heading 0: nose points north (-z)', () => {
    close(NOSE.clone().applyMatrix4(attitudeToRender(0, 0, 0)), 0, 0, -1);
  });
  it('heading 90°: nose points east (+x)', () => {
    close(NOSE.clone().applyMatrix4(attitudeToRender(90 * deg, 0, 0)), 1, 0, 0);
  });
  it('pitch up 30°: nose rises', () => {
    const n = NOSE.clone().applyMatrix4(attitudeToRender(0, 30 * deg, 0));
    close(n, 0, Math.sin(30 * deg), -Math.cos(30 * deg));
  });
  it('bank right 30°: right wing goes down', () => {
    const w = RIGHT_WING.clone().applyMatrix4(attitudeToRender(0, 0, 30 * deg));
    close(w, Math.cos(30 * deg), -Math.sin(30 * deg), 0);
  });
  it('is a proper rotation (determinant +1)', () => {
    expect(attitudeToRender(1.1, -0.4, 2.3).determinant()).toBeCloseTo(1, 12);
  });
});

describe('poseAt', () => {
  it('t = 0: 100 m north, 20 m up, flying east, banked right ≈ 29.84°', () => {
    const p = poseAt(0);
    expect(p.ned[0]).toBeCloseTo(100, 12);
    expect(p.ned[1]).toBeCloseTo(0, 12);
    expect(p.ned[2]).toBeCloseTo(-20, 12);
    expect(p.yaw).toBeCloseTo(90 * deg, 12);
    expect(p.roll / deg).toBeCloseTo(29.84, 2);
  });
  it('one lap later, the pose repeats', () => {
    const lap = (2 * Math.PI * 40) / 15;
    const a = poseAt(1.3);
    const b = poseAt(1.3 + lap);
    a.ned.forEach((v, i) => expect(b.ned[i]).toBeCloseTo(v, 9));
  });
});
