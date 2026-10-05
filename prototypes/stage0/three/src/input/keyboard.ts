// Keyboard adapter: keys -> raw targets (Mode 2 layout). The only input file that touches the DOM.
import type { Raw } from './commands';

const held = new Set<string>();
const axis = (minus: string, plus: string) => (held.has(plus) ? 1 : 0) - (held.has(minus) ? 1 : 0);
const CAPTURED = new Set(['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'KeyA', 'KeyD', 'KeyW', 'KeyS']);

export function attachKeyboard(actions: Record<string, () => void>) {
  window.addEventListener('keydown', (e) => {
    if (CAPTURED.has(e.code)) e.preventDefault();
    if (!e.repeat && actions[e.code]) actions[e.code]();
    held.add(e.code);
  });
  window.addEventListener('keyup', (e) => held.delete(e.code));
  window.addEventListener('blur', () => held.clear()); // never keep a key "held" after focus loss
}

export function readRaw(): Raw {
  return {
    roll: axis('ArrowLeft', 'ArrowRight'),
    pitch: axis('ArrowUp', 'ArrowDown'), // ArrowDown = stick back = nose up
    yaw: axis('KeyA', 'KeyD'),
    throttle: axis('KeyS', 'KeyW'),
  };
}
