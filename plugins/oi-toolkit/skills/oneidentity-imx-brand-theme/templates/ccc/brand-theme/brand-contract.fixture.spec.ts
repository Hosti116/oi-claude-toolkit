// Template of oi-toolkit (skill oneidentity-imx-brand-theme): do not edit here, change the kit and reinstall.
import { ColorMap, OI_SHADES } from './brand-ootb-colors';
import { BrandColorMaps } from './brand-theme-config';

/** Test fixture: the CSS contract a generated brand theme declares (values of the first kit customer). */
export const FIXTURE_LIGHT = 'acme-light-theme';
export const FIXTURE_DARK = 'acme-dark-theme';

export const FIXTURE_MAPS: BrandColorMaps = {
  base: {
    blue10: '#f2f3f4', blue15: '#f2f3f4', blue20: '#dfe1e3', blue40: '#c4c8cc',
    blue60: '#eb212e', blue80: '#c11723', blue85: '#a9131d', blue90: '#861016',
    orange10: '#fff5e6', orange15: '#fff5e6', orange20: '#ffe4bf', orange40: '#ffbd66',
    orange60: '#b45309', orange80: '#8c4007', orange85: '#773606', orange90: '#5c2a04',
  },
  darkForeground: {
    blue10: '#3c4146', blue15: '#3c4146', blue20: '#4c5258', blue40: '#f69097',
    blue60: '#f69097', blue80: '#f69097', blue85: '#f69097', blue90: '#f69097',
    orange10: '#fff5e6', orange15: '#fff5e6', orange20: '#ffe4bf', orange40: '#ffbd66',
    orange60: '#ffbd66', orange80: '#8c4007', orange85: '#773606', orange90: '#5c2a04',
  },
  darkSurface: {
    blue10: '#3c4146', blue15: '#3c4146', blue20: '#4c5258', blue40: '#a4262c',
    blue60: '#a4262c', blue80: '#2e3236', blue85: '#2e3236', blue90: '#1f2225',
    orange10: '#fff5e6', orange15: '#fff5e6', orange20: '#ffe4bf', orange40: '#ffbd66',
    orange60: '#ffbd66', orange80: '#8c4007', orange85: '#773606', orange90: '#5c2a04',
  },
  darkFill: '#a4262c',
  onDarkFill: '#ffffff',
};

function declarations(prefix: string, map: ColorMap): string {
  return OI_SHADES.map((shade) => `--ccc-brand-${prefix}-${shade}: ${map[shade]};`).join(' ');
}

/** CSS of a brand theme pair, as the kit compiles it (contract part only). */
export function fixtureContractCss(deviceTheme: 'brand' | 'standard' = 'brand'): string {
  const maps = FIXTURE_MAPS;
  return [
    `:root { --ccc-brand-light-class: ${FIXTURE_LIGHT}; --ccc-brand-dark-class: ${FIXTURE_DARK}; --ccc-brand-device-theme: ${deviceTheme}; }`,
    `body.${FIXTURE_LIGHT}, body.${FIXTURE_DARK} { ${declarations('map', maps.base)} }`,
    `body.${FIXTURE_DARK} { ${declarations('dark-fg', maps.darkForeground!)} ${declarations('dark-surface', maps.darkSurface!)}`,
    `  --ccc-brand-dark-fill: ${maps.darkFill}; --ccc-brand-on-dark-fill: ${maps.onDarkFill}; }`,
  ].join('\n');
}

describe('brand contract fixture', () => {
  it('declares every shade of every map', () => {
    expect(fixtureContractCss().match(/--ccc-brand-(map|dark-fg|dark-surface)-/g)?.length).toBe(3 * OI_SHADES.length);
  });
});
