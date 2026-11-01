// shot.exe OUT.png [SCALE]: one frame of the game's own window through Windows Graphics Capture.
// It reads the window itself, not the screen, so whatever covers the game is never in the picture.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

static class Shot {
  [DllImport("d3d11.dll")] static extern int D3D11CreateDevice(IntPtr adapter, int driver, IntPtr sw, uint flags, IntPtr levels, uint n, uint sdk, out IntPtr device, out int level, out IntPtr ctx);
  [DllImport("d3d11.dll")] static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgi, out IntPtr inspectable);
  [DllImport("combase.dll", PreserveSig = true)] static extern int WindowsCreateString([MarshalAs(UnmanagedType.LPWStr)] string s, int len, out IntPtr h);
  [DllImport("combase.dll", PreserveSig = true)] static extern int RoGetActivationFactory(IntPtr cls, ref Guid iid, out IntPtr factory);
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

  [ComImport, Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IGraphicsCaptureItemInterop {
    [return: MarshalAs(UnmanagedType.IUnknown)] object CreateForWindow(IntPtr window, ref Guid iid);
    [return: MarshalAs(UnmanagedType.IUnknown)] object CreateForMonitor(IntPtr monitor, ref Guid iid);
  }

  static T Wait<T>(Windows.Foundation.IAsyncOperation<T> op) { while (op.Status == Windows.Foundation.AsyncStatus.Started) Thread.Sleep(5); return op.GetResults(); }

  static int Run(string outPath, double scale) {
    Process[] ps = Process.GetProcessesByName("SaintsRow_DX12");
    if (ps.Length == 0 || ps[0].MainWindowHandle == IntPtr.Zero) { Console.WriteLine("the game has no window"); return 2; }
    IntPtr hwnd = ps[0].MainWindowHandle;

    IntPtr dev, ctx, insp; int lvl;
    Marshal.ThrowExceptionForHR(D3D11CreateDevice(IntPtr.Zero, 1, IntPtr.Zero, 0x20, IntPtr.Zero, 0, 7, out dev, out lvl, out ctx));
    Guid dxgiId = new Guid("54ec77fa-1377-44e6-8c32-88fd5f44c84c");
    IntPtr dxgi; Marshal.ThrowExceptionForHR(Marshal.QueryInterface(dev, ref dxgiId, out dxgi));
    Marshal.ThrowExceptionForHR(CreateDirect3D11DeviceFromDXGIDevice(dxgi, out insp));
    IDirect3DDevice device = (IDirect3DDevice)Marshal.GetObjectForIUnknown(insp);

    string cls = "Windows.Graphics.Capture.GraphicsCaptureItem";
    IntPtr hs, fac; WindowsCreateString(cls, cls.Length, out hs);
    Guid interopId = typeof(IGraphicsCaptureItemInterop).GUID;
    Marshal.ThrowExceptionForHR(RoGetActivationFactory(hs, ref interopId, out fac));
    IGraphicsCaptureItemInterop interop = (IGraphicsCaptureItemInterop)Marshal.GetObjectForIUnknown(fac);
    Guid itemId = new Guid("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    GraphicsCaptureItem item = (GraphicsCaptureItem)interop.CreateForWindow(hwnd, ref itemId);

    Direct3D11CaptureFramePool pool = Direct3D11CaptureFramePool.CreateFreeThreaded(device, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, item.Size);
    GraphicsCaptureSession session = pool.CreateCaptureSession(item);
    try { session.IsCursorCaptureEnabled = false; } catch { }
    try { session.IsBorderRequired = false; } catch { }
    session.StartCapture();

    Direct3D11CaptureFrame frame = null;
    for (int i = 0; i < 300 && frame == null; i++) { frame = pool.TryGetNextFrame(); if (frame == null) Thread.Sleep(10); }
    if (frame == null) { Console.WriteLine("no frame from the game's window"); return 3; }
    Console.WriteLine("window " + frame.ContentSize.Width + " x " + frame.ContentSize.Height);

    SoftwareBitmap bmp = Wait(SoftwareBitmap.CreateCopyFromSurfaceAsync(frame.Surface, BitmapAlphaMode.Ignore));
    using (InMemoryRandomAccessStream mem = new InMemoryRandomAccessStream()) {
      BitmapEncoder enc = Wait(BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, mem));
      enc.SetSoftwareBitmap(bmp);
      enc.BitmapTransform.ScaledWidth = (uint)(bmp.PixelWidth * scale);
      enc.BitmapTransform.ScaledHeight = (uint)(bmp.PixelHeight * scale);
      enc.BitmapTransform.InterpolationMode = BitmapInterpolationMode.Fant;
      Windows.Foundation.IAsyncAction flush = enc.FlushAsync();
      while (flush.Status == Windows.Foundation.AsyncStatus.Started) Thread.Sleep(5);
      flush.GetResults();
      byte[] bytes = new byte[mem.Size];
      using (DataReader r = new DataReader(mem.GetInputStreamAt(0))) { Wait(r.LoadAsync((uint)mem.Size)); r.ReadBytes(bytes); }
      File.WriteAllBytes(outPath, bytes);
    }
    frame.Dispose(); session.Dispose(); pool.Dispose();
    return 0;
  }

  [MTAThread] static int Main(string[] a) {
    SetProcessDPIAware();
    if (a.Length < 1) { Console.WriteLine("shot OUT.png [SCALE]"); return 1; }
    return Run(a[0], a.Length > 1 ? double.Parse(a[1], System.Globalization.CultureInfo.InvariantCulture) : 0.6);
  }
}
