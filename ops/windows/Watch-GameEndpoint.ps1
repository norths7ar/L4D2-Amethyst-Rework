#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$Address,
    [int]$Port = 27637,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(10, 300)][int]$IntervalSeconds = 10,
    [ValidateRange(1, 24)][int]$Hours = 8,
    [switch]$Once
)

# One small A2S_INFO request per interval, plus a challenge response if required.
# This measures the public query path, not player latency or game frame time.
$ErrorActionPreference = 'Stop'
$targetIp = [System.Net.IPAddress]::Parse($Address)
[void][System.IO.Directory]::CreateDirectory($OutputDirectory)
$lockPath = Join-Path $OutputDirectory 'endpoint.lock'
$lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
$request = [byte[]](@(255, 255, 255, 255, 84) + [System.Text.Encoding]::ASCII.GetBytes("Source Engine Query`0"))
$session = [System.Diagnostics.Stopwatch]::StartNew()
$nextSample = 0.0
try {
    do {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $record = [ordered]@{
            ts = [DateTimeOffset]::Now.ToString('o')
            target = "$Address`:$Port"
            kind = 'a2s_info'
            status = 'error'
            rtt_ms = $null
            challenge = $false
        }
        $udp = [System.Net.Sockets.UdpClient]::new($targetIp.AddressFamily)
        try {
            $udp.Client.ReceiveTimeout = 1000
            $udp.Connect($targetIp, $Port)
            [void]$udp.Send($request, $request.Length)
            $sender = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
            $reply = $udp.Receive([ref]$sender)
            if ($reply.Length -eq 9 -and [BitConverter]::ToInt32($reply, 0) -eq -1 -and $reply[4] -eq 65) {
                $record.challenge = $true
                $challenged = [byte[]]($request + $reply[5..8])
                [void]$udp.Send($challenged, $challenged.Length)
                $reply = $udp.Receive([ref]$sender)
            }
            if ($reply.Length -ge 6 -and [BitConverter]::ToInt32($reply, 0) -eq -1 -and $reply[4] -eq 73) {
                $record.status = 'ok'
                $record.rtt_ms = [Math]::Round($timer.Elapsed.TotalMilliseconds, 3)
            } else {
                $record.status = 'unexpected_reply'
            }
        } catch [System.Net.Sockets.SocketException] {
            $record.status = if ($_.Exception.SocketErrorCode -eq 'TimedOut') { 'timeout' } else { 'socket_error' }
            $record.error = $_.Exception.SocketErrorCode.ToString()
        } finally {
            $udp.Dispose()
        }
        $record.probe_ms = [Math]::Round($timer.Elapsed.TotalMilliseconds, 3)
        $logPath = Join-Path $OutputDirectory ("endpoint-{0}.jsonl" -f (Get-Date -Format 'yyyy-MM-dd'))
        # At ten-second intervals eight hours is only 2,880 compact records.
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -ge 16MB) {
            throw 'Endpoint log reached 16 MiB; stopping instead of growing indefinitely.'
        }
        [System.IO.File]::AppendAllText($logPath, (($record | ConvertTo-Json -Compress) + "`n"))
        if ($Once) { break }
        $nextSample += $IntervalSeconds
        $delay = $nextSample - $session.Elapsed.TotalSeconds
        if ($delay -gt 0) { Start-Sleep -Milliseconds ([int]($delay * 1000)) }
        else { $nextSample = $session.Elapsed.TotalSeconds }
    } while ($session.Elapsed.TotalHours -lt $Hours)
} finally {
    $lock.Dispose()
}
