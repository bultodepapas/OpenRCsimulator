// Raw input -> rate-limited commands -> surface hinge angles. Pure functions: no DOM, no clock, no three.
import { CIRCLE, CONTROLS } from '../spec';

export interface Raw { roll: number; pitch: number; yaw: number; throttle: number }
export interface Commands { roll: number; pitch: number; yaw: number; throttle: number }

export const neutralRaw = (): Raw => ({ roll: 0, pitch: 0, yaw: 0, throttle: 0 });
export const neutralCommands = (): Commands => ({ roll: 0, pitch: 0, yaw: 0, throttle: CONTROLS.throttleStart });

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

/** Move `value` toward `target` by at most `rate * dt`, never overshooting. */
export function rateLimit(value: number, target: number, rate: number, dt: number): number {
  const maxStep = rate * dt;
  return value + clamp(target - value, -maxStep, maxStep);
}

export function stepCommands(c: Commands, raw: Raw, dt: number): Commands {
  return {
    roll: rateLimit(c.roll, raw.roll, CONTROLS.rate, dt),
    pitch: rateLimit(c.pitch, raw.pitch, CONTROLS.rate, dt),
    yaw: rateLimit(c.yaw, raw.yaw, CONTROLS.rate, dt),
    throttle: clamp(c.throttle + raw.throttle * CONTROLS.throttleRate * dt, 0, 1),
  };
}

/** Trailing-edge deflections in degrees: positive = up (ailerons, elevator) or right (rudder). */
export function surfaceDeflectionsDeg(c: Commands) {
  const t = CONTROLS.maxThrowDeg;
  return {
    aileron_right: c.roll * t.aileron,
    aileron_left: -c.roll * t.aileron,
    elevator: c.pitch * t.elevator,
    rudder: c.yaw * t.rudder,
  };
}

/**
 * Hinge rotations in model axes (radians). Surfaces extend aft (+z) from the hinge.
 * About +x, the trailing edge goes up for a negative angle; about +y, it goes right (+x) for a positive angle.
 */
export function hingeRotations(c: Commands) {
  const d = surfaceDeflectionsDeg(c);
  const rad = Math.PI / 180;
  return {
    aileron_right: { x: -d.aileron_right * rad, y: 0 },
    aileron_left: { x: -d.aileron_left * rad, y: 0 },
    elevator: { x: -d.elevator * rad, y: 0 },
    rudder: { x: 0, y: d.rudder * rad },
  };
}

/** Propeller speed, rev/s: 10 at the starting throttle (visual only). */
export const propRevPerSec = (c: Commands) => CIRCLE.propRevPerSec * c.throttle * 2;
