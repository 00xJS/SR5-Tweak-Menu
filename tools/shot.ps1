# shot.ps1 OUT.png [SCALE]: captures only the game's window to an image.
param([string]$Out, [double]$Scale = 0.6)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Win {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
[void][Win]::SetProcessDPIAware()
$p = Get-Process SaintsRow_DX12 -ErrorAction Stop
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { throw "the game has no window" }
$r = New-Object Win+RECT
[void][Win]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $t = $r.B - $r.T
"window $w x $t, in front: $([Win]::GetForegroundWindow() -eq $h)"
$bmp = New-Object System.Drawing.Bitmap $w, $t
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$sw = [int]($w * $Scale); $st = [int]($t * $Scale)
$small = New-Object System.Drawing.Bitmap $sw, $st
$s = [System.Drawing.Graphics]::FromImage($small)
$s.DrawImage($bmp, 0, 0, $sw, $st)
$small.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$s.Dispose(); $small.Dispose(); $g.Dispose(); $bmp.Dispose()
