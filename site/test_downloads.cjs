// Download dispatch must survive blocked analytics and reject untrusted targets.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(`${__dirname}/downloads.js`, 'utf8');

function fixture(search = '?download=windows&release=v0.1.8', options = {}) {
  const navigation = [], timers = new Map(), listeners = {}, inserted = [];
  const version = options.version || 'v0.1.8';
  const links = ['windows-x86_64', 'linux-x86_64', 'macos-universal'].map(platform => ({
    href: `https://github.com/bultodepapas/OpenRCsimulator/releases/download/${version}/openrc-simulator-${version}-${platform}.zip`,
    parentElement: {before: element => inserted.push(element)},
    style: {},
    focus() {},
    addEventListener(name, callback) { this[name] = callback; },
  }));
  if (options.untrusted) links[0].href = links[0].href.replace('https://github.com', 'https://example.com');
  if (options.windowsHref) links[0].href = options.windowsHref;
  const window = {addEventListener: (name, callback) => listeners[name] = callback};
  const history = {state: options.state || null, replaceState(state) { this.state = state; }};
  const document = {
    documentElement: {lang: 'en'},
    querySelectorAll: () => links,
    createElement: () => ({setAttribute() {}}),
    getElementById: () => ({scrollIntoView() {}}),
    addEventListener: (name, callback) => listeners[name] = callback,
  };
  vm.runInNewContext(source, {window, document, history, URL, URLSearchParams,
    location: {search, assign: url => navigation.push(url)},
    setTimeout: (callback, delay) => { timers.set(callback, delay); return callback; },
    clearTimeout: id => timers.delete(id),
  });
  return {window, history, navigation, timers, links, listeners, inserted,
    events: () => window.dataLayer.filter(e => e[0] === 'event'),
    expire: () => [...timers.keys()].forEach(callback => callback()),
  };
}

test('prerelease links dispatch all platforms and attribute manual clicks', () => {
  for (const [platform, index] of [['windows', 0], ['linux', 1], ['macos', 2]]) {
    const f = fixture(`?download=${platform}&release=v0.1.9-beta.1`, {version: 'v0.1.9-beta.1'});
    assert.equal(f.events()[0][2].release_version, 'v0.1.9-beta.1');
    f.expire();
    assert.deepEqual(f.navigation, [f.links[index].href]);
    f.links[index].click();
    assert.equal(f.events().at(-1)[2].download_method, 'manual');
  }
});

test('release tag length matches the manifest limit', () => {
  const prefix = 'v0.1.9-';
  const tag160 = prefix + 'a'.repeat(160 - prefix.length);
  const tag161 = tag160 + 'a';
  const accepted = fixture(`?download=windows&release=${tag160}`, {version: tag160});
  accepted.expire();
  assert.equal(accepted.events()[0][2].release_version, tag160);
  assert.deepEqual(accepted.navigation, [accepted.links[0].href]);

  const rejected = fixture(`?download=windows&release=${tag161}`, {version: tag161});
  rejected.expire();
  assert.equal(rejected.events().length, 0);
  assert.equal(rejected.navigation.length, 0);
  assert.equal(rejected.links[0].click, undefined);
});

test('prerelease destinations must have an approved origin, tag and matching asset', () => {
  const base = 'https://github.com/bultodepapas/OpenRCsimulator/releases/download/';
  for (const href of [
    base + 'v0.1.9-beta.1/openrc-simulator-v0.1.9-beta.2-windows-x86_64.zip',
    base + 'v0.1.9-beta..1/openrc-simulator-v0.1.9-beta..1-windows-x86_64.zip',
    base + 'v0.1.9-beta.1/openrc-simulator-v0.1.9-beta.1-windows-arm64.zip',
    base + 'v0.1.9-beta.1/openrc-simulator-v0.1.9-beta.1-windows-x86_64.zip?redirect=1',
    base.replace('github.com', 'example.com') + 'v0.1.9-beta.1/openrc-simulator-v0.1.9-beta.1-windows-x86_64.zip',
  ]) {
    const f = fixture('?download=windows&release=v0.1.9-beta.1', {windowsHref: href});
    f.expire();
    assert.equal(f.events().length, 0, href);
    assert.equal(f.navigation.length, 0, href);
  }
});

test('blocked analytics still downloads once; late callbacks cannot restart it', () => {
  const f = fixture('?download=windows&release=v0.1.8&utm_source=github&utm_campaign=readme');
  const event = f.events()[0];
  assert.equal(event[1], 'download_request');
  assert.equal(event[2].download_source, 'github_readme');
  assert.equal(event[2].download_platform, 'windows');
  assert.equal(event[2].download_method, 'automatic');
  assert.equal([...f.timers.values()][0], 2000);
  f.expire(); event[2].event_callback(); f.expire();
  assert.deepEqual(f.navigation, [f.links[0].href]);
  assert.equal(f.history.state.openrcDownloadStarted, 'windows:v0.1.8');
});

test('callback can start promptly and clears the independent timeout', () => {
  const f = fixture('?download=macos&release=v0.1.8');
  f.events()[0][2].event_callback();
  assert.deepEqual(f.navigation, [f.links[2].href]);
  assert.equal(f.timers.size, 0);
});

test('unknown platform, old release, untrusted URL and repeat history cannot auto-download', () => {
  for (const [query, options] of [
    ['?download=https://example.com', {}],
    ['?download=windows&release=v0.0.1', {}],
    ['?download=windows', {untrusted: true}],
    ['?download=windows', {state: {openrcDownloadStarted: 'windows:v0.1.8'}}],
    ['', {}],
  ]) {
    const f = fixture(query, options);
    f.expire();
    assert.equal(f.events().length, 0);
    assert.equal(f.navigation.length, 0);
    assert.equal(f.inserted.length, 0);
  }
});

test('manual navigation cancels the automatic request without blocking the link', () => {
  const f = fixture();
  f.listeners.click({target: {closest: () => f.links[1]}});
  f.links[1].click();
  f.expire(); f.events()[0][2].event_callback();
  assert.equal(f.navigation.length, 0);
  const manual = f.events().at(-1)[2];
  assert.equal(manual.download_platform, 'linux');
  assert.equal(manual.download_method, 'manual');
  assert.equal(manual.download_source, 'website');
});

test('leaving the page cancels a pending automatic download', () => {
  const f = fixture();
  f.listeners.pagehide(); f.expire(); f.events()[0][2].event_callback();
  assert.equal(f.navigation.length, 0);
});
