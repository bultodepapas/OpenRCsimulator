'use strict';
const assert = require('assert');
const parse = require('./strict-draft-json.js');
let pass = 0;
function test(name, fn) { fn(); pass++; console.log('PASS ' + name); }
test('valid grammar matches the native decoded value', () => {
  for (const raw of ['null','true','false','0','-0.25e+2','"text\\nline"','{"a":[1,{},[],null],"b":false}', ' { "\\u0061": 1 }\n', '"\\ud83d\\ude80"', '"🚀"']) assert.deepStrictEqual(parse(raw), JSON.parse(raw));
});
test('duplicate keys are rejected at every depth after escape decoding', () => {
  for (const raw of ['{"rotation":45,"rotation":0}', '{"rotation":45,"\\u0072otation":0}', '{"x":{"a":1,"a":2}}', '[{"a":1,"a":2}]', '{"__proto__":1,"__proto__":2}']) assert.throws(() => parse(raw), /Duplicate object key/);
  assert.deepStrictEqual(parse('{"a":{"x":1},"b":{"x":2}}'), {a:{x:1},b:{x:2}});
});
test('invalid grammar trailing data and nonfinite numbers are rejected', () => {
  for (const raw of ['', ' ', '+1', '01', '1.', '1e', 'NaN', 'Infinity', '1e400', 'true false', '{"a":1,}', '[1,]', '{a:1}', '{"a" 1}', '"bad\\x"', '"line\nbreak"']) assert.throws(() => parse(raw));
});
test('both escaped and raw unpaired surrogates are rejected', () => {
  for (const raw of ['"\\ud800"','"\\udc00"','"\\ud800\\u0041"', '"'+String.fromCharCode(0xd800)+'"', '"'+String.fromCharCode(0xdc00)+'"']) assert.throws(() => parse(raw), /surrogate/i);
});
test('UTF8 byte limit includes multibyte content', () => {
  assert.strictEqual(parse('"'+'a'.repeat(65534)+'"').length, 65534);
  assert.throws(() => parse('"'+'é'.repeat(32768)+'"'), /byte limit/);
  assert.throws(() => parse(' '.repeat(65537)), /byte limit/);
});
test('nonzero numeric underflow cannot become an allowed zero rotation', () => {
  for (const raw of ['1e-400','-1e-400','0.000001e-400']) assert.throws(() => parse(raw), /underflows/);
  assert.strictEqual(parse('0e-400'),0);
  assert(Object.is(parse('-0e-400'),-0));
  assert.strictEqual(parse('1e-323'),JSON.parse('1e-323'));
});
test('depth and node bounds prevent oversized grammar traversals', () => {
  assert.doesNotThrow(() => parse('['.repeat(32)+'0'+']'.repeat(32)));
  assert.throws(() => parse('['.repeat(33)+'0'+']'.repeat(33)), /nesting/);
  assert.doesNotThrow(() => parse('['+Array(19999).fill('0').join(',')+']'));
  assert.throws(() => parse('['+Array(20000).fill('0').join(',')+']'), /node limit/);
});
console.log('Strict draft JSON results: ' + pass + ' passed, 0 failed.');
