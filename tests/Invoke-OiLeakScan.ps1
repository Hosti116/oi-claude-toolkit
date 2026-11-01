#Requires -Version 7.6
<#
.SYNOPSIS
Scans a repository (files and git history) for secrets, hostnames, UIDs, customer names and environment facts.

.DESCRIPTION
Exit code 1 when a finding is not covered by the allowlist. Matched values are never printed for the Secret and
Customer categories. Customer names come from the environment variable OI_SCAN_TERMS (separated by ;) so they
never end up in a file; without it the report says the customer check is partial.

.PARAMETER Allowlist
JSON array of { "path": "<wildcard>", "pattern": "<regex on the line>", "reason": "<why it is fine>" }.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$Allowlist
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Rules = @(
    @{ Category = 'Secret'; Regex = '(?i)(password|passwd|pwd|secret|token|api[_-]?key)[''"]?\s*[:=]\s*[''"][^''"\s$<{%]{6,}[''"]' }
    @{ Category = 'Secret'; Regex = '(?i)Password=[^;$\s"''<{`(]{4,}' }
    @{ Category = 'Secret'; Regex = '-----BEGIN [A-Z ]*PRIVATE KEY' }
    @{ Category = 'Secret'; Regex = '\b(ghp_[A-Za-z0-9]{20,}|github_pat_\w{20,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9-]{20,})\b' }
    @{ Category = 'Secret'; Regex = 'Bearer\s+[A-Za-z0-9._-]{20,}' }
    @{ Category = 'Secret'; Regex = 'UnsecureP@ss' }
    @{ Category = 'Host'; Regex = '(?i)\b(oim|spp|sps)\d{2}\b' }
    @{ Category = 'Host'; Regex = '(?i)\b[a-z0-9-]+\.(local|lan|corp|internal|intranet)\b' }
    @{ Category = 'Host'; Regex = '\b(10\.\d{1,3}|172\.(1[6-9]|2\d|3[01])|192\.168)\.\d{1,3}\.\d{1,3}\b' }
    @{ Category = 'Host'; Regex = '\\\\[A-Za-z0-9-]+\\[A-Za-z0-9$]' }
    @{ Category = 'UID'; Regex = '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b' }
    @{ Category = 'Customer'; Regex = '(?i)\b(customers?|client[ei]|previous project|progetto precedente)\b' }
    @{ Category = 'EnvFact'; Regex = '(?i)\blab\b|viadmin|claude_ro|Hosti116|OI-Workspace|973523|Fakedata|Users[\\/]Administrator' }
)
$HiddenCategories = 'Secret', 'Customer'
$SkippedFiles = 'THIRD_PARTY_LICENSES/*', 'tests/Invoke-OiLeakScan.ps1', 'tests/leakscan-allowlist.json'

function Test-Skipped([string]$Relative) {
    foreach ($pattern in $SkippedFiles) { if ($Relative -like $pattern) { return $true } }
    return $false
}

function Get-LineFinding([string]$Where, [string]$File, [int]$LineNumber, [string]$Line, [object[]]$AllRules) {
    foreach ($rule in $AllRules) {
        $match = [regex]::Match($Line, $rule.Regex)
        if (-not $match.Success) { continue }
        $shown = if ($rule.Category -in $HiddenCategories) { '***' } else { $match.Value }
        [PSCustomObject]@{ Where = $Where; File = $File; Line = $LineNumber; Category = $rule.Category; Value = $shown; Text = $Line }
    }
}

function Get-CustomerRule {
    $terms = @(($env:OI_SCAN_TERMS -split ';') | Where-Object { $_.Trim() })
    foreach ($term in $terms) { @{ Category = 'Customer'; Regex = "(?i)$([regex]::Escape($term.Trim()))" } }
}

function Get-RepositoryFile([string]$Root) {
    # A scan that read nothing must never look like a clean scan.
    $files = @(git -C $Root ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw "git cannot read $Root (exit code $LASTEXITCODE): nothing was scanned." }
    if (-not $files) { throw "No files found in ${Root}: nothing was scanned." }
    return $files
}

function Get-WorkingTreeFinding([string]$Root, [object[]]$AllRules) {
    foreach ($relative in Get-RepositoryFile $Root) {
        if (Test-Skipped $relative) { continue }
        $full = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        if ((Get-Content -LiteralPath $full -AsByteStream -TotalCount 4096) -contains 0) { continue }
        $number = 0
        foreach ($line in [IO.File]::ReadLines($full)) {
            $number++
            Get-LineFinding 'file' $relative $number $line $AllRules
        }
    }
}

function Get-HistoryFinding([string]$Root, [object[]]$AllRules) {
    $file = ''
    $null = git -C $Root rev-parse --verify --quiet HEAD
    if ($LASTEXITCODE -ne 0) { return }   # no commits yet: there is no history to read
    $history = @(git -C $Root log --all -p --no-color --format=)
    if ($LASTEXITCODE -ne 0) { throw "git log failed in $Root (exit code $LASTEXITCODE): history was not scanned." }
    foreach ($line in $history) {
        if ($line -match '^\+\+\+ b/(.+)$') { $file = $Matches[1]; continue }
        if ($line -notmatch '^\+' -or (Test-Skipped $file)) { continue }
        Get-LineFinding 'history' $file 0 $line.Substring(1) $AllRules
    }
}

function Test-Allowed([object]$Finding, [object[]]$Entries) {
    foreach ($entry in $Entries) {
        if ($Finding.File -like $entry.path -and $Finding.Text -match $entry.pattern) { return $true }
    }
    return $false
}

$root = (Resolve-Path -LiteralPath $Path).Path
$customerRules = @(Get-CustomerRule)
$allRules = $Rules + $customerRules
$entries = if ($Allowlist) { @(Get-Content -LiteralPath $Allowlist -Raw | ConvertFrom-Json) } else { @() }

$findings = @(Get-WorkingTreeFinding $root $allRules) + @(Get-HistoryFinding $root $allRules)
$open = @($findings | Where-Object { -not (Test-Allowed $_ $entries) })

$summary = [PSCustomObject]@{
    Repository    = Split-Path -Leaf $root
    Findings      = $findings.Count
    Allowlisted   = $findings.Count - $open.Count
    Open          = $open.Count
    CustomerTerms = if ($customerRules) { "$($customerRules.Count) term(s) checked" } else { 'PARTIAL: OI_SCAN_TERMS not set' }
}
$summary | Format-List | Out-String | Write-Host
foreach ($category in $findings | Group-Object Category) {
    $openCount = @($category.Group | Where-Object { -not (Test-Allowed $_ $entries) }).Count
    Write-Host ("{0,-10} total {1,5}   open {2,5}" -f $category.Name, $category.Count, $openCount)
}
$open | Select-Object Where, File, Line, Category, Value
if ($open.Count) { exit 1 }
