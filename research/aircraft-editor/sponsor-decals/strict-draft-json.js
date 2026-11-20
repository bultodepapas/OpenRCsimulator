// Study-only port of the bounded grammar guard in app/workshop/strict_json.gd
// at edd8a476. The production parser remains authoritative for Godot imports.
// Scan before JSON.parse so duplicate decoded keys cannot disappear on restore.
(function (root) {
  'use strict';
  function parseStudyJSON(text) {
    if (typeof text !== 'string' || !text.length || text.length > 65536 || new TextEncoder().encode(text).length > 65536) throw new Error('Draft JSON exceeds its byte limit or is empty');
    let offset = 0, nodes = 0;
    const fail = reason => { throw new Error(reason + ' at character ' + offset); };
    const peek = () => text[offset];
    const whitespace = () => { while (offset < text.length && ' \t\r\n'.includes(peek())) offset++; };
    function consume(token) { whitespace(); if (!text.startsWith(token, offset)) return false; offset += token.length; return true; }
    function hex4() {
      const token = text.slice(offset, offset + 4);
      if (!/^[0-9a-fA-F]{4}$/.test(token)) fail('Invalid Unicode escape');
      offset += 4; return parseInt(token, 16);
    }
    function stringToken() {
      const begin = offset++;
      while (offset < text.length) {
        const code = text.charCodeAt(offset++);
        if (code === 34) return JSON.parse(text.slice(begin, offset));
        if (code < 32) fail('Unescaped control character');
        if (code >= 0xd800 && code <= 0xdbff) {
          const low = text.charCodeAt(offset++);
          if (!(low >= 0xdc00 && low <= 0xdfff)) fail('Unpaired high surrogate');
          continue;
        }
        if (code >= 0xdc00 && code <= 0xdfff) fail('Unpaired low surrogate');
        if (code !== 92) continue;
        const escape = text[offset++];
        if (escape !== undefined && '"\\/bfnrt'.includes(escape)) continue;
        if (escape !== 'u') fail('Invalid string escape');
        const first = hex4();
        if (first >= 0xd800 && first <= 0xdbff) {
          if (text.slice(offset, offset + 2) !== '\\u') fail('Unpaired high surrogate');
          offset += 2; const second = hex4();
          if (second < 0xdc00 || second > 0xdfff) fail('Invalid surrogate pair');
        } else if (first >= 0xdc00 && first <= 0xdfff) fail('Unpaired low surrogate');
      }
      fail('Unterminated string');
    }
    function value(depth) {
      if (depth > 32 || ++nodes > 20000) fail('JSON nesting or node limit exceeded');
      whitespace();
      if (peek() === '{') {
        offset++; const keys = new Set(); if (consume('}')) return;
        while (true) {
          whitespace(); if (peek() !== '"') fail('Expected object key');
          const key = stringToken(); if (keys.has(key)) fail('Duplicate object key'); keys.add(key);
          if (!consume(':')) fail('Expected colon'); value(depth + 1);
          if (consume('}')) return; if (!consume(',')) fail('Expected comma or object end');
        }
      }
      if (peek() === '[') {
        offset++; if (consume(']')) return;
        while (true) { value(depth + 1); if (consume(']')) return; if (!consume(',')) fail('Expected comma or array end'); }
      }
      if (peek() === '"') { stringToken(); return; }
      for (const literal of ['true', 'false', 'null']) if (text.startsWith(literal, offset)) { offset += literal.length; return; }
      const token = text.slice(offset).match(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/);
      if (!token) fail('Expected JSON value');
      offset += token[0].length; const number = Number(token[0]);
      if (!Number.isFinite(number)) fail('Non-finite number');
      if (number === 0 && /[1-9]/.test(token[0].split(/[eE]/)[0])) fail('Nonzero number underflows to zero');
    }
    value(0); whitespace(); if (offset !== text.length) fail('Unexpected trailing data');
    return JSON.parse(text);
  }
  root.OPENRC_PARSE_STUDY_JSON = parseStudyJSON;
  if (typeof module !== 'undefined' && module.exports) module.exports = parseStudyJSON;
})(typeof window !== 'undefined' ? window : globalThis);
