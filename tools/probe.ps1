# probe.ps1 "lua code" : runs code in the game's menu Lua and prints its output.
param([string]$Code, [string]$File)
$d = "C:\Program Files\Epic Games\SaintsRow\sr5\TweakMenu"
$o = "$d\probe_out.txt"
$b = (Get-Item $o).LastWriteTime
if ($File) { Copy-Item $File "$d\probe_in.tmp" } else { [IO.File]::WriteAllText("$d\probe_in.tmp", $Code) }
Move-Item -Force "$d\probe_in.tmp" "$d\probe_in.lua"
for ($i = 0; $i -lt 40 -and (Get-Item $o).LastWriteTime -eq $b; $i++) { Start-Sleep -Milliseconds 100 }
Start-Sleep -Milliseconds 100
Get-Content $o
