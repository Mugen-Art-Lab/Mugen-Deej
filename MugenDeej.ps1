# Mugen Deej 1.0.0
# Portable bilingual Windows audio controller for deej-compatible USB serial devices.
# Requires Windows PowerShell 5.1+ and Windows 10/11.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:BaseDir 'config.json'
$script:ConfigPreviousPath = Join-Path $script:BaseDir 'config.previous.json'
$script:ConfigLastGoodPath = Join-Path $script:BaseDir 'config.last-good.json'
$script:ExecutablePath = Join-Path $script:BaseDir 'MugenDeej.exe'
$script:StartupRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:StartupRegistryName = 'Mugen Deej'
# Never recreate an existing Run key with New-Item -Force: Registry provider can remove its other values.
# Only create the key when it does not exist; then add/update our single named value.

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
using Microsoft.Win32;
using System.Windows.Forms;
using System.Drawing;
using System.Drawing.Drawing2D;

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

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        public static string GetForegroundProcessName()
        {
            try
            {
                IntPtr hwnd = GetForegroundWindow();
                if (hwnd == IntPtr.Zero) return String.Empty;

                uint processId;
                GetWindowThreadProcessId(hwnd, out processId);
                if (processId == 0) return String.Empty;

                using (System.Diagnostics.Process process =
                    System.Diagnostics.Process.GetProcessById((int)processId))
                {
                    return process.ProcessName ?? String.Empty;
                }
            }
            catch
            {
                return String.Empty;
            }
        }
    }

    internal static class MugenDrawing
    {
        public static GraphicsPath RoundedRect(Rectangle rect, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            int r = Math.Max(1, Math.Min(radius, Math.Min(rect.Width, rect.Height) / 2));
            int d = r * 2;

            path.AddArc(rect.Left, rect.Top, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Top, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.Left, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    public sealed class MugenCardPanel : Panel
    {
        public Color BorderColor { get; set; }
        public int CornerRadius { get; set; }

        public MugenCardPanel()
        {
            BorderColor = Color.FromArgb(210, 216, 228);
            CornerRadius = 12;
            BorderStyle = BorderStyle.None;

            SetStyle(
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw |
                ControlStyles.UserPaint |
                ControlStyles.SupportsTransparentBackColor,
                true
            );
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;

                const int WS_BORDER = 0x00800000;
                const int WS_EX_CLIENTEDGE = 0x00000200;

                cp.Style &= ~WS_BORDER;
                cp.ExStyle &= ~WS_EX_CLIENTEDGE;

                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            BorderStyle = BorderStyle.None;
            base.OnHandleCreated(e);

            // dev8: paint-only rounded geometry.
            // Do not clip the anti-aliased edge with a second rounded Region.
            Region oldRegion = Region;
            Region = null;

            if (oldRegion != null)
                oldRegion.Dispose();
        }

        protected override void OnSizeChanged(EventArgs e)
        {
            base.OnSizeChanged(e);
            Invalidate();
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

            Color outside = Parent != null ? Parent.BackColor : BackColor;

            using (SolidBrush outsideBrush = new SolidBrush(outside))
                e.Graphics.FillRectangle(outsideBrush, ClientRectangle);

            // Keep the entire anti-aliased outline inside the control bounds.
            Rectangle rect = new Rectangle(
                1,
                1,
                Math.Max(1, Width - 3),
                Math.Max(1, Height - 3)
            );

            using (GraphicsPath path = MugenDrawing.RoundedRect(rect, CornerRadius))
            using (SolidBrush surface = new SolidBrush(BackColor))
                e.Graphics.FillPath(surface, path);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

            Rectangle rect = new Rectangle(
                1,
                1,
                Math.Max(1, Width - 3),
                Math.Max(1, Height - 3)
            );

            using (GraphicsPath path = MugenDrawing.RoundedRect(rect, CornerRadius))
            using (Pen pen = new Pen(BorderColor))
                e.Graphics.DrawPath(pen, path);
        }
    }
    public sealed class MugenGroupBox : Panel
    {
        public Color BorderColor { get; set; }
        public int CornerRadius { get; set; }

        public MugenGroupBox()
        {
            BorderColor = Color.FromArgb(210, 216, 228);
            CornerRadius = 12;
            BorderStyle = BorderStyle.None;

            SetStyle(
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw |
                ControlStyles.UserPaint |
                ControlStyles.SupportsTransparentBackColor,
                true
            );
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;

                const int WS_BORDER = 0x00800000;
                const int WS_EX_CLIENTEDGE = 0x00000200;

                cp.Style &= ~WS_BORDER;
                cp.ExStyle &= ~WS_EX_CLIENTEDGE;

                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            BorderStyle = BorderStyle.None;
            base.OnHandleCreated(e);

            // dev7: no rounded Region. The anti-aliased painted outline must
            // not be clipped by a second hard-edged geometry layer.
            Region oldRegion = Region;
            Region = null;

            if (oldRegion != null)
                oldRegion.Dispose();
        }

        protected override void OnSizeChanged(EventArgs e)
        {
            base.OnSizeChanged(e);
            Invalidate();
        }

        protected override void OnTextChanged(EventArgs e)
        {
            base.OnTextChanged(e);

            // Owner-drawn text must repaint immediately when localization
            // changes Text. Without this, old-language pixels remain until
            // hover, resize or another unrelated invalidation.
            Invalidate();
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

            Color outside = Parent != null ? Parent.BackColor : BackColor;

            using (SolidBrush outsideBrush = new SolidBrush(outside))
                e.Graphics.FillRectangle(outsideBrush, ClientRectangle);

            // One-pixel inset keeps the complete anti-aliased stroke within
            // the drawable surface instead of cutting its outer half-pixels.
            Rectangle rect = new Rectangle(
                1,
                1,
                Math.Max(1, Width - 3),
                Math.Max(1, Height - 3)
            );

            using (GraphicsPath path = MugenDrawing.RoundedRect(rect, CornerRadius))
            using (SolidBrush surface = new SolidBrush(BackColor))
            using (Pen pen = new Pen(BorderColor))
            {
                e.Graphics.FillPath(surface, path);
                e.Graphics.DrawPath(pen, path);
            }

            if (!String.IsNullOrEmpty(Text))
            {
                Rectangle titleRect = new Rectangle(
                    13,
                    5,
                    Math.Max(1, Width - 26),
                    Font.Height + 4
                );

                TextRenderer.DrawText(
                    e.Graphics,
                    Text,
                    Font,
                    titleRect,
                    ForeColor,
                    TextFormatFlags.NoPadding |
                    TextFormatFlags.SingleLine |
                    TextFormatFlags.VerticalCenter |
                    TextFormatFlags.Left |
                    TextFormatFlags.EndEllipsis
                );
            }
        }
    }
    public sealed class MugenButton : Control, IButtonControl
    {
        private bool hovered;
        private bool pressed;
        private bool isDefault;
        private ContentAlignment textAlign;

        public Color BorderColor { get; private set; }
        public Color HoverBackColor { get; private set; }
        public Color PressedBackColor { get; private set; }
        public Color DisabledBackColor { get; private set; }
        public Color DisabledTextColor { get; private set; }
        public Color DisabledBorderColor { get; private set; }
        public Color FocusBorderColor { get; private set; }
        public int CornerRadius { get; private set; }

        // Compatibility properties used by existing PowerShell UI code.
        // They intentionally do not delegate to native Button painting.
        public FlatStyle FlatStyle { get; set; }
        public bool UseVisualStyleBackColor { get; set; }

        public DialogResult DialogResult { get; set; }

        public ContentAlignment TextAlign
        {
            get { return textAlign; }
            set
            {
                textAlign = value;
                Invalidate();
            }
        }

        public MugenButton()
        {
            hovered = false;
            pressed = false;
            isDefault = false;
            textAlign = ContentAlignment.MiddleCenter;

            BackColor = Color.FromArgb(247, 249, 253);
            ForeColor = Color.FromArgb(29, 35, 50);
            BorderColor = Color.FromArgb(180, 188, 202);
            HoverBackColor = Color.FromArgb(232, 238, 250);
            PressedBackColor = Color.FromArgb(220, 230, 248);
            DisabledBackColor = Color.FromArgb(229, 233, 241);
            DisabledTextColor = Color.Gray;
            DisabledBorderColor = Color.FromArgb(180, 188, 202);
            FocusBorderColor = Color.FromArgb(65, 110, 245);
            CornerRadius = 8;

            FlatStyle = FlatStyle.Flat;
            UseVisualStyleBackColor = false;
            DialogResult = DialogResult.None;

            TabStop = true;
            SetStyle(
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw |
                ControlStyles.UserPaint |
                ControlStyles.Selectable |
                ControlStyles.StandardClick |
                ControlStyles.SupportsTransparentBackColor,
                true
            );
        }

        public void ApplyTheme(
            Color background,
            Color text,
            Color border,
            Color hoverBack,
            Color pressedBack,
            Color disabledBack,
            Color disabledText,
            Color disabledBorder,
            Color focusBorder,
            int radius)
        {
            BackColor = background;
            ForeColor = text;
            BorderColor = border;
            HoverBackColor = hoverBack;
            PressedBackColor = pressedBack;
            DisabledBackColor = disabledBack;
            DisabledTextColor = disabledText;
            DisabledBorderColor = disabledBorder;
            FocusBorderColor = focusBorder;
            CornerRadius = Math.Max(1, radius);
            Invalidate();
        }

        public void NotifyDefault(bool value)
        {
            if (isDefault == value) return;
            isDefault = value;
            Invalidate();
        }

        public void PerformClick()
        {
            if (!Enabled || !Visible) return;
            OnClick(EventArgs.Empty);
        }

        protected override bool IsInputKey(Keys keyData)
        {
            Keys code = keyData & Keys.KeyCode;
            if (code == Keys.Space) return true;
            return base.IsInputKey(keyData);
        }

        protected override void OnTextChanged(EventArgs e)
        {
            base.OnTextChanged(e);

            // Owner-drawn text must repaint immediately when localization
            // changes Text. Without this, old-language pixels remain until
            // hover, resize or another unrelated invalidation.
            Invalidate();
        }
        protected override void OnMouseEnter(EventArgs e)
        {
            hovered = true;
            base.OnMouseEnter(e);
            Invalidate();
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            hovered = false;
            pressed = false;
            base.OnMouseLeave(e);
            Invalidate();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left && Enabled)
            {
                Focus();
                pressed = true;
                Capture = true;
                Invalidate();
            }
            base.OnMouseDown(e);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            // dev7: let WinForms ControlStyles.StandardClick raise exactly one
            // mouse Click. Do not call OnClick manually here.
            pressed = false;
            Capture = false;
            base.OnMouseUp(e);
            Invalidate();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (Enabled && e.KeyCode == Keys.Space && !e.Alt && !e.Control)
            {
                pressed = true;
                e.Handled = true;
                e.SuppressKeyPress = true;
                Invalidate();
            }
            else
            {
                base.OnKeyDown(e);
            }
        }

        protected override void OnKeyUp(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Space && pressed)
            {
                pressed = false;
                e.Handled = true;
                e.SuppressKeyPress = true;
                Invalidate();

                if (Enabled) OnClick(EventArgs.Empty);
            }
            else
            {
                base.OnKeyUp(e);
            }
        }

        protected override void OnGotFocus(EventArgs e)
        {
            base.OnGotFocus(e);
            Invalidate();
        }

        protected override void OnLostFocus(EventArgs e)
        {
            pressed = false;
            Capture = false;
            base.OnLostFocus(e);
            Invalidate();
        }

        protected override void OnEnabledChanged(EventArgs e)
        {
            if (!Enabled)
            {
                hovered = false;
                pressed = false;
            }
            base.OnEnabledChanged(e);
            Invalidate();
        }

        protected override void OnClick(EventArgs e)
        {
            base.OnClick(e);

            Form form = FindForm();
            if (form != null && DialogResult != DialogResult.None)
            {
                form.DialogResult = DialogResult;
            }
        }

        private TextFormatFlags GetTextFlags()
        {
            TextFormatFlags flags =
                TextFormatFlags.NoPrefix |
                TextFormatFlags.EndEllipsis |
                TextFormatFlags.SingleLine;

            switch (TextAlign)
            {
                case ContentAlignment.TopLeft:
                    flags |= TextFormatFlags.Left | TextFormatFlags.Top;
                    break;
                case ContentAlignment.TopCenter:
                    flags |= TextFormatFlags.HorizontalCenter | TextFormatFlags.Top;
                    break;
                case ContentAlignment.TopRight:
                    flags |= TextFormatFlags.Right | TextFormatFlags.Top;
                    break;
                case ContentAlignment.MiddleLeft:
                    flags |= TextFormatFlags.Left | TextFormatFlags.VerticalCenter;
                    break;
                case ContentAlignment.MiddleRight:
                    flags |= TextFormatFlags.Right | TextFormatFlags.VerticalCenter;
                    break;
                case ContentAlignment.BottomLeft:
                    flags |= TextFormatFlags.Left | TextFormatFlags.Bottom;
                    break;
                case ContentAlignment.BottomCenter:
                    flags |= TextFormatFlags.HorizontalCenter | TextFormatFlags.Bottom;
                    break;
                case ContentAlignment.BottomRight:
                    flags |= TextFormatFlags.Right | TextFormatFlags.Bottom;
                    break;
                default:
                    flags |= TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter;
                    break;
            }

            return flags;
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Color outside = Parent != null ? Parent.BackColor : SystemColors.Control;
            using (SolidBrush outsideBrush = new SolidBrush(outside))
                e.Graphics.FillRectangle(outsideBrush, ClientRectangle);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

            Color fill = BackColor;
            Color text = ForeColor;
            Color border = BorderColor;

            if (!Enabled)
            {
                fill = DisabledBackColor;
                text = DisabledTextColor;
                border = DisabledBorderColor;
            }
            else if (pressed)
            {
                fill = PressedBackColor;
            }
            else if (hovered)
            {
                fill = HoverBackColor;
            }

            if (Focused && ShowFocusCues && Enabled)
            {
                border = FocusBorderColor;
            }

            Rectangle rect = new Rectangle(
                0,
                0,
                Math.Max(1, Width - 1),
                Math.Max(1, Height - 1)
            );

            using (GraphicsPath path = MugenDrawing.RoundedRect(rect, CornerRadius))
            using (SolidBrush fillBrush = new SolidBrush(fill))
            using (Pen borderPen = new Pen(border))
            {
                e.Graphics.FillPath(fillBrush, path);
                e.Graphics.DrawPath(borderPen, path);
            }

            Rectangle textRect = new Rectangle(
                Padding.Left + 4,
                Padding.Top + 2,
                Math.Max(1, Width - Padding.Horizontal - 8),
                Math.Max(1, Height - Padding.Vertical - 4)
            );

            TextRenderer.DrawText(
                e.Graphics,
                Text,
                Font,
                textRect,
                text,
                GetTextFlags()
            );
        }
    }
    public sealed class MugenButtonTile : Label
    {
        private Color borderColor;

        public Color BorderColor
        {
            get { return borderColor; }
            set
            {
                borderColor = value;
                Invalidate();
            }
        }

        public int CornerRadius { get; set; }

        public MugenButtonTile()
        {
            BorderStyle = BorderStyle.None;
            BorderColor = Color.FromArgb(180, 188, 202);
            CornerRadius = 5;
            TextAlign = ContentAlignment.MiddleCenter;

            SetStyle(
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw |
                ControlStyles.UserPaint |
                ControlStyles.SupportsTransparentBackColor,
                true
            );
        }

        public void ApplyTheme(Color background, Color text, Color border)
        {
            BackColor = background;
            ForeColor = text;
            BorderColor = border;
            Invalidate();
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Color outside = Parent != null ? Parent.BackColor : SystemColors.Control;
            using (SolidBrush outsideBrush = new SolidBrush(outside))
                e.Graphics.FillRectangle(outsideBrush, ClientRectangle);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

            Rectangle rect = new Rectangle(
                0,
                0,
                Math.Max(1, Width - 1),
                Math.Max(1, Height - 1)
            );

            using (GraphicsPath path = MugenDrawing.RoundedRect(rect, CornerRadius))
            using (SolidBrush fillBrush = new SolidBrush(BackColor))
            using (Pen borderPen = new Pen(BorderColor))
            {
                e.Graphics.FillPath(fillBrush, path);
                e.Graphics.DrawPath(borderPen, path);
            }

            TextRenderer.DrawText(
                e.Graphics,
                Text,
                Font,
                rect,
                ForeColor,
                TextFormatFlags.HorizontalCenter |
                TextFormatFlags.VerticalCenter |
                TextFormatFlags.SingleLine |
                TextFormatFlags.NoPrefix
            );
        }
    }
    public static class MugenMediaKeys
    {
        private const uint WM_APPCOMMAND = 0x0319;

        private const int APPCOMMAND_VOLUME_MUTE = 8;
        private const int APPCOMMAND_VOLUME_DOWN = 9;
        private const int APPCOMMAND_VOLUME_UP = 10;

        private const int APPCOMMAND_MEDIA_NEXTTRACK = 11;
        private const int APPCOMMAND_MEDIA_PREVIOUSTRACK = 12;
        private const int APPCOMMAND_MEDIA_STOP = 13;
        private const int APPCOMMAND_MEDIA_PLAY_PAUSE = 14;

        private const uint SMTO_NORMAL = 0x0000;
        private const uint SMTO_ABORTIFHUNG = 0x0002;

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern IntPtr GetShellWindow();

        [System.Runtime.InteropServices.DllImport(
            "user32.dll",
            SetLastError = true
        )]
        private static extern IntPtr SendMessageTimeout(
            IntPtr hWnd,
            uint Msg,
            IntPtr wParam,
            IntPtr lParam,
            uint fuFlags,
            uint uTimeout,
            out IntPtr lpdwResult
        );

        private static void SendAppCommand(int command)
        {
            IntPtr target = GetForegroundWindow();

            if (target == IntPtr.Zero)
                target = GetShellWindow();

            if (target == IntPtr.Zero)
                throw new InvalidOperationException(
                    "No foreground or shell window is available for WM_APPCOMMAND."
                );

            IntPtr result;
            IntPtr lParam = new IntPtr(command << 16);

            IntPtr sendResult = SendMessageTimeout(
                target,
                WM_APPCOMMAND,
                target,
                lParam,
                SMTO_NORMAL | SMTO_ABORTIFHUNG,
                750,
                out result
            );

            if (sendResult == IntPtr.Zero)
            {
                int error = System.Runtime.InteropServices.Marshal.GetLastWin32Error();

                throw new System.ComponentModel.Win32Exception(
                    error,
                    "WM_APPCOMMAND delivery failed."
                );
            }
        }

        public static void PlayPause()
        {
            SendAppCommand(APPCOMMAND_MEDIA_PLAY_PAUSE);
        }

        public static void PreviousTrack()
        {
            SendAppCommand(APPCOMMAND_MEDIA_PREVIOUSTRACK);
        }

        public static void NextTrack()
        {
            SendAppCommand(APPCOMMAND_MEDIA_NEXTTRACK);
        }

        public static void Stop()
        {
            SendAppCommand(APPCOMMAND_MEDIA_STOP);
        }

        public static void VolumeUp()
        {
            SendAppCommand(APPCOMMAND_VOLUME_UP);
        }

        public static void VolumeDown()
        {
            SendAppCommand(APPCOMMAND_VOLUME_DOWN);
        }

        public static void VolumeMute()
        {
            SendAppCommand(APPCOMMAND_VOLUME_MUTE);
        }
    }
    public static class MugenHotkeys
    {
        private const uint INPUT_KEYBOARD = 1;
        private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
        private const uint KEYEVENTF_KEYUP = 0x0002;

        private const ushort VK_CONTROL = 0x11;
        private const ushort VK_SHIFT = 0x10;
        private const ushort VK_MENU = 0x12;
        private const ushort VK_LWIN = 0x5B;

        [System.Runtime.InteropServices.StructLayout(
            System.Runtime.InteropServices.LayoutKind.Sequential
        )]
        private struct INPUT
        {
            public uint type;
            public InputUnion U;
        }

        [System.Runtime.InteropServices.StructLayout(
            System.Runtime.InteropServices.LayoutKind.Explicit
        )]
        private struct InputUnion
        {
            [System.Runtime.InteropServices.FieldOffset(0)]
            public MOUSEINPUT mi;

            [System.Runtime.InteropServices.FieldOffset(0)]
            public KEYBDINPUT ki;

            [System.Runtime.InteropServices.FieldOffset(0)]
            public HARDWAREINPUT hi;
        }

        [System.Runtime.InteropServices.StructLayout(
            System.Runtime.InteropServices.LayoutKind.Sequential
        )]
        private struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [System.Runtime.InteropServices.StructLayout(
            System.Runtime.InteropServices.LayoutKind.Sequential
        )]
        private struct HARDWAREINPUT
        {
            public uint uMsg;
            public ushort wParamL;
            public ushort wParamH;
        }

        [System.Runtime.InteropServices.StructLayout(
            System.Runtime.InteropServices.LayoutKind.Sequential
        )]
        private struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public UIntPtr time;
            public IntPtr dwExtraInfo;
        }

        [System.Runtime.InteropServices.DllImport(
            "user32.dll",
            SetLastError = true
        )]
        private static extern uint SendInput(
            uint nInputs,
            INPUT[] pInputs,
            int cbSize
        );

        private static bool IsExtended(ushort vk)
        {
            switch (vk)
            {
                case 0x21: // Page Up
                case 0x22: // Page Down
                case 0x23: // End
                case 0x24: // Home
                case 0x25: // Left
                case 0x26: // Up
                case 0x27: // Right
                case 0x28: // Down
                case 0x2D: // Insert
                case 0x2E: // Delete
                case 0x6F: // Numpad Divide
                    return true;

                default:
                    return false;
            }
        }

        private static INPUT KeyInput(ushort vk, bool keyUp)
        {
            uint flags = 0;

            if (IsExtended(vk))
                flags |= KEYEVENTF_EXTENDEDKEY;

            if (keyUp)
                flags |= KEYEVENTF_KEYUP;

            INPUT input = new INPUT();
            input.type = INPUT_KEYBOARD;
            input.U.ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = 0,
                dwFlags = flags,
                time = UIntPtr.Zero,
                dwExtraInfo = IntPtr.Zero
            };

            return input;
        }

        private static void AddDown(
            System.Collections.Generic.List<INPUT> list,
            ushort vk
        )
        {
            list.Add(KeyInput(vk, false));
        }

        private static void AddUp(
            System.Collections.Generic.List<INPUT> list,
            ushort vk
        )
        {
            list.Add(KeyInput(vk, true));
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int vKey);

        public static bool IsWindowsKeyDown()
        {
            const int VK_LWIN = 0x5B;
            const int VK_RWIN = 0x5C;

            return
                (GetAsyncKeyState(VK_LWIN) & 0x8000) != 0 ||
                (GetAsyncKeyState(VK_RWIN) & 0x8000) != 0;
        }
        public static void Send(
            int keyCode,
            bool ctrl,
            bool shift,
            bool alt,
            bool win
        )
        {
            if (keyCode <= 0 || keyCode > 255)
                throw new ArgumentOutOfRangeException("keyCode");

            ushort key = (ushort)keyCode;
            var inputs = new System.Collections.Generic.List<INPUT>();

            if (ctrl) AddDown(inputs, VK_CONTROL);
            if (shift) AddDown(inputs, VK_SHIFT);
            if (alt) AddDown(inputs, VK_MENU);
            if (win) AddDown(inputs, VK_LWIN);

            AddDown(inputs, key);
            AddUp(inputs, key);

            if (win) AddUp(inputs, VK_LWIN);
            if (alt) AddUp(inputs, VK_MENU);
            if (shift) AddUp(inputs, VK_SHIFT);
            if (ctrl) AddUp(inputs, VK_CONTROL);

            INPUT[] packet = inputs.ToArray();

            uint sent = SendInput(
                (uint)packet.Length,
                packet,
                System.Runtime.InteropServices.Marshal.SizeOf(typeof(INPUT))
            );

            if (sent != packet.Length)
            {
                int error =
                    System.Runtime.InteropServices.Marshal.GetLastWin32Error();

                throw new System.ComponentModel.Win32Exception(
                    error,
                    "SendInput did not send the complete hotkey."
                );
            }
        }
    }
    public static class MugenFolderPicker
    {
        private const uint FOS_PICKFOLDERS = 0x00000020;
        private const uint FOS_FORCEFILESYSTEM = 0x00000040;
        private const uint FOS_PATHMUSTEXIST = 0x00000800;
        private const uint SIGDN_FILESYSPATH = 0x80058000;
        private const int ERROR_CANCELLED_HRESULT =
            unchecked((int)0x800704C7);

        [System.Runtime.InteropServices.ComImport]
        [System.Runtime.InteropServices.Guid(
            "DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7"
        )]
        [System.Runtime.InteropServices.ClassInterface(
            System.Runtime.InteropServices.ClassInterfaceType.None
        )]
        private class FileOpenDialogRCW
        {
        }

        [System.Runtime.InteropServices.ComImport]
        [System.Runtime.InteropServices.Guid(
            "42f85136-db7e-439c-85f1-e4075d135fc8"
        )]
        [System.Runtime.InteropServices.InterfaceType(
            System.Runtime.InteropServices.ComInterfaceType.InterfaceIsIUnknown
        )]
        private interface IFileDialog
        {
            [System.Runtime.InteropServices.PreserveSig]
            int Show(IntPtr parent);

            void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
            void SetFileTypeIndex(uint iFileType);
            void GetFileTypeIndex(out uint piFileType);
            void Advise(IntPtr pfde, out uint pdwCookie);
            void Unadvise(uint dwCookie);
            void SetOptions(uint fos);
            void GetOptions(out uint pfos);
            void SetDefaultFolder(IShellItem psi);
            void SetFolder(IShellItem psi);
            void GetFolder(out IShellItem ppsi);
            void GetCurrentSelection(out IShellItem ppsi);

            void SetFileName(
                [System.Runtime.InteropServices.MarshalAs(
                    System.Runtime.InteropServices.UnmanagedType.LPWStr
                )]
                string pszName
            );

            void GetFileName(
                [System.Runtime.InteropServices.MarshalAs(
                    System.Runtime.InteropServices.UnmanagedType.LPWStr
                )]
                out string pszName
            );

            void SetTitle(
                [System.Runtime.InteropServices.MarshalAs(
                    System.Runtime.InteropServices.UnmanagedType.LPWStr
                )]
                string pszTitle
            );

            void SetOkButtonLabel(
                [System.Runtime.InteropServices.MarshalAs(
                    System.Runtime.InteropServices.UnmanagedType.LPWStr
                )]
                string pszText
            );

            void SetFileNameLabel(
                [System.Runtime.InteropServices.MarshalAs(
                    System.Runtime.InteropServices.UnmanagedType.LPWStr
                )]
                string pszLabel
            );

            void GetResult(out IShellItem ppsi);
            void AddPlace(IShellItem psi, int fdap);

            void SetDefaultExtension(
                [System.Runtime.InteropServices.MarshalAs(
                    System.Runtime.InteropServices.UnmanagedType.LPWStr
                )]
                string pszDefaultExtension
            );

            void Close(int hr);
            void SetClientGuid(ref Guid guid);
            void ClearClientData();
            void SetFilter(IntPtr pFilter);
        }

        [System.Runtime.InteropServices.ComImport]
        [System.Runtime.InteropServices.Guid(
            "43826D1E-E718-42EE-BC55-A1E261C37BFE"
        )]
        [System.Runtime.InteropServices.InterfaceType(
            System.Runtime.InteropServices.ComInterfaceType.InterfaceIsIUnknown
        )]
        private interface IShellItem
        {
            void BindToHandler(
                IntPtr pbc,
                ref Guid bhid,
                ref Guid riid,
                out IntPtr ppv
            );

            void GetParent(out IShellItem ppsi);

            void GetDisplayName(
                uint sigdnName,
                out IntPtr ppszName
            );

            void GetAttributes(
                uint sfgaoMask,
                out uint psfgaoAttribs
            );

            void Compare(
                IShellItem psi,
                uint hint,
                out int piOrder
            );
        }

        [System.Runtime.InteropServices.DllImport(
            "shell32.dll",
            CharSet = System.Runtime.InteropServices.CharSet.Unicode,
            PreserveSig = true
        )]
        private static extern int SHCreateItemFromParsingName(
            string pszPath,
            IntPtr pbc,
            ref Guid riid,
            [System.Runtime.InteropServices.MarshalAs(
                System.Runtime.InteropServices.UnmanagedType.Interface
            )]
            out IShellItem ppv
        );

        public static string SelectFolder(
            IntPtr owner,
            string initialPath,
            string title,
            string okButtonLabel
        )
        {
            IFileDialog dialog = null;
            IShellItem initialItem = null;
            IShellItem resultItem = null;
            IntPtr pathPtr = IntPtr.Zero;

            try
            {
                dialog = (IFileDialog)new FileOpenDialogRCW();

                uint options;
                dialog.GetOptions(out options);

                options |=
                    FOS_PICKFOLDERS |
                    FOS_FORCEFILESYSTEM |
                    FOS_PATHMUSTEXIST;

                dialog.SetOptions(options);

                if (!string.IsNullOrWhiteSpace(title))
                    dialog.SetTitle(title);

                if (!string.IsNullOrWhiteSpace(okButtonLabel))
                    dialog.SetOkButtonLabel(okButtonLabel);

                if (
                    !string.IsNullOrWhiteSpace(initialPath) &&
                    System.IO.Directory.Exists(initialPath)
                )
                {
                    Guid shellItemId = new Guid(
                        "43826D1E-E718-42EE-BC55-A1E261C37BFE"
                    );

                    int createHr = SHCreateItemFromParsingName(
                        initialPath,
                        IntPtr.Zero,
                        ref shellItemId,
                        out initialItem
                    );

                    if (createHr >= 0 && initialItem != null)
                        dialog.SetFolder(initialItem);
                }

                int showHr = dialog.Show(owner);

                if (showHr == ERROR_CANCELLED_HRESULT)
                    return null;

                if (showHr < 0)
                    System.Runtime.InteropServices.Marshal.ThrowExceptionForHR(
                        showHr
                    );

                dialog.GetResult(out resultItem);
                resultItem.GetDisplayName(
                    SIGDN_FILESYSPATH,
                    out pathPtr
                );

                if (pathPtr == IntPtr.Zero)
                    return null;

                return System.Runtime.InteropServices.Marshal.PtrToStringUni(
                    pathPtr
                );
            }
            finally
            {
                if (pathPtr != IntPtr.Zero)
                    System.Runtime.InteropServices.Marshal.FreeCoTaskMem(
                        pathPtr
                    );

                if (
                    resultItem != null &&
                    System.Runtime.InteropServices.Marshal.IsComObject(
                        resultItem
                    )
                )
                {
                    System.Runtime.InteropServices.Marshal.FinalReleaseComObject(
                        resultItem
                    );
                }

                if (
                    initialItem != null &&
                    System.Runtime.InteropServices.Marshal.IsComObject(
                        initialItem
                    )
                )
                {
                    System.Runtime.InteropServices.Marshal.FinalReleaseComObject(
                        initialItem
                    );
                }

                if (
                    dialog != null &&
                    System.Runtime.InteropServices.Marshal.IsComObject(dialog)
                )
                {
                    System.Runtime.InteropServices.Marshal.FinalReleaseComObject(
                        dialog
                    );
                }
            }
        }
    }
    public sealed class MugenProgressBar : Control
    {
        private int minimum;
        private int maximum;
        private int currentValue;

        // UI-only percentage used for painting. Never used by controller/audio logic.
        private int displayPercent;

        // Hysteresis around the next integer-percent boundary, expressed as a
        // fraction of one percent. 0.20 means a value has to move 20% of the
        // way into the neighboring 1% bucket before the picture changes.
        private const double PercentBoundaryHysteresis = 0.20;

        public Color TrackColor { get; set; }
        public Color FillColor { get; set; }
        public Color BorderColor { get; set; }

        public int Minimum
        {
            get { return minimum; }
            set
            {
                minimum = value;
                if (maximum < minimum) maximum = minimum;
                if (currentValue < minimum) currentValue = minimum;
                displayPercent = GetExactRoundedPercent(currentValue);
                Invalidate();
            }
        }

        public int Maximum
        {
            get { return maximum; }
            set
            {
                maximum = Math.Max(value, minimum);
                if (currentValue > maximum) currentValue = maximum;
                displayPercent = GetExactRoundedPercent(currentValue);
                Invalidate();
            }
        }

        private double GetExactPercent(int rawValue)
        {
            double range = Math.Max(1.0, maximum - minimum);
            return Math.Max(0.0, Math.Min(100.0, ((rawValue - minimum) * 100.0) / range));
        }

        private int GetExactRoundedPercent(int rawValue)
        {
            return (int)Math.Round(GetExactPercent(rawValue), MidpointRounding.AwayFromZero);
        }

        public int Value
        {
            // Exact application-facing value remains untouched.
            get { return currentValue; }
            set
            {
                int clamped = Math.Max(minimum, Math.Min(maximum, value));
                currentValue = clamped;

                double exactPercent = GetExactPercent(clamped);

                if (clamped == minimum)
                {
                    if (displayPercent != 0)
                    {
                        displayPercent = 0;
                        Invalidate();
                    }
                    return;
                }

                if (clamped == maximum)
                {
                    if (displayPercent != 100)
                    {
                        displayPercent = 100;
                        Invalidate();
                    }
                    return;
                }

                int nextPercent = displayPercent;

                // Move upward only after crossing the halfway boundary plus a
                // small margin. For example 40 -> 41 occurs above 40.70%.
                while (nextPercent < 100 &&
                       exactPercent >= (nextPercent + 0.5 + PercentBoundaryHysteresis))
                {
                    nextPercent++;
                }

                // Move downward only after crossing the opposite boundary by
                // the same margin. This creates a stable visual hysteresis band.
                while (nextPercent > 0 &&
                       exactPercent <= (nextPercent - 0.5 - PercentBoundaryHysteresis))
                {
                    nextPercent--;
                }

                if (nextPercent != displayPercent)
                {
                    displayPercent = nextPercent;
                    Invalidate();
                }
            }
        }

        public MugenProgressBar()
        {
            minimum = 0;
            maximum = 100;
            currentValue = 0;
            displayPercent = 0;

            TrackColor = Color.FromArgb(235, 239, 247);
            FillColor = Color.FromArgb(65, 110, 245);
            BorderColor = Color.Transparent;
            SetStyle(ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw |
                     ControlStyles.UserPaint, true);
        }

        public void ApplyTheme(Color track, Color fill, Color border)
        {
            TrackColor = track;
            FillColor = fill;
            BorderColor = border;
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

            Rectangle rect = new Rectangle(0, 0, Math.Max(1, Width - 1), Math.Max(1, Height - 1));
            int radius = Math.Max(2, Math.Min(6, Height / 2));

            using (GraphicsPath trackPath = MugenDrawing.RoundedRect(rect, radius))
            using (SolidBrush trackBrush = new SolidBrush(TrackColor))
            {
                e.Graphics.FillPath(trackBrush, trackPath);

                if (BorderColor.A > 0)
                {
                    using (Pen borderPen = new Pen(BorderColor))
                        e.Graphics.DrawPath(borderPen, trackPath);
                }
            }

            double fraction = Math.Max(0.0, Math.Min(1.0, displayPercent / 100.0));
            int fillWidth = (int)Math.Round(rect.Width * fraction);

            if (fillWidth > 0)
            {
                Rectangle fillRect = new Rectangle(rect.Left, rect.Top, Math.Max(1, fillWidth), rect.Height);
                using (GraphicsPath fillPath = MugenDrawing.RoundedRect(fillRect, radius))
                using (SolidBrush fillBrush = new SolidBrush(FillColor))
                    e.Graphics.FillPath(fillBrush, fillPath);
            }
        }
    }

    public sealed class MugenComboBox : ComboBox
    {
        private Color borderColor;
        private Color accentColor;
        private Color disabledTextColor;
        private Color disabledBackColor;
        private bool hovered;

        public MugenComboBox()
        {
            DrawMode = DrawMode.OwnerDrawFixed;
            FlatStyle = FlatStyle.Flat;
            ItemHeight = 20;
            borderColor = Color.FromArgb(180, 188, 202);
            accentColor = Color.FromArgb(65, 110, 245);
            disabledTextColor = Color.Gray;
            disabledBackColor = Color.FromArgb(235, 237, 242);
        }

        public void ApplyTheme(
            Color background,
            Color text,
            Color border,
            Color accent,
            Color disabledText,
            Color disabledBack)
        {
            BackColor = background;
            ForeColor = text;
            borderColor = border;
            accentColor = accent;
            disabledTextColor = disabledText;
            disabledBackColor = disabledBack;
            Invalidate();
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            hovered = true;
            base.OnMouseEnter(e);
            Invalidate();
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            hovered = false;
            base.OnMouseLeave(e);
            Invalidate();
        }

        protected override void OnGotFocus(EventArgs e)
        {
            base.OnGotFocus(e);
            Invalidate();
        }

        protected override void OnLostFocus(EventArgs e)
        {
            base.OnLostFocus(e);
            Invalidate();
        }

        protected override void OnEnabledChanged(EventArgs e)
        {
            base.OnEnabledChanged(e);
            Invalidate();
        }

        protected override void OnSelectedIndexChanged(EventArgs e)
        {
            base.OnSelectedIndexChanged(e);
            Invalidate();
        }

        protected override void OnDrawItem(DrawItemEventArgs e)
        {
            if (e.Index < 0)
            {
                base.OnDrawItem(e);
                return;
            }

            bool selected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
            Color back = selected ? accentColor : BackColor;
            Color fore = selected ? Color.White : ForeColor;

            using (SolidBrush brush = new SolidBrush(back))
                e.Graphics.FillRectangle(brush, e.Bounds);

            string text = GetItemText(Items[e.Index]);
            Rectangle textRect = new Rectangle(e.Bounds.X + 7, e.Bounds.Y, Math.Max(1, e.Bounds.Width - 12), e.Bounds.Height);
            TextRenderer.DrawText(
                e.Graphics,
                text,
                Font,
                textRect,
                fore,
                TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix
            );

            e.DrawFocusRectangle();
        }

        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);

            const int WM_PAINT = 0x000F;
            const int WM_NCPAINT = 0x0085;
            const int WM_SETFOCUS = 0x0007;
            const int WM_KILLFOCUS = 0x0008;

            if (m.Msg == WM_PAINT || m.Msg == WM_NCPAINT || m.Msg == WM_SETFOCUS || m.Msg == WM_KILLFOCUS)
                DrawMugenSurface();
        }

        private void DrawMugenSurface()
        {
            if (!IsHandleCreated || Width < 12 || Height < 8) return;

            try
            {
                using (Graphics g = CreateGraphics())
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;

                    Color back = Enabled ? BackColor : disabledBackColor;
                    Color fore = Enabled ? ForeColor : disabledTextColor;
                    Color border = (Focused || hovered) && Enabled ? accentColor : borderColor;

                    Rectangle whole = new Rectangle(0, 0, Width, Height);
                    using (SolidBrush backBrush = new SolidBrush(back))
                        g.FillRectangle(backBrush, whole);

                    // Draw the border one pixel inside the native ComboBox
                    // client area. A stroke on x=0/y=0 is half-clipped by the
                    // Win32 control window and can make the left/top edge look
                    // missing, especially on wide owner-drawn combos.
                    Rectangle borderRect = new Rectangle(
                        1,
                        1,
                        Math.Max(1, Width - 3),
                        Math.Max(1, Height - 3)
                    );

                    int buttonWidth = Math.Min(24, Math.Max(19, Height - 2));
                    Rectangle textRect = new Rectangle(7, 1, Math.Max(1, Width - buttonWidth - 10), Height - 2);
                    string selectedText = SelectedIndex >= 0 ? GetItemText(SelectedItem) : Text;

                    TextRenderer.DrawText(
                        g,
                        selectedText,
                        Font,
                        textRect,
                        fore,
                        TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix
                    );

                    int dividerX = Width - buttonWidth;
                    using (Pen divider = new Pen(borderColor))
                        g.DrawLine(divider, dividerX, 3, dividerX, Height - 4);

                    float cx = dividerX + buttonWidth / 2f;
                    float cy = Height / 2f + 1f;
                    PointF[] arrow = new PointF[] {
                        new PointF(cx - 4f, cy - 2f),
                        new PointF(cx + 4f, cy - 2f),
                        new PointF(cx, cy + 2.5f)
                    };
                    using (SolidBrush arrowBrush = new SolidBrush(fore))
                        g.FillPolygon(arrowBrush, arrow);

                    using (Pen pen = new Pen(border))
                        g.DrawRectangle(pen, borderRect);
                }
            }
            catch
            {
                // Painting is cosmetic; never let it break combo-box behavior.
            }
        }
    }

    public sealed class MugenToolStripRenderer : ToolStripProfessionalRenderer
    {
        private readonly Color back;
        private readonly Color hover;
        private readonly Color text;
        private readonly Color border;

        public MugenToolStripRenderer(Color backColor, Color hoverColor, Color textColor, Color borderColor)
        {
            back = backColor;
            hover = hoverColor;
            text = textColor;
            border = borderColor;
            RoundedEdges = false;
        }

        protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
        {
            using (SolidBrush brush = new SolidBrush(back))
                e.Graphics.FillRectangle(brush, e.AffectedBounds);
        }

        protected override void OnRenderImageMargin(ToolStripRenderEventArgs e)
        {
            using (SolidBrush brush = new SolidBrush(back))
                e.Graphics.FillRectangle(brush, e.AffectedBounds);
        }

        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
        {
            Color itemBack = (e.Item.Selected && e.Item.Enabled) ? hover : back;
            using (SolidBrush brush = new SolidBrush(itemBack))
                e.Graphics.FillRectangle(brush, new Rectangle(Point.Empty, e.Item.Size));
        }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = e.Item.Enabled ? text : Color.FromArgb(
                Math.Max(70, text.R - 80),
                Math.Max(70, text.G - 80),
                Math.Max(70, text.B - 80)
            );
            base.OnRenderItemText(e);
        }

        protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
        {
            int y = e.Item.Height / 2;
            using (Pen pen = new Pen(border))
                e.Graphics.DrawLine(pen, 5, y, Math.Max(6, e.Item.Width - 6), y);
        }

        protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
        {
            Rectangle rect = new Rectangle(0, 0, Math.Max(1, e.ToolStrip.Width - 1), Math.Max(1, e.ToolStrip.Height - 1));
            using (Pen pen = new Pen(border))
                e.Graphics.DrawRectangle(pen, rect);
        }
    }

    public static class ThemeInterop
    {
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int valueSize);

        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
        private static extern int SetWindowTheme(IntPtr hwnd, string pszSubAppName, string pszSubIdList);

        public static void SetDarkControlTheme(IntPtr hwnd, bool dark, bool comboBox)
        {
            if (hwnd == IntPtr.Zero) return;
            try
            {
                if (dark)
                {
                    // Combo boxes use the CFD class on current Windows builds;
                    // Explorer is a useful fallback for the other standard controls.
                    string theme = comboBox ? "DarkMode_CFD" : "DarkMode_Explorer";
                    int hr = SetWindowTheme(hwnd, theme, null);
                    if (hr != 0 && comboBox)
                        SetWindowTheme(hwnd, "DarkMode_Explorer", null);
                }
                else
                {
                    // Restore the class' normal visual style.
                    SetWindowTheme(hwnd, null, null);
                }
            }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }
        }

        public static void SetDarkTitleBar(IntPtr hwnd, bool dark)
        {
            if (hwnd == IntPtr.Zero) return;
            int enabled = dark ? 1 : 0;
            try
            {
                // DWMWA_USE_IMMERSIVE_DARK_MODE is 20 on current Windows builds;
                // 19 is kept as a best-effort fallback for older Windows 10 builds.
                int hr = DwmSetWindowAttribute(hwnd, 20, ref enabled, sizeof(int));
                if (hr != 0)
                    DwmSetWindowAttribute(hwnd, 19, ref enabled, sizeof(int));
            }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }
        }
    }

    public sealed class ThemePreferenceBridge : IDisposable
    {
        private readonly Control control;
        private readonly Action<string> callback;
        private bool disposed;

        public ThemePreferenceBridge(Control control, Action<string> callback)
        {
            if (control == null) throw new ArgumentNullException("control");
            if (callback == null) throw new ArgumentNullException("callback");
            this.control = control;
            this.callback = callback;
            SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        }

        private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
        {
            if (disposed || control.IsDisposed || !control.IsHandleCreated) return;
            try
            {
                string category = e.Category.ToString();
                if (control.InvokeRequired)
                    control.Invoke(callback, new object[] { category });
                else
                    callback(category);
            }
            catch (InvalidOperationException) { }
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        }
    }

    public sealed class PowerModeBridge : IDisposable
    {
        private readonly Control control;
        private readonly Action<string> callback;
        private bool disposed;

        public PowerModeBridge(Control control, Action<string> callback)
        {
            if (control == null) throw new ArgumentNullException("control");
            if (callback == null) throw new ArgumentNullException("callback");
            this.control = control;
            this.callback = callback;
            SystemEvents.PowerModeChanged += OnPowerModeChanged;
        }

        private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
        {
            if (disposed || control.IsDisposed || !control.IsHandleCreated) return;

            try
            {
                string modeName = e.Mode.ToString();
                // Power-mode bookkeeping must run on the WinForms thread before the
                // SystemEvents callback returns. Control.Invoke marshals synchronously
                // while preserving the established serial connection across suspend.
                if (control.InvokeRequired)
                    control.Invoke(callback, new object[] { modeName });
                else
                    callback(modeName);
            }
            catch (InvalidOperationException) { }
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        }
    }
}
'@
$windowingReferences = @(
    [System.Windows.Forms.Control].Assembly.Location
    [System.Drawing.Color].Assembly.Location
    [Microsoft.Win32.SystemEvents].Assembly.Location
) | Select-Object -Unique
Add-Type -TypeDefinition $windowingSource -Language CSharp -ReferencedAssemblies $windowingReferences

# Used by the patch installer to verify that runtime Add-Type compilation works
# before the live MugenDeej.ps1 file is replaced.
if ($env:MUGENDEEJ_BOOTSTRAP_VALIDATE -eq '1') { exit 0 }

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

$script:AppVersion = '1.0.0'
$script:ControllerProtocol = 'unknown'
$script:DetectedSliderCount = 0
$script:DetectedButtonCount = 0
$script:LatestButtons = @()
$script:LastButtonStates = @()
$script:LastCapabilityMismatchLog = [DateTime]::MinValue
$script:ButtonActionConfigPath = Join-Path $script:BaseDir 'button-actions.json'
$script:LegacyButtonActionConfigPath = Join-Path $script:BaseDir 'button-actions.dev.json'
$script:ButtonActionsLoaded = $false
$script:ButtonActions = @()
$script:SoftMutedSliders = @{}
$script:LastButtonActionAt = @{}
$script:ButtonSettingsButton = $null
$script:BackupMenuButton = $null
$script:SettingsHintControl = $null
$script:ButtonStateGroup = $null
$script:ButtonStateFlow = $null
$script:MainButtonIndicators = @()
$script:KnobMuteLabels = @()
$script:LastButtonUiVisible = $null
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

function Get-ExpectedStartupCommand {
    return ('"{0}"' -f $script:ExecutablePath)
}

function Get-StartupCommand {
    try {
        if (-not (Test-Path -LiteralPath $script:StartupRegistryPath)) { return '' }
        $item = Get-ItemProperty -LiteralPath $script:StartupRegistryPath -Name $script:StartupRegistryName -ErrorAction SilentlyContinue
        if ($null -eq $item) { return '' }
        $property = $item.PSObject.Properties[$script:StartupRegistryName]
        if ($null -eq $property) { return '' }
        return [string]$property.Value
    }
    catch {
        Write-Log ("Failed to read Windows startup registration: {0}" -f $_.Exception.Message) 'WARN'
        return ''
    }
}

function Test-StartupEnabled {
    return (-not [string]::IsNullOrWhiteSpace((Get-StartupCommand)))
}

function Set-StartupEnabled {
    param([Parameter(Mandatory = $true)][bool]$Enabled)

    if ($Enabled) {
        if (-not (Test-Path -LiteralPath $script:ExecutablePath)) {
            throw ("MugenDeej.exe was not found next to MugenDeej.ps1: {0}" -f $script:ExecutablePath)
        }
        if (-not (Test-Path -LiteralPath $script:StartupRegistryPath)) {
            [void](New-Item -Path $script:StartupRegistryPath)
        }
        $command = Get-ExpectedStartupCommand
        [void](New-ItemProperty -LiteralPath $script:StartupRegistryPath -Name $script:StartupRegistryName -Value $command -PropertyType String -Force)
        Write-Log ("Windows startup enabled: {0}" -f $command) 'INFO'
    }
    else {
        if (Test-Path -LiteralPath $script:StartupRegistryPath) {
            Remove-ItemProperty -LiteralPath $script:StartupRegistryPath -Name $script:StartupRegistryName -ErrorAction SilentlyContinue
        }
        Write-Log 'Windows startup disabled' 'INFO'
    }
}

function Sync-StartupRegistrationPath {
    $current = Get-StartupCommand
    if ([string]::IsNullOrWhiteSpace($current)) { return }
    if (-not (Test-Path -LiteralPath $script:ExecutablePath)) { return }

    $expected = Get-ExpectedStartupCommand
    if ($current -ne $expected) {
        try {
            if (-not (Test-Path -LiteralPath $script:StartupRegistryPath)) {
            [void](New-Item -Path $script:StartupRegistryPath)
        }
            [void](New-ItemProperty -LiteralPath $script:StartupRegistryPath -Name $script:StartupRegistryName -Value $expected -PropertyType String -Force)
            Write-Log ("Windows startup path updated for portable location: {0}" -f $expected) 'INFO'
        }
        catch {
            Write-Log ("Failed to update Windows startup path: {0}" -f $_.Exception.Message) 'WARN'
        }
    }
}

function Ensure-FormVisible {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Form]$Form,
        [switch]$CenterIfOffscreen
    )

    if ($null -eq $Form -or $Form.IsDisposed) { return }

    try {
        $bounds = if ($Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) {
            $Form.Bounds
        }
        else {
            $Form.RestoreBounds
        }

        if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
            $bounds = New-Object System.Drawing.Rectangle($Form.Location, $Form.Size)
        }

        $isVisible = $false
        foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
            $intersection = [System.Drawing.Rectangle]::Intersect($bounds, $screen.WorkingArea)
            if ($intersection.Width -ge 80 -and $intersection.Height -ge 60) {
                $isVisible = $true
                break
            }
        }

        if ($isVisible) { return }

        $targetArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $x = $targetArea.Left + [Math]::Max(0, [int](($targetArea.Width - $Form.Width) / 2))
        $y = $targetArea.Top + [Math]::Max(0, [int](($targetArea.Height - $Form.Height) / 2))

        $Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $Form.Location = New-Object System.Drawing.Point($x, $y)
        Write-Log ("Window '{0}' was moved back into the visible desktop area" -f $Form.Text) 'WARN'
    }
    catch {
        Write-Log ("Failed to validate window position for '{0}': {1}" -f $Form.Text, $_.Exception.Message) 'WARN'
    }
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
        configVersion = 9
        app = [ordered]@{
            language = 'auto'
            theme = 'auto'
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
    Add-MissingConfigProperty -Object $Config.app -Name 'theme' -Value 'auto'
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
    $Config.configVersion = 9
    return $Config
}

$script:Config = Ensure-ConfigShape -Config (Load-Config)
Sync-StartupRegistrationPath
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
$script:ExitRequested = $false
$script:ShutdownFinalizing = $false
$script:RestartRequested = $false
$script:IsSuspended = $false
$script:ResumeReconnectAt = [DateTime]::MinValue
$script:ResumePreferredPort = ''
$script:ResumeAutoReconnectSuppressed = $false
$script:ResumeReconnectDelaySeconds = 15
$script:ResumeHotplugRetrySeconds = 2
$script:ResumeHotplugRetryWindowSeconds = 20
$script:ResumeHotplugSlowRetrySeconds = 10
$script:ResumeHotplugRetryUntil = [DateTime]::MinValue
$script:ControllerRecoveryPort = ''
$script:ControllerRecoveryAt = [DateTime]::MinValue
$script:ControllerRecoveryFastUntil = [DateTime]::MinValue
$script:ControllerRecoveryFastSeconds = 2
$script:ControllerRecoveryFastWindowSeconds = 20
$script:ControllerRecoverySlowSeconds = 10
$script:ResumePreserveUntil = [DateTime]::MinValue
$script:ResumePreserveStartedAt = [DateTime]::MinValue
$script:ResumePreserveFirstErrorLogged = $false
$script:ResumePreserveSeconds = 15
$script:ProbeGeneration = 0
$script:ActiveProbeSerial = $null
$script:PowerBridge = $null
$script:PowerUiAction = $null
$script:ThemePreferenceBridge = $null
$script:ThemeUiAction = $null
$script:ThemeCombo = $null
$script:TrayMenu = $null
$script:UpdatingThemeCombo = $false
$script:LastEffectiveTheme = ''
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
        ThemeLabel = 'Тема:'
        ThemeAuto = 'Авто'
        ThemeLight = 'Светлая'
        ThemeDark = 'Тёмная'
        Subtitle = 'Настольная панель управления'
        Starting = 'Запуск…'
        KnobStatus = 'Состояние регуляторов'
        ConfigureKnobs = 'Настроить регуляторы'
        ConfigureHint = 'Переименуйте регуляторы и назначьте им общую громкость, приложения или уровень микрофона.'
        DiagnosticsClosed = 'Подключение и диагностика ▼'
        DiagnosticsOpen = 'Подключение и диагностика ▲'
        BackupMenu = 'Резервная копия ▼'
        BackupCreate = 'Создать резервную копию…'
        BackupRestore = 'Восстановить из резервной копии…'
        BackupSaveTitle = 'Создание резервной копии Mugen Deej'
        BackupOpenTitle = 'Восстановление резервной копии Mugen Deej'
        BackupCreated = 'Резервная копия создана:'
        BackupCreateFailed = 'Не удалось создать резервную копию:'
        BackupRestoreConfirm = 'Текущие настройки будут заменены настройками из резервной копии. Перед восстановлением Mugen Deej автоматически сохранит аварийную копию текущих настроек. Продолжить?'
        BackupRestored = 'Настройки восстановлены.'
        BackupEmergencyCopy = 'Аварийная копия текущих настроек сохранена:'
        BackupRestartPrompt = 'Для полного применения резервной копии необходимо перезапустить Mugen Deej. Перезапустить сейчас?'
        BackupInvalid = 'Не удалось прочитать резервную копию:'
        BackupRestoreFailed = 'Не удалось восстановить настройки:'
        DialogYes = 'Да'
        DialogNo = 'Нет'
        DialogOK = 'ОК'
        ConnectionGroup = 'Подключение контроллера'
        AutoPort = 'Определять COM-порт автоматически'
        ManualPort = 'Выбрать порт вручную'
        RefreshList = 'Обновить список'
        Reconnect = 'Найти и подключить заново'
        ConnectionHelp = 'Автоматический режим подходит почти всегда. Ручной выбор пригодится, если подключено несколько похожих COM-устройств.'
        DriverAndLog = 'Драйвер и журнал'
        StartupGroup = 'Запуск программы'
        StartWithWindows = 'Запускать Mugen Deej вместе с Windows'
        StartMinimized = 'Запускать свёрнутым в область уведомлений'
        StartupDeleteHint = 'Перед удалением portable-папки отключите автозапуск.'
        StartupSettingsErrorTitle = 'Настройки запуска'
        StartupSettingsError = "Не удалось изменить параметры запуска.`r`n`r`n{0}"
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
        StatusResumeWaiting = 'Windows восстанавливает USB. Проверка контроллера через {0} с…'
        StatusResumePreserving = 'Windows восстанавливает прежнее соединение с {0}. Ожидаем данные контроллера…'
        StatusResumeReconnectFailed = 'Контроллер на {0} не восстановился после сна. Переподключите USB — Mugen Deej подключится автоматически.'
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
        ThemeLabel = 'Theme:'
        ThemeAuto = 'Auto'
        ThemeLight = 'Light'
        ThemeDark = 'Dark'
        Subtitle = 'Desktop control surface'
        Starting = 'Starting…'
        KnobStatus = 'Control status'
        ConfigureKnobs = 'Configure controls'
        ConfigureHint = 'Rename controls and assign master volume, applications, or microphone level.'
        DiagnosticsClosed = 'Connection and diagnostics ▼'
        DiagnosticsOpen = 'Connection and diagnostics ▲'
        BackupMenu = 'Backup & restore ▼'
        BackupCreate = 'Create backup…'
        BackupRestore = 'Restore from backup…'
        BackupSaveTitle = 'Create Mugen Deej backup'
        BackupOpenTitle = 'Restore Mugen Deej backup'
        BackupCreated = 'Backup created:'
        BackupCreateFailed = 'Could not create the backup:'
        BackupRestoreConfirm = 'Current settings will be replaced with settings from the backup. Before restoring, Mugen Deej will automatically save an emergency copy of the current settings. Continue?'
        BackupRestored = 'Settings restored.'
        BackupEmergencyCopy = 'An emergency copy of the current settings was saved:'
        BackupRestartPrompt = 'Mugen Deej must be restarted to apply the backup completely. Restart now?'
        BackupInvalid = 'Could not read the backup:'
        BackupRestoreFailed = 'Could not restore settings:'
        DialogYes = 'Yes'
        DialogNo = 'No'
        DialogOK = 'OK'
        ConnectionGroup = 'Controller connection'
        AutoPort = 'Detect COM port automatically'
        ManualPort = 'Select port manually'
        RefreshList = 'Refresh list'
        Reconnect = 'Find and reconnect'
        ConnectionHelp = 'Automatic mode is recommended. Use manual selection when several similar COM devices are connected.'
        DriverAndLog = 'Driver and log'
        StartupGroup = 'Application startup'
        StartWithWindows = 'Start Mugen Deej with Windows'
        StartMinimized = 'Start minimized to the notification area'
        StartupDeleteHint = 'Disable startup before deleting the portable folder.'
        StartupSettingsErrorTitle = 'Startup settings'
        StartupSettingsError = "Could not change the startup settings.`r`n`r`n{0}"
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
        StatusResumeWaiting = 'Windows is restoring USB. The controller will be checked in {0} s…'
        StatusResumePreserving = 'Windows is restoring the existing connection on {0}. Waiting for controller data…'
        StatusResumeReconnectFailed = 'The controller on {0} did not recover after sleep. Reconnect its USB cable; Mugen Deej will connect automatically.'
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

$script:ThemePalettes = @{
    light = @{
        # Softer canvas for bright/HDR monitors: not a white sheet anymore.
        Window = [System.Drawing.Color]::FromArgb(228, 233, 243)

        # Cards stay bright, but are visibly separated from the canvas.
        Surface = [System.Drawing.Color]::FromArgb(249, 250, 253)
        SurfaceAlt = [System.Drawing.Color]::FromArgb(245, 247, 252)

        # Controls/inputs form a third visual layer.
        Control = [System.Drawing.Color]::FromArgb(247, 249, 253)
        ControlHover = [System.Drawing.Color]::FromArgb(232, 238, 250)
        ControlPressed = [System.Drawing.Color]::FromArgb(220, 230, 248)
        Input = [System.Drawing.Color]::FromArgb(252, 253, 255)

        Text = [System.Drawing.Color]::FromArgb(29, 35, 50)
        Muted = [System.Drawing.Color]::FromArgb(93, 103, 123)
        DisabledText = [System.Drawing.Color]::FromArgb(128, 137, 153)
        DisabledControl = [System.Drawing.Color]::FromArgb(229, 233, 241)

        # Stronger than dev3 so card geometry survives HDR/high brightness.
        Border = [System.Drawing.Color]::FromArgb(187, 197, 215)

        Accent = [System.Drawing.Color]::FromArgb(63, 105, 245)
        AccentHover = [System.Drawing.Color]::FromArgb(78, 119, 255)
        AccentPressed = [System.Drawing.Color]::FromArgb(49, 91, 230)
        AccentText = [System.Drawing.Color]::White

        ProgressTrack = [System.Drawing.Color]::FromArgb(222, 229, 242)
    }
    dark = @{
        Window = [System.Drawing.Color]::FromArgb(20, 23, 29)
        Surface = [System.Drawing.Color]::FromArgb(28, 32, 40)
        SurfaceAlt = [System.Drawing.Color]::FromArgb(28, 32, 40)
        Control = [System.Drawing.Color]::FromArgb(34, 39, 48)
        ControlHover = [System.Drawing.Color]::FromArgb(43, 50, 62)
        ControlPressed = [System.Drawing.Color]::FromArgb(51, 60, 74)
        Input = [System.Drawing.Color]::FromArgb(30, 35, 43)
        Text = [System.Drawing.Color]::FromArgb(239, 243, 250)
        Muted = [System.Drawing.Color]::FromArgb(164, 174, 192)
        DisabledText = [System.Drawing.Color]::FromArgb(132, 142, 158)
        DisabledControl = [System.Drawing.Color]::FromArgb(44, 49, 59)
        Border = [System.Drawing.Color]::FromArgb(66, 75, 91)
        Accent = [System.Drawing.Color]::FromArgb(80, 130, 255)
        AccentHover = [System.Drawing.Color]::FromArgb(95, 145, 255)
        AccentPressed = [System.Drawing.Color]::FromArgb(66, 114, 235)
        AccentText = [System.Drawing.Color]::White
        ProgressTrack = [System.Drawing.Color]::FromArgb(44, 50, 61)
    }
}

function Get-NormalizedThemeSetting {
    param([string]$Value)
    $normalized = ([string]$Value).Trim().ToLowerInvariant()
    if ($normalized -in @('light', 'dark')) { return $normalized }
    return 'auto'
}

function Get-WindowsTheme {
    try {
        $personalizePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        $item = Get-ItemProperty -LiteralPath $personalizePath -Name 'AppsUseLightTheme' -ErrorAction Stop
        if ([int]$item.AppsUseLightTheme -eq 0) { return 'dark' }
    }
    catch {
        # Light is the safest fallback on unsupported/partially configured systems.
    }
    return 'light'
}

function Get-EffectiveTheme {
    $setting = Get-NormalizedThemeSetting -Value ([string]$script:Config.app.theme)
    if ($setting -eq 'auto') { return Get-WindowsTheme }
    return $setting
}

function Test-IsMutedColor {
    param([System.Drawing.Color]$Color)
    $argb = $Color.ToArgb()
    $known = @(
        [System.Drawing.Color]::DimGray.ToArgb(),
        [System.Drawing.Color]::Gray.ToArgb(),
        $script:ThemePalettes.light.Muted.ToArgb(),
        $script:ThemePalettes.dark.Muted.ToArgb()
    )
    return ($known -contains $argb)
}

function Set-RoundedControlRegion {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Control,
        [Parameter(Mandatory = $true)][int]$Radius
    )

    if ($Control.IsDisposed -or $Control.Width -le 1 -or $Control.Height -le 1) {
        return
    }

    $safeRadius = [Math]::Max(
        1,
        [Math]::Min(
            $Radius,
            [int][Math]::Floor([Math]::Min($Control.Width, $Control.Height) / 2)
        )
    )
    $diameter = $safeRadius * 2
    $rect = [System.Drawing.Rectangle]::new(
        0,
        0,
        $Control.Width,
        $Control.Height
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    try {
        $path.AddArc($rect.Left, $rect.Top, $diameter, $diameter, 180, 90)
        $path.AddArc(($rect.Right - $diameter), $rect.Top, $diameter, $diameter, 270, 90)
        $path.AddArc(($rect.Right - $diameter), ($rect.Bottom - $diameter), $diameter, $diameter, 0, 90)
        $path.AddArc($rect.Left, ($rect.Bottom - $diameter), $diameter, $diameter, 90, 90)
        $path.CloseFigure()

        $oldRegion = $Control.Region
        $Control.Region = New-Object System.Drawing.Region($path)
        if ($null -ne $oldRegion) {
            $oldRegion.Dispose()
        }
    }
    finally {
        $path.Dispose()
    }
}

function Apply-ThemeToControl {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Control,
        [Parameter(Mandatory = $true)][string]$ThemeName
    )

    $palette = $script:ThemePalettes[$ThemeName]
    $isDark = ($ThemeName -eq 'dark')
    # dev5: true owner-drawn rounded controls. Return before the dev4
    # Region-based fallback and before the generic WinForms Button/Label branches.
    if ($Control -is [MugenDeejWindowing.MugenButton]) {
        $isPrimary = ([string]$Control.Tag -eq 'MugenPrimary')
        $radius = if ([string]$Control.Tag -eq 'MugenSection') { 7 } else { 8 }

        if ($isPrimary) {
            $Control.ApplyTheme(
                $palette.Accent,
                $palette.AccentText,
                $palette.Accent,
                $palette.AccentHover,
                $palette.AccentPressed,
                $palette.DisabledControl,
                $palette.DisabledText,
                $palette.Border,
                $palette.Accent,
                $radius
            )
        }
        else {
            $Control.ApplyTheme(
                $palette.Control,
                $palette.Text,
                $palette.Border,
                $palette.ControlHover,
                $palette.ControlPressed,
                $palette.DisabledControl,
                $palette.DisabledText,
                $palette.Border,
                $palette.Accent,
                $radius
            )
        }
        return
    }

    if ($Control -is [MugenDeejWindowing.MugenButtonTile]) {
        $Control.ApplyTheme(
            $palette.Control,
            $palette.Text,
            $palette.Border
        )
        return
    }

    # dev4 rounding hierarchy:
    # cards keep their existing largest radius;
    # normal buttons use 8 px;
    # section/diagnostic toggles use a slightly tighter 7 px.
    if ($Control -is [System.Windows.Forms.Button]) {
        $buttonRadius = 8
        if ([string]$Control.Tag -eq 'MugenSection') {
            $buttonRadius = 7
        }
        Set-RoundedControlRegion -Control $Control -Radius $buttonRadius
    }

    if ($Control -is [MugenDeejWindowing.MugenProgressBar]) {
        $Control.ApplyTheme($palette.ProgressTrack, $palette.Accent, $palette.Border)
    }
    elseif ($Control -is [MugenDeejWindowing.MugenComboBox]) {
        $Control.ApplyTheme(
            $palette.Input,
            $palette.Text,
            $palette.Border,
            $palette.Accent,
            $palette.DisabledText,
            $palette.DisabledControl
        )
    }
    elseif ($Control -is [MugenDeejWindowing.MugenCardPanel]) {
        $Control.BackColor = $palette.Surface
        $Control.ForeColor = $palette.Text
        $Control.BorderColor = $palette.Border
    }
    elseif ($Control -is [MugenDeejWindowing.MugenGroupBox]) {
        $Control.BackColor = $palette.SurfaceAlt
        $Control.ForeColor = $palette.Text
        $Control.BorderColor = $palette.Border
    }
    elseif ($Control -is [System.Windows.Forms.Form]) {
        $Control.BackColor = $palette.Window
        $Control.ForeColor = $palette.Text
    }
    elseif ($Control -is [System.Windows.Forms.GroupBox]) {
        $Control.BackColor = $palette.Window
        $Control.ForeColor = $palette.Text
    }
    elseif ($Control -is [System.Windows.Forms.Panel]) {
        if ([string]$Control.Tag -eq 'MugenCardInner') {
            $Control.BackColor = $palette.Surface
        }
        elseif ($Control.BorderStyle -ne [System.Windows.Forms.BorderStyle]::None) {
            $Control.BackColor = $palette.Surface
        }
        else {
            $Control.BackColor = $palette.Window
        }
        $Control.ForeColor = $palette.Text
    }
    elseif ($Control -is [System.Windows.Forms.Button]) {
        $isPrimary = ([string]$Control.Tag -eq 'MugenPrimary')
        $Control.UseVisualStyleBackColor = $false
        $Control.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $Control.FlatAppearance.BorderSize = 1

        if ($isPrimary) {
            $Control.ForeColor = $palette.AccentText
            $Control.BackColor = $palette.Accent
            $Control.FlatAppearance.BorderColor = $palette.Accent
            $Control.FlatAppearance.MouseOverBackColor = $palette.AccentHover
            $Control.FlatAppearance.MouseDownBackColor = $palette.AccentPressed
        }
        else {
            $Control.ForeColor = $palette.Text
            $Control.BackColor = $palette.Control
            $Control.FlatAppearance.BorderColor = $palette.Border
            $Control.FlatAppearance.MouseOverBackColor = $palette.ControlHover
            $Control.FlatAppearance.MouseDownBackColor = $palette.ControlPressed
        }
    }
    elseif ($Control -is [System.Windows.Forms.CheckBox]) {
        $Control.ForeColor = $palette.Text
        $Control.BackColor = [System.Drawing.Color]::Transparent
        $Control.UseVisualStyleBackColor = (-not $isDark)
        try { [MugenDeejWindowing.ThemeInterop]::SetDarkControlTheme($Control.Handle, $isDark, $false) } catch { }
    }
    elseif ($Control -is [System.Windows.Forms.RadioButton]) {
        $Control.ForeColor = $palette.Text
        $Control.BackColor = [System.Drawing.Color]::Transparent
        $Control.UseVisualStyleBackColor = (-not $isDark)
        try { [MugenDeejWindowing.ThemeInterop]::SetDarkControlTheme($Control.Handle, $isDark, $false) } catch { }
    }
    elseif ($Control -is [System.Windows.Forms.ComboBox]) {
        $Control.BackColor = $palette.Input
        $Control.ForeColor = $palette.Text
        $Control.FlatStyle = if ($isDark) { [System.Windows.Forms.FlatStyle]::Flat } else { [System.Windows.Forms.FlatStyle]::Standard }
        try { [MugenDeejWindowing.ThemeInterop]::SetDarkControlTheme($Control.Handle, $isDark, $true) } catch { }
    }
    elseif ($Control -is [System.Windows.Forms.TextBoxBase]) {
        $Control.BackColor = $palette.Input
        $Control.ForeColor = $palette.Text
    }
    elseif ($Control -is [System.Windows.Forms.ListView]) {
        $Control.BackColor = $palette.Surface
        $Control.ForeColor = $palette.Text
    }
    elseif ($Control -is [System.Windows.Forms.ListBox]) {
        $Control.BackColor = $palette.Surface
        $Control.ForeColor = $palette.Text
    }
    elseif ($Control -is [System.Windows.Forms.Label]) {
        if ($Control.Text -ne '●') {
            $Control.ForeColor = if (Test-IsMutedColor -Color $Control.ForeColor) { $palette.Muted } else { $palette.Text }
        }
        $Control.BackColor = [System.Drawing.Color]::Transparent
    }

    if (-not $Control.Enabled) {
        if ($Control -is [System.Windows.Forms.Button]) {
            $Control.ForeColor = $palette.DisabledText
            if ($isDark) {
                $Control.UseVisualStyleBackColor = $false
                $Control.BackColor = $palette.DisabledControl
                $Control.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
                $Control.FlatAppearance.BorderColor = $palette.Border
            }
        }
        elseif (
            $Control -is [System.Windows.Forms.ComboBox] -or
            $Control -is [System.Windows.Forms.TextBoxBase]
        ) {
            $Control.BackColor = $palette.DisabledControl
            $Control.ForeColor = $palette.DisabledText
        }
        elseif (
            $Control -is [System.Windows.Forms.Label] -or
            $Control -is [System.Windows.Forms.CheckBox] -or
            $Control -is [System.Windows.Forms.RadioButton]
        ) {
            if ($Control.Text -ne '●') {
                $Control.ForeColor = $palette.DisabledText
            }
        }
    }

    foreach ($child in $Control.Controls) {
        Apply-ThemeToControl -Control $child -ThemeName $ThemeName
    }
}

function Apply-ThemeToForm {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Form]$Form,
        [string]$ThemeName = ''
    )

    if ([string]::IsNullOrWhiteSpace($ThemeName)) { $ThemeName = Get-EffectiveTheme }
    Apply-ThemeToControl -Control $Form -ThemeName $ThemeName
    try {
        [MugenDeejWindowing.ThemeInterop]::SetDarkTitleBar($Form.Handle, ($ThemeName -eq 'dark'))
    }
    catch {
        Write-Log ("Failed to update title-bar theme for '{0}': {1}" -f $Form.Text, $_.Exception.Message) 'DEBUG'
    }
    $Form.Invalidate($true)
}

function Apply-ToolStripTheme {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.ToolStrip]$ToolStrip,
        [Parameter(Mandatory = $true)][string]$ThemeName
    )

    $palette = $script:ThemePalettes[$ThemeName]

    if ($ToolStrip -is [System.Windows.Forms.ContextMenuStrip]) {
        $ToolStrip.ShowImageMargin = $false
        $ToolStrip.ShowCheckMargin = $false
    }

    $ToolStrip.BackColor = $palette.Control
    $ToolStrip.ForeColor = $palette.Text
    $ToolStrip.RenderMode = [System.Windows.Forms.ToolStripRenderMode]::Professional
    $ToolStrip.Renderer = [MugenDeejWindowing.MugenToolStripRenderer]::new(
        $palette.Control,
        $palette.ControlHover,
        $palette.Text,
        $palette.Border
    )
    foreach ($item in $ToolStrip.Items) {
        $item.BackColor = $palette.Control
        $item.ForeColor = $palette.Text
    }
}

function Apply-CurrentTheme {
    $themeName = Get-EffectiveTheme
    foreach ($openForm in @([System.Windows.Forms.Application]::OpenForms)) {
        if ($null -ne $openForm -and -not $openForm.IsDisposed) {
            Apply-ThemeToForm -Form $openForm -ThemeName $themeName
        }
    }
    if ($null -ne $script:TrayMenu -and -not $script:TrayMenu.IsDisposed) {
        Apply-ToolStripTheme -ToolStrip $script:TrayMenu -ThemeName $themeName
    }
    if ($script:LastEffectiveTheme -ne $themeName) {
        Write-Log ("Effective interface theme changed: {0} -> {1}" -f $script:LastEffectiveTheme, $themeName) 'INFO'
    }
    $script:LastEffectiveTheme = $themeName
    return $themeName
}

function Sync-ThemeCombo {
    if ($null -eq $script:ThemeCombo -or $script:ThemeCombo.IsDisposed) { return }

    $script:UpdatingThemeCombo = $true
    try {
        $setting = Get-NormalizedThemeSetting -Value ([string]$script:Config.app.theme)
        $script:ThemeCombo.BeginUpdate()
        try {
            $script:ThemeCombo.Items.Clear()
            [void]$script:ThemeCombo.Items.Add((T -Key 'ThemeAuto'))
            [void]$script:ThemeCombo.Items.Add((T -Key 'ThemeLight'))
            [void]$script:ThemeCombo.Items.Add((T -Key 'ThemeDark'))
            $script:ThemeCombo.SelectedIndex = switch ($setting) {
                'light' { 1 }
                'dark' { 2 }
                default { 0 }
            }
        }
        finally {
            $script:ThemeCombo.EndUpdate()
        }
    }
    finally {
        $script:UpdatingThemeCombo = $false
    }
}

function Handle-ThemePreferenceChange {
    param([Parameter(Mandatory = $true)][string]$CategoryName)
    if ($script:Closing -or $script:ExitRequested) { return }
    if ((Get-NormalizedThemeSetting -Value ([string]$script:Config.app.theme)) -ne 'auto') { return }

    $newEffective = Get-EffectiveTheme
    if ($newEffective -eq $script:LastEffectiveTheme) { return }
    [void](Apply-CurrentTheme)
    Write-Log ("Windows preference change ({0}) updated Auto theme to {1}" -f $CategoryName, $newEffective) 'INFO'
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

    $activeGroup = New-Object MugenDeejWindowing.MugenGroupBox
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

    $otherGroup = New-Object MugenDeejWindowing.MugenGroupBox
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

    $refreshAppsButton = New-Object MugenDeejWindowing.MugenButton
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

    $addManualButton = New-Object MugenDeejWindowing.MugenButton
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

    $cancelButton = New-Object MugenDeejWindowing.MugenButton
    $cancelButton.Text = (T -Key 'Cancel')
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelButton.Location = New-Object System.Drawing.Point(635, 685)
    $cancelButton.Size = New-Object System.Drawing.Size(90, 34)
    $pickerForm.Controls.Add($cancelButton)

    $saveButton = New-Object MugenDeejWindowing.MugenButton
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
    Apply-ThemeToForm -Form $pickerForm
    $pickerForm.Add_Shown({ Ensure-FormVisible -Form $pickerForm -CenterIfOffscreen })
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
    # Leave enough vertical room for the five-row physical-slider editor plus
    # the expanded Advanced card and the action buttons without overlap.
    $settingsForm.ClientSize = New-Object System.Drawing.Size(1110, 775)
    $settingsForm.MinimumSize = New-Object System.Drawing.Size(1126, 814)
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
    # SOAK UX: configuration is transactional, while hardware position is live.
    $saveNotice = New-Object System.Windows.Forms.Label

    if ($script:Language -eq 'ru') {
        $saveNotice.Text = 'Важно: названия, режимы и назначенные приложения применяются только после нажатия «Сохранить». Положение физических регуляторов отображается сразу.'
    }
    else {
        $saveNotice.Text = 'Important: names, modes, and assigned applications are applied only after you click Save. Physical control positions are shown immediately.'
    }

    $saveNotice.Font = New-Object System.Drawing.Font(
        'Segoe UI Semibold',
        9.5
    )
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(
        230,
        170,
        70
    )
    $saveNotice.AutoSize = $false
    $saveNotice.Location = New-Object System.Drawing.Point(
        $hint.Left,
        ($hint.Bottom + 4)
    )
    $saveNotice.Size = New-Object System.Drawing.Size(
        ($settingsForm.ClientSize.Width - $hint.Left - 24),
        34
    )
    $saveNotice.TextAlign = 'MiddleLeft'
    $settingsForm.Controls.Add($saveNotice)

    $headers = @(
        @{ Text = (T -Key 'HeaderKnob'); X = 24; Width = 140 },
        @{ Text = (T -Key 'HeaderName'); X = 174; Width = 145 },
        @{ Text = (T -Key 'HeaderMode'); X = 326; Width = 185 },
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
        $rowPanel = New-Object MugenDeejWindowing.MugenCardPanel
        $rowPanel.Location = New-Object System.Drawing.Point(20, $y)
        $rowPanel.Size = New-Object System.Drawing.Size(1070, 66)
        $rowPanel.BackColor = [System.Drawing.Color]::White
        $rowPanel.BorderStyle = 'None'
        $settingsForm.Controls.Add($rowPanel)

        $position = if ($i -lt $positions.Count) { $positions[$i] } else { (T -Key 'PosNumber' -Args @($i + 1)) }
        $indexLabel = New-Object System.Windows.Forms.Label
        $indexLabel.Text = "$($i + 1) · $position"
        $indexLabel.Location = New-Object System.Drawing.Point(8, 9)
        $indexLabel.Size = New-Object System.Drawing.Size(142, 45)
        $indexLabel.TextAlign = 'MiddleLeft'
        $rowPanel.Controls.Add($indexLabel)

        $nameBox = New-Object System.Windows.Forms.TextBox
        $nameBox.Location = New-Object System.Drawing.Point(154, 17)
        $nameBox.Size = New-Object System.Drawing.Size(145, 30)
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

        $modeCombo = New-Object MugenDeejWindowing.MugenComboBox
        $modeCombo.DropDownStyle = 'DropDownList'
        $modeCombo.Location = New-Object System.Drawing.Point(306, 16)
        $modeCombo.Size = New-Object System.Drawing.Size(186, 30)
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

        $selectButton = New-Object MugenDeejWindowing.MugenButton
        $selectButton.Text = (T -Key 'SelectApplications')
        $selectButton.Location = New-Object System.Drawing.Point(722, 15)
        $selectButton.Size = New-Object System.Drawing.Size(180, 34)
        $selectButton.Tag = $i
        $rowPanel.Controls.Add($selectButton)
        [void]$selectButtons.Add($selectButton)

        $microphoneCombo = New-Object MugenDeejWindowing.MugenComboBox
        $microphoneCombo.DropDownStyle = 'DropDownList'
        $microphoneCombo.Location = New-Object System.Drawing.Point(502, 16)
        $microphoneCombo.Size = New-Object System.Drawing.Size(400, 30)
        $microphoneCombo.DropDownWidth = 520
        $microphoneCombo.Tag = $i
        Set-MicrophoneComboItems -Combo $microphoneCombo -SelectedId $selectedInputDeviceId -SelectedName $selectedInputDeviceName
        $microphoneCombo.Visible = $false
        $rowPanel.Controls.Add($microphoneCombo)
        [void]$microphoneCombos.Add($microphoneCombo)

        $progressBar = New-Object MugenDeejWindowing.MugenProgressBar
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

    # The analog editor only has a handful of advanced options. Keep them
    # permanently visible in a dedicated card instead of hiding them behind a
    # collapsible control. This avoids deferred WinForms layout/scope edge cases
    # and makes inversion/responsiveness discoverable on the real hardware UI.
    $sliderAdvancedPanel = New-Object MugenDeejWindowing.MugenCardPanel
    $sliderAdvancedPanel.Name = 'SliderAdvancedPanel'
    $sliderAdvancedPanel.Location = New-Object System.Drawing.Point(25, 540)
    $sliderAdvancedPanel.Size = New-Object System.Drawing.Size(1065, 112)
    $sliderAdvancedPanel.Visible = $true
    $settingsForm.Controls.Add($sliderAdvancedPanel)

    $advancedHeading = New-Object System.Windows.Forms.Label
    $advancedHeading.Text = ((T -Key 'AdvancedClosed') -replace '\s*[▼▲]\s*$', '')
    $advancedHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $advancedHeading.Location = New-Object System.Drawing.Point(14, 8)
    $advancedHeading.Size = New-Object System.Drawing.Size(240, 24)
    $sliderAdvancedPanel.Controls.Add($advancedHeading)

    $invertCheck = New-Object System.Windows.Forms.CheckBox
    $invertCheck.Name = 'SliderInvertAllCheck'
    $invertCheck.Text = (T -Key 'InvertAll')
    $invertCheck.AutoSize = $true
    $invertCheck.Checked = [bool]$script:Config.behavior.invertSliders
    $invertCheck.Location = New-Object System.Drawing.Point(14, 34)
    $sliderAdvancedPanel.Controls.Add($invertCheck)

    $responseLabel = New-Object System.Windows.Forms.Label
    $responseLabel.Text = (T -Key 'Responsiveness')
    $responseLabel.Location = New-Object System.Drawing.Point(14, 72)
    $responseLabel.Size = New-Object System.Drawing.Size(110, 25)
    $sliderAdvancedPanel.Controls.Add($responseLabel)

    $responseCombo = New-Object MugenDeejWindowing.MugenComboBox
    $responseCombo.Name = 'SliderResponseCombo'
    $responseCombo.DropDownStyle = 'DropDownList'
    $responseCombo.Location = New-Object System.Drawing.Point(125, 68)
    $responseCombo.Size = New-Object System.Drawing.Size(255, 30)
    [void]$responseCombo.Items.Add((T -Key 'ResponseFast'))
    [void]$responseCombo.Items.Add((T -Key 'ResponseBalanced'))
    [void]$responseCombo.Items.Add((T -Key 'ResponseSmooth'))
    $currentThreshold = [double]$script:Config.behavior.noiseThreshold
    if ($currentThreshold -le 0.004) { $responseCombo.SelectedIndex = 0 }
    elseif ($currentThreshold -le 0.009) { $responseCombo.SelectedIndex = 1 }
    else { $responseCombo.SelectedIndex = 2 }
    $sliderAdvancedPanel.Controls.Add($responseCombo)

    $responseHint = New-Object System.Windows.Forms.Label
    $responseHint.ForeColor = [System.Drawing.Color]::DimGray
    $responseHint.Location = New-Object System.Drawing.Point(395, 58)
    $responseHint.Size = New-Object System.Drawing.Size(410, 48)
    $sliderAdvancedPanel.Controls.Add($responseHint)

    $advancedConfigButton = New-Object MugenDeejWindowing.MugenButton
    $advancedConfigButton.Text = (T -Key 'OpenConfig')
    $advancedConfigButton.Location = New-Object System.Drawing.Point(850, 64)
    $advancedConfigButton.Size = New-Object System.Drawing.Size(190, 32)
    $sliderAdvancedPanel.Controls.Add($advancedConfigButton)

    $updateResponseHint = {
        switch ($responseCombo.SelectedIndex) {
            0 { $responseHint.Text = (T -Key 'FastHint') }
            1 { $responseHint.Text = (T -Key 'BalancedHint') }
            default { $responseHint.Text = (T -Key 'SmoothHint') }
        }
    }
    $responseCombo.Add_SelectedIndexChanged({ & $updateResponseHint })
    & $updateResponseHint

    $advancedConfigButton.Add_Click({ Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:ConfigPath) })

    $cancelButton = New-Object MugenDeejWindowing.MugenButton
    $cancelButton.Text = (T -Key 'Cancel')
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelButton.Location = New-Object System.Drawing.Point(870, 674)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 36)
    $settingsForm.Controls.Add($cancelButton)

    $saveButton = New-Object MugenDeejWindowing.MugenButton
    $saveButton.Text = (T -Key 'Save')
    $saveButton.Location = New-Object System.Drawing.Point(982, 674)
    $saveButton.Size = New-Object System.Drawing.Size(105, 36)
    $saveButton.Tag = 'MugenPrimary'
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
        param($sender, $eventArgs)

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

        # Resolve Advanced-settings values from the dialog's own controls for
        # the same reason as the collapsible panel: avoid ambiguous deferred
        # event-scope variable binding.
        $saveOwnerForm = $sender.FindForm()
        $invertMatches = @($saveOwnerForm.Controls.Find('SliderInvertAllCheck', $true))
        $responseMatches = @($saveOwnerForm.Controls.Find('SliderResponseCombo', $true))
        if ($invertMatches.Count -ne 1 -or $responseMatches.Count -ne 1) {
            throw (
                'Slider Advanced-settings controls could not be resolved: invert={0}; response={1}' -f
                $invertMatches.Count,
                $responseMatches.Count
            )
        }

        $script:Config.behavior.invertSliders = [bool]$invertMatches[0].Checked
        switch ($responseMatches[0].SelectedIndex) {
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

    # Make room for the Save/apply notice without depending on hardcoded row Y
    # coordinates. All existing top-level controls below the original hint move
    # down together; the form grows by the same amount.
    $saveNoticeShift = 38
    $originalHintBottom = $hint.Bottom

    foreach ($control in @($settingsForm.Controls)) {
        if (
            $control -ne $saveNotice -and
            $control -ne $hint -and
            $control.Top -gt $originalHintBottom
        ) {
            $control.Top = $control.Top + $saveNoticeShift
        }
    }

    $settingsForm.ClientSize = New-Object System.Drawing.Size(
        $settingsForm.ClientSize.Width,
        ($settingsForm.ClientSize.Height + $saveNoticeShift)
    )

    if (
        $settingsForm.MinimumSize.Width -gt 0 -and
        $settingsForm.MinimumSize.Height -gt 0
    ) {
        $settingsForm.MinimumSize = New-Object System.Drawing.Size(
            $settingsForm.MinimumSize.Width,
            ($settingsForm.MinimumSize.Height + $saveNoticeShift)
        )
    }
    Apply-ThemeToForm -Form $settingsForm

    # Theme application recolors generic labels; restore semantic amber.
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(
        230,
        170,
        70
    )
    $settingsForm.Add_Shown({ Ensure-FormVisible -Form $settingsForm -CenterIfOffscreen })
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

        $bar = New-Object MugenDeejWindowing.MugenProgressBar
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

    $laterButton = New-Object MugenDeejWindowing.MugenButton
    $laterButton.Text = (T -Key 'CloseHint')
    $laterButton.Location = New-Object System.Drawing.Point(305, 452)
    $laterButton.Size = New-Object System.Drawing.Size(155, 36)
    $wizard.Controls.Add($laterButton)

    $configureButton = New-Object MugenDeejWindowing.MugenButton
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
    Apply-ThemeToForm -Form $wizard
    $wizard.Add_Shown({ Ensure-FormVisible -Form $wizard -CenterIfOffscreen })
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

function Get-ExceptionDiagnosticText {
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    $parts = New-Object 'System.Collections.Generic.List[string]'
    $exception = $ErrorRecord.Exception
    $depth = 0

    while ($null -ne $exception -and $depth -lt 8) {
        $typeName = $exception.GetType().FullName
        $hResultHex = '0x' + (([System.Convert]::ToString([int]$exception.HResult, 16).PadLeft(8, '0')).ToUpperInvariant())
        $message = ([string]$exception.Message) -replace '[\r\n]+', ' '
        $nativeText = ''

        if ($exception -is [System.ComponentModel.Win32Exception]) {
            $nativeText = '; nativeErrorCode=' + [string]$exception.NativeErrorCode
        }

        [void]$parts.Add(("type={0}; hresult={1}{2}; message={3}" -f $typeName, $hResultHex, $nativeText, $message))
        $exception = $exception.InnerException
        $depth++
    }

    if ($parts.Count -eq 0) { return 'no exception details available' }
    return ($parts -join ' -> inner: ')
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

function Get-ControllerPacketSignature {
    param([Parameter(Mandatory = $true)]$Packet)
    return ('{0}:{1}:{2}' -f [string]$Packet.Protocol, @($Packet.Sliders).Count, @($Packet.Buttons).Count)
}

function Test-ControllerProtocolLine {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

    $parts = @($Line.Trim() -split '\|')
    if ($parts.Count -lt 1 -or $parts.Count -gt 64) { return $null }

    # Classic deej protocol: raw numeric values only.
    $legacyValues = New-Object 'System.Collections.Generic.List[int]'
    $legacy = $true
    foreach ($part in $parts) {
        $value = 0
        if (-not [int]::TryParse($part, [ref]$value) -or $value -lt 0 -or $value -gt 1023) {
            $legacy = $false
            break
        }
        $legacyValues.Add($value)
    }

    if ($legacy -and $legacyValues.Count -gt 0) {
        return [pscustomobject]@{
            Protocol = 'legacy'
            Sliders = @($legacyValues.ToArray())
            Buttons = @()
        }
    }

    # Extended s/b protocol used by Miodec-style button sketches and the
    # Mugen reference sketch. Slider and button counts are discovered from
    # the packet itself.
    $sliders = New-Object 'System.Collections.Generic.List[int]'
    $buttons = New-Object 'System.Collections.Generic.List[int]'

    foreach ($part in $parts) {
        $match = [regex]::Match($part, '^(?<kind>[sSbB])(?<value>\d{1,4})$')
        if (-not $match.Success) { return $null }

        $kind = $match.Groups['kind'].Value.ToLowerInvariant()
        $value = 0
        if (-not [int]::TryParse($match.Groups['value'].Value, [ref]$value)) { return $null }

        if ($kind -eq 's') {
            if ($value -lt 0 -or $value -gt 1023) { return $null }
            $sliders.Add($value)
        }
        elseif ($kind -eq 'b') {
            if ($value -ne 0 -and $value -ne 1) { return $null }
            $buttons.Add($value)
        }
        else {
            return $null
        }
    }

    if ($sliders.Count -lt 1) { return $null }

    return [pscustomobject]@{
        Protocol = 'extended'
        Sliders = @($sliders.ToArray())
        Buttons = @($buttons.ToArray())
    }
}

function Get-ControllerConnectedStatusText {
    param([Parameter(Mandatory = $true)][string]$PortName)

    $sliderCount = [int]$script:DetectedSliderCount
    $buttonCount = [int]$script:DetectedButtonCount

    if ($sliderCount -le 0) {
        $sliderCount = [int]$script:Config.connection.expectedSliders
    }

    if ($script:Language -eq 'ru') {
        if ($buttonCount -gt 0) {
            return ('Контроллер подключён — {0} · {1} регуляторов · {2} кнопок' -f $PortName, $sliderCount, $buttonCount)
        }
        return ('Контроллер подключён — {0} · {1} регуляторов' -f $PortName, $sliderCount)
    }

    if ($buttonCount -gt 0) {
        return ('Controller connected — {0} · {1} controls · {2} buttons' -f $PortName, $sliderCount, $buttonCount)
    }
    return ('Controller connected — {0} · {1} controls' -f $PortName, $sliderCount)
}

function Set-DetectedControllerCapabilities {
    param(
        [Parameter(Mandatory = $true)]$Packet,
        [string]$PortName = ''
    )

    $protocol = [string]$Packet.Protocol
    $sliderCount = @($Packet.Sliders).Count
    $buttonCount = @($Packet.Buttons).Count

    $changed = (
        $script:ControllerProtocol -ne $protocol -or
        $script:DetectedSliderCount -ne $sliderCount -or
        $script:DetectedButtonCount -ne $buttonCount
    )

    $script:ControllerProtocol = $protocol
    $script:DetectedSliderCount = $sliderCount
    $script:DetectedButtonCount = $buttonCount
    $script:SoftMutedSliders = @{}
    $script:LastButtonActionAt = @{}
    if ($buttonCount -gt 0) {
        Normalize-ButtonActions -Count $buttonCount
    }
    Update-ButtonFeatureUi

    if ($changed) {
        Write-Log (
            'Controller capabilities detected: port={0}; protocol={1}; sliders={2}; buttons={3}' -f
            $PortName, $protocol, $sliderCount, $buttonCount
        ) 'INFO'
    }
}

function Initialize-ButtonStates {
    param([int[]]$Values)

    $script:LatestButtons = @($Values)
    $script:LastButtonStates = @($Values)

    if (@($Values).Count -gt 0) {
        Write-Log ('Button states initialized: {0}' -f (@($Values) -join ',')) 'DEBUG'
    }
}

function Update-ButtonStates {
    param([int[]]$Values)

    $valuesArray = @($Values)
    $script:LatestButtons = $valuesArray

    if ($valuesArray.Count -eq 0) {
        $script:LastButtonStates = @()
        return
    }

    if (@($script:LastButtonStates).Count -ne $valuesArray.Count) {
        Initialize-ButtonStates -Values $valuesArray
        return
    }

    for ($i = 0; $i -lt $valuesArray.Count; $i++) {
        $newValue = [int]$valuesArray[$i]
        $oldValue = [int]$script:LastButtonStates[$i]
        if ($newValue -eq $oldValue) { continue }

        $script:LastButtonStates[$i] = $newValue
        $state = if ($newValue -eq 0) { 'pressed' } else { 'released' }
        Write-Log ('Button {0} {1} (raw={2})' -f ($i + 1), $state, $newValue) 'INFO'
        if ($newValue -eq 0) {
            Invoke-ButtonAction -ButtonIndex $i
        }
    }
}

function Get-ButtonFeatureText {
    param([Parameter(Mandatory = $true)][string]$Key)

    $ru = ($script:Language -eq 'ru')

    switch ($Key) {
        'MainButton' {
            if ($ru) { return 'Настроить кнопки' }
            else { return 'Configure buttons' }
        }

        'Title' {
            if ($ru) { return 'Настройка кнопок — Mugen Deej' }
            else { return 'Button settings — Mugen Deej' }
        }

        'Heading' {
            if ($ru) { return 'Действия физических кнопок' }
            else { return 'Physical button actions' }
        }

        'Hint' {
            if ($ru) {
                return 'Назначьте каждой физической кнопке действие. Доступны действия регуляторов, медиакоманды, системная громкость Windows и собственные горячие клавиши. Действие выполняется один раз при нажатии.'
            }
            else {
                return 'Assign an action to each physical button. Available actions include control mute, media commands, Windows system volume, and custom hotkeys. Each action fires once per press.'
            }
        }

        'ButtonN' {
            if ($ru) { return 'Кнопка' }
            else { return 'Button' }
        }

        'ButtonStatus' {
            if ($ru) { return 'Состояние кнопок' }
            else { return 'Button status' }
        }

        'None' {
            if ($ru) { return 'Не использовать' }
            else { return 'Do nothing' }
        }

        'MuteControl' {
            if ($ru) { return 'Регулятор: отключить / включить звук' }
            else { return 'Control: mute / unmute' }
        }

        'PlayPause' {
            if ($ru) { return 'Медиа: воспроизведение / пауза' }
            else { return 'Media: play / pause' }
        }

        'PreviousTrack' {
            if ($ru) { return 'Медиа: предыдущий трек' }
            else { return 'Media: previous track' }
        }

        'NextTrack' {
            if ($ru) { return 'Медиа: следующий трек' }
            else { return 'Media: next track' }
        }

        'StopPlayback' {
            if ($ru) { return 'Медиа: стоп (полная остановка)' }
            else { return 'Media: stop playback' }
        }

        'VolumeUp' {
            if ($ru) { return 'Windows: сделать громче' }
            else { return 'Windows: volume up' }
        }

        'VolumeDown' {
            if ($ru) { return 'Windows: сделать тише' }
            else { return 'Windows: volume down' }
        }

        'VolumeMute' {
            if ($ru) { return 'Windows: отключить / включить системный звук' }
            else { return 'Windows: mute / unmute system volume' }
        }

        'HotkeyConfigure' {
            if ($ru) { return 'Горячая клавиша…' }
            else { return 'Hotkey…' }
        }

        'HotkeyPrefix' {
            if ($ru) { return 'Горячая клавиша: ' }
            else { return 'Hotkey: ' }
        }

        'HotkeyTitle' {
            if ($ru) { return 'Горячая клавиша — Mugen Deej' }
            else { return 'Hotkey — Mugen Deej' }
        }

        'HotkeyHeading' {
            if ($ru) { return 'Настройка горячей клавиши' }
            else { return 'Configure hotkey' }
        }

        'HotkeyHint' {
            if ($ru) {
                return 'Выберите модификаторы и клавишу. F13–F24 особенно удобны для OBS и других программ: они редко заняты обычной клавиатурой.'
            }
            else {
                return 'Choose modifiers and a key. F13–F24 are especially useful for OBS and similar apps because normal keyboards rarely use them.'
            }
        }

        'HotkeyKey' {
            if ($ru) { return 'Клавиша:' }
            else { return 'Key:' }
        }

        'Muted' {
            if ($ru) { return 'БЕЗ ЗВУКА' }
            else { return 'MUTED' }
        }

        'Save' {
            if ($ru) { return 'Сохранить' }
            else { return 'Save' }
        }

        'Cancel' {
            if ($ru) { return 'Отмена' }
            else { return 'Cancel' }
        }

        'NoButtons' {
            if ($ru) { return 'Подключённый контроллер не сообщает о кнопках.' }
            else { return 'The connected controller does not report any buttons.' }
        }

        default {
            return $Key
        }
    }
}

function Get-HotkeyKeyName {
    param(
        [Parameter(Mandatory = $true)]
        [int]$KeyCode
    )

    if ($KeyCode -ge 65 -and $KeyCode -le 90) {
        return [char]$KeyCode
    }

    if ($KeyCode -ge 48 -and $KeyCode -le 57) {
        return [char]$KeyCode
    }

    if ($KeyCode -ge 112 -and $KeyCode -le 135) {
        return ('F' + ($KeyCode - 111))
    }

    if ($KeyCode -ge 96 -and $KeyCode -le 105) {
        return ('Num ' + ($KeyCode - 96))
    }

    switch ($KeyCode) {
        8   { return 'Backspace' }
        9   { return 'Tab' }
        13  { return 'Enter' }
        19  { return 'Pause' }
        27  { return 'Esc' }
        32  { return 'Space' }
        33  { return 'Page Up' }
        34  { return 'Page Down' }
        35  { return 'End' }
        36  { return 'Home' }
        37  { return 'Left' }
        38  { return 'Up' }
        39  { return 'Right' }
        40  { return 'Down' }
        44  { return 'Print Screen' }
        45  { return 'Insert' }
        46  { return 'Delete' }
        106 { return 'Num *' }
        107 { return 'Num +' }
        109 { return 'Num -' }
        110 { return 'Num .' }
        111 { return 'Num /' }
        186 { return ';' }
        187 { return '=' }
        188 { return ',' }
        189 { return '-' }
        190 { return '.' }
        191 { return '/' }
        192 { return '`' }
        219 { return '[' }
        220 { return '\' }
        221 { return ']' }
        222 { return '''' }
        default { return ('VK ' + $KeyCode) }
    }
}

function Get-HotkeyActionDisplay {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action
    )

    if ($Action -notmatch '^hotkey:(\d{1,3}):(\d{1,2})$') {
        return (Get-ButtonFeatureText -Key 'HotkeyConfigure')
    }

    $keyCode = [int]$Matches[1]
    $mask = [int]$Matches[2]
    $parts = @()

    if (($mask -band 1) -ne 0) { $parts += 'Ctrl' }
    if (($mask -band 2) -ne 0) { $parts += 'Shift' }
    if (($mask -band 4) -ne 0) { $parts += 'Alt' }
    if (($mask -band 8) -ne 0) { $parts += 'Win' }

    $parts += (Get-HotkeyKeyName -KeyCode $keyCode)

    return (
        (Get-ButtonFeatureText -Key 'HotkeyPrefix') +
        ($parts -join ' + ')
    )
}

function Get-HotkeyChoiceTable {
    $labels = @()
    $codes = @()

    foreach ($code in 65..90) {
        $labels += [string][char]$code
        $codes += $code
    }

    foreach ($code in 48..57) {
        $labels += [string][char]$code
        $codes += $code
    }

    foreach ($number in 1..24) {
        $labels += ('F' + $number)
        $codes += (111 + $number)
    }

    $special = @(
        @(32, 'Space'),
        @(13, 'Enter'),
        @(9, 'Tab'),
        @(8, 'Backspace'),
        @(27, 'Esc'),
        @(45, 'Insert'),
        @(46, 'Delete'),
        @(36, 'Home'),
        @(35, 'End'),
        @(33, 'Page Up'),
        @(34, 'Page Down'),
        @(37, 'Left'),
        @(38, 'Up'),
        @(39, 'Right'),
        @(40, 'Down'),
        @(44, 'Print Screen'),
        @(19, 'Pause'),
        @(186, ';'),
        @(187, '='),
        @(188, ','),
        @(189, '-'),
        @(190, '.'),
        @(191, '/'),
        @(192, '`'),
        @(219, '['),
        @(220, '\'),
        @(221, ']'),
        @(222, '''')
    )

    foreach ($item in $special) {
        $codes += [int]$item[0]
        $labels += [string]$item[1]
    }

    foreach ($number in 0..9) {
        $labels += ('Num ' + $number)
        $codes += (96 + $number)
    }

    foreach ($item in @(
        @(106, 'Num *'),
        @(107, 'Num +'),
        @(109, 'Num -'),
        @(110, 'Num .'),
        @(111, 'Num /')
    )) {
        $codes += [int]$item[0]
        $labels += [string]$item[1]
    }

    return [pscustomobject]@{
        Labels = @($labels)
        Codes = @($codes)
    }
}

function Show-HotkeyEditor {
    param(
        [string]$ExistingAction = ''
    )

    $script:HotkeyEditorResult = $null

    $editor = New-Object System.Windows.Forms.Form
    $editor.Text = Get-ButtonFeatureText -Key 'HotkeyTitle'
    $editor.StartPosition = 'CenterParent'
    $editor.ClientSize = [System.Drawing.Size]::new(590, 435)
    $editor.MinimumSize = [System.Drawing.Size]::new(606, 474)
    $editor.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $editor.FormBorderStyle = 'FixedDialog'
    $editor.MaximizeBox = $false
    $editor.MinimizeBox = $false
    $editor.KeyPreview = $true

    Set-FormAppIcon -Form $editor

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-ButtonFeatureText -Key 'HotkeyHeading'
    $heading.Font = New-Object System.Drawing.Font(
        'Segoe UI Semibold',
        15
    )
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $editor.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    if ($script:Language -eq 'ru') {
        $hint.Text = 'Можно выбрать сочетание вручную или нажать кнопку захвата и затем нужное сочетание на обычной клавиатуре. F13–F24 особенно удобны для OBS и других программ.'
    }
    else {
        $hint.Text = 'Choose a shortcut manually, or start capture and press the desired combination on your keyboard. F13–F24 are especially useful for OBS and similar apps.'
    }
    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(540, 62)
    $editor.Controls.Add($hint)

    $ctrlCheck = New-Object System.Windows.Forms.CheckBox
    $ctrlCheck.Text = 'Ctrl'
    $ctrlCheck.Location = [System.Drawing.Point]::new(28, 128)
    $ctrlCheck.Size = [System.Drawing.Size]::new(82, 28)
    $editor.Controls.Add($ctrlCheck)

    $shiftCheck = New-Object System.Windows.Forms.CheckBox
    $shiftCheck.Text = 'Shift'
    $shiftCheck.Location = [System.Drawing.Point]::new(116, 128)
    $shiftCheck.Size = [System.Drawing.Size]::new(82, 28)
    $editor.Controls.Add($shiftCheck)

    $altCheck = New-Object System.Windows.Forms.CheckBox
    $altCheck.Text = 'Alt'
    $altCheck.Location = [System.Drawing.Point]::new(204, 128)
    $altCheck.Size = [System.Drawing.Size]::new(82, 28)
    $editor.Controls.Add($altCheck)

    $winCheck = New-Object System.Windows.Forms.CheckBox
    $winCheck.Text = 'Win'
    $winCheck.Location = [System.Drawing.Point]::new(292, 128)
    $winCheck.Size = [System.Drawing.Size]::new(82, 28)
    $editor.Controls.Add($winCheck)

    $keyLabel = New-Object System.Windows.Forms.Label
    $keyLabel.Text = Get-ButtonFeatureText -Key 'HotkeyKey'
    $keyLabel.Location = [System.Drawing.Point]::new(28, 177)
    $keyLabel.Size = [System.Drawing.Size]::new(90, 28)
    $editor.Controls.Add($keyLabel)

    $keyCombo = New-Object MugenDeejWindowing.MugenComboBox
    $keyCombo.DropDownStyle = 'DropDownList'
    $keyCombo.Location = [System.Drawing.Point]::new(122, 174)
    $keyCombo.Size = [System.Drawing.Size]::new(250, 30)

    $choices = Get-HotkeyChoiceTable

    foreach ($label in $choices.Labels) {
        [void]$keyCombo.Items.Add([string]$label)
    }

    $existingKey = 124
    $existingMask = 0

    if ($ExistingAction -match '^hotkey:(\d{1,3}):(\d{1,2})$') {
        $existingKey = [int]$Matches[1]
        $existingMask = [int]$Matches[2]
    }

    $ctrlCheck.Checked = (($existingMask -band 1) -ne 0)
    $shiftCheck.Checked = (($existingMask -band 2) -ne 0)
    $altCheck.Checked = (($existingMask -band 4) -ne 0)
    $winCheck.Checked = (($existingMask -band 8) -ne 0)

    $selectedKeyIndex = [array]::IndexOf(
        [object[]]$choices.Codes,
        [object]$existingKey
    )

    if ($selectedKeyIndex -lt 0) {
        $selectedKeyIndex = [array]::IndexOf(
            [object[]]$choices.Codes,
            [object]124
        )
    }

    if ($selectedKeyIndex -lt 0) {
        $selectedKeyIndex = 0
    }

    $keyCombo.SelectedIndex = $selectedKeyIndex
    $editor.Controls.Add($keyCombo)

    $captureButton = New-Object MugenDeejWindowing.MugenButton
    if ($script:Language -eq 'ru') {
        $captureButton.Text = 'Нажать сочетание…'
    }
    else {
        $captureButton.Text = 'Press shortcut…'
    }
    $captureButton.Location = [System.Drawing.Point]::new(386, 172)
    $captureButton.Size = [System.Drawing.Size]::new(175, 34)
    $editor.Controls.Add($captureButton)

    $preview = New-Object System.Windows.Forms.Label
    $preview.Location = [System.Drawing.Point]::new(28, 224)
    $preview.Size = [System.Drawing.Size]::new(530, 30)
    $preview.Font = New-Object System.Drawing.Font(
        'Segoe UI Semibold',
        11
    )
    $editor.Controls.Add($preview)

    $captureStatus = New-Object System.Windows.Forms.Label
    $captureStatus.Location = [System.Drawing.Point]::new(28, 257)
    $captureStatus.Size = [System.Drawing.Size]::new(530, 34)
    $editor.Controls.Add($captureStatus)

    $systemHotkeyWarning = New-Object System.Windows.Forms.Label
    if ($script:Language -eq 'ru') {
        $systemHotkeyWarning.Text = 'Некоторые сочетания — особенно с Win / Alt — зарезервированы Windows или активным приложением. Они могут сработать во время записи или не дойти до нужной программы.'
    }
    else {
        $systemHotkeyWarning.Text = 'Some shortcuts — especially Win / Alt combinations — are reserved by Windows or the active app. They may trigger while recording or never reach the target app.'
    }
    $systemHotkeyWarning.Location = [System.Drawing.Point]::new(28, 300)
    $systemHotkeyWarning.Size = [System.Drawing.Size]::new(530, 58)
    $editor.Controls.Add($systemHotkeyWarning)

    $captureState = [pscustomobject]@{
        Armed = $false
    }

    $updatePreview = {
        if ($keyCombo.SelectedIndex -lt 0) {
            $preview.Text = ''
            return
        }

        $mask = 0

        if ($ctrlCheck.Checked) { $mask = $mask -bor 1 }
        if ($shiftCheck.Checked) { $mask = $mask -bor 2 }
        if ($altCheck.Checked) { $mask = $mask -bor 4 }
        if ($winCheck.Checked) { $mask = $mask -bor 8 }

        $keyCode = [int]$choices.Codes[$keyCombo.SelectedIndex]

        $preview.Text = Get-HotkeyActionDisplay -Action (
            'hotkey:' +
            $keyCode +
            ':' +
            $mask
        )
    }

    $setCaptureText = {
        if ($captureState.Armed) {
            if ($script:Language -eq 'ru') {
                $captureButton.Text = 'Ожидаю…'
                $captureStatus.Text = 'Нажмите нужную клавишу или сочетание на клавиатуре.'
                $captureStatus.ForeColor = [System.Drawing.Color]::FromArgb(48, 190, 108)
            }
            else {
                $captureButton.Text = 'Waiting…'
                $captureStatus.Text = 'Press the desired key or shortcut on your keyboard.'
                $captureStatus.ForeColor = [System.Drawing.Color]::FromArgb(48, 190, 108)
            }
        }
        else {
            if ($script:Language -eq 'ru') {
                $captureButton.Text = 'Нажать сочетание…'
            }
            else {
                $captureButton.Text = 'Press shortcut…'
            }

            $captureStatus.Text = ''
        }
    }

    $captureButton.Add_Click({
        if ($captureState.Armed) {
            $captureState.Armed = $false
            & $setCaptureText
            $captureButton.Refresh()
            $captureStatus.Refresh()
            return
        }

        $captureState.Armed = $true
        & $setCaptureText
        $captureButton.Refresh()
        $captureStatus.Refresh()

        $editor.Activate()
        $editor.Focus()
    })

    $editor.Add_KeyDown({
        param($sender, $eventArgs)

        if (-not $captureState.Armed) {
            return
        }

        $keyCode = [int]$eventArgs.KeyCode

        # Ignore pure modifier presses and wait for the actual key.
        if ($keyCode -in @(16, 17, 18, 91, 92)) {
            $eventArgs.Handled = $true
            $eventArgs.SuppressKeyPress = $true
            return
        }

        # Leave capture mode immediately, before changing checkboxes or the
        # ComboBox. Those control changes can trigger more WinForms events and
        # repaint work; keeping Armed=true until the end made "Ожидаю..." linger
        # visually even though the shortcut had already been captured.
        $captureState.Armed = $false
        & $setCaptureText
        $captureButton.Refresh()
        $captureStatus.Refresh()
        [System.Windows.Forms.Application]::DoEvents()

        $mask = 0

        if ($eventArgs.Control) { $mask = $mask -bor 1 }
        if ($eventArgs.Shift)   { $mask = $mask -bor 2 }
        if ($eventArgs.Alt)     { $mask = $mask -bor 4 }

        if ([MugenDeejWindowing.MugenHotkeys]::IsWindowsKeyDown()) {
            $mask = $mask -bor 8
        }

        $ctrlCheck.Checked = (($mask -band 1) -ne 0)
        $shiftCheck.Checked = (($mask -band 2) -ne 0)
        $altCheck.Checked = (($mask -band 4) -ne 0)
        $winCheck.Checked = (($mask -band 8) -ne 0)

        $foundIndex = -1

        for ($i = 0; $i -lt @($choices.Codes).Count; $i++) {
            if ([int]$choices.Codes[$i] -eq $keyCode) {
                $foundIndex = $i
                break
            }
        }

        if ($foundIndex -lt 0) {
            $choices.Codes = @($choices.Codes) + $keyCode
            $choices.Labels = @($choices.Labels) + (
                Get-HotkeyKeyName -KeyCode $keyCode
            )

            [void]$keyCombo.Items.Add(
                (Get-HotkeyKeyName -KeyCode $keyCode)
            )

            $foundIndex = $keyCombo.Items.Count - 1
        }

        $keyCombo.SelectedIndex = $foundIndex

        & $updatePreview

        $eventArgs.Handled = $true
        $eventArgs.SuppressKeyPress = $true
    })

    $ctrlCheck.Add_CheckedChanged($updatePreview)
    $shiftCheck.Add_CheckedChanged($updatePreview)
    $altCheck.Add_CheckedChanged($updatePreview)
    $winCheck.Add_CheckedChanged($updatePreview)
    $keyCombo.Add_SelectedIndexChanged($updatePreview)

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(364, 383)
    $cancel.Size = [System.Drawing.Size]::new(95, 36)
    $editor.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(470, 383)
    $save.Size = [System.Drawing.Size]::new(95, 36)
    $editor.Controls.Add($save)

    $save.Add_Click({
        if ($keyCombo.SelectedIndex -lt 0) {
            return
        }

        $mask = 0

        if ($ctrlCheck.Checked) { $mask = $mask -bor 1 }
        if ($shiftCheck.Checked) { $mask = $mask -bor 2 }
        if ($altCheck.Checked) { $mask = $mask -bor 4 }
        if ($winCheck.Checked) { $mask = $mask -bor 8 }

        $keyCode = [int]$choices.Codes[$keyCombo.SelectedIndex]

        $script:HotkeyEditorResult = (
            'hotkey:' +
            $keyCode +
            ':' +
            $mask
        )

        $editor.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $editor.Close()
    })

    Apply-ThemeToForm -Form $editor
    $systemHotkeyWarning.ForeColor = [System.Drawing.Color]::FromArgb(215, 160, 62)

    & $updatePreview
    & $setCaptureText

    $editor.Add_Shown({
        Ensure-FormVisible -Form $editor -CenterIfOffscreen
    })

    $editor.AcceptButton = $save
    $editor.CancelButton = $cancel

    [void]$editor.ShowDialog($form)
    $editor.Dispose()

    return $script:HotkeyEditorResult
}
function Encode-ButtonActionPayload {
    param([Parameter(Mandatory = $true)][string]$Text)

    return [Convert]::ToBase64String(
        [System.Text.Encoding]::UTF8.GetBytes($Text)
    )
}

function Decode-ButtonActionPayload {
    param([Parameter(Mandatory = $true)][string]$Payload)

    try {
        return [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($Payload)
        )
    }
    catch {
        return ''
    }
}

function Get-LaunchActionDisplay {
    param([Parameter(Mandatory = $true)][string]$Action)

    if ($Action -match '^launch64:(.+)$') {
        $target = Decode-ButtonActionPayload -Payload $Matches[1]

        if (-not [string]::IsNullOrWhiteSpace($target)) {
            $name = [System.IO.Path]::GetFileName($target)

            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = $target
            }

            if ($script:Language -eq 'ru') {
                return ('Запустить: ' + $name)
            }

            return ('Launch: ' + $name)
        }
    }

    if ($script:Language -eq 'ru') {
        return 'Запустить программу / файл…'
    }

    return 'Launch program / file…'
}

function Get-UrlActionDisplay {
    param([Parameter(Mandatory = $true)][string]$Action)

    if ($Action -match '^url64:(.+)$') {
        $url = Decode-ButtonActionPayload -Payload $Matches[1]

        if (-not [string]::IsNullOrWhiteSpace($url)) {
            $display = $url

            try {
                $uri = [Uri]$url

                if (-not [string]::IsNullOrWhiteSpace($uri.Host)) {
                    $display = $uri.Host
                }
            }
            catch {}

            if ($script:Language -eq 'ru') {
                return ('Открыть URL: ' + $display)
            }

            return ('Open URL: ' + $display)
        }
    }

    if ($script:Language -eq 'ru') {
        return 'Открыть URL…'
    }

    return 'Open URL…'
}

function Invoke-WithWindowsUICulture {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    $thread = [System.Threading.Thread]::CurrentThread
    $oldUiCulture = $thread.CurrentUICulture
    $oldCulture = $thread.CurrentCulture

    try {
        $windowsCulture = [System.Globalization.CultureInfo]::InstalledUICulture

        if ($null -ne $windowsCulture) {
            $thread.CurrentUICulture = $windowsCulture
            $thread.CurrentCulture = $windowsCulture
        }

        return (& $Action)
    }
    finally {
        $thread.CurrentUICulture = $oldUiCulture
        $thread.CurrentCulture = $oldCulture
    }
}
function Select-LaunchTargetAction {
    param(
        [string]$ExistingAction = ''
    )

    $existingTarget = ''

    if ($ExistingAction -match '^launch64:(.+)$') {
        $existingTarget = Decode-ButtonActionPayload -Payload $Matches[1]
    }

    return (
        Invoke-WithWindowsUICulture -Action {
            $dialog = New-Object System.Windows.Forms.OpenFileDialog

            try {
                $dialog.AutoUpgradeEnabled = $true
                $dialog.CheckFileExists = $true
                $dialog.Multiselect = $false
                $dialog.RestoreDirectory = $true

                if ($script:Language -eq 'ru') {
                    $dialog.Title = 'Выберите программу или файл'
                    $dialog.Filter = 'Все файлы (*.*)|*.*'
                }
                else {
                    $dialog.Title = 'Select a program or file'
                    $dialog.Filter = 'All files (*.*)|*.*'
                }

                if (
                    -not [string]::IsNullOrWhiteSpace($existingTarget) -and
                    (Test-Path -LiteralPath $existingTarget -PathType Leaf)
                ) {
                    try {
                        $dialog.InitialDirectory = Split-Path -Parent $existingTarget
                        $dialog.FileName = [System.IO.Path]::GetFileName(
                            $existingTarget
                        )
                    }
                    catch {}
                }

                $dialogResult = $dialog.ShowDialog($form)

                if (
                    $dialogResult -ne
                    [System.Windows.Forms.DialogResult]::OK
                ) {
                    return $null
                }

                $target = [string]$dialog.FileName

                if ([string]::IsNullOrWhiteSpace($target)) {
                    return $null
                }

                return (
                    'launch64:' +
                    (Encode-ButtonActionPayload -Text $target)
                )
            }
            finally {
                $dialog.Dispose()
            }
        }
    )
}
function Get-FolderActionDisplay {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action
    )

    if ($Action -match '^folder64:(.+)$') {
        $target = Decode-ButtonActionPayload -Payload $Matches[1]

        if (-not [string]::IsNullOrWhiteSpace($target)) {
            $trimmed = $target.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            )

            $name = [System.IO.Path]::GetFileName($trimmed)

            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = $target
            }

            if ($script:Language -eq 'ru') {
                return ('Открыть папку: ' + $name)
            }

            return ('Open folder: ' + $name)
        }
    }

    if ($script:Language -eq 'ru') {
        return 'Открыть папку…'
    }

    return 'Open folder…'
}

function Select-FolderTargetAction {
    param(
        [string]$ExistingAction = ''
    )

    $existingTarget = ''

    if ($ExistingAction -match '^folder64:(.+)$') {
        $existingTarget = Decode-ButtonActionPayload -Payload $Matches[1]

        if (
            [string]::IsNullOrWhiteSpace($existingTarget) -or
            -not (Test-Path -LiteralPath $existingTarget -PathType Container)
        ) {
            $existingTarget = ''
        }
    }

    $title = if ($script:Language -eq 'ru') {
        'Выберите папку'
    }
    else {
        'Select folder'
    }

    $okLabel = if ($script:Language -eq 'ru') {
        'Выбрать папку'
    }
    else {
        'Select folder'
    }

    try {
        $target = [MugenDeejWindowing.MugenFolderPicker]::SelectFolder(
            $form.Handle,
            $existingTarget,
            $title,
            $okLabel
        )
    }
    catch {
        Write-Log (
            'Modern folder picker failed: {0}' -f
            $_.Exception.Message
        ) 'WARN'

        $folderPickerErrorMessage = if ($script:Language -eq 'ru') {
            'Не удалось открыть современное окно выбора папки.'
        }
        else {
            'Could not open the modern folder picker.'
        }

        [System.Windows.Forms.MessageBox]::Show(
            $folderPickerErrorMessage,
            'Mugen Deej',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null

        return $null
    }

    if ([string]::IsNullOrWhiteSpace($target)) {
        return $null
    }

    return (
        'folder64:' +
        (Encode-ButtonActionPayload -Text $target)
    )
}
function Show-UrlActionEditor {
    param([string]$ExistingAction = '')

    $script:UrlEditorResult = $null

    $editor = New-Object System.Windows.Forms.Form

    if ($script:Language -eq 'ru') {
        $editor.Text = 'Открыть URL — Mugen Deej'
    }
    else {
        $editor.Text = 'Open URL — Mugen Deej'
    }

    $editor.StartPosition = 'CenterParent'
    $editor.ClientSize = [System.Drawing.Size]::new(600, 250)
    $editor.MinimumSize = [System.Drawing.Size]::new(616, 289)
    $editor.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $editor.FormBorderStyle = 'FixedDialog'
    $editor.MaximizeBox = $false
    $editor.MinimizeBox = $false

    Set-FormAppIcon -Form $editor

    $heading = New-Object System.Windows.Forms.Label

    if ($script:Language -eq 'ru') {
        $heading.Text = 'Адрес для открытия'
    }
    else {
        $heading.Text = 'URL to open'
    }

    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $editor.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label

    if ($script:Language -eq 'ru') {
        $hint.Text = 'Введите полный адрес. Он откроется в браузере по умолчанию.'
    }
    else {
        $hint.Text = 'Enter a full URL. It will open in your default browser.'
    }

    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(550, 30)
    $editor.Controls.Add($hint)

    $urlBox = New-Object System.Windows.Forms.TextBox
    $urlBox.Location = [System.Drawing.Point]::new(28, 100)
    $urlBox.Size = [System.Drawing.Size]::new(544, 30)

    if ($ExistingAction -match '^url64:(.+)$') {
        $urlBox.Text = Decode-ButtonActionPayload -Payload $Matches[1]
    }
    else {
        $urlBox.Text = 'https://'
    }

    $editor.Controls.Add($urlBox)

    $validation = New-Object System.Windows.Forms.Label
    $validation.Location = [System.Drawing.Point]::new(28, 137)
    $validation.Size = [System.Drawing.Size]::new(544, 30)
    $editor.Controls.Add($validation)

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(378, 195)
    $cancel.Size = [System.Drawing.Size]::new(95, 36)
    $editor.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(484, 195)
    $save.Size = [System.Drawing.Size]::new(95, 36)
    $editor.Controls.Add($save)

    $save.Add_Click({
        $url = [string]$urlBox.Text.Trim()
        $valid = $false

        try {
            $uri = [Uri]$url
            $valid = (
                $uri.IsAbsoluteUri -and
                ($uri.Scheme -eq 'http' -or $uri.Scheme -eq 'https')
            )
        }
        catch {
            $valid = $false
        }

        if (-not $valid) {
            if ($script:Language -eq 'ru') {
                $validation.Text = 'Введите корректный адрес http:// или https://'
            }
            else {
                $validation.Text = 'Enter a valid http:// or https:// URL.'
            }

            $validation.ForeColor = [System.Drawing.Color]::FromArgb(235, 95, 95)
            return
        }

        $script:UrlEditorResult = (
            'url64:' +
            (Encode-ButtonActionPayload -Text $url)
        )

        $editor.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $editor.Close()
    })

    Apply-ThemeToForm -Form $editor

    $editor.Add_Shown({
        Ensure-FormVisible -Form $editor -CenterIfOffscreen
        $urlBox.SelectAll()
        $urlBox.Focus()
    })

    $editor.AcceptButton = $save
    $editor.CancelButton = $cancel

    [void]$editor.ShowDialog($form)
    $editor.Dispose()

    return $script:UrlEditorResult
}

function Invoke-ShellButtonTarget {
    param([Parameter(Mandatory = $true)][string]$Target)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Target
    $psi.UseShellExecute = $true

    if (Test-Path -LiteralPath $Target -PathType Leaf) {
        try {
            $workingDir = Split-Path -Parent $Target

            if (-not [string]::IsNullOrWhiteSpace($workingDir)) {
                $psi.WorkingDirectory = $workingDir
            }
        }
        catch {}
    }

    [void][System.Diagnostics.Process]::Start($psi)
}
function Get-CommandActionDisplay {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action
    )

    if ($Action -match '^command64:(.+)$') {
        $command = Decode-ButtonActionPayload -Payload $Matches[1]

        if (-not [string]::IsNullOrWhiteSpace($command)) {
            $display = $command.Trim()

            if ($display.Length -gt 72) {
                $display = $display.Substring(0, 69) + '...'
            }

            if ($script:Language -eq 'ru') {
                return ('Выполнить: ' + $display)
            }

            return ('Run: ' + $display)
        }
    }

    if ($script:Language -eq 'ru') {
        return 'Выполнить команду…'
    }

    return 'Run command…'
}

function Show-CommandActionEditor {
    param(
        [string]$ExistingAction = ''
    )

    $script:CommandEditorResult = $null

    $editor = New-Object System.Windows.Forms.Form

    if ($script:Language -eq 'ru') {
        $editor.Text = 'Выполнить команду — Mugen Deej'
    }
    else {
        $editor.Text = 'Run command — Mugen Deej'
    }

    $editor.StartPosition = 'CenterParent'
    $editor.ClientSize = [System.Drawing.Size]::new(650, 310)
    $editor.MinimumSize = [System.Drawing.Size]::new(666, 349)
    $editor.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $editor.FormBorderStyle = 'FixedDialog'
    $editor.MaximizeBox = $false
    $editor.MinimizeBox = $false

    Set-FormAppIcon -Form $editor

    $heading = New-Object System.Windows.Forms.Label

    if ($script:Language -eq 'ru') {
        $heading.Text = 'Команда Windows'
    }
    else {
        $heading.Text = 'Windows command'
    }

    $heading.Font = New-Object System.Drawing.Font(
        'Segoe UI Semibold',
        15
    )
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $editor.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label

    if ($script:Language -eq 'ru') {
        $hint.Text = 'Введите то, что обычно можно запустить через Win+R: cmd, notepad, control, ms-settings:display. Можно указывать аргументы, например: cmd /k ipconfig'
    }
    else {
        $hint.Text = 'Enter something you would normally run with Win+R: cmd, notepad, control, ms-settings:display. Arguments are allowed, for example: cmd /k ipconfig'
    }

    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(600, 58)
    $editor.Controls.Add($hint)

    $commandBox = New-Object System.Windows.Forms.TextBox
    $commandBox.Location = [System.Drawing.Point]::new(28, 127)
    $commandBox.Size = [System.Drawing.Size]::new(594, 30)

    if ($ExistingAction -match '^command64:(.+)$') {
        $commandBox.Text = Decode-ButtonActionPayload -Payload $Matches[1]
    }

    $editor.Controls.Add($commandBox)

    $validation = New-Object System.Windows.Forms.Label
    $validation.Location = [System.Drawing.Point]::new(28, 165)
    $validation.Size = [System.Drawing.Size]::new(594, 32)
    $editor.Controls.Add($validation)

    $notice = New-Object System.Windows.Forms.Label

    if ($script:Language -eq 'ru') {
        $notice.Text = 'Команда запускается с теми же правами, что и Mugen Deej.'
    }
    else {
        $notice.Text = 'The command runs with the same privileges as Mugen Deej.'
    }

    $notice.Location = [System.Drawing.Point]::new(28, 207)
    $notice.Size = [System.Drawing.Size]::new(594, 30)
    $editor.Controls.Add($notice)

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(428, 257)
    $cancel.Size = [System.Drawing.Size]::new(95, 36)
    $editor.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(534, 257)
    $save.Size = [System.Drawing.Size]::new(95, 36)
    $editor.Controls.Add($save)

    $save.Add_Click({
        $command = [string]$commandBox.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($command)) {
            if ($script:Language -eq 'ru') {
                $validation.Text = 'Введите команду.'
            }
            else {
                $validation.Text = 'Enter a command.'
            }

            $validation.ForeColor = [System.Drawing.Color]::FromArgb(
                235,
                95,
                95
            )

            return
        }

        $script:CommandEditorResult = (
            'command64:' +
            (Encode-ButtonActionPayload -Text $command)
        )

        $editor.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $editor.Close()
    })

    Apply-ThemeToForm -Form $editor

    $editor.Add_Shown({
        Ensure-FormVisible -Form $editor -CenterIfOffscreen
        $commandBox.Focus()
        $commandBox.SelectionStart = $commandBox.Text.Length
    })

    $editor.AcceptButton = $save
    $editor.CancelButton = $cancel

    [void]$editor.ShowDialog($form)
    $editor.Dispose()

    return $script:CommandEditorResult
}

function Invoke-RunCommandAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        throw 'Command is empty.'
    }

    $commandProcessor = $env:ComSpec

    if ([string]::IsNullOrWhiteSpace($commandProcessor)) {
        $commandProcessor = 'cmd.exe'
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $commandProcessor
    $psi.Arguments = (
        '/d /c start "" ' +
        $Command
    )
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    [void][System.Diagnostics.Process]::Start($psi)
}
function Read-ButtonActionConfigFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($null -eq $data) {
        throw 'Button action configuration is empty.'
    }
    if ($null -eq $data.PSObject.Properties['version']) {
        throw 'Button action configuration has no schema version.'
    }
    if ([int]$data.version -ne 1) {
        throw ('Unsupported button action configuration version: {0}' -f $data.version)
    }
    if ($null -eq $data.PSObject.Properties['actions']) {
        throw 'Button action configuration has no actions array.'
    }

    $actions = @()
    foreach ($item in @($data.actions)) {
        if ($null -eq $item) {
            throw 'Button action configuration contains a null action.'
        }
        $actions += [string]$item
    }

    return [pscustomobject]@{
        version = 1
        actions = @($actions)
    }
}

function Write-ButtonActionConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Actions
    )

    $tempPath = "$Path.tmp-$PID"

    try {
        $payload = [pscustomobject]@{
            version = 1
            actions = @($Actions | ForEach-Object { [string]$_ })
        }

        $json = $payload | ConvertTo-Json -Depth 4
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)

        $verified = Read-ButtonActionConfigFile -Path $tempPath
        $expected = @($payload.actions)
        $actual = @($verified.actions)

        if ($actual.Count -ne $expected.Count) {
            throw 'Button action configuration failed action-count verification.'
        }

        for ($i = 0; $i -lt $expected.Count; $i++) {
            if ([string]$actual[$i] -cne [string]$expected[$i]) {
                throw ('Button action configuration failed verification at action {0}.' -f ($i + 1))
            }
        }

        if (Test-Path -LiteralPath $Path) {
            try {
                [System.IO.File]::Replace($tempPath, $Path, $null, $true)
            }
            catch {
                Copy-Item -LiteralPath $tempPath -Destination $Path -Force
                Remove-Item -LiteralPath $tempPath -Force
            }
        }
        else {
            [System.IO.File]::Move($tempPath, $Path)
        }

        [void](Read-ButtonActionConfigFile -Path $Path)
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Try-MigrateLegacyButtonActionConfig {
    if (Test-Path -LiteralPath $script:ButtonActionConfigPath) { return $false }
    if (-not (Test-Path -LiteralPath $script:LegacyButtonActionConfigPath)) { return $false }

    try {
        $legacy = Read-ButtonActionConfigFile -Path $script:LegacyButtonActionConfigPath
        Write-ButtonActionConfigFile -Path $script:ButtonActionConfigPath -Actions @($legacy.actions)

        Write-Log (
            'Button action config migrated safely: {0} -> {1}; actions={2}; legacy file preserved' -f
            [System.IO.Path]::GetFileName($script:LegacyButtonActionConfigPath),
            [System.IO.Path]::GetFileName($script:ButtonActionConfigPath),
            @($legacy.actions).Count
        ) 'INFO'

        return $true
    }
    catch {
        Write-Log (
            'Button action config migration failed; legacy file was left untouched: {0}' -f
            $_.Exception.Message
        ) 'WARN'
        return $false
    }
}

function Initialize-ButtonActions {
    if ($script:ButtonActionsLoaded) { return }

    $script:ButtonActionsLoaded = $true
    $script:ButtonActions = @()

    [void](Try-MigrateLegacyButtonActionConfig)

    $loadPath = ''
    if (Test-Path -LiteralPath $script:ButtonActionConfigPath) {
        $loadPath = $script:ButtonActionConfigPath
    }
    elseif (Test-Path -LiteralPath $script:LegacyButtonActionConfigPath) {
        # A migration can fail because the folder is temporarily unwritable.
        # Keep the user's existing button mappings active without modifying the
        # legacy file; the migration will be attempted again on the next run.
        $loadPath = $script:LegacyButtonActionConfigPath
    }
    else {
        return
    }

    try {
        $data = Read-ButtonActionConfigFile -Path $loadPath
        $script:ButtonActions = @($data.actions | ForEach-Object { [string]$_ })

        Write-Log (
            'Button action config loaded: file={0}; actions={1}' -f
            [System.IO.Path]::GetFileName($loadPath),
            @($script:ButtonActions).Count
        ) 'DEBUG'
    }
    catch {
        Write-Log (
            'Failed to load button action config {0}: {1}' -f
            [System.IO.Path]::GetFileName($loadPath),
            $_.Exception.Message
        ) 'WARN'
        $script:ButtonActions = @()
    }
}

function Normalize-ButtonActions {
    param([Parameter(Mandatory = $true)][int]$Count)

    Initialize-ButtonActions

    if ($Count -lt 0) {
        $Count = 0
    }

    $validFixedActions = @(
        'media:playpause',
        'media:previous',
        'media:next',
        'media:stop',
        'system:volumeup',
        'system:volumedown',
        'system:volumemute'
    )

    $normalized = @()

    for ($i = 0; $i -lt $Count; $i++) {
        $action = if ($i -lt @($script:ButtonActions).Count) {
            [string]$script:ButtonActions[$i]
        }
        else {
            'none'
        }

        if ([string]::IsNullOrWhiteSpace($action)) {
            $action = 'none'
        }

        $valid = (
            $action -eq 'none' -or
            $action -match '^mute:\d+$' -or
            $validFixedActions -contains $action
        )

        if (
            -not $valid -and
            $action -match '^hotkey:(\d{1,3}):(\d{1,2})$'
        ) {
            $vk = [int]$Matches[1]
            $mask = [int]$Matches[2]

            $valid = (
                $vk -gt 0 -and
                $vk -le 255 -and
                $mask -ge 0 -and
                $mask -le 15
            )
        }

        if (
            -not $valid -and
            $action -match '^(launch64|folder64|url64|command64):(.+)$'
        ) {
            $decoded = Decode-ButtonActionPayload -Payload $Matches[2]
            $valid = -not [string]::IsNullOrWhiteSpace($decoded)
        }

        if (-not $valid) {
            $action = 'none'
        }

        $normalized += $action
    }

    $script:ButtonActions = @($normalized)
}
function Save-ButtonActions {
    Write-ButtonActionConfigFile `
        -Path $script:ButtonActionConfigPath `
        -Actions @($script:ButtonActions)

    Write-Log (
        'Button actions saved to {0}: {1}' -f
        [System.IO.Path]::GetFileName($script:ButtonActionConfigPath),
        (@($script:ButtonActions) -join ',')
    ) 'INFO'
}

function Get-MugenDeejBackupFileName {
    return ('MugenDeej_{0}.backup' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
}

function Read-MugenDeejBackupFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $data) {
        throw 'Backup file is empty.'
    }
    if ([string]$data.format -cne 'MugenDeejBackup') {
        throw 'This file is not a Mugen Deej backup.'
    }
    if ($null -eq $data.PSObject.Properties['schemaVersion']) {
        throw 'Backup schema version is missing.'
    }
    if ([int]$data.schemaVersion -ne 1) {
        throw ('Unsupported backup schema version: {0}' -f $data.schemaVersion)
    }
    if ($null -eq $data.PSObject.Properties['config'] -or $null -eq $data.config) {
        throw 'Backup does not contain the main configuration.'
    }
    if ($null -eq $data.PSObject.Properties['buttonActions'] -or $null -eq $data.buttonActions) {
        throw 'Backup does not contain button actions.'
    }
    if ($null -eq $data.buttonActions.PSObject.Properties['version'] -or [int]$data.buttonActions.version -ne 1) {
        throw 'Unsupported or missing button-action configuration version in backup.'
    }
    if ($null -eq $data.buttonActions.PSObject.Properties['actions']) {
        throw 'Backup button-action list is missing.'
    }

    foreach ($item in @($data.buttonActions.actions)) {
        if ($null -eq $item) {
            throw 'Backup button-action list contains a null item.'
        }
    }

    return $data
}

function New-MugenDeejBackupSnapshot {
    Initialize-ButtonActions

    $configClone = $script:Config | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $actions = @($script:ButtonActions | ForEach-Object { [string]$_ })

    return [pscustomobject][ordered]@{
        format = 'MugenDeejBackup'
        schemaVersion = 1
        createdAt = (Get-Date).ToString('o')
        createdBy = $script:AppVersion
        config = $configClone
        buttonActions = [pscustomobject][ordered]@{
            version = 1
            actions = @($actions)
        }
    }
}

function Write-MugenDeejBackupFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Snapshot
    )

    $tempPath = "$Path.tmp-$PID"
    try {
        $json = $Snapshot | ConvertTo-Json -Depth 16
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)

        [void](Read-MugenDeejBackupFile -Path $tempPath)

        if (Test-Path -LiteralPath $Path) {
            try {
                [System.IO.File]::Replace($tempPath, $Path, $null, $true)
            }
            catch {
                Copy-Item -LiteralPath $tempPath -Destination $Path -Force
                Remove-Item -LiteralPath $tempPath -Force
            }
        }
        else {
            [System.IO.File]::Move($tempPath, $Path)
        }

        [void](Read-MugenDeejBackupFile -Path $Path)
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Show-MugenDeejStyledDialog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('OK','YesNo')][string]$Buttons = 'OK',
        [ValidateSet('Info','Warning','Error')][string]$Kind = 'Info'
    )

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Mugen Deej'
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.ClientSize = New-Object System.Drawing.Size(560, 250)
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $card = New-Object MugenDeejWindowing.MugenCardPanel
    $card.Location = New-Object System.Drawing.Point(18, 18)
    $card.Size = New-Object System.Drawing.Size(524, 158)
    $dialog.Controls.Add($card)

    $badge = New-Object System.Windows.Forms.Label
    $badge.AutoSize = $false
    $badge.Location = New-Object System.Drawing.Point(18, 22)
    $badge.Size = New-Object System.Drawing.Size(42, 42)
    $badge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $badge.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 18)
    $badge.Text = if ($Kind -eq 'Info') { 'ⓘ' } elseif ($Kind -eq 'Warning') { '⚠' } else { '×' }
    $card.Controls.Add($badge)

    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.AutoSize = $false
    $messageLabel.Location = New-Object System.Drawing.Point(72, 16)
    $messageLabel.Size = New-Object System.Drawing.Size(432, 126)
    $messageLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $messageLabel.Text = $Message
    $card.Controls.Add($messageLabel)

    if ($Buttons -eq 'YesNo') {
        $yesButton = New-Object MugenDeejWindowing.MugenButton
        $yesButton.Tag = 'MugenPrimary'
        $yesButton.Text = (T -Key 'DialogYes')
        $yesButton.Location = New-Object System.Drawing.Point(342, 194)
        $yesButton.Size = New-Object System.Drawing.Size(92, 36)
        $yesButton.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $dialog.Controls.Add($yesButton)

        $noButton = New-Object MugenDeejWindowing.MugenButton
        $noButton.Text = (T -Key 'DialogNo')
        $noButton.Location = New-Object System.Drawing.Point(450, 194)
        $noButton.Size = New-Object System.Drawing.Size(92, 36)
        $noButton.DialogResult = [System.Windows.Forms.DialogResult]::No
        $dialog.Controls.Add($noButton)

        $dialog.AcceptButton = $yesButton
        $dialog.CancelButton = $noButton
    }
    else {
        $okButton = New-Object MugenDeejWindowing.MugenButton
        $okButton.Tag = 'MugenPrimary'
        $okButton.Text = (T -Key 'DialogOK')
        $okButton.Location = New-Object System.Drawing.Point(450, 194)
        $okButton.Size = New-Object System.Drawing.Size(92, 36)
        $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Controls.Add($okButton)

        $dialog.AcceptButton = $okButton
        $dialog.CancelButton = $okButton
    }

    Apply-ThemeToForm -Form $dialog -ThemeName (Get-EffectiveTheme)
    $dialog.Add_Shown({ Ensure-FormVisible -Form $dialog -CenterIfOffscreen })
    return $dialog.ShowDialog($form)
}

function Save-MugenDeejBackupInteractive {
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = (T -Key 'BackupSaveTitle')
    $dialog.Filter = 'Mugen Deej backup (*.backup)|*.backup|All files (*.*)|*.*'
    $dialog.DefaultExt = 'backup'
    $dialog.AddExtension = $true
    # The native overwrite prompt follows the Windows shell language, which
    # can differ from the language selected inside Mugen.
    $dialog.OverwritePrompt = $false
    $dialog.FileName = Get-MugenDeejBackupFileName

    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    if (Test-Path -LiteralPath $dialog.FileName -PathType Leaf) {
        $nl = [Environment]::NewLine
        $overwriteMessage = if ($script:Language -eq 'ru') {
            'Файл резервной копии уже существует:' + $nl + $nl + $dialog.FileName + $nl + $nl + 'Заменить его?'
        }
        else {
            'The backup file already exists:' + $nl + $nl + $dialog.FileName + $nl + $nl + 'Replace it?'
        }

        $overwriteResult = Show-MugenDeejStyledDialog -Message $overwriteMessage -Buttons 'YesNo' -Kind 'Warning'
        if ($overwriteResult -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }

    try {
        $snapshot = New-MugenDeejBackupSnapshot
        Write-MugenDeejBackupFile -Path $dialog.FileName -Snapshot $snapshot
        Write-Log ('Portable backup created: {0}' -f $dialog.FileName) 'INFO'

        [void](Show-MugenDeejStyledDialog `
            -Message ((T -Key 'BackupCreated') + "`r`n`r`n" + $dialog.FileName) `
            -Buttons 'OK' `
            -Kind 'Info')
    }
    catch {
        Write-Log ('Backup creation failed: {0}' -f $_.Exception.Message) 'ERROR'
        [void](Show-MugenDeejStyledDialog `
            -Message ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $_.Exception.Message) `
            -Buttons 'OK' `
            -Kind 'Error')
    }
}
function Restore-MugenDeejBackupInteractive {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = (T -Key 'BackupOpenTitle')
    $dialog.Filter = 'Mugen Deej backup (*.backup)|*.backup|All files (*.*)|*.*'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    try {
        $backup = Read-MugenDeejBackupFile -Path $dialog.FileName
    }
    catch {
        Write-Log ('Backup validation failed: {0}' -f $_.Exception.Message) 'WARN'
        [void](Show-MugenDeejStyledDialog `
            -Message ((T -Key 'BackupInvalid') + "`r`n`r`n" + $_.Exception.Message) `
            -Buttons 'OK' `
            -Kind 'Warning')
        return
    }

    $confirmation = Show-MugenDeejStyledDialog `
        -Message (T -Key 'BackupRestoreConfirm') `
        -Buttons 'YesNo' `
        -Kind 'Warning'

    if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    Initialize-ButtonActions
    $preRestoreSnapshot = New-MugenDeejBackupSnapshot
    $preRestorePath = Join-Path $script:BaseDir ('MugenDeej_PreRestore_{0}.backup' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))

    try {
        Write-MugenDeejBackupFile -Path $preRestorePath -Snapshot $preRestoreSnapshot
    }
    catch {
        Write-Log ('Restore aborted because emergency backup could not be created: {0}' -f $_.Exception.Message) 'ERROR'
        [void](Show-MugenDeejStyledDialog `
            -Message ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $_.Exception.Message) `
            -Buttons 'OK' `
            -Kind 'Error')
        return
    }

    try {
        $configClone = $backup.config | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $restoredConfig = Ensure-ConfigShape -Config $configClone
        $restoredActions = @($backup.buttonActions.actions | ForEach-Object { [string]$_ })

        Save-Config -Config $restoredConfig
        Write-ButtonActionConfigFile -Path $script:ButtonActionConfigPath -Actions $restoredActions

        $script:Config = $restoredConfig
        $script:ButtonActions = @($restoredActions)
        $script:ButtonActionsLoaded = $true

        Write-Log ('Settings restored from backup: {0}; emergencyBackup={1}' -f $dialog.FileName, $preRestorePath) 'INFO'

        $restartMessage = (
            (T -Key 'BackupRestored') + "`r`n`r`n" +
            (T -Key 'BackupEmergencyCopy') + "`r`n" + $preRestorePath + "`r`n`r`n" +
            (T -Key 'BackupRestartPrompt')
        )

        $restartResult = Show-MugenDeejStyledDialog `
            -Message $restartMessage `
            -Buttons 'YesNo' `
            -Kind 'Info'

        if ($restartResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            Write-Log 'Restart requested after backup restore.' 'INFO'
            $script:RestartRequested = $true
            $script:Closing = $true
            $script:ExitRequested = $true
            $script:ShutdownFinalizing = $true
            $form.Close()
        }
    }
    catch {
        $restoreError = $_.Exception.Message
        Write-Log ('Restore failed; attempting rollback from emergency backup: {0}' -f $restoreError) 'ERROR'

        try {
            $rollback = Read-MugenDeejBackupFile -Path $preRestorePath
            $rollbackConfigClone = $rollback.config | ConvertTo-Json -Depth 12 | ConvertFrom-Json
            $rollbackConfig = Ensure-ConfigShape -Config $rollbackConfigClone
            $rollbackActions = @($rollback.buttonActions.actions | ForEach-Object { [string]$_ })

            Save-Config -Config $rollbackConfig
            Write-ButtonActionConfigFile -Path $script:ButtonActionConfigPath -Actions $rollbackActions
            $script:Config = $rollbackConfig
            $script:ButtonActions = @($rollbackActions)
            $script:ButtonActionsLoaded = $true
            Write-Log 'Rollback after failed restore completed successfully.' 'WARN'
        }
        catch {
            Write-Log ('Rollback after failed restore also failed: {0}' -f $_.Exception.Message) 'ERROR'
        }

        [void](Show-MugenDeejStyledDialog `
            -Message ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $restoreError) `
            -Buttons 'OK' `
            -Kind 'Error')
    }
}
function Show-MugenDeejBackupMenu {
    param([Parameter(Mandatory = $true)]$OwnerControl)

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $createItem = $menu.Items.Add((T -Key 'BackupCreate'))
    $restoreItem = $menu.Items.Add((T -Key 'BackupRestore'))

    $createItem.Add_Click({ Save-MugenDeejBackupInteractive })
    $restoreItem.Add_Click({ Restore-MugenDeejBackupInteractive })

    try {
        Apply-ToolStripTheme -ToolStrip $menu -ThemeName (Get-EffectiveTheme)
    }
    catch { }

    $menu.Show($OwnerControl, (New-Object System.Drawing.Point(0, $OwnerControl.Height)))
}
function Get-MuteStatusColor {
    if ((Get-EffectiveTheme) -eq 'dark') {
        return [System.Drawing.Color]::FromArgb(255, 92, 92)
    }
    return [System.Drawing.Color]::Firebrick
}

function Set-ButtonIndicatorAppearance {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Label]$Indicator,
        [Parameter(Mandatory = $true)][int]$ButtonIndex,
        [switch]$DotOnly
    )

    $themeName = Get-EffectiveTheme
    $palette = $script:ThemePalettes[$themeName]
    if ($Indicator -is [MugenDeejWindowing.MugenButtonTile]) {
        $Indicator.BorderColor = $palette.Border
    }
    $pressed = (
        @($script:LatestButtons).Count -gt $ButtonIndex -and
        [int]$script:LatestButtons[$ButtonIndex] -eq 0
    )

    if ($DotOnly) {
        $Indicator.BackColor = [System.Drawing.Color]::Transparent
        $Indicator.ForeColor = if ($pressed) { $palette.Accent } else { $palette.Muted }
        return
    }

    $Indicator.BackColor = if ($pressed) { $palette.Accent } else { $palette.Control }
    $Indicator.ForeColor = if ($pressed) { $palette.AccentText } else { $palette.Text }
}

function Ensure-MainButtonIndicators {
    $count = if ($script:IsConnected) { [int]$script:DetectedButtonCount } else { 0 }

    if ($null -eq $script:ButtonStateFlow -or $script:ButtonStateFlow.IsDisposed) { return }
    if (@($script:MainButtonIndicators).Count -eq $count) { return }

    $script:ButtonStateFlow.SuspendLayout()
    try {
        $script:ButtonStateFlow.Controls.Clear()
        $script:MainButtonIndicators = @()

        for ($i = 0; $i -lt $count; $i++) {
            $indicator = New-Object MugenDeejWindowing.MugenButtonTile
            $indicator.Text = [string]($i + 1)
            $indicator.Size = [System.Drawing.Size]::new(46, 28)
            $indicator.Margin = New-Object System.Windows.Forms.Padding(4, 1, 4, 1)
            $indicator.TextAlign = 'MiddleCenter'
            $indicator.BorderStyle = 'None'
            # dev5: MugenButtonTile draws its own rounded border; no Region clipping.
            $indicator.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $script:ButtonStateFlow.Controls.Add($indicator)
            $script:MainButtonIndicators += $indicator
        }
    }
    finally {
        $script:ButtonStateFlow.ResumeLayout($true)
    }
}

function Update-MainButtonIndicators {
    Ensure-MainButtonIndicators

    
# dev3 theme fix: FlowLayoutPanel must visually inherit the MugenGroupBox card surface
    if (
        $null -ne $script:ButtonStateFlow -and
        -not $script:ButtonStateFlow.IsDisposed -and
        $null -ne $script:ButtonStateGroup -and
        -not $script:ButtonStateGroup.IsDisposed
    ) {
        $script:ButtonStateFlow.BackColor = $script:ButtonStateGroup.BackColor
    }

    for ($i = 0; $i -lt @($script:MainButtonIndicators).Count; $i++) {
        Set-ButtonIndicatorAppearance `
            -Indicator $script:MainButtonIndicators[$i] `
            -ButtonIndex $i
    }
}

function Set-MainButtonLayout {
    param([Parameter(Mandatory = $true)][bool]$HasButtons)

    if (
        $null -eq $form -or
        $null -eq $startupGroup -or
        $null -eq $advancedToggle -or
        $null -eq $advancedPanel -or
        $null -eq $footer
    ) {
        return
    }

    $offset = if ($HasButtons) { 84 } else { 0 }

    if ($null -ne $script:ButtonStateGroup) {
        $script:ButtonStateGroup.Location = [System.Drawing.Point]::new(24, 356)
    }

    $settingsButton.Location = [System.Drawing.Point]::new(24, (360 + $offset))
    if ($null -ne $script:ButtonSettingsButton) {
        $script:ButtonSettingsButton.Location = [System.Drawing.Point]::new(272, (360 + $offset))
    }
    if ($null -ne $script:SettingsHintControl) {
        $script:SettingsHintControl.Location = [System.Drawing.Point]::new(272, (358 + $offset))
    }

    $startupGroup.Location = [System.Drawing.Point]::new(24, (414 + $offset))
    $advancedToggle.Location = [System.Drawing.Point]::new(24, (516 + $offset))
    if ($null -ne $script:BackupMenuButton -and -not $script:BackupMenuButton.IsDisposed) {
        $script:BackupMenuButton.Location = [System.Drawing.Point]::new(292, (516 + $offset))
    }
    $advancedPanel.Location = [System.Drawing.Point]::new(0, (550 + $offset))

    $collapsedHeight = 592 + $offset
    $expandedHeight = 860 + $offset

    $form.MinimumSize = [System.Drawing.Size]::new(696, (631 + $offset))
    $form.MaximumSize = [System.Drawing.Size]::new(696, (899 + $offset))
    $form.ClientSize = [System.Drawing.Size]::new(
        680,
        $(if ($advancedPanel.Visible) { $expandedHeight } else { $collapsedHeight })
    )
    $footer.Location = [System.Drawing.Point]::new(24, ($form.ClientSize.Height - 28))
}

function Update-ButtonFeatureUi {
    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)

    if ($null -ne $script:ButtonSettingsButton -and -not $script:ButtonSettingsButton.IsDisposed) {
        $script:ButtonSettingsButton.Text = Get-ButtonFeatureText -Key 'MainButton'
        $script:ButtonSettingsButton.Visible = $hasButtons
        $script:ButtonSettingsButton.Enabled = $hasButtons
    }

    if ($null -ne $script:SettingsHintControl -and -not $script:SettingsHintControl.IsDisposed) {
        $script:SettingsHintControl.Visible = (-not $hasButtons)
    }

    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed) {
        $script:ButtonStateGroup.Text = Get-ButtonFeatureText -Key 'ButtonStatus'
        $script:ButtonStateGroup.Visible = $hasButtons
    }

    if ($script:LastButtonUiVisible -ne $hasButtons) {
        $script:LastButtonUiVisible = $hasButtons
        Set-MainButtonLayout -HasButtons $hasButtons
    }

    if ($hasButtons) {
        Update-MainButtonIndicators
    }
}

function Set-SliderAudioLevelDirect {
    param(
        [Parameter(Mandatory = $true)][int]$SliderIndex,
        [Parameter(Mandatory = $true)][double]$Level
    )

    if ($SliderIndex -lt 0 -or $SliderIndex -ge $script:Config.sliders.Count) { return }

    $levelClamped = [Math]::Max(0.0, [Math]::Min(1.0, $Level))
    $slider = $script:Config.sliders[$SliderIndex]
    $processTargets = New-Object 'System.Collections.Generic.List[string]'

    foreach ($targetObject in @($slider.targets)) {
        $target = ([string]$targetObject).Trim()
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        $audioTargetKey = $target

        try {
            if ($target -ieq 'master') {
                [MugenDeejAudio.AudioMixer]::SetMaster([single]$levelClamped)
            }
            elseif ($target -ieq 'mic') {
                $inputDeviceId = [string]$slider.inputDeviceId
                $audioTargetKey = 'mic:' + $inputDeviceId
                [MugenDeejAudio.AudioMixer]::SetInputDeviceVolume($inputDeviceId, [single]$levelClamped)
            }
            else {
                $processTargets.Add($target)
            }
        }
        catch {
            Write-AudioWarningThrottled `
                -Key ('button-slider-' + ($SliderIndex + 1) + '-' + $audioTargetKey) `
                -Message ('Button audio target failed: ' + $audioTargetKey + '; ' + $_.Exception.Message)
        }
    }

    if ($processTargets.Count -gt 0) {
        try {
            [void][MugenDeejAudio.AudioMixer]::SetProcessVolumes($processTargets.ToArray(), [single]$levelClamped)
        }
        catch {
            Write-AudioWarningThrottled `
                -Key ('button-slider-' + ($SliderIndex + 1) + '-applications') `
                -Message ('Button application targets failed for slider ' + ($SliderIndex + 1) + ': ' + $_.Exception.Message)
            [MugenDeejAudio.AudioMixer]::InvalidateSessions()
        }
    }
}

function Toggle-SliderSoftMute {
    param([Parameter(Mandatory = $true)][int]$SliderIndex)

    if ($SliderIndex -lt 0 -or $SliderIndex -ge $script:Config.sliders.Count) { return }

    if ($script:SoftMutedSliders.ContainsKey($SliderIndex)) {
        [void]$script:SoftMutedSliders.Remove($SliderIndex)

        $level = 0.0
        if ($script:LatestLevels.Count -gt $SliderIndex) {
            $level = [Math]::Max(0.0, [Math]::Min(1.0, [double]$script:LatestLevels[$SliderIndex]))
        }

        if ($script:LastValues.Count -gt $SliderIndex) {
            $script:LastValues[$SliderIndex] = $level
        }

        Set-SliderAudioLevelDirect -SliderIndex $SliderIndex -Level $level
        Write-Log ('Button action: slider {0} unmuted at {1:P0}' -f ($SliderIndex + 1), $level) 'INFO'
    }
    else {
        $script:SoftMutedSliders[$SliderIndex] = $true
        Set-SliderAudioLevelDirect -SliderIndex $SliderIndex -Level 0.0
        Write-Log ('Button action: slider {0} muted' -f ($SliderIndex + 1)) 'INFO'
    }
}

function Clear-SoftMutesAfterControllerDisconnect {
    param(
        [string]$Reason = 'controller disconnected'
    )

    $mutedIndexes = @(
        $script:SoftMutedSliders.Keys |
        ForEach-Object { [int]$_ } |
        Sort-Object
    )

    if ($mutedIndexes.Count -eq 0) {
        return
    }

    $restored = New-Object 'System.Collections.Generic.List[string]'

    foreach ($sliderIndex in $mutedIndexes) {
        $level = 0.0

        if ($script:LatestLevels.Count -gt $sliderIndex) {
            $level = [Math]::Max(
                0.0,
                [Math]::Min(
                    1.0,
                    [double]$script:LatestLevels[$sliderIndex]
                )
            )
        }

        [void]$script:SoftMutedSliders.Remove($sliderIndex)

        if ($script:LastValues.Count -gt $sliderIndex) {
            $script:LastValues[$sliderIndex] = $level
        }

        Set-SliderAudioLevelDirect `
            -SliderIndex $sliderIndex `
            -Level $level

        $restored.Add(
            ('{0}:{1:P0}' -f ($sliderIndex + 1), $level)
        )
    }

    Write-Log (
        'Soft mutes cleared after controller disconnect: reason={0}; sliders={1}; restored={2}' -f
        $Reason,
        $mutedIndexes.Count,
        ($restored -join ',')
    ) 'INFO'
}

function Invoke-ButtonAction {
    param([Parameter(Mandatory = $true)][int]$ButtonIndex)

    Initialize-ButtonActions

    if (
        $ButtonIndex -lt 0 -or
        $ButtonIndex -ge @($script:ButtonActions).Count
    ) {
        return
    }

    $now = Get-Date

    if ($script:LastButtonActionAt.ContainsKey($ButtonIndex)) {
        $elapsedMs = (
            $now -
            [DateTime]$script:LastButtonActionAt[$ButtonIndex]
        ).TotalMilliseconds

        if ($elapsedMs -lt 80) {
            Write-Log (
                'Button {0} action suppressed by debounce ({1:N0} ms)' -f
                ($ButtonIndex + 1),
                $elapsedMs
            ) 'DEBUG'
            return
        }
    }

    $script:LastButtonActionAt[$ButtonIndex] = $now

    $action = [string]$script:ButtonActions[$ButtonIndex]

    if (
        [string]::IsNullOrWhiteSpace($action) -or
        $action -eq 'none'
    ) {
        return
    }

    if ($action -match '^mute:(\d+)$') {
        Toggle-SliderSoftMute -SliderIndex ([int]$Matches[1])
        return
    }

    if ($action -match '^hotkey:(\d{1,3}):(\d{1,2})$') {
        $keyCode = [int]$Matches[1]
        $mask = [int]$Matches[2]

        try {
            [MugenDeejWindowing.MugenHotkeys]::Send(
                $keyCode,
                (($mask -band 1) -ne 0),
                (($mask -band 2) -ne 0),
                (($mask -band 4) -ne 0),
                (($mask -band 8) -ne 0)
            )

            Write-Log (
                'Button action: custom hotkey; transport=SendInput; button={0}; hotkey={1}' -f
                ($ButtonIndex + 1),
                (Get-HotkeyActionDisplay -Action $action)
            ) 'INFO'
        }
        catch {
            Write-Log (
                'Custom hotkey failed: button={0}; action={1}; error={2}' -f
                ($ButtonIndex + 1),
                $action,
                $_.Exception.Message
            ) 'WARN'
        }

        return
    }

    if ($action -match '^command64:(.+)$') {
        $command = Decode-ButtonActionPayload -Payload $Matches[1]

        try {
            Invoke-RunCommandAction -Command $command

            Write-Log (
                'Button action: run command; button={0}' -f
                ($ButtonIndex + 1)
            ) 'INFO'
        }
        catch {
            Write-Log (
                'Command action failed: button={0}; error={1}' -f
                ($ButtonIndex + 1),
                $_.Exception.Message
            ) 'WARN'
        }

        return
    }
    if ($action -match '^launch64:(.+)$') {
        $target = Decode-ButtonActionPayload -Payload $Matches[1]

        try {
            if (
                [string]::IsNullOrWhiteSpace($target) -or
                -not (Test-Path -LiteralPath $target -PathType Leaf)
            ) {
                throw ('Target file was not found: ' + $target)
            }

            Invoke-ShellButtonTarget -Target $target

            Write-Log (
                'Button action: launch file/program; button={0}; target={1}' -f
                ($ButtonIndex + 1),
                [System.IO.Path]::GetFileName($target)
            ) 'INFO'
        }
        catch {
            Write-Log (
                'Launch action failed: button={0}; error={1}' -f
                ($ButtonIndex + 1),
                $_.Exception.Message
            ) 'WARN'
        }

        return
    }

    if ($action -match '^folder64:(.+)$') {
        $target = Decode-ButtonActionPayload -Payload $Matches[1]

        try {
            if (
                [string]::IsNullOrWhiteSpace($target) -or
                -not (Test-Path -LiteralPath $target -PathType Container)
            ) {
                throw ('Target folder was not found: ' + $target)
            }

            Invoke-ShellButtonTarget -Target $target

            Write-Log (
                'Button action: open folder; button={0}; target={1}' -f
                ($ButtonIndex + 1),
                $target
            ) 'INFO'
        }
        catch {
            Write-Log (
                'Folder action failed: button={0}; error={1}' -f
                ($ButtonIndex + 1),
                $_.Exception.Message
            ) 'WARN'
        }

        return
    }

    if ($action -match '^url64:(.+)$') {
        $url = Decode-ButtonActionPayload -Payload $Matches[1]

        try {
            Invoke-ShellButtonTarget -Target $url

            $urlHost = $url

            try {
                $urlHost = ([Uri]$url).Host
            }
            catch {}

            Write-Log (
                'Button action: open URL; button={0}; target={1}' -f
                ($ButtonIndex + 1),
                $urlHost
            ) 'INFO'
        }
        catch {
            Write-Log (
                'URL action failed: button={0}; error={1}' -f
                ($ButtonIndex + 1),
                $_.Exception.Message
            ) 'WARN'
        }

        return
    }

    try {
        switch ($action) {
            'media:playpause' {
                [MugenDeejWindowing.MugenMediaKeys]::PlayPause()
                Write-Log (
                    'Button action: media play/pause; transport=WM_APPCOMMAND; button={0}' -f
                    ($ButtonIndex + 1)
                ) 'INFO'
                return
            }

            'media:previous' {
                [MugenDeejWindowing.MugenMediaKeys]::PreviousTrack()
                Write-Log (
                    'Button action: media previous track; transport=WM_APPCOMMAND; button={0}' -f
                    ($ButtonIndex + 1)
                ) 'INFO'
                return
            }

            'media:next' {
                [MugenDeejWindowing.MugenMediaKeys]::NextTrack()
                Write-Log (
                    'Button action: media next track; transport=WM_APPCOMMAND; button={0}' -f
                    ($ButtonIndex + 1)
                ) 'INFO'
                return
            }

            'media:stop' {
                [MugenDeejWindowing.MugenMediaKeys]::Stop()
                Write-Log (
                    'Button action: media stop; transport=WM_APPCOMMAND; button={0}' -f
                    ($ButtonIndex + 1)
                ) 'INFO'
                return
            }

            'system:volumeup' {
                [MugenDeejWindowing.MugenMediaKeys]::VolumeUp()
                Write-Log (
                    'Button action: Windows volume up; transport=WM_APPCOMMAND; button={0}' -f
                    ($ButtonIndex + 1)
                ) 'INFO'
                return
            }

            'system:volumedown' {
                [MugenDeejWindowing.MugenMediaKeys]::VolumeDown()
                Write-Log (
                    'Button action: Windows volume down; transport=WM_APPCOMMAND; button={0}' -f
                    ($ButtonIndex + 1)
                ) 'INFO'
                return
            }

            'system:volumemute' {
                [MugenDeejWindowing.MugenMediaKeys]::VolumeMute()
                Write-Log (
                    'Button action: Windows volume mute toggle; transport=WM_APPCOMMAND; button={0}' -f
                    ($ButtonIndex + 1)
                ) 'INFO'
                return
            }
        }
    }
    catch {
        Write-Log (
            'Button fixed action failed: button={0}; action={1}; error={2}' -f
            ($ButtonIndex + 1),
            $action,
            $_.Exception.Message
        ) 'WARN'

        return
    }

    Write-Log (
        'Unknown button action ignored: button={0}; action={1}' -f
        ($ButtonIndex + 1),
        $action
    ) 'WARN'
}
function Show-ButtonSettings {
    if (
        -not $script:IsConnected -or
        $script:DetectedButtonCount -le 0
    ) {
        [System.Windows.Forms.MessageBox]::Show(
            (Get-ButtonFeatureText -Key 'NoButtons'),
            'Mugen Deej',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null

        return
    }

    Normalize-ButtonActions -Count $script:DetectedButtonCount

    $pendingActions = @()

    foreach ($action in @($script:ButtonActions)) {
        $pendingActions += [string]$action
    }

    $buttonForm = New-Object System.Windows.Forms.Form
    $buttonForm.Text = Get-ButtonFeatureText -Key 'Title'
    $buttonForm.StartPosition = 'CenterParent'
    $buttonForm.ClientSize = [System.Drawing.Size]::new(720, 500)
    $buttonForm.MinimumSize = [System.Drawing.Size]::new(736, 539)
    $buttonForm.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $buttonForm.FormBorderStyle = 'FixedDialog'
    $buttonForm.MaximizeBox = $false
    $buttonForm.MinimizeBox = $false

    Set-FormAppIcon -Form $buttonForm

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-ButtonFeatureText -Key 'Heading'
    $heading.Font = New-Object System.Drawing.Font(
        'Segoe UI Semibold',
        16
    )
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $buttonForm.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label

    if ($script:Language -eq 'ru') {
        $hint.Text = 'Назначьте каждой физической кнопке действие: регулятор, медиакоманду, системную громкость, горячую клавишу, запуск программы / файла, папки, URL или команды Windows.'
    }
    else {
        $hint.Text = 'Assign each physical button an action: control mute, media, system volume, a hotkey, launch a program / file, folder, URL, or Windows command.'
    }

    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(660, 43)
    $buttonForm.Controls.Add($hint)

    $saveNotice = New-Object System.Windows.Forms.Label

    if ($script:Language -eq 'ru') {
        $saveNotice.Text = 'Важно: выбранные действия начнут работать только после нажатия «Сохранить».'
    }
    else {
        $saveNotice.Text = 'Important: selected actions take effect only after you click Save.'
    }

    $saveNotice.Font = New-Object System.Drawing.Font(
        'Segoe UI Semibold',
        9.5
    )
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(
        230,
        170,
        70
    )
    $saveNotice.Location = [System.Drawing.Point]::new(25, 101)
    $saveNotice.Size = [System.Drawing.Size]::new(660, 27)
    $buttonForm.Controls.Add($saveNotice)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = [System.Drawing.Point]::new(22, 132)
    $panel.Size = [System.Drawing.Size]::new(676, 296)
    $panel.AutoScroll = $true
    $buttonForm.Controls.Add($panel)

    $settingsIndicators = @()

    $sliderCount = [Math]::Min(
        [int]$script:DetectedSliderCount,
        [int]$script:Config.sliders.Count
    )

    for ($i = 0; $i -lt $script:DetectedButtonCount; $i++) {
        $y = 8 + ($i * 46)

        $label = New-Object System.Windows.Forms.Label
        $label.Text = (
            (Get-ButtonFeatureText -Key 'ButtonN') +
            ' ' +
            ($i + 1)
        )
        $label.Location = [System.Drawing.Point]::new(8, ($y + 4))
        $label.Size = [System.Drawing.Size]::new(92, 28)
        $panel.Controls.Add($label)

        $indicator = New-Object System.Windows.Forms.Label
        $indicator.Text = '●'
        $indicator.Location = [System.Drawing.Point]::new(101, ($y + 3))
        $indicator.Size = [System.Drawing.Size]::new(28, 28)
        $indicator.TextAlign = 'MiddleCenter'
        $indicator.Font = New-Object System.Drawing.Font(
            'Segoe UI',
            13
        )
        $panel.Controls.Add($indicator)
        $settingsIndicators += $indicator

        $combo = New-Object MugenDeejWindowing.MugenComboBox
        $combo.DropDownStyle = 'DropDownList'
        $combo.Location = [System.Drawing.Point]::new(136, $y)
        $combo.Size = [System.Drawing.Size]::new(508, 30)

        $state = [pscustomobject]@{
            Row = $i
            ActionMap = New-Object System.Collections.ArrayList
            Suppress = $true
        }

        $combo.Tag = $state

        [void]$combo.Items.Add(
            (Get-ButtonFeatureText -Key 'None')
        )
        [void]$state.ActionMap.Add('none')

        for ($sliderIndex = 0; $sliderIndex -lt $sliderCount; $sliderIndex++) {
            $name = [string]$script:Config.sliders[$sliderIndex].name

            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = [string]($sliderIndex + 1)
            }

            $display = (
                (Get-ButtonFeatureText -Key 'MuteControl') +
                ' ' +
                ($sliderIndex + 1) +
                ' — ' +
                $name
            )

            [void]$combo.Items.Add($display)
            [void]$state.ActionMap.Add(('mute:' + $sliderIndex))
        }

        foreach ($fixedAction in @(
            @('PlayPause', 'media:playpause'),
            @('PreviousTrack', 'media:previous'),
            @('NextTrack', 'media:next'),
            @('StopPlayback', 'media:stop'),
            @('VolumeUp', 'system:volumeup'),
            @('VolumeDown', 'system:volumedown'),
            @('VolumeMute', 'system:volumemute')
        )) {
            [void]$combo.Items.Add(
                (Get-ButtonFeatureText -Key $fixedAction[0])
            )

            [void]$state.ActionMap.Add(
                [string]$fixedAction[1]
            )
        }

        $action = [string]$pendingActions[$i]

        if (
            $action -match '^hotkey:\d{1,3}:\d{1,2}$' -or
            $action -match '^launch64:.+$' -or
            $action -match '^folder64:.+$' -or
            $action -match '^command64:.+$' -or
            $action -match '^url64:.+$'
        ) {
            $dynamicDisplay = if ($action -match '^hotkey:') {
                Get-HotkeyActionDisplay -Action $action
            }
            elseif ($action -match '^launch64:') {
                Get-LaunchActionDisplay -Action $action
            }
            elseif ($action -match '^folder64:') {
                Get-FolderActionDisplay -Action $action
            }
            elseif ($action -match '^command64:') {
                Get-CommandActionDisplay -Action $action
            }
            else {
                Get-UrlActionDisplay -Action $action
            }

            [void]$combo.Items.Add($dynamicDisplay)
            [void]$state.ActionMap.Add($action)
        }

        [void]$combo.Items.Add(
            (Get-ButtonFeatureText -Key 'HotkeyConfigure')
        )
        [void]$state.ActionMap.Add('hotkey:configure')

        if ($script:Language -eq 'ru') {
            [void]$combo.Items.Add('Запустить программу / файл…')
            [void]$combo.Items.Add('Открыть папку…')
            [void]$combo.Items.Add('Выполнить команду…')
            [void]$combo.Items.Add('Открыть URL…')
        }
        else {
            [void]$combo.Items.Add('Launch program / file…')
            [void]$combo.Items.Add('Open folder…')
            [void]$combo.Items.Add('Run command…')
            [void]$combo.Items.Add('Open URL…')
        }

        [void]$state.ActionMap.Add('launch:configure')
        [void]$state.ActionMap.Add('folder:configure')
        [void]$state.ActionMap.Add('command:configure')
        [void]$state.ActionMap.Add('url:configure')

        $selected = -1

        for (
            $mapIndex = 0;
            $mapIndex -lt $state.ActionMap.Count;
            $mapIndex++
        ) {
            if (
                [string]$state.ActionMap[$mapIndex] -eq
                $action
            ) {
                $selected = $mapIndex
                break
            }
        }

        if ($selected -lt 0) {
            $selected = 0
            $pendingActions[$i] = 'none'
        }

        $combo.SelectedIndex = $selected
        $state.Suppress = $false

        $combo.Add_SelectedIndexChanged({
            param($sender, $eventArgs)

            $comboState = $sender.Tag

            if ($comboState.Suppress) {
                return
            }

            $row = [int]$comboState.Row
            $selectedIndex = [int]$sender.SelectedIndex

            if (
                $selectedIndex -lt 0 -or
                $selectedIndex -ge $comboState.ActionMap.Count
            ) {
                return
            }

            $selectedAction = [string]$comboState.ActionMap[
                $selectedIndex
            ]

            if (
                $selectedAction -notin @(
                    'hotkey:configure',
                    'launch:configure',
                    'folder:configure',
                    'command:configure',
                    'url:configure'
                )
            ) {
                $pendingActions[$row] = $selectedAction
                return
            }

            $previousAction = [string]$pendingActions[$row]
            $configuredAction = $null

            switch ($selectedAction) {
                'hotkey:configure' {
                    $configuredAction = Show-HotkeyEditor `
                        -ExistingAction $previousAction
                }

                'launch:configure' {
                    $configuredAction = Select-LaunchTargetAction `
                        -ExistingAction $previousAction
                }

                'folder:configure' {
                    $configuredAction = Select-FolderTargetAction `
                        -ExistingAction $previousAction
                }

                'command:configure' {
                    $configuredAction = Show-CommandActionEditor `
                        -ExistingAction $previousAction
                }

                'url:configure' {
                    $configuredAction = Show-UrlActionEditor `
                        -ExistingAction $previousAction
                }
            }

            $comboState.Suppress = $true

            try {
                if (
                    [string]::IsNullOrWhiteSpace($configuredAction)
                ) {
                    $restoreIndex = -1

                    for (
                        $j = 0;
                        $j -lt $comboState.ActionMap.Count;
                        $j++
                    ) {
                        if (
                            [string]$comboState.ActionMap[$j] -eq
                            $previousAction
                        ) {
                            $restoreIndex = $j
                            break
                        }
                    }

                    if ($restoreIndex -lt 0) {
                        $restoreIndex = 0
                    }

                    $sender.SelectedIndex = $restoreIndex
                    return
                }

                $configuredAction = [string]$configuredAction
                $pendingActions[$row] = $configuredAction

                $dynamicIndex = -1
                $firstConfigureIndex = -1

                for (
                    $j = 0;
                    $j -lt $comboState.ActionMap.Count;
                    $j++
                ) {
                    $mappedAction = [string]$comboState.ActionMap[$j]

                    if (
                        $mappedAction -match '^hotkey:' -or
                        $mappedAction -match '^launch64:' -or
                        $mappedAction -match '^folder64:' -or
                        $mappedAction -match '^command64:' -or
                        $mappedAction -match '^url64:'
                    ) {
                        $dynamicIndex = $j
                    }

                    if (
                        $firstConfigureIndex -lt 0 -and
                        $mappedAction -in @(
                            'hotkey:configure',
                            'launch:configure',
                            'folder:configure',
                            'command:configure',
                            'url:configure'
                        )
                    ) {
                        $firstConfigureIndex = $j
                    }
                }

                $display = if (
                    $configuredAction -match '^hotkey:'
                ) {
                    Get-HotkeyActionDisplay `
                        -Action $configuredAction
                }
                elseif (
                    $configuredAction -match '^launch64:'
                ) {
                    Get-LaunchActionDisplay `
                        -Action $configuredAction
                }
                elseif (
                    $configuredAction -match '^folder64:'
                ) {
                    Get-FolderActionDisplay `
                        -Action $configuredAction
                }
                elseif (
                    $configuredAction -match '^command64:'
                ) {
                    Get-CommandActionDisplay `
                        -Action $configuredAction
                }
                else {
                    Get-UrlActionDisplay `
                        -Action $configuredAction
                }

                if ($dynamicIndex -ge 0) {
                    $comboState.ActionMap[$dynamicIndex] =
                        $configuredAction

                    $sender.Items[$dynamicIndex] = $display
                }
                else {
                    if ($firstConfigureIndex -lt 0) {
                        $firstConfigureIndex = $sender.Items.Count
                    }

                    $comboState.ActionMap.Insert(
                        $firstConfigureIndex,
                        $configuredAction
                    )

                    $sender.Items.Insert(
                        $firstConfigureIndex,
                        $display
                    )

                    $dynamicIndex = $firstConfigureIndex
                }

                $sender.SelectedIndex = $dynamicIndex
            }
            finally {
                $comboState.Suppress = $false
            }
        })

        $panel.Controls.Add($combo)
    }

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(472, 447)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(588, 447)
    $save.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($save)

    $save.Add_Click({
        $script:ButtonActions = @($pendingActions)
        Save-ButtonActions

        $buttonForm.DialogResult =
            [System.Windows.Forms.DialogResult]::OK

        $buttonForm.Close()
    })

    $liveButtonTimer = New-Object System.Windows.Forms.Timer
    $liveButtonTimer.Interval = 25

    $liveButtonTimer.Add_Tick({
        for (
            $i = 0;
            $i -lt $settingsIndicators.Count;
            $i++
        ) {
            Set-ButtonIndicatorAppearance `
                -Indicator $settingsIndicators[$i] `
                -ButtonIndex $i `
                -DotOnly
        }
    })

    Apply-ThemeToForm -Form $buttonForm

    # Keep the Save note as a semantic amber accent after theme application.
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(
        230,
        170,
        70
    )

    for (
        $i = 0;
        $i -lt $settingsIndicators.Count;
        $i++
    ) {
        Set-ButtonIndicatorAppearance `
            -Indicator $settingsIndicators[$i] `
            -ButtonIndex $i `
            -DotOnly
    }

    $buttonForm.Add_Shown({
        Ensure-FormVisible `
            -Form $buttonForm `
            -CenterIfOffscreen

        $liveButtonTimer.Start()
    })

    $buttonForm.Add_FormClosed({
        $liveButtonTimer.Stop()
        $liveButtonTimer.Dispose()
    })

    $buttonForm.AcceptButton = $save
    $buttonForm.CancelButton = $cancel

    [void]$buttonForm.ShowDialog($form)
    $buttonForm.Dispose()
}
function Test-ControllerPacketMatchesCapabilities {
    param([Parameter(Mandatory = $true)]$Packet)

    if ($script:ControllerProtocol -eq 'unknown' -or $script:DetectedSliderCount -le 0) {
        return $true
    }

    return (
        [string]$Packet.Protocol -eq $script:ControllerProtocol -and
        @($Packet.Sliders).Count -eq $script:DetectedSliderCount -and
        @($Packet.Buttons).Count -eq $script:DetectedButtonCount
    )
}

function Close-ControllerPort {
    param(
        [string]$Reason = '',
        [switch]$Detailed
    )

    $serial = $script:Serial
    $portName = [string]$script:ConnectedPort
    if ([string]::IsNullOrWhiteSpace($portName) -and $null -ne $serial) {
        try { $portName = [string]$serial.PortName } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($portName)) { $portName = '(none)' }

    if ($Detailed) {
        Write-Log ("Controller-port cleanup started; reason={0}; port={1}; objectPresent={2}" -f $Reason, $portName, ($null -ne $serial)) 'INFO'
    }

    if ($null -ne $serial) {
        try {
            if ($serial.IsOpen) {
                $serial.Close()
                if ($Detailed) { Write-Log ("SerialPort.Close completed for {0}" -f $portName) 'INFO' }
            }
            elseif ($Detailed) {
                Write-Log ("SerialPort for {0} was already closed" -f $portName) 'DEBUG'
            }
        }
        catch {
            Write-Log ("SerialPort.Close failed for {0}: {1}" -f $portName, $_.Exception.Message) 'WARN'
        }

        try {
            $serial.Dispose()
            if ($Detailed) { Write-Log ("SerialPort.Dispose completed for {0}" -f $portName) 'INFO' }
        }
        catch {
            Write-Log ("SerialPort.Dispose failed for {0}: {1}" -f $portName, $_.Exception.Message) 'WARN'
        }
    }
    elseif ($Detailed) {
        Write-Log ("No active controller SerialPort object existed for {0}" -f $portName) 'DEBUG'
    }

    $script:Serial = $null
    $script:SerialBuffer = ''
    $script:IsConnected = $false
    $script:ConnectedPort = ''
    $script:LastSerialPacketAt = [DateTime]::MinValue
    $script:LatestLevels = @()
    $script:ControllerProtocol = 'unknown'
    $script:DetectedSliderCount = 0
    $script:DetectedButtonCount = 0
    $script:LatestButtons = @()
    $script:LastButtonStates = @()
    if ($Detailed) {
        Write-Log ("Controller-port cleanup completed; reason={0}; port={1}" -f $Reason, $portName) 'INFO'
    }
}

function Cancel-ActivePortProbe {
    param(
        [string]$Reason = '',
        [switch]$Detailed
    )

    $script:ProbeGeneration++
    $probe = $script:ActiveProbeSerial
    $script:ActiveProbeSerial = $null
    $probePort = '(none)'
    if ($null -ne $probe) {
        try { $probePort = [string]$probe.PortName } catch { }
    }

    if ($Detailed) {
        Write-Log ("Probe cleanup started; reason={0}; port={1}; objectPresent={2}" -f $Reason, $probePort, ($null -ne $probe)) 'INFO'
    }

    if ($null -ne $probe) {
        try {
            if ($probe.IsOpen) {
                $probe.Close()
                if ($Detailed) { Write-Log ("Probe SerialPort.Close completed for {0}" -f $probePort) 'INFO' }
            }
        }
        catch {
            Write-Log ("Probe SerialPort.Close failed for {0}: {1}" -f $probePort, $_.Exception.Message) 'WARN'
        }
        try {
            $probe.Dispose()
            if ($Detailed) { Write-Log ("Probe SerialPort.Dispose completed for {0}" -f $probePort) 'INFO' }
        }
        catch {
            Write-Log ("Probe SerialPort.Dispose failed for {0}: {1}" -f $probePort, $_.Exception.Message) 'WARN'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        Write-Log ("Active COM-port probe cancelled: {0}" -f $Reason) 'DEBUG'
    }

    if ($Detailed) {
        Write-Log ("Probe cleanup completed; reason={0}; port={1}" -f $Reason, $probePort) 'INFO'
    }
}

function Test-ConnectionWorkCancelled {
    param([int]$Generation)

    return (
        $script:Closing -or
        $script:ExitRequested -or
        $script:IsSuspended -or
        $Generation -ne $script:ProbeGeneration
    )
}

function Open-And-ProbePort {
    param([Parameter(Mandatory = $true)][string]$PortName)

    $probeGeneration = $script:ProbeGeneration
    if (Test-ConnectionWorkCancelled -Generation $probeGeneration) { return $false }

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

    $accepted = $false
    $cancelled = $false
    $script:ActiveProbeSerial = $serial

    try {
        if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
            $cancelled = $true
            return $false
        }

        Write-Log "Probing $PortName"
        $serial.Open()

        if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
            $cancelled = $true
            return $false
        }

        if ($script:PortProbeFailureCounts.ContainsKey($PortName)) {
            [void]$script:PortProbeFailureCounts.Remove($PortName)
        }

        $deadline = (Get-Date).AddMilliseconds([int]$script:Config.connection.startupWaitMs + 2800)
        $readyAfter = (Get-Date).AddMilliseconds([int]$script:Config.connection.startupWaitMs)
        $buffer = ''
        $candidateSignature = ''
        $candidateHits = 0

        while ((Get-Date) -lt $deadline) {
            [System.Windows.Forms.Application]::DoEvents()

            if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
                $cancelled = $true
                return $false
            }

            Start-Sleep -Milliseconds 40

            if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
                $cancelled = $true
                return $false
            }

            if ((Get-Date) -lt $readyAfter) { continue }

            $chunk = $serial.ReadExisting()
            if ($chunk.Length -eq 0) { continue }

            $buffer += $chunk
            while ($buffer.Contains("`n")) {
                $idx = $buffer.IndexOf("`n")
                $line = $buffer.Substring(0, $idx).Trim("`r", "`n", " ", "`t")
                $buffer = $buffer.Substring($idx + 1)
                $parsed = Test-ControllerProtocolLine -Line $line

                if ($null -ne $parsed) {
                    $signature = Get-ControllerPacketSignature -Packet $parsed
                    if ($signature -eq $candidateSignature) {
                        $candidateHits++
                    }
                    else {
                        $candidateSignature = $signature
                        $candidateHits = 1
                    }

                    $requiredHits = if ([string]$parsed.Protocol -eq 'extended') { 2 } else { 3 }
                    if ($candidateHits -lt $requiredHits) { continue }

                    Set-DetectedControllerCapabilities -Packet $parsed -PortName $PortName
                    Initialize-ButtonStates -Values @($parsed.Buttons)
                    if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
                        $cancelled = $true
                        return $false
                    }

                    $script:Serial = $serial
                    $script:ActiveProbeSerial = $null
                    $script:SerialBuffer = $buffer
                    $script:IsConnected = $true
                    $script:ConnectedPort = $PortName
                    $script:ResumeAutoReconnectSuppressed = $false
                    $script:ControllerRecoveryPort = ''
                    $script:ControllerRecoveryAt = [DateTime]::MinValue
                    $script:ControllerRecoveryFastUntil = [DateTime]::MinValue
                    $script:LastSerialPacketAt = Get-Date
                    $script:Config.connection.lastWorkingPort = $PortName
                    Clear-PortProbeCooldown -PortName $PortName
                    $script:PendingNewPorts = @($script:PendingNewPorts | Where-Object { $_ -ne $PortName })
                    Save-Config -Config $script:Config
                    Write-Log "Controller detected on $PortName"
                    $accepted = $true
                    return $true
                }
            }
        }

        if (-not (Test-ConnectionWorkCancelled -Generation $probeGeneration)) {
            Write-Log "$PortName opened, but Mugen Deej protocol was not detected" 'WARN'
            Set-PortProbeCooldown -PortName $PortName -Seconds $script:NegativeProbeCooldownSeconds
        }
        else {
            $cancelled = $true
        }
    }
    catch {
        if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
            $cancelled = $true
        }
        else {
            $diagnostic = Get-ExceptionDiagnosticText -ErrorRecord $_
            if (Test-IsPortBusyError -ErrorRecord $_) {
                if ($script:LastScanBusyPorts -notcontains $PortName) {
                    $script:LastScanBusyPorts += $PortName
                }
                $retrySeconds = Register-PortProbeFailure -PortName $PortName -Busy
                Write-Log "$PortName is busy or unavailable; $diagnostic; retry in $retrySeconds s" 'WARN'
            }
            else {
                $retrySeconds = Register-PortProbeFailure -PortName $PortName
                Write-Log "Failed to open ${PortName}; $diagnostic; retry in $retrySeconds s" 'WARN'
            }
        }
    }
    finally {
        if ($script:ActiveProbeSerial -eq $serial) {
            $script:ActiveProbeSerial = $null
        }

        if (-not $accepted) {
            try { if ($serial.IsOpen) { $serial.Close() } } catch { }
            try { $serial.Dispose() } catch { }
        }

        if ($cancelled) {
            Write-Log ("Probe of {0} ended because connection work was cancelled" -f $PortName) 'DEBUG'
        }
    }

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

    if ($script:IsSuspended -or $script:Closing -or $script:ExitRequested) {
        Write-Log 'Connection scan skipped because the application is suspended or closing' 'DEBUG'
        return $false
    }

    # Open-And-ProbePort pumps WinForms messages while waiting for a controller
    # to become ready. The guard prevents nested scans, while ProbeGeneration
    # lets suspend/exit events cancel the active probe cleanly.
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

        if (Test-ConnectionWorkCancelled -Generation $script:ProbeGeneration) { return $false }

        if ($ports.Count -eq 0) {
            if (-not $Quiet) { Set-Status (T -Key 'StatusNoPorts') 'warn' }
            return $false
        }

        if (-not $Quiet) { Set-Status (T -Key 'StatusSearching') 'busy' }

        foreach ($port in $ports) {
            if (Test-ConnectionWorkCancelled -Generation $script:ProbeGeneration) { return $false }
            if (-not $Quiet) { Set-Status (T -Key 'StatusCheckingPort' -Args @($port)) 'busy' }

            if (Open-And-ProbePort -PortName $port) {
                if (Test-ConnectionWorkCancelled -Generation $script:ProbeGeneration) {
                    Close-ControllerPort
                    return $false
                }

                Set-Status (Get-ControllerConnectedStatusText -PortName $port) 'ok'
                Update-TrayText
                Update-DriverStatus
                return $true
            }
        }

        if (Test-ConnectionWorkCancelled -Generation $script:ProbeGeneration) { return $false }

        if ($script:IsConnected -and $null -ne $script:Serial -and $script:Serial.IsOpen) {
            Set-Status (Get-ControllerConnectedStatusText -PortName $script:ConnectedPort) 'ok'
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

        if ($null -ne $connectButton -and -not $connectButton.IsDisposed) {
            $connectButton.Enabled = (-not $script:Closing -and -not $script:IsSuspended)
        }

        if ($script:ExitRequested -and -not $script:ShutdownFinalizing -and $null -ne $form -and -not $form.IsDisposed) {
            $script:ShutdownFinalizing = $true
            $form.Close()
        }
    }
}

function Apply-SliderValues {
    param([int[]]$Values)

    if ($null -eq $Values -or $Values.Count -lt 1) { return }
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
        if ($script:SoftMutedSliders.ContainsKey($i)) {
            continue
        }

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

    $lostPort = [string]$script:ConnectedPort
    if ([string]::IsNullOrWhiteSpace($lostPort)) {
        $lostPort = [string]$script:Config.connection.lastWorkingPort
    }

    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        Write-Log (
            'Serial connection lost: {0}' -f
            $Reason
        ) 'WARN'
    }

    Clear-SoftMutesAfterControllerDisconnect `
        -Reason 'controller disconnected'

    Close-ControllerPort

    [MugenDeejAudio.AudioMixer]::InvalidateSessions()

    $script:LastReconnectAttempt = Get-Date

    # A device can reset, brown out, or disappear/reappear on the same COM name
    # without Windows exposing a clean remove/add edge. Do not let a failed
    # protocol probe put the last known-good controller into a 5-minute cooldown.
    # Keep a bounded fast retry, then a quiet low-frequency targeted retry only
    # against that last known-good COM port until it comes back.
    if (-not [string]::IsNullOrWhiteSpace($lostPort)) {
        $now = Get-Date
        $script:ControllerRecoveryPort = $lostPort
        $script:ControllerRecoveryFastUntil = $now.AddSeconds([int]$script:ControllerRecoveryFastWindowSeconds)
        $script:ControllerRecoveryAt = $now.AddSeconds([int]$script:ControllerRecoveryFastSeconds)
        Reset-PortProbeState -PortName $lostPort
        Write-Log ("Controller recovery armed for {0}; fastWindow={1} s; firstRetryIn={2} s" -f $lostPort, [int]$script:ControllerRecoveryFastWindowSeconds, [int]$script:ControllerRecoveryFastSeconds) 'INFO'
    }

    Set-Status `
        (T -Key 'StatusLost') `
        'warn'

    Update-TrayText
    Update-DriverStatus
}
function Fail-ResumePreservedConnection {
    param([string]$Reason)

    $portName = [string]$script:ConnectedPort
    if ([string]::IsNullOrWhiteSpace($portName)) {
        $portName = [string]$script:ResumePreferredPort
    }

    $elapsedMs = 0
    if ($script:ResumePreserveStartedAt -ne [DateTime]::MinValue) {
        $elapsedMs = [int](((Get-Date) - $script:ResumePreserveStartedAt).TotalMilliseconds)
    }

    Write-Log ("Preserved serial connection did not resume; port={0}; elapsedMs={1}; reason={2}" -f $portName, $elapsedMs, $Reason) 'WARN'
    $script:ResumePreserveUntil = [DateTime]::MinValue
    $script:ResumePreserveStartedAt = [DateTime]::MinValue
    $script:ResumePreserveFirstErrorLogged = $false

    Clear-SoftMutesAfterControllerDisconnect -Reason 'preserved connection failed after resume'
    Close-ControllerPort -Reason 'preserved connection failed after system resume' -Detailed
    [MugenDeejAudio.AudioMixer]::InvalidateSessions()
    $script:LastReconnectAttempt = Get-Date
    $script:ResumeAutoReconnectSuppressed = $true
    $script:ResumeHotplugRetryUntil = [DateTime]::MinValue

    # The stale pre-suspend handle can fail even while Windows has already
    # recreated the same COM number. Treat the previous controller port as
    # unseen after cleanup so the normal 500 ms port-snapshot path gets one
    # fresh, targeted auto-reconnect opportunity. This also catches a very fast
    # unplug/replug where Windows reuses the same COM number between snapshots.
    $currentPorts = @(Get-PortNames)
    $script:KnownPorts = @($currentPorts | Where-Object { $_ -ne $portName })
    $script:PendingNewPorts = @($script:PendingNewPorts | Where-Object { $_ -ne $portName })
    Reset-PortProbeState -PortName $portName
    $script:LastPortSnapshotCheck = [DateTime]::MinValue
    Write-Log ("Resume recovery armed for fresh detection of {0}; currentPorts={1}" -f $portName, ($currentPorts -join ', ')) 'INFO'

    Set-Status (T -Key 'StatusResumeReconnectFailed' -Args @($portName)) 'warn'
    Update-TrayText
    Update-DriverStatus
}

function Process-SerialData {
    $resumePreserveActive = ($script:ResumePreserveUntil -ne [DateTime]::MinValue)
    $now = Get-Date

    if (-not $script:IsConnected -or $null -eq $script:Serial) {
        if ($resumePreserveActive -and $now -ge $script:ResumePreserveUntil) {
            Fail-ResumePreservedConnection -Reason 'The preserved SerialPort object was no longer available'
        }
        return
    }

    if (-not $script:Serial.IsOpen) {
        if ($resumePreserveActive -and $now -lt $script:ResumePreserveUntil) {
            if (-not $script:ResumePreserveFirstErrorLogged) {
                Write-Log ("Preserved SerialPort is temporarily reported closed after resume; port={0}; waiting until deadline" -f $script:ConnectedPort) 'WARN'
                $script:ResumePreserveFirstErrorLogged = $true
            }
            return
        }

        if ($resumePreserveActive) {
            Fail-ResumePreservedConnection -Reason 'The preserved SerialPort remained closed until the resume deadline'
        }
        else {
            Handle-ControllerConnectionLost -Reason 'Serial port is no longer open'
        }
        return
    }

    try {
        $chunk = $script:Serial.ReadExisting()
        if ($chunk.Length -gt 0) {
            $script:SerialBuffer += $chunk
        }

        # Controllers can send packets much faster than Windows audio sessions need updates.
        # Keep only the newest complete packet so slow browser session enumeration
        # cannot build a several-second queue of obsolete knob positions.
        $latestParsed = $null
        while ($script:SerialBuffer.Contains("`n")) {
            $idx = $script:SerialBuffer.IndexOf("`n")
            $line = $script:SerialBuffer.Substring(0, $idx).Trim("`r", "`n", " ", "`t")
            $script:SerialBuffer = $script:SerialBuffer.Substring($idx + 1)
            $parsed = Test-ControllerProtocolLine -Line $line
            if ($null -ne $parsed) {
                if (Test-ControllerPacketMatchesCapabilities -Packet $parsed) {
                    Update-ButtonStates -Values @($parsed.Buttons)
                    $latestParsed = $parsed
                }
                else {
                    $nowMismatch = Get-Date
                    if (
                        $script:LastCapabilityMismatchLog -eq [DateTime]::MinValue -or
                        ($nowMismatch - $script:LastCapabilityMismatchLog).TotalSeconds -ge 5
                    ) {
                        Write-Log (
                            'Ignored packet whose shape changed while connected: expected={0}:{1}:{2}; got={3}' -f
                            $script:ControllerProtocol,
                            $script:DetectedSliderCount,
                            $script:DetectedButtonCount,
                            (Get-ControllerPacketSignature -Packet $parsed)
                        ) 'WARN'
                        $script:LastCapabilityMismatchLog = $nowMismatch
                    }
                }
            }
        }

        if ($null -ne $latestParsed) {
            $script:LastSerialPacketAt = Get-Date

            if ($resumePreserveActive) {
                $elapsedMs = [int](((Get-Date) - $script:ResumePreserveStartedAt).TotalMilliseconds)
                $resumedPort = [string]$script:ConnectedPort
                $script:ResumePreserveUntil = [DateTime]::MinValue
                $script:ResumePreserveStartedAt = [DateTime]::MinValue
                $script:ResumePreserveFirstErrorLogged = $false
                $script:ResumeAutoReconnectSuppressed = $false
                Write-Log ("Existing SerialPort resumed without Close/Open; port={0}; firstValidPacketAfterMs={1}" -f $resumedPort, $elapsedMs) 'INFO'
                Set-Status (Get-ControllerConnectedStatusText -PortName $resumedPort) 'ok'
                Update-TrayText
                Update-DriverStatus
            }

            Apply-SliderValues -Values @($latestParsed.Sliders)
            return
        }

        if ($resumePreserveActive) {
            if ((Get-Date) -lt $script:ResumePreserveUntil) {
                return
            }

            Fail-ResumePreservedConnection -Reason 'No valid controller packets arrived on the preserved SerialPort before the resume deadline'
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
        if ($resumePreserveActive -and (Get-Date) -lt $script:ResumePreserveUntil) {
            if (-not $script:ResumePreserveFirstErrorLogged) {
                $diagnostic = Get-ExceptionDiagnosticText -ErrorRecord $_
                Write-Log ("Preserved SerialPort read failed during resume grace period; port={0}; {1}; continuing to wait" -f $script:ConnectedPort, $diagnostic) 'WARN'
                $script:ResumePreserveFirstErrorLogged = $true
            }
            return
        }

        if ($resumePreserveActive) {
            $diagnostic = Get-ExceptionDiagnosticText -ErrorRecord $_
            Fail-ResumePreservedConnection -Reason ("Serial read still failed at the resume deadline: {0}" -f $diagnostic)
        }
        else {
            Handle-ControllerConnectionLost -Reason $_.Exception.Message
        }
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

    $russianButton = New-Object MugenDeejWindowing.MugenButton
    $russianButton.Text = 'Русский'
    $russianButton.Location = New-Object System.Drawing.Point(32, 128)
    $russianButton.Size = New-Object System.Drawing.Size(238, 54)
    $russianButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $languageForm.Controls.Add($russianButton)

    $englishButton = New-Object MugenDeejWindowing.MugenButton
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
    Apply-ThemeToForm -Form $languageForm
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
$form.ClientSize = New-Object System.Drawing.Size(680, 592)
$form.MinimumSize = New-Object System.Drawing.Size(696, 631)
$form.MaximumSize = New-Object System.Drawing.Size(696, 899)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(247, 247, 249)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
Set-FormAppIcon -Form $form

# When start-minimized is enabled, keep the main form completely invisible
# during its first WinForms show cycle. Application.Run(form) must create/show
# the main form to establish the message loop, but an opacity of 0 together
# with no taskbar button prevents a visible startup flash. The form is hidden
# immediately in Shown and restored to normal display properties for later
# opening from the tray.
$script:ForceShowAfterRestore = ($env:MUGEN_DEEJ_SHOW_AFTER_RESTORE -eq '1')
if ($script:ForceShowAfterRestore) {
    Remove-Item Env:\MUGEN_DEEJ_SHOW_AFTER_RESTORE -ErrorAction SilentlyContinue
    Write-Log 'One-shot visible launch requested after backup restore.' 'INFO'
}
$script:LaunchMinimized = ([bool]$script:Config.app.startMinimized) -and (-not $script:ForceShowAfterRestore)
if ($script:LaunchMinimized) {
    $form.Opacity = 0
    $form.ShowInTaskbar = $false
}

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

$themeLabel = New-Object System.Windows.Forms.Label
$themeLabel.Text = (T -Key 'ThemeLabel')
$themeLabel.Location = New-Object System.Drawing.Point(274, 24)
$themeLabel.Size = New-Object System.Drawing.Size(60, 25)
$themeLabel.TextAlign = 'MiddleRight'
$form.Controls.Add($themeLabel)

$themeCombo = New-Object MugenDeejWindowing.MugenComboBox
$themeCombo.DropDownStyle = 'DropDownList'
$themeCombo.Location = New-Object System.Drawing.Point(340, 21)
$themeCombo.Size = New-Object System.Drawing.Size(110, 29)
$form.Controls.Add($themeCombo)
$script:ThemeCombo = $themeCombo

$languageLabel = New-Object System.Windows.Forms.Label
$languageLabel.Text = (T -Key 'LanguageLabel')
$languageLabel.Location = New-Object System.Drawing.Point(456, 24)
$languageLabel.Size = New-Object System.Drawing.Size(84, 25)
$languageLabel.TextAlign = 'MiddleRight'
$form.Controls.Add($languageLabel)

$languageCombo = New-Object MugenDeejWindowing.MugenComboBox
$languageCombo.DropDownStyle = 'DropDownList'
$languageCombo.Location = New-Object System.Drawing.Point(545, 21)
$languageCombo.Size = New-Object System.Drawing.Size(110, 29)
[void]$languageCombo.Items.Add('Русский')
[void]$languageCombo.Items.Add('English')
$languageCombo.SelectedIndex = if ($script:Language -eq 'ru') { 0 } else { 1 }
$form.Controls.Add($languageCombo)

$statusPanel = New-Object MugenDeejWindowing.MugenCardPanel
$statusPanel.Location = New-Object System.Drawing.Point(24, 88)
$statusPanel.Size = New-Object System.Drawing.Size(632, 60)
$statusPanel.BackColor = [System.Drawing.Color]::White
$statusPanel.BorderStyle = 'None'
$form.Controls.Add($statusPanel)

$statusDot = New-Object System.Windows.Forms.Label
$statusDot.Text = '●'
$statusDot.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 9)
$statusDot.AutoSize = $false
$statusDot.Size = New-Object System.Drawing.Size(16, 16)
$statusDot.TextAlign = 'MiddleCenter'
$statusDot.Location = New-Object System.Drawing.Point(15, 22)
$statusPanel.Controls.Add($statusDot)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = (T -Key 'Starting')
$statusLabel.AutoSize = $false
$statusLabel.Size = New-Object System.Drawing.Size(560, 38)
$statusLabel.Location = New-Object System.Drawing.Point(46, 10)
$statusLabel.TextAlign = 'MiddleLeft'
$statusPanel.Controls.Add($statusLabel)

$knobGroup = New-Object MugenDeejWindowing.MugenGroupBox
$knobGroup.Text = (T -Key 'KnobStatus')
$knobGroup.Location = New-Object System.Drawing.Point(24, 160)
$knobGroup.Size = New-Object System.Drawing.Size(632, 184)
$form.Controls.Add($knobGroup)

for ($i = 0; $i -lt 5; $i++) {
    $y = 34 + ($i * 29)
    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.Text = (T -Key 'KnobN' -Args @($i + 1))
    $nameLabel.Location = New-Object System.Drawing.Point(16, $y)
    $nameLabel.Size = New-Object System.Drawing.Size(170, 23)
    $nameLabel.AutoEllipsis = $true
    $knobGroup.Controls.Add($nameLabel)
    $script:KnobNameLabels += $nameLabel

    $bar = New-Object MugenDeejWindowing.MugenProgressBar
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

# dev3: leave room for a persistent bilingual mute label.
foreach ($bar in @($script:KnobProgressBars)) {
    $bar.Size = [System.Drawing.Size]::new(280, 21)
}
foreach ($percent in @($script:KnobPercentLabels)) {
    $percent.Location = [System.Drawing.Point]::new(480, $percent.Location.Y)
    $percent.Size = [System.Drawing.Size]::new(126, 23)
}

$buttonStateGroup = New-Object MugenDeejWindowing.MugenGroupBox
$buttonStateGroup.Text = Get-ButtonFeatureText -Key 'ButtonStatus'
$buttonStateGroup.Location = [System.Drawing.Point]::new(24, 356)
$buttonStateGroup.Size = [System.Drawing.Size]::new(632, 72)
$buttonStateGroup.Visible = $false
$form.Controls.Add($buttonStateGroup)
$script:ButtonStateGroup = $buttonStateGroup

$buttonStateFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonStateFlow.Location = [System.Drawing.Point]::new(13, 30)
$buttonStateFlow.Size = [System.Drawing.Size]::new(606, 34)
$buttonStateFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$buttonStateFlow.WrapContents = $false
$buttonStateFlow.AutoScroll = $true
$buttonStateFlow.BackColor = $buttonStateGroup.BackColor
$buttonStateGroup.Controls.Add($buttonStateFlow)
$script:ButtonStateFlow = $buttonStateFlow

$settingsButton = New-Object MugenDeejWindowing.MugenButton
$settingsButton.Text = (T -Key 'ConfigureKnobs')
$settingsButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$settingsButton.Tag = 'MugenPrimary'
$settingsButton.Location = New-Object System.Drawing.Point(24, 360)
$settingsButton.Size = New-Object System.Drawing.Size(230, 42)
$form.Controls.Add($settingsButton)

$buttonSettingsButton = New-Object MugenDeejWindowing.MugenButton
$buttonSettingsButton.Text = Get-ButtonFeatureText -Key 'MainButton'
$buttonSettingsButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$buttonSettingsButton.Location = New-Object System.Drawing.Point(272, 360)
$buttonSettingsButton.Size = New-Object System.Drawing.Size(210, 42)
$buttonSettingsButton.Visible = $false
$form.Controls.Add($buttonSettingsButton)
$script:ButtonSettingsButton = $buttonSettingsButton

$settingsHint = New-Object System.Windows.Forms.Label
$settingsHint.Text = (T -Key 'ConfigureHint')
$settingsHint.ForeColor = [System.Drawing.Color]::DimGray
$settingsHint.Location = New-Object System.Drawing.Point(272, 358)
$settingsHint.Size = New-Object System.Drawing.Size(380, 48)
$settingsHint.TextAlign = 'MiddleLeft'
$form.Controls.Add($settingsHint)
$script:SettingsHintControl = $settingsHint
# dev3 layout hotfix: early button-layout update intentionally deferred

$startupGroup = New-Object MugenDeejWindowing.MugenGroupBox
$startupGroup.Text = (T -Key 'StartupGroup')
$startupGroup.Location = New-Object System.Drawing.Point(24, 414)
$startupGroup.Size = New-Object System.Drawing.Size(632, 90)
$form.Controls.Add($startupGroup)

$startWithWindowsCheck = New-Object System.Windows.Forms.CheckBox
$startWithWindowsCheck.Text = (T -Key 'StartWithWindows')
$startWithWindowsCheck.AutoSize = $true
$startWithWindowsCheck.Location = New-Object System.Drawing.Point(16, 28)
$startWithWindowsCheck.Checked = (Test-StartupEnabled)
$startWithWindowsCheck.Enabled = (Test-Path -LiteralPath $script:ExecutablePath)
$startupGroup.Controls.Add($startWithWindowsCheck)

$startMinimizedCheck = New-Object System.Windows.Forms.CheckBox
$startMinimizedCheck.Text = (T -Key 'StartMinimized')
$startMinimizedCheck.AutoSize = $true
$startMinimizedCheck.Location = New-Object System.Drawing.Point(300, 28)
$startMinimizedCheck.Checked = [bool]$script:Config.app.startMinimized
$startupGroup.Controls.Add($startMinimizedCheck)

$startupDeleteHint = New-Object System.Windows.Forms.Label
$startupDeleteHint.Text = (T -Key 'StartupDeleteHint')
$startupDeleteHint.ForeColor = [System.Drawing.Color]::DimGray
$startupDeleteHint.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$startupDeleteHint.Location = New-Object System.Drawing.Point(18, 56)
$startupDeleteHint.Size = New-Object System.Drawing.Size(590, 22)
$startupDeleteHint.TextAlign = 'MiddleLeft'
$startupGroup.Controls.Add($startupDeleteHint)

$advancedToggle = New-Object MugenDeejWindowing.MugenButton
$advancedToggle.Tag = 'MugenSection'
$advancedToggle.Text = (T -Key 'DiagnosticsClosed')
$advancedToggle.Location = New-Object System.Drawing.Point(24, 516)
$advancedToggle.Size = New-Object System.Drawing.Size(250, 32)
$form.Controls.Add($advancedToggle)

$backupMenuButton = New-Object MugenDeejWindowing.MugenButton
$backupMenuButton.Tag = 'MugenSection'
$backupMenuButton.Text = (T -Key 'BackupMenu')
$backupMenuButton.Location = New-Object System.Drawing.Point(292, 516)
$backupMenuButton.Size = New-Object System.Drawing.Size(250, 32)
$form.Controls.Add($backupMenuButton)
$script:BackupMenuButton = $backupMenuButton

$advancedPanel = New-Object System.Windows.Forms.Panel
$advancedPanel.Location = New-Object System.Drawing.Point(0, 550)
$advancedPanel.Size = New-Object System.Drawing.Size(680, 270)
$advancedPanel.Visible = $false
$form.Controls.Add($advancedPanel)

$connectionGroup = New-Object MugenDeejWindowing.MugenGroupBox
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

$portCombo = New-Object MugenDeejWindowing.MugenComboBox
$portCombo.DropDownStyle = 'DropDownList'
$portCombo.Location = New-Object System.Drawing.Point(220, 58)
$portCombo.Size = New-Object System.Drawing.Size(125, 29)
$connectionGroup.Controls.Add($portCombo)

$refreshButton = New-Object MugenDeejWindowing.MugenButton
$refreshButton.Text = (T -Key 'RefreshList')
$refreshButton.Location = New-Object System.Drawing.Point(356, 56)
$refreshButton.Size = New-Object System.Drawing.Size(145, 32)
$connectionGroup.Controls.Add($refreshButton)

$connectButton = New-Object MugenDeejWindowing.MugenButton
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

$driverGroup = New-Object MugenDeejWindowing.MugenGroupBox
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

$driverButton = New-Object MugenDeejWindowing.MugenButton
$driverButton.Text = (T -Key 'InstallDriver')
$driverButton.Location = New-Object System.Drawing.Point(18, 61)
$driverButton.Size = New-Object System.Drawing.Size(310, 32)
$driverGroup.Controls.Add($driverButton)

$logButton = New-Object MugenDeejWindowing.MugenButton
$logButton.Text = (T -Key 'OpenLog')
$logButton.Location = New-Object System.Drawing.Point(342, 61)
$logButton.Size = New-Object System.Drawing.Size(170, 32)
$driverGroup.Controls.Add($logButton)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = 'Made by Mugen Art Lab'
$footer.ForeColor = [System.Drawing.Color]::Gray
$footer.AutoSize = $true
$footer.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Bottom
$footer.Location = New-Object System.Drawing.Point(24, 564)
$form.Controls.Add($footer)
# dev3 layout hotfix: initialize button layout only after the full main UI exists
Update-ButtonFeatureUi

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
$script:TrayMenu = $trayMenu

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
    $themeLabel.Text = (T -Key 'ThemeLabel')
    $languageLabel.Text = (T -Key 'LanguageLabel')
    Sync-ThemeCombo
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
    $startupGroup.Text = (T -Key 'StartupGroup')
    $startWithWindowsCheck.Text = (T -Key 'StartWithWindows')
    $startMinimizedCheck.Text = (T -Key 'StartMinimized')
    $startupDeleteHint.Text = (T -Key 'StartupDeleteHint')
    $logButton.Text = (T -Key 'OpenLog')
    $trayOpen.Text = (T -Key 'TrayOpen')
    $traySettings.Text = (T -Key 'TraySettings')
    $trayReconnect.Text = (T -Key 'TrayReconnect')
    $trayExit.Text = (T -Key 'TrayExit')
    if ($null -ne $script:BackupMenuButton -and -not $script:BackupMenuButton.IsDisposed) {
        $script:BackupMenuButton.Text = (T -Key 'BackupMenu')
    }
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

$script:TrayTransitionInProgress = $false

function Hide-MainWindowToTray {
    param(
        [string]$Reason = 'tray hide'
    )

    if ($null -eq $form -or $form.IsDisposed) {
        return
    }

    if ($script:TrayTransitionInProgress) {
        Write-Log (
            'Tray transition re-entry suppressed while hiding; reason={0}' -f
            $Reason
        ) 'DEBUG'
        return
    }

    $script:TrayTransitionInProgress = $true

    try {
        # dev13: hide FIRST.
        #
        # dev12 normalized WindowState while the form was still visible.
        # Windows could therefore display one unpainted/restored frame before
        # Hide() completed. Once invisible, changing WindowState or taskbar
        # ownership cannot produce that visible empty-shell flash.
        if ($form.Visible) {
            $form.Hide()
        }

        if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }

        $form.ShowInTaskbar = $false

        Write-Log (
            'Main window hidden to tray; reason={0}; order=hide-first' -f
            $Reason
        ) 'DEBUG'
    }
    catch {
        Write-Log (
            'Failed to hide main window to tray: reason={0}; error={1}' -f
            $Reason,
            $_.Exception.Message
        ) 'WARN'
    }
    finally {
        $script:TrayTransitionInProgress = $false
    }
}
function Show-MainWindowForeground {
    if ($null -eq $form -or $form.IsDisposed) {
        return
    }

    if ($script:TrayTransitionInProgress) {
        Write-Log 'Tray transition re-entry suppressed while restoring' 'DEBUG'
        return
    }

    $script:TrayTransitionInProgress = $true

    try {
        if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }

        $form.ShowInTaskbar = $true
        $form.Opacity = 1

        if (-not $form.Visible) {
            $form.Show()
        }

        Ensure-FormVisible `
            -Form $form `
            -CenterIfOffscreen

        [void][MugenDeejWindowing.Foreground]::ShowWindowAsync(
            $form.Handle,
            9
        )

        $form.TopMost = $true
        $form.BringToFront()

        [void][MugenDeejWindowing.Foreground]::BringWindowToTop(
            $form.Handle
        )

        [void][MugenDeejWindowing.Foreground]::SetForegroundWindow(
            $form.Handle
        )

        $form.Activate()
        [System.Windows.Forms.Application]::DoEvents()
        $form.TopMost = $false

        Write-Log 'Main window restored from tray' 'DEBUG'
    }
    catch {
        Write-Log (
            'Failed to restore main window from tray: {0}' -f
            $_.Exception.Message
        ) 'WARN'
    }
    finally {
        try {
            $form.TopMost = $false
        }
        catch {}

        $script:TrayTransitionInProgress = $false
    }
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
    Update-ButtonFeatureUi

    $themeName = Get-EffectiveTheme
    $palette = $script:ThemePalettes[$themeName]
    $muteColor = Get-MuteStatusColor

    for ($i = 0; $i -lt $script:KnobProgressBars.Count; $i++) {
        if ($script:LatestLevels.Count -gt $i) {
            $level = [Math]::Max(
                0.0,
                [Math]::Min(1.0, [double]$script:LatestLevels[$i])
            )
            $script:KnobProgressBars[$i].Value = [int][Math]::Round($level * 1000)

            if ($script:SoftMutedSliders.ContainsKey($i)) {
                $script:KnobPercentLabels[$i].Text = Get-ButtonFeatureText -Key 'Muted'
                $script:KnobPercentLabels[$i].ForeColor = $muteColor
                $script:KnobPercentLabels[$i].Font = New-Object System.Drawing.Font(
                    'Segoe UI Semibold',
                    9
                )
            }
            else {
                $script:KnobPercentLabels[$i].Text = (
                    '{0}%' -f [int][Math]::Round($level * 100)
                )
                $script:KnobPercentLabels[$i].ForeColor = $palette.Text
                $script:KnobPercentLabels[$i].Font = New-Object System.Drawing.Font(
                    'Segoe UI',
                    10
                )
            }
        }
        else {
            $script:KnobProgressBars[$i].Value = 0
            $script:KnobPercentLabels[$i].Text = '—'
            $script:KnobPercentLabels[$i].ForeColor = $palette.Text
        }
    }

    Update-MainButtonIndicators
}

function Set-AdvancedExpanded {
    param(
        [bool]$Expanded,
        [bool]$Persist = $true
    )

    $advancedPanel.Visible = $Expanded
    $advancedToggle.Text = if ($Expanded) {
        T -Key 'DiagnosticsOpen'
    }
    else {
        T -Key 'DiagnosticsClosed'
    }

    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)
    $offset = if ($hasButtons) { 84 } else { 0 }

    $form.ClientSize = [System.Drawing.Size]::new(
        680,
        $(if ($Expanded) { 860 + $offset } else { 592 + $offset })
    )

    $footer.Location = [System.Drawing.Point]::new(
        24,
        ($form.ClientSize.Height - 28)
    )

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
$initialTheme = Get-EffectiveTheme
Apply-ThemeToForm -Form $form -ThemeName $initialTheme
Apply-ToolStripTheme -ToolStrip $trayMenu -ThemeName $initialTheme
$script:LastEffectiveTheme = $initialTheme

$themeCombo.Add_SelectedIndexChanged({
    if ($script:UpdatingThemeCombo -or $themeCombo.SelectedIndex -lt 0) { return }

    $newTheme = switch ($themeCombo.SelectedIndex) {
        1 { 'light' }
        2 { 'dark' }
        default { 'auto' }
    }
    $previousTheme = Get-NormalizedThemeSetting -Value ([string]$script:Config.app.theme)
    if ($newTheme -eq $previousTheme) { return }

    $script:Config.app.theme = $newTheme
    try {
        Save-Config -Config $script:Config
        [void](Apply-CurrentTheme)
        Write-Log ("Interface theme setting changed: {0} -> {1}" -f $previousTheme, $newTheme) 'INFO'
    }
    catch {
        $script:Config.app.theme = $previousTheme
        Sync-ThemeCombo
        [void](Apply-CurrentTheme)
        Write-Log ("Failed to save interface theme setting: {0}" -f $_.Exception.Message) 'ERROR'
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Mugen Deej',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
})

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
        Set-Status (Get-ControllerConnectedStatusText -PortName $script:ConnectedPort) 'ok'
    }
    else {
        Set-Status (T -Key 'StatusNotConnected') 'idle'
    }
    Write-Log "Interface language changed to $newLanguage"
})

$script:UpdatingStartupCheck = $false
$script:UpdatingStartMinimizedCheck = $false

$startWithWindowsCheck.Add_CheckedChanged({
    if ($script:UpdatingStartupCheck) { return }
    try {
        Set-StartupEnabled -Enabled ([bool]$startWithWindowsCheck.Checked)
    }
    catch {
        Write-Log ("Failed to change Windows startup setting: {0}" -f $_.Exception.Message) 'ERROR'
        $script:UpdatingStartupCheck = $true
        try { $startWithWindowsCheck.Checked = (Test-StartupEnabled) }
        finally { $script:UpdatingStartupCheck = $false }
        [System.Windows.Forms.MessageBox]::Show(
            (T -Key 'StartupSettingsError' -Args @($_.Exception.Message)),
            (T -Key 'StartupSettingsErrorTitle'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
})

$startMinimizedCheck.Add_CheckedChanged({
    if ($script:UpdatingStartMinimizedCheck) { return }
    $previous = [bool]$script:Config.app.startMinimized
    $script:Config.app.startMinimized = [bool]$startMinimizedCheck.Checked
    try {
        Save-Config -Config $script:Config
        Write-Log ("Start minimized setting changed: {0}" -f ([bool]$script:Config.app.startMinimized)) 'INFO'
    }
    catch {
        $script:Config.app.startMinimized = $previous
        $script:UpdatingStartMinimizedCheck = $true
        try { $startMinimizedCheck.Checked = $previous }
        finally { $script:UpdatingStartMinimizedCheck = $false }
        [System.Windows.Forms.MessageBox]::Show(
            (T -Key 'StartupSettingsError' -Args @($_.Exception.Message)),
            (T -Key 'StartupSettingsErrorTitle'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
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

function Handle-PowerModeChange {
    param([Parameter(Mandatory = $true)][string]$ModeName)

    if ($script:Closing -or $script:ExitRequested) { return }

    switch ($ModeName) {
        'Suspend' {
            if ($script:IsSuspended) { return }

            $suspendStarted = Get-Date
            $activePort = [string]$script:ConnectedPort
            if ([string]::IsNullOrWhiteSpace($activePort)) {
                $activePort = [string]$script:Config.connection.lastWorkingPort
            }
            $script:ResumePreferredPort = $activePort

            $serialPresent = ($null -ne $script:Serial)
            $serialIsOpen = $false
            if ($serialPresent) {
                try { $serialIsOpen = [bool]$script:Serial.IsOpen } catch { }
            }

            Write-Log ("System suspend detected; connectedPort={0}; preferredResumePort={1}; scanning={2}; serialObjectPresent={3}; serialIsOpen={4}" -f $script:ConnectedPort, $script:ResumePreferredPort, $script:IsConnecting, $serialPresent, $serialIsOpen) 'INFO'
            $script:IsSuspended = $true
            $script:ControllerRecoveryPort = ''
            $script:ControllerRecoveryAt = [DateTime]::MinValue
            $script:ControllerRecoveryFastUntil = [DateTime]::MinValue
            $script:ResumeReconnectAt = [DateTime]::MinValue
            $script:ResumeHotplugRetryUntil = [DateTime]::MinValue
            $script:ResumeAutoReconnectSuppressed = $true
            $script:ResumePreserveUntil = [DateTime]::MinValue
            $script:ResumePreserveStartedAt = [DateTime]::MinValue
            $script:ResumePreserveFirstErrorLogged = $false

            if ($null -ne $timer) { $timer.Stop() }

            # Preserve the established controller SerialPort across sleep and hibernation.
            # Only an unrelated in-progress discovery probe is cancelled; Windows
            # can restore the existing handle when the system resumes.
            Cancel-ActivePortProbe -Reason 'system suspend; active controller port is intentionally preserved' -Detailed
            [MugenDeejAudio.AudioMixer]::InvalidateSessions()

            $elapsedMs = [int](((Get-Date) - $suspendStarted).TotalMilliseconds)
            Write-Log ("Suspend handler completed without closing the controller SerialPort; elapsedMs={0}; port={1}; objectPresent={2}; isOpen={3}" -f $elapsedMs, $script:ConnectedPort, ($null -ne $script:Serial), $serialIsOpen) 'INFO'
            Set-Status (T -Key 'StatusLost') 'warn'
            Update-TrayText
        }

        'Resume' {
            if ([string]::IsNullOrWhiteSpace($script:ResumePreferredPort)) {
                $script:ResumePreferredPort = [string]$script:Config.connection.lastWorkingPort
            }

            $preserveSeconds = [int]$script:ResumePreserveSeconds
            $serialPresent = ($null -ne $script:Serial)
            $serialIsOpen = $false
            if ($serialPresent) {
                try { $serialIsOpen = [bool]$script:Serial.IsOpen } catch { }
            }

            Write-Log ("System resume detected; preferredResumePort={0}; preserving the existing SerialPort for {1} seconds; objectPresent={2}; isConnected={3}; isOpen={4}" -f $script:ResumePreferredPort, $preserveSeconds, $serialPresent, $script:IsConnected, $serialIsOpen) 'INFO'
            $script:IsSuspended = $false
            [MugenDeejAudio.AudioMixer]::InvalidateSessions()

            $script:ResumeAutoReconnectSuppressed = $true
            $script:ResumeReconnectAt = [DateTime]::MinValue
            $script:ResumeHotplugRetryUntil = [DateTime]::MinValue
            $script:ResumePreserveFirstErrorLogged = $false
            $script:SerialBuffer = ''
            $script:LastSerialPacketAt = Get-Date

            if ($script:IsConnected -and $serialPresent) {
                $script:ResumePreserveStartedAt = Get-Date
                $script:ResumePreserveUntil = (Get-Date).AddSeconds($preserveSeconds)
                Set-Status (T -Key 'StatusResumePreserving' -Args @($script:ResumePreferredPort)) 'busy'
            }
            else {
                # No established connection exists to preserve. Wait briefly,
                # then perform one targeted reconnect attempt instead of immediately
                # scanning every COM port.
                $script:ResumePreserveStartedAt = [DateTime]::MinValue
                $script:ResumePreserveUntil = [DateTime]::MinValue
                $script:ResumeReconnectAt = (Get-Date).AddSeconds([int]$script:ResumeReconnectDelaySeconds)
                Set-Status (T -Key 'StatusResumeWaiting' -Args @([int]$script:ResumeReconnectDelaySeconds)) 'busy'
                Write-Log 'No established SerialPort existed at resume; falling back to one delayed connection attempt' 'WARN'
            }

            Ensure-FormVisible -Form $form -CenterIfOffscreen
            try {
                $form.Invalidate($true)
                $form.Update()
            }
            catch { }

            if ($null -ne $timer -and -not $script:Closing) { $timer.Start() }
        }
    }
}

function Request-AppExit {
    if ($script:ExitRequested) { return }

    $script:Closing = $true
    $script:ExitRequested = $true
    if ($null -ne $timer) { $timer.Stop() }

    Cancel-ActivePortProbe -Reason 'application exit requested'
    Close-ControllerPort

    if ($script:IsConnecting) {
        $form.Hide()
        return
    }

    $script:ShutdownFinalizing = $true
    $form.Close()
}

$backupMenuButton.Add_Click({ Show-MugenDeejBackupMenu -OwnerControl $backupMenuButton })
$advancedToggle.Add_Click({ Set-AdvancedExpanded -Expanded (-not $advancedPanel.Visible) })
$refreshButton.Add_Click({ Refresh-PortList; Update-DriverStatus })
$connectButton.Add_Click({
    $script:ResumeReconnectAt = [DateTime]::MinValue
    $script:ResumeHotplugRetryUntil = [DateTime]::MinValue
    $script:ControllerRecoveryPort = ''
    $script:ControllerRecoveryAt = [DateTime]::MinValue
    $script:ControllerRecoveryFastUntil = [DateTime]::MinValue
    $script:ResumePreserveUntil = [DateTime]::MinValue
    $script:ResumePreserveStartedAt = [DateTime]::MinValue
    $script:ResumePreserveFirstErrorLogged = $false
    $script:ResumeAutoReconnectSuppressed = $false
    [void](Connect-Controller -ForceFullScan)
})
$settingsButton.Add_Click({ Show-SliderSettings })
$buttonSettingsButton.Add_Click({ Show-ButtonSettings })
$driverButton.Add_Click({ Install-Ch340Driver })
$logButton.Add_Click({ Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:LogPath) })

$trayOpen.Add_Click({ Show-MainWindowForeground })
$traySettings.Add_Click({ Show-MainWindowForeground; Show-SliderSettings })
$trayReconnect.Add_Click({
    $script:ResumeReconnectAt = [DateTime]::MinValue
    $script:ResumeHotplugRetryUntil = [DateTime]::MinValue
    $script:ControllerRecoveryPort = ''
    $script:ControllerRecoveryAt = [DateTime]::MinValue
    $script:ControllerRecoveryFastUntil = [DateTime]::MinValue
    $script:ResumePreserveUntil = [DateTime]::MinValue
    $script:ResumePreserveStartedAt = [DateTime]::MinValue
    $script:ResumePreserveFirstErrorLogged = $false
    $script:ResumeAutoReconnectSuppressed = $false
    [void](Connect-Controller -ForceFullScan)
})
$trayExit.Add_Click({ Request-AppExit })
$notifyIcon.Add_DoubleClick({ Show-MainWindowForeground })
# dev11: normalize the hidden main form BEFORE the legacy Resize handler runs.
$form.Add_Resize({
    if (
        $form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized -and
        [bool]$script:Config.app.minimizeToTray
    ) {
        Hide-MainWindowToTray
    }
})

# dev11: X-to-tray safety. The existing FormClosing handler still sets Cancel
# and owns actual shutdown; this pre-handler only guarantees a clean tray state.
$form.Add_FormClosing({
    param($sender, $eventArgs)

    if (
        -not $script:Closing -and
        [bool]$script:Config.app.minimizeToTray
    ) {
        Hide-MainWindowToTray
    }
})

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

    $script:Closing = $true
    $script:ExitRequested = $true

    if ($script:IsConnecting -and -not $script:ShutdownFinalizing) {
        $eventArgs.Cancel = $true
        if ($null -ne $timer) { $timer.Stop() }
        Cancel-ActivePortProbe -Reason 'form closing while a COM-port probe is active'
        Close-ControllerPort
        $form.Hide()
        return
    }

    $script:ShutdownFinalizing = $true
    if ($null -ne $timer) { $timer.Stop() }

    Cancel-ActivePortProbe -Reason 'final application shutdown'

    try { Save-Config -Config $script:Config }
    catch { Write-Log "Final config save on exit failed: $($_.Exception.Message)" 'ERROR' }

    Close-ControllerPort

    if ($null -ne $script:PowerBridge) {
        try { $script:PowerBridge.Dispose() } catch { }
        $script:PowerBridge = $null
    }
    if ($null -ne $script:ThemePreferenceBridge) {
        try { $script:ThemePreferenceBridge.Dispose() } catch { }
        $script:ThemePreferenceBridge = $null
    }

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
    if ($script:IsSuspended -or $script:Closing -or $script:ExitRequested) { return }

    $now = Get-Date

    # During the resume grace period, do not enumerate or open COM ports.
    # Read only from the SerialPort object that existed before hibernation.
    # Process-SerialData clears this state on success or failure.
    if ($script:ResumePreserveUntil -ne [DateTime]::MinValue) {
        Process-SerialData
        Update-KnobMonitor
        return
    }

    if ($script:ResumeReconnectAt -ne [DateTime]::MinValue) {
        if ($now -lt $script:ResumeReconnectAt) {
            Update-KnobMonitor
            return
        }

        # When no established SerialPort existed to preserve, perform one
        # delayed targeted attempt without a broad scan.
        $script:ResumeReconnectAt = [DateTime]::MinValue
        $preferredPort = [string]$script:ResumePreferredPort
        $script:KnownPorts = @(Get-PortNames)
        $script:LastPortSnapshotCheck = Get-Date
        Write-Log ("Resume recovery delay completed; ports={0}; preferredPort={1}; performing one targeted connection attempt" -f ($script:KnownPorts -join ', '), $preferredPort) 'INFO'

        $connected = $false
        if (-not [string]::IsNullOrWhiteSpace($preferredPort) -and $script:KnownPorts -contains $preferredPort) {
            Reset-PortProbeState -PortName $preferredPort
            $connected = [bool](Connect-Controller -Quiet -CandidatePorts @($preferredPort))
        }
        else {
            Write-Log ("The previous working port is not present after the resume quiet period: {0}" -f $preferredPort) 'WARN'
        }

        if ($connected) {
            $script:ResumeHotplugRetryUntil = [DateTime]::MinValue
            $script:ResumeAutoReconnectSuppressed = $false
            Write-Log ("Targeted resume connection attempt succeeded on {0}" -f $preferredPort) 'INFO'
        }
        elseif (
            $script:ResumeHotplugRetryUntil -ne [DateTime]::MinValue -and
            $now -lt $script:ResumeHotplugRetryUntil
        ) {
            $retrySeconds = [int]$script:ResumeHotplugRetrySeconds
            $remainingSeconds = [int][Math]::Ceiling(($script:ResumeHotplugRetryUntil - $now).TotalSeconds)
            $script:ResumeReconnectAt = $now.AddSeconds($retrySeconds)
            $script:ResumeAutoReconnectSuppressed = $true
            Write-Log ("Targeted resume retry on {0} is still not ready; retrying in {1} s; readinessWindowRemaining={2} s" -f $preferredPort, $retrySeconds, $remainingSeconds) 'WARN'
        }
        else {
            $hadReadinessWindow = ($script:ResumeHotplugRetryUntil -ne [DateTime]::MinValue)
            $script:ResumeHotplugRetryUntil = [DateTime]::MinValue
            $script:ResumeAutoReconnectSuppressed = $true

            # Do not get stuck forever if Windows keeps the same COM name in
            # enumeration across unplug/replug. After the fast readiness window
            # expires, keep one low-frequency targeted retry alive only for the
            # previously working port. This avoids broad scans while still
            # honoring the user-facing promise that replugging USB reconnects
            # automatically.
            $slowRetrySeconds = [int]$script:ResumeHotplugSlowRetrySeconds
            $script:ResumeReconnectAt = $now.AddSeconds($slowRetrySeconds)

            if ($hadReadinessWindow) {
                Write-Log ("Resume readiness retry window exhausted for {0}; continuing low-frequency targeted retries every {1} s until the controller returns or the user requests a manual scan" -f $preferredPort, $slowRetrySeconds) 'WARN'
            }
            else {
                Write-Log ("Targeted resume attempt failed on {0}; continuing low-frequency targeted retries every {1} s until the controller returns or the user requests a manual scan" -f $preferredPort, $slowRetrySeconds) 'WARN'
            }
            Set-Status (T -Key 'StatusResumeReconnectFailed' -Args @($preferredPort)) 'warn'
            Update-TrayText
            Update-DriverStatus
        }

        Update-KnobMonitor
        return
    }

    # Ordinary controller-loss recovery. Unlike resume recovery this also
    # handles runtime resets/brownouts and very fast same-COM unplug/replug.
    if (
        -not $script:IsConnected -and
        -not $script:IsConnecting -and
        $script:ControllerRecoveryAt -ne [DateTime]::MinValue -and
        $now -ge $script:ControllerRecoveryAt
    ) {
        $recoveryPort = [string]$script:ControllerRecoveryPort
        if ([string]::IsNullOrWhiteSpace($recoveryPort)) {
            $script:ControllerRecoveryAt = [DateTime]::MinValue
            $script:ControllerRecoveryFastUntil = [DateTime]::MinValue
        }
        else {
            $currentPorts = @(Get-PortNames)
            $connected = $false

            if ($currentPorts -contains $recoveryPort) {
                Reset-PortProbeState -PortName $recoveryPort
                Write-Log ("Controller recovery attempt on {0}; ports={1}" -f $recoveryPort, ($currentPorts -join ', ')) 'INFO'
                $connected = [bool](Connect-Controller -Quiet -CandidatePorts @($recoveryPort))
            }
            else {
                Write-Log ("Controller recovery waiting for {0} to appear; ports={1}" -f $recoveryPort, ($currentPorts -join ', ')) 'DEBUG'
            }

            if (-not $connected) {
                $retrySeconds = if (
                    $script:ControllerRecoveryFastUntil -ne [DateTime]::MinValue -and
                    $now -lt $script:ControllerRecoveryFastUntil
                ) {
                    [int]$script:ControllerRecoveryFastSeconds
                }
                else {
                    [int]$script:ControllerRecoverySlowSeconds
                }

                $script:ControllerRecoveryAt = (Get-Date).AddSeconds($retrySeconds)
                Write-Log ("Controller recovery for {0} still pending; next targeted retry in {1} s" -f $recoveryPort, $retrySeconds) 'DEBUG'
            }

            Update-KnobMonitor
            if ($script:IsConnected) { return }
        }
    }

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
        $resumeSuppressionWasActive = $script:ResumeAutoReconnectSuppressed
        if ($resumeSuppressionWasActive) {
            Write-Log ("New COM device appeared while automatic resume reconnect was suppressed; trying only the new port(s): {0}" -f ($candidatePorts -join ', ')) 'INFO'
        }

        $newPortConnected = [bool](Connect-Controller -Quiet -CandidatePorts $candidatePorts)
        if ($newPortConnected) {
            $script:ResumeAutoReconnectSuppressed = $false
        }
        elseif ($resumeSuppressionWasActive) {
            $preferredPort = [string]$script:ResumePreferredPort
            if (
                -not [string]::IsNullOrWhiteSpace($preferredPort) -and
                $candidatePorts -contains $preferredPort
            ) {
                # Windows can publish the COM device name before CreateFile/Open
                # can actually use it. Start a short bounded readiness window
                # and keep retrying only the preferred resume port.
                $retrySeconds = [int]$script:ResumeHotplugRetrySeconds
                $retryWindowSeconds = [int]$script:ResumeHotplugRetryWindowSeconds
                $retryNow = Get-Date
                $script:ResumeHotplugRetryUntil = $retryNow.AddSeconds($retryWindowSeconds)
                $script:ResumeReconnectAt = $retryNow.AddSeconds($retrySeconds)
                $script:ResumeAutoReconnectSuppressed = $true
                Write-Log ("Fresh resume port {0} appeared but was not ready to open; starting bounded readiness retry window of {1} s; next attempt in {2} s" -f $preferredPort, $retryWindowSeconds, $retrySeconds) 'WARN'
            }
            else {
                $script:ResumeAutoReconnectSuppressed = $true
            }
        }
    }

    if ($script:IsConnected) {
        Process-SerialData
    }
    elseif (-not $script:IsConnecting -and -not $script:ResumeAutoReconnectSuppressed) {
        $seconds = [int]$script:Config.connection.reconnectSeconds
        if (((Get-Date) - $script:LastReconnectAttempt).TotalSeconds -ge $seconds) {
            $script:LastReconnectAttempt = Get-Date
            [void](Connect-Controller -Quiet)
        }
    }
    Update-KnobMonitor
})

$script:PowerUiAction = [System.Action[string]]{
    param($modeName)
    try {
        Handle-PowerModeChange -ModeName $modeName
    }
    catch {
        Write-Log ("Power-mode handler failed for {0}: {1}" -f $modeName, $_.Exception.Message) 'ERROR'
    }
}

$script:PowerBridge = [MugenDeejWindowing.PowerModeBridge]::new($form, $script:PowerUiAction)
Write-Log 'Power suspend/resume monitoring initialized' 'DEBUG'

$script:ThemeUiAction = [System.Action[string]]{
    param($categoryName)
    try {
        Handle-ThemePreferenceChange -CategoryName $categoryName
    }
    catch {
        Write-Log ("Theme preference handler failed for {0}: {1}" -f $categoryName, $_.Exception.Message) 'ERROR'
    }
}
$script:ThemePreferenceBridge = [MugenDeejWindowing.ThemePreferenceBridge]::new($form, $script:ThemeUiAction)
Write-Log 'Windows theme preference monitoring initialized' 'DEBUG'

$form.Add_Shown({
    $startMinimized = ([bool]$script:Config.app.startMinimized) -and (-not $script:ForceShowAfterRestore)
    if ($startMinimized) {
        # Hide before controller discovery/initialization so startup-to-tray does
        # not display the main window while COM probing is in progress.
        $form.Hide()
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $form.ShowInTaskbar = $true
        $form.Opacity = 1
        Write-Log 'Main window suppressed during start-minimized launch' 'DEBUG'
    }
    else {
        Ensure-FormVisible -Form $form -CenterIfOffscreen
        Show-MainWindowForeground
    }

    $script:ResumeAutoReconnectSuppressed = $false
    $script:KnownPorts = @(Get-PortNames)
    $script:LastPortSnapshotCheck = Get-Date
    Update-DriverStatus
    [void](Connect-Controller -ForceFullScan)
    $timer.Start()
    if (-not $startMinimized -and -not [bool]$script:Config.app.firstRunCompleted) {
        Show-FirstRunWizard
    }
})

[System.Windows.Forms.Application]::Run($form)

if ($script:RestartRequested) {
    try {
        Write-Log ('Restarting Mugen Deej via launcher with one-shot visible window: {0}' -f $script:ExecutablePath) 'INFO'
        $env:MUGEN_DEEJ_SHOW_AFTER_RESTORE = '1'
        try {
            Start-Process -FilePath $script:ExecutablePath -WorkingDirectory $script:BaseDir
        }
        finally {
            Remove-Item Env:\MUGEN_DEEJ_SHOW_AFTER_RESTORE -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Log ('Automatic restart failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}
