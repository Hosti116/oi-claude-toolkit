---
name: oneidentity-imx
description: Use for any development or customization of the One Identity Manager HTML5 web applications (Web Portal qer-app-portal, Password Reset Portal, API Server landing page, custom apps) in the IdentityManager.Imx Angular/Nx monorepo under oim/webportal/imx — components, menus, dashboard tiles, data tables, plugins, theming, build, local debugging against an API Server.
---

# One Identity Manager HTML5 apps (IdentityManager.Imx)

## Where things are
- Fork of `OneIdentity/IdentityManager.Imx`, submodule at `oim/webportal/imx`. Fork and working branch: `CLAUDE.md` of the workspace.
- Angular workspace = `oim/webportal/imx/imxweb` (run every npm/ng/nx command from there).
- Official step-by-step samples: `oim/webportal/imx/sdk_samples/` (dashboard tile, menu item, data tables).
- Read before guessing: `imxweb/projects/<lib>/readme.md`, `imxweb/custom-theme/readme.md`,
  `imxweb/projects/qbm/src/lib/cdr/Readme.md`, `UPGRADE.md`, `imxweb/changes/`.

## Version pinning (critical)
- Read the installed version from `## Ambiente` of CLAUDE.md. Identity Manager **10.0 LTS** → branch `v100`, **Angular 20**, **Node 22.x** (what upstream CI uses).
- The API client packages in `imxweb/imx-modules/imx-api-*.tgz` (see `*.tgz-version`) must match the
  installed API Server build. The `v100` head of 2026-10-05 **requires Identity Manager 10.1** (see CHANGELOG):
  do not merge/rebase onto upstream commits newer than the installed version.
- Never edit files in `imx-modules/` and never regenerate them by hand.

## Architecture rules
- Libraries map 1:1 to Identity Manager modules (`qbm`, `qer`, `att`, `rmb`, …). `qbm`/`qer` are compile-time
  libraries; the others are **plugins loaded at runtime** via each project's `imx-plugin-config.json`.
- **Customizations go in our own code, not in upstream files**, so upgrades stay a clean rebase:
  1. preferred: a new plugin library `ccc` (copy the structure of a small existing plugin, register it
     in `imx-plugin-config.json`) that adds menus/tiles/routes through the plugin system (see sdk_samples 01/02);
  2. only when there is no extension point: a minimal, commented change in the upstream file,
     marked `// CCC-CUSTOM: <reason>` so it is easy to find during rebase.
- **Follow the existing code style of this repo over generic Angular advice** (including the
  `angular-developer` skill): same module structure, ElementalUI + Angular Material, `imx-data-source-toolbar` /
  `imx-data-table`, CDR components, existing services. Do not refactor upstream code "to best practices".
- UI strings use LDS keys: `'#LDS#Text' | translate` — never hard-code visible text.

## Commands (from `oim/webportal/imx/imxweb`)
```powershell
npm install                               # also unpacks imx-modules (postinstall); npm only, no yarn/pnpm
npx nx build qer                          # builds qbm then qer (Nx resolves dependencies)
npx nx build qer-app-portal               # app build
npm run start -- qer-app-portal           # = ng serve, dev config, talks to environment.ts (default http://localhost:8182)
npx nx test <project> --watch=false --browsers ChromeHeadless
npm run lint
npm run doc <project>                     # component docs into imxweb/documentation/<project>
```
Local API Server for debugging (run by the operator, from the Identity Manager install folder):
`imxclient.exe run-apiserver -B` → `http://localhost:8182`.

## Safety
- Running `npm install`, builds and tests is fine. Deploying a build to any environment (database / API Server)
  is a write action: prepare the steps, show them, and wait for explicit OK.
- Deployment procedure: follow the official HTML Development Guide for 10.0
  (docs.oneidentity.com → One Identity Manager 10.0 → HTML5 Development). Do not invent deployment steps.

## Definition of done for a change
1. builds with `npx nx build <affected projects>`,
2. tests/lint green for the touched projects,
3. no edits in `imx-modules/`, upstream edits (if any) marked `CCC-CUSTOM`,
4. short note in `oim/webportal/CUSTOMIZATIONS.md` (what, where, why) — this is the rebase checklist for the next upgrade.