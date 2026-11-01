# shot.ps1 OUT.png [SCALE]: one frame of the game's own window, even with other windows over it. Builds shot.exe from shot.cs when needed.
param([string]$Out, [double]$Scale = 0.6)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $here "..\build\shot.exe"
$src = Join-Path $here "shot.cs"
if (-not (Test-Path $exe) -or (Get-Item $src).LastWriteTime -gt (Get-Item $exe).LastWriteTime) {
  $net = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319"
  $refs = @((Get-ChildItem "C:\Windows\System32\WinMetadata\*.winmd" | ForEach-Object { "/r:$($_.FullName)" })) + @("/r:$net\System.Runtime.dll", "/r:$net\System.Runtime.WindowsRuntime.dll", "/r:$net\System.Runtime.InteropServices.WindowsRuntime.dll", "/r:$net\System.Threading.Tasks.dll", "/r:$net\System.IO.dll")
  New-Item -ItemType Directory -Force (Split-Path -Parent $exe) | Out-Null
  & "$net\csc.exe" /nologo /platform:x64 /out:$exe @refs $src
  if ($LASTEXITCODE -ne 0) { throw "shot.cs did not build" }
}
& $exe $Out ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0}", $Scale))
exit $LASTEXITCODE
