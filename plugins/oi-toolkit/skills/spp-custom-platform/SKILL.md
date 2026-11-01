---
name: spp-custom-platform
description: Use FIRST for any Safeguard for Privileged Passwords (SPP) custom platform work in this workspace — creating, enhancing, validating, importing or testing a custom platform JSON script, or analyzing its task logs. Reads the official SafeguardCustomPlatform agent skills directly from the submodule, maps them onto this workspace's layout and enforces the production gate from the Ambiente section of CLAUDE.md.
---

# SPP custom platforms — workspace adapter

The official agent system lives in the submodule `vendor/SafeguardCustomPlatform/`.
**Read `vendor/SafeguardCustomPlatform/AGENTS.md` before doing anything else** and follow its
workflows (new platform / enhance platform), iterative debug loop and loop budget.

If that file is missing, stop and ask the operator to run
`git submodule update --init vendor/SafeguardCustomPlatform`.

## Official skills: read them from the submodule
They are not installed as Claude Code skills. When `AGENTS.md` hands off to one of them, read its file with the
Read tool and follow it:

| Skill | File |
|---|---|
| `target-probing` | `vendor/SafeguardCustomPlatform/.agents/skills/target-probing/SKILL.md` |
| `strategy-selection` | `vendor/SafeguardCustomPlatform/.agents/skills/strategy-selection/SKILL.md` |
| `script-authoring` | `vendor/SafeguardCustomPlatform/.agents/skills/script-authoring/SKILL.md` |
| `safeguard-ps-operations` | `vendor/SafeguardCustomPlatform/.agents/skills/safeguard-ps-operations/SKILL.md` |
| `task-log-analysis` | `vendor/SafeguardCustomPlatform/.agents/skills/task-log-analysis/SKILL.md` |

## Production gate (MANDATORY, before any probe, import or trigger)
Read the `## Ambiente` section of `CLAUDE.md` at the workspace root and find `Tipo: <value>`.

| What you find | Environment | What is allowed |
|---|---|---|
| `Tipo: LAB`, `Tipo: TEST` or `Tipo: DEMO` | non-production | `nonProductionAffirmed=true`; **full-loop** when the target is reachable, otherwise **author-only** |
| Any other value, an ambiguous value, no `Tipo`, no `## Ambiente` section, no `CLAUDE.md` | **production** | **author-only**: local edits and `-SchemaOnly` validation. Never set `nonProductionAffirmed`; no probe, import or trigger |

- This section of `CLAUDE.md` is the only source. Never infer the type from a hostname, memory or the conversation.
- In production, say so and stop before the appliance. To change the classification, the operator edits `CLAUDE.md`.
- The official contract still applies on top of this gate (`AGENTS.md`: never operate against a production target).

## Environment facts
Read these from `## Ambiente` too; if one is missing, ask the operator. Never assume a value.
- SPP appliance and version. Check the features you need against `vendor/SafeguardCustomPlatform/docs/reference/compatibility.md`.
- Identity provider for the interactive login.

## Rules valid everywhere
- Login is interactive PKCE: `Connect-Safeguard -Appliance <spp> -DeviceCode` (fallback `-Browser`; add `-Insecure`
  only after a TLS error). Never use `-Username/-Password` or store credentials in scripts.
- safeguard-ps must be **>= 8.4.3** (enforced by `Invoke-PlatformDevLoop.ps1`). It can be newer than the
  appliance: if a cmdlet or endpoint returns 404/unsupported, report it — do not work around it silently.
- PowerShell 7 (`pwsh`) for every safeguard-ps call.

## Path mapping (the official skills assume their own repo root)
| Official skills say | In this workspace |
|---|---|
| `.agents/…`, `schema/…`, `samples/…`, `templates/…`, `tools/…`, `docs/agent-reference/…` | `vendor/SafeguardCustomPlatform/<same path>` |
| `$env:USERPROFILE\.copilot\session-state\<id>\files\sg-session.json` | `.sg-state/sg-session.json` (workspace root, gitignored) |
| where to save a new platform script | `spp/custom-platforms/<PlatformName>/<PlatformName>.json` |

Never write into `vendor/` (it is a pinned submodule). Copy a sample/template into
`spp/custom-platforms/<PlatformName>/` and edit it there.

## Per-platform folder
```
spp/custom-platforms/<PlatformName>/
  <PlatformName>.json   ← the script (schema: vendor/SafeguardCustomPlatform/schema/custom-platform-script.schema.json)
  README.md             ← target, version, operations implemented, credential intent, test asset/account names
  evidence.json         ← target-probing output (no secrets)
  logs/                 ← task-log JSON from runs (gitignored)
```

## Dev loop command (from the workspace root)
```powershell
pwsh -NoProfile -File vendor/SafeguardCustomPlatform/tools/Invoke-PlatformDevLoop.ps1 `
     -ScriptFile spp/custom-platforms/<PlatformName>/<PlatformName>.json -SchemaOnly
```
Run `Get-Help vendor/SafeguardCustomPlatform/tools/Invoke-PlatformDevLoop.ps1 -Full` before using any other switch.

Other useful commands (all paths from the workspace root, PowerShell 7):
```powershell
# Pure schema check, no appliance (same as -SchemaOnly)
Test-Json -Path spp/custom-platforms/<P>/<P>.json -SchemaFile vendor/SafeguardCustomPlatform/schema/custom-platform-script.schema.json

# Full loop: only when the production gate says non-production (connect first, see safeguard-ps-operations)
pwsh -NoProfile -File vendor/SafeguardCustomPlatform/tools/Invoke-PlatformDevLoop.ps1 `
     -ScriptFile spp/custom-platforms/<P>/<P>.json `
     -PlatformToEdit "<P>" -Operation CheckPassword -AccountToUse "<account>"
```
`tools/TestTool.ps1` is legacy (hard-coded variables): never use it, prefer `Invoke-PlatformDevLoop.ps1`.
`Build-SamplesIndex.ps1` / `Test-AgentLinks.ps1` are upstream-maintainer tools: not needed here.

## Script format essentials (things AGENTS.md does not repeat)
- One JSON object: `Id`, `BackEnd` (always `"Scriptable"`), optional `Meta` / `Imports` / `Functions`,
  then one object per **operation** (`CheckSystem`, `CheckPassword`, `ChangePassword`, `DiscoverAccounts`, …).
  Each operation = `Parameters` (typed inputs) + `Do` (ordered command list). `%Name%` interpolates.
- **Feature flags are derived, never configured**: the operations present decide what SPP enables.
  Do not add an operation the operator did not request.
- **Reserved parameters** (most common copy-paste bug when adapting a sample):

| Name | Source | Scope |
|---|---|---|
| `FuncUserName` / `FuncPassword` | asset service account | any operation |
| `AccountUserName` / `AccountPassword` | managed account | account-level operations only |
| `NewPassword` | SPP-generated new password | `ChangePassword` |
| `Address` | asset network address | all operations |

- `CheckSystem` is asset-level: only `Func*` credentials, no managed account in context.
- Real secrets must be typed `Secret` (masked as `**secret**` in task logs), never `String`.
- Reference docs to cite before guessing: `docs/reference/{operations,reserved-parameters,custom-parameters,script-structure,status-messages,variables}.md`
  and `docs/reference/commands/` (all under `vendor/SafeguardCustomPlatform/`).

## Learnings
When a run reveals a new failure signature, add it to `spp/custom-platforms/<PlatformName>/README.md`
(and propose it for `docs/agent-reference/failure-patterns.md` upstream) — never edit the submodule.
