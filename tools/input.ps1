# input.ps1 -Keys "W,SHIFT" -Ms 1500 [-Mouse]: brings the game to the front and
# holds keys (and the left mouse button) for a time, as real input.
param([string]$Keys = "", [int]$Ms = 500, [switch]$Mouse, [switch]$Right)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Inp {
  [StructLayout(LayoutKind.Sequential)] public struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] public struct MI { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] public struct U { [FieldOffset(0)] public KI k; [FieldOffset(0)] public MI m; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public U u; }
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] i, int size);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint map);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static void Key(ushort vk, bool down) {
    var i = new INPUT[1]; i[0].type = 1;
    i[0].u.k.scan = (ushort)MapVirtualKey(vk, 0);
    i[0].u.k.flags = 8u | (down ? 0u : 2u);
    SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Btn(uint flag) {
    var i = new INPUT[1]; i[0].type = 0; i[0].u.m.flags = flag;
    SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
  }
}
'@
$p = Get-Process SaintsRow_DX12 -ErrorAction Stop
$h = $p.MainWindowHandle
if ([Inp]::GetForegroundWindow() -ne $h) {
  [Inp]::keybd_event(0x12, 0, 0, [IntPtr]::Zero); [Inp]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)
  [void][Inp]::SetForegroundWindow($h)
  Start-Sleep -Milliseconds 400
}
"in front: $([Inp]::GetForegroundWindow() -eq $h)"
$map = @{ SHIFT = 0x10; CTRL = 0x11; ALT = 0x12; SPACE = 0x20; ENTER = 0x0D; ESC = 0x1B; UP = 0x26; DOWN = 0x28; LEFT = 0x25; RIGHT = 0x27; F5 = 0x74; TAB = 0x09 }
$vks = @()
foreach ($k in ($Keys -split ',' | Where-Object { $_ })) {
  $u = $k.Trim().ToUpper()
  if ($map.ContainsKey($u)) { $vks += [uint16]$map[$u] } else { $vks += [uint16][char]$u[0] }
}
foreach ($v in $vks) { [Inp]::Key($v, $true) }
if ($Mouse) { [Inp]::Btn(2) }
if ($Right) { [Inp]::Btn(8) }
Start-Sleep -Milliseconds $Ms
if ($Right) { [Inp]::Btn(16) }
if ($Mouse) { [Inp]::Btn(4) }
foreach ($v in $vks) { [Inp]::Key($v, $false) }
