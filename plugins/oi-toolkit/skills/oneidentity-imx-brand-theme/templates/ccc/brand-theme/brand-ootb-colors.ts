// Template of oi-toolkit (skill oneidentity-imx-brand-theme): do not edit here, change the kit and reinstall.
/**
 * Fixed One Identity palette ($color-blue-*, $color-orange-* of @elemental-ui/core) that upstream styles use
 * instead of the theme palette. BrandThemeService replaces these colors with the brand ones.
 * Template of the oi-toolkit kit (skill oneidentity-imx-brand-theme): identical for every brand.
 */

export const OI_SHADES = [
  'blue10', 'blue15', 'blue20', 'blue40', 'blue60', 'blue80', 'blue85', 'blue90',
  'orange10', 'orange15', 'orange20', 'orange40', 'orange60', 'orange80', 'orange85', 'orange90',
] as const;

export type OiShade = (typeof OI_SHADES)[number];

export type ColorMap = Readonly<Record<OiShade, string>>;

export const ONE_IDENTITY_COLORS: ColorMap = {
  blue10: '#f2fcff',
  blue15: '#e1f4fa',
  blue20: '#cbe8f2',
  blue40: '#8acbe3',
  blue60: '#0a96d1',
  blue80: '#016b91',
  blue85: '#004e6b',
  blue90: '#00384d',
  orange10: '#fff9f2',
  orange15: '#fbefe2',
  orange20: '#f7e4d0',
  orange40: '#edbe8e',
  orange60: '#e36a00',
  orange80: '#a65300',
  orange85: '#7a3e00',
  orange90: '#592d00',
};
