# Mugen Deej 0.8.4
# Portable bilingual Windows audio controller for deej-compatible USB serial devices.
# Requires Windows PowerShell 5.1+ and Windows 10/11.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:BaseDir 'config.json'
$script:ConfigPreviousPath = Join-Path $script:BaseDir 'config.previous.json'
$script:ConfigLastGoodPath = Join-Path $script:BaseDir 'config.last-good.json'

function Get-DefaultLanguage {
    try {
        if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ru') { return 'ru' }
    }
    catch { }
    return 'en'
}

$bootstrapLanguage = Get-DefaultLanguage
try {
    if (Test-Path -LiteralPath $script:ConfigPath) {
        $bootstrapConfig = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $savedLanguage = ([string]$bootstrapConfig.app.language).ToLowerInvariant()
        if ($savedLanguage -in @('ru','en')) { $bootstrapLanguage = $savedLanguage }
    }
}
catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$windowingSource = @'
using System;
using System.Runtime.InteropServices;

namespace MugenDeejWindowing
{
    public static class Foreground
    {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool BringWindowToTop(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    }
}
'@
Add-Type -TypeDefinition $windowingSource -Language CSharp

$createdNew = $false
$script:InstanceMutex = [System.Threading.Mutex]::new($true, 'Local\MugenDeej-MugenArtLab', [ref]$createdNew)
if (-not $createdNew) {
    $alreadyRunningText = if ($bootstrapLanguage -eq 'ru') {
        'Mugen Deej уже запущен. Проверьте значок программы в области уведомлений Windows.'
    }
    else {
        'Mugen Deej is already running. Check its icon in the Windows notification area.'
    }
    [System.Windows.Forms.MessageBox]::Show(
        $alreadyRunningText,
        'Mugen Deej',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    $script:InstanceMutex.Dispose()
    exit 0
}

$script:AppVersion = '0.8.4'
$script:LogDir = Join-Path $script:BaseDir 'logs'
$script:LogPath = Join-Path $script:LogDir 'mugen-deej.log'
$script:DriverDir = Join-Path $script:BaseDir 'drivers'
$script:DriverInstallerPath = Join-Path $script:DriverDir 'CH341SER.EXE'
$script:OfficialDriverDownload = 'https://www.wch-ic.com/downloads/file/65.html?time=2023-03-16%2022:57:59'
$script:OfficialDriverPage = 'https://www.wch-ic.com/downloads/CH341SER_EXE.html'

$script:AppIconPath = Join-Path $script:BaseDir 'MugenDeej.ico'
$script:AppIcon = $null

function Initialize-AppIcon {
    if (-not (Test-Path -LiteralPath $script:AppIconPath)) { return }
    try {
        $script:AppIcon = New-Object System.Drawing.Icon($script:AppIconPath)
    }
    catch {
        Write-Log ("Failed to load application icon from {0}: {1}" -f $script:AppIconPath, $_.Exception.Message) 'WARN'
        $script:AppIcon = $null
    }
}

function Set-FormAppIcon {
    param([Parameter(Mandatory = $true)][System.Windows.Forms.Form]$Form)
    if ($script:AppIcon) {
        try { $Form.Icon = $script:AppIcon } catch { }
    }
}


New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $script:DriverDir | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('DEBUG','INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $line = '{0:yyyy-MM-dd HH:mm:ss.fff} [{1}] {2}' -f (Get-Date), $Level, $Message
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
}

Initialize-AppIcon

Write-Log "Mugen Deej $script:AppVersion starting"

$audioSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Linq;

namespace MugenDeejAudio
{
    public enum EDataFlow { eRender, eCapture, eAll, EDataFlow_enum_count }
    public enum ERole { eConsole, eMultimedia, eCommunications, ERole_enum_count }
    [Flags]
    public enum DeviceState : uint { Active = 0x1, Disabled = 0x2, NotPresent = 0x4, Unplugged = 0x8, All = 0xF }
    [Flags]
    public enum CLSCTX : uint { InprocServer = 0x1, InprocHandler = 0x2, LocalServer = 0x4, RemoteServer = 0x10, All = InprocServer | InprocHandler | LocalServer | RemoteServer }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        [PreserveSig]
        int EnumAudioEndpoints(EDataFlow dataFlow, DeviceState stateMask, out IMMDeviceCollection devices);
        [PreserveSig]
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice endpoint);
        [PreserveSig]
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        [PreserveSig]
        int RegisterEndpointNotificationCallback(IntPtr client);
        [PreserveSig]
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection
    {
        [PreserveSig]
        int GetCount(out uint count);
        [PreserveSig]
        int Item(uint index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig]
        int Activate(ref Guid iid, CLSCTX clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object interfacePointer);
        [PreserveSig]
        int OpenPropertyStore(int access, out IPropertyStore properties);
        [PreserveSig]
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig]
        int GetState(out DeviceState state);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PROPERTYKEY
    {
        public Guid fmtid;
        public uint pid;

        public PROPERTYKEY(Guid formatId, uint propertyId)
        {
            fmtid = formatId;
            pid = propertyId;
        }
    }

    [StructLayout(LayoutKind.Explicit)]
    internal struct PROPVARIANT
    {
        [FieldOffset(0)]
        public ushort vt;
        [FieldOffset(8)]
        public IntPtr pointerValue;

        public string GetStringValue()
        {
            if (pointerValue == IntPtr.Zero) return String.Empty;
            if (vt == 31) return Marshal.PtrToStringUni(pointerValue) ?? String.Empty;
            return String.Empty;
        }
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyStore
    {
        [PreserveSig]
        int GetCount(out uint propertyCount);
        [PreserveSig]
        int GetAt(uint propertyIndex, out PROPERTYKEY key);
        [PreserveSig]
        int GetValue(ref PROPERTYKEY key, IntPtr value);
        [PreserveSig]
        int SetValue(ref PROPERTYKEY key, IntPtr value);
        [PreserveSig]
        int Commit();
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioEndpointVolume
    {
        [PreserveSig]
        int RegisterControlChangeNotify(IntPtr notify);
        [PreserveSig]
        int UnregisterControlChangeNotify(IntPtr notify);
        [PreserveSig]
        int GetChannelCount(out uint channelCount);
        [PreserveSig]
        int SetMasterVolumeLevel(float levelDb, ref Guid eventContext);
        [PreserveSig]
        int SetMasterVolumeLevelScalar(float level, ref Guid eventContext);
        [PreserveSig]
        int GetMasterVolumeLevel(out float levelDb);
        [PreserveSig]
        int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig]
        int SetChannelVolumeLevel(uint channelNumber, float levelDb, ref Guid eventContext);
        [PreserveSig]
        int SetChannelVolumeLevelScalar(uint channelNumber, float level, ref Guid eventContext);
        [PreserveSig]
        int GetChannelVolumeLevel(uint channelNumber, out float levelDb);
        [PreserveSig]
        int GetChannelVolumeLevelScalar(uint channelNumber, out float level);
        [PreserveSig]
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid eventContext);
        [PreserveSig]
        int GetMute(out bool mute);
        [PreserveSig]
        int GetVolumeStepInfo(out uint step, out uint stepCount);
        [PreserveSig]
        int VolumeStepUp(ref Guid eventContext);
        [PreserveSig]
        int VolumeStepDown(ref Guid eventContext);
        [PreserveSig]
        int QueryHardwareSupport(out uint mask);
        [PreserveSig]
        int GetVolumeRange(out float minDb, out float maxDb, out float incrementDb);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionManager2
    {
        [PreserveSig]
        int GetAudioSessionControl(ref Guid audioSessionGuid, uint streamFlags, out IAudioSessionControl sessionControl);
        [PreserveSig]
        int GetSimpleAudioVolume(ref Guid audioSessionGuid, uint streamFlags, out ISimpleAudioVolume audioVolume);
        [PreserveSig]
        int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnum);
        [PreserveSig]
        int RegisterSessionNotification(IntPtr sessionNotification);
        [PreserveSig]
        int UnregisterSessionNotification(IntPtr sessionNotification);
        [PreserveSig]
        int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionId, IntPtr duckNotification);
        [PreserveSig]
        int UnregisterDuckNotification(IntPtr duckNotification);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionEnumerator
    {
        [PreserveSig]
        int GetCount(out int count);
        [PreserveSig]
        int GetSession(int index, out IAudioSessionControl sessionControl);
    }

    [ComImport, Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionControl
    {
        [PreserveSig]
        int GetState(out int state);
        [PreserveSig]
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string displayName);
        [PreserveSig]
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string displayName, ref Guid eventContext);
        [PreserveSig]
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string iconPath);
        [PreserveSig]
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string iconPath, ref Guid eventContext);
        [PreserveSig]
        int GetGroupingParam(out Guid groupingId);
        [PreserveSig]
        int SetGroupingParam(ref Guid groupingId, ref Guid eventContext);
        [PreserveSig]
        int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig]
        int UnregisterAudioSessionNotification(IntPtr client);
    }

    [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionControl2
    {
        // IAudioSessionControl methods
        [PreserveSig]
        int GetState(out int state);
        [PreserveSig]
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string displayName);
        [PreserveSig]
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string displayName, ref Guid eventContext);
        [PreserveSig]
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string iconPath);
        [PreserveSig]
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string iconPath, ref Guid eventContext);
        [PreserveSig]
        int GetGroupingParam(out Guid groupingId);
        [PreserveSig]
        int SetGroupingParam(ref Guid groupingId, ref Guid eventContext);
        [PreserveSig]
        int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig]
        int UnregisterAudioSessionNotification(IntPtr client);
        // IAudioSessionControl2 methods
        [PreserveSig]
        int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string sessionIdentifier);
        [PreserveSig]
        int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string sessionInstanceIdentifier);
        [PreserveSig]
        int GetProcessId(out uint processId);
        [PreserveSig]
        int IsSystemSoundsSession();
        [PreserveSig]
        int SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool optOut);
    }

    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface ISimpleAudioVolume
    {
        [PreserveSig]
        int SetMasterVolume(float level, ref Guid eventContext);
        [PreserveSig]
        int GetMasterVolume(out float level);
        [PreserveSig]
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid eventContext);
        [PreserveSig]
        int GetMute(out bool mute);
    }

    public sealed class AudioDeviceInfo
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public bool IsDefault { get; set; }
    }

    public static class AudioMixer
    {
        private static readonly Guid EndpointVolumeId = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
        private static readonly Guid SessionManagerId = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
        private static readonly PROPERTYKEY FriendlyNameKey = new PROPERTYKEY(new Guid("A45C254E-DF1C-4EFD-8020-67D146A850E0"), 14);

        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(IntPtr value);
        private static readonly object SessionSync = new object();
        private static readonly TimeSpan SessionCacheLifetime = TimeSpan.FromMilliseconds(1500);
        private static readonly TimeSpan MissRefreshCooldown = TimeSpan.FromSeconds(2);
        private static DateTime lastMissRefreshUtc = DateTime.MinValue;

        private sealed class SessionEntry
        {
            public string Name;
            public IAudioSessionControl Control;
        }

        private static List<SessionEntry> sessionCache = new List<SessionEntry>();
        private static DateTime sessionCacheUpdatedUtc = DateTime.MinValue;

        private static float Clamp(float value)
        {
            if (value < 0f) return 0f;
            if (value > 1f) return 1f;
            return value;
        }

        private static string NormalizeName(string name)
        {
            if (String.IsNullOrWhiteSpace(name)) return String.Empty;
            name = name.Trim().Trim('"', '\'');
            if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                name = name.Substring(0, name.Length - 4);
            return name;
        }

        private static void SetEndpointVolume(IMMDevice device, float level)
        {
            object endpointObject = null;
            try
            {
                Guid iid = EndpointVolumeId;
                Marshal.ThrowExceptionForHR(device.Activate(ref iid, CLSCTX.All, IntPtr.Zero, out endpointObject));
                var endpoint = (IAudioEndpointVolume)endpointObject;
                Guid context = Guid.Empty;
                Marshal.ThrowExceptionForHR(endpoint.SetMasterVolumeLevelScalar(Clamp(level), ref context));
            }
            finally
            {
                if (endpointObject != null && Marshal.IsComObject(endpointObject)) Marshal.ReleaseComObject(endpointObject);
            }
        }

        private static void SetDefaultEndpointVolume(EDataFlow flow, ERole primaryRole, ERole fallbackRole, float level)
        {
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            try
            {
                enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
                int hr = enumerator.GetDefaultAudioEndpoint(flow, primaryRole, out device);
                if (hr != 0 && fallbackRole != primaryRole)
                    hr = enumerator.GetDefaultAudioEndpoint(flow, fallbackRole, out device);
                Marshal.ThrowExceptionForHR(hr);
                SetEndpointVolume(device, level);
            }
            finally
            {
                if (device != null && Marshal.IsComObject(device)) Marshal.ReleaseComObject(device);
                if (enumerator != null && Marshal.IsComObject(enumerator)) Marshal.ReleaseComObject(enumerator);
            }
        }

        private static string GetFriendlyName(IMMDevice device)
        {
            IPropertyStore store = null;
            IntPtr value = IntPtr.Zero;
            try
            {
                Marshal.ThrowExceptionForHR(device.OpenPropertyStore(0, out store));

                // PROPVARIANT is 16 bytes in a 32-bit process and 24 bytes in a
                // 64-bit process. Using a truncated managed struct can corrupt the
                // COM call and abort endpoint enumeration, so allocate the native
                // buffer explicitly.
                int valueSize = IntPtr.Size == 8 ? 24 : 16;
                value = Marshal.AllocCoTaskMem(valueSize);
                for (int i = 0; i < valueSize; i++) Marshal.WriteByte(value, i, 0);

                PROPERTYKEY key = FriendlyNameKey;
                Marshal.ThrowExceptionForHR(store.GetValue(ref key, value));

                ushort variantType = unchecked((ushort)Marshal.ReadInt16(value, 0));
                if (variantType != 31) return String.Empty; // VT_LPWSTR

                IntPtr stringPointer = Marshal.ReadIntPtr(value, 8);
                if (stringPointer == IntPtr.Zero) return String.Empty;
                return Marshal.PtrToStringUni(stringPointer) ?? String.Empty;
            }
            finally
            {
                if (value != IntPtr.Zero)
                {
                    PropVariantClear(value);
                    Marshal.FreeCoTaskMem(value);
                }
                if (store != null && Marshal.IsComObject(store)) Marshal.ReleaseComObject(store);
            }
        }

        public static AudioDeviceInfo[] GetCaptureDevices()
        {
            IMMDeviceEnumerator enumerator = null;
            IMMDeviceCollection collection = null;
            IMMDevice defaultDevice = null;
            string defaultId = String.Empty;
            List<AudioDeviceInfo> result = new List<AudioDeviceInfo>();

            try
            {
                enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
                int defaultHr = enumerator.GetDefaultAudioEndpoint(EDataFlow.eCapture, ERole.eMultimedia, out defaultDevice);
                if (defaultHr != 0)
                    defaultHr = enumerator.GetDefaultAudioEndpoint(EDataFlow.eCapture, ERole.eCommunications, out defaultDevice);
                if (defaultHr == 0 && defaultDevice != null)
                {
                    string resolvedDefaultId;
                    if (defaultDevice.GetId(out resolvedDefaultId) == 0) defaultId = resolvedDefaultId;
                }

                Marshal.ThrowExceptionForHR(enumerator.EnumAudioEndpoints(EDataFlow.eCapture, DeviceState.Active, out collection));
                uint count;
                Marshal.ThrowExceptionForHR(collection.GetCount(out count));
                for (uint i = 0; i < count; i++)
                {
                    IMMDevice device = null;
                    try
                    {
                        Marshal.ThrowExceptionForHR(collection.Item(i, out device));
                        string id;
                        Marshal.ThrowExceptionForHR(device.GetId(out id));
                        string name;
                        try { name = GetFriendlyName(device); }
                        catch { name = id; }
                        if (String.IsNullOrWhiteSpace(name)) name = id;
                        result.Add(new AudioDeviceInfo
                        {
                            Id = id,
                            Name = name,
                            IsDefault = String.Equals(id, defaultId, StringComparison.OrdinalIgnoreCase)
                        });
                    }
                    catch
                    {
                        // A single broken or half-removed endpoint must not hide all
                        // the other microphones from the settings list.
                    }
                    finally
                    {
                        if (device != null && Marshal.IsComObject(device)) Marshal.ReleaseComObject(device);
                    }
                }
            }
            finally
            {
                if (defaultDevice != null && Marshal.IsComObject(defaultDevice)) Marshal.ReleaseComObject(defaultDevice);
                if (collection != null && Marshal.IsComObject(collection)) Marshal.ReleaseComObject(collection);
                if (enumerator != null && Marshal.IsComObject(enumerator)) Marshal.ReleaseComObject(enumerator);
            }

            return result
                .OrderByDescending(item => item.IsDefault)
                .ThenBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToArray();
        }

        public static void SetMaster(float level)
        {
            SetDefaultEndpointVolume(EDataFlow.eRender, ERole.eMultimedia, ERole.eConsole, level);
        }

        public static void SetMicrophone(float level)
        {
            SetDefaultEndpointVolume(EDataFlow.eCapture, ERole.eMultimedia, ERole.eCommunications, level);
        }

        public static void SetInputDeviceVolume(string deviceId, float level)
        {
            if (String.IsNullOrWhiteSpace(deviceId))
            {
                SetMicrophone(level);
                return;
            }

            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            try
            {
                enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
                Marshal.ThrowExceptionForHR(enumerator.GetDevice(deviceId, out device));
                SetEndpointVolume(device, level);
            }
            finally
            {
                if (device != null && Marshal.IsComObject(device)) Marshal.ReleaseComObject(device);
                if (enumerator != null && Marshal.IsComObject(enumerator)) Marshal.ReleaseComObject(enumerator);
            }
        }

        private static void ReleaseEntries(List<SessionEntry> entries)
        {
            if (entries == null) return;
            foreach (SessionEntry entry in entries)
            {
                try
                {
                    if (entry != null && entry.Control != null && Marshal.IsComObject(entry.Control))
                        Marshal.ReleaseComObject(entry.Control);
                }
                catch { }
            }
        }

        private static void RefreshSessionsInternal()
        {
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            object managerObject = null;
            IAudioSessionEnumerator sessions = null;
            List<SessionEntry> fresh = new List<SessionEntry>();
            bool success = false;

            try
            {
                enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
                Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out device));
                Guid iid = SessionManagerId;
                Marshal.ThrowExceptionForHR(device.Activate(ref iid, CLSCTX.All, IntPtr.Zero, out managerObject));
                var manager = (IAudioSessionManager2)managerObject;
                Marshal.ThrowExceptionForHR(manager.GetSessionEnumerator(out sessions));
                int count;
                Marshal.ThrowExceptionForHR(sessions.GetCount(out count));

                for (int i = 0; i < count; i++)
                {
                    IAudioSessionControl control = null;
                    bool keep = false;
                    try
                    {
                        if (sessions.GetSession(i, out control) != 0 || control == null) continue;
                        var control2 = (IAudioSessionControl2)control;
                        uint pid;
                        if (control2.GetProcessId(out pid) != 0 || pid == 0) continue;

                        string actual;
                        try { actual = Process.GetProcessById((int)pid).ProcessName; }
                        catch { continue; }

                        string normalized = NormalizeName(actual);
                        if (normalized.Length == 0) continue;
                        fresh.Add(new SessionEntry { Name = normalized, Control = control });
                        keep = true;
                    }
                    finally
                    {
                        if (!keep && control != null && Marshal.IsComObject(control))
                            Marshal.ReleaseComObject(control);
                    }
                }
                success = true;
            }
            finally
            {
                if (sessions != null && Marshal.IsComObject(sessions)) Marshal.ReleaseComObject(sessions);
                if (managerObject != null && Marshal.IsComObject(managerObject)) Marshal.ReleaseComObject(managerObject);
                if (device != null && Marshal.IsComObject(device)) Marshal.ReleaseComObject(device);
                if (enumerator != null && Marshal.IsComObject(enumerator)) Marshal.ReleaseComObject(enumerator);

                if (success)
                {
                    List<SessionEntry> old = sessionCache;
                    sessionCache = fresh;
                    sessionCacheUpdatedUtc = DateTime.UtcNow;
                    ReleaseEntries(old);
                }
                else
                {
                    ReleaseEntries(fresh);
                }
            }
        }

        private static void EnsureSessionsInternal(bool force)
        {
            if (force || sessionCache.Count == 0 || (DateTime.UtcNow - sessionCacheUpdatedUtc) >= SessionCacheLifetime)
                RefreshSessionsInternal();
        }

        private static int ApplyToCachedSessions(HashSet<string> wanted, float level)
        {
            int changed = 0;
            Guid context = Guid.Empty;
            float clamped = Clamp(level);

            foreach (SessionEntry entry in sessionCache)
            {
                if (entry == null || entry.Control == null || !wanted.Contains(entry.Name)) continue;
                try
                {
                    var volume = (ISimpleAudioVolume)entry.Control;
                    if (volume.SetMasterVolume(clamped, ref context) == 0) changed++;
                }
                catch { }
            }
            return changed;
        }

        public static int SetProcessVolumes(string[] processNames, float level)
        {
            if (processNames == null || processNames.Length == 0) return 0;
            HashSet<string> wanted = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string processName in processNames)
            {
                string normalized = NormalizeName(processName);
                if (normalized.Length > 0) wanted.Add(normalized);
            }
            if (wanted.Count == 0) return 0;

            lock (SessionSync)
            {
                EnsureSessionsInternal(false);
                int changed = ApplyToCachedSessions(wanted, level);
                if (changed == 0 && (DateTime.UtcNow - lastMissRefreshUtc) >= MissRefreshCooldown)
                {
                    lastMissRefreshUtc = DateTime.UtcNow;
                    EnsureSessionsInternal(true);
                    changed = ApplyToCachedSessions(wanted, level);
                }
                return changed;
            }
        }

        public static string[] GetProcessNames()
        {
            lock (SessionSync)
            {
                EnsureSessionsInternal(true);
                return sessionCache
                    .Where(entry => entry != null && !String.IsNullOrWhiteSpace(entry.Name))
                    .Select(entry => entry.Name)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .OrderBy(name => name, StringComparer.CurrentCultureIgnoreCase)
                    .ToArray();
            }
        }

        public static int SetProcessVolume(string processName, float level)
        {
            return SetProcessVolumes(new string[] { processName }, level);
        }

        public static void InvalidateSessions()
        {
            lock (SessionSync)
            {
                sessionCacheUpdatedUtc = DateTime.MinValue;
            }
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $audioSource -Language CSharp
    Write-Log 'Core Audio bridge loaded'
}
catch {
    Write-Log "Core Audio bridge failed: $($_.Exception.Message)" 'ERROR'
    $audioErrorText = if ($bootstrapLanguage -eq 'ru') {
        "Не удалось загрузить аудиомодуль.`r`n$($_.Exception.Message)"
    }
    else {
        "Failed to load the audio module.`r`n$($_.Exception.Message)"
    }
    [System.Windows.Forms.MessageBox]::Show(
        $audioErrorText,
        'Mugen Deej',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

function Get-ConfigTargetCount {
    param([Parameter(Mandatory = $true)]$Config)
    $count = 0
    foreach ($slider in @($Config.sliders)) {
        foreach ($target in @($slider.targets)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$target)) { $count++ }
        }
    }
    return $count
}

function Get-ConfigSummary {
    param([Parameter(Mandatory = $true)]$Config)
    $language = [string]$Config.app.language
    $firstRun = [bool]$Config.app.firstRunCompleted
    $sliderCount = @($Config.sliders).Count
    $targetCount = Get-ConfigTargetCount -Config $Config
    return "language=$language; firstRunCompleted=$firstRun; sliders=$sliderCount; targets=$targetCount"
}

function Read-ConfigFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-CompletedConfig {
    param([Parameter(Mandatory = $true)]$Config)
    $language = ([string]$Config.app.language).ToLowerInvariant()
    return ([bool]$Config.app.firstRunCompleted) -and ($language -in @('ru','en'))
}

function Save-Config {
    param([Parameter(Mandatory = $true)]$Config)

    $tempPath = "$script:ConfigPath.tmp-$PID"
    try {
        $json = $Config | ConvertTo-Json -Depth 8
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)

        # Never replace the live configuration with JSON that cannot be read back.
        $verifiedTemp = Read-ConfigFile -Path $tempPath
        if ($null -eq $verifiedTemp.app -or $null -eq $verifiedTemp.connection -or $null -eq $verifiedTemp.sliders) {
            throw 'The temporary configuration is incomplete.'
        }
        if (@($verifiedTemp.sliders).Count -ne @($Config.sliders).Count) {
            throw 'The temporary configuration failed slider-count verification.'
        }

        if (Test-Path -LiteralPath $script:ConfigPath) {
            if (Test-Path -LiteralPath $script:ConfigPreviousPath) {
                Remove-Item -LiteralPath $script:ConfigPreviousPath -Force
            }
            try {
                [System.IO.File]::Replace($tempPath, $script:ConfigPath, $script:ConfigPreviousPath, $true)
            }
            catch {
                # Fallback for unusual file systems where File.Replace is unavailable.
                Copy-Item -LiteralPath $script:ConfigPath -Destination $script:ConfigPreviousPath -Force
                Remove-Item -LiteralPath $script:ConfigPath -Force
                [System.IO.File]::Move($tempPath, $script:ConfigPath)
            }
        }
        else {
            [System.IO.File]::Move($tempPath, $script:ConfigPath)
        }

        $verifiedLive = Read-ConfigFile -Path $script:ConfigPath
        if ($null -eq $verifiedLive.app -or $null -eq $verifiedLive.connection -or $null -eq $verifiedLive.sliders) {
            throw 'The saved configuration failed read-back verification.'
        }
        Copy-Item -LiteralPath $script:ConfigPath -Destination $script:ConfigLastGoodPath -Force
        Write-Log "Config saved and verified: $(Get-ConfigSummary -Config $verifiedLive)" 'DEBUG'
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $script:ConfigPreviousPath) {
            try { Copy-Item -LiteralPath $script:ConfigPreviousPath -Destination $script:ConfigPath -Force } catch { }
        }
        Write-Log "Config save failed: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

function New-DefaultConfig {
    $default = [ordered]@{
        configVersion = 8
        app = [ordered]@{
            language = 'auto'
            startMinimized = $false
            minimizeToTray = $true
            firstRunCompleted = $false
            advancedExpanded = $false
        }
        connection = [ordered]@{
            mode = 'auto'
            port = ''
            lastWorkingPort = ''
            baudRate = 9600
            expectedSliders = 5
            reconnectSeconds = 3
            startupWaitMs = 2200
            dataTimeoutMs = 2500
        }
        behavior = [ordered]@{
            invertSliders = $false
            noiseThreshold = 0.007
        }
        sliders = @(
            [ordered]@{ name = 'Control 1'; defaultName = $true; targets = @(); inputDeviceId = ''; inputDeviceName = '' },
            [ordered]@{ name = 'Control 2'; defaultName = $true; targets = @(); inputDeviceId = ''; inputDeviceName = '' },
            [ordered]@{ name = 'Control 3'; defaultName = $true; targets = @(); inputDeviceId = ''; inputDeviceName = '' },
            [ordered]@{ name = 'Control 4'; defaultName = $true; targets = @(); inputDeviceId = ''; inputDeviceName = '' },
            [ordered]@{ name = 'Control 5'; defaultName = $true; targets = @(); inputDeviceId = ''; inputDeviceName = '' }
        )
    }
    Save-Config -Config $default

    # On the very first launch, $default is an OrderedDictionary. The rest of
    # the application expects the PSCustomObject shape produced by
    # ConvertFrom-Json. Returning the dictionary directly can make UI changes
    # update temporary note properties while ConvertTo-Json still writes the
    # untouched dictionary values. Reload immediately so the first launch uses
    # exactly the same runtime model as every later launch.
    $runtimeConfig = Read-ConfigFile -Path $script:ConfigPath
    Write-Log "Default config created and reloaded: $(Get-ConfigSummary -Config $runtimeConfig)" 'INFO'
    return $runtimeConfig
}

function Load-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        if (Test-Path -LiteralPath $script:ConfigLastGoodPath) {
            try {
                $recovered = Read-ConfigFile -Path $script:ConfigLastGoodPath
                Copy-Item -LiteralPath $script:ConfigLastGoodPath -Destination $script:ConfigPath -Force
                Write-Log "Config was missing and restored from last-good copy: $(Get-ConfigSummary -Config $recovered)" 'WARN'
                return $recovered
            }
            catch {
                Write-Log "Last-good config recovery failed: $($_.Exception.Message)" 'ERROR'
            }
        }
        Write-Log 'Config missing; creating default config' 'WARN'
        return New-DefaultConfig
    }

    try {
        $loaded = Read-ConfigFile -Path $script:ConfigPath

        # A completed last-good configuration must not be silently replaced by a
        # fresh first-run file. This specifically protects portable installs from
        # an unexpected reset between launches.
        if ((-not (Test-CompletedConfig -Config $loaded)) -and (Test-Path -LiteralPath $script:ConfigLastGoodPath)) {
            try {
                $lastGood = Read-ConfigFile -Path $script:ConfigLastGoodPath
                if (Test-CompletedConfig -Config $lastGood) {
                    Copy-Item -LiteralPath $script:ConfigPath -Destination $script:ConfigPreviousPath -Force
                    Copy-Item -LiteralPath $script:ConfigLastGoodPath -Destination $script:ConfigPath -Force
                    Write-Log "Unexpected first-run config replaced with last-good copy: $(Get-ConfigSummary -Config $lastGood)" 'WARN'
                    return $lastGood
                }
            }
            catch {
                Write-Log "Last-good config comparison failed: $($_.Exception.Message)" 'WARN'
            }
        }

        Write-Log "Config loaded: $(Get-ConfigSummary -Config $loaded)" 'INFO'
        return $loaded
    }
    catch {
        Write-Log "Config load failed: $($_.Exception.Message)" 'ERROR'
        $broken = "$script:ConfigPath.broken-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item -LiteralPath $script:ConfigPath -Destination $broken -Force

        if (Test-Path -LiteralPath $script:ConfigLastGoodPath) {
            try {
                $recovered = Read-ConfigFile -Path $script:ConfigLastGoodPath
                Copy-Item -LiteralPath $script:ConfigLastGoodPath -Destination $script:ConfigPath -Force
                Write-Log "Broken config restored from last-good copy: $(Get-ConfigSummary -Config $recovered)" 'WARN'
                return $recovered
            }
            catch {
                Write-Log "Last-good config recovery failed: $($_.Exception.Message)" 'ERROR'
            }
        }
        return New-DefaultConfig
    }
}

function Add-MissingConfigProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value
    )
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Ensure-ConfigShape {
    param([Parameter(Mandatory = $true)]$Config)

    Add-MissingConfigProperty -Object $Config -Name 'configVersion' -Value 7
    if ($null -eq $Config.PSObject.Properties['app']) {
        $Config | Add-Member -MemberType NoteProperty -Name 'app' -Value ([pscustomobject]@{})
    }
    Add-MissingConfigProperty -Object $Config.app -Name 'language' -Value 'auto'
    Add-MissingConfigProperty -Object $Config.app -Name 'startMinimized' -Value $false
    Add-MissingConfigProperty -Object $Config.app -Name 'minimizeToTray' -Value $true
    Add-MissingConfigProperty -Object $Config.app -Name 'firstRunCompleted' -Value $false
    Add-MissingConfigProperty -Object $Config.app -Name 'advancedExpanded' -Value $false

    if ($null -eq $Config.PSObject.Properties['connection']) {
        $Config | Add-Member -MemberType NoteProperty -Name 'connection' -Value ([pscustomobject]@{})
    }
    Add-MissingConfigProperty -Object $Config.connection -Name 'mode' -Value 'auto'
    Add-MissingConfigProperty -Object $Config.connection -Name 'port' -Value ''
    Add-MissingConfigProperty -Object $Config.connection -Name 'lastWorkingPort' -Value ''
    Add-MissingConfigProperty -Object $Config.connection -Name 'baudRate' -Value 9600
    Add-MissingConfigProperty -Object $Config.connection -Name 'expectedSliders' -Value 5
    Add-MissingConfigProperty -Object $Config.connection -Name 'reconnectSeconds' -Value 3
    Add-MissingConfigProperty -Object $Config.connection -Name 'startupWaitMs' -Value 2200
    Add-MissingConfigProperty -Object $Config.connection -Name 'dataTimeoutMs' -Value 2500

    if ($null -eq $Config.PSObject.Properties['behavior']) {
        $Config | Add-Member -MemberType NoteProperty -Name 'behavior' -Value ([pscustomobject]@{})
    }
    Add-MissingConfigProperty -Object $Config.behavior -Name 'invertSliders' -Value $false
    Add-MissingConfigProperty -Object $Config.behavior -Name 'noiseThreshold' -Value 0.007

    if ($null -eq $Config.PSObject.Properties['sliders']) {
        $Config | Add-Member -MemberType NoteProperty -Name 'sliders' -Value @()
    }
    for ($i = 0; $i -lt @($Config.sliders).Count; $i++) {
        $slider = $Config.sliders[$i]
        Add-MissingConfigProperty -Object $slider -Name 'targets' -Value @()
        Add-MissingConfigProperty -Object $slider -Name 'inputDeviceId' -Value ''
        Add-MissingConfigProperty -Object $slider -Name 'inputDeviceName' -Value ''
        $sliderName = [string]$slider.name
        $looksGenerated = $sliderName -match '^(Ручка|Регулятор|Knob|Control)\s+\d+$'
        Add-MissingConfigProperty -Object $slider -Name 'defaultName' -Value $looksGenerated
    }
    $Config.configVersion = 8
    return $Config
}

$script:Config = Ensure-ConfigShape -Config (Load-Config)
$savedLanguage = ([string]$script:Config.app.language).ToLowerInvariant()
$script:NeedsInitialLanguageSelection = (-not [bool]$script:Config.app.firstRunCompleted) -and ($savedLanguage -notin @('ru','en'))
$script:Language = if ($savedLanguage -in @('ru','en')) { $savedLanguage } else { Get-DefaultLanguage }
if (-not $script:NeedsInitialLanguageSelection -and $savedLanguage -notin @('ru','en')) {
    $script:Config.app.language = $script:Language
    Save-Config -Config $script:Config
}
$script:Serial = $null
$script:SerialBuffer = ''
$script:IsConnected = $false
$script:IsConnecting = $false
$script:ConnectedPort = ''
$script:LastReconnectAttempt = [DateTime]::MinValue
$script:LastSerialPacketAt = [DateTime]::MinValue
$script:LastPortSnapshotCheck = [DateTime]::MinValue
$script:KnownPorts = @()
$script:PendingNewPorts = @()
$script:PortProbeCooldowns = @{}
$script:PortProbeFailureCounts = @{}
$script:PortSnapshotIntervalMs = 500
$script:NegativeProbeCooldownSeconds = 300
$script:FailedOpenCooldownSeconds = 60
$script:BusyPortCooldownBaseSeconds = 60
$script:BusyPortCooldownMaxSeconds = 600
$script:LastScanBusyPorts = @()
$script:LastValues = @()
$script:LatestLevels = @()
$script:AudioWarningCooldowns = @{}
$script:CaptureDeviceCache = @()
$script:CaptureDeviceCacheAt = [DateTime]::MinValue
$script:CaptureDeviceCacheInitialized = $false
$script:CaptureDeviceCacheSignature = ''
$script:CaptureDeviceCacheTtlSeconds = 15
$script:CaptureDeviceRefreshMinSeconds = 4
$script:CoreAudioCaptureUnavailable = $false
$script:Closing = $false
$script:KnobNameLabels = @()
$script:KnobProgressBars = @()
$script:KnobPercentLabels = @()

$script:FriendlyProcessNames = @{
    'chrome' = 'Google Chrome'
    'msedge' = 'Microsoft Edge'
    'firefox' = 'Mozilla Firefox'
    'discord' = 'Discord'
    'steam' = 'Steam'
    'spotify' = 'Spotify'
    'telegram' = 'Telegram'
    'telegramdesktop' = 'Telegram Desktop'
    'vlc' = 'VLC media player'
    'obs64' = 'OBS Studio'
    'opera' = 'Opera'
    'opera_gx' = 'Opera GX'
    'yandex' = 'Yandex Browser'
}

$script:Strings = @{
    ru = @{
        LanguageLabel = 'Язык:'
        Subtitle = 'Настольный аудиоконтроллер'
        Starting = 'Запуск…'
        KnobStatus = 'Состояние регуляторов'
        ConfigureKnobs = 'Настроить регуляторы'
        ConfigureHint = 'Переименуйте регуляторы и назначьте им общую громкость, приложения или уровень микрофона.'
        DiagnosticsClosed = 'Подключение и диагностика ▼'
        DiagnosticsOpen = 'Подключение и диагностика ▲'
        ConnectionGroup = 'Подключение контроллера'
        AutoPort = 'Определять COM-порт автоматически'
        ManualPort = 'Выбрать порт вручную'
        RefreshList = 'Обновить список'
        Reconnect = 'Найти и подключить заново'
        ConnectionHelp = 'Автоматический режим подходит почти всегда. Ручной выбор пригодится, если подключено несколько похожих COM-устройств.'
        DriverAndLog = 'Драйвер и журнал'
        Checking = 'Проверяем…'
        InstallDriver = 'Установить драйвер'
        ReinstallDriver = 'Переустановить драйвер'
        RepairDriver = 'Исправить / переустановить драйвер'
        InstallOrReinstall = 'Установить / переустановить драйвер'
        OpenLog = 'Открыть журнал'
        TrayOpen = 'Открыть Mugen Deej'
        TraySettings = 'Настроить регуляторы'
        TrayReconnect = 'Переподключить контроллер'
        TrayExit = 'Выход'
        TrayDisconnected = 'Mugen Deej — контроллер не подключён'
        KnobN = 'Регулятор {0}'
        StatusNoPorts = 'Контроллер не найден: в Windows нет доступных COM-портов'
        StatusSearching = 'Ищем контроллер…'
        StatusCheckingPort = 'Проверяем {0}…'
        StatusConnected = 'Контроллер подключён — {0} · {1} регуляторов'
        StatusNotConnected = 'Контроллер пока не подключён'
        StatusManualNotRecognized = 'На выбранном порту контроллер не распознан'
        StatusAutoNotFound = 'Mugen Deej не найден на доступных COM-портах'
        StatusPortsBusy = 'Mugen Deej не найден. Некоторые COM-порты заняты: {0}'
        StatusLost = 'Связь с контроллером потеряна. Переподключаемся…'
        DriverWorking = 'Драйвер WCH работает — {0}'
        DriverProblem = 'Устройство WCH найдено, но драйвер работает с ошибкой (код {0})'
        DriverCode31 = 'WCH не запустился (код 31). Попробуйте другой USB-порт или питание хаба.'
        DriverPortConflict = 'Конфликт {0}: номер занят другим устройством. Попробуйте другой USB-порт.'
        DriverActiveWorking = 'Драйвер контроллера работает — {0}'
        DriverActiveProblem = 'Драйвер контроллера сообщает об ошибке — {0} (код {1})'
        DriverActiveUnknown = 'Контроллер подключён через {0}, но сведения о его драйвере недоступны'
        DriverInstalledNoDevice = 'Драйвер WCH установлен; контроллер сейчас не подключён'
        DriverAwaitingController = 'Драйвер контроллера будет определён после подключения устройства'
        DriverMissing = 'Драйвер CH340/CH341 не обнаружен'
        DriverUnknown = 'Не удалось проверить драйвер автоматически'
        DriverConfirmText = "Mugen Deej скачает драйвер CH340/CH341 с официального сайта WCH, проверит цифровую подпись производителя и запустит установщик с правами администратора.`r`n`r`nПродолжить?"
        DriverInstallTitle = 'Установка драйвера'
        DriverDownloading = 'Скачиваем официальный установщик WCH…'
        DriverSignatureInvalid = 'Цифровая подпись скачанного файла не принадлежит WCH. Файл не был запущен.'
        DriverLaunching = 'Запускаем установщик WCH…'
        DriverFailedText = "Автоматическая установка не удалась.`r`n`r`n{0}`r`n`r`nСейчас откроется официальная страница WCH."
        AppPickerTitle = 'Выбор приложений — {0}'
        AppPickerHeading = 'Какими приложениями должен управлять этот регулятор?'
        AppPickerHint = 'Верхний список показывает приложения с активной аудиосессией. Ниже можно заранее выбрать запущенные приложения, которые пока молчат.'
        ActiveAudioGroup = 'Сейчас используют звук'
        ActiveAudioEmpty = 'Сейчас ни одно приложение не воспроизводит звук.'
        OtherAppsGroup = 'Запущены без звука или уже сохранены'
        OtherAppsEmpty = 'Других приложений пока нет.'
        OtherAppsHint = 'Для молчащего приложения управление начнёт работать автоматически, как только оно создаст аудиосессию Windows.'
        ApplicationColumn = 'Приложение'
        TechnicalNameColumn = 'Техническое имя'
        AppStateColumn = 'Состояние'
        RunningSilentStatus = 'Запущено, ждёт звук'
        SavedOfflineStatus = 'Сохранено, не запущено'
        ManualAppLabel = 'Не нашли приложение? Добавьте имя процесса вручную:'
        Add = 'Добавить'
        ManualAppHint = 'Можно писать с .exe или без него, с кавычками или без — программа всё нормализует.'
        Cancel = 'Отмена'
        Done = 'Готово'
        Save = 'Сохранить'
        SettingsTitle = 'Настройка регуляторов — Mugen Deej'
        SettingsHeading = 'Настройка физических регуляторов'
        SettingsHint = ('Регуляторы идут слева направо. Их названия можно и нужно менять под назначение — например, «Музыка», «Игра» или «Чат». Названия используются только для отображения и не влияют на подключение.' + "`r`n" + 'Поверните крутилку или передвиньте фейдер: соответствующий индикатор покажет, какой физический регулятор вы настраиваете.')
        HeaderKnob = 'Регулятор'
        HeaderName = 'Название'
        NameHelp = 'Название используется только для отображения. Например: «Музыка», «Игра», «Браузер» или «Микрофон».'
        HeaderMode = 'Режим'
        HeaderControls = 'Что регулируется'
        HeaderPosition = 'Положение'
        PosFarLeft = 'крайний слева'
        PosSecondLeft = 'второй слева'
        PosCenter = 'центральный'
        PosSecondRight = 'второй справа'
        PosFarRight = 'крайний справа'
        PosNumber = 'номер {0}'
        ModeMaster = 'Общая громкость Windows'
        ModeApplications = 'Приложения'
        ModeMicrophone = 'Уровень микрофона'
        DefaultMicrophoneOption = 'Микрофон по умолчанию в Windows — рекомендуется'
        MicrophoneDisconnected = '{0} — устройство не подключено'
        ModeDisabled = 'Не использовать'
        SelectApplications = 'Выбрать приложения'
        ApplicationsNotSelected = 'Приложения не выбраны'
        KnobDisabled = 'Регулятор отключён'
        AdvancedClosed = 'Дополнительные настройки ▼'
        AdvancedOpen = 'Дополнительные настройки ▲'
        InvertAll = 'Инвертировать направление всех регуляторов'
        Responsiveness = 'Отзывчивость:'
        ResponseFast = 'Быстрая'
        ResponseBalanced = 'Сбалансированная'
        ResponseSmooth = 'Очень плавная'
        OpenConfig = 'Открыть config.json'
        FastHint = 'Мгновенная реакция. Возможны небольшие колебания возле неподвижного регулятора.'
        BalancedHint = 'Баланс скорости и подавления дрожания потенциометров.'
        SmoothHint = 'Максимально плавно, но реакция может ощущаться немного медленнее.'
        WizardTitle = 'Первый запуск — Mugen Deej'
        WizardHeading = 'Добро пожаловать в Mugen Deej'
        WizardSteps = ("1. Подключите контроллер к USB.`r`n" + '2. Поверните крутилку или передвиньте фейдер — соответствующий индикатор должен двигаться.' + "`r`n" + '3. Нажмите «Настроить регуляторы». Каждый регулятор можно переименовать и назначить ему общую громкость, приложения или уровень микрофона.')
        CloseHint = 'Закрыть подсказку'
        WizardConnected = '✓ Контроллер подключён — {0}'
        WizardNotFound = 'Контроллер пока не найден. Подключите USB или откройте диагностику.'
    }
    en = @{
        LanguageLabel = 'Language:'
        Subtitle = 'Desktop audio controller'
        Starting = 'Starting…'
        KnobStatus = 'Control status'
        ConfigureKnobs = 'Configure controls'
        ConfigureHint = 'Rename controls and assign master volume, applications, or microphone level.'
        DiagnosticsClosed = 'Connection and diagnostics ▼'
        DiagnosticsOpen = 'Connection and diagnostics ▲'
        ConnectionGroup = 'Controller connection'
        AutoPort = 'Detect COM port automatically'
        ManualPort = 'Select port manually'
        RefreshList = 'Refresh list'
        Reconnect = 'Find and reconnect'
        ConnectionHelp = 'Automatic mode is recommended. Use manual selection when several similar COM devices are connected.'
        DriverAndLog = 'Driver and log'
        Checking = 'Checking…'
        InstallDriver = 'Install driver'
        ReinstallDriver = 'Reinstall driver'
        RepairDriver = 'Repair / reinstall driver'
        InstallOrReinstall = 'Install / reinstall driver'
        OpenLog = 'Open log'
        TrayOpen = 'Open Mugen Deej'
        TraySettings = 'Configure controls'
        TrayReconnect = 'Reconnect controller'
        TrayExit = 'Exit'
        TrayDisconnected = 'Mugen Deej — controller disconnected'
        KnobN = 'Control {0}'
        StatusNoPorts = 'Controller not found: Windows has no available COM ports'
        StatusSearching = 'Searching for controller…'
        StatusCheckingPort = 'Checking {0}…'
        StatusConnected = 'Controller connected — {0} · {1} controls'
        StatusNotConnected = 'Controller is not connected yet'
        StatusManualNotRecognized = 'The controller was not recognized on the selected port'
        StatusAutoNotFound = 'Mugen Deej was not found on available COM ports'
        StatusPortsBusy = 'Mugen Deej was not found. Some COM ports are busy: {0}'
        StatusLost = 'Controller connection lost. Reconnecting…'
        DriverWorking = 'WCH driver is working — {0}'
        DriverProblem = 'A WCH device was found, but its driver reports an error (code {0})'
        DriverCode31 = 'WCH could not start (code 31). Try another USB port or power the hub.'
        DriverPortConflict = '{0} is assigned to multiple devices. Try another USB port.'
        DriverActiveWorking = 'Controller driver is working — {0}'
        DriverActiveProblem = 'Controller driver reports an error — {0} (code {1})'
        DriverActiveUnknown = 'The controller is connected through {0}, but its driver details are unavailable'
        DriverInstalledNoDevice = 'WCH driver is installed; the controller is not connected'
        DriverAwaitingController = 'The controller driver will be identified after the device is connected'
        DriverMissing = 'CH340/CH341 driver was not found'
        DriverUnknown = 'The driver could not be checked automatically'
        DriverConfirmText = "Mugen Deej will download the CH340/CH341 driver from the official WCH website, verify the publisher's digital signature, and start the installer with administrator privileges.`r`n`r`nContinue?"
        DriverInstallTitle = 'Driver installation'
        DriverDownloading = 'Downloading the official WCH installer…'
        DriverSignatureInvalid = 'The downloaded file is not digitally signed by WCH. It was not started.'
        DriverLaunching = 'Starting the WCH installer…'
        DriverFailedText = "Automatic installation failed.`r`n`r`n{0}`r`n`r`nThe official WCH page will now open."
        AppPickerTitle = 'Application selection — {0}'
        AppPickerHeading = 'Which applications should this control manage?'
        AppPickerHint = 'The upper list shows active audio sessions. Below, you can preselect running applications that are currently silent.'
        ActiveAudioGroup = 'Currently using audio'
        ActiveAudioEmpty = 'No application is playing audio right now.'
        OtherAppsGroup = 'Running silently or already saved'
        OtherAppsEmpty = 'No other applications are available yet.'
        OtherAppsHint = 'A silent application will start responding automatically as soon as it creates a Windows audio session.'
        ApplicationColumn = 'Application'
        TechnicalNameColumn = 'Process name'
        AppStateColumn = 'Status'
        RunningSilentStatus = 'Running, waiting for audio'
        SavedOfflineStatus = 'Saved, not running'
        ManualAppLabel = 'Cannot find an application? Add its process name manually:'
        Add = 'Add'
        ManualAppHint = 'You may enter the name with or without .exe and with or without quotes — Mugen Deej normalizes it.'
        Cancel = 'Cancel'
        Done = 'Done'
        Save = 'Save'
        SettingsTitle = 'Control settings — Mugen Deej'
        SettingsHeading = 'Configure physical controls'
        SettingsHint = ('Controls are ordered from left to right. Rename them to match their purpose, for example Music, Game, or Chat. Names are only labels and do not affect the device connection.' + "`r`n" + 'Turn a knob or move a fader: the matching indicator shows which physical control you are configuring.')
        HeaderKnob = 'Control'
        HeaderName = 'Name'
        NameHelp = 'This is only a display label. Examples: Music, Game, Browser, or Microphone.'
        HeaderMode = 'Mode'
        HeaderControls = 'Controls'
        HeaderPosition = 'Position'
        PosFarLeft = 'far left'
        PosSecondLeft = 'second from left'
        PosCenter = 'center'
        PosSecondRight = 'second from right'
        PosFarRight = 'far right'
        PosNumber = 'number {0}'
        ModeMaster = 'Windows master volume'
        ModeApplications = 'Applications'
        ModeMicrophone = 'Microphone level'
        DefaultMicrophoneOption = 'Default Windows microphone — recommended'
        MicrophoneDisconnected = '{0} — device is not connected'
        ModeDisabled = 'Do not use'
        SelectApplications = 'Select applications'
        ApplicationsNotSelected = 'No applications selected'
        KnobDisabled = 'Control disabled'
        AdvancedClosed = 'Advanced settings ▼'
        AdvancedOpen = 'Advanced settings ▲'
        InvertAll = 'Invert the direction of all controls'
        Responsiveness = 'Responsiveness:'
        ResponseFast = 'Fast'
        ResponseBalanced = 'Balanced'
        ResponseSmooth = 'Very smooth'
        OpenConfig = 'Open config.json'
        FastHint = 'Immediate response. Small fluctuations may occur while a control is stationary.'
        BalancedHint = 'A balance between speed and potentiometer jitter suppression.'
        SmoothHint = 'Maximum smoothing, but response may feel slightly slower.'
        WizardTitle = 'First run — Mugen Deej'
        WizardHeading = 'Welcome to Mugen Deej'
        WizardSteps = ('1. Connect the controller by USB.' + "`r`n" + '2. Turn a knob or move a fader — the matching indicator should move.' + "`r`n" + '3. Select "Configure controls". You can rename every control and assign master volume, applications, or microphone level.')
        CloseHint = 'Close guide'
        WizardConnected = '✓ Controller connected — {0}'
        WizardNotFound = 'Controller not found yet. Connect USB or open diagnostics.'
    }
}

function T {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Args = @()
    )
    $lang = if ($script:Strings.ContainsKey($script:Language)) { $script:Language } else { 'en' }
    $text = $script:Strings[$lang][$Key]
    if ($null -eq $text) { $text = $script:Strings['en'][$Key] }
    if ($null -eq $text) { return $Key }
    $value = [string]$text
    if ($Args.Count -gt 0) { return ($value -f $Args) }
    return $value
}

function Get-CaptureDevicesFromPnp {
    $items = @()

    try {
        $pnpCommand = Get-Command Get-PnpDevice -ErrorAction SilentlyContinue
        if ($null -ne $pnpCommand) {
            $items = @(Get-PnpDevice -Class AudioEndpoint -PresentOnly -ErrorAction Stop)
        }
        else {
            $items = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass='AudioEndpoint'" -ErrorAction Stop)
        }
    }
    catch {
        Write-Log "PnP capture-endpoint fallback failed: $($_.Exception.Message)" 'WARN'
        return @()
    }

    $result = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($item in $items) {
        $instanceId = ''
        if ($item.PSObject.Properties.Name -contains 'InstanceId') {
            $instanceId = [string]$item.InstanceId
        }
        elseif ($item.PSObject.Properties.Name -contains 'PNPDeviceID') {
            $instanceId = [string]$item.PNPDeviceID
        }

        if ([string]::IsNullOrWhiteSpace($instanceId)) { continue }
        if ($instanceId -notmatch '^SWD\\MMDEVAPI\\\{0\.0\.1\.') { continue }

        $status = ''
        if ($item.PSObject.Properties.Name -contains 'Status') {
            $status = [string]$item.Status
        }
        if (-not [string]::IsNullOrWhiteSpace($status) -and $status -notin @('OK', 'Unknown')) { continue }

        $endpointId = $instanceId -replace '^SWD\\MMDEVAPI\\', ''
        if ([string]::IsNullOrWhiteSpace($endpointId)) { continue }
        if ($seen.ContainsKey($endpointId)) { continue }

        $friendlyName = ''
        if ($item.PSObject.Properties.Name -contains 'FriendlyName') {
            $friendlyName = [string]$item.FriendlyName
        }
        if ([string]::IsNullOrWhiteSpace($friendlyName) -and ($item.PSObject.Properties.Name -contains 'Name')) {
            $friendlyName = [string]$item.Name
        }
        if ([string]::IsNullOrWhiteSpace($friendlyName)) { $friendlyName = $endpointId }

        $seen[$endpointId] = $true
        [void]$result.Add([pscustomobject]@{
            Id = $endpointId
            Name = $friendlyName
            IsDefault = $false
        })
    }

    return @($result | Sort-Object Name)
}

function Get-CaptureDeviceSignature {
    param([object[]]$Devices = @())
    $rows = @(
        $Devices |
            ForEach-Object { ('{0}`t{1}' -f ([string]$_.Id), ([string]$_.Name)) } |
            Sort-Object
    )
    return ($rows -join "`n")
}

function Refresh-CaptureDeviceCache {
    param([switch]$ForceRefresh)

    $now = Get-Date
    $ageSeconds = if ($script:CaptureDeviceCacheInitialized) {
        ($now - $script:CaptureDeviceCacheAt).TotalSeconds
    }
    else {
        [double]::PositiveInfinity
    }

    $shouldRefresh = -not $script:CaptureDeviceCacheInitialized
    if (-not $shouldRefresh -and $ForceRefresh -and $ageSeconds -ge $script:CaptureDeviceRefreshMinSeconds) {
        $shouldRefresh = $true
    }
    if (-not $shouldRefresh -and -not $ForceRefresh -and $ageSeconds -ge $script:CaptureDeviceCacheTtlSeconds) {
        $shouldRefresh = $true
    }
    if (-not $shouldRefresh) { return }

    $devices = @()
    $source = ''

    if (-not $script:CoreAudioCaptureUnavailable) {
        try {
            $devices = @([MugenDeejAudio.AudioMixer]::GetCaptureDevices())
            if ($devices.Count -gt 0) { $source = 'Core Audio' }
        }
        catch {
            $message = [string]$_.Exception.Message
            if ($message -match 'E_NOINTERFACE|0x80004002|No such interface supported') {
                $script:CoreAudioCaptureUnavailable = $true
                Write-Log 'Core Audio capture enumeration is unavailable for this run (E_NOINTERFACE); using the Windows PnP fallback.' 'WARN'
            }
            else {
                Write-AudioWarningThrottled -Key 'capture-core-audio' -Message "Core Audio capture enumeration failed: $message" -CooldownSeconds 30
            }
            $devices = @()
        }
    }

    if ($devices.Count -eq 0) {
        $devices = @(Get-CaptureDevicesFromPnp)
        $source = 'PnP fallback'
    }

    $signature = Get-CaptureDeviceSignature -Devices $devices
    $changed = (-not $script:CaptureDeviceCacheInitialized) -or ($signature -ne $script:CaptureDeviceCacheSignature)

    $script:CaptureDeviceCache = @($devices)
    $script:CaptureDeviceCacheAt = $now
    $script:CaptureDeviceCacheInitialized = $true
    $script:CaptureDeviceCacheSignature = $signature

    if ($changed) {
        $captureNames = @($script:CaptureDeviceCache | ForEach-Object { [string]$_.Name })
        if ($captureNames.Count -gt 0) {
            Write-Log ("Capture endpoints detected through {0} ({1}): {2}" -f $source, $captureNames.Count, ($captureNames -join ' | ')) 'INFO'
        }
        else {
            Write-AudioWarningThrottled -Key 'capture-empty-list' -Message 'Capture endpoint enumeration returned no active devices through Core Audio or PnP.' -CooldownSeconds 30
        }
    }
}

function Get-MicrophoneOptions {
    param(
        [AllowEmptyString()][string]$SelectedId = '',
        [AllowEmptyString()][string]$SelectedName = '',
        [switch]$ForceRefresh
    )

    $options = New-Object System.Collections.ArrayList
    [void]$options.Add([pscustomobject]@{
        Id = ''
        FriendlyName = ''
        Display = (T -Key 'DefaultMicrophoneOption')
        Available = $true
    })

    $selectedFound = [string]::IsNullOrWhiteSpace($SelectedId)
    try {
        Refresh-CaptureDeviceCache -ForceRefresh:$ForceRefresh
        foreach ($device in @($script:CaptureDeviceCache)) {
            $deviceId = [string]$device.Id
            $deviceName = [string]$device.Name
            if ([string]::IsNullOrWhiteSpace($deviceId)) { continue }
            if ([string]::IsNullOrWhiteSpace($deviceName)) { $deviceName = $deviceId }
            [void]$options.Add([pscustomobject]@{
                Id = $deviceId
                FriendlyName = $deviceName
                Display = $deviceName
                Available = $true
            })
            if ($deviceId -ieq $SelectedId) { $selectedFound = $true }
        }
    }
    catch {
        Write-AudioWarningThrottled -Key 'capture-device-list' -Message "Capture-device enumeration failed: $($_.Exception.Message)"
    }

    if (-not $selectedFound -and -not [string]::IsNullOrWhiteSpace($SelectedId)) {
        $savedName = if ([string]::IsNullOrWhiteSpace($SelectedName)) { $SelectedId } else { $SelectedName }
        [void]$options.Add([pscustomobject]@{
            Id = $SelectedId
            FriendlyName = $savedName
            Display = (T -Key 'MicrophoneDisconnected' -Args @($savedName))
            Available = $false
        })
    }

    return @($options)
}

function Set-MicrophoneComboItems {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.ComboBox]$Combo,
        [AllowEmptyString()][string]$SelectedId = '',
        [AllowEmptyString()][string]$SelectedName = '',
        [switch]$ForceRefresh
    )

    $Combo.BeginUpdate()
    try {
        $Combo.Items.Clear()
        $Combo.DisplayMember = 'Display'
        $selectedIndex = 0
        $index = 0
        foreach ($option in @(Get-MicrophoneOptions -SelectedId $SelectedId -SelectedName $SelectedName -ForceRefresh:$ForceRefresh)) {
            [void]$Combo.Items.Add($option)
            if ([string]$option.Id -ieq $SelectedId) { $selectedIndex = $index }
            $index++
        }
        if ($Combo.Items.Count -gt 0) { $Combo.SelectedIndex = [Math]::Min($selectedIndex, $Combo.Items.Count - 1) }
    }
    finally {
        $Combo.EndUpdate()
    }
}

function Write-AudioWarningThrottled {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Message,
        [int]$CooldownSeconds = 10
    )
    $now = Get-Date
    if ($script:AudioWarningCooldowns.ContainsKey($Key)) {
        $until = [DateTime]$script:AudioWarningCooldowns[$Key]
        if ($now -lt $until) { return }
    }
    Write-Log $Message 'WARN'
    $script:AudioWarningCooldowns[$Key] = $now.AddSeconds([Math]::Max(1, $CooldownSeconds))
}

function Set-DefaultControlNamesForLanguage {
    param([switch]$Save)
    for ($i = 0; $i -lt @($script:Config.sliders).Count; $i++) {
        $slider = $script:Config.sliders[$i]
        if ([bool]$slider.defaultName) {
            $slider.name = (T -Key 'KnobN' -Args @($i + 1))
        }
    }
    if ($Save) { Save-Config -Config $script:Config }
}

Set-DefaultControlNamesForLanguage

function Normalize-TargetName {
    param([AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $target = $Value.Trim()
    $target = $target.Trim([char[]]@([char]34, [char]39, [char]32, [char]9))
    if ($target.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        $target = $target.Substring(0, $target.Length - 4)
    }
    return $target.Trim()
}

function Get-FriendlyProcessName {
    param([AllowEmptyString()][string]$ProcessName)
    $normalized = Normalize-TargetName -Value $ProcessName
    if ([string]::IsNullOrWhiteSpace($normalized)) { return '' }
    $key = $normalized.ToLowerInvariant()
    if ($script:FriendlyProcessNames.ContainsKey($key)) {
        return [string]$script:FriendlyProcessNames[$key]
    }
    return $normalized
}

function Get-TargetSummary {
    param([object[]]$Targets)
    $friendly = @()
    foreach ($targetObject in @($Targets)) {
        $target = Normalize-TargetName -Value ([string]$targetObject)
        if ([string]::IsNullOrWhiteSpace($target) -or $target -ieq 'master' -or $target -ieq 'mic') { continue }
        $name = Get-FriendlyProcessName -ProcessName $target
        if ($friendly -notcontains $name) { $friendly += $name }
    }
    return ($friendly -join ', ')
}

function Get-AudioProcessNames {
    try {
        return @([MugenDeejAudio.AudioMixer]::GetProcessNames())
    }
    catch {
        Write-Log "Audio application scan failed: $($_.Exception.Message)" 'WARN'
        return @()
    }
}

function Get-RunningApplicationProcessNames {
    param([string[]]$IncludeProcessNames = @())

    $results = New-Object System.Collections.Generic.List[string]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $includeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($value in @($IncludeProcessNames)) {
        $normalized = Normalize-TargetName -Value ([string]$value)
        if (-not [string]::IsNullOrWhiteSpace($normalized)) { [void]$includeSet.Add($normalized) }
    }

    $excluded = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @(
        'idle','system','registry','smss','csrss','wininit','services','lsass','svchost','fontdrvhost',
        'winlogon','dwm','sihost','taskhostw','explorer','shellexperiencehost','startmenuexperiencehost',
        'searchhost','searchapp','runtimebroker','applicationframehost','textinputhost','ctfmon','conhost',
        'dllhost','rundll32','audiodg','powershell','pwsh','cmd','mugendeej'
    )) { [void]$excluded.Add($name) }

    $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    $currentSessionId = $currentProcess.SessionId

    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            if ($process.Id -eq 0 -or $process.Id -eq $currentProcess.Id -or $process.HasExited) { continue }
            if ($process.SessionId -ne $currentSessionId) { continue }

            $processName = Normalize-TargetName -Value ([string]$process.ProcessName)
            if ([string]::IsNullOrWhiteSpace($processName) -or $excluded.Contains($processName)) { continue }

            $key = $processName.ToLowerInvariant()
            $hasVisibleWindow = ($process.MainWindowHandle -ne [IntPtr]::Zero -and -not [string]::IsNullOrWhiteSpace([string]$process.MainWindowTitle))
            $isKnownApplication = $script:FriendlyProcessNames.ContainsKey($key)
            $isExplicitlyIncluded = $includeSet.Contains($processName)

            $description = ''
            $executablePath = ''
            try {
                $executablePath = [string]$process.MainModule.FileName
                $description = [string]$process.MainModule.FileVersionInfo.FileDescription
            }
            catch { }

            $isOutsideWindows = (-not [string]::IsNullOrWhiteSpace($executablePath) -and -not $executablePath.StartsWith($env:WINDIR, [System.StringComparison]::OrdinalIgnoreCase))
            $looksLikeBackgroundHelper = ($processName -match '(?i)(crashpad|cefsubprocess|webhelper|helper|updater|update|service|broker|daemon|telemetry|installer|setup)$')
            $isUserApplication = ($isOutsideWindows -and -not $looksLikeBackgroundHelper -and -not [string]::IsNullOrWhiteSpace($description))
            if (-not ($hasVisibleWindow -or $isKnownApplication -or $isExplicitlyIncluded -or $isUserApplication)) { continue }

            if (-not $script:FriendlyProcessNames.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($description) -and $description -ine $processName) {
                $script:FriendlyProcessNames[$key] = $description.Trim()
            }

            if ($seen.Add($processName)) { $results.Add($processName) }
        }
        catch { }
    }

    return @($results.ToArray())
}

function Show-ApplicationPicker {
    param(
        [Parameter(Mandatory = $true)]$Owner,
        [Parameter(Mandatory = $true)][string]$SliderName,
        [object[]]$SelectedTargets = @()
    )

    $pickerForm = New-Object System.Windows.Forms.Form
    $pickerForm.Text = (T -Key 'AppPickerTitle' -Args @($SliderName))
    $pickerForm.StartPosition = 'CenterParent'
    $pickerForm.ClientSize = New-Object System.Drawing.Size(860, 735)
    $pickerForm.MinimumSize = New-Object System.Drawing.Size(876, 774)
    $pickerForm.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $pickerForm.BackColor = [System.Drawing.Color]::FromArgb(247, 247, 249)
    $pickerForm.FormBorderStyle = 'FixedDialog'
    $pickerForm.MaximizeBox = $false
    $pickerForm.MinimizeBox = $false
    Set-FormAppIcon -Form $pickerForm

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = (T -Key 'AppPickerHeading')
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $heading.AutoSize = $true
    $heading.Location = New-Object System.Drawing.Point(22, 18)
    $pickerForm.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = (T -Key 'AppPickerHint')
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = New-Object System.Drawing.Point(25, 54)
    $hint.Size = New-Object System.Drawing.Size(810, 42)
    $pickerForm.Controls.Add($hint)

    $activeGroup = New-Object System.Windows.Forms.GroupBox
    $activeGroup.Text = (T -Key 'ActiveAudioGroup')
    $activeGroup.Location = New-Object System.Drawing.Point(25, 100)
    $activeGroup.Size = New-Object System.Drawing.Size(810, 205)
    $pickerForm.Controls.Add($activeGroup)

    $activeListView = New-Object System.Windows.Forms.ListView
    $activeListView.Location = New-Object System.Drawing.Point(12, 24)
    $activeListView.Size = New-Object System.Drawing.Size(786, 145)
    $activeListView.View = [System.Windows.Forms.View]::Details
    $activeListView.CheckBoxes = $true
    $activeListView.FullRowSelect = $true
    $activeListView.HideSelection = $false
    $activeListView.MultiSelect = $false
    [void]$activeListView.Columns.Add((T -Key 'ApplicationColumn'), 430)
    [void]$activeListView.Columns.Add((T -Key 'TechnicalNameColumn'), 320)
    $activeGroup.Controls.Add($activeListView)

    $activeEmptyLabel = New-Object System.Windows.Forms.Label
    $activeEmptyLabel.Text = (T -Key 'ActiveAudioEmpty')
    $activeEmptyLabel.ForeColor = [System.Drawing.Color]::DimGray
    $activeEmptyLabel.Location = New-Object System.Drawing.Point(15, 174)
    $activeEmptyLabel.Size = New-Object System.Drawing.Size(775, 22)
    $activeGroup.Controls.Add($activeEmptyLabel)

    $otherGroup = New-Object System.Windows.Forms.GroupBox
    $otherGroup.Text = (T -Key 'OtherAppsGroup')
    $otherGroup.Location = New-Object System.Drawing.Point(25, 315)
    $otherGroup.Size = New-Object System.Drawing.Size(810, 235)
    $pickerForm.Controls.Add($otherGroup)

    $otherListView = New-Object System.Windows.Forms.ListView
    $otherListView.Location = New-Object System.Drawing.Point(12, 24)
    $otherListView.Size = New-Object System.Drawing.Size(786, 158)
    $otherListView.View = [System.Windows.Forms.View]::Details
    $otherListView.CheckBoxes = $true
    $otherListView.FullRowSelect = $true
    $otherListView.HideSelection = $false
    $otherListView.MultiSelect = $false
    [void]$otherListView.Columns.Add((T -Key 'ApplicationColumn'), 330)
    [void]$otherListView.Columns.Add((T -Key 'TechnicalNameColumn'), 250)
    [void]$otherListView.Columns.Add((T -Key 'AppStateColumn'), 170)
    $otherGroup.Controls.Add($otherListView)

    $otherHint = New-Object System.Windows.Forms.Label
    $otherHint.Text = (T -Key 'OtherAppsHint')
    $otherHint.ForeColor = [System.Drawing.Color]::DimGray
    $otherHint.Location = New-Object System.Drawing.Point(15, 187)
    $otherHint.Size = New-Object System.Drawing.Size(775, 40)
    $otherGroup.Controls.Add($otherHint)

    $otherEmptyLabel = New-Object System.Windows.Forms.Label
    $otherEmptyLabel.Text = (T -Key 'OtherAppsEmpty')
    $otherEmptyLabel.ForeColor = [System.Drawing.Color]::DimGray
    $otherEmptyLabel.Location = New-Object System.Drawing.Point(15, 187)
    $otherEmptyLabel.Size = New-Object System.Drawing.Size(775, 40)
    $otherEmptyLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $otherGroup.Controls.Add($otherEmptyLabel)

    $refreshAppsButton = New-Object System.Windows.Forms.Button
    $refreshAppsButton.Text = (T -Key 'RefreshList')
    $refreshAppsButton.Location = New-Object System.Drawing.Point(25, 563)
    $refreshAppsButton.Size = New-Object System.Drawing.Size(175, 34)
    $pickerForm.Controls.Add($refreshAppsButton)

    $manualLabel = New-Object System.Windows.Forms.Label
    $manualLabel.Text = (T -Key 'ManualAppLabel')
    $manualLabel.Location = New-Object System.Drawing.Point(220, 567)
    $manualLabel.AutoSize = $true
    $pickerForm.Controls.Add($manualLabel)

    $manualBox = New-Object System.Windows.Forms.TextBox
    $manualBox.Location = New-Object System.Drawing.Point(220, 598)
    $manualBox.Size = New-Object System.Drawing.Size(430, 30)
    $pickerForm.Controls.Add($manualBox)

    $addManualButton = New-Object System.Windows.Forms.Button
    $addManualButton.Text = (T -Key 'Add')
    $addManualButton.Location = New-Object System.Drawing.Point(660, 596)
    $addManualButton.Size = New-Object System.Drawing.Size(175, 34)
    $pickerForm.Controls.Add($addManualButton)

    $manualHint = New-Object System.Windows.Forms.Label
    $manualHint.Text = (T -Key 'ManualAppHint')
    $manualHint.ForeColor = [System.Drawing.Color]::DimGray
    $manualHint.Location = New-Object System.Drawing.Point(25, 640)
    $manualHint.Size = New-Object System.Drawing.Size(610, 38)
    $pickerForm.Controls.Add($manualHint)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = (T -Key 'Cancel')
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelButton.Location = New-Object System.Drawing.Point(635, 685)
    $cancelButton.Size = New-Object System.Drawing.Size(90, 34)
    $pickerForm.Controls.Add($cancelButton)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = (T -Key 'Done')
    $saveButton.Location = New-Object System.Drawing.Point(735, 685)
    $saveButton.Size = New-Object System.Drawing.Size(90, 34)
    $pickerForm.Controls.Add($saveButton)

    $selectedNormalized = @()
    foreach ($target in @($SelectedTargets)) {
        $normalized = Normalize-TargetName -Value ([string]$target)
        if (-not [string]::IsNullOrWhiteSpace($normalized) -and $normalized -ine 'master' -and $normalized -ine 'mic' -and $selectedNormalized -notcontains $normalized) {
            $selectedNormalized += $normalized
        }
    }

    $pickerState = [pscustomobject]@{ InitialPopulate = $true }

    $getCheckedTargets = {
        $checked = @()
        foreach ($view in @($activeListView, $otherListView)) {
            foreach ($item in $view.Items) {
                if (-not $item.Checked) { continue }
                $target = Normalize-TargetName -Value ([string]$item.Tag)
                if (-not [string]::IsNullOrWhiteSpace($target) -and $checked -notcontains $target) { $checked += $target }
            }
        }
        return @($checked)
    }

    $findTargetItem = {
        param([string]$Target)
        foreach ($view in @($activeListView, $otherListView)) {
            foreach ($item in $view.Items) {
                if ([string]$item.Tag -ieq $Target) { return $item }
            }
        }
        return $null
    }

    $populateLists = {
        $checkedNow = if ($pickerState.InitialPopulate) { @($selectedNormalized) } else { @(& $getCheckedTargets) }
        $pickerState.InitialPopulate = $false

        $audioNames = New-Object System.Collections.Generic.List[string]
        $audioSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($candidate in @(Get-AudioProcessNames)) {
            $normalized = Normalize-TargetName -Value ([string]$candidate)
            if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -ieq 'master' -or $normalized -ieq 'mic') { continue }
            if ($audioSet.Add($normalized)) { $audioNames.Add($normalized) }
        }

        $runningNames = New-Object System.Collections.Generic.List[string]
        $runningSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($candidate in @(Get-RunningApplicationProcessNames -IncludeProcessNames $checkedNow)) {
            $normalized = Normalize-TargetName -Value ([string]$candidate)
            if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -ieq 'master' -or $normalized -ieq 'mic') { continue }
            if ($runningSet.Add($normalized)) { $runningNames.Add($normalized) }
        }

        $activeListView.BeginUpdate()
        $otherListView.BeginUpdate()
        try {
            $activeListView.Items.Clear()
            $otherListView.Items.Clear()

            foreach ($processName in @($audioNames | Sort-Object { Get-FriendlyProcessName -ProcessName $_ })) {
                $item = New-Object System.Windows.Forms.ListViewItem((Get-FriendlyProcessName -ProcessName $processName))
                [void]$item.SubItems.Add("$processName.exe")
                $item.Tag = $processName
                $item.Checked = ($checkedNow -contains $processName)
                [void]$activeListView.Items.Add($item)
            }

            foreach ($processName in @($runningNames | Where-Object { -not $audioSet.Contains($_) } | Sort-Object { Get-FriendlyProcessName -ProcessName $_ })) {
                $item = New-Object System.Windows.Forms.ListViewItem((Get-FriendlyProcessName -ProcessName $processName))
                [void]$item.SubItems.Add("$processName.exe")
                [void]$item.SubItems.Add((T -Key 'RunningSilentStatus'))
                $item.Tag = $processName
                $item.Checked = ($checkedNow -contains $processName)
                [void]$otherListView.Items.Add($item)
            }

            foreach ($processName in @($checkedNow | Where-Object { -not $audioSet.Contains($_) -and -not $runningSet.Contains($_) } | Sort-Object { Get-FriendlyProcessName -ProcessName $_ })) {
                $item = New-Object System.Windows.Forms.ListViewItem((Get-FriendlyProcessName -ProcessName $processName))
                [void]$item.SubItems.Add("$processName.exe")
                [void]$item.SubItems.Add((T -Key 'SavedOfflineStatus'))
                $item.Tag = $processName
                $item.Checked = $true
                [void]$otherListView.Items.Add($item)
            }
        }
        finally {
            $activeListView.EndUpdate()
            $otherListView.EndUpdate()
        }

        $activeGroup.Text = ('{0} ({1})' -f (T -Key 'ActiveAudioGroup'), $activeListView.Items.Count)
        $otherGroup.Text = ('{0} ({1})' -f (T -Key 'OtherAppsGroup'), $otherListView.Items.Count)
        $activeEmptyLabel.Visible = ($activeListView.Items.Count -eq 0)
        $otherEmptyLabel.Visible = ($otherListView.Items.Count -eq 0)
        $otherHint.Visible = -not $otherEmptyLabel.Visible
    }

    $refreshAppsButton.Add_Click({ & $populateLists })
    $addManualButton.Add_Click({
        $target = Normalize-TargetName -Value $manualBox.Text
        if ([string]::IsNullOrWhiteSpace($target) -or $target -ieq 'master' -or $target -ieq 'mic') { return }

        $existing = & $findTargetItem $target
        if ($null -ne $existing) {
            $existing.Checked = $true
            $existing.EnsureVisible()
            $manualBox.Clear()
            return
        }

        $item = New-Object System.Windows.Forms.ListViewItem((Get-FriendlyProcessName -ProcessName $target))
        [void]$item.SubItems.Add("$target.exe")
        [void]$item.SubItems.Add((T -Key 'SavedOfflineStatus'))
        $item.Tag = $target
        $item.Checked = $true
        [void]$otherListView.Items.Add($item)
        $otherGroup.Text = ('{0} ({1})' -f (T -Key 'OtherAppsGroup'), $otherListView.Items.Count)
        $otherEmptyLabel.Visible = $false
        $otherHint.Visible = $true
        $item.EnsureVisible()
        $manualBox.Clear()
    })
    $manualBox.Add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $addManualButton.PerformClick()
            $eventArgs.SuppressKeyPress = $true
        }
    })
    $saveButton.Add_Click({
        $chosen = @(& $getCheckedTargets)
        $pickerForm.Tag = [object[]]@($chosen)
        $pickerForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $pickerForm.Close()
    })

    & $populateLists
    $pickerForm.AcceptButton = $saveButton
    $pickerForm.CancelButton = $cancelButton
    $result = $pickerForm.ShowDialog($Owner)
    $chosenResult = if ($result -eq [System.Windows.Forms.DialogResult]::OK) { [object[]]@($pickerForm.Tag) } else { [object[]]@($selectedNormalized) }
    $pickerForm.Dispose()
    return ,$chosenResult
}

function Show-SliderSettings {
    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = (T -Key 'SettingsTitle')
    $settingsForm.StartPosition = 'CenterParent'
    $settingsForm.ClientSize = New-Object System.Drawing.Size(1110, 735)
    $settingsForm.MinimumSize = New-Object System.Drawing.Size(1126, 774)
    $settingsForm.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $settingsForm.BackColor = [System.Drawing.Color]::FromArgb(247, 247, 249)
    $settingsForm.FormBorderStyle = 'FixedDialog'
    $settingsForm.MaximizeBox = $false
    $settingsForm.MinimizeBox = $false
    Set-FormAppIcon -Form $settingsForm

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = (T -Key 'SettingsHeading')
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = New-Object System.Drawing.Point(22, 18)
    $settingsForm.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = (T -Key 'SettingsHint')
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = New-Object System.Drawing.Point(25, 56)
    $hint.Size = New-Object System.Drawing.Size(1055, 58)
    $settingsForm.Controls.Add($hint)

    $headers = @(
        @{ Text = (T -Key 'HeaderKnob'); X = 24; Width = 120 },
        @{ Text = (T -Key 'HeaderName'); X = 150; Width = 160 },
        @{ Text = (T -Key 'HeaderMode'); X = 322; Width = 190 },
        @{ Text = (T -Key 'HeaderControls'); X = 524; Width = 260 },
        @{ Text = (T -Key 'HeaderPosition'); X = 930; Width = 130 }
    )
    foreach ($headerInfo in $headers) {
        $header = New-Object System.Windows.Forms.Label
        $header.Text = $headerInfo.Text
        $header.Location = New-Object System.Drawing.Point($headerInfo.X, 122)
        $header.Size = New-Object System.Drawing.Size($headerInfo.Width, 24)
        $settingsForm.Controls.Add($header)
    }

    $nameBoxes = New-Object System.Collections.ArrayList
    $nameToolTip = New-Object System.Windows.Forms.ToolTip
    $modeCombos = New-Object System.Collections.ArrayList
    $summaryLabels = New-Object System.Collections.ArrayList
    $selectButtons = New-Object System.Collections.ArrayList
    $progressBars = New-Object System.Collections.ArrayList
    $percentLabels = New-Object System.Collections.ArrayList
    $targetSelections = New-Object System.Collections.ArrayList
    $microphoneCombos = New-Object System.Collections.ArrayList
    $count = [int]$script:Config.connection.expectedSliders
    $positions = @((T -Key 'PosFarLeft'), (T -Key 'PosSecondLeft'), (T -Key 'PosCenter'), (T -Key 'PosSecondRight'), (T -Key 'PosFarRight'))

    for ($i = 0; $i -lt $count; $i++) {
        $y = 150 + ($i * 76)
        $rowPanel = New-Object System.Windows.Forms.Panel
        $rowPanel.Location = New-Object System.Drawing.Point(20, $y)
        $rowPanel.Size = New-Object System.Drawing.Size(1070, 66)
        $rowPanel.BackColor = [System.Drawing.Color]::White
        $rowPanel.BorderStyle = 'FixedSingle'
        $settingsForm.Controls.Add($rowPanel)

        $position = if ($i -lt $positions.Count) { $positions[$i] } else { (T -Key 'PosNumber' -Args @($i + 1)) }
        $indexLabel = New-Object System.Windows.Forms.Label
        $indexLabel.Text = "$($i + 1) · $position"
        $indexLabel.Location = New-Object System.Drawing.Point(8, 9)
        $indexLabel.Size = New-Object System.Drawing.Size(116, 45)
        $indexLabel.TextAlign = 'MiddleLeft'
        $rowPanel.Controls.Add($indexLabel)

        $nameBox = New-Object System.Windows.Forms.TextBox
        $nameBox.Location = New-Object System.Drawing.Point(128, 17)
        $nameBox.Size = New-Object System.Drawing.Size(160, 30)
        if ($i -lt $script:Config.sliders.Count) { $nameBox.Text = [string]$script:Config.sliders[$i].name }
        else { $nameBox.Text = (T -Key 'KnobN' -Args @($i + 1)) }
        $rowPanel.Controls.Add($nameBox)
        $nameToolTip.SetToolTip($nameBox, (T -Key 'NameHelp'))
        [void]$nameBoxes.Add($nameBox)

        $targets = @()
        if ($i -lt $script:Config.sliders.Count) {
            foreach ($targetObject in @($script:Config.sliders[$i].targets)) {
                $target = Normalize-TargetName -Value ([string]$targetObject)
                if (-not [string]::IsNullOrWhiteSpace($target) -and $targets -notcontains $target) { $targets += $target }
            }
        }
        $applicationTargets = @($targets | Where-Object { $_ -ine 'master' -and $_ -ine 'mic' })
        [void]$targetSelections.Add([object[]]@($applicationTargets))
        $selectedInputDeviceId = ''
        $selectedInputDeviceName = ''
        if ($i -lt $script:Config.sliders.Count) {
            $selectedInputDeviceId = [string]$script:Config.sliders[$i].inputDeviceId
            $selectedInputDeviceName = [string]$script:Config.sliders[$i].inputDeviceName
        }

        $modeCombo = New-Object System.Windows.Forms.ComboBox
        $modeCombo.DropDownStyle = 'DropDownList'
        $modeCombo.Location = New-Object System.Drawing.Point(300, 16)
        $modeCombo.Size = New-Object System.Drawing.Size(190, 30)
        $modeCombo.Tag = $i
        [void]$modeCombo.Items.Add((T -Key 'ModeMaster'))
        [void]$modeCombo.Items.Add((T -Key 'ModeApplications'))
        [void]$modeCombo.Items.Add((T -Key 'ModeMicrophone'))
        [void]$modeCombo.Items.Add((T -Key 'ModeDisabled'))
        if ($targets -contains 'master') { $modeCombo.SelectedIndex = 0 }
        elseif ($targets -contains 'mic') { $modeCombo.SelectedIndex = 2 }
        elseif ($targets.Count -gt 0) { $modeCombo.SelectedIndex = 1 }
        else { $modeCombo.SelectedIndex = 3 }
        $rowPanel.Controls.Add($modeCombo)
        [void]$modeCombos.Add($modeCombo)

        $summaryLabel = New-Object System.Windows.Forms.Label
        $summaryLabel.Location = New-Object System.Drawing.Point(502, 8)
        $summaryLabel.Size = New-Object System.Drawing.Size(215, 48)
        $summaryLabel.TextAlign = 'MiddleLeft'
        $summaryLabel.AutoEllipsis = $true
        $rowPanel.Controls.Add($summaryLabel)
        [void]$summaryLabels.Add($summaryLabel)

        $selectButton = New-Object System.Windows.Forms.Button
        $selectButton.Text = (T -Key 'SelectApplications')
        $selectButton.Location = New-Object System.Drawing.Point(722, 15)
        $selectButton.Size = New-Object System.Drawing.Size(180, 34)
        $selectButton.Tag = $i
        $rowPanel.Controls.Add($selectButton)
        [void]$selectButtons.Add($selectButton)

        $microphoneCombo = New-Object System.Windows.Forms.ComboBox
        $microphoneCombo.DropDownStyle = 'DropDownList'
        $microphoneCombo.Location = New-Object System.Drawing.Point(502, 16)
        $microphoneCombo.Size = New-Object System.Drawing.Size(400, 30)
        $microphoneCombo.DropDownWidth = 520
        $microphoneCombo.Tag = $i
        Set-MicrophoneComboItems -Combo $microphoneCombo -SelectedId $selectedInputDeviceId -SelectedName $selectedInputDeviceName
        $microphoneCombo.Visible = $false
        $rowPanel.Controls.Add($microphoneCombo)
        [void]$microphoneCombos.Add($microphoneCombo)

        $progressBar = New-Object System.Windows.Forms.ProgressBar
        $progressBar.Location = New-Object System.Drawing.Point(914, 17)
        $progressBar.Size = New-Object System.Drawing.Size(105, 23)
        $progressBar.Minimum = 0
        $progressBar.Maximum = 1000
        $rowPanel.Controls.Add($progressBar)
        [void]$progressBars.Add($progressBar)

        $percentLabel = New-Object System.Windows.Forms.Label
        $percentLabel.Text = '—'
        $percentLabel.Location = New-Object System.Drawing.Point(1022, 17)
        $percentLabel.Size = New-Object System.Drawing.Size(42, 25)
        $percentLabel.TextAlign = 'MiddleRight'
        $rowPanel.Controls.Add($percentLabel)
        [void]$percentLabels.Add($percentLabel)
    }

    $updateRowSummary = {
        param([int]$Index)
        $mode = $modeCombos[$Index].SelectedIndex
        $summaryLabels[$Index].Visible = $true
        $selectButtons[$Index].Visible = $true
        $microphoneCombos[$Index].Visible = $false
        if ($mode -eq 0) {
            $summaryLabels[$Index].Text = (T -Key 'ModeMaster')
            $selectButtons[$Index].Enabled = $false
        }
        elseif ($mode -eq 1) {
            $summary = Get-TargetSummary -Targets @($targetSelections[$Index])
            $summaryLabels[$Index].Text = if ([string]::IsNullOrWhiteSpace($summary)) { (T -Key 'ApplicationsNotSelected') } else { $summary }
            $selectButtons[$Index].Enabled = $true
        }
        elseif ($mode -eq 2) {
            $summaryLabels[$Index].Visible = $false
            $selectButtons[$Index].Visible = $false
            $microphoneCombos[$Index].Visible = $true
        }
        else {
            $summaryLabels[$Index].Text = (T -Key 'KnobDisabled')
            $selectButtons[$Index].Enabled = $false
        }
    }

    for ($i = 0; $i -lt $count; $i++) {
        $modeCombos[$i].Add_SelectedIndexChanged({
            param($sender, $eventArgs)
            & $updateRowSummary ([int]$sender.Tag)
        })
        $selectButtons[$i].Add_Click({
            param($sender, $eventArgs)
            $idx = [int]$sender.Tag
            $sliderName = [string]$nameBoxes[$idx].Text
            if ([string]::IsNullOrWhiteSpace($sliderName)) { $sliderName = (T -Key 'KnobN' -Args @($idx + 1)) }
            $newTargets = Show-ApplicationPicker -Owner $settingsForm -SliderName $sliderName -SelectedTargets @($targetSelections[$idx])
            $targetSelections[$idx] = [object[]]@($newTargets)
            & $updateRowSummary $idx
        })
        $microphoneCombos[$i].Add_DropDown({
            param($sender, $eventArgs)
            $currentItem = $sender.SelectedItem
            $currentId = if ($null -eq $currentItem) { '' } else { [string]$currentItem.Id }
            $currentName = if ($null -eq $currentItem) { '' } else { [string]$currentItem.FriendlyName }
            Set-MicrophoneComboItems -Combo $sender -SelectedId $currentId -SelectedName $currentName -ForceRefresh
        })
        & $updateRowSummary $i
    }

    $advancedToggle = New-Object System.Windows.Forms.Button
    $advancedToggle.Text = (T -Key 'AdvancedClosed')
    $advancedToggle.Location = New-Object System.Drawing.Point(25, 540)
    $advancedToggle.Size = New-Object System.Drawing.Size(245, 34)
    $settingsForm.Controls.Add($advancedToggle)

    $advancedPanel = New-Object System.Windows.Forms.Panel
    $advancedPanel.Location = New-Object System.Drawing.Point(25, 578)
    $advancedPanel.Size = New-Object System.Drawing.Size(780, 112)
    $advancedPanel.Visible = $false
    $settingsForm.Controls.Add($advancedPanel)

    $invertCheck = New-Object System.Windows.Forms.CheckBox
    $invertCheck.Text = (T -Key 'InvertAll')
    $invertCheck.AutoSize = $true
    $invertCheck.Checked = [bool]$script:Config.behavior.invertSliders
    $invertCheck.Location = New-Object System.Drawing.Point(0, 8)
    $advancedPanel.Controls.Add($invertCheck)

    $responseLabel = New-Object System.Windows.Forms.Label
    $responseLabel.Text = (T -Key 'Responsiveness')
    $responseLabel.Location = New-Object System.Drawing.Point(0, 42)
    $responseLabel.Size = New-Object System.Drawing.Size(110, 25)
    $advancedPanel.Controls.Add($responseLabel)

    $responseCombo = New-Object System.Windows.Forms.ComboBox
    $responseCombo.DropDownStyle = 'DropDownList'
    $responseCombo.Location = New-Object System.Drawing.Point(110, 38)
    $responseCombo.Size = New-Object System.Drawing.Size(255, 30)
    [void]$responseCombo.Items.Add((T -Key 'ResponseFast'))
    [void]$responseCombo.Items.Add((T -Key 'ResponseBalanced'))
    [void]$responseCombo.Items.Add((T -Key 'ResponseSmooth'))
    $currentThreshold = [double]$script:Config.behavior.noiseThreshold
    if ($currentThreshold -le 0.004) { $responseCombo.SelectedIndex = 0 }
    elseif ($currentThreshold -le 0.009) { $responseCombo.SelectedIndex = 1 }
    else { $responseCombo.SelectedIndex = 2 }
    $advancedPanel.Controls.Add($responseCombo)

    $responseHint = New-Object System.Windows.Forms.Label
    $responseHint.ForeColor = [System.Drawing.Color]::DimGray
    $responseHint.Location = New-Object System.Drawing.Point(380, 35)
    $responseHint.Size = New-Object System.Drawing.Size(355, 48)
    $advancedPanel.Controls.Add($responseHint)

    $advancedConfigButton = New-Object System.Windows.Forms.Button
    $advancedConfigButton.Text = (T -Key 'OpenConfig')
    $advancedConfigButton.Location = New-Object System.Drawing.Point(0, 74)
    $advancedConfigButton.Size = New-Object System.Drawing.Size(190, 32)
    $advancedPanel.Controls.Add($advancedConfigButton)

    $updateResponseHint = {
        switch ($responseCombo.SelectedIndex) {
            0 { $responseHint.Text = (T -Key 'FastHint') }
            1 { $responseHint.Text = (T -Key 'BalancedHint') }
            default { $responseHint.Text = (T -Key 'SmoothHint') }
        }
    }
    $responseCombo.Add_SelectedIndexChanged({ & $updateResponseHint })
    & $updateResponseHint

    $advancedToggle.Add_Click({
        $advancedPanel.Visible = -not $advancedPanel.Visible
        $advancedToggle.Text = if ($advancedPanel.Visible) { (T -Key 'AdvancedOpen') } else { (T -Key 'AdvancedClosed') }
    })
    $advancedConfigButton.Add_Click({ Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:ConfigPath) })

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = (T -Key 'Cancel')
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelButton.Location = New-Object System.Drawing.Point(870, 677)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 36)
    $settingsForm.Controls.Add($cancelButton)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = (T -Key 'Save')
    $saveButton.Location = New-Object System.Drawing.Point(982, 677)
    $saveButton.Size = New-Object System.Drawing.Size(105, 36)
    $settingsForm.Controls.Add($saveButton)

    $liveTimer = New-Object System.Windows.Forms.Timer
    $liveTimer.Interval = 50
    $liveTimer.Add_Tick({
        for ($i = 0; $i -lt $count; $i++) {
            if ($script:LatestLevels.Count -gt $i) {
                $level = [Math]::Max(0.0, [Math]::Min(1.0, [double]$script:LatestLevels[$i]))
                $progressBars[$i].Value = [int][Math]::Round($level * 1000)
                $percentLabels[$i].Text = ('{0}%' -f [int][Math]::Round($level * 100))
            }
            else {
                $progressBars[$i].Value = 0
                $percentLabels[$i].Text = '—'
            }
        }
    })

    $saveButton.Add_Click({
        $newSliders = @()
        for ($i = 0; $i -lt $count; $i++) {
            $name = ([string]$nameBoxes[$i].Text).Trim()
            $defaultDisplayName = (T -Key 'KnobN' -Args @($i + 1))
            if ([string]::IsNullOrWhiteSpace($name)) { $name = $defaultDisplayName }
            $isDefaultName = ($name -eq $defaultDisplayName)
            $mode = $modeCombos[$i].SelectedIndex
            $targets = @()
            $inputDeviceId = ''
            $inputDeviceName = ''
            if ($mode -eq 0) {
                $targets = @('master')
            }
            elseif ($mode -eq 1) {
                foreach ($targetObject in @($targetSelections[$i])) {
                    $target = Normalize-TargetName -Value ([string]$targetObject)
                    if (-not [string]::IsNullOrWhiteSpace($target) -and $targets -notcontains $target) { $targets += $target }
                }
            }
            elseif ($mode -eq 2) {
                $targets = @('mic')
                $selectedMicrophone = $microphoneCombos[$i].SelectedItem
                if ($null -ne $selectedMicrophone) {
                    $inputDeviceId = [string]$selectedMicrophone.Id
                    $inputDeviceName = [string]$selectedMicrophone.FriendlyName
                }
            }
            $newSliders += [pscustomobject]@{
                name = $name
                defaultName = $isDefaultName
                targets = @($targets)
                inputDeviceId = $inputDeviceId
                inputDeviceName = $inputDeviceName
            }
        }

        $script:Config.sliders = @($newSliders)
        $script:Config.app.firstRunCompleted = $true
        $script:Config.behavior.invertSliders = [bool]$invertCheck.Checked
        switch ($responseCombo.SelectedIndex) {
            0 { $script:Config.behavior.noiseThreshold = 0.003 }
            1 { $script:Config.behavior.noiseThreshold = 0.007 }
            default { $script:Config.behavior.noiseThreshold = 0.015 }
        }
        Save-Config -Config $script:Config
        $script:LastValues = @()
        [MugenDeejAudio.AudioMixer]::InvalidateSessions()
        Refresh-KnobLabels
        Write-Log "Slider settings saved from user-friendly UI: $(Get-ConfigSummary -Config $script:Config)"
        $settingsForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $settingsForm.Close()
    })

    $settingsForm.Add_FormClosed({ $liveTimer.Stop(); $liveTimer.Dispose(); $nameToolTip.Dispose() })
    $settingsForm.AcceptButton = $saveButton
    $settingsForm.CancelButton = $cancelButton
    $liveTimer.Start()
    [void]$settingsForm.ShowDialog($form)
    $settingsForm.Dispose()
}

function Show-FirstRunWizard {
    $wizard = New-Object System.Windows.Forms.Form
    $wizard.Text = (T -Key 'WizardTitle')
    $wizard.StartPosition = 'CenterParent'
    $wizard.ClientSize = New-Object System.Drawing.Size(660, 505)
    $wizard.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $wizard.BackColor = [System.Drawing.Color]::FromArgb(247, 247, 249)
    $wizard.FormBorderStyle = 'FixedDialog'
    $wizard.MaximizeBox = $false
    $wizard.MinimizeBox = $false
    Set-FormAppIcon -Form $wizard

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = (T -Key 'WizardHeading')
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17)
    $heading.AutoSize = $true
    $heading.Location = New-Object System.Drawing.Point(24, 20)
    $wizard.Controls.Add($heading)

    $steps = New-Object System.Windows.Forms.Label
    $steps.Text = (T -Key 'WizardSteps')
    $steps.Location = New-Object System.Drawing.Point(27, 62)
    $steps.Size = New-Object System.Drawing.Size(600, 110)
    $wizard.Controls.Add($steps)

    $connectionLabel = New-Object System.Windows.Forms.Label
    $connectionLabel.Location = New-Object System.Drawing.Point(27, 168)
    $connectionLabel.Size = New-Object System.Drawing.Size(600, 30)
    $connectionLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $wizard.Controls.Add($connectionLabel)

    $wizardBars = @()
    $wizardPercents = @()
    for ($i = 0; $i -lt 5; $i++) {
        $y = 208 + ($i * 42)
        $label = New-Object System.Windows.Forms.Label
        $label.Text = (T -Key 'KnobN' -Args @($i + 1))
        $label.Location = New-Object System.Drawing.Point(28, $y)
        $label.Size = New-Object System.Drawing.Size(90, 24)
        $wizard.Controls.Add($label)

        $bar = New-Object System.Windows.Forms.ProgressBar
        $bar.Location = New-Object System.Drawing.Point(120, $y)
        $bar.Size = New-Object System.Drawing.Size(420, 23)
        $bar.Maximum = 1000
        $wizard.Controls.Add($bar)
        $wizardBars += $bar

        $percent = New-Object System.Windows.Forms.Label
        $percent.Text = '—'
        $percent.Location = New-Object System.Drawing.Point(548, $y)
        $percent.Size = New-Object System.Drawing.Size(60, 24)
        $percent.TextAlign = 'MiddleRight'
        $wizard.Controls.Add($percent)
        $wizardPercents += $percent
    }

    $laterButton = New-Object System.Windows.Forms.Button
    $laterButton.Text = (T -Key 'CloseHint')
    $laterButton.Location = New-Object System.Drawing.Point(305, 452)
    $laterButton.Size = New-Object System.Drawing.Size(155, 36)
    $wizard.Controls.Add($laterButton)

    $configureButton = New-Object System.Windows.Forms.Button
    $configureButton.Text = (T -Key 'ConfigureKnobs')
    $configureButton.Location = New-Object System.Drawing.Point(472, 452)
    $configureButton.Size = New-Object System.Drawing.Size(160, 36)
    $wizard.Controls.Add($configureButton)

    $wizardTimer = New-Object System.Windows.Forms.Timer
    $wizardTimer.Interval = 70
    $wizardTimer.Add_Tick({
        $connectionLabel.Text = if ($script:IsConnected) { (T -Key 'WizardConnected' -Args @($script:ConnectedPort)) } else { (T -Key 'WizardNotFound') }
        $connectionLabel.ForeColor = if ($script:IsConnected) { [System.Drawing.Color]::SeaGreen } else { [System.Drawing.Color]::DarkOrange }
        for ($i = 0; $i -lt 5; $i++) {
            if ($script:LatestLevels.Count -gt $i) {
                $level = [Math]::Max(0.0, [Math]::Min(1.0, [double]$script:LatestLevels[$i]))
                $wizardBars[$i].Value = [int][Math]::Round($level * 1000)
                $wizardPercents[$i].Text = ('{0}%' -f [int][Math]::Round($level * 100))
            }
        }
    })

    $finishWizard = {
        $script:Config.app.firstRunCompleted = $true
        Save-Config -Config $script:Config
    }
    $laterButton.Add_Click({ & $finishWizard; $wizard.Close() })
    $configureButton.Add_Click({ & $finishWizard; $wizard.Close(); Show-SliderSettings })
    $wizard.Add_FormClosing({
        if (-not [bool]$script:Config.app.firstRunCompleted) { & $finishWizard }
    })
    $wizard.Add_FormClosed({ $wizardTimer.Stop(); $wizardTimer.Dispose() })
    $wizardTimer.Start()
    [void]$wizard.ShowDialog($form)
    $wizard.Dispose()
}

function Get-PortNames {
    return @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object { [int]($_ -replace '\D','0') })
}

function Clear-PortProbeCooldown {
    param([Parameter(Mandatory = $true)][string]$PortName)
    if ($script:PortProbeCooldowns.ContainsKey($PortName)) {
        [void]$script:PortProbeCooldowns.Remove($PortName)
    }
}

function Reset-PortProbeState {
    param([Parameter(Mandatory = $true)][string]$PortName)
    Clear-PortProbeCooldown -PortName $PortName
    if ($script:PortProbeFailureCounts.ContainsKey($PortName)) {
        [void]$script:PortProbeFailureCounts.Remove($PortName)
    }
}

function Clear-AllPortProbeCooldowns {
    $hadState = ($script:PortProbeCooldowns.Count -gt 0) -or ($script:PortProbeFailureCounts.Count -gt 0)
    $script:PortProbeCooldowns.Clear()
    $script:PortProbeFailureCounts.Clear()
    if ($hadState) {
        Write-Log 'Temporary COM-port probe cache cleared' 'DEBUG'
    }
}

function Set-PortProbeCooldown {
    param(
        [Parameter(Mandatory = $true)][string]$PortName,
        [Parameter(Mandatory = $true)][int]$Seconds
    )
    $script:PortProbeCooldowns[$PortName] = (Get-Date).AddSeconds([Math]::Max(1, $Seconds))
}

function Register-PortProbeFailure {
    param(
        [Parameter(Mandatory = $true)][string]$PortName,
        [switch]$Busy
    )

    $count = 1
    if ($script:PortProbeFailureCounts.ContainsKey($PortName)) {
        $count = [int]$script:PortProbeFailureCounts[$PortName] + 1
    }
    $script:PortProbeFailureCounts[$PortName] = $count

    if ($Busy) {
        $power = [Math]::Min(4, [Math]::Max(0, $count - 1))
        $seconds = [int][Math]::Min(
            $script:BusyPortCooldownMaxSeconds,
            $script:BusyPortCooldownBaseSeconds * [Math]::Pow(2, $power)
        )
    }
    else {
        $seconds = [int]$script:FailedOpenCooldownSeconds
    }

    Set-PortProbeCooldown -PortName $PortName -Seconds $seconds
    return $seconds
}

function Test-IsPortBusyError {
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        if ($exception -is [System.UnauthorizedAccessException]) { return $true }
        $message = [string]$exception.Message
        if ($message -match 'access to the port.+denied|access.+denied|доступ к порту.+закрыт|отказано в доступе') {
            return $true
        }
        $exception = $exception.InnerException
    }
    return $false
}

function Test-PortProbeAllowed {
    param([Parameter(Mandatory = $true)][string]$PortName)
    if (-not $script:PortProbeCooldowns.ContainsKey($PortName)) { return $true }
    $until = [DateTime]$script:PortProbeCooldowns[$PortName]
    if ((Get-Date) -ge $until) {
        [void]$script:PortProbeCooldowns.Remove($PortName)
        return $true
    }
    return $false
}

function Add-PendingNewPorts {
    param([string[]]$Ports)
    foreach ($port in @($Ports)) {
        if ([string]::IsNullOrWhiteSpace($port)) { continue }
        Reset-PortProbeState -PortName $port
        if ($script:PendingNewPorts -notcontains $port) {
            $script:PendingNewPorts += $port
        }
    }
}

function Test-ProtocolLine {
    param(
        [string]$Line,
        [int]$ExpectedCount
    )
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    $parts = $Line.Trim() -split '\|'
    if ($parts.Count -ne $ExpectedCount) { return $null }
    $values = New-Object int[] $ExpectedCount
    for ($i = 0; $i -lt $ExpectedCount; $i++) {
        $value = 0
        if (-not [int]::TryParse($parts[$i], [ref]$value)) { return $null }
        if ($value -lt 0 -or $value -gt 1023) { return $null }
        $values[$i] = $value
    }
    return ,$values
}

function Close-ControllerPort {
    if ($null -ne $script:Serial) {
        try {
            if ($script:Serial.IsOpen) { $script:Serial.Close() }
        }
        catch { }
        try { $script:Serial.Dispose() } catch { }
    }
    $script:Serial = $null
    $script:SerialBuffer = ''
    $script:IsConnected = $false
    $script:ConnectedPort = ''
    $script:LastSerialPacketAt = [DateTime]::MinValue
    $script:LatestLevels = @()
}

function Open-And-ProbePort {
    param([Parameter(Mandatory = $true)][string]$PortName)

    $serial = New-Object System.IO.Ports.SerialPort
    $serial.PortName = $PortName
    $serial.BaudRate = [int]$script:Config.connection.baudRate
    $serial.Parity = [System.IO.Ports.Parity]::None
    $serial.DataBits = 8
    $serial.StopBits = [System.IO.Ports.StopBits]::One
    $serial.Handshake = [System.IO.Ports.Handshake]::None
    $serial.DtrEnable = $false
    $serial.RtsEnable = $false
    $serial.ReadTimeout = 200
    $serial.WriteTimeout = 200
    $serial.NewLine = "`n"

    try {
        Write-Log "Probing $PortName"
        $serial.Open()
        if ($script:PortProbeFailureCounts.ContainsKey($PortName)) {
            [void]$script:PortProbeFailureCounts.Remove($PortName)
        }
        $deadline = (Get-Date).AddMilliseconds([int]$script:Config.connection.startupWaitMs + 2800)
        $readyAfter = (Get-Date).AddMilliseconds([int]$script:Config.connection.startupWaitMs)
        $buffer = ''

        while ((Get-Date) -lt $deadline) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 40
            if ((Get-Date) -lt $readyAfter) { continue }
            $chunk = $serial.ReadExisting()
            if ($chunk.Length -eq 0) { continue }
            $buffer += $chunk
            while ($buffer.Contains("`n")) {
                $idx = $buffer.IndexOf("`n")
                $line = $buffer.Substring(0, $idx).Trim("`r", "`n", " ", "`t")
                $buffer = $buffer.Substring($idx + 1)
                $parsed = Test-ProtocolLine -Line $line -ExpectedCount ([int]$script:Config.connection.expectedSliders)
                if ($null -ne $parsed) {
                    $script:Serial = $serial
                    $script:SerialBuffer = $buffer
                    $script:IsConnected = $true
                    $script:ConnectedPort = $PortName
                    $script:LastSerialPacketAt = Get-Date
                    $script:Config.connection.lastWorkingPort = $PortName
                    Clear-PortProbeCooldown -PortName $PortName
                    $script:PendingNewPorts = @($script:PendingNewPorts | Where-Object { $_ -ne $PortName })
                    Save-Config -Config $script:Config
                    Write-Log "Controller detected on $PortName"
                    return $true
                }
            }
        }
        Write-Log "$PortName opened, but Mugen Deej protocol was not detected" 'WARN'
        Set-PortProbeCooldown -PortName $PortName -Seconds $script:NegativeProbeCooldownSeconds
    }
    catch {
        if (Test-IsPortBusyError -ErrorRecord $_) {
            if ($script:LastScanBusyPorts -notcontains $PortName) {
                $script:LastScanBusyPorts += $PortName
            }
            $retrySeconds = Register-PortProbeFailure -PortName $PortName -Busy
            Write-Log "$PortName is busy or held by another application; retry in $retrySeconds s" 'WARN'
        }
        else {
            $retrySeconds = Register-PortProbeFailure -PortName $PortName
            Write-Log "Failed to open ${PortName}: $($_.Exception.Message); retry in $retrySeconds s" 'WARN'
        }
    }

    try { if ($serial.IsOpen) { $serial.Close() } } catch { }
    try { $serial.Dispose() } catch { }
    return $false
}

function Get-PortsInPreferredOrder {
    param(
        [string[]]$CandidatePorts = @(),
        [switch]$IgnoreCooldowns
    )

    $availablePorts = @(Get-PortNames)
    $ports = if (@($CandidatePorts).Count -gt 0) {
        @($CandidatePorts | Where-Object { $availablePorts -contains $_ } | Select-Object -Unique)
    }
    else {
        @($availablePorts)
    }

    $ordered = New-Object System.Collections.Generic.List[string]
    $preferred = [string]$script:Config.connection.lastWorkingPort
    if (-not [string]::IsNullOrWhiteSpace($preferred) -and $ports -contains $preferred) {
        $ordered.Add($preferred)
    }
    foreach ($port in $ports) {
        if (-not $ordered.Contains($port)) { $ordered.Add($port) }
    }

    if ($IgnoreCooldowns) { return @($ordered) }
    return @($ordered | Where-Object { Test-PortProbeAllowed -PortName $_ })
}

function Connect-Controller {
    param(
        [switch]$Quiet,
        [string[]]$CandidatePorts = @(),
        [switch]$ForceFullScan
    )

    # Open-And-ProbePort pumps WinForms messages while waiting for an Arduino to
    # reboot. Without this guard, the UI timer (or a second button click) can start
    # another scan inside the first one. One scan may connect successfully while
    # the other finishes later and overwrites the green status with "not found".
    if ($script:IsConnecting) {
        Write-Log 'Connection scan request ignored because another scan is already running' 'DEBUG'
        return $script:IsConnected
    }

    $script:IsConnecting = $true
    try {
        if ($null -ne $connectButton) { $connectButton.Enabled = $false }
        Close-ControllerPort
        $script:LastScanBusyPorts = @()
        $mode = [string]$script:Config.connection.mode
        $isExplicitScan = $ForceFullScan -or (-not $Quiet -and @($CandidatePorts).Count -eq 0)
        if ($isExplicitScan) {
            Clear-AllPortProbeCooldowns
            $script:PendingNewPorts = @()
        }

        $ports = @()
        if ($mode -eq 'manual') {
            $manualPort = [string]$script:Config.connection.port
            if (-not [string]::IsNullOrWhiteSpace($manualPort)) {
                if (@($CandidatePorts).Count -eq 0 -or $CandidatePorts -contains $manualPort) {
                    if ($isExplicitScan -or (Test-PortProbeAllowed -PortName $manualPort)) {
                        $ports = @($manualPort)
                    }
                }
            }
        }
        else {
            $ignoreCooldowns = $isExplicitScan -or @($CandidatePorts).Count -gt 0
            $ports = @(Get-PortsInPreferredOrder -CandidatePorts $CandidatePorts -IgnoreCooldowns:$ignoreCooldowns)
        }

        if ($ports.Count -eq 0) {
            if (-not $Quiet) { Set-Status (T -Key 'StatusNoPorts') 'warn' }
            return $false
        }

        if (-not $Quiet) { Set-Status (T -Key 'StatusSearching') 'busy' }
        foreach ($port in $ports) {
            if (-not $Quiet) { Set-Status (T -Key 'StatusCheckingPort' -Args @($port)) 'busy' }
            if (Open-And-ProbePort -PortName $port) {
                Set-Status (T -Key 'StatusConnected' -Args @($port, [int]$script:Config.connection.expectedSliders)) 'ok'
                Update-TrayText
                Update-DriverStatus
                return $true
            }
        }

        # Defensive check: never replace a real open connection with a stale
        # "not found" result, even if some future code changes the scan flow.
        if ($script:IsConnected -and $null -ne $script:Serial -and $script:Serial.IsOpen) {
            Set-Status (T -Key 'StatusConnected' -Args @($script:ConnectedPort, [int]$script:Config.connection.expectedSliders)) 'ok'
            Update-TrayText
            return $true
        }

        if (-not $Quiet) {
            if ($mode -eq 'manual') {
                Set-Status (T -Key 'StatusManualNotRecognized') 'warn'
            }
            elseif ($script:LastScanBusyPorts.Count -gt 0) {
                Set-Status (T -Key 'StatusPortsBusy' -Args @(($script:LastScanBusyPorts -join ', '))) 'warn'
            }
            else {
                Set-Status (T -Key 'StatusAutoNotFound') 'warn'
            }
        }
        Update-TrayText
        Update-DriverStatus
        return $false
    }
    finally {
        $script:IsConnecting = $false
        $script:LastReconnectAttempt = Get-Date
        if ($null -ne $connectButton) { $connectButton.Enabled = $true }
    }
}

function Apply-SliderValues {
    param([int[]]$Values)

    if ($Values.Count -ne [int]$script:Config.connection.expectedSliders) { return }
    $threshold = [double]$script:Config.behavior.noiseThreshold
    $invert = [bool]$script:Config.behavior.invertSliders

    if ($script:LastValues.Count -ne $Values.Count) {
        $script:LastValues = @(for ($i = 0; $i -lt $Values.Count; $i++) { -1.0 })
    }
    $liveLevels = @()
    for ($i = 0; $i -lt $Values.Count; $i++) {
        $liveLevel = [double]$Values[$i] / 1023.0
        if ($invert) { $liveLevel = 1.0 - $liveLevel }
        $liveLevels += $liveLevel
    }
    $script:LatestLevels = @($liveLevels)

    for ($i = 0; $i -lt $Values.Count; $i++) {
        $level = [double]$script:LatestLevels[$i]
        if ([Math]::Abs($level - [double]$script:LastValues[$i]) -lt $threshold) { continue }
        $script:LastValues[$i] = $level

        if ($i -ge $script:Config.sliders.Count) { continue }
        $slider = $script:Config.sliders[$i]
        $processTargets = New-Object System.Collections.Generic.List[string]

        foreach ($targetObject in @($slider.targets)) {
            $target = ([string]$targetObject).Trim()
            if ([string]::IsNullOrWhiteSpace($target)) { continue }
            $audioTargetKey = $target
            try {
                if ($target -ieq 'master') {
                    [MugenDeejAudio.AudioMixer]::SetMaster([single]$level)
                }
                elseif ($target -ieq 'mic') {
                    $inputDeviceId = [string]$slider.inputDeviceId
                    $audioTargetKey = "mic:$inputDeviceId"
                    [MugenDeejAudio.AudioMixer]::SetInputDeviceVolume($inputDeviceId, [single]$level)
                }
                else {
                    $processTargets.Add($target)
                }
            }
            catch {
                Write-AudioWarningThrottled -Key "slider-$($i + 1)-$audioTargetKey" -Message "Audio target '$audioTargetKey' failed: $($_.Exception.Message)"
            }
        }

        if ($processTargets.Count -gt 0) {
            try {
                [void][MugenDeejAudio.AudioMixer]::SetProcessVolumes($processTargets.ToArray(), [single]$level)
            }
            catch {
                Write-AudioWarningThrottled -Key "slider-$($i + 1)-applications" -Message "Audio targets for slider $($i + 1) failed: $($_.Exception.Message)"
                [MugenDeejAudio.AudioMixer]::InvalidateSessions()
            }
        }
    }
}

function Handle-ControllerConnectionLost {
    param([string]$Reason)

    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        Write-Log "Serial connection lost: $Reason" 'WARN'
    }
    Close-ControllerPort
    [MugenDeejAudio.AudioMixer]::InvalidateSessions()
    $script:LastReconnectAttempt = Get-Date
    Set-Status (T -Key 'StatusLost') 'warn'
    Update-TrayText
    Update-DriverStatus
}

function Process-SerialData {
    if (-not $script:IsConnected -or $null -eq $script:Serial) { return }
    if (-not $script:Serial.IsOpen) {
        Handle-ControllerConnectionLost -Reason 'Serial port is no longer open'
        return
    }

    try {
        $chunk = $script:Serial.ReadExisting()
        if ($chunk.Length -gt 0) {
            $script:SerialBuffer += $chunk
        }

        # Arduino sends packets much faster than Windows audio sessions need updates.
        # Keep only the newest complete packet so slow browser session enumeration
        # cannot build a several-second queue of obsolete knob positions.
        $latestParsed = $null
        while ($script:SerialBuffer.Contains("`n")) {
            $idx = $script:SerialBuffer.IndexOf("`n")
            $line = $script:SerialBuffer.Substring(0, $idx).Trim("`r", "`n", " ", "`t")
            $script:SerialBuffer = $script:SerialBuffer.Substring($idx + 1)
            $parsed = Test-ProtocolLine -Line $line -ExpectedCount ([int]$script:Config.connection.expectedSliders)
            if ($null -ne $parsed) { $latestParsed = $parsed }
        }

        if ($null -ne $latestParsed) {
            $script:LastSerialPacketAt = Get-Date
            Apply-SliderValues -Values $latestParsed
            return
        }

        # System.IO.Ports.SerialPort may remain formally open after a USB device is
        # unplugged. Treat prolonged absence of valid packets as a real disconnect,
        # then let the normal reconnect loop discover the controller again.
        $timeoutMs = [Math]::Max(1000, [int]$script:Config.connection.dataTimeoutMs)
        if ($script:LastSerialPacketAt -ne [DateTime]::MinValue -and
            ((Get-Date) - $script:LastSerialPacketAt).TotalMilliseconds -ge $timeoutMs) {
            throw "No valid controller packets received for $timeoutMs ms"
        }
    }
    catch {
        Handle-ControllerConnectionLost -Reason $_.Exception.Message
    }
}

function Get-PnpDeviceForPort {
    param([string]$PortName)

    if ([string]::IsNullOrWhiteSpace($PortName)) { return $null }
    $portPattern = '\(' + [regex]::Escape($PortName) + '\)\s*$'

    $devices = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.Name) -and
        ([string]$_.Name -match $portPattern)
    })
    if ($devices.Count -gt 0) { return $devices[0] }

    # Fallback for drivers whose friendly name does not contain the COM number.
    $serialDevices = @(Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Where-Object {
        [string]$_.DeviceID -ieq $PortName
    })
    if ($serialDevices.Count -gt 0) {
        $pnpId = [string]$serialDevices[0].PNPDeviceID
        if (-not [string]::IsNullOrWhiteSpace($pnpId)) {
            $matches = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
                [string]$_.PNPDeviceID -ieq $pnpId
            })
            if ($matches.Count -gt 0) { return $matches[0] }
        }
    }

    return $null
}

function Test-IsWchDevice {
    param($Device)
    if ($null -eq $Device) { return $false }
    $pnpId = [string]$Device.PNPDeviceID
    $name = [string]$Device.Name
    return (($pnpId -match 'VID_1A86') -or ($name -match 'CH340|CH341|CH343|CH910'))
}

function Get-ComNameFromDevice {
    param($Device)
    if ($null -eq $Device) { return '' }
    $match = [regex]::Match([string]$Device.Name, '\((COM\d+)\)\s*$')
    if ($match.Success) { return [string]$match.Groups[1].Value }
    return ''
}

function Test-ComPortConflict {
    param(
        [Parameter(Mandatory = $true)][string]$PortName,
        [object[]]$Devices = @()
    )

    $portPattern = '\(' + [regex]::Escape($PortName) + '\)\s*$'
    $allDevices = if (@($Devices).Count -gt 0) {
        @($Devices)
    }
    else {
        @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue)
    }

    $matches = @($allDevices | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.Name) -and
        ([string]$_.Name -match $portPattern)
    })
    return ($matches.Count -gt 1)
}

function Get-DriverStatus {
    try {
        # When a controller is connected, report the driver bound to that exact
        # COM port. This avoids showing an unrelated CH340 when several serial
        # devices are present.
        if ($script:IsConnected -and -not [string]::IsNullOrWhiteSpace($script:ConnectedPort)) {
            $activeDevice = Get-PnpDeviceForPort -PortName $script:ConnectedPort
            if ($null -ne $activeDevice) {
                $isWch = Test-IsWchDevice -Device $activeDevice
                $errorCode = [int]$activeDevice.ConfigManagerErrorCode
                if ($errorCode -eq 0) {
                    return [pscustomobject]@{
                        State = 'ok'
                        Text = (T -Key 'DriverActiveWorking' -Args @([string]$activeDevice.Name))
                        DevicePresent = $true
                        IsWch = $isWch
                    }
                }
                return [pscustomobject]@{
                    State = 'error'
                    Text = (T -Key 'DriverActiveProblem' -Args @([string]$activeDevice.Name, $errorCode))
                    DevicePresent = $true
                    IsWch = $isWch
                }
            }

            return [pscustomobject]@{
                State = 'unknown'
                Text = (T -Key 'DriverActiveUnknown' -Args @($script:ConnectedPort))
                DevicePresent = $true
                IsWch = $false
            }
        }

        # When no controller is active, do not assign an unrelated healthy
        # CH340/CH341 device to it. Only surface a WCH device here when Windows
        # reports an actual driver problem. Otherwise wait until a controller is
        # connected, then diagnose the exact COM port that passed protocol checks.
        $allPnpDevices = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)
        $wchDevices = @($allPnpDevices | Where-Object {
            ($_.PNPDeviceID -match 'VID_1A86') -or
            ($_.Name -match 'CH340|CH341|CH343|CH910')
        })

        $problemDevices = @($wchDevices | Where-Object {
            ([int]$_.ConfigManagerErrorCode -ne 0) -or
            ([string]$_.Name -notmatch '\(COM\d+\)')
        })
        if ($problemDevices.Count -gt 0) {
            $problem = $problemDevices[0]
            $errorCode = [int]$problem.ConfigManagerErrorCode
            $problemPort = Get-ComNameFromDevice -Device $problem

            if ($errorCode -eq 31) {
                if (-not [string]::IsNullOrWhiteSpace($problemPort) -and
                    (Test-ComPortConflict -PortName $problemPort -Devices $allPnpDevices)) {
                    return [pscustomobject]@{
                        State = 'warn'
                        Text = (T -Key 'DriverPortConflict' -Args @($problemPort))
                        DevicePresent = $true
                        IsWch = $false
                    }
                }

                return [pscustomobject]@{
                    State = 'warn'
                    Text = (T -Key 'DriverCode31')
                    DevicePresent = $true
                    IsWch = $false
                }
            }

            return [pscustomobject]@{
                State = 'error'
                Text = (T -Key 'DriverProblem' -Args @($errorCode))
                DevicePresent = $true
                IsWch = $true
            }
        }

        return [pscustomobject]@{
            State = 'idle'
            Text = (T -Key 'DriverAwaitingController')
            DevicePresent = $false
            IsWch = $false
        }
    }
    catch {
        Write-Log "Driver check failed: $($_.Exception.Message)" 'WARN'
        return [pscustomobject]@{ State = 'unknown'; Text = (T -Key 'DriverUnknown'); DevicePresent = $false; IsWch = $true }
    }
}

function Test-WchInstallerSignature {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -lt 2 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { return $false }
        $signature = Get-AuthenticodeSignature -FilePath $Path
        if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) { return $false }
        $subject = [string]$signature.SignerCertificate.Subject
        return ($subject -match 'Qinheng|WCH|Nanjing')
    }
    catch { return $false }
}

function Install-Ch340Driver {
    $answer = [System.Windows.Forms.MessageBox]::Show(
        (T -Key 'DriverConfirmText'),
        (T -Key 'DriverInstallTitle'),
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        Set-DriverStatus (T -Key 'DriverDownloading') 'busy'
        [System.Windows.Forms.Application]::DoEvents()
        Invoke-WebRequest -Uri $script:OfficialDriverDownload -UseBasicParsing -OutFile $script:DriverInstallerPath

        if (-not (Test-WchInstallerSignature -Path $script:DriverInstallerPath)) {
            Remove-Item -LiteralPath $script:DriverInstallerPath -Force -ErrorAction SilentlyContinue
            throw (T -Key 'DriverSignatureInvalid')
        }

        Set-DriverStatus (T -Key 'DriverLaunching') 'busy'
        [System.Windows.Forms.Application]::DoEvents()
        Start-Process -FilePath $script:DriverInstallerPath -Verb RunAs -Wait
        Update-DriverStatus
        Refresh-PortList
    }
    catch {
        Write-Log "Driver installation failed: $($_.Exception.Message)" 'ERROR'
        [System.Windows.Forms.MessageBox]::Show(
            (T -Key 'DriverFailedText' -Args @($_.Exception.Message)),
            'Mugen Deej',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        Start-Process $script:OfficialDriverPage
        Update-DriverStatus
    }
}

function Show-InitialLanguagePicker {
    $languageForm = New-Object System.Windows.Forms.Form
    $languageForm.Text = 'Mugen Deej — Язык / Language'
    $languageForm.StartPosition = 'CenterScreen'
    $languageForm.ClientSize = New-Object System.Drawing.Size(560, 270)
    $languageForm.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $languageForm.BackColor = [System.Drawing.Color]::FromArgb(247, 247, 249)
    $languageForm.FormBorderStyle = 'FixedDialog'
    $languageForm.MaximizeBox = $false
    $languageForm.MinimizeBox = $false
    $languageForm.ControlBox = $false
    $languageForm.ShowInTaskbar = $true
    $languageForm.TopMost = $true
    Set-FormAppIcon -Form $languageForm

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = 'Выберите язык / Choose your language'
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17)
    $heading.AutoSize = $true
    $heading.Location = New-Object System.Drawing.Point(28, 24)
    $languageForm.Controls.Add($heading)

    $description = New-Object System.Windows.Forms.Label
    $description.Text = ('Продолжите на удобном языке.' + "`r`n" + 'Continue in the language you prefer.')
    $description.ForeColor = [System.Drawing.Color]::DimGray
    $description.Location = New-Object System.Drawing.Point(31, 68)
    $description.Size = New-Object System.Drawing.Size(495, 48)
    $languageForm.Controls.Add($description)

    $russianButton = New-Object System.Windows.Forms.Button
    $russianButton.Text = 'Русский'
    $russianButton.Location = New-Object System.Drawing.Point(32, 128)
    $russianButton.Size = New-Object System.Drawing.Size(238, 54)
    $russianButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $languageForm.Controls.Add($russianButton)

    $englishButton = New-Object System.Windows.Forms.Button
    $englishButton.Text = 'English'
    $englishButton.Location = New-Object System.Drawing.Point(290, 128)
    $englishButton.Size = New-Object System.Drawing.Size(238, 54)
    $englishButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $languageForm.Controls.Add($englishButton)

    $laterHint = New-Object System.Windows.Forms.Label
    $laterHint.Text = ('Язык можно изменить позже в правом верхнем углу программы.' + "`r`n" + 'You can change the language later in the upper-right corner of the app.')
    $laterHint.ForeColor = [System.Drawing.Color]::DimGray
    $laterHint.Location = New-Object System.Drawing.Point(31, 202)
    $laterHint.Size = New-Object System.Drawing.Size(495, 48)
    $languageForm.Controls.Add($laterHint)

    $languageForm.Tag = 'pending'
    $chooseLanguage = {
        param([string]$LanguageCode)
        $script:Language = $LanguageCode
        $script:Config.app.language = $LanguageCode
        Set-DefaultControlNamesForLanguage
        Save-Config -Config $script:Config
        Write-Log "Initial interface language selected: $LanguageCode"
        $languageForm.Tag = 'selected'
        $languageForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $languageForm.Close()
    }

    $russianButton.Add_Click({ & $chooseLanguage 'ru' })
    $englishButton.Add_Click({ & $chooseLanguage 'en' })
    $languageForm.Add_FormClosing({
        param($sender, $eventArgs)
        if ([string]$languageForm.Tag -ne 'selected') { $eventArgs.Cancel = $true }
    })
    $languageForm.Add_Shown({
        [void][MugenDeejWindowing.Foreground]::ShowWindowAsync($languageForm.Handle, 9)
        [void][MugenDeejWindowing.Foreground]::BringWindowToTop($languageForm.Handle)
        [void][MugenDeejWindowing.Foreground]::SetForegroundWindow($languageForm.Handle)
        $languageForm.Activate()
    })

    [void]$languageForm.ShowDialog()
    $languageForm.Dispose()
    $script:NeedsInitialLanguageSelection = $false
}

if ($script:NeedsInitialLanguageSelection) {
    Show-InitialLanguagePicker
}

# ---------- UI ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Mugen Deej $script:AppVersion"
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(680, 490)
$form.MinimumSize = New-Object System.Drawing.Size(696, 529)
$form.MaximumSize = New-Object System.Drawing.Size(696, 797)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(247, 247, 249)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
Set-FormAppIcon -Form $form

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Mugen Deej'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(24, 18)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = (T -Key 'Subtitle')
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(27, 57)
$form.Controls.Add($subtitle)

$languageLabel = New-Object System.Windows.Forms.Label
$languageLabel.Text = (T -Key 'LanguageLabel')
$languageLabel.Location = New-Object System.Drawing.Point(470, 24)
$languageLabel.Size = New-Object System.Drawing.Size(75, 25)
$languageLabel.TextAlign = 'MiddleRight'
$form.Controls.Add($languageLabel)

$languageCombo = New-Object System.Windows.Forms.ComboBox
$languageCombo.DropDownStyle = 'DropDownList'
$languageCombo.Location = New-Object System.Drawing.Point(550, 21)
$languageCombo.Size = New-Object System.Drawing.Size(105, 29)
[void]$languageCombo.Items.Add('Русский')
[void]$languageCombo.Items.Add('English')
$languageCombo.SelectedIndex = if ($script:Language -eq 'ru') { 0 } else { 1 }
$form.Controls.Add($languageCombo)

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Location = New-Object System.Drawing.Point(24, 88)
$statusPanel.Size = New-Object System.Drawing.Size(632, 60)
$statusPanel.BackColor = [System.Drawing.Color]::White
$statusPanel.BorderStyle = 'FixedSingle'
$form.Controls.Add($statusPanel)

$statusDot = New-Object System.Windows.Forms.Label
$statusDot.Text = '●'
$statusDot.Font = New-Object System.Drawing.Font('Segoe UI', 16)
$statusDot.AutoSize = $true
$statusDot.Location = New-Object System.Drawing.Point(14, 12)
$statusPanel.Controls.Add($statusDot)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = (T -Key 'Starting')
$statusLabel.AutoSize = $false
$statusLabel.Size = New-Object System.Drawing.Size(560, 38)
$statusLabel.Location = New-Object System.Drawing.Point(46, 10)
$statusLabel.TextAlign = 'MiddleLeft'
$statusPanel.Controls.Add($statusLabel)

$knobGroup = New-Object System.Windows.Forms.GroupBox
$knobGroup.Text = (T -Key 'KnobStatus')
$knobGroup.Location = New-Object System.Drawing.Point(24, 160)
$knobGroup.Size = New-Object System.Drawing.Size(632, 184)
$form.Controls.Add($knobGroup)

for ($i = 0; $i -lt 5; $i++) {
    $y = 26 + ($i * 29)
    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.Text = (T -Key 'KnobN' -Args @($i + 1))
    $nameLabel.Location = New-Object System.Drawing.Point(16, $y)
    $nameLabel.Size = New-Object System.Drawing.Size(170, 23)
    $nameLabel.AutoEllipsis = $true
    $knobGroup.Controls.Add($nameLabel)
    $script:KnobNameLabels += $nameLabel

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = New-Object System.Drawing.Point(190, $y)
    $bar.Size = New-Object System.Drawing.Size(350, 21)
    $bar.Minimum = 0
    $bar.Maximum = 1000
    $knobGroup.Controls.Add($bar)
    $script:KnobProgressBars += $bar

    $percent = New-Object System.Windows.Forms.Label
    $percent.Text = '—'
    $percent.Location = New-Object System.Drawing.Point(548, $y)
    $percent.Size = New-Object System.Drawing.Size(58, 23)
    $percent.TextAlign = 'MiddleRight'
    $knobGroup.Controls.Add($percent)
    $script:KnobPercentLabels += $percent
}

$settingsButton = New-Object System.Windows.Forms.Button
$settingsButton.Text = (T -Key 'ConfigureKnobs')
$settingsButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$settingsButton.Location = New-Object System.Drawing.Point(24, 360)
$settingsButton.Size = New-Object System.Drawing.Size(230, 42)
$form.Controls.Add($settingsButton)

$settingsHint = New-Object System.Windows.Forms.Label
$settingsHint.Text = (T -Key 'ConfigureHint')
$settingsHint.ForeColor = [System.Drawing.Color]::DimGray
$settingsHint.Location = New-Object System.Drawing.Point(272, 358)
$settingsHint.Size = New-Object System.Drawing.Size(380, 48)
$settingsHint.TextAlign = 'MiddleLeft'
$form.Controls.Add($settingsHint)

$advancedToggle = New-Object System.Windows.Forms.Button
$advancedToggle.Text = (T -Key 'DiagnosticsClosed')
$advancedToggle.Location = New-Object System.Drawing.Point(24, 416)
$advancedToggle.Size = New-Object System.Drawing.Size(250, 32)
$form.Controls.Add($advancedToggle)

$advancedPanel = New-Object System.Windows.Forms.Panel
$advancedPanel.Location = New-Object System.Drawing.Point(0, 450)
$advancedPanel.Size = New-Object System.Drawing.Size(680, 270)
$advancedPanel.Visible = $false
$form.Controls.Add($advancedPanel)

$connectionGroup = New-Object System.Windows.Forms.GroupBox
$connectionGroup.Text = (T -Key 'ConnectionGroup')
$connectionGroup.Location = New-Object System.Drawing.Point(24, 0)
$connectionGroup.Size = New-Object System.Drawing.Size(632, 150)
$advancedPanel.Controls.Add($connectionGroup)

$autoRadio = New-Object System.Windows.Forms.RadioButton
$autoRadio.Text = (T -Key 'AutoPort')
$autoRadio.AutoSize = $true
$autoRadio.Location = New-Object System.Drawing.Point(18, 29)
$connectionGroup.Controls.Add($autoRadio)

$manualRadio = New-Object System.Windows.Forms.RadioButton
$manualRadio.Text = (T -Key 'ManualPort')
$manualRadio.AutoSize = $true
$manualRadio.Location = New-Object System.Drawing.Point(18, 61)
$connectionGroup.Controls.Add($manualRadio)

$portCombo = New-Object System.Windows.Forms.ComboBox
$portCombo.DropDownStyle = 'DropDownList'
$portCombo.Location = New-Object System.Drawing.Point(220, 58)
$portCombo.Size = New-Object System.Drawing.Size(125, 29)
$connectionGroup.Controls.Add($portCombo)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = (T -Key 'RefreshList')
$refreshButton.Location = New-Object System.Drawing.Point(356, 56)
$refreshButton.Size = New-Object System.Drawing.Size(145, 32)
$connectionGroup.Controls.Add($refreshButton)

$connectButton = New-Object System.Windows.Forms.Button
$connectButton.Text = (T -Key 'Reconnect')
$connectButton.Location = New-Object System.Drawing.Point(18, 99)
$connectButton.Size = New-Object System.Drawing.Size(230, 34)
$connectionGroup.Controls.Add($connectButton)

$connectionHelp = New-Object System.Windows.Forms.Label
$connectionHelp.Text = (T -Key 'ConnectionHelp')
$connectionHelp.ForeColor = [System.Drawing.Color]::DimGray
$connectionHelp.Location = New-Object System.Drawing.Point(265, 91)
$connectionHelp.Size = New-Object System.Drawing.Size(345, 52)
$connectionGroup.Controls.Add($connectionHelp)

$driverGroup = New-Object System.Windows.Forms.GroupBox
$driverGroup.Text = (T -Key 'DriverAndLog')
$driverGroup.Location = New-Object System.Drawing.Point(24, 158)
$driverGroup.Size = New-Object System.Drawing.Size(632, 104)
$advancedPanel.Controls.Add($driverGroup)

$driverDot = New-Object System.Windows.Forms.Label
$driverDot.Text = '●'
$driverDot.Font = New-Object System.Drawing.Font('Segoe UI', 14)
$driverDot.AutoSize = $true
$driverDot.Location = New-Object System.Drawing.Point(16, 27)
$driverGroup.Controls.Add($driverDot)

$driverLabel = New-Object System.Windows.Forms.Label
$driverLabel.Text = (T -Key 'Checking')
$driverLabel.AutoSize = $false
$driverLabel.Location = New-Object System.Drawing.Point(46, 23)
$driverLabel.Size = New-Object System.Drawing.Size(560, 28)
$driverLabel.TextAlign = 'MiddleLeft'
$driverGroup.Controls.Add($driverLabel)

$driverButton = New-Object System.Windows.Forms.Button
$driverButton.Text = (T -Key 'InstallDriver')
$driverButton.Location = New-Object System.Drawing.Point(18, 61)
$driverButton.Size = New-Object System.Drawing.Size(310, 32)
$driverGroup.Controls.Add($driverButton)

$logButton = New-Object System.Windows.Forms.Button
$logButton.Text = (T -Key 'OpenLog')
$logButton.Location = New-Object System.Drawing.Point(342, 61)
$logButton.Size = New-Object System.Drawing.Size(170, 32)
$driverGroup.Controls.Add($logButton)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = 'Made by Mugen Art Lab'
$footer.ForeColor = [System.Drawing.Color]::Gray
$footer.AutoSize = $true
$footer.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Bottom
$footer.Location = New-Object System.Drawing.Point(24, 462)
$form.Controls.Add($footer)

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = if ($script:AppIcon) { $script:AppIcon } else { [System.Drawing.SystemIcons]::Application }
$notifyIcon.Visible = $true
$notifyIcon.Text = 'Mugen Deej'

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayOpen = $trayMenu.Items.Add((T -Key 'TrayOpen'))
$traySettings = $trayMenu.Items.Add((T -Key 'TraySettings'))
$trayReconnect = $trayMenu.Items.Add((T -Key 'TrayReconnect'))
[void]$trayMenu.Items.Add('-')
$trayExit = $trayMenu.Items.Add((T -Key 'TrayExit'))
$notifyIcon.ContextMenuStrip = $trayMenu

function Set-Status {
    param([string]$Text, [ValidateSet('ok','warn','error','busy','idle')][string]$State = 'idle')
    $statusLabel.Text = $Text
    switch ($State) {
        'ok'    { $statusDot.ForeColor = [System.Drawing.Color]::SeaGreen }
        'warn'  { $statusDot.ForeColor = [System.Drawing.Color]::DarkOrange }
        'error' { $statusDot.ForeColor = [System.Drawing.Color]::Firebrick }
        'busy'  { $statusDot.ForeColor = [System.Drawing.Color]::RoyalBlue }
        default { $statusDot.ForeColor = [System.Drawing.Color]::Gray }
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-DriverStatus {
    param([string]$Text, [ValidateSet('ok','warn','error','busy','idle')][string]$State = 'idle')
    $driverLabel.Text = $Text
    switch ($State) {
        'ok'    { $driverDot.ForeColor = [System.Drawing.Color]::SeaGreen }
        'warn'  { $driverDot.ForeColor = [System.Drawing.Color]::DarkOrange }
        'error' { $driverDot.ForeColor = [System.Drawing.Color]::Firebrick }
        'busy'  { $driverDot.ForeColor = [System.Drawing.Color]::RoyalBlue }
        default { $driverDot.ForeColor = [System.Drawing.Color]::Gray }
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-DriverStatus {
    $status = Get-DriverStatus

    # The bundled installer is only relevant to WCH controllers. For FTDI or
    # other USB-serial devices, keep the exact driver status but hide the WCH
    # maintenance button and give the log button the available space.
    $driverButton.Visible = [bool]$status.IsWch
    if ($driverButton.Visible) {
        $driverButton.Location = New-Object System.Drawing.Point(18, 61)
        $driverButton.Size = New-Object System.Drawing.Size(310, 32)
        $logButton.Location = New-Object System.Drawing.Point(342, 61)
        $logButton.Size = New-Object System.Drawing.Size(170, 32)
    }
    else {
        $logButton.Location = New-Object System.Drawing.Point(18, 61)
        $logButton.Size = New-Object System.Drawing.Size(494, 32)
    }

    switch ($status.State) {
        'ok' {
            Set-DriverStatus $status.Text 'ok'
            $driverButton.Text = (T -Key 'ReinstallDriver')
        }
        'error' {
            Set-DriverStatus $status.Text 'error'
            $driverButton.Text = (T -Key 'RepairDriver')
        }
        'warn' {
            Set-DriverStatus $status.Text 'warn'
            $driverButton.Text = (T -Key 'InstallOrReinstall')
        }
        'missing' {
            Set-DriverStatus $status.Text 'warn'
            $driverButton.Text = (T -Key 'InstallDriver')
        }
        default {
            Set-DriverStatus $status.Text 'idle'
            $driverButton.Text = (T -Key 'InstallOrReinstall')
        }
    }
}

function Apply-MainLocalization {
    $languageLabel.Text = (T -Key 'LanguageLabel')
    $subtitle.Text = (T -Key 'Subtitle')
    $knobGroup.Text = (T -Key 'KnobStatus')
    $settingsButton.Text = (T -Key 'ConfigureKnobs')
    $settingsHint.Text = (T -Key 'ConfigureHint')
    $connectionGroup.Text = (T -Key 'ConnectionGroup')
    $autoRadio.Text = (T -Key 'AutoPort')
    $manualRadio.Text = (T -Key 'ManualPort')
    $refreshButton.Text = (T -Key 'RefreshList')
    $connectButton.Text = (T -Key 'Reconnect')
    $connectionHelp.Text = (T -Key 'ConnectionHelp')
    $driverGroup.Text = (T -Key 'DriverAndLog')
    $logButton.Text = (T -Key 'OpenLog')
    $trayOpen.Text = (T -Key 'TrayOpen')
    $traySettings.Text = (T -Key 'TraySettings')
    $trayReconnect.Text = (T -Key 'TrayReconnect')
    $trayExit.Text = (T -Key 'TrayExit')
    Set-AdvancedExpanded -Expanded $advancedPanel.Visible -Persist $false
    Refresh-KnobLabels
    Update-TrayText
}

function Refresh-PortList {
    $selected = [string]$portCombo.SelectedItem
    $portCombo.Items.Clear()
    foreach ($port in @(Get-PortNames)) { [void]$portCombo.Items.Add($port) }
    $wanted = [string]$script:Config.connection.port
    if (-not [string]::IsNullOrWhiteSpace($selected)) { $wanted = $selected }
    if (-not [string]::IsNullOrWhiteSpace($wanted) -and $portCombo.Items.Contains($wanted)) {
        $portCombo.SelectedItem = $wanted
    }
    elseif ($portCombo.Items.Count -gt 0) {
        $portCombo.SelectedIndex = 0
    }
}

function Update-ConnectionControls {
    $manual = $manualRadio.Checked
    $portCombo.Enabled = $manual
    $refreshButton.Enabled = $manual
}

function Show-MainWindowForeground {
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }

    $form.Show()
    [void][MugenDeejWindowing.Foreground]::ShowWindowAsync($form.Handle, 9)

    # A process launched from Explorer can otherwise create its WinForms window
    # behind the folder that started it. Briefly placing the form at the top,
    # activating it, then restoring the normal z-order makes startup predictable
    # without leaving Mugen Deej permanently always-on-top.
    $form.TopMost = $true
    $form.BringToFront()
    [void][MugenDeejWindowing.Foreground]::BringWindowToTop($form.Handle)
    [void][MugenDeejWindowing.Foreground]::SetForegroundWindow($form.Handle)
    $form.Activate()
    [System.Windows.Forms.Application]::DoEvents()
    $form.TopMost = $false
}

function Update-TrayText {
    $text = if ($script:IsConnected) { "Mugen Deej — $script:ConnectedPort" } else { (T -Key 'TrayDisconnected') }
    if ($text.Length -gt 63) { $text = $text.Substring(0, 63) }
    $notifyIcon.Text = $text
}

function Refresh-KnobLabels {
    for ($i = 0; $i -lt $script:KnobNameLabels.Count; $i++) {
        $name = if ($i -lt $script:Config.sliders.Count) { [string]$script:Config.sliders[$i].name } else { (T -Key 'KnobN' -Args @($i + 1)) }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = (T -Key 'KnobN' -Args @($i + 1)) }
        $script:KnobNameLabels[$i].Text = "$($i + 1). $name"
    }
}

function Update-KnobMonitor {
    for ($i = 0; $i -lt $script:KnobProgressBars.Count; $i++) {
        if ($script:LatestLevels.Count -gt $i) {
            $level = [Math]::Max(0.0, [Math]::Min(1.0, [double]$script:LatestLevels[$i]))
            $script:KnobProgressBars[$i].Value = [int][Math]::Round($level * 1000)
            $script:KnobPercentLabels[$i].Text = ('{0}%' -f [int][Math]::Round($level * 100))
        }
        else {
            $script:KnobProgressBars[$i].Value = 0
            $script:KnobPercentLabels[$i].Text = '—'
        }
    }
}

function Set-AdvancedExpanded {
    param(
        [bool]$Expanded,
        [bool]$Persist = $true
    )
    $advancedPanel.Visible = $Expanded
    $advancedToggle.Text = if ($Expanded) { (T -Key 'DiagnosticsOpen') } else { (T -Key 'DiagnosticsClosed') }
    $form.ClientSize = if ($Expanded) { New-Object System.Drawing.Size(680, 758) } else { New-Object System.Drawing.Size(680, 490) }
    # Keep the signature attached to the visible bottom edge in both layouts.
    $footer.Location = New-Object System.Drawing.Point(24, ($form.ClientSize.Height - 28))
    if ($Persist) {
        $script:Config.app.advancedExpanded = $Expanded
        Save-Config -Config $script:Config
    }
}

if ([string]$script:Config.connection.mode -eq 'manual') { $manualRadio.Checked = $true } else { $autoRadio.Checked = $true }
Refresh-PortList
Update-ConnectionControls
Apply-MainLocalization
Set-AdvancedExpanded -Expanded ([bool]$script:Config.app.advancedExpanded) -Persist $false

$languageCombo.Add_SelectedIndexChanged({
    $newLanguage = if ($languageCombo.SelectedIndex -eq 0) { 'ru' } else { 'en' }
    if ($newLanguage -eq $script:Language) { return }
    $script:Language = $newLanguage
    $script:Config.app.language = $newLanguage
    Set-DefaultControlNamesForLanguage
    Save-Config -Config $script:Config
    Apply-MainLocalization
    Update-DriverStatus
    if ($script:IsConnected) {
        Set-Status (T -Key 'StatusConnected' -Args @($script:ConnectedPort, [int]$script:Config.connection.expectedSliders)) 'ok'
    }
    else {
        Set-Status (T -Key 'StatusNotConnected') 'idle'
    }
    Write-Log "Interface language changed to $newLanguage"
})

$autoRadio.Add_CheckedChanged({
    if ($autoRadio.Checked) {
        $script:Config.connection.mode = 'auto'
        Save-Config -Config $script:Config
        Update-ConnectionControls
    }
})

$manualRadio.Add_CheckedChanged({
    if ($manualRadio.Checked) {
        $script:Config.connection.mode = 'manual'
        Save-Config -Config $script:Config
        Update-ConnectionControls
    }
})

$portCombo.Add_SelectedIndexChanged({
    if ($null -ne $portCombo.SelectedItem) {
        $script:Config.connection.port = [string]$portCombo.SelectedItem
        Save-Config -Config $script:Config
    }
})

$advancedToggle.Add_Click({ Set-AdvancedExpanded -Expanded (-not $advancedPanel.Visible) })
$refreshButton.Add_Click({ Refresh-PortList; Update-DriverStatus })
$connectButton.Add_Click({ [void](Connect-Controller -ForceFullScan) })
$settingsButton.Add_Click({ Show-SliderSettings })
$driverButton.Add_Click({ Install-Ch340Driver })
$logButton.Add_Click({ Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:LogPath) })

$trayOpen.Add_Click({ Show-MainWindowForeground })
$traySettings.Add_Click({ Show-MainWindowForeground; Show-SliderSettings })
$trayReconnect.Add_Click({ [void](Connect-Controller -ForceFullScan) })
$trayExit.Add_Click({ $script:Closing = $true; $form.Close() })
$notifyIcon.Add_DoubleClick({ Show-MainWindowForeground })

$form.Add_Resize({
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized -and [bool]$script:Config.app.minimizeToTray) {
        $form.Hide()
    }
})

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if (-not $script:Closing -and [bool]$script:Config.app.minimizeToTray) {
        $eventArgs.Cancel = $true
        $form.Hide()
        return
    }
    $timer.Stop()
    try { Save-Config -Config $script:Config }
    catch { Write-Log "Final config save on exit failed: $($_.Exception.Message)" 'ERROR' }
    Close-ControllerPort
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    if ($script:AppIcon) { try { $script:AppIcon.Dispose() } catch { } }
    try { $script:InstanceMutex.ReleaseMutex() } catch { }
    try { $script:InstanceMutex.Dispose() } catch { }
    Write-Log 'Mugen Deej stopped'
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 20
$timer.Add_Tick({
    $now = Get-Date

    # Detect changes in Windows' COM-port list separately from the slower retry
    # loop. A newly appeared port is always treated as fresh, even if the same
    # COM number previously failed protocol detection.
    if (($now - $script:LastPortSnapshotCheck).TotalMilliseconds -ge $script:PortSnapshotIntervalMs) {
        $script:LastPortSnapshotCheck = $now
        $currentPorts = @(Get-PortNames)
        $newPorts = @($currentPorts | Where-Object { $script:KnownPorts -notcontains $_ })
        $removedPorts = @($script:KnownPorts | Where-Object { $currentPorts -notcontains $_ })
        $script:KnownPorts = @($currentPorts)

        if ($removedPorts.Count -gt 0) {
            foreach ($removedPort in $removedPorts) {
                Reset-PortProbeState -PortName $removedPort
                $script:PendingNewPorts = @($script:PendingNewPorts | Where-Object { $_ -ne $removedPort })
            }
            Write-Log ("COM ports removed: {0}" -f ($removedPorts -join ', ')) 'DEBUG'
        }
        if ($newPorts.Count -gt 0) {
            Write-Log ("New COM ports detected: {0}" -f ($newPorts -join ', ')) 'INFO'
            Add-PendingNewPorts -Ports $newPorts
        }
    }

    if (-not $script:IsConnected -and -not $script:IsConnecting -and $script:PendingNewPorts.Count -gt 0) {
        $candidatePorts = @($script:PendingNewPorts)
        $script:PendingNewPorts = @()
        [void](Connect-Controller -Quiet -CandidatePorts $candidatePorts)
    }

    if ($script:IsConnected) {
        Process-SerialData
    }
    elseif (-not $script:IsConnecting) {
        $seconds = [int]$script:Config.connection.reconnectSeconds
        if (((Get-Date) - $script:LastReconnectAttempt).TotalSeconds -ge $seconds) {
            $script:LastReconnectAttempt = Get-Date
            [void](Connect-Controller -Quiet)
        }
    }
    Update-KnobMonitor
})

$form.Add_Shown({
    $startMinimized = [bool]$script:Config.app.startMinimized
    if (-not $startMinimized) {
        Show-MainWindowForeground
    }

    $script:KnownPorts = @(Get-PortNames)
    $script:LastPortSnapshotCheck = Get-Date
    Update-DriverStatus
    [void](Connect-Controller -ForceFullScan)
    $timer.Start()
    if ($startMinimized) {
        $form.WindowState = 'Minimized'
        $form.Hide()
    }
    elseif (-not [bool]$script:Config.app.firstRunCompleted) {
        Show-FirstRunWizard
    }
})

[System.Windows.Forms.Application]::Run($form)
