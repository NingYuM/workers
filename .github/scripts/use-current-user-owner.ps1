# Elevated hosted runners default new objects to Administrators. Set only the
# default owner to TokenUser; retain privileges and DACLs, and restore on exit.
# Windows APIs require PowerShell/.NET interop; Nu and Node have no built-in FFI.
param([Parameter(Mandatory=$true)][string]$Script)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class XdocTokenOwner {
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetTokenInformation(IntPtr token, int kind, IntPtr data, int size, out int needed);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool SetTokenInformation(IntPtr token, int kind, IntPtr data, int size);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  static IntPtr token, previous;
  static IntPtr Read(int kind) {
    int size;
    GetTokenInformation(token, kind, IntPtr.Zero, 0, out size);
    if (size <= 0) throw new Win32Exception(Marshal.GetLastWin32Error());
    IntPtr data = Marshal.AllocHGlobal(size);
    if (!GetTokenInformation(token, kind, data, size, out size)) {
      int error = Marshal.GetLastWin32Error(); Marshal.FreeHGlobal(data); throw new Win32Exception(error);
    }
    return data;
  }
  public static void Enter() {
    if (!OpenProcessToken(new IntPtr(-1), 0x88, out token)) throw new Win32Exception(Marshal.GetLastWin32Error());
    try {
      previous = Read(4);
      IntPtr user = Read(1);
      try {
        if (!SetTokenInformation(token, 4, user, IntPtr.Size)) throw new Win32Exception(Marshal.GetLastWin32Error());
      } finally { Marshal.FreeHGlobal(user); }
    } catch { Leave(); throw; }
  }
  public static void Leave() {
    int error = 0;
    if (previous != IntPtr.Zero) {
      if (!SetTokenInformation(token, 4, previous, IntPtr.Size)) error = Marshal.GetLastWin32Error();
      Marshal.FreeHGlobal(previous); previous = IntPtr.Zero;
    }
    if (token != IntPtr.Zero) { CloseHandle(token); token = IntPtr.Zero; }
    if (error != 0) throw new Win32Exception(error);
  }
}
'@
[XdocTokenOwner]::Enter()
try {
  & nu --no-config-file $Script
  $result = $LASTEXITCODE
} finally {
  [XdocTokenOwner]::Leave()
}
exit $result
