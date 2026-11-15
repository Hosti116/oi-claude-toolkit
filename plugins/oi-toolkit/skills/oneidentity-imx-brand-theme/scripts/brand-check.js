// Brand theme checks for the Web Portal (skill oneidentity-imx-brand-theme, verification.md).
// Inject the whole file with the Chrome javascript tool, then call window.__brandCheck.scan() / go() / tour().
// Read-only: it only reads the page, except go()/tour() which switch the hash route and the body theme class.
(() => {
  const OOB = /rgba?\((10, 150, 209|1, 107, 145|0, 78, 107|138, 203, 227|227, 106, 0)[,)]/;
  // Low-contrast texts of the standard One Identity theme itself (grey subtitles, decorative "no data" icon,
  // disabled controls, empty-state titles such as "No Shared Statistics"): reported by the standard theme too, not
  // caused by the brand theme.
  const STANDARD_LOW = /rgb\((145, 151, 153|170, 176, 179|196, 202, 204|223, 228, 230)\)|rgba\(47, 50, 51, 0\.38\)/;
  const BRAND_CSS = /\/[a-z0-9-]+-(light|dark)-theme\.css(\?|$)/;

  const parse = (c) => {
    const m = c.match(/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?/);
    return m ? { r: +m[1], g: +m[2], b: +m[3], a: m[4] === undefined ? 1 : +m[4] } : null;
  };
  const lum = ({ r, g, b }) => {
    const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };
  const blend = (fg, bg) => ({ r: fg.r * fg.a + bg.r * (1 - fg.a), g: fg.g * fg.a + bg.g * (1 - fg.a), b: fg.b * fg.a + bg.b * (1 - fg.a), a: 1 });
  const effectiveBackground = (el) => {
    const layers = [];
    for (let e = el; e; e = e.parentElement) {
      const c = parse(getComputedStyle(e).backgroundColor);
      if (c && c.a > 0) { layers.push(c); if (c.a >= 1) break; }
    }
    return layers.reverse().reduce((base, layer) => blend(layer, base), { r: 255, g: 255, b: 255, a: 1 });
  };
  const visible = (el) => { const r = el.getBoundingClientRect(); return r.width && r.height && r.bottom > 0 && r.top < innerHeight; };
  const inc = (map, key) => { map[key] = (map[key] || 0) + 1; };
  const contract = () => getComputedStyle(document.documentElement).getPropertyValue('--ccc-brand-light-class').trim();

  function scan() {
    const oobColors = {}, lowContrast = {}, accentText = {};
    for (const el of document.querySelectorAll('body *')) {
      if (el.closest('.imx-hyperviewshape, svg') || !visible(el)) continue;
      const cs = getComputedStyle(el);
      for (const p of ['color', 'backgroundColor', 'borderBottomColor']) {
        if (p === 'borderBottomColor' && parseFloat(cs.borderBottomWidth) === 0) continue;
        if (OOB.test(cs[p])) inc(oobColors, `${p} ${cs[p]}`);
      }
      const hasText = Array.from(el.childNodes).some((n) => n.nodeType === 3 && n.textContent.trim());
      if (!hasText || cs.visibility === 'hidden') continue;
      const fg0 = parse(cs.color);
      if (!fg0) continue;
      const bg = effectiveBackground(el);
      const fg = blend(fg0, bg);
      const ratio = (Math.max(lum(fg), lum(bg)) + 0.05) / (Math.min(lum(fg), lum(bg)) + 0.05);
      if (ratio < 3 && !STANDARD_LOW.test(cs.color)) inc(lowContrast, `${ratio.toFixed(2)}:1 ${cs.color} on rgb(${Math.round(bg.r)},${Math.round(bg.g)},${Math.round(bg.b)})`);
      if (fg0.r > fg0.g + 60 && fg0.r > fg0.b + 60) inc(accentText, cs.color);
    }
    const logo = document.querySelector('.eui-masthead-inner > eui-logo');
    const masthead = document.querySelector('header.eui-masthead');
    const lightClass = contract();
    const brandActive = !!lightClass && Array.from(document.body.classList).some((c) => c === lightClass || c === lightClass.replace(/-light-theme$/, '-dark-theme'));
    const darkActive = brandActive && document.body.classList.contains(lightClass.replace(/-light-theme$/, '-dark-theme'));
    return {
      page: location.hash,
      bodyClasses: document.body.className,
      mainScript: (Array.from(document.scripts).map((s) => s.src).find((s) => /\/main-[A-Z0-9]+\.js$/.test(s)) || '').split('/').pop(),
      brandContract: lightClass || null,
      themeCssLoaded: Array.from(document.styleSheets).filter((s) => BRAND_CSS.test(s.href || '')).map((s) => { try { return s.cssRules.length; } catch { return -1; } }),
      pluginEffect: brandActive && (!darkActive || document.body.classList.contains('eui-dark-theme')) && Object.keys(oobColors).length === 0,
      logo: !!logo && getComputedStyle(logo).backgroundImage.startsWith('url("data:'),
      masthead: masthead ? getComputedStyle(masthead).backgroundColor : null,
      oobColors,
      lowContrast,
      accentText,
      fontErrors: Array.from(document.fonts).filter((f) => f.status === 'error').length,
    };
  }

  // theme: forces the body class for a quick look. Works only when the user's choice is not "Device theme"
  // (BrandThemeService maps Auto back to the device mode). For a real check select the theme in
  // "User interface settings": the portal keeps the choice in the user's settings on the server, not in this page.
  async function go(hash, theme, waitMs = 3500) {
    if (theme) document.body.className = `${document.body.className.replace(/\S*theme\S*/g, '').trim()} ${theme}`.trim();
    if (hash) location.hash = hash;
    await new Promise((r) => setTimeout(r, waitMs));
    return scan();
  }

  // At most 4 pages per call: the Chrome tool stops a call after 45 s.
  async function tour(theme, hashes, waitMs = 3500) {
    const result = {};
    let first = true;
    for (const hash of hashes.slice(0, 4)) {
      result[hash] = await go(hash, first ? theme : null, waitMs);
      first = false;
    }
    return result;
  }

  window.__brandCheck = { scan, go, tour };
  return 'brand-check ready';
})();
