# look.ps1 PROBE.lua OUT.png [DELAY]: runs a probe in the game, waits, shows its
# output and captures the left part of the game's window (scaled to fit).
param([string]$Probe, [string]$Out, [double]$Delay = 1)
$d = "C:\Program Files\Epic Games\SaintsRow\sr5\TweakMenu"
$o = "$d\probe_out.txt"
$b = (Get-Item $o).LastWriteTime
Copy-Item $Probe "$d\probe_in.tmp"
Move-Item -Force "$d\probe_in.tmp" "$d\probe_in.lua"
for ($i = 0; $i -lt 60 -and (Get-Item $o).LastWriteTime -eq $b; $i++) { Start-Sleep -Milliseconds 250 }
Get-Content $o
Start-Sleep -Milliseconds ([int]($Delay * 1000))
$full = "$Out.full.png"
& "$PSScriptRoot\shot.ps1" -Out $full -Scale 1
Add-Type -AssemblyName System.Drawing
$i = [System.Drawing.Image]::FromFile($full)
$c = New-Object System.Drawing.Bitmap 1000, 800
$g = [System.Drawing.Graphics]::FromImage($c)
$g.DrawImage($i, (New-Object System.Drawing.Rectangle 0, 0, 1000, 800), (New-Object System.Drawing.Rectangle 0, 200, 1280, 1024), [System.Drawing.GraphicsUnit]::Pixel)
$c.Save($Out)
$g.Dispose(); $c.Dispose(); $i.Dispose()
Remove-Item $full
