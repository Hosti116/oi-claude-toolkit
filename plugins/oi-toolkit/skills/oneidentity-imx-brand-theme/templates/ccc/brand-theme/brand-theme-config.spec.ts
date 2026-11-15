// Template of oi-toolkit (skill oneidentity-imx-brand-theme): do not edit here, change the kit and reinstall.
import { FIXTURE_DARK, FIXTURE_LIGHT, FIXTURE_MAPS, fixtureContractCss } from './brand-contract.fixture.spec';
import { readBrandColorMaps, readBrandThemeConfig } from './brand-theme-config';

describe('brand-theme-config', () => {
  let style: HTMLStyleElement | undefined;
  const originalBodyClasses = Array.from(document.body.classList);

  function addContract(deviceTheme: 'brand' | 'standard' = 'brand'): void {
    style = document.createElement('style');
    style.textContent = fixtureContractCss(deviceTheme);
    document.head.appendChild(style);
  }

  afterEach(() => {
    style?.remove();
    style = undefined;
    document.body.className = originalBodyClasses.join(' ');
  });

  it('returns null when no loaded theme declares the brand contract', () => {
    expect(readBrandThemeConfig(document)).toBeNull();
  });

  it('reads the theme classes and the device theme mode from :root', () => {
    addContract('standard');

    expect(readBrandThemeConfig(document)).toEqual({ lightClass: FIXTURE_LIGHT, darkClass: FIXTURE_DARK, deviceTheme: 'standard' });
  });

  it('reads only the base map for the light theme', () => {
    addContract();
    document.body.classList.add(FIXTURE_LIGHT);

    const maps = readBrandColorMaps(document.body, false);

    expect(maps?.base).toEqual(FIXTURE_MAPS.base);
    expect(maps?.darkForeground).toBeUndefined();
  });

  it('reads the dark maps, the dark fill and its text color for the dark theme', () => {
    addContract();
    document.body.classList.add(FIXTURE_DARK);

    const maps = readBrandColorMaps(document.body, true);

    expect(maps).toEqual(FIXTURE_MAPS);
  });

  it('returns null when the active theme does not declare the maps (CSS not loaded yet)', () => {
    document.body.classList.add(FIXTURE_LIGHT);

    expect(readBrandColorMaps(document.body, false)).toBeNull();
  });
});
