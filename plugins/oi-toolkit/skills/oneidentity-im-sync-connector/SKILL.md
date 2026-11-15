---
name: oneidentity-im-sync-connector
description: Use when designing, generating, testing or debugging a One Identity Manager 10.0 Synchronization Editor connector — especially the generic PowerShell connector (PowershellConnectorDefinition XML) for REST/SaaS targets such as ServiceNow — and when planning the sync project around it (schema classes, mappings, matching, workflows, scope, provisioning).
---

# One Identity Manager — Synchronization connectors (PowerShell connector)

## Evidence levels (use them in every answer and every README)
**[VERIFICATO]** proven in an Identity Manager wizard/sync or executed for real ·
**[DOC]** written in official documentation, not proven here ·
**[DEDOTTO]** reasoning, not confirmed. Always say which level a claim has, and separate
"tested in OIM" from "tested offline with the mock".

## Sources (cite `file:line`)
| Source | Path | Use |
|---|---|---|
| PowerShell connector guide (official) | `vendor/IdentityManager.PoSh-Connector-Guide/README.md` | XML format, command sequences, MVP members, best practices, MS Graph sample (~lines 1106–1900) |
| Connector generators | `sync/connectors/ServiceNow/`, `sync/connectors/ServiceNowModule/` | Reference implementations; read their README first |
| Synchronization documentation | docs.oneidentity.com, version from `## Ambiente` of CLAUDE.md | Sync project, mapping, matching, workflows, scope. Cite the page and mark it **[DOC]** |
Grep first, then read with offset/limit (the files are long).

## Verified rules from previous projects (re-confirm on 10.0 the first time)
- **[VERIFICATO]** The wizard rejects `Description` on `<Class>` / `<Property>` and rejects `IsAutofill`, although the README
  documents them. `Description` is accepted on `<PowershellConnectorDefinition>` and `<ConnectionParameter>`.
  Put descriptions in XML comments. General rule: every README attribute is "documented, to be confirmed".
- **[VERIFICATO]** Key property: `DataType="String" IsMandatory="true" IsUniqueKey="true" AccessConstraint="ReadOnly"`.
  **[DOC]** every Class needs ≥1 `IsUniqueKey` and ≥1 `IsDisplay`; every command referenced must be a Custom/Predefined command.
- **[VERIFICATO]** README layout with `Import-Module` in the Connect sequence + module functions in `PredefinedCommands`
  **fails in the wizard** (`The term 'Connect-XXX' is not recognized`, `PageShell03_ConnectionTargetView`).
  → Put **all code inline as `CustomCommands`**, keep `PredefinedCommands` empty.
- Passwords: `ConnectionParameter IsSensibleData="true"`, passed with `ConversionMethod="ToSecureString"`.
- Reading: the `ListingCommand` must return **every** property of the class with real values.
  **[VERIFICATO in OIM 9.2]** matching compares the listing values; the documented per-object reload
  (`vendor/IdentityManager.PoSh-Connector-Guide/README.md:646`) does not happen before matching: a property absent
  from the listing → `No Property x found` (`PoshSystemObjectDataExtensions.GetPathItemFromPSObject`); present but
  null → matching rules on it silently never match. Keep the `CommandSequence` reload by key for single-object reads.
- After regenerating the XML, re-run "Edit connection" in the Synchronization Editor: the project keeps the old
  definition until then (and commit to the database if the sync runs on the Job server) **[DEDOTTO]**.
- Update with `Condition="ModificationExists"`; `ModifiedBy` Insert on New, Update on Set; `IsRevision="true"` on the last-modified field.
- Command names with a unique prefix: `Verb-OneIM<System><Noun>`.

## PowerShell inside the connector
- Everything on the **output stream** is consumed by the connector: Set/Remove/Connect return nothing (`$null = ...`).
- Logging: `Write-Host` (info), `Write-Verbose`, `Write-Warning` → NLog. `Write-Error` fails the call.
- Shared state in `$global:` variables (e.g. auth header).
- **Engine version = Identity Manager version**: ≤ 9.2 → Windows PowerShell 5.1 (.NET Framework);
  9.3 / 10.x → PowerShell 7 (.NET 8/9). Read the installed version from `## Ambiente` of CLAUDE.md (confirm once with a CustomCommand that
  `Write-Host`s `$PSVersionTable.PSVersion` during Connect, then mark [VERIFICATO]).
- **Connectors must run on both engines** (environments on mixed versions). Dual-engine rules:
  - HTTP error body: try `$_.ErrorDetails.Message` first; fall back to `$_.Exception.Response.GetResponseStream()`
    only if that method exists (5.1). Status: `[int]$_.Exception.Response.StatusCode` with a null check.
  - SecureString → text via `Marshal.SecureStringToBSTR` + `ZeroFreeBSTR` in `finally` (works on both).
  - No `-AsHashtable`; iterate `.PSObject.Properties`. URL encoding with `[uri]::EscapeDataString()`.
  - Files UTF-8 **with BOM**; bodies as `[Text.Encoding]::UTF8.GetBytes($json)` + `charset=utf-8`;
    keep `-UseBasicParsing` and forcing TLS 1.2 (harmless on 7).
  - Never name parameters like automatic variables (`input`, `args`, `host`, `error`, `matches`, `event`).
- **Verify on both engines**: `powershell.exe -NoProfile -File Verify-<System>Connector.ps1` **and**
  `pwsh -NoProfile -File Verify-<System>Connector.ps1` must both pass before any wizard test.
- Wizard rules marked [VERIFICATO] above were proven on **9.2**: re-confirm on 10.0 and note the version next to the tag.

## Architecture: generator, not hand-edited XML
Per connector, under `sync/connectors/<System>/`:
```
New-<System>ConnectorXml.ps1   ← source of truth: reads the target schema (online, cached) and generates the XML
<System>Schema.json            ← schema cache (offline regeneration with -Offline)
<System>Connector.xml          ← GENERATED, never edited by hand (.bak before overwrite)
Verify-<System>Connector.ps1   ← offline: HttpListener mock (401/404/429/paging/POST/PATCH/DELETE) + static checks
Test-<System>Connector.ps1     ← smoke test against the real (non-prod) instance; writes only with -WriteTests
README.md                      ← classes, filters, decisions, evidence level of each, open points
```
Reference implementation of the pattern: `sync/connectors/ServiceNow/` (Table API: `sys_db_object`/`sys_dictionary`
for schema, offset paging with `ORDERBYsys_id`, retry with backoff on 429/5xx, type mapping, `Defaults` per class,
`ReferenceTarget` generation). For a new REST system only schema discovery and URL format change.

Tests load the functions **from the generated XML**, so they test what OIM runs:
```powershell
$def = [xml](Get-Content $xml -Raw -Encoding UTF8)
foreach ($cc in $def.PowershellConnectorDefinition.Initialization.CustomCommands.CustomCommand) {
    Set-Item "function:global:$($cc.Name)" ([scriptblock]::Create($cc.'#cdata-section')) }
```
Static checks on every generation: XML well-formed; every CDATA parses with
`[Management.Automation.Language.Parser]::ParseInput` without errors; every `Command`/`CommandResultOf`/`ToCommand` exists;
every `Map Parameter=` is a real parameter of its command.

## Rollout order (never skip a step)
1. offline mock + static checks → 2. smoke test read-only against the non-prod target → 3. load XML in the
Synchronization Editor wizard (operator; wizard errors arrive as screenshots — the class name in the stack, e.g.
`PageShell03_ConnectionTargetView`, tells the phase) → 4. **read-only sync** into a non-production environment (no provisioning, simulate first)
→ 5. only then provisioning/writes, one class at a time.

## Sync project pitfalls (seen in OIM 9.2)
- **[VERIFICATO]** "Key resolution" virtual properties need a unique search property. On a non-unique one (e.g. a
  person's city) the engine warns `does not have unique data ... is ignored. This results in empty references` and
  maps an empty value; with a connector that clears on `$null`, provisioning empties the target field. To read a
  value of a referenced object use an **Object reference** property (route, e.g. `UID_Person.City`).
- **[VERIFICATO]** Ad hoc provisioning (`AdHocProjection`) transfers only the changes in `CausingEntityPatch`
  (`DPR_WrapObjectForProjection(Entity)`). A process fired by a dedicated event with no column change ends `Success`
  with no modifications; values read from other tables are never in the patch. Fix with the job parameter
  `ForceSyncOf`: comma-delimited `[<table>.]<column>` of **source columns** (not virtual property names, not bare
  table names — `Person,Department` forced nothing):
  - columns of the account table without prefix (`FirstName`); other tables as `Table.Column`, also for multi-hop
    routes: list the final table and column (`Department.CustomProperty08` for
    `UID_Person.UID_Department.CustomProperty08`) **[VERIFICATO]** up to 3 hops;
  - script properties that use `$UID_Person$` are forced by listing `UID_Person` **[VERIFICATO]**; put it last;
  - write the value one entry per line, and test one entry first:
    ```vb
    Value = String.Join(",", New String() { _
        "FirstName", _
        "Person.City", _
        "Department.CustomProperty08", _
        "UID_Person" _
    })
    ```
    **[VERIFICATO]** a single long line containing an invalid entry (a table not reachable by FK) silently ignored
    every entry after a certain point; cause not isolated (invalid entry or invisible pasted character) **[DEDOTTO]**.
- **[DEDOTTO]** Values that only another table points to (the person's AD account, the manager's account) are not
  reachable by an FK route: use a script property and force it with `UID_Person`.
- **[VERIFICATO]** Forced properties are rewritten on every ad hoc run: an empty OIM value clears the target field.
  **[DEDOTTO]** A script property must not `catch` and return an empty string: a transient query error would clear
  target data. Let the exception fail the job.
- Debugging ad hoc: the provisioning log (journal) lists the properties written per object; `Success` with an empty
  "Details" section means nothing was in the patch, not a connector failure.

## Safety
- Never point a connector or test at a production target. Credentials only via connection parameters / SecretManagement,
  never in files, caches or logs. Never decode credentials found in files.
- Creating/changing the sync project in the database is done by the operator in the Synchronization Editor.