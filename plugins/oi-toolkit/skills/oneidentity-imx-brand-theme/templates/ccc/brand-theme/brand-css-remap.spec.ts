// Template of oi-toolkit (skill oneidentity-imx-brand-theme): do not edit here, change the kit and reinstall.
import { applyPatches, collectPatches, remapValue, revertPatches } from './brand-css-remap';
import { FIXTURE_MAPS } from './brand-contract.fixture.spec';
const LIGHT = FIXTURE_MAPS.base;

function sheetOf(css: string): CSSStyleSheet {
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(css);
  return sheet;
}

function firstStyleRule(rules: CSSRuleList): CSSStyleRule {
  for (let index = 0; index < rules.length; index++) {
    const rule = rules[index];
    if (rule instanceof CSSStyleRule) {
      return rule;
    }
    if (rule instanceof CSSGroupingRule) {
      return firstStyleRule(rule.cssRules);
    }
  }
  throw new Error('no style rule');
}

describe('brand-css-remap', () => {
  describe('remapValue', () => {
    it('replaces a One Identity color written as rgb()', () => {
      expect(remapValue('rgb(10, 150, 209)', LIGHT)).toBe('rgb(235, 33, 46)');
    });

    it('replaces a hex color in any case, as found in custom property values', () => {
      expect(remapValue('#0A96D1', LIGHT)).toBe('#eb212e');
    });

    it('keeps the alpha channel of rgba() values', () => {
      expect(remapValue('rgba(10, 150, 209, 0.5)', LIGHT)).toBe('rgba(235, 33, 46, 0.5)');
    });

    it('replaces every One Identity color inside a composite value', () => {
      expect(remapValue('0 0 0 1px rgb(10, 150, 209), 0 0 0 2px rgb(227, 106, 0)', LIGHT)).toBe(
        '0 0 0 1px rgb(235, 33, 46), 0 0 0 2px rgb(180, 83, 9)',
      );
    });

    it('returns null when the value has no One Identity color', () => {
      expect(remapValue('rgb(1, 2, 3)', LIGHT)).toBeNull();
    });
  });

  describe('collectPatches / applyPatches / revertPatches', () => {
    it('recolors the declaration in its own rule and leaves the other declarations alone', () => {
      const sheet = sheetOf('.link { color: #0a96d1; font-weight: bold; }');
      const rule = firstStyleRule(sheet.cssRules);

      applyPatches(collectPatches(sheet.cssRules, false, FIXTURE_MAPS));

      expect(rule.style.getPropertyValue('color')).toBe('rgb(235, 33, 46)');
      expect(rule.style.getPropertyValue('font-weight')).toBe('bold');
      expect(sheet.cssRules.length).toBe(1);
    });

    it('recolors custom properties', () => {
      const sheet = sheetOf('body .mat-primary { --mat-icon-button-icon-color: #0a96d1; }');

      applyPatches(collectPatches(sheet.cssRules, false, FIXTURE_MAPS));

      expect(firstStyleRule(sheet.cssRules).style.getPropertyValue('--mat-icon-button-icon-color').trim()).toBe('#eb212e');
    });

    it('keeps !important', () => {
      const sheet = sheetOf('.x { color: #0a96d1 !important; }');
      const rule = firstStyleRule(sheet.cssRules);

      applyPatches(collectPatches(sheet.cssRules, false, FIXTURE_MAPS));

      expect(rule.style.getPropertyPriority('color')).toBe('important');
    });

    it('recolors rules nested in @media', () => {
      const sheet = sheetOf('@media (max-width: 768px) { .x { color: #0a96d1; } }');

      applyPatches(collectPatches(sheet.cssRules, false, FIXTURE_MAPS));

      expect(firstStyleRule(sheet.cssRules).style.getPropertyValue('color')).toBe('rgb(235, 33, 46)');
    });

    it('maps dark-theme surfaces to anthracite and every dark-theme foreground to the single light red', () => {
      const sheet = sheetOf(
        '.eui-dark-theme .card { background-color: #016b91; color: #016b91; } .eui-dark-theme .link { color: #0a96d1; }',
      );
      const card = sheet.cssRules[0] as CSSStyleRule;
      const link = sheet.cssRules[1] as CSSStyleRule;

      applyPatches(collectPatches(sheet.cssRules, true, FIXTURE_MAPS));

      expect(card.style.getPropertyValue('background-color')).toBe('rgb(46, 50, 54)');
      expect(card.style.getPropertyValue('color')).toBe('rgb(246, 144, 151)');
      expect(link.style.getPropertyValue('color')).toBe('rgb(246, 144, 151)');
    });

    it('turns dark-theme blue-40 text into the light card red, readable on cards and menu bars', () => {
      // e.g. .eui-dark-theme .imx-valuelist a (dashboard lists) on the #444647 card: #ee424d would be 2.5:1.
      const sheet = sheetOf('.eui-dark-theme .imx-valuelist a { color: #8acbe3; }');

      applyPatches(collectPatches(sheet.cssRules, true, FIXTURE_MAPS));

      expect(firstStyleRule(sheet.cssRules).style.getPropertyValue('color')).toBe('rgb(246, 144, 151)');
    });

    it('turns dark-theme blue-40 fills into dark red with white text in the same rule', () => {
      // e.g. .eui-dark-theme .imx-card-header (login): blue-40 background with gray-80 text.
      const sheet = sheetOf('.eui-dark-theme .header { background-color: #8acbe3; color: #2f3233; }');
      const rule = firstStyleRule(sheet.cssRules);

      applyPatches(collectPatches(sheet.cssRules, true, FIXTURE_MAPS));

      expect(rule.style.getPropertyValue('background-color')).toBe('rgb(164, 38, 44)');
      expect(rule.style.getPropertyValue('color')).toBe('rgb(255, 255, 255)');
    });

    it('turns the text token of the same component white when its fill token becomes dark red', () => {
      const sheet = sheetOf(
        '.eui-dark-theme { --mat-button-filled-container-color: #8acbe3; --mat-button-filled-label-text-color: #2f3233;' +
          ' --mat-badge-text-color: #2f3233; }',
      );
      const rule = firstStyleRule(sheet.cssRules);

      applyPatches(collectPatches(sheet.cssRules, true, FIXTURE_MAPS));

      expect(rule.style.getPropertyValue('--mat-button-filled-container-color').trim()).toBe('#a4262c');
      expect(rule.style.getPropertyValue('--mat-button-filled-label-text-color').trim()).toBe('#ffffff');
      // Different component (no fill in this rule): unchanged.
      expect(rule.style.getPropertyValue('--mat-badge-text-color').trim()).toBe('#2f3233');
    });

    it('keeps dark text on other light fills of the dark theme, such as amber', () => {
      const sheet = sheetOf('.eui-dark-theme .warning { background-color: #edbe8e; color: #2f3233; }');
      const rule = firstStyleRule(sheet.cssRules);

      applyPatches(collectPatches(sheet.cssRules, true, FIXTURE_MAPS));

      expect(rule.style.getPropertyValue('color')).toBe('rgb(47, 50, 51)');
    });

    it('restores the text color it turned white', () => {
      const sheet = sheetOf('.eui-dark-theme .header { background-color: #8acbe3; color: #2f3233; }');
      const rule = firstStyleRule(sheet.cssRules);
      const patches = collectPatches(sheet.cssRules, true, FIXTURE_MAPS);
      applyPatches(patches);

      revertPatches(patches);

      expect(rule.style.getPropertyValue('color')).toBe('rgb(47, 50, 51)');
    });

    it('uses the light map for dark-theme rules when the dark mode is off', () => {
      const sheet = sheetOf('.eui-dark-theme .card { background-color: #016b91; }');

      applyPatches(collectPatches(sheet.cssRules, false, FIXTURE_MAPS));

      expect(firstStyleRule(sheet.cssRules).style.getPropertyValue('background-color')).toBe('rgb(193, 23, 35)');
    });

    it('restores the original values', () => {
      const sheet = sheetOf('.x { color: #0a96d1 !important; }');
      const rule = firstStyleRule(sheet.cssRules);
      const patches = collectPatches(sheet.cssRules, false, FIXTURE_MAPS);
      applyPatches(patches);

      revertPatches(patches);

      expect(rule.style.getPropertyValue('color')).toBe('rgb(10, 150, 209)');
      expect(rule.style.getPropertyPriority('color')).toBe('important');
    });

    it('returns no patches for rules without One Identity colors', () => {
      const sheet = sheetOf('.x { color: red; }');

      expect(collectPatches(sheet.cssRules, false, FIXTURE_MAPS)).toEqual([]);
    });
  });
});
