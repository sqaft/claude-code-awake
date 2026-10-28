# Prints "<parent pid>`t<command line>`t<parent command line>" for the
# process in CLAUDE_CODE_AWAKE_PID. Used by windows_proc_info in platform.sh.

$id = 0
[void][int]::TryParse("$env:CLAUDE_CODE_AWAKE_PID", [ref]$id)

$self = Get-CimInstance Win32_Process -Filter "ProcessId = $id"
if (-not $self) { exit 1 }

$parent = Get-CimInstance Win32_Process -Filter "ProcessId = $($self.ParentProcessId)"
"{0}`t{1}`t{2}" -f $self.ParentProcessId, $self.CommandLine, $parent.CommandLine
