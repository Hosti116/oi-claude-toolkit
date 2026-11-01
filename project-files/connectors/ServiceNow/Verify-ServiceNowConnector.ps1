# module layout: .\Verify-ServiceNowConnector.ps1 -XmlFile ServiceNowConnector.Module.xml
param([string]$XmlFile = "ServiceNowConnector.xml")
$ErrorActionPreference = "Stop"
$port = 18089
$ok = 0; $fail = 0
function Check($name, $cond) { if ($cond) { $script:ok++; "PASS $name" } else { $script:fail++; "FAIL $name" } }
"Engine: PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)), XML: $XmlFile"
# ServiceNow's JSON error body as sent by the mock: must reach the exception message on both engines
# (the status text alone, e.g. "404 (Not Found)" on 7, must not satisfy the check)
function Test-ErrorBody($message, $text) { $message -match ('"message":\s*"' + [regex]::Escape($text) + '"') }

# --- mock ServiceNow Table API in a background runspace ---
$mock = {
    param($port)
    Add-Type -AssemblyName System.Web   # HttpUtility is not loaded by default in Windows PowerShell 5.1
    $store = [ordered]@{}
    1..25 | ForEach-Object {
        $id = ('{0:x32}' -f $_)
        $store[$id] = @{ sys_id=$id; name="Dept $_"; id="D$_"; description=""; parent=""; dept_head=""; head_count="$_"; primary_contact=""; company=""; business_unit=""; sys_updated_on="2026-01-02 03:04:05" }
    }
    $l = [Net.HttpListener]::new(); $l.Prefixes.Add("http://localhost:$port/"); $l.Start()
    $throttled = $false
    while ($true) {
        $c = $l.GetContext(); $rq = $c.Request; $rs = $c.Response
        $send = {
            param($code, $obj)
            $rs.StatusCode = $code
            if ($null -ne $obj) { $b = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 5 -Compress)); $rs.ContentType="application/json;charset=UTF-8"; $rs.OutputStream.Write($b,0,$b.Length) }
            $rs.Close()
        }
        $expected = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:secret"))
        if ($rq.Headers["Authorization"] -ne $expected) { & $send 401 @{error=@{message="auth"}}; continue }
        $path = $rq.Url.AbsolutePath; $qs = [Web.HttpUtility]::ParseQueryString($rq.Url.Query)
        if ($path -eq "/shutdown") { & $send 200 @{}; break }
        if ($path -notmatch "^/api/now/table/cmn_department(/(?<id>[0-9a-f]+))?$") { & $send 404 $null; continue }
        $id = $Matches["id"]
        $body = $null
        if ($rq.HasEntityBody) {
            # ConvertFrom-Json -AsHashtable is PowerShell 7 only
            $json = [IO.StreamReader]::new($rq.InputStream, [Text.Encoding]::UTF8).ReadToEnd() | ConvertFrom-Json
            $body = @{}; foreach ($p in $json.PSObject.Properties) { $body[$p.Name] = $p.Value }
        }
        switch ($rq.HttpMethod) {
            "GET" {
                if ($id) { if ($store.Contains($id)) { & $send 200 @{result=$store[$id]} } else { & $send 404 @{error=@{message="not found"}} }; break }
                $lim = [int]$qs["sysparm_limit"]; $off = [int]$qs["sysparm_offset"]
                # throttle the first real list call, not the connection test (sysparm_limit=1)
                if (-not $throttled -and $lim -ne 1) { $throttled = $true; & $send 429 @{error=@{message="slow down"}}; break }
                $fields = ($qs["sysparm_fields"] -split ",")
                $rows = @($store.Values | Select-Object -Skip $off -First $lim | ForEach-Object {
                    $r = @{}; foreach ($f in $fields) { $r[$f] = $_[$f] }; $r })
                & $send 200 @{result=$rows}
            }
            "POST" {
                $nid = ('{0:x32}' -f (100 + $store.Count)); $rec = @{ sys_id=$nid; name=""; id=""; description=""; parent=""; dept_head=""; head_count=""; primary_contact=""; company=""; business_unit=""; sys_updated_on="2026-02-02 10:00:00" }
                foreach ($k in $body.Keys) { $rec[$k] = "$($body[$k])" }
                $store[$nid] = $rec; & $send 201 @{result=$rec}
            }
            "PATCH" {
                if (-not $store.Contains($id)) { & $send 404 @{error=@{message="not found"}}; break }
                foreach ($k in $body.Keys) { $store[$id][$k] = "$($body[$k])" }
                & $send 200 @{result=$store[$id]}
            }
            "DELETE" { if ($store.Contains($id)) { $store.Remove($id); & $send 204 $null } else { & $send 404 @{error=@{message="not found"}} } }
        }
    }
    $l.Stop()
}
$rsp = [runspacefactory]::CreateRunspace(); $rsp.Open()
$ps = [powershell]::Create(); $ps.Runspace = $rsp; [void]$ps.AddScript($mock).AddArgument($port); $async = $ps.BeginInvoke()
Start-Sleep 2

# load the CustomCommands straight from the connector XML (same code OIM runs)
$def = [xml](Get-Content (Join-Path $PSScriptRoot $XmlFile) -Raw -Encoding UTF8)
foreach ($cc in $def.PowershellConnectorDefinition.Initialization.CustomCommands.CustomCommand)
{
    Set-Item -Path "function:global:$($cc.Name)" -Value ([scriptblock]::Create($cc.'#cdata-section'))
}
$pw = ConvertTo-SecureString "secret" -AsPlainText -Force
$mod = @{}
if ($def.PowershellConnectorDefinition.ConnectionParameters.ConnectionParameter | Where-Object { $_.Name -eq "ModuleLocation" })
{
    # README convention: path without the .psm1 suffix must work too
    $mod.ModuleLocation = Join-Path $PSScriptRoot "ServiceNowConnector"
    $msg = ""; try { Connect-OneIMSnow -InstanceUrl "http://localhost:$port" -Username admin -Password $pw -ModuleLocation "C:\nowhere\x.psm1" 6>$null } catch { $msg = $_.Exception.Message }
    Check "missing module -> clear error" ($msg -match "module not found")
}

# bad credentials
$threw = $false; $msg401 = ""
try { Connect-OneIMSnow -InstanceUrl "http://localhost:$port" -Username admin -Password (ConvertTo-SecureString "bad" -AsPlainText -Force) @mod 6>$null } catch { $threw = $true; $msg401 = $_.Exception.Message }
Check "bad credentials throw" $threw
Check "HTTP 401 status in error" ($msg401 -match "HTTP 401")
Check "HTTP 401 error body read" (Test-ErrorBody $msg401 "auth")

Connect-OneIMSnow -InstanceUrl "http://localhost:$port" -Username admin -Password $pw @mod 6>$null
if ($mod.Count) { Check "module functions global" ($null -ne (Get-Command Get-OneIMSnowRecord -ErrorAction SilentlyContinue)) }
Check "connect ok" ($null -ne $global:OneIMSnowSession)

# list with paging (25 records, page 10) + a 429 retry on first list call
$sw = [Diagnostics.Stopwatch]::StartNew()
# generic reader called directly: the per-class wrapper does not expose PageSize
$all = @(Get-OneIMSnowRecord -Table cmn_department -Types (Get-OneIMSnowDepartmentTypes) -PageSize 10 -PropertiesToRequest sys_id,name,sys_updated_on 6>$null 3>$null)
Check "paging returns 25" ($all.Count -eq 25)
Check "429 retried (>=2s)" ($sw.Elapsed.TotalSeconds -ge 2)
Check "datetime typed UTC" ($all[0].sys_updated_on -is [datetime] -and $all[0].sys_updated_on.Kind -eq 'Utc' -and $all[0].sys_updated_on.Year -eq 2026)
Check "missing field -> null" ($null -eq $all[0].description)

# single, typed int
$one = Get-OneIMSnowDepartment -sys_id $all[2].sys_id 6>$null
Check "single get name" ($one.name -eq "Dept 3")
Check "head_count int" ($one.head_count -is [int] -and $one.head_count -eq 3)

# create (accented name: checks UTF-8 body encoding on 5.1)
$accented = "Test " + [char]0x00E0 + [char]0x00E8 + [char]0x00F9   # "Test àèù", built from code points so the file encoding doesn't matter
$new = New-OneIMSnowDepartment -name $accented -description "d" -head_count 7 6>$null
Check "create returns sys_id" ($new.sys_id.Length -eq 32)
Check "create fields" ($new.name -eq $accented -and $new.head_count -eq 7)

# partial update only touches bound params
Set-OneIMSnowDepartment -sys_id $new.sys_id -description "changed" 6>$null
$u = Get-OneIMSnowDepartment -sys_id $new.sys_id 6>$null
Check "update description" ($u.description -eq "changed")
Check "update keeps name/head_count" ($u.name -eq $accented -and $u.head_count -eq 7)
Set-OneIMSnowDepartment -sys_id $new.sys_id -description $null 6>$null
Check "null clears field" ($null -eq (Get-OneIMSnowDepartment -sys_id $new.sys_id 6>$null).description)

# output stream hygiene: set/remove/connect must emit nothing
$o = Set-OneIMSnowDepartment -sys_id $new.sys_id -name "Test2" 6>$null
Check "Set emits no output" ($null -eq $o)

# delete twice
Remove-OneIMSnowDepartment -sys_id $new.sys_id 6>$null
$o = Remove-OneIMSnowDepartment -sys_id $new.sys_id 6>$null 3>$null
Check "delete twice tolerated" ($null -eq $o)
$gone = $false; $msg404 = ""
try { Get-OneIMSnowDepartment -sys_id $new.sys_id 6>$null } catch { $msg404 = $_.Exception.Message; $gone = $msg404 -match "404" }
Check "get deleted -> 404 error" $gone
Check "HTTP 404 error body read" (Test-ErrorBody $msg404 "not found")

# URL normalisation
Disconnect-OneIMSnow 6>$null
Check "disconnect clears session" ($null -eq $global:OneIMSnowSession)

# shutdown mock
$global:OneIMSnowSession = @{ BaseUrl="http://localhost:$port"; Headers=@{Authorization="Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:secret"))} }
try { Invoke-RestMethod "http://localhost:$port/shutdown" -Headers $global:OneIMSnowSession.Headers | Out-Null } catch {}
"`n$ok passed, $fail failed"
