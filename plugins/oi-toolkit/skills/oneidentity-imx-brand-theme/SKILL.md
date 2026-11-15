---
name: oneidentity-imx-brand-theme
description: Use to create or update organization brand themes (light and dark) for the One Identity Manager 10.0 Web Portal from a brand book and logos — palette, logo in masthead and login, no One Identity blue left in any component, "Device theme" mapped to the brand themes, Software Loader package and automatic checks in Chrome. Triggers: tema, theme, brand, branding, logo, colori del portale, brand identity, corporate design.
---

# Web Portal brand themes (kit)

From a `brand.json` (colors and logos of the organization) the kit produces, without investigating upstream code:
two themes `<id>-light-theme` / `<id>-dark-theme`, the runtime support in the `ccc` plugin, the Software Loader
package and the checks in Chrome. Agent: `imx-brand-theme-builder`. Architecture of the portal: skill `oneidentity-imx`.
Why each rule exists (symptom, cause, check): `reference.md`. Checks after the import: `verification.md`.

## Before starting
- Workspace with the IdentityManager.Imx fork (`imxweb` with `node_modules`), version pinning from `CLAUDE.md`.
- Production gate: read `## Ambiente` of `CLAUDE.md`. Only `Tipo: LAB`, `TEST` or `DEMO` allow the copy into the API
  Server `bin` and the pool recycle (each with explicit OK). Otherwise stop at the package and hand it over.
- `CompanyLogoUrl` must be empty (one logo for all themes in OIM; the theme draws its own): check in Chrome
  (`<API Server>/imx/config` or the masthead shows the One Identity logo with the standard theme).
- Scripts: `<kit>/scripts/` where `<kit>` is this skill folder. Run with `pwsh -NoProfile -File`. Each prints one
  JSON line at the end: read only that line.

## Phases
1. **brand.json** — read the brand book (PDF pages with colors and logo rules) and the logos; write
   `oim/webportal/brand/<id>/brand.json` (schema `brand.schema.json`, example `examples/acme/`). Copy the logos next
   to it or reference them relatively (brand assets stay out of git if the brand owner asks). Propose it to the operator
   with: primary, computed dark accent and dark fill (`Read-ImxBrand` in `scripts/ImxBrandColor.psm1` shows them and
   any warning), layouts, logos per surface. Wait for confirmation.
2. **Generate** — `New-ImxBrandTheme.ps1 -Brand <brand.json> -ImxWebDir <imxweb> -CustomizationsPath oim/webportal/CUSTOMIZATIONS.md`.
   `blocked` = a generated file was edited by hand: move the change into `brand.json` or the kit, never patch it.
3. **Plugin** — `Install-ImxBrandPlugin.ps1 -ImxWebDir <imxweb>`. `needs-ccc`: follow `reference.md`, "Plugin ccc".
   Apply the `actions` it reports (spec of `InitService`, legacy theme services).
4. **Package** — `New-ImxBrandDeployPackage.ps1 -Id <id> -ImxWebDir <imxweb> -BrandDir oim/webportal/brand/<id>
   -StagingRoot oim/webportal/deploy-staging -ApiServerImxWeb <ApiServer>\bin\imxweb` (tests, theme build checks,
   production build without Nx cache, bundle check). Give the operator the table of files with `importNeeded`.
5. **Deploy (operator)** — with OK: copy the staging into `bin\imxweb` (backup of replaced files); the operator imports
   the files with the Software Loader (root `...\ApiServer\bin`, machine role `Server\Web\Business Api Server`);
   with OK: recycle `<API Server app pool>`.
6. **Checks** — `verification.md` (scanner `scripts/brand-check.js`): report pages × themes, anomalies only.
7. **Documentation** — skill `oi-documentation`: change record, flow "Scelta del tema nel Web Portal", indexes.

## Color rules (applied by the kit, overridable in brand.json)
- Light theme: One Identity blue → brand palette (60→500, 80→700, 85→800, 90→900); light blue tints → neutral;
  orange → warn (amber by default).
- Dark theme: one **accent** for text, links, icons, active tabs, indicators: the most saturated tint with ≥ 4.0:1 on
  cards `#444647` and ≥ 4.5:1 on the page `#1e1e1e`. One **fill** with white text ≥ 7:1 for filled buttons, FABs,
  badges, selected chips/dates, stepper icons, side panel and login title bars. Dark blue surfaces → anthracite.
- Text on the brand color (masthead, buttons): white when ≥ 3:1 (large text), else the better of white/black.
- Values below the thresholds are kept when the brand owner insists, with the warning recorded in `notes`.

## Economy
- Do not read upstream code, `node_modules` or the compiled CSS: the scripts check them. Read the JSON lines.
- A new kind of anomaly (not covered by `reference.md`) is a new kit rule: stop, describe it, propose the kit change.
- Login: the operator logs out and in; never type credentials.
