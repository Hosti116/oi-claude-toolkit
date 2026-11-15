// Template of oi-toolkit (skill oneidentity-imx-brand-theme): do not edit here, change the kit and reinstall.
import { ColorMap, ONE_IDENTITY_COLORS, OiShade } from './brand-ootb-colors';
import { BrandColorMaps } from './brand-theme-config';

/**
 * CCC: recolors CSS declarations that use One Identity palette colors with the brand colors.
 * Template of the oi-toolkit kit (skill oneidentity-imx-brand-theme): identical for every brand.
 *
 * The declarations are changed in place, inside their own rule: the rule keeps its position and
 * specificity, so the cascade stays as upstream wrote it (a copy appended later would also win
 * against the rules that originally overrode it). Every change is recorded and can be reverted.
 */

const DARK_THEME_CLASS = 'eui-dark-theme';
const FOREGROUND_PROPERTY = /(text|icon|label|foreground)/;
const SURFACE_PROPERTY = /(background|border|outline|shadow|container|surface)/;
/** Fill properties whose text partner is the plain "color" property. */
const PLAIN_FILL_PROPERTY = /^background(-color|-image)?$/;
/** Suffix of a fill token; what remains is the component prefix, e.g. "--mat-button-filled-". */
const FILL_TOKEN_SUFFIX = /(container-)?(background-)?color$/;
/** Relative luminance below which a text color counts as dark (One Identity gray-80 is about 0.03). */
const DARK_TEXT_LUMINANCE = 0.1;
const SINGLE_COLOR = /^(?:#([0-9a-f]{6})|rgba?\(\s*(\d+),\s*(\d+),\s*(\d+)\s*(?:,\s*[\d.]+\s*)?\))$/i;

/** One recolored declaration: enough to apply it and to restore the original. */
export interface DeclarationPatch {
  readonly style: CSSStyleDeclaration;
  readonly property: string;
  readonly priority: string;
  readonly original: string;
  readonly replacement: string;
}

interface ShadePattern {
  readonly shade: OiShade;
  /** Hex form, any case; a trailing alpha pair (#rrggbbaa) is kept. */
  readonly hex: RegExp;
  /** rgb()/rgba() form as serialized by the browser: "(r, g, b" followed by "," or ")". */
  readonly rgb: RegExp;
}

function toRgbTriplet(hex: string): [number, number, number] {
  return [1, 3, 5].map((start) => parseInt(hex.slice(start, start + 2), 16)) as [number, number, number];
}

const rgbPrefixCache = new Map<string, string>();

/** "(r, g, b" of a hex color, memoized: called for every declaration of every stylesheet. */
function toRgbPrefix(hex: string): string {
  let prefix = rgbPrefixCache.get(hex);
  if (prefix === undefined) {
    prefix = `(${toRgbTriplet(hex).join(', ')}`;
    rgbPrefixCache.set(hex, prefix);
  }
  return prefix;
}

const SHADE_PATTERNS: readonly ShadePattern[] = (Object.keys(ONE_IDENTITY_COLORS) as OiShade[]).map((shade) => {
  const [r, g, b] = toRgbTriplet(ONE_IDENTITY_COLORS[shade]);
  return {
    shade,
    hex: new RegExp(ONE_IDENTITY_COLORS[shade], 'gi'),
    rgb: new RegExp(`\\(\\s*${r},\\s*${g},\\s*${b}(?=\\s*[,)])`, 'g'),
  };
});

/** Returns the value with every One Identity color replaced, or null when there is nothing to replace. */
export function remapValue(value: string, map: ColorMap): string | null {
  if (!value.includes('#') && !value.includes('(')) {
    return null;
  }
  let result = value;
  for (const pattern of SHADE_PATTERNS) {
    const target = map[pattern.shade];
    result = result.replace(pattern.hex, target).replace(pattern.rgb, toRgbPrefix(target));
  }
  return result === value ? null : result;
}

function isSurfaceProperty(property: string): boolean {
  return !FOREGROUND_PROPERTY.test(property) && SURFACE_PROPERTY.test(property);
}

function mapFor(property: string, isDarkRule: boolean, maps: BrandColorMaps): ColorMap {
  if (!isDarkRule || !maps.darkSurface || !maps.darkForeground) {
    return maps.base;
  }
  return isSurfaceProperty(property) ? maps.darkSurface : maps.darkForeground;
}

function relativeLuminance(red: number, green: number, blue: number): number {
  const linear = (channel: number): number => {
    const value = channel / 255;
    return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue);
}

/** True for a single dark color value (#rrggbb, rgb(), rgba()); false for anything else, such as var(). */
function isDarkColor(value: string): boolean {
  const match = SINGLE_COLOR.exec(value.trim());
  if (!match) {
    return false;
  }
  const [red, green, blue] = match[1] ? toRgbTriplet(`#${match[1]}`) : [+match[2], +match[3], +match[4]];
  return relativeLuminance(red, green, blue) < DARK_TEXT_LUMINANCE;
}

function containsDarkFill(value: string, darkFill: string): boolean {
  return value.toLowerCase().includes(darkFill) || value.includes(toRgbPrefix(darkFill));
}

/** Text property that belongs to a fill property of the same rule ("color" for background, same token prefix). */
function isTextPartner(textProperty: string, fillProperty: string): boolean {
  if (PLAIN_FILL_PROPERTY.test(fillProperty)) {
    return textProperty === 'color';
  }
  const prefix = fillProperty.replace(FILL_TOKEN_SUFFIX, '');
  return (
    fillProperty.startsWith('--') &&
    prefix.length > 2 &&
    textProperty.startsWith(prefix) &&
    textProperty !== fillProperty &&
    FOREGROUND_PROPERTY.test(textProperty.slice(prefix.length))
  );
}

function collectFromStyleRule(rule: CSSStyleRule, darkMode: boolean, maps: BrandColorMaps, patches: DeclarationPatch[]): void {
  // Rules for the high-contrast theme never match while a brand theme is active: no special case needed.
  const isDarkRule = darkMode && rule.selectorText.includes(DARK_THEME_CLASS);
  const style = rule.style;
  const darkFills: string[] = [];
  for (let index = 0; index < style.length; index++) {
    const property = style[index];
    const original = style.getPropertyValue(property);
    const replacement = remapValue(original, mapFor(property, isDarkRule, maps));
    if (replacement !== null) {
      patches.push({ style, property, priority: style.getPropertyPriority(property), original, replacement });
      if (isDarkRule && maps.darkFill && isSurfaceProperty(property) && containsDarkFill(replacement, maps.darkFill)) {
        darkFills.push(property);
      }
    }
  }
  if (darkFills.length > 0) {
    collectTextOnDarkFill(style, darkFills, maps.onDarkFill ?? '#ffffff', patches);
  }
}

/** One Identity pairs its light blue fill with dark text: on the dark red fill that text becomes white. */
function collectTextOnDarkFill(style: CSSStyleDeclaration, fills: readonly string[], onDarkFill: string, patches: DeclarationPatch[]): void {
  for (let index = 0; index < style.length; index++) {
    const property = style[index];
    const original = style.getPropertyValue(property);
    if (isDarkColor(original) && fills.some((fill) => isTextPartner(property, fill))) {
      const replacement = original.trim().startsWith('#') ? onDarkFill : `rgb${toRgbPrefix(onDarkFill)})`;
      patches.push({ style, property, priority: style.getPropertyPriority(property), original, replacement });
    }
  }
}

/**
 * Finds the declarations to recolor in a rule list, including rules nested in @media, @supports,
 * @container and @layer.
 * @param darkMode true while the brand dark theme (with .eui-dark-theme) is active
 * @param maps color maps declared by the active brand theme (readBrandColorMaps)
 */
export function collectPatches(rules: CSSRuleList, darkMode: boolean, maps: BrandColorMaps): DeclarationPatch[] {
  const patches: DeclarationPatch[] = [];
  const visit = (list: CSSRuleList): void => {
    for (let index = 0; index < list.length; index++) {
      const rule = list[index];
      if (rule instanceof CSSStyleRule) {
        collectFromStyleRule(rule, darkMode, maps, patches);
      } else if (rule instanceof CSSGroupingRule) {
        visit(rule.cssRules);
      }
    }
  };
  visit(rules);
  return patches;
}

/** Writes the brand colors into the declarations (same rule, same priority). */
export function applyPatches(patches: readonly DeclarationPatch[]): void {
  patches.forEach((patch) => patch.style.setProperty(patch.property, patch.replacement, patch.priority));
}

/** Writes the original One Identity values back into the declarations. */
export function revertPatches(patches: readonly DeclarationPatch[]): void {
  patches.forEach((patch) => patch.style.setProperty(patch.property, patch.original, patch.priority));
}
