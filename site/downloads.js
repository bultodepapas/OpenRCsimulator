// README links arrive here before downloading; GTM owns the Google tag config.
(() => {
  const destination = 'G-4Z11DSB2BV';
  // WEB-18: only the published site reports to Analytics; downloads work on every host.
  const measured = location.hostname === 'bultodepapas.github.io';
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
    if (url.origin !== 'https://github.com' || !match || match[1].length > 160 || url.search || url.hash) continue;
    const platform = match[2].split('-')[0];
    links.set(platform, {link, release: match[1]});
  }

  window.dataLayer = window.dataLayer || [];
  // No second config/page_view: route events through the existing GTM tag.
  function gtag() { window.dataLayer.push(arguments); }
  const sent = new Set(); // WEB-20: one request per platform and release per page load
  function track(platform, item, method, callback) {
    const key = `${platform}:${item.release}`;
    if (!measured || sent.has(key)) return;
    sent.add(key);
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
  // [explanation, share, copy, copied]
  const handoff = {
    es: ['OpenRC funciona en ordenadores con Windows, Linux o macOS. Abre esta página en tu ordenador para descargarlo.',
      'Compartir enlace', 'Copiar enlace', 'Enlace copiado'],
    en: ['OpenRC runs on Windows, Linux and macOS computers. Open this page on your computer to download it.',
      'Share link', 'Copy link', 'Link copied'],
    pt: ['O OpenRC funciona em computadores com Windows, Linux ou macOS. Abra esta página no seu computador para baixá-lo.',
      'Compartilhar link', 'Copiar link', 'Link copiado'],
    'zh-Hans': ['OpenRC 运行于 Windows、Linux 和 macOS 电脑。请在电脑上打开此页面进行下载。',
      '分享链接', '复制链接', '链接已复制'],
    de: ['OpenRC läuft auf Computern mit Windows, Linux oder macOS. Öffne diese Seite auf deinem Computer, um es herunterzuladen.',
      'Link teilen', 'Link kopieren', 'Link kopiert'],
    ru: ['OpenRC работает на компьютерах с Windows, Linux и macOS. Откройте эту страницу на компьютере, чтобы скачать его.',
      'Поделиться ссылкой', 'Скопировать ссылку', 'Ссылка скопирована'],
    fr: ['OpenRC fonctionne sur les ordinateurs Windows, Linux et macOS. Ouvrez cette page sur votre ordinateur pour le télécharger.',
      'Partager le lien', 'Copier le lien', 'Lien copié'],
    it: ['OpenRC funziona su computer Windows, Linux e macOS. Apri questa pagina sul tuo computer per scaricarlo.',
      'Condividi link', 'Copia link', 'Link copiato'],
    ja: ['OpenRC は Windows、Linux、macOS のパソコンで動作します。ダウンロードするには、パソコンでこのページを開いてください。',
      'リンクを共有', 'リンクをコピー', 'リンクをコピーしました'],
    ko: ['OpenRC는 Windows, Linux, macOS 컴퓨터에서 실행됩니다. 컴퓨터에서 이 페이지를 열어 다운로드하세요.',
      '링크 공유', '링크 복사', '링크를 복사했습니다'],
    ar: ['يعمل OpenRC على أجهزة الكمبيوتر بنظام Windows وLinux وmacOS. افتح هذه الصفحة على جهاز الكمبيوتر لتنزيله.',
      'مشاركة الرابط', 'نسخ الرابط', 'تم نسخ الرابط'],
  };
  function handheld() {
    const nav = globalThis.navigator || {};
    if (nav.userAgentData?.mobile) return true;
    const agent = nav.userAgent || '';
    // iPadOS reports a Macintosh desktop agent; touch points distinguish it from a Mac.
    return /Android|iPhone|iPad|iPod|Mobile/i.test(agent) || (/Macintosh/.test(agent) && nav.maxTouchPoints > 1);
  }
  function handoffParams() {
    return {download_platform: requested, release_version: item.release, download_source: source};
  }
  const lang = document.documentElement.lang;
  const status = document.createElement('p');
  status.id = 'download-request-status';
  status.className = 'download-intro';
  status.setAttribute('role', 'status');

  // WEB-20: phones and tablets cannot run the simulator; offer the link for a computer instead of a ZIP.
  if (handheld()) {
    const text = handoff[lang] || handoff.en;
    status.removeAttribute?.('role');  // plain text: a live region inserted with content is rarely announced
    status.textContent = text[0];
    item.link.parentElement.before(status);
    const nav = globalThis.navigator || {};
    const canShare = typeof nav.share === 'function';
    const canCopy = typeof nav.clipboard?.writeText === 'function';
    if (canShare || canCopy) {
      const share = document.createElement('button');
      share.type = 'button';
      share.className = 'download-handoff';
      share.textContent = canShare ? text[1] : text[2];
      const live = document.createElement('span');  // empty until a copy succeeds, so it is announced
      live.className = 'download-handoff-status';
      live.setAttribute('role', 'status');
      const counted = new Set();
      const done = action => {
        if (action === 'copied') live.textContent = text[3];
        if (measured && !counted.has(action)) {
          counted.add(action);
          gtag('event', 'download_handoff', {send_to: destination, ...handoffParams(), handoff_action: action});
        }
      };
      const copy = href => canCopy && nav.clipboard.writeText(href).then(() => done('copied'), () => {});
      share.addEventListener('click', () => {
        // A shared link is a new visit: keep download/release, drop the README and ad-click attribution.
        const url = new URL(location.href);
        for (const name of [...url.searchParams.keys()]) {
          if (/^utm_|^(fbclid|gclid|msclkid|igshid|ttclid|twclid)$/.test(name)) url.searchParams.delete(name);
        }
        url.searchParams.set('utm_source', 'handoff');
        url.searchParams.set('utm_medium', 'share');
        if (canShare) {
          nav.share({title: document.title, url: url.href}).then(() => done('shared'),
            error => { if (error?.name !== 'AbortError') copy(url.href); });
        } else {
          copy(url.href);
        }
      });
      status.after(share, live);
    }
    document.getElementById('download').scrollIntoView({behavior: 'instant'});
    // Count the hand-off once per tab history entry, not on every reload.
    if (measured && history.state?.openrcHandoffShown !== key) {
      gtag('event', 'download_handoff', {send_to: destination, ...handoffParams(), handoff_action: 'shown'});
    }
    try { history.replaceState({...history.state, openrcHandoffShown: key}, ''); } catch (_) { /* rate-limited */ }
    return;
  }

  status.textContent = messages[lang] || messages.en;
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
    try { history.replaceState({...history.state, openrcDownloadStarted: key}, ''); } catch (_) { /* rate-limited */ }
    location.assign(item.link.href);
  };
  // Independent fallback: downloading must not depend on Google or an ad blocker.
  timer = setTimeout(start, 2000);
  track(requested, item, 'automatic', start);
})();
