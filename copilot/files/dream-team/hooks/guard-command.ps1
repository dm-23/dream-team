# Dream Team - Windows launcher for the guard (PreToolUse). Finds Git for
# Windows' bash and runs guard-command with it, passing the hook payload on
# stdin and the deny JSON, if any, on stdout; a bash on PATH is used only when
# it is not the WSL one, which cannot read this Windows path. Without a bash
# it exits quietly: the guard is simply unavailable. It always exits 0,
# because the Copilot CLI denies the tool call when a pre-tool hook fails.
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
$input | & $bash $script
exit 0
