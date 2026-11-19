# Small server for the word cloud (Windows PowerShell 5.1). Nothing is stored on disk: words live in memory only.
# Usage:  powershell -ExecutionPolicy Bypass -File server.ps1
#         powershell -ExecutionPolicy Bypass -File server.ps1 -Pin 4711 -Port 8765
#         powershell -ExecutionPolicy Bypass -File server.ps1 -Network      (reachable from other devices, run as administrator)
param(
  [int]$Port = 8765,
  [string]$Pin = '',
  [switch]$Network,
  [string]$ParticipantFile = 'Invent-Dataport_Teilnehmende_v1.4.html',
  [string]$ModeratorFile = 'Invent-Dataport_Moderator_v1.4.html'
)
$ErrorActionPreference = 'Stop'
$MaxLen = 40; $MaxWords = 150; $MaxCount = 99; $MaxBody = 2048; $RateLimit = 10; $RateSeconds = 60

if (-not $Pin) { $Pin = -join (1..4 | ForEach-Object { Get-Random -Minimum 0 -Maximum 10 }) }
$words = New-Object System.Collections.ArrayList    # entries: @{ w = ...; n = ... }
$state = @{ rev = 0; open = $true }
$stamps = @{}                                        # per device: times of recent submissions (not logged, not stored)
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Clean([string]$s) {
  $s = [regex]::Replace($s, '[\x00-\x1F\x7F<>]', ' ')
  $s = ([regex]::Replace($s, '\s+', ' ')).Trim()
  if ($s.Length -gt $MaxLen) { $s = $s.Substring(0, $MaxLen).Trim() }
  return $s
}
function Find-Word([string]$key) {
  for ($i = 0; $i -lt $words.Count; $i++) { if ($words[$i].w.ToLowerInvariant() -ceq $key) { return $i } }
  return -1
}
function Send-Json($ctx, [int]$code, $obj) {
  $json = ConvertTo-Json -InputObject $obj -Depth 5 -Compress
  $b = $utf8.GetBytes($json)
  $ctx.Response.StatusCode = $code
  $ctx.Response.ContentType = 'application/json; charset=utf-8'
  $ctx.Response.OutputStream.Write($b, 0, $b.Length)
}
function Send-File($ctx, [string]$name) {
  $f = Join-Path $PSScriptRoot $name
  if (-not (Test-Path $f -PathType Leaf)) { $ctx.Response.StatusCode = 404; return }
  $b = [System.IO.File]::ReadAllBytes($f)
  $ctx.Response.ContentType = 'text/html; charset=utf-8'
  $ctx.Response.OutputStream.Write($b, 0, $b.Length)
}
function Read-Body($ctx) {
  $len = $ctx.Request.ContentLength64
  if ($len -gt $MaxBody) { return $null }
  $sr = New-Object System.IO.StreamReader($ctx.Request.InputStream, $utf8)
  $txt = $sr.ReadToEnd(); $sr.Dispose()
  if ($txt.Length -gt $MaxBody) { return $null }
  return $txt
}
function Rate-Ok([string]$id) {
  $now = [DateTime]::UtcNow
  $list = New-Object System.Collections.ArrayList
  if ($stamps.ContainsKey($id)) { foreach ($t in $stamps[$id]) { if (($now - $t).TotalSeconds -lt $RateSeconds) { [void]$list.Add($t) } } }
  if ($list.Count -ge $RateLimit) { $stamps[$id] = $list; return $false }
  [void]$list.Add($now); $stamps[$id] = $list; return $true
}

$prefix = if ($Network) { "http://+:$Port/" } else { "http://localhost:$Port/" }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try { $listener.Start() } catch {
  Write-Host "Server konnte nicht starten: $($_.Exception.Message)" -ForegroundColor Red
  if ($Network) { Write-Host 'Fuer den Netzwerkbetrieb PowerShell als Administrator starten.' -ForegroundColor Yellow }
  exit 1
}
Write-Host ''
Write-Host '  Wortwolke-Server laeuft.' -ForegroundColor Green
Write-Host "  PIN der Moderation: $Pin"
if ($Network) {
  $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object { $_.IPAddress })
  foreach ($ip in $ips) { Write-Host "  Teilnehmende:  http://${ip}:$Port/      Moderation:  http://${ip}:$Port/moderator" }
} else {
  Write-Host "  Teilnehmende:  http://localhost:$Port/      Moderation:  http://localhost:$Port/moderator"
  Write-Host '  (Nur auf diesem Rechner. Fuer andere Geraete mit -Network starten.)'
}
Write-Host '  Beenden mit Strg+C. Beim Beenden sind alle Woerter weg.'
Write-Host ''

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  try {
    $req = $ctx.Request; $res = $ctx.Response
    $res.Headers.Add('Cache-Control', 'no-store')
    $res.Headers.Add('X-Content-Type-Options', 'nosniff')
    $res.Headers.Add('Access-Control-Allow-Origin', '*')
    $res.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $res.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    $path = $req.Url.AbsolutePath.TrimEnd('/'); if ($path -eq '') { $path = '/' }
    $method = $req.HttpMethod
    $q = $req.QueryString
    $pinOk = ($q['pin'] -ceq $Pin)

    if ($method -eq 'OPTIONS') { $res.StatusCode = 204 }
    elseif ($method -eq 'GET' -and $path -eq '/') { Send-File $ctx $ParticipantFile }
    elseif ($method -eq 'GET' -and $path -eq '/moderator') { Send-File $ctx $ModeratorFile }
    elseif ($method -eq 'GET' -and $path -eq '/api/status') { Send-Json $ctx 200 @{ open = $state.open } }
    elseif ($method -eq 'POST' -and $path -eq '/api/words') {
      if (-not $state.open) { Send-Json $ctx 410 @{ error = 'closed' } }
      elseif (-not (Rate-Ok $req.RemoteEndPoint.Address.ToString())) { Send-Json $ctx 429 @{ error = 'rate' } }
      else {
        $body = Read-Body $ctx
        $w = ''
        if ($null -ne $body) { try { $w = Clean ([string](ConvertFrom-Json $body).w) } catch { $w = '' } }
        if (-not $w) { Send-Json $ctx 400 @{ error = 'empty' } }
        else {
          $i = Find-Word $w.ToLowerInvariant()
          if ($i -ge 0) { if ($words[$i].n -lt $MaxCount) { $words[$i].n++ } }
          elseif ($words.Count -lt $MaxWords) { [void]$words.Add(@{ w = $w; n = 1 }) }
          $state.rev++
          Send-Json $ctx 200 @{ ok = $true }
          Write-Host ("  {0}  Antworten: {1}, Woerter: {2}" -f (Get-Date -Format 'HH:mm:ss'), (($words | ForEach-Object { $_.n } | Measure-Object -Sum).Sum), $words.Count)
        }
      }
    }
    elseif ($path -like '/api/*') {
      if (-not $pinOk) { Send-Json $ctx 401 @{ error = 'pin' } }
      elseif ($method -eq 'GET' -and $path -eq '/api/words') {
        $known = -2; [void][int]::TryParse([string]$q['rev'], [ref]$known)
        if ($known -eq $state.rev) { Send-Json $ctx 200 @{ rev = $state.rev; open = $state.open; same = $true } }
        else { Send-Json $ctx 200 @{ rev = $state.rev; open = $state.open; words = @($words | ForEach-Object { @{ w = $_.w; n = $_.n } }) } }
      }
      elseif ($method -eq 'POST' -and $path -eq '/api/remove') {
        $i = Find-Word ([string]$q['k'])
        if ($i -ge 0) { $words.RemoveAt($i); $state.rev++ }
        Send-Json $ctx 200 @{ ok = $true }
      }
      elseif ($method -eq 'POST' -and $path -eq '/api/reset') {
        $words.Clear(); $stamps.Clear(); $state.rev++; Send-Json $ctx 200 @{ ok = $true }
      }
      elseif ($method -eq 'POST' -and $path -eq '/api/open') {
        $state.open = ([string]$q['v'] -eq '1'); $state.rev++; Send-Json $ctx 200 @{ ok = $true; open = $state.open }
      }
      else { Send-Json $ctx 404 @{ error = 'unknown' } }
    }
    else { $res.StatusCode = 404 }
  } catch {
    try { $ctx.Response.StatusCode = 500 } catch { }
  } finally {
    try { $ctx.Response.Close() } catch { }
  }
}
