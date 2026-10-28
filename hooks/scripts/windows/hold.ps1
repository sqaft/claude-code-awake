# Keeps Windows from sleeping until stdin closes or, when
# CLAUDE_CODE_AWAKE_WATCH_PID holds a PID, until that process exits.
# Started by start_powershell_hold in platform.sh.

$kernel = Add-Type -Name ExecutionState -Namespace ClaudeCodeAwake -PassThru -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
'@

# ES_CONTINUOUS (0x80000000) | ES_SYSTEM_REQUIRED (0x00000001). The state
# belongs to this thread and ends with the process.
[void]$kernel::SetThreadExecutionState([uint32]2147483649)

$watched = $null
$watchPid = 0
[void][int]::TryParse("$env:CLAUDE_CODE_AWAKE_WATCH_PID", [ref]$watchPid)
if ($watchPid -gt 0) {
    $watched = Get-Process -Id $watchPid -ErrorAction SilentlyContinue
    if (-not $watched) { exit }
}

# [Console]::In blocks even in its *Async methods, so read the raw stream.
# The feeding loop writes a heartbeat every second; a read of 0 bytes means
# it has stopped.
$stdin = [Console]::OpenStandardInput()
$buffer = New-Object byte[] 256
$read = $stdin.ReadAsync($buffer, 0, $buffer.Length)
while ($true) {
    if ($read.IsCompleted) {
        if ($read.IsFaulted -or $read.Result -le 0) { break }
        $read = $stdin.ReadAsync($buffer, 0, $buffer.Length)
        continue
    }
    if ($watched -and $watched.HasExited) { break }
    Start-Sleep -Milliseconds 500
}
