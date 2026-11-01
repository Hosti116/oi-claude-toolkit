#Requires -Version 7.6
# Static checks of the plugin and of the rules the toolkit promises. No network.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolkit = Split-Path -Parent $PSScriptRoot
$plugin = Join-Path $toolkit 'plugins/oi-toolkit'
$script:failures = 0

function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok   $Name" } else { Write-Host "FAIL $Name"; $script:failures++ }
}

$manifest = Get-Content -LiteralPath (Join-Path $plugin '.claude-plugin/plugin.json') -Raw | ConvertFrom-Json
$marketplace = Get-Content -LiteralPath (Join-Path $toolkit '.claude-plugin/marketplace.json') -Raw | ConvertFrom-Json
Assert-True ($manifest.name -eq 'oi-toolkit') 'plugin name'
Assert-True ($manifest.version -match '^\d+\.\d+\.\d+$') 'plugin version is explicit'
Assert-True ($marketplace.plugins[0].source -eq './plugins/oi-toolkit') 'marketplace source is relative to the root'

# A tagged commit must carry the matching version: users receive nothing otherwise.
$tags = @(git -C $toolkit tag --points-at HEAD 2>$null | Where-Object { $_ -match '^v\d' })
foreach ($tag in $tags) { Assert-True ($tag -eq "v$($manifest.version)") "tag $tag matches plugin version" }

# Every skill starts with its frontmatter and its name matches the folder
foreach ($skill in Get-ChildItem -LiteralPath (Join-Path $plugin 'skills') -Directory) {
    $lines = @(Get-Content -LiteralPath (Join-Path $skill.FullName 'SKILL.md') -TotalCount 2)
    Assert-True ($lines[0] -eq '---' -and $lines[1] -eq "name: $($skill.Name)") "skill $($skill.Name): frontmatter at line 1"
}

# Plugin agents: fields Claude Code ignores in a plugin must not be relied upon
$ignoredField = '^(permissionMode|hooks|mcpServers|initialPrompt):'
foreach ($agent in Get-ChildItem -LiteralPath (Join-Path $plugin 'agents') -File) {
    Assert-True (-not (Select-String -LiteralPath $agent.FullName -Pattern $ignoredField -Quiet)) "agent $($agent.BaseName): no ignored field"
}

# No absolute paths in the plugin (home-relative ~/.claude is fine: it is the user's Claude folder)
$absolute = '(?<![\w/~.])(?:[A-Za-z]:[\\/](?!\\|/)|/home/\w|/c/\w)'
$allowedAbsolute = @{
    'skills/oneidentity-im-posh/SKILL.md' = 'C:\\Program Files'
}
$hits = foreach ($file in Get-ChildItem -LiteralPath $plugin -Recurse -File -Include *.md, *.json) {
    $relative = [IO.Path]::GetRelativePath($plugin, $file.FullName).Replace('\', '/')
    foreach ($match in Select-String -LiteralPath $file.FullName -Pattern $absolute) {
        $allowed = $allowedAbsolute.ContainsKey($relative) -and $match.Line -match $allowedAbsolute[$relative]
        if (-not $allowed) { "${relative}:$($match.LineNumber)" }
    }
}
Assert-True (@($hits).Count -eq 0) "no absolute path in the plugin $(@($hits) -join ', ')"

# Production gate of spp-custom-platform
$spp = Get-Content -LiteralPath (Join-Path $plugin 'skills/spp-custom-platform/SKILL.md') -Raw
Assert-True ($spp -match '## Production gate') 'spp: production gate present'
Assert-True ($spp -match 'no `## Ambiente` section') 'spp: missing section means production'
Assert-True ($spp -notmatch 'Junction|non-production affirmed') 'spp: no junction, no affirmation of its own'
foreach ($name in 'target-probing', 'strategy-selection', 'script-authoring', 'safeguard-ps-operations', 'task-log-analysis') {
    Assert-True ($spp.Contains("vendor/SafeguardCustomPlatform/.agents/skills/$name/SKILL.md")) "spp: reads $name from the submodule"
}

# Permission rules: Claude Code takes a * before a trailing :* literally, so such a rule never matches
$baseSettings = Get-Content -LiteralPath (Join-Path $toolkit 'project-files/settings.base.json') -Raw | ConvertFrom-Json
$brokenRules = @(@($baseSettings.permissions.ask) + @($baseSettings.permissions.deny) | Where-Object { $_ -match '\*:\*\)$' })
Assert-True ($brokenRules.Count -eq 0) "no rule mixes * with :* $($brokenRules -join ', ')"

# Third-party attribution
$notice = Get-Content -LiteralPath (Join-Path $toolkit 'NOTICE') -Raw
Assert-True ($notice -match 'Affaan Mustafa') 'NOTICE credits ECC'
Assert-True (Test-Path -LiteralPath (Join-Path $toolkit 'THIRD_PARTY_LICENSES/ECC-MIT.txt')) 'MIT text shipped'
foreach ($line in ($notice -split '\r?\n' | Where-Object { $_ -match '^- ' })) {
    $path = ($line -replace '^- ', '') -replace ' \(.*$', ''
    Assert-True (Test-Path -LiteralPath (Join-Path $toolkit $path)) "NOTICE entry exists: $path"
}

if ($script:failures) { Write-Host "$script:failures check(s) FAILED"; exit 1 }
Write-Host 'All toolkit checks passed.'
