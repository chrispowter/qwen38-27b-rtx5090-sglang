param(
    [string]$SshTarget = 'gpu-server',
    [int]$RemotePort = 17893,
    [string]$LocalProxyHost = '127.0.0.1',
    [int]$LocalProxyPort = 7890,
    [string]$RemoteStatusFile = '/data/qwen38-sglang/run/deployment.status'
)

$ErrorActionPreference = 'Stop'
$remoteForward = "127.0.0.1:${RemotePort}:${LocalProxyHost}:${LocalProxyPort}"
$readStatus = "head -n 1 '$RemoteStatusFile' 2>/dev/null || true"

while ($true) {
    $status = & ssh.exe -o ConnectTimeout=10 -o BatchMode=yes $SshTarget $readStatus 2>$null
    if ($status -match '^(complete|failed)\b') {
        Write-Output $status
        exit 0
    }

    # Keep the reverse tunnel for 30 seconds, then reconnect and recheck state.
    # ServerAlive options make broken VPN/SSH paths fail promptly.
    & ssh.exe `
        -R $remoteForward `
        -o ExitOnForwardFailure=yes `
        -o ServerAliveInterval=10 `
        -o ServerAliveCountMax=3 `
        -o ConnectTimeout=10 `
        -o BatchMode=yes `
        $SshTarget `
        'sleep 30'

    Start-Sleep -Seconds 5
}
