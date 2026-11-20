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
    title: 'OpenRC',
    documentElement: {lang: options.lang || 'en'},
    querySelectorAll: () => links,
    createElement: tag => ({tag, attributes: {}, siblings: [],
      setAttribute(name, value) { this.attributes[name] = value; },
      removeAttribute(name) { delete this.attributes[name]; },
      after(...elements) { this.siblings.push(...elements); },
      addEventListener(name, callback) { this[name] = callback; }}),
    getElementById: () => ({scrollIntoView() {}}),
    addEventListener: (name, callback) => listeners[name] = callback,
  };
  const hostname = options.hostname ?? 'bultodepapas.github.io';
  const context = {window, document, history, URL, URLSearchParams,
    location: {search, hostname, href: `https://${hostname}/OpenRCsimulator/en.html${search}`,
      assign: url => navigation.push(url)},
    setTimeout: (callback, delay) => { timers.set(callback, delay); return callback; },
    clearTimeout: id => timers.delete(id),
  };
  if (options.navigator) context.navigator = options.navigator;
  vm.runInNewContext(source, context);
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
    f.links[index].click();  // the same platform and release is not counted twice in one page load
    assert.equal(f.events().length, 1);
    const other = (index + 1) % 3;
    f.links[other].click();
    assert.equal(f.events().at(-1)[2].download_method, 'manual');
    assert.equal(f.events().length, 2);
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

test('non-production hosts download without sending analytics (WEB-18)', () => {
  for (const hostname of ['127.0.0.1', 'localhost', '']) {
    const f = fixture('?download=windows&release=v0.1.8', {hostname});
    f.expire();
    assert.deepEqual(f.navigation, [f.links[0].href], hostname);
    f.links[1].click();
    assert.equal(f.window.dataLayer.length, 0, hostname);
  }
});

test('one request per platform and release per page load (WEB-20)', () => {
  const f = fixture('');
  f.links[0].click(); f.links[0].click(); f.links[2].click();
  assert.deepEqual(JSON.parse(JSON.stringify(f.events().map(e => e[2].download_platform))), ['windows', 'macos']);
  const automatic = fixture();
  automatic.links[0].click();  // same platform and release as the automatic request
  assert.equal(automatic.events().length, 1);
});

const PHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1';
// Safari on a Mac and on iPadOS (desktop mode) share this agent; only touch points tell them apart.
const MACINTOSH = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15';
const settle = () => new Promise(resolve => setImmediate(resolve));
const plain = value => JSON.parse(JSON.stringify(value));

test('phones and tablets get a hand-off instead of a desktop ZIP (WEB-20)', async () => {
  for (const navigator of [{userAgent: PHONE}, {userAgent: MACINTOSH, maxTouchPoints: 5}, {userAgentData: {mobile: true}}]) {
    const shared = [];
    navigator.share = data => { shared.push(data); return Promise.resolve(); };
    const f = fixture('?download=windows&release=v0.1.8&utm_source=github&utm_campaign=readme&fbclid=abc',
      {navigator, lang: 'de'});
    f.expire();
    assert.equal(f.navigation.length, 0);
    assert.deepEqual(plain(f.events().map(e => [e[1], e[2].handoff_action, e[2].download_platform])),
      [['download_handoff', 'shown', 'windows']]);
    const [message] = f.inserted;
    assert.equal(message.attributes.role, undefined);  // plain text; the live region is separate
    const [button, live] = message.siblings;
    assert.equal(button.textContent, 'Link teilen');
    assert.equal(live.attributes.role, 'status');
    button.click(); button.click();
    await settle();
    const url = new URL(shared[0].url);
    assert.equal(url.searchParams.get('download'), 'windows');
    assert.equal(url.searchParams.get('utm_source'), 'handoff');
    for (const name of ['fbclid', 'utm_campaign']) assert.equal(url.searchParams.get(name), null);
    assert.deepEqual(plain(f.events().map(e => e[2].handoff_action)), ['shown', 'shared']);  // repeat taps once
    f.links[0].click();  // an explicit tap still downloads and is counted as manual
    assert.equal(f.events().at(-1)[2].download_method, 'manual');
  }
});

test('the hand-off copies when sharing is unavailable or refused, and counts "shown" once', async () => {
  const copied = [];
  const clipboard = {writeText: text => { copied.push(text); return Promise.resolve(); }};
  const f = fixture('?download=macos&release=v0.1.8', {navigator: {userAgent: PHONE, clipboard}});
  const [button, live] = f.inserted[0].siblings;
  assert.equal(button.textContent, 'Copy link');
  button.click();
  await settle();
  assert.equal(copied.length, 1);
  assert.equal(live.textContent, 'Link copied');
  assert.equal(button.textContent, 'Copy link');  // the focused button keeps its name
  const reload = fixture('?download=macos&release=v0.1.8', {navigator: {userAgent: PHONE, clipboard}, state: f.history.state});
  assert.equal(reload.events().length, 0);
  assert.equal(reload.inserted.length, 1);  // the message is still shown

  const refusing = {userAgent: PHONE, clipboard, share: () => Promise.reject(Object.assign(new Error('x'), {name: 'NotAllowedError'}))};
  const r = fixture('?download=macos&release=v0.1.8', {navigator: refusing});
  r.inserted[0].siblings[0].click();
  await settle(); await settle();
  assert.equal(r.events().at(-1)[2].handoff_action, 'copied');
  const cancelling = {userAgent: PHONE, clipboard, share: () => Promise.reject(Object.assign(new Error('x'), {name: 'AbortError'}))};
  const c = fixture('?download=macos&release=v0.1.8', {navigator: cancelling});
  c.inserted[0].siblings[0].click();
  await settle(); await settle();
  assert.deepEqual(plain(c.events().map(e => e[2].handoff_action)), ['shown']);  // the visitor cancelled

  const bare = fixture('?download=macos&release=v0.1.8', {navigator: {userAgent: PHONE}});
  assert.equal(bare.inserted[0].siblings.length, 0);  // no share or clipboard API: no dead button
});

test('handheld previews show the hand-off without analytics; unknown languages fall back to English', () => {
  const f = fixture('?download=linux&release=v0.1.8', {navigator: {userAgent: PHONE}, hostname: '127.0.0.1', lang: 'xx'});
  assert.equal(f.window.dataLayer.length, 0);
  assert.match(f.inserted[0].textContent, /^OpenRC runs on Windows, Linux and macOS computers/);
  const arabic = fixture('?download=linux&release=v0.1.8', {navigator: {userAgent: PHONE}, lang: 'ar'});
  assert.match(arabic.inserted[0].textContent, /^يعمل OpenRC/);
});

test('desktop Macs and Windows keep the automatic download', () => {
  for (const userAgent of [MACINTOSH, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0 Safari/537.36']) {
    const f = fixture('?download=macos&release=v0.1.8', {navigator: {userAgent, maxTouchPoints: 0}});
    f.expire();
    assert.deepEqual(f.navigation, [f.links[2].href]);
  }
});

test('a refused history update cannot block the download', () => {
  const f = fixture('?download=windows&release=v0.1.8');
  f.history.replaceState = () => { throw new Error('SecurityError'); };
  f.expire();
  assert.deepEqual(f.navigation, [f.links[0].href]);
});
test('leaving the page cancels a pending automatic download', () => {
  const f = fixture();
  f.listeners.pagehide(); f.expire(); f.events()[0][2].event_callback();
  assert.equal(f.navigation.length, 0);
});
