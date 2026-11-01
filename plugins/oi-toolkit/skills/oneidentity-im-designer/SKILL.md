---
name: oneidentity-im-designer
description: Use when designing, writing, reviewing or testing One Identity Manager 10.0 customizations that live in the Designer — VB.NET scripts in the script library, column templates and formatting scripts, processes (process chains, generating conditions, process steps and their parameters), events, configuration parameters, custom schema extensions (CCC_ tables/columns) and change labels / transport.
---

# One Identity Manager — Designer customizations (scripts, templates, processes)

## Working model (MANDATORY)
- **The repo holds the source, the Designer applies it.** Claude drafts and reviews code in
  `oim/designer/`; the operator applies it in the Designer, under a change label, and compiles.
- **Never write Designer/system objects via API or SQL** (script library, column definitions, process chains,
  config parameters, schema). No `New-/Set-/Remove-Entity` on those tables, no `Invoke-*` that changes them.
  Reading them (Get-*) is allowed and encouraged.
- Every deliverable = code file(s) in the repo + **numbered Designer steps** (where to click, which change label,
  when to compile) + a **test plan**.

## Reuse first: OOTB check (MANDATORY before writing any new script/template/process)
Before creating anything `CCC_`, prove that nothing built-in already does it. Output an **"OOTB check"**
section at the top of every proposal:

1. **Follow the current behaviour to its source.** For a column, read its current template / formatting script
   and note every script it calls; for a behaviour, find the process or event that produces it.
2. **Search the script library by name AND by code**, with several keywords — built-in names and comments are
   often English *and* German (e.g. `Umlaut`, `Sonderzeichen`, `Accent`, `Normaliz`, `Replace`, `Format`, `Convert`,
   `CentralAccount`, `Mail`, `Unique`). Use the read-only SQL login named in `## Ambiente` of CLAUDE.md (SELECT only) or `Get-Entity`;
   discover the code column name first:
   ```sql
   SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'DialogScript';
   SELECT ScriptName FROM DialogScript WHERE ScriptName LIKE '%Umlaut%' OR <codeColumn> LIKE '%Umlaut%';
   ```
3. **Search configuration parameters** (`Get-ConfigParm` / table `DialogConfigParm`) for a switch or format that
   already controls the behaviour — configuring is always preferred to coding.
4. **Report** a table: candidate (name) · what it does (from its code) · fits / partially / no · why.
5. **Decide in this order**: configure (config parameter) → call the built-in script from a short `CCC_` template
   → wrap it in a `CCC_` script that adds only the missing part → write new logic (only if 1–3 found nothing).
   Never copy-paste a built-in script's body into a `CCC_` script: call it, so fixes from updates still apply.

## Learn from the installed system before writing
The database contains thousands of One Identity built-in scripts, templates and processes for **this exact
version**. Copy their idioms instead of guessing APIs (10.0 changed several object-layer APIs vs 8.x/9.x):
```powershell
. .\tools\Connect-OIM.ps1
# Script library: find similar built-in scripts and read their code
Get-Entity -Type 'DialogScript' -Filter "ScriptName like 'QER[_]Person%'" -ResultSize 20 | Select-Object ScriptName
# Column definitions (templates/formatting) of a table
Get-Entity -Type 'DialogColumn' -Filter "UID_DialogTable = 'QER-T-Person'" -ResultSize 300
# Discover real column names before using them
Get-Entity -Type 'DialogScript' -ResultSize 1 | Get-Member -MemberType ScriptProperty
Remove-IdentityManagerSession
```
- Table/column names above are starting points: **verify with Get-Member** before relying on a column.
- Cite which built-in object you modelled the code on (name) in the file header.

## VB.NET API: verify every name before using it
A first draft written with "plausible" API names failed to compile in the Designer with 4 errors (earlier project).
Every API name must be confirmed in the official VB.NET samples (`ScriptSamples/**/*.vb` under the OIM SDK path in
`## Ambiente`; they are proprietary: read them, never copy them into a repo; if no path is set, use built-ins only) or in a
built-in script of this database, citing `file:line` or the script name — otherwise mark it **[DEDOTTO]**.
Confirmed on an earlier version (re-confirm on the installed version the first time):

| Need | Correct | Does NOT exist |
|---|---|---|
| Log | `RaiseMessage(MsgSeverity.Info / Warning / Serious, "msg")` | `Session.Log`, `LogEntry` |
| One filtered row | `Query.From("T").Where(w).GetQuery()` + `Session.Source().TryGet(query, entity)` | `CollectionLoadParameters` |
| Customizer method | `entity.CallMethod("Name")` **then** `entity.Save(Session)` (not executed without Save) | `entity.Method(...).Invoke()` |
| Create an object | `Session.Source.CreateNew("T")` → `PutValue(...)` → `Save(Session)` | |
| Arbitrary SQL (JOIN/TOP/ORDER BY) on the OIM DB | **not supported from scripts**: use a `SQLComponent` job, the script reads its output | `Connection.Select(...)` |

## Processes: formats and components
- **Job Chain Editor paste buffer** (select all + copy in the editor: header `ElementEditControl V1.0`,
  `<JobChainEdit><Elements>…</Elements><Connectors>…</Connectors></JobChainEdit>`) can be pasted back into a chain:
  it is the exchange format for jobs — but **only model it on a real example of the same component**. No real example
  → give manual Designer steps instead of inventing XML.
- The Script Editor export of a table's event/generation code is generated by the Designer: read it, never hand-write it.
- `HandleObjectComponent.FireGenEvent` (`EventName` + `WhereClause` with the keys of the triggering object, e.g.
  `$UID_Person$`) chains separate processes; `FireGenEvent("Read")` on a target-system object re-syncs it.
- `SQLComponent.Exists` is a **runtime** check (success → Successor, failure → `ErrorSuccessor`), not a generating condition.

## Repo layout
```
oim/designer/
  scripts/<ScriptName>.vb                 ← one file per script-library script (CCC_ prefix)
  templates/<Table>.<Column>.template.vb  ← column template
  templates/<Table>.<Column>.format.vb    ← formatting script (if any)
  processes/<Table>/<ProcessName>.md      ← process design: event, generating condition, steps, params (code inline)
  schema/<Table>.md                       ← custom columns/tables: name, type, length, purpose
  CHANGELOG.md                            ← change label → list of objects changed, date, status (draft/applied/tested)
```
`oim/scripts/` is for PowerShell (PSIdentityManagerUtils) — do not mix Designer VB.NET code into it.

## Conventions
- Everything custom uses the **`CCC_` prefix**: scripts, custom columns/tables, processes, events, config parameters.
  Never modify a built-in object when an extension point exists; if a built-in template/process must change,
  document the original value in the repo file first (it is the rollback).
- **VB.NET** for scripts, templates, generating conditions and process parameters.
- Templates/conditions/parameters return through `Value = ...`; column values via `$Column$`, foreign keys via
  `$FK(UID_X).Column$` — follow the exact syntax of comparable built-in templates.
- Scripts: `Public Function CCC_…`/`Public Sub CCC_…`, explicit parameter and return types, no hard-coded UIDs
  (use config parameters `CCC\...`), no secrets, handle `Nothing`/empty values.
- Keep templates short and side-effect free; put logic in a `CCC_` script and call it from the template.
- Processes: generating condition as narrow as possible (avoid generating a job for every update), idempotent steps,
  meaningful process/step names, error handling on each step.

## Testing
- **Script library function** (after the operator has applied + compiled): call it from PowerShell —
  `Invoke-IdentityManagerScript -Name 'CCC_X' -Parameters @(...)`. Classified *Write* by `oneidentity-im-posh`:
  show the call and wait for OK, even if the script is read-only by design.
- **Template**: create the object in memory without saving and read the computed column, e.g.
  `$p = New-Person -FirstName 'Test' -LastName 'Template' -Unsaved; $p.CentralAccount` — verify on the first use
  that templates fire on unsaved entities in this version; otherwise test in the Object Browser / Manager.
- **Process**: trigger on a test object (marker in `## Ambiente` of CLAUDE.md), then follow it in **Job Queue Info**;
  never test on real data, and never in an environment classified as production.
- Write the expected result in the test plan **before** running the test.

## Review checklist (use for every change)
1. CCC_ prefix everywhere, no built-in object changed without a documented original.
2. Null/empty handling, no hard-coded UIDs, no secrets, no SQL string concatenation with user data.
3. Template: no heavy queries, no recursion with other templates on the same object.
4. Process: generating condition precise, parameters correct, no infinite loop (process updating the column that triggers it).
5. Compile impact noted (Database Compiler needed), change label recorded in `oim/designer/CHANGELOG.md`.