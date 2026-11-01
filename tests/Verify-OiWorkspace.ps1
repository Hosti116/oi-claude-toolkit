#Requires -Version 7.6
# Offline checks of the workspace scripts: no network, no submodules, everything in a temporary folder.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolkit = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $toolkit 'lib/OiWorkspace.psm1') -Force
$script:failures = 0

function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok   $Name" } else { Write-Host "FAIL $Name"; $script:failures++ }
}

$temp = Join-Path ([IO.Path]::GetTempPath()) "oi-verify-$([guid]::NewGuid().ToString('N'))"
$newScript = Join-Path $toolkit 'New-OiWorkspace.ps1'
$updateScript = Join-Path $toolkit 'Update-OiWorkspace.ps1'
$repo = 'example-owner/oi-claude-toolkit'
try {
    # Arrange + Act: a new workspace with the default type
    $ws = Join-Path $temp 'prod'
    & $newScript -Path $ws -MarketplaceRepo $repo -SkipSubmodules 6>$null
    $claude = Get-Content -LiteralPath (Join-Path $ws 'CLAUDE.md') -Raw
    Assert-True ($claude -match 'Tipo: PRODUZIONE') 'default type is production'
    Assert-True ($claude -match '@\.claude/oi-shared\.md') 'CLAUDE.md imports the shared rules'
    Assert-True ($claude -notmatch '__[A-Z_]+__') 'no template token left in CLAUDE.md'
    Assert-True (Test-Path (Join-Path $ws '.claude/rules/coding-style.md')) 'rules copied'
    Assert-True (Test-Path (Join-Path $ws 'tools/Connect-OIM.ps1')) 'tools copied'
    Assert-True (-not (Test-Path (Join-Path $ws '.claude/skills'))) 'skills come from the plugin, not from files'

    $settings = Get-Content -LiteralPath (Join-Path $ws '.claude/settings.json') -Raw | ConvertFrom-Json -AsHashtable
    Assert-True ($settings.enabledPlugins['oi-toolkit@oi-claude-toolkit'] -eq $true) 'plugin enabled'
    Assert-True ($settings.extraKnownMarketplaces['oi-claude-toolkit'].source.repo -eq $repo) 'marketplace repo written'
    Assert-True ($settings.extraKnownMarketplaces['oi-claude-toolkit'].source.ref -eq 'v1.0.0') 'ref pinned to the toolkit version'
    Assert-True ($settings.permissions.deny -contains 'Read(./secrets/**)') 'deny rules present'

    $lab = Join-Path $temp 'lab'
    & $newScript -Path $lab -MarketplaceRepo $repo -EnvironmentType LAB -SkipSubmodules 6>$null
    Assert-True ((Get-Content -LiteralPath (Join-Path $lab 'CLAUDE.md') -Raw) -match 'Tipo: LAB') 'explicit type written'

    # New never overwrites
    $marker = 'edited by the operator'
    Set-Content -LiteralPath (Join-Path $ws 'CLAUDE.md') -Value $marker
    & $newScript -Path $ws -MarketplaceRepo $repo -SkipSubmodules 6>$null
    Assert-True ((Get-Content -LiteralPath (Join-Path $ws 'CLAUDE.md') -Raw).Trim() -eq $marker) 'second New keeps CLAUDE.md'

    # Update keeps local changes and repairs nothing silently
    $rule = Join-Path $ws '.claude/rules/testing.md'
    Set-Content -LiteralPath $rule -Value $marker
    $seed = Join-Path $ws 'mkdocs.yml'
    Set-Content -LiteralPath $seed -Value $marker
    $report = @(& $updateScript -Path $ws)
    Assert-True ((Get-Content -LiteralPath $rule -Raw).Trim() -eq $marker) 'Update keeps a locally changed rule'
    Assert-True (@($report | Where-Object { $_.Action -eq 'LocalChange' -and $_.Target -eq '.claude/rules/testing.md' }).Count -eq 1) 'Update reports the local change'
    Assert-True ((Get-Content -LiteralPath $seed -Raw).Trim() -eq $marker) 'Update never touches seed files'

    # Update permissions: rules added by the workspace survive
    $settingsPath = Join-Path $ws '.claude/settings.json'
    $custom = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
    $custom.permissions.deny = @($custom.permissions.deny) + 'Read(./local-only/**)'
    $custom.permissions.defaultMode = 'plan'
    $custom | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $settingsPath
    $null = & $updateScript -Path $ws -Ref 'v9.9.9'
    $after = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
    Assert-True ($after.permissions.deny -contains 'Read(./local-only/**)') 'Update keeps workspace deny rules'
    Assert-True ($after.permissions.deny -contains 'Read(./secrets/**)') 'Update keeps base deny rules'
    Assert-True ($after.permissions.defaultMode -eq 'plan') 'Update keeps defaultMode'
    Assert-True ($after.extraKnownMarketplaces['oi-claude-toolkit'].source.ref -eq 'v9.9.9') 'Update moves the ref'

    # DryRun writes nothing
    Remove-Item -LiteralPath (Join-Path $lab 'tools/Get-OiEnv.ps1')
    $before = Get-OiContentHash (Join-Path $lab '.claude/settings.json')
    $dry = @(& $updateScript -Path $lab -Ref 'v0.0.1' -DryRun)
    Assert-True (-not (Test-Path (Join-Path $lab 'tools/Get-OiEnv.ps1'))) 'DryRun creates no file'
    Assert-True ((Get-OiContentHash (Join-Path $lab '.claude/settings.json')) -eq $before) 'DryRun keeps settings'
    Assert-True (@($dry | Where-Object { $_.Action -eq 'Create' }).Count -eq 1) 'DryRun reports the missing file'

    # Decision table
    Assert-True ((Get-OiFileAction -Mode managed -WorkspaceHash '' -LockHash '' -SourceHash 'a') -eq 'Create') 'action: missing file'
    Assert-True ((Get-OiFileAction -Mode seed -WorkspaceHash 'x' -LockHash '' -SourceHash 'a') -eq 'Keep') 'action: seed exists'
    Assert-True ((Get-OiFileAction -Mode managed -WorkspaceHash 'a' -LockHash '' -SourceHash 'a') -eq 'Unchanged') 'action: same content, no lock'
    Assert-True ((Get-OiFileAction -Mode managed -WorkspaceHash 'b' -LockHash 'b' -SourceHash 'a') -eq 'Update') 'action: untouched since last sync'
    Assert-True ((Get-OiFileAction -Mode managed -WorkspaceHash 'c' -LockHash 'b' -SourceHash 'a') -eq 'LocalChange') 'action: changed locally'
    Assert-True ((Get-OiFileAction -Mode managed -WorkspaceHash 'c' -LockHash '' -SourceHash 'a') -eq 'LocalChange') 'action: differs, no lock'

    # Immutability of the settings merge
    $base = @{ permissions = @{ deny = @('a') } }
    $existing = @{ permissions = @{ deny = @('b') } }
    $null = Get-OiMergedSettings -Base $base -Existing $existing -MarketplaceName 'm' -PluginId 'p@m' -Repo 'o/r' -Ref 'v1'
    Assert-True ($existing.permissions.deny.Count -eq 1 -and -not $existing.ContainsKey('enabledPlugins')) 'merge leaves its input untouched'

    # Get-OiEnv
    $getEnv = Join-Path $ws 'tools/Get-OiEnv.ps1'
    $emptyEnvFails = $false
    try { $null = & $getEnv -Require 'Oim.AppServer' } catch { $emptyEnvFails = $_.Exception.Message -match 'Oim\.AppServer' }
    Assert-True $emptyEnvFails 'Get-OiEnv stops on an empty required value'
    $noFileFails = $false
    Remove-Item -LiteralPath (Join-Path $ws 'oi-env.psd1')
    try { $null = & $getEnv } catch { $noFileFails = $_.Exception.Message -match 'oi-env\.psd1' }
    Assert-True $noFileFails 'Get-OiEnv stops without oi-env.psd1'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

if ($script:failures) { Write-Host "$script:failures check(s) FAILED"; exit 1 }
Write-Host 'All workspace checks passed.'
