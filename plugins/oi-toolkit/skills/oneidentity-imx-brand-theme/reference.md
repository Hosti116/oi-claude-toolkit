# Brand theme kit — reference

## Pitfalls (each one is checked or handled by the kit)

| Symptom | Cause | Handled by |
|---|---|---|
| Theme CSS answers 404, no logo, only plugin colors | API Server 10.0 publishes `/html/<folder>` only for web apps registered in `QBMHtmlApp`; `Html_<theme>.zip` of the official theme procedure is extracted to `App_Data\WebCache\html\<theme>` but not served | CSS inside the portal package (`custom\Html_qer-app-portal.zip` → `<id>/<class>.css`), `Urls` = `../qer-app-portal/<id>/<class>.css` |
| A theme recolors the other themes, standard ones included | ElementalUI `theme.theme()` (used by the template) emits Material tokens on `html`; the portal loads the CSS of every custom theme | `_brand-scoped-theme.scss` (`:where(body.<class>)`); build check `scopeDiffs = 0` |
| Icon buttons lose their color with the theme | scoping with `body.<class>` raises Material's specificity above the portal rules | `:where()` (zero specificity) |
| 503 on `Cadence-Icon*.woff`, `SourceSansPro*` | font partials of the template use paths relative to the theme CSS | partials not included; build check `fontFaces = 0` |
| Dark theme: content area stays light | component dark rules are scoped to `.eui-dark-theme`; `EuiThemeService` sets one class only | `BrandThemeService` adds `eui-dark-theme` |
| One Identity blue/orange in shop, menus, lists | ~290 upstream uses of the fixed palette and 53 in ElementalUI, some in `[_ngcontent]` component styles | runtime recolor **in place** (same rule, same specificity) |
| A hidden blue background reappears (e.g. "Forgot password?" red on red) | a recolored copy appended later beats the rules that overrode the original | in-place patching, never copies |
| Login: labels and username white on white | `login-theme` of `imx-theme.theme()` gives `.imx-loginPage` the primary contrast color | light template: dark text in `.imx-card`, light on `.imx-card-header` |
| Dark: dark text on brand fills (1.8:1) | One Identity pairs light blue-40 fills with dark text | plugin turns the paired text white; theme sets fill text tokens |
| Page freezes | `classList.add/remove` rewrite the attribute even without change → body observer loop | classes changed only when needed (unit test "no observer loop") |
| New ccc code not in the deployed portal | Nx does not count `dist/ccc` as a portal input; cached portal build | `--skip-nx-cache`; bundle check of the package |
| Old portal after the import | browser cache | Ctrl+Shift+R; scanner reports `mainScript` |
| Theme choice ignored by scripts | the choice is a user setting on the server, the portal overwrites `localStorage` | select the theme in "User interface settings" |
| Theme applied late or not at all | theme CSS loads after the plugin started | plugin re-evaluates on every stylesheet load |

## Deployment (Software Loader)
- Files (staging mirrors `bin\imxweb`): `custom\Html_qer-app-portal.zip`, `Html_ccc\imx-plugin-config.json`,
  `Html_<id>-light-theme\imx-theme-config.json`. Root folder of the import: `...\ApiServer\bin` (paths saved as
  `imxweb\...`). Machine role: `Server\Web\Business Api Server` (the guide names "Business API Server" for the
  application; for plugin and theme files it is the closest role). Then recycle the API Server application pool.
- Source: HTML Development Guide 10.0, "Compiling and deploying web applications" and "Adding plugins";
  Web Application Configuration Guide 10.0, "Creating and deploying custom themes" (its ZIP layout is not served,
  see the first pitfall).
- Rollback: remove the imported files with the Software Loader and from `bin\imxweb`, recycle the pool: the standard
  portal (`imxweb\Html_qer-app-portal.zip`) is still there.

## Plugin ccc

The runtime support (`BrandThemeService`) lives in the workspace plugin library `ccc` of IdentityManager.Imx
(`imxweb/projects/ccc`). `Install-ImxBrandPlugin.ps1` adds it to an existing `ccc`; when the workspace has no `ccc`
(status `needs-ccc`), create the library first. These are the only upstream files touched, each change marked
`CCC-CUSTOM` and listed in `oim/webportal/CUSTOMIZATIONS.md`:

1. Copy `templates/ccc/skeleton/` to `imxweb/projects/ccc/` (configuration copied from the `olg` plugin, module
   `CccConfigModule`, `InitService` that starts `BrandThemeService`).
2. `imxweb/angular.json`: add a `ccc` project entry, copy of the `olg` entry with `olg` replaced by `ccc`.
3. `imxweb/tsconfig.json`, `compilerOptions.paths`: `"ccc": ["dist/ccc"]`.
4. `imxweb/projects/qer-app-portal/project.json`: add `"ccc"` to `targets.build.dependsOn[].projects`.
5. `imxweb/projects/qer-app-portal/src/app/dynamic-import/portal-dynamic-modules-import.service.ts`
   (the documented extension point for external developers):

   ```ts
   // CCC-CUSTOM: ccc plugin (runtime support of the brand themes), loaded in loadThirdPartyModules.
   import { CccConfigModule } from "ccc";
   import { environment } from "../../environments/environment";

   const CCC_PLUGIN: PlugInInfo = { Container: 'ccc', Name: 'CccConfigModule' };

   // in the class:
   async loadThirdPartyModules(modules: PlugInInfo[]): Promise<void> {
     // CCC-CUSTOM: load the ccc plugin when the API Server lists it (deployed imx-plugin-config.json).
     // In development builds it is also loaded when the local API Server does not list it yet.
     const cccModule = modules.find((m) => m.Container === CCC_PLUGIN.Container) ?? (environment.production ? undefined : CCC_PLUGIN);
     if (cccModule) {
       await this.loadModule(cccModule, async () => {
         await import('ccc');
         return [CccConfigModule];
       });
     }
   }
   ```
6. `pwsh -NoProfile -File <kit>/scripts/Install-ImxBrandPlugin.ps1 -ImxWebDir imxweb` (copies `brand-theme/`), then
   `npx nx test ccc --watch=false --browsers ChromeHeadless` and `npx nx build ccc` from `imxweb`.

In production the portal loads `ccc` only when the API Server lists it: `Html_ccc/imx-plugin-config.json`
(`{"qer-app-portal":[{"Container":"ccc","Name":"CccConfigModule"}]}`) is part of every deploy package.
