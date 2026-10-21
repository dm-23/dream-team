# Dream Team - Windows launcher for the guard (PreToolUse). Finds Git for
# Windows' bash and runs guard-command with it, passing the hook payload on
# stdin and the deny JSON, if any, on stdout; a bash on PATH is used only when
# it is not the WSL one, which cannot read this Windows path. Without a bash
# it exits quietly: the guard is simply unavailable. It always exits 0,
# because the Copilot CLI denies the tool call when a pre-tool hook fails;
# the hook entry runs it with -File only after a Test-Path and ends in exit 0,
# so a missing or broken launcher exits 0 too. It is run with -File, not
# inside -Command, because a -Command host reads stdin before this script can
# set its encoding. The payload is read and piped as UTF-8: Windows
# PowerShell 5.1 would otherwise re-encode it as ASCII, and a non-ASCII path
# would reach bash as "?", which the rm rule reads as a glob.
$ErrorActionPreference = 'SilentlyContinue'
$script = Join-Path $PSScriptRoot 'guard-command'
$candidates = @(
  "$env:ProgramFiles\Git\bin\bash.exe",
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$bash = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $bash) {
  $cmd = Get-Command bash -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -notmatch '\\System32\\') { $bash = $cmd.Source }
}
if (-not $bash) { exit 0 }
try {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $OutputEncoding = $utf8
  [Console]::InputEncoding = $utf8
  [Console]::OutputEncoding = $utf8
} catch {}
try { [Console]::In.ReadToEnd() | & $bash $script } catch {}
exit 0
