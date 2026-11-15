# Brand theme kit — reference

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
