// README links arrive here before downloading; GTM owns the Google tag config.
(() => {
  const destination = 'G-4Z11DSB2BV';
  const query = new URLSearchParams(location.search);
  const requested = query.get('download');
  const release = query.get('release');
  const source = query.get('utm_source') === 'github' && query.get('utm_campaign') === 'readme'
    ? 'github_readme' : 'website';
  const platforms = ['windows', 'linux', 'macos'];
  const links = new Map();
  for (const link of document.querySelectorAll('#download a[href]')) {
    const url = new URL(link.href);
    const match = url.pathname.match(/^\/bultodepapas\/OpenRCsimulator\/releases\/download\/(v\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?)\/openrc-simulator-\1-(windows-x86_64|linux-x86_64|macos-universal)\.zip$/);
    if (url.origin !== 'https://github.com' || !match || url.search || url.hash) continue;
    const platform = match[2].split('-')[0];
    links.set(platform, {link, release: match[1]});
  }

  window.dataLayer = window.dataLayer || [];
  function track(platform, item, method, callback) {
    // No second config/page_view: route the event through the existing GTM tag.
    function gtag() { window.dataLayer.push(arguments); }
    gtag('event', 'download_request', {
      send_to: destination,
      download_platform: platform,
      release_version: item.release,
      download_source: source,
      download_method: method,
      link_url: item.link.href,
      file_name: new URL(item.link.href).pathname.split('/').pop(),
      event_callback: callback || (() => {}),
      event_timeout: 1800,
    });
  }

  let pending = false;
  let timer;
  function cancel() { pending = false; clearTimeout(timer); }
  // A visitor's own navigation always wins over a pending automatic download.
  document.addEventListener('click', event => {
    if (event.target.closest('a, button')) cancel();
  }, true);
  window.addEventListener('pagehide', cancel);
  for (const [platform, item] of links) {
    item.link.addEventListener('click', () => track(platform, item, 'manual'));
  }

  if (!platforms.includes(requested)) return;
  const item = links.get(requested);
  if (!item || (release && release !== item.release)) return;
  const key = `${requested}:${item.release}`;
  if (history.state?.openrcDownloadStarted === key) return;

  const messages = {
    es: 'Tu descarga comenzará en breve. Si no se inicia, usa el botón seleccionado.',
    en: 'Your download will start shortly. If it does not, use the selected button.',
    pt: 'O download começará em breve. Se não começar, use o botão selecionado.',
    'zh-Hans': '下载即将开始。如果未开始，请使用选中的按钮。',
    de: 'Dein Download startet gleich. Falls nicht, nutze die ausgewählte Schaltfläche.',
    ru: 'Скачивание скоро начнётся. Если нет, нажмите выделенную кнопку.',
    fr: 'Votre téléchargement va commencer. Sinon, utilisez le bouton sélectionné.',
    it: 'Il download inizierà a breve. In caso contrario, usa il pulsante selezionato.',
    ja: 'ダウンロードがまもなく始まります。始まらない場合は、選択されたボタンを押してください。',
    ko: '곧 다운로드가 시작됩니다. 시작되지 않으면 선택된 버튼을 누르세요.',
    ar: 'سيبدأ التنزيل قريبًا. إذا لم يبدأ، فاستخدم الزر المحدد.',
  };
  const status = document.createElement('p');
  status.id = 'download-request-status';
  status.className = 'download-intro';
  status.setAttribute('role', 'status');
  status.textContent = messages[document.documentElement.lang] || messages.en;
  item.link.parentElement.before(status);
  item.link.style.outline = '3px solid currentColor';
  item.link.style.outlineOffset = '-3px';
  item.link.focus({preventScroll: true});
  document.getElementById('download').scrollIntoView({behavior: 'instant'});

  pending = true;
  const start = () => {
    if (!pending) return;
    cancel();
    // Retain attribution in the URL but do not restart on reload/back navigation.
    history.replaceState({...history.state, openrcDownloadStarted: key}, '');
    location.assign(item.link.href);
  };
  // Independent fallback: downloading must not depend on Google or an ad blocker.
  timer = setTimeout(start, 2000);
  track(requested, item, 'automatic', start);
})();
