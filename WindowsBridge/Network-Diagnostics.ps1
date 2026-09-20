$ErrorActionPreference = 'Continue'
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) ('ScreenPilot-Network-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('ScreenPilot: read-only network diagnostics. No network settings changed.')
$lines.Add((Get-Date).ToString('o'))
$lines.Add('=== IP / DNS / gateway ===')
$lines.Add((Get-NetIPConfiguration | Format-List InterfaceAlias,IPv4Address,IPv4DefaultGateway,DNSServer | Out-String))
$lines.Add('=== Default IPv4 routes ===')
$lines.Add((Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Format-Table InterfaceAlias,NextHop,RouteMetric | Out-String))
$lines.Add('=== Proxy configured (values intentionally omitted) ===')
$p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$lines.Add(('ProxyEnable=' + $p.ProxyEnable + '; PAC configured=' + [bool]$p.AutoConfigURL))
if($p.ProxyEnable -eq 1 -and $p.ProxyServer) {
  $parts=([string]$p.ProxyServer) -split ';'
  foreach($part in $parts) {
    $address=$part -replace '^[a-zA-Z]+=', ''
    if($address -match '^(127\.0\.0\.1|localhost):(\d+)$') {
      $tcp=New-Object Net.Sockets.TcpClient
      try { $job=$tcp.BeginConnect($matches[1],[int]$matches[2],$null,$null);$connected=$job.AsyncWaitHandle.WaitOne(2000);if($connected){$tcp.EndConnect($job)};$lines.Add(('Local proxy '+$address+' reachable='+($connected -and $tcp.Connected))) } catch { $lines.Add(('Local proxy '+$address+' unreachable')) } finally { $tcp.Close() }
    }
  }
}
$lines.Add('=== DNS lookup www.microsoft.com ===')
try { $lines.Add((Resolve-DnsName www.microsoft.com -Type A -DnsOnly -QuickTimeout -ErrorAction Stop | Select-Object Name,IPAddress | Out-String)) } catch { $lines.Add($_.Exception.Message) }
$lines.Add('=== Direct HTTPS, no proxy ===')
if(Get-Command curl.exe -ErrorAction SilentlyContinue) {
  $lines.Add((& curl.exe --noproxy '*' --head --connect-timeout 4 --max-time 8 https://www.microsoft.com 2>&1 | Out-String))
} else { $lines.Add('curl.exe unavailable; test skipped.') }
$lines.Add('=== ScreenPilot process ===')
$lines.Add((Get-Process ScreenPilotBridge -ErrorAction SilentlyContinue | Select-Object Id,CPU,WorkingSet64 | Out-String))
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host $out
Start-Process notepad.exe -ArgumentList ('"' + $out + '"')
