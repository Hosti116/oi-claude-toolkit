// Blocking checks of the two compiled brand theme CSS files (skill oneidentity-imx-brand-theme).
// Usage: node check-theme-css.mjs <imxweb> <light.css> <dark.css> <lightClass> <darkClass>
// Prints one JSON line { scopeDiffs, scopeExamples, fontFaces, contractMissing }; exit 1 when a check fails.
// - scopeDiffs: declarations outside the theme classes that differ between the two files. The portal loads the CSS
//   of every custom theme, so any of them would recolor the other themes.
// - fontFaces: @font-face rules (their relative font paths do not exist next to the theme CSS).
// - contractMissing: CSS variables of the runtime contract read by BrandThemeService.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join } from 'node:path';

const [imxweb, lightPath, darkPath, lightClass, darkClass] = process.argv.slice(2);
if (!darkClass) {
  console.error('usage: node check-theme-css.mjs <imxweb> <light.css> <dark.css> <lightClass> <darkClass>');
  process.exit(2);
}
const postcss = createRequire(join(imxweb, 'package.json'))('postcss');

const SHADES = ['blue10', 'blue15', 'blue20', 'blue40', 'blue60', 'blue80', 'blue85', 'blue90',
  'orange10', 'orange15', 'orange20', 'orange40', 'orange60', 'orange80', 'orange85', 'orange90'];

function analyse(path, themeClass) {
  const root = postcss.parse(readFileSync(path, 'utf8'));
  const unscoped = new Map();
  const declared = new Set();
  let fontFaces = 0;
  root.walkAtRules('font-face', () => { fontFaces++; });
  root.walkRules((rule) => {
    rule.walkDecls((decl) => { if (decl.prop.startsWith('--ccc-brand-')) declared.add(decl.prop); });
    if (rule.selectors.every((s) => s.includes(themeClass))) return;
    const context = rule.parent.type === 'atrule' ? `@${rule.parent.name} ${rule.parent.params} ` : '';
    rule.walkDecls((decl) => unscoped.set(`${context}${rule.selector} | ${decl.prop}`, decl.value));
  });
  return { unscoped, declared, fontFaces };
}

const light = analyse(lightPath, lightClass);
const dark = analyse(darkPath, darkClass);

const diffs = [];
for (const [key, value] of light.unscoped) if (!dark.unscoped.has(key) || dark.unscoped.get(key) !== value) diffs.push(key);
for (const key of dark.unscoped.keys()) if (!light.unscoped.has(key)) diffs.push(key);

const required = {
  light: ['--ccc-brand-light-class', '--ccc-brand-dark-class', '--ccc-brand-device-theme', ...SHADES.map((s) => `--ccc-brand-map-${s}`)],
  dark: ['--ccc-brand-light-class', '--ccc-brand-dark-class', '--ccc-brand-device-theme', '--ccc-brand-dark-fill', '--ccc-brand-on-dark-fill',
    ...['map', 'dark-fg', 'dark-surface'].flatMap((p) => SHADES.map((s) => `--ccc-brand-${p}-${s}`))],
};
const contractMissing = [
  ...required.light.filter((v) => !light.declared.has(v)).map((v) => `light:${v}`),
  ...required.dark.filter((v) => !dark.declared.has(v)).map((v) => `dark:${v}`),
];

const result = { scopeDiffs: diffs.length, scopeExamples: diffs.slice(0, 5), fontFaces: light.fontFaces + dark.fontFaces, contractMissing };
console.log(JSON.stringify(result));
process.exit(result.scopeDiffs || result.fontFaces || contractMissing.length ? 1 : 0);
