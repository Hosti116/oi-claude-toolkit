---
name: oneidentity-im-posh
description: Use when writing, reviewing or running PowerShell against One Identity Manager 10.0 LTS with the PSIdentityManagerUtils module (vendor/IdentityManager.PoSh) — reading/creating/updating/deleting entities (Person, Department, UNSAccount…), triggering events, running object methods or Identity Manager scripts, bulk changes with UnitOfWork, or generating demo data.
---

# One Identity Manager via PowerShell (PSIdentityManagerUtils)

## Platform facts
- Identity Manager **10.0 LTS** (.NET 9) → run ONLY with **PowerShell 7.6+**:
  `pwsh -NoProfile -File <script>`. Never `powershell.exe` (5.1): it fails with
  `Cannot find type [QBM.AppServer.Client.ServiceClientFactory]`.
- Module source: `vendor/IdentityManager.PoSh/PSIdentityManagerUtils` (Public/ = exported functions).
  When unsure how a function behaves, READ its file in `Public/` instead of guessing.
- Cmdlet reference (incl. generated typed wrappers like `Get-Person`):
  `docs/reference/oim-posh-cmdlets.md`. Grep it before using any parameter.
- Product DLLs are loaded from the installation folder (`Oim.ProductPath` in `oi-env.psd1`) — never copy them into the repo.

## Connecting
Always dot-source the workspace helper; never put credentials in scripts:
```powershell
#Requires -Version 7.6
. (Join-Path $PSScriptRoot '..\..\tools\Connect-OIM.ps1')   # adjust relative path
try {
    # ... work ...
} finally {
    Remove-IdentityManagerSession
}
```
- Connection goes through the **Application Server** (recommended by the module).
- Credentials come from SecretManagement (entry `Oim.SecretName` in `oi-env.psd1`) inside `Connect-OIM.ps1`.
- Only one session per prefix: dot-sourcing `Connect-OIM.ps1` twice in the same shell throws
  "There is already a connection with prefix ''". Reuse the session or call `Remove-IdentityManagerSession` first.
- Typed wrappers are generated at connect time only for modules in `-ModulesToAdd` (default `QER`).
  If `Get-<Table>` does not exist, the table's module was not added — add it (e.g. `'QER','ADS','RMB'`)
  rather than falling back to raw SQL.

## Safety classification (MANDATORY)
| Class | Functions | Rule |
|---|---|---|
| Read | `Get-Entity`, `Get-<Table>`, `Get-TableCount`, `Get-ConfigParm`, `Get-ImEvent`, `Get-EntityMethod`, `Get-Authentifier`, `Get-InstalledIdentityManagerModule`, `Get-EntityColumnValue` | May run after showing the script |
| Write | `New-*`, `Set-*`, `Remove-*`, `Set-EntityColumnValue`, `Add-UnitOfWorkEntity` + `Save-UnitOfWork`, `Invoke-ImEvent`, `Invoke-EntityMethod`, `Invoke-IdentityManagerScript` | Write the script to `oim/scripts/`, show it, wait for explicit OK |
| Forbidden | Direct `UPDATE/INSERT/DELETE` on the OneIM SQL DB; using the module as a transport tool between DBs | Never |

Write scripts must support a dry run: add a `[switch]$WhatIf`-style parameter (or `[CmdletBinding(SupportsShouldProcess)]`)
that only prints what would change.

## Core patterns

### Read
```powershell
Get-TableCount -Name 'Person' -Filter "IsInActive = 0"
Get-Person -ResultSize 10 | Select-Object Display, CentralAccount
Get-Entity -Type 'Person' -Filter "LastName = 'Rossi'" -ResultSize 50
Get-Person -Identity '<UID or XObjectKey>'
Get-Department -FilterClause "DepartmentName like 'IT%'"
```
- Default `-ResultSize` is **1000**: for counts use `Get-TableCount`, for large sets set `-ResultSize` explicitly.
- `-Filter` / `-FilterClause` take a SQL WHERE clause: always quote string values, never interpolate untrusted input.

### Create
```powershell
$p = New-Person -FirstName 'Mario' -LastName 'Rossi'                 # typed
$p = New-Entity -Type 'Person' -Properties @{ FirstName='Mario'; LastName='Rossi' }   # generic
```
`Get-Help New-Person`: `[<param>]` = mandatory, `[[<param>]]` = optional.

### Update
```powershell
Get-Department -DepartmentName 'D1' | Set-Department -UID_PersonHead $manager   # FK by entity or UID
Set-Entity -Type Person -Identity $uid -Properties @{ LastName = 'Bianchi' }
```
- Assigning a property on a loaded entity (`$p.LastName = 'X'`) changes it **in memory only**;
  persist with `Set-*`/`Set-Entity` or a UnitOfWork.

### Bulk changes → UnitOfWork
```powershell
$uow = New-UnitOfWork
foreach ($p in Get-Person -FilterClause "UID_Department is null" -ResultSize 500) {
    $p.CustomProperty01 = 'no-dept'
    Add-UnitOfWorkEntity -UnitOfWork $uow -Entity $p
}
Save-UnitOfWork -UnitOfWork $uow     # single commit
```

### Delete
```powershell
Remove-Person -Identity $uid                     # marks for deletion (delete delay)
Remove-Person -Identity $uid -IgnoreDeleteDelay  # immediate — needs explicit OK
```

### Events, methods, scripts
```powershell
Get-ImEvent -Entity $p                          # list events first
Invoke-ImEvent -Entity $p -EventName 'CHECK_EXITDATE' -EventParameters @{}
Get-EntityMethod -Entity $p
Invoke-EntityMethod -Entity $p -MethodName '<name>' -Parameters @()
Invoke-IdentityManagerScript -Name 'QBM_GetTempPath'
```
Always list available events/methods before invoking; never guess names.

### Session variables
Remove any custom session variable you set, otherwise wrong processes may be generated:
```powershell
$s = $Global:imsessions[$Global:imsessions.Keys[0]].Session
$s.Variables.Put('MyVar','value'); try { ... } finally { $s.Variables.Remove('MyVar') }
```

## Demo data
`vendor/IdentityManager.PoSh/Contrib/FillDbWithFakeData.ps1` creates ~100 identities with hierarchy
(seeded, reproducible). It WRITES to the DB: the user runs it, after a DB backup, and **only** when `## Ambiente`
of CLAUDE.md says `Tipo: LAB`, `TEST` or `DEMO`. Missing or any other value = production: never use it.

## Conventions
- Custom objects/columns: prefix `CCC_`.
- Scripts live in `oim/scripts/<area>/<Verb>-<Noun>.ps1`, start with `#Requires -Version 7.6`,
  `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, and close the session in `finally`.
- After changing the schema (new CCC_ columns/tables), regenerate `docs/reference/oim-posh-cmdlets.md`.
- Report scripts return objects (`[PSCustomObject]`), never `Format-Table`/`Format-List`/`Write-Host` for data:
  the caller decides the format (table, CSV, pipeline).