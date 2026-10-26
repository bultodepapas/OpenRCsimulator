const themeButton = document.querySelector('.theme-toggle');
let theme = 'day';
try {theme = localStorage.getItem('openrc-theme') === 'night' ? 'night' : 'day';} catch {}
function applyTheme() {
  document.documentElement.dataset.theme = theme;
  const night = theme === 'night';
  themeButton.firstElementChild.textContent = night ? '☀' : '☾';
  themeButton.setAttribute('aria-label', night ? siteText.themeDay : siteText.themeNight);
  document.querySelectorAll('img[src*="brands/"]:not(.partner-logo img):not(.allies-logos img)').forEach(img => {
    const source = img.getAttribute('src');
    const next = source.replace(night ? 'Black' : 'White', night ? 'White' : 'Black');
    if(source !== next) img.src = next;
  });
}
themeButton.hidden = false;
themeButton.addEventListener('click', () => {theme = theme === 'day' ? 'night' : 'day';applyTheme();try{localStorage.setItem('openrc-theme',theme);}catch{}});
document.addEventListener('openrc-language', applyTheme);
applyTheme();
