<#
    Mock of the ServiceNow Table API for Verify-ServiceNowModuleConnector.ps1 (dot-source it, then run
    $ServiceNowMockScript in a background runspace with the port as argument). Windows PowerShell 5.1 and PowerShell 7.
    - Basic auth admin:secret (test-only value, not a real credential); 401 with a JSON body otherwise
    - any table under /api/now/table/<table>; GET list (sysparm_fields/limit/offset), GET/PATCH/DELETE by sys_id, POST
    - the first list call (sysparm_limit <> 1) answers 429 once
    - /stats returns the number of table requests served; /shutdown stops the listener
    - responses are chunked (no Content-Length): on 5.1 the error body is then only readable from the response stream
#>
$ServiceNowMockScript = {
    param($port)
    Add-Type -AssemblyName System.Web   # HttpUtility is not loaded by default in Windows PowerShell 5.1
    $updatedOn = '2026-01-02 03:04:05'
    $tables = @{}
    $tables['cmn_department'] = [ordered]@{}
    1..25 | ForEach-Object {
        $id = ('{0:x32}' -f $_)
        # no 'code' field: a field missing in the answer must become $null
        $tables['cmn_department'][$id] = @{ sys_id = $id; name = "Dept $_"; id = "D$_"; description = ''; head_count = "$_"; sys_updated_on = $updatedOn }
    }
    $tables['sys_user'] = [ordered]@{}
    1..3 | ForEach-Object {
        $id = ('{0:x32}' -f (1000 + $_))
        $tables['sys_user'][$id] = @{ sys_id = $id; user_name = "user$_"; active = $(if ($_ -eq 3) { 'false' } else { 'true' }); last_login_time = ''; sys_updated_on = $updatedOn }
    }
    $expectedAuth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:secret'))
    $requests = 0
    $throttled = $false
    $nextId = 5000

    $listener = New-Object Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$port/")
    $listener.Start()
    while ($true)
    {
        $context = $listener.GetContext(); $request = $context.Request; $response = $context.Response
        $send = {
            param($code, $object)
            $response.StatusCode = $code
            if ($null -ne $object)
            {
                $bytes = [Text.Encoding]::UTF8.GetBytes(($object | ConvertTo-Json -Depth 5 -Compress))
                $response.ContentType = 'application/json;charset=UTF-8'
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            $response.Close()
        }
        if ($request.Headers['Authorization'] -ne $expectedAuth) { & $send 401 @{ error = @{ message = 'User Not Authenticated' } }; continue }
        $path = $request.Url.AbsolutePath
        if ($path -eq '/shutdown') { & $send 200 @{}; break }
        if ($path -eq '/stats') { & $send 200 @{ requests = $requests }; continue }
        if ($path -notmatch '^/api/now/table/(?<table>[a-z0-9_]+)(/(?<id>[^/]+))?$') { & $send 400 @{ error = @{ message = 'bad path' } }; continue }
        $requests++
        $table = $Matches['table']; $id = $Matches['id']
        if (-not $tables.ContainsKey($table)) { $tables[$table] = [ordered]@{} }
        $store = $tables[$table]
        $query = [Web.HttpUtility]::ParseQueryString($request.Url.Query)
        $body = @{}
        if ($request.HasEntityBody)
        {
            # ConvertFrom-Json -AsHashtable is PowerShell 7 only
            $json = (New-Object IO.StreamReader($request.InputStream, [Text.Encoding]::UTF8)).ReadToEnd() | ConvertFrom-Json
            foreach ($p in $json.PSObject.Properties) { $body[$p.Name] = "$($p.Value)" }
        }
        switch ($request.HttpMethod)
        {
            'GET'
            {
                if ($id)
                {
                    if ($store.Contains($id)) { & $send 200 @{ result = $store[$id] } } else { & $send 404 @{ error = @{ message = 'No Record found' } } }
                    break
                }
                $limit = [int]$query['sysparm_limit']; $offset = [int]$query['sysparm_offset']
                if (-not $throttled -and $limit -ne 1) { $throttled = $true; & $send 429 @{ error = @{ message = 'Too many requests' } }; break }
                $fields = @($query['sysparm_fields'] -split ',')
                $rows = @($store.Values | Select-Object -Skip $offset -First $limit | ForEach-Object {
                        $record = $_; $row = @{}
                        foreach ($f in $fields) { if ($record.ContainsKey($f)) { $row[$f] = $record[$f] } }
                        $row })
                & $send 200 @{ result = $rows }
            }
            'POST'
            {
                $nextId++
                $newId = ('{0:x32}' -f $nextId)
                $record = @{ sys_id = $newId; sys_updated_on = '2026-02-02 10:00:00' }
                foreach ($k in $body.Keys) { $record[$k] = $body[$k] }
                $store[$newId] = $record
                & $send 201 @{ result = $record }
            }
            'PATCH'
            {
                if (-not $store.Contains($id)) { & $send 404 @{ error = @{ message = 'No Record found' } }; break }
                foreach ($k in $body.Keys) { $store[$id][$k] = $body[$k] }
                & $send 200 @{ result = $store[$id] }
            }
            'DELETE'
            {
                if ($store.Contains($id)) { $store.Remove($id); & $send 204 $null } else { & $send 404 @{ error = @{ message = 'No Record found' } } }
            }
            default { & $send 405 @{ error = @{ message = 'method not allowed' } } }
        }
    }
    $listener.Stop()
}
