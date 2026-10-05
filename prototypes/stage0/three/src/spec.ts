// Every number from ../../SPEC.md lives here, once.

export const G = 9.80665;

export const CIRCLE = {
  centerNorth: 60,
  centerEast: 0,
  altitude: 20,
  radius: 40,
  speed: 15,
  propRevPerSec: 10,
};

export const COLORS = {
  white: 0xf2f2f2,
  darkGrey: 0x333333,
  yellow: 0xffcc00,
  darkBlue: 0x1a2a6c,
  red: 0xd01c1c,
  black: 0x111111,
  grass: 0x4a7a32,
  runway: 0x6f9a4a,
  sky: 0x9cc9ef,
};

type Vec3 = [number, number, number];
export interface BoxPart { name: string; size: Vec3; center: Vec3; color: number }
export interface WheelPart { name: string; diameter: number; width: number; center: Vec3; color: number }

// Model axes: +x right, +y up, -z forward. Origin near the CG.
export const BOXES: BoxPart[] = [
  { name: 'fuselage', size: [0.14, 0.16, 1.2], center: [0, 0, 0.1], color: COLORS.white },
  { name: 'cowl', size: [0.13, 0.14, 0.12], center: [0, 0, -0.56], color: COLORS.darkGrey },
  { name: 'stab', size: [0.6, 0.02, 0.14], center: [0, 0.02, 0.61], color: COLORS.yellow },
  { name: 'fin', size: [0.02, 0.18, 0.16], center: [0, 0.12, 0.62], color: COLORS.yellow },
  { name: 'propeller', size: [0.305, 0.025, 0.01], center: [0, 0, -0.63], color: COLORS.black },
];

// The wing gets a different color underneath, for orientation.
export const WING = {
  name: 'wing', size: [1.676, 0.04, 0.27] as Vec3, center: [0, 0.1, -0.03] as Vec3,
  top: COLORS.yellow, bottom: COLORS.darkBlue,
};

// Control surfaces pivot on their leading edge (hinge line).
export const SURFACES: BoxPart[] = [
  { name: 'aileron_left', size: [0.6, 0.02, 0.08], center: [-0.5, 0.1, 0.145], color: COLORS.red },
  { name: 'aileron_right', size: [0.6, 0.02, 0.08], center: [0.5, 0.1, 0.145], color: COLORS.red },
  { name: 'elevator', size: [0.6, 0.02, 0.07], center: [0, 0.02, 0.715], color: COLORS.red },
  { name: 'rudder', size: [0.02, 0.2, 0.07], center: [0, 0.13, 0.735], color: COLORS.red },
];

export const WHEELS: WheelPart[] = [
  { name: 'gear_left', diameter: 0.09, width: 0.03, center: [-0.18, -0.22, -0.28], color: COLORS.black },
  { name: 'gear_right', diameter: 0.09, width: 0.03, center: [0.18, -0.22, -0.28], color: COLORS.black },
  { name: 'tailwheel', diameter: 0.04, width: 0.015, center: [0, -0.1, 0.68], color: COLORS.black },
];

export const GROUND = { size: 2000 };
export const RUNWAY = { lengthEastWest: 100, widthNorthSouth: 12, centerNorth: 15 };

export const SUN = { azimuthFromNorthDeg: 225, elevationDeg: 45 }; // south-west

export const CAMERA = { eyeHeight: 1.7, fovDeg: 50, near: 0.1, far: 3000 };

export const CAPTURE = { time: 3.0, width: 1280, height: 720 };
