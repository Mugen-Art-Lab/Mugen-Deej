# Mugen Deej 2.0.0
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

        private bool semanticStateEnabled;
        private bool semanticSelected;
        private bool semanticPressed;
        private Color semanticNormalBackground;
        private Color semanticNormalText;
        private Color semanticNormalBorder;
        private Color semanticPressedBackground;
        private Color semanticPressedText;
        private Color semanticAccentBorder;

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

        public void ApplySemanticStateTheme(
            Color normalBackground,
            Color normalText,
            Color normalBorder,
            Color pressedBackground,
            Color pressedText,
            Color accentBorder,
            bool selected,
            bool pressed)
        {
            bool changed =
                !semanticStateEnabled ||
                semanticSelected != selected ||
                semanticPressed != pressed ||
                semanticNormalBackground.ToArgb() != normalBackground.ToArgb() ||
                semanticNormalText.ToArgb() != normalText.ToArgb() ||
                semanticNormalBorder.ToArgb() != normalBorder.ToArgb() ||
                semanticPressedBackground.ToArgb() != pressedBackground.ToArgb() ||
                semanticPressedText.ToArgb() != pressedText.ToArgb() ||
                semanticAccentBorder.ToArgb() != accentBorder.ToArgb();

            semanticStateEnabled = true;
            semanticSelected = selected;
            semanticPressed = pressed;
            semanticNormalBackground = normalBackground;
            semanticNormalText = normalText;
            semanticNormalBorder = normalBorder;
            semanticPressedBackground = pressedBackground;
            semanticPressedText = pressedText;
            semanticAccentBorder = accentBorder;

            if (changed)
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

            Color fill = BackColor;
            Color text = ForeColor;
            Color border = BorderColor;

            if (semanticStateEnabled)
            {
                fill = semanticPressed ? semanticPressedBackground : semanticNormalBackground;
                text = semanticPressed ? semanticPressedText : semanticNormalText;
                border = (semanticSelected || semanticPressed) ? semanticAccentBorder : semanticNormalBorder;
            }

            using (GraphicsPath path = MugenDrawing.RoundedRect(rect, CornerRadius))
            using (SolidBrush fillBrush = new SolidBrush(fill))
            using (Pen borderPen = new Pen(border))
            {
                e.Graphics.FillPath(fillBrush, path);
                e.Graphics.DrawPath(borderPen, path);
            }

            TextRenderer.DrawText(
                e.Graphics,
                Text,
                Font,
                rect,
                text,
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
    public static class MugenMouseWheel
    {
        private const uint INPUT_MOUSE = 0;
        private const uint INPUT_KEYBOARD = 1;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const uint MOUSEEVENTF_WHEEL = 0x0800;
        private const uint MOUSEEVENTF_HWHEEL = 0x01000;
        private const int WHEEL_DELTA = 120;

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

        private static INPUT KeyInput(ushort vk, bool keyUp)
        {
            INPUT input = new INPUT();
            input.type = INPUT_KEYBOARD;
            input.U.ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = 0,
                dwFlags = keyUp ? KEYEVENTF_KEYUP : 0,
                time = UIntPtr.Zero,
                dwExtraInfo = IntPtr.Zero
            };
            return input;
        }

        private static INPUT WheelInput(int delta, bool horizontal)
        {
            INPUT input = new INPUT();
            input.type = INPUT_MOUSE;
            input.U.mi = new MOUSEINPUT
            {
                dx = 0,
                dy = 0,
                mouseData = unchecked((uint)delta),
                dwFlags = horizontal ? MOUSEEVENTF_HWHEEL : MOUSEEVENTF_WHEEL,
                time = 0,
                dwExtraInfo = IntPtr.Zero
            };
            return input;
        }

        public static void Scroll(
            int steps,
            bool horizontal,
            bool ctrl,
            bool shift,
            bool alt,
            bool win
        )
        {
            if (steps == 0)
                return;

            if (steps < -32 || steps > 32)
                throw new ArgumentOutOfRangeException("steps");

            var inputs = new System.Collections.Generic.List<INPUT>();

            if (ctrl) inputs.Add(KeyInput(VK_CONTROL, false));
            if (shift) inputs.Add(KeyInput(VK_SHIFT, false));
            if (alt) inputs.Add(KeyInput(VK_MENU, false));
            if (win) inputs.Add(KeyInput(VK_LWIN, false));

            inputs.Add(WheelInput(steps * WHEEL_DELTA, horizontal));

            if (win) inputs.Add(KeyInput(VK_LWIN, true));
            if (alt) inputs.Add(KeyInput(VK_MENU, true));
            if (shift) inputs.Add(KeyInput(VK_SHIFT, true));
            if (ctrl) inputs.Add(KeyInput(VK_CONTROL, true));

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
                    "SendInput did not send the complete mouse-wheel action."
                );
            }
        }
    }    public static class MugenFolderPicker
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

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindowDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

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

            IntPtr hdc = IntPtr.Zero;
            try
            {
                // ComboBox owns a native non-client rim. CreateGraphics() only
                // paints the client area, so Windows can leave different pieces
                // of the native rim visible on different sides. Paint the full
                // window DC after the native WM_PAINT/WM_NCPAINT pass instead.
                hdc = GetWindowDC(Handle);
                if (hdc == IntPtr.Zero) return;

                using (Graphics g = Graphics.FromHdc(hdc))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;

                    Color back = Enabled ? BackColor : disabledBackColor;
                    Color fore = Enabled ? ForeColor : disabledTextColor;
                    Color border = (Focused || hovered) && Enabled ? accentColor : borderColor;

                    Rectangle whole = new Rectangle(0, 0, Width, Height);
                    using (SolidBrush backBrush = new SolidBrush(back))
                        g.FillRectangle(backBrush, whole);

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

                    using (SolidBrush borderBrush = new SolidBrush(border))
                    {
                        g.FillRectangle(borderBrush, 0, 0, Width, 1);
                        g.FillRectangle(borderBrush, 0, Height - 1, Width, 1);
                        g.FillRectangle(borderBrush, 0, 0, 1, Height);
                        g.FillRectangle(borderBrush, Width - 1, 0, 1, Height);
                    }
                }
            }
            catch
            {
                // Painting is cosmetic; never let it break combo-box behavior.
            }
            finally
            {
                if (hdc != IntPtr.Zero)
                    ReleaseDC(Handle, hdc);
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

    public sealed class MugenLayerPopupForm : Form
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct NativePoint
        {
            public int X;
            public int Y;

            public NativePoint(int x, int y)
            {
                X = x;
                Y = y;
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeSize
        {
            public int Width;
            public int Height;

            public NativeSize(int width, int height)
            {
                Width = width;
                Height = height;
            }
        }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct BlendFunction
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UpdateLayeredWindow(
            IntPtr hwnd,
            IntPtr hdcDst,
            ref NativePoint pptDst,
            ref NativeSize psize,
            IntPtr hdcSrc,
            ref NativePoint pptSrc,
            int crKey,
            ref BlendFunction pblend,
            int dwFlags
        );

        [DllImport("user32.dll")]
        private static extern IntPtr GetDC(IntPtr hwnd);

        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);

        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

        [DllImport("gdi32.dll")]
        private static extern bool DeleteDC(IntPtr hdc);

        [DllImport("gdi32.dll")]
        private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);

        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr hObject);

        private string captionText = String.Empty;
        private string layerText = String.Empty;
        private Color surfaceColor = Color.FromArgb(245, 247, 251);
        private Color borderColor = Color.FromArgb(190, 198, 210);
        private Color captionColor = Color.DimGray;
        private Color nameColor = Color.Black;
        private int cornerRadius = 14;
        private int opacityPercent = 50;

        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                const int WS_EX_LAYERED = 0x00080000;
                const int WS_EX_NOACTIVATE = 0x08000000;
                const int WS_EX_TOOLWINDOW = 0x00000080;
                cp.ExStyle |= WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
                return cp;
            }
        }

        public void ConfigureSurface(
            string caption,
            string layer,
            Color surface,
            Color border,
            Color captionTextColor,
            Color layerTextColor,
            int radius,
            int opacity)
        {
            captionText = caption ?? String.Empty;
            layerText = layer ?? String.Empty;
            surfaceColor = surface;
            borderColor = border;
            captionColor = captionTextColor;
            nameColor = layerTextColor;
            cornerRadius = Math.Max(1, radius);
            opacityPercent = Math.Max(20, Math.Min(100, opacity));

            if (IsHandleCreated && Visible)
                UpdateLayeredSurface();
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            UpdateLayeredSurface();
        }

        protected override void OnSizeChanged(EventArgs e)
        {
            base.OnSizeChanged(e);
            if (IsHandleCreated && Visible)
                UpdateLayeredSurface();
        }

        private void UpdateLayeredSurface()
        {
            if (!IsHandleCreated || Width <= 2 || Height <= 2)
                return;

            using (Bitmap bitmap = new Bitmap(
                Width,
                Height,
                System.Drawing.Imaging.PixelFormat.Format32bppPArgb))
            {
                using (Graphics g = Graphics.FromImage(bitmap))
                {
                    g.Clear(Color.Transparent);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
                    g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;

                    Rectangle rect = new Rectangle(
                        1,
                        1,
                        Math.Max(1, Width - 3),
                        Math.Max(1, Height - 3)
                    );

                    using (GraphicsPath path = MugenDrawing.RoundedRect(rect, cornerRadius))
                    using (SolidBrush surfaceBrush = new SolidBrush(surfaceColor))
                    using (Pen borderPen = new Pen(borderColor, 1f))
                    {
                        g.FillPath(surfaceBrush, path);
                        g.DrawPath(borderPen, path);
                    }

                    using (Font captionFont = new Font("Segoe UI", 9f, FontStyle.Regular, GraphicsUnit.Point))
                    using (Font nameFont = new Font("Segoe UI Semibold", 18f, FontStyle.Regular, GraphicsUnit.Point))
                    using (SolidBrush captionBrush = new SolidBrush(captionColor))
                    using (SolidBrush nameBrush = new SolidBrush(nameColor))
                    using (StringFormat captionFormat = new StringFormat())
                    using (StringFormat nameFormat = new StringFormat())
                    {
                        captionFormat.Alignment = StringAlignment.Center;
                        captionFormat.LineAlignment = StringAlignment.Center;
                        captionFormat.Trimming = StringTrimming.EllipsisCharacter;
                        captionFormat.FormatFlags = StringFormatFlags.NoWrap;

                        nameFormat.Alignment = StringAlignment.Center;
                        nameFormat.LineAlignment = StringAlignment.Center;
                        nameFormat.Trimming = StringTrimming.EllipsisCharacter;
                        nameFormat.FormatFlags = StringFormatFlags.NoWrap;

                        g.DrawString(
                            captionText,
                            captionFont,
                            captionBrush,
                            new RectangleF(14f, 9f, Math.Max(1, Width - 28), 20f),
                            captionFormat
                        );

                        g.DrawString(
                            layerText,
                            nameFont,
                            nameBrush,
                            new RectangleF(14f, 29f, Math.Max(1, Width - 28), 42f),
                            nameFormat
                        );
                    }
                }

                IntPtr screenDc = IntPtr.Zero;
                IntPtr memoryDc = IntPtr.Zero;
                IntPtr bitmapHandle = IntPtr.Zero;
                IntPtr oldBitmap = IntPtr.Zero;

                try
                {
                    screenDc = GetDC(IntPtr.Zero);
                    memoryDc = CreateCompatibleDC(screenDc);
                    bitmapHandle = bitmap.GetHbitmap(Color.FromArgb(0));
                    oldBitmap = SelectObject(memoryDc, bitmapHandle);

                    NativePoint destination = new NativePoint(Left, Top);
                    NativeSize size = new NativeSize(Width, Height);
                    NativePoint source = new NativePoint(0, 0);

                    BlendFunction blend = new BlendFunction();
                    blend.BlendOp = 0; // AC_SRC_OVER
                    blend.BlendFlags = 0;
                    blend.SourceConstantAlpha = (byte)Math.Round(opacityPercent * 255.0 / 100.0);
                    blend.AlphaFormat = 1; // AC_SRC_ALPHA

                    if (!UpdateLayeredWindow(
                        Handle,
                        screenDc,
                        ref destination,
                        ref size,
                        memoryDc,
                        ref source,
                        0,
                        ref blend,
                        0x00000002)) // ULW_ALPHA
                    {
                        throw new System.ComponentModel.Win32Exception(
                            Marshal.GetLastWin32Error(),
                            "UpdateLayeredWindow failed for the layer OSD."
                        );
                    }
                }
                finally
                {
                    if (oldBitmap != IntPtr.Zero && memoryDc != IntPtr.Zero)
                        SelectObject(memoryDc, oldBitmap);
                    if (bitmapHandle != IntPtr.Zero)
                        DeleteObject(bitmapHandle);
                    if (memoryDc != IntPtr.Zero)
                        DeleteDC(memoryDc);
                    if (screenDc != IntPtr.Zero)
                        ReleaseDC(IntPtr.Zero, screenDc);
                }
            }
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

$script:AppVersion = '2.0.0'
$script:ControllerProtocol = 'unknown'
$script:DetectedSliderCount = 0
$script:DetectedButtonCount = 0
$script:DetectedToggleCount = 0
$script:DetectedEncoderCount = 0
$script:LatestButtons = @()
$script:LatestToggles = @()
$script:LatestEncoders = @()
$script:LastEncoderPositions = @()
$script:AdaptiveDebounceDiagnostics = $null
$script:LastButtonStates = @()
$script:LastCapabilityMismatchLog = [DateTime]::MinValue
$script:PacketRateWindowStartedAt = [DateTime]::MinValue
$script:PacketRateWindowCount = 0
$script:PacketRateHz = 0.0
$script:AdaptiveOverflowButton = $null
$script:SliderOverflowButton = $null
$script:ButtonActionConfigPath = Join-Path $script:BaseDir 'button-actions.json'
$script:LegacyButtonActionConfigPath = Join-Path $script:BaseDir 'button-actions.dev.json'
$script:AdaptiveActionConfigPath = Join-Path $script:BaseDir 'adaptive-actions.json'
$script:AdaptiveProfileConfigPath = Join-Path $script:BaseDir 'adaptive-profiles.json'
$script:AdaptiveLayerConfigPath = Join-Path $script:BaseDir 'adaptive-layers.json'
$script:AdaptiveLayersLoaded = $false
$script:AdaptiveLayerConfig = $null
$script:LayerStateLabel = $null
$script:AdaptiveLayerPopupForm = $null
$script:AdaptiveLayerPopupTimer = $null
$script:AdaptiveActionsLoaded = $false
$script:AdaptiveToggleActions = @()
$script:AdaptiveEncoderActions = @()
$script:AdaptiveProfilesLoaded = $false
$script:AdaptiveProfiles = @()
$script:AdaptiveSettingsButton = $null
$script:ButtonActionsLoaded = $false
$script:ButtonActions = @()
$script:SoftMutedSliders = @{}
$script:LastButtonActionAt = @{}
$script:ButtonSettingsButton = $null
$script:VirtualGamepadFeatureAvailable = $false
$virtualGamepadModulePath = Join-Path $script:BaseDir 'virtual-gamepad\MugenDeej.VirtualGamepad.ps1'
if (Test-Path -LiteralPath $virtualGamepadModulePath -PathType Leaf) {
    . $virtualGamepadModulePath
    $script:VirtualGamepadFeatureAvailable = $true
}
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
            baudRateMode = 'auto'
            lastWorkingBaudRate = 0
            expectedSliders = 5
            reconnectSeconds = 3
            startupWaitMs = 2200
            dataTimeoutMs = 2500
        }
        behavior = [ordered]@{
            invertSliders = $false
            invertSlidersByController = [ordered]@{}
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
    Add-MissingConfigProperty -Object $Config.connection -Name 'baudRateMode' -Value 'auto'
    Add-MissingConfigProperty -Object $Config.connection -Name 'lastWorkingBaudRate' -Value 0
    Add-MissingConfigProperty -Object $Config.connection -Name 'expectedSliders' -Value 5
    Add-MissingConfigProperty -Object $Config.connection -Name 'reconnectSeconds' -Value 3
    Add-MissingConfigProperty -Object $Config.connection -Name 'startupWaitMs' -Value 2200
    Add-MissingConfigProperty -Object $Config.connection -Name 'dataTimeoutMs' -Value 2500

    if ($null -eq $Config.PSObject.Properties['behavior']) {
        $Config | Add-Member -MemberType NoteProperty -Name 'behavior' -Value ([pscustomobject]@{})
    }
    Add-MissingConfigProperty -Object $Config.behavior -Name 'invertSliders' -Value $false
    Add-MissingConfigProperty -Object $Config.behavior -Name 'invertSlidersByController' -Value ([pscustomobject]@{})
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
        StatusConnected = 'Контроллер · {1} регуляторов'
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
        DriverActiveWorking = 'USB-драйвер работает — {0}'
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
        AppPickerHint = 'Верхний список показывает приложения с активной аудиосессией.' + "`r`n" + 'Ниже можно заранее выбрать запущенные приложения, которые пока молчат.'
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
        SettingsHint = ('Регуляторы идут слева направо. Их названия можно и нужно менять под назначение — например, «Музыка», «Игра» или «Чат».' + "`r`n" + 'Названия используются только для отображения и не влияют на подключение.' + "`r`n" + 'Поверните крутилку или передвиньте фейдер: соответствующий индикатор покажет, какой физический регулятор вы настраиваете.')
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
        CloseHint = 'Продолжить'
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
        StatusConnected = 'Controller · {1} controls'
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
        DriverActiveWorking = 'USB driver is working — {0}'
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
        AppPickerHint = 'The upper list shows active audio sessions.' + "`r`n" + 'Below, you can preselect running applications that are currently silent.'
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
        SettingsHint = ('Controls are ordered from left to right. Rename them to match their purpose, for example Music, Game, or Chat.' + "`r`n" + 'Names are only labels and do not affect the device connection.' + "`r`n" + 'Turn a knob or move a fader: the matching indicator shows which physical control you are configuring.')
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
        CloseHint = 'Continue'
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
    $activeListView.Location = New-Object System.Drawing.Point(12, 31)
    $activeListView.Size = New-Object System.Drawing.Size(786, 138)
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
    $otherListView.Location = New-Object System.Drawing.Point(12, 31)
    $otherListView.Size = New-Object System.Drawing.Size(786, 151)
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
    if ($script:IsConnected -and [int]$script:DetectedSliderCount -le 0) {
        $message = if ($script:Language -eq 'ru') {
            'У подключённого контроллера нет физических регуляторов.'
        }
        else {
            'The connected controller does not expose any physical analog controls.'
        }
        [void](Show-MugenDeejStyledDialog -Message $message -Buttons 'OK' -Kind 'Info')
        return
    }
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
    $count = if ($script:IsConnected) { [int]$script:DetectedSliderCount } else { [int]$script:Config.connection.expectedSliders }
    Ensure-SliderConfigCapacity -Count $count
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
    $advancedY = 150 + ($count * 76) + 10
    $sliderAdvancedPanel.Location = New-Object System.Drawing.Point(25, $advancedY)
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
    $invertCheck.Checked = [bool](Get-EffectiveSliderInversion)
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
    $responseHint.Location = New-Object System.Drawing.Point(395, 64)
    $responseHint.Size = New-Object System.Drawing.Size(645, 38)
$responseHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $sliderAdvancedPanel.Controls.Add($responseHint)

    $advancedConfigButton = New-Object MugenDeejWindowing.MugenButton
    $advancedConfigButton.Text = (T -Key 'OpenConfig')
    $advancedConfigButton.Location = New-Object System.Drawing.Point(850, 64)
    $advancedConfigButton.Size = New-Object System.Drawing.Size(190, 32)
$advancedConfigButton.Visible = $false
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
    # The always-visible Advanced card is 112px tall. Leave a clean gap
    # before the Save/Cancel action row.
    $actionY = $advancedY + 134
    $cancelButton.Location = New-Object System.Drawing.Point(870, $actionY)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 36)
    $settingsForm.Controls.Add($cancelButton)

    $saveButton = New-Object MugenDeejWindowing.MugenButton
    $saveButton.Text = (T -Key 'Save')
    $saveButton.Location = New-Object System.Drawing.Point(982, $actionY)
    if ($count -gt 5) {
        $settingsForm.AutoScroll = $true
        $settingsForm.AutoScrollMinSize = [System.Drawing.Size]::new(1090, ($actionY + 70))
    }
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

        # Keep settings for controls that are absent from the currently
        # connected topology. Universal backups/configs must not be truncated
        # merely because a smaller controller is attached while editing.
        for ($i = $count; $i -lt @($script:Config.sliders).Count; $i++) {
            $newSliders += $script:Config.sliders[$i]
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

        $selectedInvert = [bool]$invertMatches[0].Checked
        $controllerSignature = Get-CurrentControllerSignature
        if ([string]::IsNullOrWhiteSpace($controllerSignature)) {
            # Keep the legacy global setting as a disconnected fallback. Once a
            # controller is present, settings are stored against its topology.
            $script:Config.behavior.invertSliders = $selectedInvert
        }
        else {
            Set-SliderInversionForController -Signature $controllerSignature -Invert $selectedInvert
            Write-Log ('Slider inversion saved for controller: signature={0}; invert={1}' -f $controllerSignature, $selectedInvert) 'INFO'
        }
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
    $wizard.ClientSize = New-Object System.Drawing.Size(660, 452)
    $wizard.MinimumSize = New-Object System.Drawing.Size(676, 491)
    $wizard.MaximumSize = New-Object System.Drawing.Size(676, 491)
    $wizard.Font = New-Object System.Drawing.Font('Segoe UI', 10)
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

    # Use single-line labels instead of wrapped paragraphs so the vertical rhythm
    # is identical in RU and EN.
    $introLine1 = New-Object System.Windows.Forms.Label
    $introLine1.Location = New-Object System.Drawing.Point(27, 62)
    $introLine1.Size = New-Object System.Drawing.Size(606, 22)
    $wizard.Controls.Add($introLine1)

    $introLine2 = New-Object System.Windows.Forms.Label
    $introLine2.Location = New-Object System.Drawing.Point(27, 84)
    $introLine2.Size = New-Object System.Drawing.Size(606, 22)
    $wizard.Controls.Add($introLine2)

    # A card + explicit title keeps every line on the same left edge.
    $controllerCard = New-Object MugenDeejWindowing.MugenCardPanel
    $controllerCard.Location = New-Object System.Drawing.Point(24, 122)
    $controllerCard.Size = New-Object System.Drawing.Size(612, 126)
    $wizard.Controls.Add($controllerCard)

    $controllerTitle = New-Object System.Windows.Forms.Label
    $controllerTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $controllerTitle.Location = New-Object System.Drawing.Point(16, 12)
    $controllerTitle.Size = New-Object System.Drawing.Size(580, 22)
    $controllerCard.Controls.Add($controllerTitle)

    # Keep connected and disconnected card contents in separate panels.
    # This lets resume/disconnect switch the whole card atomically instead of
    # toggling Visible on a collection of individual labels from a timer tick.
    $connectedDetailsPanel = New-Object System.Windows.Forms.Panel
    $connectedDetailsPanel.Tag = 'MugenCardInner'
    $connectedDetailsPanel.Location = New-Object System.Drawing.Point(16, 37)
    $connectedDetailsPanel.Size = New-Object System.Drawing.Size(580, 74)
    $controllerCard.Controls.Add($connectedDetailsPanel)

    $waitingPanel = New-Object System.Windows.Forms.Panel
    $waitingPanel.Tag = 'MugenCardInner'
    $waitingPanel.Location = New-Object System.Drawing.Point(16, 37)
    $waitingPanel.Size = New-Object System.Drawing.Size(580, 74)
    $waitingPanel.Visible = $false
    $controllerCard.Controls.Add($waitingPanel)

    $portName = New-Object System.Windows.Forms.Label
    $portName.Location = New-Object System.Drawing.Point(0, 6)
    $portName.Size = New-Object System.Drawing.Size(42, 22)
    $connectedDetailsPanel.Controls.Add($portName)

    $portValue = New-Object System.Windows.Forms.Label
    $portValue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $portValue.Location = New-Object System.Drawing.Point(42, 6)
    $portValue.Size = New-Object System.Drawing.Size(82, 22)
    $connectedDetailsPanel.Controls.Add($portValue)

    $protocolName = New-Object System.Windows.Forms.Label
    $protocolName.Location = New-Object System.Drawing.Point(132, 6)
    $protocolName.Size = New-Object System.Drawing.Size(76, 22)
    $connectedDetailsPanel.Controls.Add($protocolName)

    $protocolValue = New-Object System.Windows.Forms.Label
    $protocolValue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $protocolValue.Location = New-Object System.Drawing.Point(208, 6)
    $protocolValue.Size = New-Object System.Drawing.Size(112, 22)
    $connectedDetailsPanel.Controls.Add($protocolValue)

    $baudName = New-Object System.Windows.Forms.Label
    $baudName.Location = New-Object System.Drawing.Point(332, 6)
    $baudName.Size = New-Object System.Drawing.Size(78, 22)
    $connectedDetailsPanel.Controls.Add($baudName)

    $baudValue = New-Object System.Windows.Forms.Label
    $baudValue.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $baudValue.Location = New-Object System.Drawing.Point(410, 6)
    $baudValue.Size = New-Object System.Drawing.Size(164, 22)
    $connectedDetailsPanel.Controls.Add($baudValue)

    $capabilityLabel = New-Object System.Windows.Forms.Label
    $capabilityLabel.Location = New-Object System.Drawing.Point(0, 39)
    $capabilityLabel.Size = New-Object System.Drawing.Size(574, 22)
    $connectedDetailsPanel.Controls.Add($capabilityLabel)

    $waitingLabel = New-Object System.Windows.Forms.Label
    $waitingLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $waitingLabel.Location = New-Object System.Drawing.Point(0, 8)
    $waitingLabel.Size = New-Object System.Drawing.Size(574, 22)
    $waitingPanel.Controls.Add($waitingLabel)

    $waitingHint = New-Object System.Windows.Forms.Label
    $waitingHint.Location = New-Object System.Drawing.Point(0, 39)
    $waitingHint.Size = New-Object System.Drawing.Size(574, 22)
    $waitingPanel.Controls.Add($waitingHint)

    $nextHintLine1 = New-Object System.Windows.Forms.Label
    $nextHintLine1.ForeColor = [System.Drawing.Color]::DimGray
    $nextHintLine1.Location = New-Object System.Drawing.Point(27, 266)
    $nextHintLine1.Size = New-Object System.Drawing.Size(606, 22)
    $wizard.Controls.Add($nextHintLine1)

    $nextHintLine2 = New-Object System.Windows.Forms.Label
    $nextHintLine2.ForeColor = [System.Drawing.Color]::DimGray
    $nextHintLine2.Location = New-Object System.Drawing.Point(27, 288)
    $nextHintLine2.Size = New-Object System.Drawing.Size(606, 22)
    $wizard.Controls.Add($nextHintLine2)

    $nextHintLine3 = New-Object System.Windows.Forms.Label
    $nextHintLine3.ForeColor = [System.Drawing.Color]::DimGray
    $nextHintLine3.Location = New-Object System.Drawing.Point(27, 310)
    $nextHintLine3.Size = New-Object System.Drawing.Size(606, 22)
    $nextHintLine3.Visible = $false
    $wizard.Controls.Add($nextHintLine3)

    $sliderButton = New-Object MugenDeejWindowing.MugenButton
    $sliderButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $sliderButton.Size = New-Object System.Drawing.Size(188, 38)
    $sliderButton.Visible = $false
    $wizard.Controls.Add($sliderButton)

    $buttonButton = New-Object MugenDeejWindowing.MugenButton
    $buttonButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $buttonButton.Size = New-Object System.Drawing.Size(188, 38)
    $buttonButton.Visible = $false
    $wizard.Controls.Add($buttonButton)

    $typedButton = New-Object MugenDeejWindowing.MugenButton
    $typedButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $typedButton.Size = New-Object System.Drawing.Size(188, 38)
    $typedButton.Visible = $false
    $wizard.Controls.Add($typedButton)

    $laterButton = New-Object MugenDeejWindowing.MugenButton
    $laterButton.Text = (T -Key 'CloseHint')
    $laterButton.Location = New-Object System.Drawing.Point(478, 400)
    $laterButton.Size = New-Object System.Drawing.Size(158, 36)
    $wizard.Controls.Add($laterButton)

    $wizardChoice = [pscustomobject]@{ Value = '' }

    $finishWizard = {
        if (-not [bool]$script:Config.app.firstRunCompleted) {
            $script:Config.app.firstRunCompleted = $true
            Save-Config -Config $script:Config
        }
    }

    $layoutButtons = {
        $available = @()
        if ($sliderButton.Visible) { $available += $sliderButton }
        if ($buttonButton.Visible) { $available += $buttonButton }
        if ($typedButton.Visible) { $available += $typedButton }

        $count = $available.Count
        if ($count -le 0) { return }

        $gap = 12
        $width = 188
        $total = ($count * $width) + (($count - 1) * $gap)
        $startX = [int][Math]::Floor((660 - $total) / 2)
        for ($i = 0; $i -lt $count; $i++) {
            $available[$i].Location = New-Object System.Drawing.Point(($startX + ($i * ($width + $gap))), 348)
        }
    }

    $refreshWizard = {
        $ru = ($script:Language -eq 'ru')
        $connected = [bool]$script:IsConnected
        $sliders = if ($connected) { [int]$script:DetectedSliderCount } else { 0 }
        $buttons = if ($connected) { [int]$script:DetectedButtonCount } else { 0 }
        $toggles = if ($connected) { [int]$script:DetectedToggleCount } else { 0 }
        $encoders = if ($connected) { [int]$script:DetectedEncoderCount } else { 0 }

        $controllerTitle.Text = if ($ru) { 'Ваш контроллер' } else { 'Your controller' }

        # Short category names fit all three peer buttons in both languages.
        $sliderButton.Text = if ($ru) { 'Регуляторы' } else { 'Analog controls' }
        $buttonButton.Text = if ($ru) { 'Кнопки' } else { 'Buttons' }
        $typedButton.Text = if ($ru) { 'Тумблеры и энкодеры' } else { 'Toggles & encoders' }

        if ($connected) {
            $introLine1.Text = if ($ru) { 'Контроллер найден и готов к работе.' } else { 'Your controller is connected and ready.' }
            $introLine2.Text = if ($ru) {
                'Проверьте органы управления — их состояние сразу видно в главном окне.'
            }
            else {
                'Try the controls — their state appears immediately in the main window.'
            }

            $port = if ([string]::IsNullOrWhiteSpace($script:ConnectedPort)) { '—' } else { $script:ConnectedPort }
            $baud = '—'
            if ($null -ne $script:Serial) {
                try { $baud = [string][int]$script:Serial.BaudRate } catch { }
            }

            $portName.Text = if ($ru) { 'Порт:' } else { 'Port:' }
            $protocolName.Text = if ($ru) { 'Протокол:' } else { 'Protocol:' }
            $baudName.Text = if ($ru) { 'Скорость:' } else { 'Baud:' }
            $portValue.Text = $port
            $protocolValue.Text = Get-ControllerProtocolDisplayText
            $baudValue.Text = if ($ru) { $baud + ' бод' } else { $baud }

            $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
            $normalText = $palette.Text
            foreach ($label in @($portName, $protocolName, $baudName)) {
                $label.ForeColor = $normalText
            }
            foreach ($value in @($portValue, $protocolValue, $baudValue)) {
                $value.ForeColor = [System.Drawing.Color]::SeaGreen
            }

            $capabilityLabel.Text = if ($ru) {
                'Доступно: {0} регуляторов · {1} кнопок · {2} тумблеров · {3} энкодеров' -f $sliders, $buttons, $toggles, $encoders
            }
            else {
                'Available: {0} controls · {1} buttons · {2} toggles · {3} encoders' -f $sliders, $buttons, $toggles, $encoders
            }

            $connectedDetailsPanel.Visible = $true
            $waitingPanel.Visible = $false

            $nextHintLine1.Text = if ($ru) { 'Можно настроить нужные элементы прямо сейчас.' } else { 'You can configure the controls you need right now.' }
            $nextHintLine2.Text = if ($ru) {
                'Или закрыть это окно и вернуться к настройкам позже.'
            }
            else {
                'Or close this window and return to the settings later.'
            }

            $nextHintLine3.Visible = ($sliders -gt 0)
            $nextHintLine3.Text = if ($sliders -gt 0) {
                if ($ru) {
                    'Если регуляторы работают наоборот — включите инверсию направления в «Регуляторах».'
                }
                else {
                    'If the controls move backwards, enable direction inversion in Controls.'
                }
            }
            else { '' }
        }
        else {
            $introLine1.Text = if ($ru) { 'Подключите контроллер по USB.' } else { 'Connect your controller by USB.' }
            $introLine2.Text = if ($ru) {
                'Mugen сам найдёт его и покажет, какие элементы управления доступны.'
            }
            else {
                'Mugen will find it automatically and show which controls are available.'
            }

            $connectedDetailsPanel.Visible = $false
            $waitingPanel.Visible = $true
            $waitingLabel.Text = if ($ru) { 'Жду контроллер…' } else { 'Waiting for controller…' }
            $waitingLabel.ForeColor = [System.Drawing.Color]::DarkOrange
            $waitingHint.Text = if ($ru) {
                'После подключения здесь появится состав контроллера.'
            }
            else {
                'The controller layout will appear here after it connects.'
            }

            $nextHintLine1.Text = if ($ru) {
                'Можно оставить это окно открытым — оно обновится автоматически.'
            }
            else {
                'You can leave this window open — it will update automatically.'
            }
            $nextHintLine2.Text = ''
            $nextHintLine3.Text = ''
            $nextHintLine3.Visible = $false
        }

        $sliderButton.Visible = ($connected -and $sliders -gt 0)
        $buttonButton.Visible = ($connected -and $buttons -gt 0)
        $typedButton.Visible = ($connected -and ($toggles -gt 0 -or $encoders -gt 0))
        & $layoutButtons
    }

    $laterButton.Add_Click({
        & $finishWizard
        $wizard.Close()
    })
    $sliderButton.Add_Click({
        $wizardChoice.Value = 'sliders'
        & $finishWizard
        $wizard.Close()
    })
    $buttonButton.Add_Click({
        $wizardChoice.Value = 'buttons'
        & $finishWizard
        $wizard.Close()
    })
    $typedButton.Add_Click({
        $wizardChoice.Value = 'typed'
        & $finishWizard
        $wizard.Close()
    })

    $wizardTimer = New-Object System.Windows.Forms.Timer
    $wizardTimer.Interval = 150
    $wizardTimer.Add_Tick({
        try {
            & $refreshWizard
        }
        catch {
            # A first-run helper must never surface a WinForms JIT exception.
            # Stop only this helper timer and keep the main application alive.
            Write-Log ('First-run wizard refresh failed: {0}' -f (Get-ExceptionDiagnosticText -ErrorRecord $_)) 'WARN'
            $wizardTimer.Stop()
        }
    })

    Apply-ThemeToForm -Form $wizard -ThemeName (Get-EffectiveTheme)
    # Theme application normalizes label colors, so restore the warning accent afterwards.
    $nextHintLine3.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    & $refreshWizard
    $wizard.Add_Shown({
        Ensure-FormVisible -Form $wizard -CenterIfOffscreen
        $wizardTimer.Start()
    })
    $wizard.Add_FormClosing({
        if (-not [bool]$script:Config.app.firstRunCompleted) { & $finishWizard }
    })
    $wizard.Add_FormClosed({
        $wizardTimer.Stop()
        $wizardTimer.Dispose()
    })

    [void]$wizard.ShowDialog($form)
    $wizard.Dispose()

    switch ([string]$wizardChoice.Value) {
        'sliders' { Show-SliderSettings }
        'buttons' { Show-ButtonSettings }
        'typed' { Show-AdaptiveControlSettings }
    }
}
function Get-PortNames {
    return @(
        [System.IO.Ports.SerialPort]::GetPortNames() |
            Sort-Object { [int]($_ -replace '\D','0') } |
            Select-Object -Unique
    )
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

function Get-ControllerPacketArray {
    param(
        [Parameter(Mandatory = $true)]$Packet,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $Packet.PSObject.Properties[$Name]
    if ($null -eq $property) { return @() }
    return @($property.Value)
}

function Get-ControllerPacketSignature {
    param([Parameter(Mandatory = $true)]$Packet)

    $toggles = @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles')
    $encoders = @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders')

    return ('{0}:{1}:{2}:{3}:{4}' -f
        [string]$Packet.Protocol,
        @($Packet.Sliders).Count,
        @($Packet.Buttons).Count,
        $toggles.Count,
        $encoders.Count
    )
}

function Get-CurrentControllerSignature {
    if ([string]$script:ControllerProtocol -eq 'unknown') { return '' }

    return ('{0}:{1}:{2}:{3}:{4}' -f
        [string]$script:ControllerProtocol,
        [int]$script:DetectedSliderCount,
        [int]$script:DetectedButtonCount,
        [int]$script:DetectedToggleCount,
        [int]$script:DetectedEncoderCount
    )
}

function Get-SliderInversionProfileStore {
    $property = $script:Config.behavior.PSObject.Properties['invertSlidersByController']
    if ($null -eq $property -or $null -eq $property.Value) {
        $store = [pscustomobject]@{}
        if ($null -eq $property) {
            $script:Config.behavior | Add-Member -MemberType NoteProperty -Name 'invertSlidersByController' -Value $store
        }
        else {
            $property.Value = $store
        }
        return $store
    }
    return $property.Value
}

function Get-EffectiveSliderInversion {
    param([string]$Signature = '')

    if ([string]::IsNullOrWhiteSpace($Signature)) {
        $Signature = Get-CurrentControllerSignature
    }

    $store = Get-SliderInversionProfileStore
    if (-not [string]::IsNullOrWhiteSpace($Signature)) {
        $entry = $store.PSObject.Properties[$Signature]
        if ($null -ne $entry) {
            return [bool]$entry.Value
        }
    }

    # An empty profile store means this configuration predates per-controller
    # inversion. Preserve the old global setting until the first controller is
    # detected and migrated. After that, unseen controller signatures default
    # to normal direction instead of inheriting another device's wiring.
    if (@($store.PSObject.Properties).Count -eq 0) {
        return [bool]$script:Config.behavior.invertSliders
    }
    return $false
}

function Set-SliderInversionForController {
    param(
        [Parameter(Mandatory = $true)][string]$Signature,
        [Parameter(Mandatory = $true)][bool]$Invert
    )

    $store = Get-SliderInversionProfileStore
    $entry = $store.PSObject.Properties[$Signature]
    if ($null -eq $entry) {
        $store | Add-Member -MemberType NoteProperty -Name $Signature -Value $Invert
    }
    else {
        $entry.Value = $Invert
    }
}

function Initialize-SliderInversionProfileForCurrentController {
    $signature = Get-CurrentControllerSignature
    if ([string]::IsNullOrWhiteSpace($signature)) { return }

    $store = Get-SliderInversionProfileStore
    if (@($store.PSObject.Properties).Count -ne 0) { return }

    $legacyValue = [bool]$script:Config.behavior.invertSliders
    Set-SliderInversionForController -Signature $signature -Invert $legacyValue
    Save-Config -Config $script:Config
    Write-Log ('Migrated global slider inversion to controller profile: signature={0}; invert={1}' -f $signature, $legacyValue) 'INFO'
}

function Test-ControllerProtocolLine {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

    $parts = @($Line.Trim() -split '\|')
    if ($parts.Count -lt 1 -or $parts.Count -gt 64) { return $null }

    # Adaptive v3: explicit version marker plus first-class typed controls.
    # Example:
    #   v3|s0|s512|b1|b0|t0|t1|e42:1
    #
    # b0/b1 preserve Extended semantics (0 pressed, 1 released).
    # t0/t1 are logical OFF/ON states.
    # eN[:P] reports a cumulative signed detent position and optional push
    # state P using button semantics (0 pressed, 1 released).
    #
    # Optional low-latency firmware diagnostic:
    #   d<debounceMs>:<filteredCount>:<filteredMaskHex>:<rapidCount>:<rapidMaskHex>
    # It is ignored for controller capability/signature matching.
    if ([string]$parts[0] -eq 'v3') {
        if ($parts.Count -lt 2) { return $null }

        $adaptiveSliders = New-Object 'System.Collections.Generic.List[int]'
        $adaptiveButtons = New-Object 'System.Collections.Generic.List[int]'
        $adaptiveToggles = New-Object 'System.Collections.Generic.List[int]'
        $adaptiveEncoders = New-Object System.Collections.ArrayList
        $adaptiveDiagnostics = $null

        for ($partIndex = 1; $partIndex -lt $parts.Count; $partIndex++) {
            $part = [string]$parts[$partIndex]
            if ([string]::IsNullOrWhiteSpace($part)) { return $null }

            if ($part -match '^s(\d{1,4})$') {
                $value = 0
                if (-not [int]::TryParse($Matches[1], [ref]$value)) { return $null }
                if ($value -lt 0 -or $value -gt 1023) { return $null }
                $adaptiveSliders.Add($value)
                continue
            }

            if ($part -match '^b([01])$') {
                $adaptiveButtons.Add([int]$Matches[1])
                continue
            }

            if ($part -match '^t([01])$') {
                $adaptiveToggles.Add([int]$Matches[1])
                continue
            }

            if ($part -match '^e(-?\d+)(?::([01]))?$') {
                $position = [int64]0
                if (-not [int64]::TryParse($Matches[1], [ref]$position)) { return $null }

                $hasPush = -not [string]::IsNullOrWhiteSpace([string]$Matches[2])
                $push = 1
                if ($hasPush) {
                    $push = [int]$Matches[2]
                }

                [void]$adaptiveEncoders.Add([pscustomobject]@{
                    Position = $position
                    Push = $push
                    HasPush = $hasPush
                })
                continue
            }

            if ($part -match '^d(\d{1,3}):(\d+):([0-9A-Fa-f]{1,8}):(\d+):([0-9A-Fa-f]{1,8})$') {
                if ($null -ne $adaptiveDiagnostics) { return $null }

                $debounceMs = 0
                [uint64]$filteredCount = 0
                [uint64]$rapidCount = 0
                if (-not [int]::TryParse($Matches[1], [ref]$debounceMs)) { return $null }
                if (-not [uint64]::TryParse($Matches[2], [ref]$filteredCount)) { return $null }
                if (-not [uint64]::TryParse($Matches[4], [ref]$rapidCount)) { return $null }

                try {
                    [uint32]$filteredMask = [Convert]::ToUInt32($Matches[3], 16)
                    [uint32]$rapidMask = [Convert]::ToUInt32($Matches[5], 16)
                }
                catch {
                    return $null
                }

                $adaptiveDiagnostics = [pscustomobject][ordered]@{
                    DebounceMs = $debounceMs
                    FilteredCount = $filteredCount
                    FilteredMask = $filteredMask
                    RapidCount = $rapidCount
                    RapidMask = $rapidMask
                }
                continue
            }

            return $null
        }

        # Adaptive v3 is explicitly versioned; unlike Legacy/Extended it does
        # not require an analog family. A valid v3 controller may consist only
        # of buttons, toggles, or encoders.
        if (
            ($adaptiveSliders.Count + $adaptiveButtons.Count + $adaptiveToggles.Count + $adaptiveEncoders.Count) -lt 1
        ) { return $null }

        return [pscustomobject]@{
            Protocol = 'adaptive'
            Sliders = @($adaptiveSliders.ToArray())
            Buttons = @($adaptiveButtons.ToArray())
            Toggles = @($adaptiveToggles.ToArray())
            Encoders = @($adaptiveEncoders.ToArray())
            Diagnostics = $adaptiveDiagnostics
        }
    }

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

function Get-AdaptiveDebounceDiagnostics {
    param([Parameter(Mandatory = $true)]$Packet)

    $property = $Packet.PSObject.Properties['Diagnostics']
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-AdaptiveDebounceDiagnosticContacts {
    param([uint32]$Mask)

    $labels = New-Object 'System.Collections.Generic.List[string]'
    for ($bit = 0; $bit -lt 28; $bit++) {
        if (($Mask -band ([uint32]1 -shl $bit)) -ne 0) {
            $labels.Add(('B{0}' -f ($bit + 1)))
        }
    }
    if (($Mask -band ([uint32]1 -shl 28)) -ne 0) { $labels.Add('T1') }
    if (($Mask -band ([uint32]1 -shl 29)) -ne 0) { $labels.Add('T2') }

    if ($labels.Count -eq 0) { return 'none' }
    return ($labels -join ',')
}

function Test-AdaptiveMappedAction {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'none') { return $true }
    if ($Action -match '^mute:\d+$') { return $true }
    if ($Action -in @(
        'media:playpause',
        'media:previous',
        'media:next',
        'media:stop',
        'system:volumeup',
        'system:volumedown',
        'system:volumemute',
        'mouse:wheelup',
        'mouse:wheeldown',
        'mouse:hwheelleft',
        'mouse:hwheelright',
        'mouse:ctrlwheelup',
        'mouse:ctrlwheeldown',
        'mouse:shiftwheelup',
        'mouse:shiftwheeldown',
        'mouse:altwheelup',
        'mouse:altwheeldown'
    )) { return $true }

    if ($Action -match '^hotkey:(\d{1,3}):(\d{1,2})$') {
        $vk = [int]$Matches[1]
        $mask = [int]$Matches[2]
        return ($vk -gt 0 -and $vk -le 255 -and $mask -ge 0 -and $mask -le 15)
    }

    if ($Action -match '^(launch64|folder64|url64|command64):(.+)$') {
        $decoded = Decode-ButtonActionPayload -Payload $Matches[2]
        return (-not [string]::IsNullOrWhiteSpace($decoded))
    }

    return $false
}

function ConvertTo-SafeAdaptiveAction {
    param([string]$Action)
    if (Test-AdaptiveMappedAction -Action $Action) { return [string]$Action }
    return 'none'
}

function Read-AdaptiveActionConfigFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $data) { throw 'Adaptive action configuration is empty.' }
    if ($null -eq $data.PSObject.Properties['version'] -or [int]$data.version -ne 1) {
        throw 'Unsupported or missing Adaptive action configuration version.'
    }
    if ($null -eq $data.PSObject.Properties['toggles'] -or $null -eq $data.PSObject.Properties['encoders']) {
        throw 'Adaptive action configuration is missing control families.'
    }

    $toggles = @()
    foreach ($item in @($data.toggles)) {
        if ($null -eq $item) { throw 'Adaptive toggle action contains a null item.' }
        $on = ConvertTo-SafeAdaptiveAction -Action ([string]$item.on)
        $off = ConvertTo-SafeAdaptiveAction -Action ([string]$item.off)
        $toggles += [pscustomobject][ordered]@{ on = $on; off = $off }
    }

    $encoders = @()
    foreach ($item in @($data.encoders)) {
        if ($null -eq $item) { throw 'Adaptive encoder action contains a null item.' }
        $cw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.cw)
        $ccw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.ccw)
        $push = ConvertTo-SafeAdaptiveAction -Action ([string]$item.push)
        $encoders += [pscustomobject][ordered]@{ cw = $cw; ccw = $ccw; push = $push }
    }

    return [pscustomobject][ordered]@{
        version = 1
        toggles = @($toggles)
        encoders = @($encoders)
    }
}

function Write-AdaptiveActionConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Toggles,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Encoders
    )

    $safeToggles = @()
    foreach ($item in @($Toggles)) {
        $safeToggles += [pscustomobject][ordered]@{
            on = ConvertTo-SafeAdaptiveAction -Action ([string]$item.on)
            off = ConvertTo-SafeAdaptiveAction -Action ([string]$item.off)
        }
    }

    $safeEncoders = @()
    foreach ($item in @($Encoders)) {
        $safeEncoders += [pscustomobject][ordered]@{
            cw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.cw)
            ccw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.ccw)
            push = ConvertTo-SafeAdaptiveAction -Action ([string]$item.push)
        }
    }

    $payload = [pscustomobject][ordered]@{
        version = 1
        toggles = @($safeToggles)
        encoders = @($safeEncoders)
    }

    $tempPath = "$Path.tmp-$PID"
    try {
        $json = $payload | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        $verified = Read-AdaptiveActionConfigFile -Path $tempPath
        if (@($verified.toggles).Count -ne @($safeToggles).Count -or @($verified.encoders).Count -ne @($safeEncoders).Count) {
            throw 'Adaptive action configuration failed count verification.'
        }

        if (Test-Path -LiteralPath $Path) {
            try { [System.IO.File]::Replace($tempPath, $Path, $null, $true) }
            catch {
                Copy-Item -LiteralPath $tempPath -Destination $Path -Force
                Remove-Item -LiteralPath $tempPath -Force
            }
        }
        else {
            [System.IO.File]::Move($tempPath, $Path)
        }
        [void](Read-AdaptiveActionConfigFile -Path $Path)
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Initialize-AdaptiveActions {
    if ($script:AdaptiveActionsLoaded) { return }
    $script:AdaptiveActionsLoaded = $true
    $script:AdaptiveToggleActions = @()
    $script:AdaptiveEncoderActions = @()

    if (-not (Test-Path -LiteralPath $script:AdaptiveActionConfigPath -PathType Leaf)) { return }

    try {
        $data = Read-AdaptiveActionConfigFile -Path $script:AdaptiveActionConfigPath
        $script:AdaptiveToggleActions = @($data.toggles)
        $script:AdaptiveEncoderActions = @($data.encoders)
        Write-Log ('Adaptive actions loaded: toggles={0}; encoders={1}' -f @($script:AdaptiveToggleActions).Count, @($script:AdaptiveEncoderActions).Count) 'DEBUG'
    }
    catch {
        Write-Log ('Failed to load Adaptive action config: {0}' -f $_.Exception.Message) 'WARN'
        $script:AdaptiveToggleActions = @()
        $script:AdaptiveEncoderActions = @()
    }
}

function Ensure-AdaptiveActionCapacity {
    param(
        [int]$ToggleCount = 0,
        [int]$EncoderCount = 0
    )

    Initialize-AdaptiveActions

    $toggles = @($script:AdaptiveToggleActions)
    while ($toggles.Count -lt $ToggleCount) {
        $toggles += [pscustomobject][ordered]@{ on = 'none'; off = 'none' }
    }
    $script:AdaptiveToggleActions = @($toggles)

    $encoders = @($script:AdaptiveEncoderActions)
    while ($encoders.Count -lt $EncoderCount) {
        $encoders += [pscustomobject][ordered]@{ cw = 'none'; ccw = 'none'; push = 'none' }
    }
    $script:AdaptiveEncoderActions = @($encoders)
}

function Test-ProfileButtonAction {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'none') { return $true }
    if ($Action -match '^mute:\d+$') { return $true }
    if ($Action -in @(
        'media:playpause',
        'media:previous',
        'media:next',
        'media:stop',
        'system:volumeup',
        'system:volumedown',
        'system:volumemute'
    )) { return $true }

    if ($script:VirtualGamepadFeatureAvailable -and (Test-MugenVirtualGamepadAction -Action $Action)) { return $true }

    if ($Action -match '^hotkey:(\d{1,3}):(\d{1,2})$') {
        $vk = [int]$Matches[1]
        $mask = [int]$Matches[2]
        return ($vk -gt 0 -and $vk -le 255 -and $mask -ge 0 -and $mask -le 15)
    }

    if ($Action -match '^(launch64|folder64|url64|command64):(.+)$') {
        $decoded = Decode-ButtonActionPayload -Payload $Matches[2]
        return (-not [string]::IsNullOrWhiteSpace($decoded))
    }

    return $false
}

function ConvertTo-SafeProfileButtonAction {
    param([string]$Action)
    if (Test-ProfileButtonAction -Action $Action) { return [string]$Action }
    return 'none'
}

function Copy-AdaptiveProfileButtons {
    param([object[]]$Items)
    $copy = @()
    foreach ($item in @($Items)) {
        $copy += ConvertTo-SafeProfileButtonAction -Action ([string]$item)
    }
    return $copy
}

function Get-BaseProfiledButtonActionContext {
    Initialize-ButtonActions

    $globalActions = @($script:ButtonActions | ForEach-Object { [string]$_ })
    $globalContext = [pscustomobject][ordered]@{
        Key = '__global__'
        Actions = @($globalActions)
    }

    # Button application profiles are protocol-agnostic. Legacy exposes no
    # momentary buttons, while Extended and Adaptive use the same established
    # button-action transport. With no matching profile (or an older profile
    # that has no button payload), Global remains the exact compatibility path.
    $profile = Get-ForegroundAdaptiveProfile
    if ($null -eq $profile) { return $globalContext }

    $profileButtons = @()
    if ($null -ne $profile.PSObject.Properties['buttons']) {
        $profileButtons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
    }

    # #89 profiles did not contain button mappings. Empty/missing means inherit
    # Global until the user explicitly edits/saves button mappings for that app.
    if ($profileButtons.Count -eq 0) { return $globalContext }

    $processName = Normalize-TargetName -Value ([string]$profile.process)
    if ([string]::IsNullOrWhiteSpace($processName)) { return $globalContext }

    return [pscustomobject][ordered]@{
        Key = $processName.ToLowerInvariant()
        Actions = @($profileButtons)
    }
}

function Get-ProfiledButtonActionContext {
    $baseContext = Get-BaseProfiledButtonActionContext
    return Resolve-AdaptiveLayerButtonContext -BaseContext $baseContext
}
function Get-ProfiledButtonAction {
    param([int]$ButtonIndex)

    if ($ButtonIndex -lt 0) { return 'none' }
    $context = Get-ProfiledButtonActionContext
    $actions = @($context.Actions)
    if ($ButtonIndex -ge $actions.Count) { return 'none' }

    return ConvertTo-SafeProfileButtonAction -Action ([string]$actions[$ButtonIndex])
}

function Copy-AdaptiveProfileToggles {
    param([object[]]$Items)
    $copy = @()
    foreach ($item in @($Items)) {
        $copy += [pscustomobject][ordered]@{
            on = ConvertTo-SafeAdaptiveAction -Action ([string]$item.on)
            off = ConvertTo-SafeAdaptiveAction -Action ([string]$item.off)
        }
    }
    return $copy
}

function Copy-AdaptiveProfileEncoders {
    param([object[]]$Items)
    $copy = @()
    foreach ($item in @($Items)) {
        $copy += [pscustomobject][ordered]@{
            cw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.cw)
            ccw = ConvertTo-SafeAdaptiveAction -Action ([string]$item.ccw)
            push = ConvertTo-SafeAdaptiveAction -Action ([string]$item.push)
        }
    }
    return $copy
}

function Initialize-AdaptiveProfiles {
    if ($script:AdaptiveProfilesLoaded) { return }
    $script:AdaptiveProfilesLoaded = $true
    $script:AdaptiveProfiles = @()

    if (-not (Test-Path -LiteralPath $script:AdaptiveProfileConfigPath -PathType Leaf)) { return }

    try {
        $data = Get-Content -LiteralPath $script:AdaptiveProfileConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $data -or $null -eq $data.PSObject.Properties['version'] -or [int]$data.version -ne 1) {
            throw 'Unsupported or missing Adaptive profile configuration version.'
        }

        $profiles = @()
        foreach ($raw in @($data.profiles)) {
            if ($null -eq $raw) { continue }
            $processName = Normalize-TargetName -Value ([string]$raw.process)
            if ([string]::IsNullOrWhiteSpace($processName)) { continue }

            $name = [string]$raw.name
            if ([string]::IsNullOrWhiteSpace($name)) { $name = Get-FriendlyProcessName -ProcessName $processName }

            $buttons = @()
            if ($null -ne $raw.PSObject.Properties['buttons']) {
                $buttons = @(Copy-AdaptiveProfileButtons -Items @($raw.buttons))
            }

            $profiles += [pscustomobject][ordered]@{
                name = $name
                process = $processName
                buttons = @($buttons)
                toggles = @(Copy-AdaptiveProfileToggles -Items @($raw.toggles))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($raw.encoders))
            }
        }
        $script:AdaptiveProfiles = @($profiles)
        Write-Log ('Adaptive application profiles loaded: {0}' -f $script:AdaptiveProfiles.Count) 'INFO'
    }
    catch {
        $script:AdaptiveProfiles = @()
        Write-Log ('Failed to load Adaptive application profiles: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Save-AdaptiveProfiles {
    Initialize-AdaptiveProfiles

    $profiles = @()
    foreach ($profile in @($script:AdaptiveProfiles)) {
        $buttons = @()
        if ($null -ne $profile.PSObject.Properties['buttons']) {
            $buttons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
        }

        $profiles += [pscustomobject][ordered]@{
            name = [string]$profile.name
            process = Normalize-TargetName -Value ([string]$profile.process)
            buttons = @($buttons)
            toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
            encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
        }
    }

    $payload = [pscustomobject][ordered]@{ version = 1; profiles = @($profiles) }
    $tempPath = $script:AdaptiveProfileConfigPath + '.tmp-' + $PID

    try {
        $json = $payload | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        $verify = Get-Content -LiteralPath $tempPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $verify -or [int]$verify.version -ne 1) { throw 'Adaptive profile verification failed.' }

        if (Test-Path -LiteralPath $script:AdaptiveProfileConfigPath) {
            try { [System.IO.File]::Replace($tempPath, $script:AdaptiveProfileConfigPath, $null, $true) }
            catch {
                Copy-Item -LiteralPath $tempPath -Destination $script:AdaptiveProfileConfigPath -Force
                Remove-Item -LiteralPath $tempPath -Force
            }
        }
        else {
            [System.IO.File]::Move($tempPath, $script:AdaptiveProfileConfigPath)
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Get-AdaptiveProfileForProcess {
    param([AllowEmptyString()][string]$ProcessName)

    Initialize-AdaptiveProfiles
    $normalized = Normalize-TargetName -Value $ProcessName
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }

    foreach ($profile in @($script:AdaptiveProfiles)) {
        if ((Normalize-TargetName -Value ([string]$profile.process)) -ieq $normalized) { return $profile }
    }
    return $null
}

function Get-ForegroundAdaptiveProfile {
    Initialize-AdaptiveProfiles

    try {
        $processName = Normalize-TargetName -Value ([MugenDeejWindowing.Foreground]::GetForegroundProcessName())
        if ([string]::IsNullOrWhiteSpace($processName)) { return $null }

        $selfName = Normalize-TargetName -Value ([System.Diagnostics.Process]::GetCurrentProcess().ProcessName)
        if ($processName -ieq $selfName -or $processName -ieq 'powershell' -or $processName -ieq 'pwsh') {
            return $null
        }

        return Get-AdaptiveProfileForProcess -ProcessName $processName
    }
    catch {
        return $null
    }
}

function Save-AdaptiveActions {
    Write-AdaptiveActionConfigFile -Path $script:AdaptiveActionConfigPath -Toggles @($script:AdaptiveToggleActions) -Encoders @($script:AdaptiveEncoderActions)
    Write-Log ('Adaptive actions saved: toggles={0}; encoders={1}' -f @($script:AdaptiveToggleActions).Count, @($script:AdaptiveEncoderActions).Count) 'INFO'
}

function Get-AdaptiveToggleMappedAction {
    param([int]$Index, [int]$State)

    Initialize-AdaptiveActions
    $profile = Get-ForegroundAdaptiveProfile
    $source = @(if ($null -ne $profile) { @($profile.toggles) } else { @($script:AdaptiveToggleActions) })

    if ($Index -lt 0 -or $Index -ge $source.Count) { return 'none' }
    if ($State -eq 1) { return ConvertTo-SafeAdaptiveAction -Action ([string]$source[$Index].on) }
    return ConvertTo-SafeAdaptiveAction -Action ([string]$source[$Index].off)
}

function Get-BaseAdaptiveEncoderMappedAction {
    param([int]$Index, [ValidateSet('cw','ccw','push')][string]$Kind)

    Initialize-AdaptiveActions
    $profile = Get-ForegroundAdaptiveProfile
    $source = @(if ($null -ne $profile) { @($profile.encoders) } else { @($script:AdaptiveEncoderActions) })

    if ($Index -lt 0 -or $Index -ge $source.Count) { return 'none' }
    return ConvertTo-SafeAdaptiveAction -Action ([string]$source[$Index].$Kind)
}

function Get-AdaptiveEncoderMappedAction {
    param([int]$Index, [ValidateSet('cw','ccw','push')][string]$Kind)

    $baseAction = Get-BaseAdaptiveEncoderMappedAction -Index $Index -Kind $Kind

    if ([string]$script:ControllerProtocol -ne 'adaptive') {
        return $baseAction
    }

    $layer = Get-AdaptiveLayerIndex
    if ($layer -le 0 -or -not (Test-AdaptiveLayersEnabled)) {
        return $baseAction
    }

    Initialize-AdaptiveLayers
    $contextKey = Get-AdaptiveLayerProfileKey
    $override = Get-AdaptiveLayerEncoderOverride -Config $script:AdaptiveLayerConfig -ContextKey $contextKey -Layer $layer -EncoderIndex $Index -Kind $Kind

    if ($override -eq 'inherit') {
        return $baseAction
    }

    return ConvertTo-SafeAdaptiveAction -Action $override
}
function Invoke-AdaptiveMappedAction {
    param(
        [string]$Action,
        [string]$Source = 'Adaptive control'
    )

    if (Test-MugenInputActionsSuspended) {
        Write-Log ('Adaptive mapped action suppressed while a modal Mugen dialog is open: {0}' -f $Source) 'DEBUG'
        return
    }

    $Action = ConvertTo-SafeAdaptiveAction -Action $Action
    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'none') { return }

    if ($Action -match '^mute:(\d+)$') {
        $sliderIndex = [int]$Matches[1]
        if ($script:IsConnected -and $sliderIndex -ge 0 -and $sliderIndex -lt [int]$script:DetectedSliderCount) {
            Toggle-SliderSoftMute -SliderIndex $sliderIndex
        }
        return
    }

    if ($Action -match '^hotkey:(\d{1,3}):(\d{1,2})$') {
        try {
            $keyCode = [int]$Matches[1]
            $mask = [int]$Matches[2]
            [MugenDeejWindowing.MugenHotkeys]::Send(
                $keyCode,
                (($mask -band 1) -ne 0),
                (($mask -band 2) -ne 0),
                (($mask -band 4) -ne 0),
                (($mask -band 8) -ne 0)
            )
            Write-Log ('Adaptive action: {0}; hotkey={1}' -f $Source, (Get-HotkeyActionDisplay -Action $Action)) 'INFO'
        }
        catch { Write-Log ('Adaptive hotkey failed: {0}; error={1}' -f $Source, $_.Exception.Message) 'WARN' }
        return
    }

    if ($Action -match '^command64:(.+)$') {
        try { Invoke-RunCommandAction -Command (Decode-ButtonActionPayload -Payload $Matches[1]); Write-Log ('Adaptive action: {0}; run command' -f $Source) 'INFO' }
        catch { Write-Log ('Adaptive command failed: {0}; error={1}' -f $Source, $_.Exception.Message) 'WARN' }
        return
    }

    if ($Action -match '^launch64:(.+)$') {
        $target = Decode-ButtonActionPayload -Payload $Matches[1]
        try {
            if ([string]::IsNullOrWhiteSpace($target) -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { throw ('Target file was not found: ' + $target) }
            Invoke-ShellButtonTarget -Target $target
            Write-Log ('Adaptive action: {0}; launch={1}' -f $Source, [System.IO.Path]::GetFileName($target)) 'INFO'
        }
        catch { Write-Log ('Adaptive launch failed: {0}; error={1}' -f $Source, $_.Exception.Message) 'WARN' }
        return
    }

    if ($Action -match '^folder64:(.+)$') {
        $target = Decode-ButtonActionPayload -Payload $Matches[1]
        try {
            if ([string]::IsNullOrWhiteSpace($target) -or -not (Test-Path -LiteralPath $target -PathType Container)) { throw ('Target folder was not found: ' + $target) }
            Invoke-ShellButtonTarget -Target $target
            Write-Log ('Adaptive action: {0}; folder={1}' -f $Source, $target) 'INFO'
        }
        catch { Write-Log ('Adaptive folder failed: {0}; error={1}' -f $Source, $_.Exception.Message) 'WARN' }
        return
    }

    if ($Action -match '^url64:(.+)$') {
        $target = Decode-ButtonActionPayload -Payload $Matches[1]
        try { Invoke-ShellButtonTarget -Target $target; Write-Log ('Adaptive action: {0}; URL' -f $Source) 'INFO' }
        catch { Write-Log ('Adaptive URL failed: {0}; error={1}' -f $Source, $_.Exception.Message) 'WARN' }
        return
    }

    try {
        switch ($Action) {
            'media:playpause' { [MugenDeejWindowing.MugenMediaKeys]::PlayPause(); break }
            'media:previous' { [MugenDeejWindowing.MugenMediaKeys]::PreviousTrack(); break }
            'media:next' { [MugenDeejWindowing.MugenMediaKeys]::NextTrack(); break }
            'media:stop' { [MugenDeejWindowing.MugenMediaKeys]::Stop(); break }
            'system:volumeup' { [MugenDeejWindowing.MugenMediaKeys]::VolumeUp(); break }
            'system:volumedown' { [MugenDeejWindowing.MugenMediaKeys]::VolumeDown(); break }
            'system:volumemute' { [MugenDeejWindowing.MugenMediaKeys]::VolumeMute(); break }
            'mouse:wheelup' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(1, $false, $false, $false, $false, $false); break }
            'mouse:wheeldown' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(-1, $false, $false, $false, $false, $false); break }
            'mouse:hwheelleft' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(-1, $true, $false, $false, $false, $false); break }
            'mouse:hwheelright' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(1, $true, $false, $false, $false, $false); break }
            'mouse:ctrlwheelup' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(1, $false, $true, $false, $false, $false); break }
            'mouse:ctrlwheeldown' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(-1, $false, $true, $false, $false, $false); break }
            'mouse:shiftwheelup' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(1, $false, $false, $true, $false, $false); break }
            'mouse:shiftwheeldown' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(-1, $false, $false, $true, $false, $false); break }
            'mouse:altwheelup' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(1, $false, $false, $false, $true, $false); break }
            'mouse:altwheeldown' { [MugenDeejWindowing.MugenMouseWheel]::Scroll(-1, $false, $false, $false, $true, $false); break }
            default { return }
        }
        Write-Log ('Adaptive action: {0}; action={1}' -f $Source, $Action) 'INFO'
    }
    catch { Write-Log ('Adaptive fixed action failed: {0}; action={1}; error={2}' -f $Source, $Action, $_.Exception.Message) 'WARN' }
}

function Populate-AdaptiveActionCombo {
    param(
        [Parameter(Mandatory = $true)]$Combo,
        [Parameter(Mandatory = $true)]$Map,
        [string]$CurrentAction = 'none'
    )

    $CurrentAction = ConvertTo-SafeAdaptiveAction -Action $CurrentAction
    $Combo.BeginUpdate()
    try {
        $Combo.Items.Clear()
        $Map.Clear()

        [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'None'))
        [void]$Map.Add('none')

        $sliderCount = [Math]::Min([int]$script:DetectedSliderCount, @($script:Config.sliders).Count)
        for ($sliderIndex = 0; $sliderIndex -lt $sliderCount; $sliderIndex++) {
            $name = [string]$script:Config.sliders[$sliderIndex].name
            if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]($sliderIndex + 1) }
            [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'MuteControl') + ' ' + ($sliderIndex + 1) + ' — ' + $name)
            [void]$Map.Add(('mute:' + $sliderIndex))
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
            [void]$Combo.Items.Add((Get-ButtonFeatureText -Key $fixedAction[0]))
            [void]$Map.Add([string]$fixedAction[1])
        }

        $mouseActions = if ($script:Language -eq 'ru') {
            @(
                @('Колесо мыши ↑', 'mouse:wheelup'),
                @('Колесо мыши ↓', 'mouse:wheeldown'),
                @('Горизонтальная прокрутка ←', 'mouse:hwheelleft'),
                @('Горизонтальная прокрутка →', 'mouse:hwheelright'),
                @('Ctrl + колесо ↑', 'mouse:ctrlwheelup'),
                @('Ctrl + колесо ↓', 'mouse:ctrlwheeldown'),
                @('Shift + колесо ↑', 'mouse:shiftwheelup'),
                @('Shift + колесо ↓', 'mouse:shiftwheeldown'),
                @('Alt + колесо ↑', 'mouse:altwheelup'),
                @('Alt + колесо ↓', 'mouse:altwheeldown')
            )
        }
        else {
            @(
                @('Mouse wheel ↑', 'mouse:wheelup'),
                @('Mouse wheel ↓', 'mouse:wheeldown'),
                @('Horizontal scroll ←', 'mouse:hwheelleft'),
                @('Horizontal scroll →', 'mouse:hwheelright'),
                @('Ctrl + wheel ↑', 'mouse:ctrlwheelup'),
                @('Ctrl + wheel ↓', 'mouse:ctrlwheeldown'),
                @('Shift + wheel ↑', 'mouse:shiftwheelup'),
                @('Shift + wheel ↓', 'mouse:shiftwheeldown'),
                @('Alt + wheel ↑', 'mouse:altwheelup'),
                @('Alt + wheel ↓', 'mouse:altwheeldown')
            )
        }
        foreach ($mouseAction in $mouseActions) {
            [void]$Combo.Items.Add([string]$mouseAction[0])
            [void]$Map.Add([string]$mouseAction[1])
        }

        if ($CurrentAction -match '^(hotkey:|launch64:|folder64:|command64:|url64:)') {
            [void]$Combo.Items.Add((Get-LargeButtonActionDisplay -Action $CurrentAction))
            [void]$Map.Add($CurrentAction)
        }

        [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'HotkeyConfigure'))
        [void]$Map.Add('hotkey:configure')
        if ($script:Language -eq 'ru') {
            [void]$Combo.Items.Add('Запустить программу / файл…')
            [void]$Combo.Items.Add('Открыть папку…')
            [void]$Combo.Items.Add('Выполнить команду…')
            [void]$Combo.Items.Add('Открыть URL…')
        }
        else {
            [void]$Combo.Items.Add('Launch program / file…')
            [void]$Combo.Items.Add('Open folder…')
            [void]$Combo.Items.Add('Run command…')
            [void]$Combo.Items.Add('Open URL…')
        }
        [void]$Map.Add('launch:configure')
        [void]$Map.Add('folder:configure')
        [void]$Map.Add('command:configure')
        [void]$Map.Add('url:configure')

        $selected = 0
        for ($i = 0; $i -lt $Map.Count; $i++) {
            if ([string]$Map[$i] -eq $CurrentAction) { $selected = $i; break }
        }
        $Combo.SelectedIndex = $selected
    }
    finally { $Combo.EndUpdate() }
}

function Resolve-AdaptiveConfiguredAction {
    param(
        [Parameter(Mandatory = $true)][string]$SelectedAction,
        [string]$PreviousAction = 'none'
    )

    switch ($SelectedAction) {
        'hotkey:configure' { return Show-HotkeyEditor -ExistingAction $PreviousAction }
        'launch:configure' { return Select-LaunchTargetAction -ExistingAction $PreviousAction }
        'folder:configure' { return Select-FolderTargetAction -ExistingAction $PreviousAction }
        'command:configure' { return Show-CommandActionEditor -ExistingAction $PreviousAction }
        'url:configure' { return Show-UrlActionEditor -ExistingAction $PreviousAction }
        default { return $SelectedAction }
    }
}

function Get-AdaptiveActionDisplay {
    param([string]$Action)

    $Action = ConvertTo-SafeAdaptiveAction -Action $Action
    $ru = ($script:Language -eq 'ru')

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'none') {
        return (Get-ButtonFeatureText -Key 'None')
    }

    if ($Action -match '^mute:(\d+)$') {
        $sliderIndex = [int]$Matches[1]
        $name = ''
        if ($sliderIndex -ge 0 -and $sliderIndex -lt @($script:Config.sliders).Count) {
            $name = [string]$script:Config.sliders[$sliderIndex].name
        }
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = [string]($sliderIndex + 1)
        }
        return ((Get-ButtonFeatureText -Key 'MuteControl') + ' ' + ($sliderIndex + 1) + ' — ' + $name)
    }

    switch ($Action) {
        'media:playpause' { return (Get-ButtonFeatureText -Key 'PlayPause') }
        'media:previous' { return (Get-ButtonFeatureText -Key 'PreviousTrack') }
        'media:next' { return (Get-ButtonFeatureText -Key 'NextTrack') }
        'media:stop' { return (Get-ButtonFeatureText -Key 'StopPlayback') }
        'system:volumeup' { return (Get-ButtonFeatureText -Key 'VolumeUp') }
        'system:volumedown' { return (Get-ButtonFeatureText -Key 'VolumeDown') }
        'system:volumemute' { return (Get-ButtonFeatureText -Key 'VolumeMute') }
        'mouse:wheelup' { return $(if ($ru) { 'Колесо мыши ↑' } else { 'Mouse wheel ↑' }) }
        'mouse:wheeldown' { return $(if ($ru) { 'Колесо мыши ↓' } else { 'Mouse wheel ↓' }) }
        'mouse:hwheelleft' { return $(if ($ru) { 'Горизонтальная прокрутка ←' } else { 'Horizontal scroll ←' }) }
        'mouse:hwheelright' { return $(if ($ru) { 'Горизонтальная прокрутка →' } else { 'Horizontal scroll →' }) }
        'mouse:ctrlwheelup' { return ('Ctrl + ' + $(if ($ru) { 'колесо ↑' } else { 'wheel ↑' })) }
        'mouse:ctrlwheeldown' { return ('Ctrl + ' + $(if ($ru) { 'колесо ↓' } else { 'wheel ↓' })) }
        'mouse:shiftwheelup' { return ('Shift + ' + $(if ($ru) { 'колесо ↑' } else { 'wheel ↑' })) }
        'mouse:shiftwheeldown' { return ('Shift + ' + $(if ($ru) { 'колесо ↓' } else { 'wheel ↓' })) }
        'mouse:altwheelup' { return ('Alt + ' + $(if ($ru) { 'колесо ↑' } else { 'wheel ↑' })) }
        'mouse:altwheeldown' { return ('Alt + ' + $(if ($ru) { 'колесо ↓' } else { 'wheel ↓' })) }
    }

    if ($Action -match '^hotkey:') { return (Get-HotkeyActionDisplay -Action $Action) }
    if ($Action -match '^launch64:') { return (Get-LaunchActionDisplay -Action $Action) }
    if ($Action -match '^folder64:') { return (Get-FolderActionDisplay -Action $Action) }
    if ($Action -match '^command64:') { return (Get-CommandActionDisplay -Action $Action) }
    if ($Action -match '^url64:') { return (Get-UrlActionDisplay -Action $Action) }

    return $Action
}

function New-DefaultAdaptiveLayerConfig {
    return [pscustomobject][ordered]@{
        version = 1
        modifierToggles = @($false, $false)
        names = [pscustomobject][ordered]@{
            base = ''
            t1 = ''
            t2 = ''
            both = ''
        }
        notification = [pscustomobject][ordered]@{
            enabled = $false
            topMost = $true
            screen = ''
            position = 'topRight'
            durationMs = 2000
            opacityPercent = 50
        }
        contexts = @()
    }
}

function ConvertTo-SafeAdaptiveLayerCustomName {
    param([string]$Value)

    if ($null -eq $Value) { return '' }

    $safe = ([string]$Value) -replace '[\r\n\t]+', ' '
    $safe = $safe.Trim()
    if ($safe.Length -gt 24) {
        $safe = $safe.Substring(0, 24).TrimEnd()
    }

    return $safe
}

function ConvertTo-SafeAdaptiveLayerButtonOverride {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'inherit') {
        return 'inherit'
    }

    return ConvertTo-SafeProfileButtonAction -Action $Action
}

function ConvertTo-SafeAdaptiveLayerTypedOverride {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'inherit') {
        return 'inherit'
    }

    return ConvertTo-SafeAdaptiveAction -Action $Action
}

function Normalize-AdaptiveLayerContextKey {
    param([string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key) -or $Key -eq '__global__') {
        return '__global__'
    }

    $normalized = Normalize-TargetName -Value $Key
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return '__global__'
    }

    return $normalized.ToLowerInvariant()
}

function ConvertTo-NormalizedAdaptiveLayerConfig {
    param($Data)

    $result = New-DefaultAdaptiveLayerConfig
    if ($null -eq $Data) { return $result }

    if ($null -ne $Data.PSObject.Properties['modifierToggles']) {
        $mods = @($Data.modifierToggles)
        $result.modifierToggles = @(
            $(if ($mods.Count -gt 0) { [bool]$mods[0] } else { $false }),
            $(if ($mods.Count -gt 1) { [bool]$mods[1] } else { $false })
        )
    }

    if ($null -ne $Data.PSObject.Properties['names'] -and $null -ne $Data.names) {
        foreach ($nameKey in @('base','t1','t2','both')) {
            $nameProperty = $Data.names.PSObject.Properties[$nameKey]
            if ($null -ne $nameProperty) {
                $result.names.$nameKey = ConvertTo-SafeAdaptiveLayerCustomName -Value ([string]$nameProperty.Value)
            }
        }
    }

    if ($null -ne $Data.PSObject.Properties['notification'] -and $null -ne $Data.notification) {
        $notification = $Data.notification

        if ($null -ne $notification.PSObject.Properties['enabled']) {
            $result.notification.enabled = [bool]$notification.enabled
        }
        if ($null -ne $notification.PSObject.Properties['topMost']) {
            $result.notification.topMost = [bool]$notification.topMost
        }
        if ($null -ne $notification.PSObject.Properties['screen']) {
            $result.notification.screen = ([string]$notification.screen).Trim()
        }

        $validPositions = @(
            'topLeft','topCenter','topRight',
            'middleLeft','center','middleRight',
            'bottomLeft','bottomCenter','bottomRight'
        )
        if ($null -ne $notification.PSObject.Properties['position']) {
            $candidatePosition = [string]$notification.position
            if ($candidatePosition -in $validPositions) {
                $result.notification.position = $candidatePosition
            }
        }

        if ($null -ne $notification.PSObject.Properties['durationMs']) {
            $duration = [int]$notification.durationMs
            if ($duration -lt 500) { $duration = 500 }
            if ($duration -gt 10000) { $duration = 10000 }
            $result.notification.durationMs = $duration
        }

        if ($null -ne $notification.PSObject.Properties['opacityPercent']) {
            $opacityPercent = [int]$notification.opacityPercent
            if ($opacityPercent -lt 20) { $opacityPercent = 20 }
            if ($opacityPercent -gt 100) { $opacityPercent = 100 }
            $result.notification.opacityPercent = $opacityPercent
        }
    }

    $seen = @{}
    $contexts = @()
    if ($null -ne $Data.PSObject.Properties['contexts']) {
        foreach ($raw in @($Data.contexts)) {
            if ($null -eq $raw) { continue }

            $key = Normalize-AdaptiveLayerContextKey -Key ([string]$raw.key)
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            $context = [pscustomobject][ordered]@{
                key = $key
                t1 = @()
                t2 = @()
                both = @()
                t1Encoders = @()
                t2Encoders = @()
                bothEncoders = @()
            }

            foreach ($layerName in @('t1','t2','both')) {
                $safe = @()
                $property = $raw.PSObject.Properties[$layerName]
                if ($null -ne $property) {
                    foreach ($action in @($property.Value)) {
                        $safe += ConvertTo-SafeAdaptiveLayerButtonOverride -Action ([string]$action)
                    }
                }
                $context.$layerName = @($safe)

                $encoderField = $layerName + 'Encoders'
                $safeEncoders = @()
                $encoderProperty = $raw.PSObject.Properties[$encoderField]
                if ($null -ne $encoderProperty) {
                    foreach ($encoder in @($encoderProperty.Value)) {
                        if ($null -eq $encoder) { continue }
                        $safeEncoders += [pscustomobject][ordered]@{
                            cw = ConvertTo-SafeAdaptiveLayerTypedOverride -Action ([string]$encoder.cw)
                            ccw = ConvertTo-SafeAdaptiveLayerTypedOverride -Action ([string]$encoder.ccw)
                            push = ConvertTo-SafeAdaptiveLayerTypedOverride -Action ([string]$encoder.push)
                        }
                    }
                }
                $context.$encoderField = @($safeEncoders)
            }

            $contexts += $context
        }
    }

    $result.contexts = @($contexts)
    return $result
}

function Read-AdaptiveLayerConfigFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $data) { throw 'Adaptive layer configuration is empty.' }
    if ($null -eq $data.PSObject.Properties['version'] -or [int]$data.version -ne 1) {
        throw 'Unsupported or missing Adaptive layer configuration version.'
    }

    return ConvertTo-NormalizedAdaptiveLayerConfig -Data $data
}

function Write-AdaptiveLayerConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Config
    )

    $safe = ConvertTo-NormalizedAdaptiveLayerConfig -Data $Config
    $tempPath = "$Path.tmp-$PID"

    try {
        $json = $safe | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        $verified = Read-AdaptiveLayerConfigFile -Path $tempPath

        if (@($verified.modifierToggles).Count -ne 2) {
            throw 'Adaptive layer configuration failed modifier verification.'
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

        [void](Read-AdaptiveLayerConfigFile -Path $Path)
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Initialize-AdaptiveLayers {
    if ($script:AdaptiveLayersLoaded) { return }

    $script:AdaptiveLayersLoaded = $true
    $script:AdaptiveLayerConfig = New-DefaultAdaptiveLayerConfig

    if (-not (Test-Path -LiteralPath $script:AdaptiveLayerConfigPath -PathType Leaf)) {
        return
    }

    try {
        $script:AdaptiveLayerConfig = Read-AdaptiveLayerConfigFile -Path $script:AdaptiveLayerConfigPath
        Write-Log (
            'Adaptive layers loaded: modifierToggles={0},{1}; contexts={2}' -f
            [bool]$script:AdaptiveLayerConfig.modifierToggles[0],
            [bool]$script:AdaptiveLayerConfig.modifierToggles[1],
            @($script:AdaptiveLayerConfig.contexts).Count
        ) 'DEBUG'
    }
    catch {
        $script:AdaptiveLayerConfig = New-DefaultAdaptiveLayerConfig
        Write-Log ('Failed to load Adaptive layer config; defaults restored: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Save-AdaptiveLayers {
    Initialize-AdaptiveLayers
    Write-AdaptiveLayerConfigFile -Path $script:AdaptiveLayerConfigPath -Config $script:AdaptiveLayerConfig
    Write-Log (
        'Adaptive layers saved: modifierToggles={0},{1}; contexts={2}' -f
        [bool]$script:AdaptiveLayerConfig.modifierToggles[0],
        [bool]$script:AdaptiveLayerConfig.modifierToggles[1],
        @($script:AdaptiveLayerConfig.contexts).Count
    ) 'INFO'
}

function Copy-AdaptiveLayerConfig {
    param($Config)

    if ($null -eq $Config) {
        return New-DefaultAdaptiveLayerConfig
    }

    $json = $Config | ConvertTo-Json -Depth 12
    return ConvertTo-NormalizedAdaptiveLayerConfig -Data ($json | ConvertFrom-Json)
}

function Get-AdaptiveLayerContextObject {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$Key = '__global__',
        [switch]$Create
    )

    $normalized = Normalize-AdaptiveLayerContextKey -Key $Key
    foreach ($context in @($Config.contexts)) {
        if ([string]$context.key -eq $normalized) {
            return $context
        }
    }

    if (-not $Create) { return $null }

    $created = [pscustomobject][ordered]@{
        key = $normalized
        t1 = @()
        t2 = @()
        both = @()
        t1Encoders = @()
        t2Encoders = @()
        bothEncoders = @()
    }

    $contexts = @($Config.contexts)
    $contexts += $created
    $Config.contexts = @($contexts)
    return $created
}

function Ensure-AdaptiveLayerContextCapacity {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [int]$ButtonCount
    )

    if ($ButtonCount -lt 0) { $ButtonCount = 0 }

    foreach ($layerName in @('t1','t2','both')) {
        $actions = @($Context.$layerName)
        while ($actions.Count -lt $ButtonCount) {
            $actions += 'inherit'
        }
        $Context.$layerName = @($actions)
    }
}

function Ensure-AdaptiveLayerEncoderCapacity {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [int]$EncoderCount
    )

    if ($EncoderCount -lt 0) { $EncoderCount = 0 }

    foreach ($field in @('t1Encoders','t2Encoders','bothEncoders')) {
        $items = @($Context.$field)
        while ($items.Count -lt $EncoderCount) {
            $items += [pscustomobject][ordered]@{
                cw = 'inherit'
                ccw = 'inherit'
                push = 'inherit'
            }
        }
        $Context.$field = @($items)
    }
}

function Get-AdaptiveLayerNameForIndex {
    param([int]$Layer)

    switch ($Layer) {
        1 { return 't1' }
        2 { return 't2' }
        3 { return 'both' }
        default { return '' }
    }
}

function Get-AdaptiveLayerDefaultDisplayName {
    param([int]$Layer)

    if ($script:Language -eq 'ru') {
        switch ($Layer) {
            1 { return 'T1' }
            2 { return 'T2' }
            3 { return 'T1 + T2' }
            default { return 'Основной' }
        }
    }

    switch ($Layer) {
        1 { return 'T1' }
        2 { return 'T2' }
        3 { return 'T1 + T2' }
        default { return 'Base' }
    }
}

function Get-AdaptiveLayerCustomNameKey {
    param([int]$Layer)

    switch ($Layer) {
        1 { return 't1' }
        2 { return 't2' }
        3 { return 'both' }
        default { return 'base' }
    }
}

function Get-AdaptiveLayerDisplayNameFromConfig {
    param(
        $Config,
        [int]$Layer
    )

    $fallback = Get-AdaptiveLayerDefaultDisplayName -Layer $Layer
    if ($null -eq $Config -or $null -eq $Config.PSObject.Properties['names'] -or $null -eq $Config.names) {
        return $fallback
    }

    $key = Get-AdaptiveLayerCustomNameKey -Layer $Layer
    $property = $Config.names.PSObject.Properties[$key]
    if ($null -eq $property) { return $fallback }

    $custom = ConvertTo-SafeAdaptiveLayerCustomName -Value ([string]$property.Value)
    if ([string]::IsNullOrWhiteSpace($custom)) { return $fallback }

    return $custom
}

function Get-AdaptiveLayerDisplayName {
    param([int]$Layer)

    Initialize-AdaptiveLayers
    return Get-AdaptiveLayerDisplayNameFromConfig -Config $script:AdaptiveLayerConfig -Layer $Layer
}

function Set-AdaptiveLayerComboDisplayItems {
    param(
        [Parameter(Mandatory = $true)]$Combo,
        [Parameter(Mandatory = $true)]$Config
    )

    $selected = [int]$Combo.SelectedIndex
    if ($selected -lt 0 -or $selected -gt 2) { $selected = 0 }

    $Combo.BeginUpdate()
    try {
        $Combo.Items.Clear()
        for ($layer = 1; $layer -le 3; $layer++) {
            [void]$Combo.Items.Add((Get-AdaptiveLayerDisplayNameFromConfig -Config $Config -Layer $layer))
        }
        $Combo.SelectedIndex = $selected
    }
    finally {
        $Combo.EndUpdate()
    }
}

function Get-AdaptiveLayerNotificationScreen {
    param($Config)

    $screens = @([System.Windows.Forms.Screen]::AllScreens)
    if ($screens.Count -le 0) { return $null }

    $deviceName = ''
    if (
        $null -ne $Config -and
        $null -ne $Config.PSObject.Properties['notification'] -and
        $null -ne $Config.notification
    ) {
        $deviceName = ([string]$Config.notification.screen).Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($deviceName)) {
        foreach ($screen in $screens) {
            if ([string]$screen.DeviceName -eq $deviceName) {
                return $screen
            }
        }
    }

    foreach ($screen in $screens) {
        if ($screen.Primary) { return $screen }
    }

    return $screens[0]
}

function Get-AdaptiveLayerPopupLocation {
    param(
        [Parameter(Mandatory = $true)]$Screen,
        [string]$Position,
        [int]$Width,
        [int]$Height
    )

    $area = $Screen.WorkingArea
    $margin = 24

    $leftX = $area.Left + $margin
    $centerX = $area.Left + [int](($area.Width - $Width) / 2)
    $rightX = $area.Right - $Width - $margin

    $topY = $area.Top + $margin
    $centerY = $area.Top + [int](($area.Height - $Height) / 2)
    $bottomY = $area.Bottom - $Height - $margin

    switch ($Position) {
        'topLeft'      { return [System.Drawing.Point]::new($leftX, $topY) }
        'topCenter'    { return [System.Drawing.Point]::new($centerX, $topY) }
        'middleLeft'   { return [System.Drawing.Point]::new($leftX, $centerY) }
        'center'       { return [System.Drawing.Point]::new($centerX, $centerY) }
        'middleRight'  { return [System.Drawing.Point]::new($rightX, $centerY) }
        'bottomLeft'   { return [System.Drawing.Point]::new($leftX, $bottomY) }
        'bottomCenter' { return [System.Drawing.Point]::new($centerX, $bottomY) }
        'bottomRight'  { return [System.Drawing.Point]::new($rightX, $bottomY) }
        default        { return [System.Drawing.Point]::new($rightX, $topY) }
    }
}

function Close-AdaptiveLayerNotification {
    if ($null -ne $script:AdaptiveLayerPopupTimer) {
        try {
            $script:AdaptiveLayerPopupTimer.Stop()
            $script:AdaptiveLayerPopupTimer.Dispose()
        }
        catch {}
        $script:AdaptiveLayerPopupTimer = $null
    }

    if ($null -ne $script:AdaptiveLayerPopupForm) {
        try {
            if (-not $script:AdaptiveLayerPopupForm.IsDisposed) {
                $script:AdaptiveLayerPopupForm.Close()
                $script:AdaptiveLayerPopupForm.Dispose()
            }
        }
        catch {}
        $script:AdaptiveLayerPopupForm = $null
    }
}

function Show-AdaptiveLayerNotification {
    param(
        [int]$Layer,
        $Config = $null,
        [switch]$Force
    )

    if ($null -eq $Config) {
        Initialize-AdaptiveLayers
        $Config = $script:AdaptiveLayerConfig
    }

    if (
        $null -eq $Config -or
        $null -eq $Config.PSObject.Properties['notification'] -or
        $null -eq $Config.notification
    ) {
        return
    }

    if (-not $Force -and -not [bool]$Config.notification.enabled) {
        return
    }

    $screen = Get-AdaptiveLayerNotificationScreen -Config $Config
    if ($null -eq $screen) { return }

    Close-AdaptiveLayerNotification

    $displayName = Get-AdaptiveLayerDisplayNameFromConfig -Config $Config -Layer $Layer
    $captionText = if ($script:Language -eq 'ru') { 'Активный слой' } else { 'Active layer' }
    $nameFont = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
    $captionFont = New-Object System.Drawing.Font('Segoe UI', 9)
    $measureFlags = [System.Windows.Forms.TextFormatFlags]::SingleLine -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
    $measuredName = [System.Windows.Forms.TextRenderer]::MeasureText(
        $displayName,
        $nameFont,
        [System.Drawing.Size]::new(2000, 80),
        $measureFlags
    )
    $measuredCaption = [System.Windows.Forms.TextRenderer]::MeasureText(
        $captionText,
        $captionFont,
        [System.Drawing.Size]::new(2000, 40),
        $measureFlags
    )
    $contentWidth = [Math]::Max([int]$measuredName.Width, [int]$measuredCaption.Width)
    $availablePopupWidth = [Math]::Max(170, ([int]$screen.WorkingArea.Width - 48))
    $maximumPopupWidth = [Math]::Min(620, $availablePopupWidth)
    $minimumPopupWidth = [Math]::Min(170, $maximumPopupWidth)
    $popupWidth = [Math]::Max(
        $minimumPopupWidth,
        [Math]::Min($maximumPopupWidth, ($contentWidth + 44))
    )
    $popupHeight = 88

    $popup = New-Object MugenDeejWindowing.MugenLayerPopupForm
    $popup.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $popup.ShowInTaskbar = $false
    $popup.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $popup.TopMost = [bool]$Config.notification.topMost
    $opacityPercent = [int]$Config.notification.opacityPercent
    if ($opacityPercent -lt 20) { $opacityPercent = 20 }
    if ($opacityPercent -gt 100) { $opacityPercent = 100 }
    $popup.ClientSize = [System.Drawing.Size]::new($popupWidth, $popupHeight)
    $popup.MinimumSize = $popup.Size
    $popup.MaximumSize = $popup.Size
    $popup.Padding = New-Object System.Windows.Forms.Padding(0)

    $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
    $popup.ConfigureSurface(
        $captionText,
        $displayName,
        $palette.Surface,
        $palette.Border,
        $palette.Muted,
        $palette.Text,
        14,
        $opacityPercent
    )

    $nameFont.Dispose()
    $captionFont.Dispose()

    $position = [string]$Config.notification.position
    $popup.Location = Get-AdaptiveLayerPopupLocation -Screen $screen -Position $position -Width $popup.Width -Height $popup.Height

    $duration = [int]$Config.notification.durationMs
    if ($duration -lt 500) { $duration = 500 }
    if ($duration -gt 10000) { $duration = 10000 }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $duration
    $timer.Add_Tick({
        Close-AdaptiveLayerNotification
    })

    $script:AdaptiveLayerPopupForm = $popup
    $script:AdaptiveLayerPopupTimer = $timer

    $popup.Show()
    $timer.Start()
}

function Get-AdaptiveLayerNotificationPositionDisplay {
    param([string]$Position)

    if ($script:Language -eq 'ru') {
        switch ($Position) {
            'topLeft'      { return 'Слева сверху' }
            'topCenter'    { return 'По центру сверху' }
            'topRight'     { return 'Справа сверху' }
            'middleLeft'   { return 'Слева по центру' }
            'center'       { return 'По центру' }
            'middleRight'  { return 'Справа по центру' }
            'bottomLeft'   { return 'Слева снизу' }
            'bottomCenter' { return 'По центру снизу' }
            'bottomRight'  { return 'Справа снизу' }
        }
    }

    switch ($Position) {
        'topLeft'      { return 'Top left' }
        'topCenter'    { return 'Top center' }
        'topRight'     { return 'Top right' }
        'middleLeft'   { return 'Middle left' }
        'center'       { return 'Center' }
        'middleRight'  { return 'Middle right' }
        'bottomLeft'   { return 'Bottom left' }
        'bottomCenter' { return 'Bottom center' }
        'bottomRight'  { return 'Bottom right' }
        default        { return $Position }
    }
}

function Show-AdaptiveLayerNotificationSettings {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [System.Windows.Forms.IWin32Window]$Owner
    )

    $workingNotification = ConvertTo-NormalizedAdaptiveLayerConfig -Data $Config
    $workingNotification = $workingNotification.notification

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = if ($script:Language -eq 'ru') { 'Уведомление о смене слоя — Mugen Deej' } else { 'Layer-change notification — Mugen Deej' }
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ClientSize = [System.Drawing.Size]::new(700, 392)
    $dialog.MinimumSize = [System.Drawing.Size]::new(716, 431)
    $dialog.MaximumSize = [System.Drawing.Size]::new(716, 431)
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.Font = $form.Font
    Set-FormAppIcon -Form $dialog

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = if ($script:Language -eq 'ru') { 'Всплывающее уведомление' } else { 'Popup notification' }
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $dialog.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = if ($script:Language -eq 'ru') {
        'Показывает имя активного слоя при переключении T1/T2.' + "`r`n" + 'Экран и позиция выбираются отдельно для многомониторной системы.'
    }
    else {
        'Shows the active layer name when T1/T2 changes.' + "`r`n" + 'Choose a specific display and anchor for multi-monitor setups.'
    }
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 57)
    $hint.Size = [System.Drawing.Size]::new(650, 42)
    $dialog.Controls.Add($hint)

    $card = New-Object MugenDeejWindowing.MugenGroupBox
    $card.Text = if ($script:Language -eq 'ru') { 'Параметры' } else { 'Options' }
    $card.Location = [System.Drawing.Point]::new(22, 110)
    $card.Size = [System.Drawing.Size]::new(656, 210)
    $dialog.Controls.Add($card)

    $enabledCheck = New-Object System.Windows.Forms.CheckBox
    $enabledCheck.Text = if ($script:Language -eq 'ru') { 'Показывать уведомление при смене слоя' } else { 'Show a notification when the layer changes' }
    $enabledCheck.AutoSize = $true
    $enabledCheck.Location = [System.Drawing.Point]::new(16, 30)
    $enabledCheck.Checked = [bool]$workingNotification.enabled
    $card.Controls.Add($enabledCheck)

    $topMostCheck = New-Object System.Windows.Forms.CheckBox
    $topMostCheck.Text = if ($script:Language -eq 'ru') { 'Показывать поверх окон' } else { 'Show above other windows' }
    $topMostCheck.AutoSize = $true
    $topMostCheck.Location = [System.Drawing.Point]::new(350, 30)
    $topMostCheck.Checked = [bool]$workingNotification.topMost
    $card.Controls.Add($topMostCheck)

    $screenLabel = New-Object System.Windows.Forms.Label
    $screenLabel.Text = if ($script:Language -eq 'ru') { 'Экран' } else { 'Display' }
    $screenLabel.Location = [System.Drawing.Point]::new(16, 72)
    $screenLabel.Size = [System.Drawing.Size]::new(90, 25)
    $screenLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $card.Controls.Add($screenLabel)

    $screenCombo = New-Object MugenDeejWindowing.MugenComboBox
    $screenCombo.DropDownStyle = 'DropDownList'
    $screenCombo.Location = [System.Drawing.Point]::new(105, 70)
    $screenCombo.Size = [System.Drawing.Size]::new(525, 30)
    $card.Controls.Add($screenCombo)

    $screenMap = New-Object System.Collections.ArrayList
    $screens = @([System.Windows.Forms.Screen]::AllScreens)
    $screenSelected = 0
    for ($i = 0; $i -lt $screens.Count; $i++) {
        $screen = $screens[$i]
        $bounds = $screen.Bounds
        $primarySuffix = if ($screen.Primary) {
            $(if ($script:Language -eq 'ru') { ' · основной' } else { ' · primary' })
        }
        else { '' }

        $label = '{0}. {1} · {2}x{3}{4}' -f ($i + 1), $screen.DeviceName, $bounds.Width, $bounds.Height, $primarySuffix
        [void]$screenCombo.Items.Add($label)
        [void]$screenMap.Add([string]$screen.DeviceName)

        if (
            -not [string]::IsNullOrWhiteSpace([string]$workingNotification.screen) -and
            [string]$workingNotification.screen -eq [string]$screen.DeviceName
        ) {
            $screenSelected = $i
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$workingNotification.screen) -and $screen.Primary) {
            $screenSelected = $i
        }
    }
    if ($screenCombo.Items.Count -gt 0) { $screenCombo.SelectedIndex = $screenSelected }

    $positionLabel = New-Object System.Windows.Forms.Label
    $positionLabel.Text = if ($script:Language -eq 'ru') { 'Положение' } else { 'Position' }
    $positionLabel.Location = [System.Drawing.Point]::new(16, 116)
    $positionLabel.Size = [System.Drawing.Size]::new(90, 25)
    $positionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $card.Controls.Add($positionLabel)

    $positionCombo = New-Object MugenDeejWindowing.MugenComboBox
    $positionCombo.DropDownStyle = 'DropDownList'
    $positionCombo.Location = [System.Drawing.Point]::new(105, 114)
    $positionCombo.Size = [System.Drawing.Size]::new(220, 30)
    $card.Controls.Add($positionCombo)

    $positionMap = New-Object System.Collections.ArrayList
    foreach ($position in @(
        'topLeft','topCenter','topRight',
        'middleLeft','center','middleRight',
        'bottomLeft','bottomCenter','bottomRight'
    )) {
        [void]$positionCombo.Items.Add((Get-AdaptiveLayerNotificationPositionDisplay -Position $position))
        [void]$positionMap.Add($position)
    }
    $positionSelected = $positionMap.IndexOf([string]$workingNotification.position)
    if ($positionSelected -lt 0) { $positionSelected = 2 }
    $positionCombo.SelectedIndex = $positionSelected

    $durationLabel = New-Object System.Windows.Forms.Label
    $durationLabel.Text = if ($script:Language -eq 'ru') { 'Показывать, сек' } else { 'Duration, sec' }
    $durationLabel.Location = [System.Drawing.Point]::new(350, 116)
    $durationLabel.Size = [System.Drawing.Size]::new(120, 25)
    $durationLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $card.Controls.Add($durationLabel)

    $durationBox = New-Object System.Windows.Forms.NumericUpDown
    $durationBox.DecimalPlaces = 1
    $durationBox.Increment = [decimal]0.5
    $durationBox.Minimum = [decimal]0.5
    $durationBox.Maximum = [decimal]10.0
    $durationBox.Location = [System.Drawing.Point]::new(480, 115)
    $durationBox.Size = [System.Drawing.Size]::new(100, 26)
    $durationBox.Value = [decimal]([double]$workingNotification.durationMs / 1000.0)
    $card.Controls.Add($durationBox)

    $opacityLabel = New-Object System.Windows.Forms.Label
    $opacityLabel.Text = if ($script:Language -eq 'ru') { 'Непрозрачность, %' } else { 'Opacity, %' }
    $opacityLabel.Location = [System.Drawing.Point]::new(16, 162)
    $opacityLabel.Size = [System.Drawing.Size]::new(140, 25)
    $opacityLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $card.Controls.Add($opacityLabel)

    $opacityBox = New-Object System.Windows.Forms.NumericUpDown
    $opacityBox.DecimalPlaces = 0
    $opacityBox.Increment = [decimal]5
    $opacityBox.Minimum = [decimal]20
    $opacityBox.Maximum = [decimal]100
    $opacityBox.Location = [System.Drawing.Point]::new(160, 161)
    $opacityBox.Size = [System.Drawing.Size]::new(90, 26)
    $opacityBox.Value = [decimal][int]$workingNotification.opacityPercent
    $card.Controls.Add($opacityBox)

    $testButton = New-Object MugenDeejWindowing.MugenButton
    $testButton.Text = if ($script:Language -eq 'ru') { 'Тест уведомления' } else { 'Test notification' }
    $testButton.Location = [System.Drawing.Point]::new(440, 160)
    $testButton.Size = [System.Drawing.Size]::new(190, 34)
    $card.Controls.Add($testButton)

    $readControls = {
        $workingNotification.enabled = [bool]$enabledCheck.Checked
        $workingNotification.topMost = [bool]$topMostCheck.Checked

        $screenIndex = [int]$screenCombo.SelectedIndex
        if ($screenIndex -ge 0 -and $screenIndex -lt $screenMap.Count) {
            $workingNotification.screen = [string]$screenMap[$screenIndex]
        }

        $positionIndex = [int]$positionCombo.SelectedIndex
        if ($positionIndex -ge 0 -and $positionIndex -lt $positionMap.Count) {
            $workingNotification.position = [string]$positionMap[$positionIndex]
        }

        $workingNotification.durationMs = [int]([decimal]$durationBox.Value * 1000)
        $workingNotification.opacityPercent = [int]$opacityBox.Value
    }

    $testButton.Add_Click({
        & $readControls
        $previewConfig = ConvertTo-NormalizedAdaptiveLayerConfig -Data $Config
        $previewConfig.notification = $workingNotification
        $previewLayer = Get-AdaptiveLayerIndex
        Show-AdaptiveLayerNotification -Layer $previewLayer -Config $previewConfig -Force
    })

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(450, 340)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $dialog.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(568, 340)
    $save.Size = [System.Drawing.Size]::new(108, 36)
    $dialog.Controls.Add($save)

    $save.Add_Click({
        & $readControls
        $Config.notification = $workingNotification
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    Apply-ThemeToForm -Form $dialog
    $dialog.AcceptButton = $save
    $dialog.CancelButton = $cancel

    $dialog.Add_Shown({
        Ensure-FormVisible -Form $dialog -CenterIfOffscreen
    })

    if ($null -eq $Owner) {
        [void]$dialog.ShowDialog($form)
    }
    else {
        [void]$dialog.ShowDialog($Owner)
    }

    if (-not $dialog.IsDisposed) { $dialog.Dispose() }
}

function Get-AdaptiveLayerIndexFromValues {
    param([object[]]$Values)

    # Hard compatibility gate: Legacy and Extended do not participate in
    # toggle layers and retain their established flat button mappings.
    if ([string]$script:ControllerProtocol -ne 'adaptive') { return 0 }

    Initialize-AdaptiveLayers
    $mods = @($script:AdaptiveLayerConfig.modifierToggles)
    $valuesArray = @($Values)
    $layer = 0

    if (
        $mods.Count -gt 0 -and
        [bool]$mods[0] -and
        $valuesArray.Count -gt 0 -and
        [int]$valuesArray[0] -eq 1
    ) {
        $layer = $layer -bor 1
    }

    if (
        $mods.Count -gt 1 -and
        [bool]$mods[1] -and
        $valuesArray.Count -gt 1 -and
        [int]$valuesArray[1] -eq 1
    ) {
        $layer = $layer -bor 2
    }

    return [int]$layer
}

function Get-AdaptiveLayerIndex {
    return Get-AdaptiveLayerIndexFromValues -Values @($script:LatestToggles)
}

function Test-AdaptiveLayersEnabled {
    if ([string]$script:ControllerProtocol -ne 'adaptive') { return $false }

    Initialize-AdaptiveLayers
    $mods = @($script:AdaptiveLayerConfig.modifierToggles)
    return (
        ($mods.Count -gt 0 -and [bool]$mods[0] -and [int]$script:DetectedToggleCount -gt 0) -or
        ($mods.Count -gt 1 -and [bool]$mods[1] -and [int]$script:DetectedToggleCount -gt 1)
    )
}

function Test-AdaptiveToggleIsLayerModifier {
    param([int]$Index)

    if ([string]$script:ControllerProtocol -ne 'adaptive') { return $false }
    if ($Index -lt 0 -or $Index -gt 1) { return $false }

    Initialize-AdaptiveLayers
    $mods = @($script:AdaptiveLayerConfig.modifierToggles)
    return (
        $mods.Count -gt $Index -and
        [bool]$mods[$Index] -and
        [int]$script:DetectedToggleCount -gt $Index
    )
}

function Get-AdaptiveLayerButtonOverride {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$ContextKey,
        [int]$Layer,
        [int]$ButtonIndex
    )

    if ($Layer -le 0 -or $ButtonIndex -lt 0) { return 'inherit' }

    $context = Get-AdaptiveLayerContextObject -Config $Config -Key $ContextKey
    if ($null -eq $context) { return 'inherit' }

    $layerName = Get-AdaptiveLayerNameForIndex -Layer $Layer
    if ([string]::IsNullOrWhiteSpace($layerName)) { return 'inherit' }

    $actions = @($context.$layerName)
    if ($ButtonIndex -ge $actions.Count) { return 'inherit' }

    return ConvertTo-SafeAdaptiveLayerButtonOverride -Action ([string]$actions[$ButtonIndex])
}

function Set-AdaptiveLayerButtonOverride {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$ContextKey,
        [int]$Layer,
        [int]$ButtonIndex,
        [string]$Action,
        [int]$ButtonCount
    )

    if ($Layer -le 0 -or $ButtonIndex -lt 0) { return }

    $context = Get-AdaptiveLayerContextObject -Config $Config -Key $ContextKey -Create
    Ensure-AdaptiveLayerContextCapacity -Context $context -ButtonCount $ButtonCount

    $layerName = Get-AdaptiveLayerNameForIndex -Layer $Layer
    if ([string]::IsNullOrWhiteSpace($layerName)) { return }

    $actions = @($context.$layerName)
    $actions[$ButtonIndex] = ConvertTo-SafeAdaptiveLayerButtonOverride -Action $Action
    $context.$layerName = @($actions)
}

function Get-AdaptiveLayerEncoderFieldName {
    param([int]$Layer)

    switch ($Layer) {
        1 { return 't1Encoders' }
        2 { return 't2Encoders' }
        3 { return 'bothEncoders' }
        default { return '' }
    }
}

function Get-AdaptiveLayerEncoderOverride {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$ContextKey,
        [int]$Layer,
        [int]$EncoderIndex,
        [ValidateSet('cw','ccw','push')][string]$Kind
    )

    if ($Layer -le 0 -or $EncoderIndex -lt 0) { return 'inherit' }

    $context = Get-AdaptiveLayerContextObject -Config $Config -Key $ContextKey
    if ($null -eq $context) { return 'inherit' }

    $field = Get-AdaptiveLayerEncoderFieldName -Layer $Layer
    if ([string]::IsNullOrWhiteSpace($field)) { return 'inherit' }

    $items = @($context.$field)
    if ($EncoderIndex -ge $items.Count) { return 'inherit' }

    return ConvertTo-SafeAdaptiveLayerTypedOverride -Action ([string]$items[$EncoderIndex].$Kind)
}

function Set-AdaptiveLayerEncoderOverride {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$ContextKey,
        [int]$Layer,
        [int]$EncoderIndex,
        [ValidateSet('cw','ccw','push')][string]$Kind,
        [string]$Action,
        [int]$EncoderCount
    )

    if ($Layer -le 0 -or $EncoderIndex -lt 0) { return }

    $context = Get-AdaptiveLayerContextObject -Config $Config -Key $ContextKey -Create
    Ensure-AdaptiveLayerEncoderCapacity -Context $context -EncoderCount $EncoderCount

    $field = Get-AdaptiveLayerEncoderFieldName -Layer $Layer
    if ([string]::IsNullOrWhiteSpace($field)) { return }

    $items = @($context.$field)
    $items[$EncoderIndex].$Kind = ConvertTo-SafeAdaptiveLayerTypedOverride -Action $Action
    $context.$field = @($items)
}

function Get-AdaptiveLayerBaseEncoderAction {
    param(
        [string]$ContextKey,
        [int]$EncoderIndex,
        [ValidateSet('cw','ccw','push')][string]$Kind
    )

    Initialize-AdaptiveActions
    Initialize-AdaptiveProfiles

    if ($EncoderIndex -lt 0) { return 'none' }

    $key = Normalize-AdaptiveLayerContextKey -Key $ContextKey
    $source = @($script:AdaptiveEncoderActions)

    if ($key -ne '__global__') {
        foreach ($profile in @($script:AdaptiveProfiles)) {
            $processName = Normalize-TargetName -Value ([string]$profile.process)
            if ([string]::IsNullOrWhiteSpace($processName)) { continue }
            if ($processName.ToLowerInvariant() -ne $key) { continue }

            $profileEncoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
            if ($profileEncoders.Count -gt 0) {
                $source = @($profileEncoders)
            }
            break
        }
    }

    if ($EncoderIndex -ge $source.Count) { return 'none' }
    return ConvertTo-SafeAdaptiveAction -Action ([string]$source[$EncoderIndex].$Kind)
}

function Populate-AdaptiveLayerTypedActionCombo {
    param(
        [Parameter(Mandatory = $true)]$Combo,
        [Parameter(Mandatory = $true)]$Map,
        [string]$CurrentAction = 'inherit'
    )

    $safe = ConvertTo-SafeAdaptiveLayerTypedOverride -Action $CurrentAction
    Populate-AdaptiveActionCombo -Combo $Combo -Map $Map -CurrentAction $(if ($safe -eq 'inherit') { 'none' } else { $safe })

    $inheritText = if ($script:Language -eq 'ru') { 'Как в основном слое' } else { 'Same as base layer' }
    $Combo.Items.Insert(0, $inheritText)
    $Map.Insert(0, 'inherit')

    if ($safe -eq 'inherit') {
        $Combo.SelectedIndex = 0
        return
    }

    for ($i = 0; $i -lt $Map.Count; $i++) {
        if ([string]$Map[$i] -eq $safe) {
            $Combo.SelectedIndex = $i
            break
        }
    }
}

function Show-AdaptiveLayerEncoderSettings {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [System.Windows.Forms.IWin32Window]$Owner
    )

    if (
        [string]$script:ControllerProtocol -ne 'adaptive' -or
        [int]$script:DetectedEncoderCount -le 0
    ) {
        return
    }

    Initialize-AdaptiveActions
    Initialize-AdaptiveProfiles

    $encoderLayerWorking = Copy-AdaptiveLayerConfig -Config $Config
    $encoderCount = [int]$script:DetectedEncoderCount

    $encoderLayerDialog = New-Object System.Windows.Forms.Form
    $encoderLayerDialog.Text = if ($script:Language -eq 'ru') { 'Энкодеры в слоях — Mugen Deej' } else { 'Layered encoders — Mugen Deej' }
    $encoderLayerDialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $encoderLayerDialog.ClientSize = [System.Drawing.Size]::new(720, 462)
    $encoderLayerDialog.MinimumSize = [System.Drawing.Size]::new(736, 501)
    $encoderLayerDialog.MaximumSize = [System.Drawing.Size]::new(736, 501)
    $encoderLayerDialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $encoderLayerDialog.MaximizeBox = $false
    $encoderLayerDialog.MinimizeBox = $false
    $encoderLayerDialog.Font = $form.Font
    Set-FormAppIcon -Form $encoderLayerDialog

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = if ($script:Language -eq 'ru') { 'Энкодер в слоях' } else { 'Encoder layer mappings' }
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $encoderLayerDialog.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = if ($script:Language -eq 'ru') {
        'Для каждого слоя можно отдельно задать вращение и нажатие.' + "`r`n" + '«Как в основном слое» оставляет обычное назначение энкодера из выбранного профиля.'
    }
    else {
        'Each layer can set rotation and push separately.' + "`r`n" + '“Same as base layer” keeps the normal encoder mapping from the selected profile.'
    }
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(670, 44)
    $encoderLayerDialog.Controls.Add($hint)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = if ($script:Language -eq 'ru') { 'Профиль:' } else { 'Profile:' }
    $profileLabel.Location = [System.Drawing.Point]::new(25, 111)
    $profileLabel.Size = [System.Drawing.Size]::new(68, 28)
    $profileLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $encoderLayerDialog.Controls.Add($profileLabel)

    $encoderLayerProfileCombo = New-Object MugenDeejWindowing.MugenComboBox
    $encoderLayerProfileCombo.DropDownStyle = 'DropDownList'
    $encoderLayerProfileCombo.Location = [System.Drawing.Point]::new(92, 109)
    $encoderLayerProfileCombo.Size = [System.Drawing.Size]::new(224, 30)
    $encoderLayerDialog.Controls.Add($encoderLayerProfileCombo)

    $encoderLayerProfileMap = New-Object System.Collections.ArrayList
    [void]$encoderLayerProfileCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Общий' } else { 'Global' }))
    [void]$encoderLayerProfileMap.Add('__global__')
    foreach ($profile in @($script:AdaptiveProfiles | Sort-Object name)) {
        $processName = Normalize-TargetName -Value ([string]$profile.process)
        if ([string]::IsNullOrWhiteSpace($processName)) { continue }
        [void]$encoderLayerProfileCombo.Items.Add(('{0} ({1}.exe)' -f [string]$profile.name, $processName))
        [void]$encoderLayerProfileMap.Add($processName.ToLowerInvariant())
    }
    $encoderLayerProfileCombo.SelectedIndex = 0

    $layerLabel = New-Object System.Windows.Forms.Label
    $layerLabel.Text = if ($script:Language -eq 'ru') { 'Слой:' } else { 'Layer:' }
    $layerLabel.Location = [System.Drawing.Point]::new(330, 111)
    $layerLabel.Size = [System.Drawing.Size]::new(48, 28)
    $layerLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $encoderLayerDialog.Controls.Add($layerLabel)

    $encoderLayerLayerCombo = New-Object MugenDeejWindowing.MugenComboBox
    $encoderLayerLayerCombo.DropDownStyle = 'DropDownList'
    $encoderLayerLayerCombo.Location = [System.Drawing.Point]::new(378, 109)
    $encoderLayerLayerCombo.Size = [System.Drawing.Size]::new(126, 30)
    Set-AdaptiveLayerComboDisplayItems -Combo $encoderLayerLayerCombo -Config $encoderLayerWorking
    $encoderLayerDialog.Controls.Add($encoderLayerLayerCombo)

    $encoderLabel = New-Object System.Windows.Forms.Label
    $encoderLabel.Text = if ($script:Language -eq 'ru') { 'Энкодер:' } else { 'Encoder:' }
    $encoderLabel.Location = [System.Drawing.Point]::new(516, 111)
    $encoderLabel.Size = [System.Drawing.Size]::new(70, 28)
    $encoderLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $encoderLayerDialog.Controls.Add($encoderLabel)

    $encoderLayerEncoderCombo = New-Object MugenDeejWindowing.MugenComboBox
    $encoderLayerEncoderCombo.DropDownStyle = 'DropDownList'
    $encoderLayerEncoderCombo.Location = [System.Drawing.Point]::new(585, 109)
    $encoderLayerEncoderCombo.Size = [System.Drawing.Size]::new(110, 30)
    for ($i = 0; $i -lt $encoderCount; $i++) {
        [void]$encoderLayerEncoderCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Энкодер ' + ($i + 1) } else { 'Encoder ' + ($i + 1) }))
    }
    $encoderLayerEncoderCombo.SelectedIndex = 0
    $encoderLayerDialog.Controls.Add($encoderLayerEncoderCombo)

    $encoderLayerBaseLabel = New-Object System.Windows.Forms.Label
    $encoderLayerBaseLabel.ForeColor = [System.Drawing.Color]::DimGray
    $encoderLayerBaseLabel.Location = [System.Drawing.Point]::new(25, 154)
    $encoderLayerBaseLabel.Size = [System.Drawing.Size]::new(670, 52)
    $encoderLayerDialog.Controls.Add($encoderLayerBaseLabel)

    $encoderLayerLabels = @()
    $encoderLayerCombos = @()
    $encoderLayerMaps = @()
    $encoderLayerKinds = @('cw','ccw','push')
    $kindTitlesRu = @('↻', '↺', 'Нажатие')
    $kindTitlesEn = @('↻', '↺', 'Push')

    for ($i = 0; $i -lt 3; $i++) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $(if ($script:Language -eq 'ru') { $kindTitlesRu[$i] } else { $kindTitlesEn[$i] })
        $label.Location = [System.Drawing.Point]::new(25, (217 + ($i * 58)))
        $label.Size = [System.Drawing.Size]::new(145, 26)
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $encoderLayerDialog.Controls.Add($label)
        $encoderLayerLabels += $label

        $combo = New-Object MugenDeejWindowing.MugenComboBox
        $combo.Tag = $i
        $combo.DropDownStyle = 'DropDownList'
        $combo.Location = [System.Drawing.Point]::new(175, (215 + ($i * 58)))
        $combo.Size = [System.Drawing.Size]::new(520, 30)
        $encoderLayerDialog.Controls.Add($combo)
        $encoderLayerCombos += $combo
        $encoderLayerMaps += ,(New-Object System.Collections.ArrayList)
    }

    $encoderLayerState = [pscustomobject]@{ Suppress = $false }
    $encoderLayerDialog.Tag = [pscustomobject]@{
        TargetConfig = $Config
        WorkingConfig = $encoderLayerWorking
    }

    $encoderLayerGetContextKey = {
        $index = [int]$encoderLayerProfileCombo.SelectedIndex
        if ($index -lt 0 -or $index -ge $encoderLayerProfileMap.Count) { return '__global__' }
        return [string]$encoderLayerProfileMap[$index]
    }

    $encoderLayerRefresh = {
        $contextKey = & $encoderLayerGetContextKey
        $layer = [int]$encoderLayerLayerCombo.SelectedIndex + 1
        $encoderIndex = [int]$encoderLayerEncoderCombo.SelectedIndex
        if ($encoderIndex -lt 0) { $encoderIndex = 0 }

        $context = Get-AdaptiveLayerContextObject -Config $encoderLayerWorking -Key $contextKey -Create
        Ensure-AdaptiveLayerEncoderCapacity -Context $context -EncoderCount $encoderCount

        $baseCw = Get-AdaptiveLayerBaseEncoderAction -ContextKey $contextKey -EncoderIndex $encoderIndex -Kind 'cw'
        $baseCcw = Get-AdaptiveLayerBaseEncoderAction -ContextKey $contextKey -EncoderIndex $encoderIndex -Kind 'ccw'
        $basePush = Get-AdaptiveLayerBaseEncoderAction -ContextKey $contextKey -EncoderIndex $encoderIndex -Kind 'push'
        $encoderLayerBaseLabel.Text = if ($script:Language -eq 'ru') {
            'Основной слой: ↻ {0} · ↺ {1} · Нажатие: {2}' -f (Get-AdaptiveActionDisplay -Action $baseCw), (Get-AdaptiveActionDisplay -Action $baseCcw), (Get-AdaptiveActionDisplay -Action $basePush)
        }
        else {
            'Base layer: ↻ {0} · ↺ {1} · Push: {2}' -f (Get-AdaptiveActionDisplay -Action $baseCw), (Get-AdaptiveActionDisplay -Action $baseCcw), (Get-AdaptiveActionDisplay -Action $basePush)
        }

        $encoderLayerState.Suppress = $true
        try {
            for ($i = 0; $i -lt 3; $i++) {
                $override = Get-AdaptiveLayerEncoderOverride -Config $encoderLayerWorking -ContextKey $contextKey -Layer $layer -EncoderIndex $encoderIndex -Kind $encoderLayerKinds[$i]
                Populate-AdaptiveLayerTypedActionCombo -Combo $encoderLayerCombos[$i] -Map $encoderLayerMaps[$i] -CurrentAction $override
            }
        }
        finally {
            $encoderLayerState.Suppress = $false
        }

        $hasPush = $false
        if (@($script:LatestEncoders).Count -gt $encoderIndex) {
            $hasPush = [bool]$script:LatestEncoders[$encoderIndex].HasPush
        }
        $encoderLayerLabels[2].Visible = $hasPush
        $encoderLayerCombos[2].Visible = $hasPush
    }

    for ($comboIndex = 0; $comboIndex -lt 3; $comboIndex++) {
        $encoderLayerCombos[$comboIndex].Add_SelectedIndexChanged({
            param($sender, $eventArgs)

            if ($encoderLayerState.Suppress) { return }

            $slotIndex = [int]$sender.Tag
            $selectedIndex = [int]$sender.SelectedIndex
            if ($slotIndex -lt 0 -or $slotIndex -ge $encoderLayerMaps.Count) { return }
            if ($selectedIndex -lt 0 -or $selectedIndex -ge $encoderLayerMaps[$slotIndex].Count) { return }

            $contextKey = & $encoderLayerGetContextKey
            $layer = [int]$encoderLayerLayerCombo.SelectedIndex + 1
            $encoderIndex = [int]$encoderLayerEncoderCombo.SelectedIndex
            $kind = [string]$encoderLayerKinds[$slotIndex]
            $chosen = [string]$encoderLayerMaps[$slotIndex][$selectedIndex]
            $previous = Get-AdaptiveLayerEncoderOverride -Config $encoderLayerWorking -ContextKey $contextKey -Layer $layer -EncoderIndex $encoderIndex -Kind $kind

            $configured = if ($chosen -eq 'inherit') {
                'inherit'
            }
            else {
                Resolve-AdaptiveConfiguredAction -SelectedAction $chosen -PreviousAction $(if ($previous -eq 'inherit') { 'none' } else { $previous })
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$configured)) {
                Set-AdaptiveLayerEncoderOverride -Config $encoderLayerWorking -ContextKey $contextKey -Layer $layer -EncoderIndex $encoderIndex -Kind $kind -Action ([string]$configured) -EncoderCount $encoderCount
            }

            & $encoderLayerRefresh
        })
    }

    $encoderLayerProfileCombo.Add_SelectedIndexChanged({ if (-not $encoderLayerState.Suppress) { & $encoderLayerRefresh } })
    $encoderLayerLayerCombo.Add_SelectedIndexChanged({ if (-not $encoderLayerState.Suppress) { & $encoderLayerRefresh } })
    $encoderLayerEncoderCombo.Add_SelectedIndexChanged({ if (-not $encoderLayerState.Suppress) { & $encoderLayerRefresh } })

    $encoderLayerCancel = New-Object MugenDeejWindowing.MugenButton
    $encoderLayerCancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $encoderLayerCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $encoderLayerCancel.Location = [System.Drawing.Point]::new(486, 408)
    $encoderLayerCancel.Size = [System.Drawing.Size]::new(98, 36)
    $encoderLayerDialog.Controls.Add($encoderLayerCancel)

    $encoderLayerSave = New-Object MugenDeejWindowing.MugenButton
    $encoderLayerSave.Text = Get-ButtonFeatureText -Key 'Save'
    $encoderLayerSave.Tag = 'MugenPrimary'
    $encoderLayerSave.Location = [System.Drawing.Point]::new(596, 408)
    $encoderLayerSave.Size = [System.Drawing.Size]::new(99, 36)
    $encoderLayerDialog.Controls.Add($encoderLayerSave)

    $encoderLayerSave.Add_Click({
        param($sender, $eventArgs)

        $ownerForm = $sender.FindForm()
        $editorState = $ownerForm.Tag
        $normalized = ConvertTo-NormalizedAdaptiveLayerConfig -Data $editorState.WorkingConfig
        $editorState.TargetConfig.contexts = @($normalized.contexts)
        $ownerForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $ownerForm.Close()
    })

    Apply-ThemeToForm -Form $encoderLayerDialog
    & $encoderLayerRefresh
    $encoderLayerDialog.AcceptButton = $encoderLayerSave
    $encoderLayerDialog.CancelButton = $encoderLayerCancel
    [void]$encoderLayerDialog.ShowDialog($Owner)
    if (-not $encoderLayerDialog.IsDisposed) { $encoderLayerDialog.Dispose() }
}

function Get-AdaptiveLayerProfileKey {
    $profile = Get-ForegroundAdaptiveProfile
    if ($null -eq $profile) { return '__global__' }

    $processName = Normalize-TargetName -Value ([string]$profile.process)
    if ([string]::IsNullOrWhiteSpace($processName)) { return '__global__' }

    return $processName.ToLowerInvariant()
}

function Resolve-AdaptiveLayerButtonContext {
    param([Parameter(Mandatory = $true)]$BaseContext)

    if ([string]$script:ControllerProtocol -ne 'adaptive') {
        return $BaseContext
    }

    $layer = Get-AdaptiveLayerIndex
    if ($layer -le 0 -or -not (Test-AdaptiveLayersEnabled)) {
        return $BaseContext
    }

    Initialize-AdaptiveLayers
    $layerContextKey = Get-AdaptiveLayerProfileKey
    $context = Get-AdaptiveLayerContextObject -Config $script:AdaptiveLayerConfig -Key $layerContextKey

    $baseActions = @($BaseContext.Actions | ForEach-Object { [string]$_ })
    $count = [Math]::Max($baseActions.Count, [int]$script:DetectedButtonCount)
    $resolved = @()

    for ($i = 0; $i -lt $count; $i++) {
        $baseAction = if ($i -lt $baseActions.Count) {
            ConvertTo-SafeProfileButtonAction -Action ([string]$baseActions[$i])
        }
        else {
            'none'
        }

        $override = if ($null -eq $context) {
            'inherit'
        }
        else {
            Get-AdaptiveLayerButtonOverride -Config $script:AdaptiveLayerConfig -ContextKey $layerContextKey -Layer $layer -ButtonIndex $i
        }

        if ($override -eq 'inherit') {
            $resolved += $baseAction
        }
        else {
            $resolved += ConvertTo-SafeProfileButtonAction -Action $override
        }
    }

    $baseKey = [string]$BaseContext.Key
    if ([string]::IsNullOrWhiteSpace($baseKey)) { $baseKey = '__global__' }

    return [pscustomobject][ordered]@{
        Key = ('{0}|layer:{1}|layerProfile:{2}' -f $baseKey, $layer, $layerContextKey)
        Actions = @($resolved)
    }
}

function Get-AdaptiveLayerBaseButtonAction {
    param(
        [string]$ContextKey,
        [int]$ButtonIndex
    )

    Initialize-ButtonActions
    Initialize-AdaptiveProfiles

    if ($ButtonIndex -lt 0) { return 'none' }

    $key = Normalize-AdaptiveLayerContextKey -Key $ContextKey
    $actions = @($script:ButtonActions | ForEach-Object { [string]$_ })

    if ($key -ne '__global__') {
        foreach ($profile in @($script:AdaptiveProfiles)) {
            $processName = Normalize-TargetName -Value ([string]$profile.process)
            if ([string]::IsNullOrWhiteSpace($processName)) { continue }
            if ($processName.ToLowerInvariant() -ne $key) { continue }

            $profileButtons = @()
            if ($null -ne $profile.PSObject.Properties['buttons']) {
                $profileButtons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
            }
            if ($profileButtons.Count -gt 0) {
                $actions = @($profileButtons)
            }
            break
        }
    }

    if ($ButtonIndex -ge $actions.Count) { return 'none' }
    return ConvertTo-SafeProfileButtonAction -Action ([string]$actions[$ButtonIndex])
}

function Get-AdaptiveLayerOverrideDisplay {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'inherit') {
        return $(if ($script:Language -eq 'ru') { 'Как в основном слое' } else { 'Same as base layer' })
    }

    return Get-LargeButtonActionDisplay -Action $Action
}

function Populate-AdaptiveLayerButtonActionCombo {
    param(
        [Parameter(Mandatory = $true)]$Combo,
        [Parameter(Mandatory = $true)]$Map,
        [string]$CurrentAction = 'inherit'
    )

    $CurrentAction = ConvertTo-SafeAdaptiveLayerButtonOverride -Action $CurrentAction

    $Combo.BeginUpdate()
    try {
        $Combo.Items.Clear()
        $Map.Clear()

        [void]$Combo.Items.Add($(if ($script:Language -eq 'ru') { 'Как в основном слое' } else { 'Same as base layer' }))
        [void]$Map.Add('inherit')

        [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'None'))
        [void]$Map.Add('none')

        $sliderCount = [Math]::Min([int]$script:DetectedSliderCount, @($script:Config.sliders).Count)
        for ($sliderIndex = 0; $sliderIndex -lt $sliderCount; $sliderIndex++) {
            $name = [string]$script:Config.sliders[$sliderIndex].name
            if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]($sliderIndex + 1) }
            [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'MuteControl') + ' ' + ($sliderIndex + 1) + ' — ' + $name)
            [void]$Map.Add(('mute:' + $sliderIndex))
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
            [void]$Combo.Items.Add((Get-ButtonFeatureText -Key $fixedAction[0]))
            [void]$Map.Add([string]$fixedAction[1])
        }

        if (
            $script:VirtualGamepadFeatureAvailable -and
            (Test-MugenVirtualGamepadAction -Action $CurrentAction)
        ) {
            [void]$Combo.Items.Add((Get-MugenVirtualGamepadActionDisplay -Action $CurrentAction))
            [void]$Map.Add($CurrentAction)
        }

        if (
            $script:VirtualGamepadFeatureAvailable -and
            [string]$script:ControllerProtocol -eq 'adaptive'
        ) {
            [void]$Combo.Items.Add($(if ($script:Language -eq 'ru') { 'Виртуальный геймпад Xbox…' } else { 'Virtual Xbox gamepad…' }))
            [void]$Map.Add('virtual:xbox:configure')
        }

        if ($CurrentAction -match '^(hotkey:|launch64:|folder64:|command64:|url64:)') {
            [void]$Combo.Items.Add((Get-LargeButtonActionDisplay -Action $CurrentAction))
            [void]$Map.Add($CurrentAction)
        }

        [void]$Combo.Items.Add((Get-ButtonFeatureText -Key 'HotkeyConfigure'))
        [void]$Map.Add('hotkey:configure')

        if ($script:Language -eq 'ru') {
            [void]$Combo.Items.Add('Запустить программу / файл…')
            [void]$Combo.Items.Add('Открыть папку…')
            [void]$Combo.Items.Add('Выполнить команду…')
            [void]$Combo.Items.Add('Открыть URL…')
        }
        else {
            [void]$Combo.Items.Add('Launch program / file…')
            [void]$Combo.Items.Add('Open folder…')
            [void]$Combo.Items.Add('Run command…')
            [void]$Combo.Items.Add('Open URL…')
        }

        [void]$Map.Add('launch:configure')
        [void]$Map.Add('folder:configure')
        [void]$Map.Add('command:configure')
        [void]$Map.Add('url:configure')

        $selected = 0
        for ($i = 0; $i -lt $Map.Count; $i++) {
            if ([string]$Map[$i] -eq $CurrentAction) {
                $selected = $i
                break
            }
        }
        $Combo.SelectedIndex = $selected
    }
    finally {
        $Combo.EndUpdate()
    }
}

function Resolve-AdaptiveLayerConfiguredButtonAction {
    param(
        [string]$SelectedAction,
        [string]$PreviousAction,
        [System.Windows.Forms.IWin32Window]$Owner
    )

    switch ($SelectedAction) {
        'virtual:xbox:configure' {
            return Show-MugenVirtualGamepadButtonPicker -ExistingAction $PreviousAction -Owner $Owner
        }
        'hotkey:configure' { return Show-HotkeyEditor -ExistingAction $PreviousAction }
        'launch:configure' { return Select-LaunchTargetAction -ExistingAction $PreviousAction }
        'folder:configure' { return Select-FolderTargetAction -ExistingAction $PreviousAction }
        'command:configure' { return Show-CommandActionEditor -ExistingAction $PreviousAction }
        'url:configure' { return Show-UrlActionEditor -ExistingAction $PreviousAction }
        default { return $SelectedAction }
    }
}

function Show-AdaptiveLayerSettings {
    if (
        -not $script:IsConnected -or
        [string]$script:ControllerProtocol -ne 'adaptive' -or
        [int]$script:DetectedButtonCount -le 0 -or
        [int]$script:DetectedToggleCount -le 0
    ) {
        return
    }

    Initialize-AdaptiveLayers
    Initialize-AdaptiveActions
    Initialize-AdaptiveProfiles
    Initialize-ButtonActions

    $working = Copy-AdaptiveLayerConfig -Config $script:AdaptiveLayerConfig
    $buttonCount = [int]$script:DetectedButtonCount

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = if ($script:Language -eq 'ru') { 'Слои управления — Mugen Deej' } else { 'Control layers — Mugen Deej' }
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ClientSize = [System.Drawing.Size]::new(1160, 814)
    $dialog.MinimumSize = [System.Drawing.Size]::new(1176, 853)
    $dialog.MaximumSize = [System.Drawing.Size]::new(1176, 853)
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.Font = $form.Font
    Set-FormAppIcon -Form $dialog

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = if ($script:Language -eq 'ru') { 'Слои управления' } else { 'Control layers' }
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $dialog.Controls.Add($heading)

    $notificationSettingsButton = New-Object MugenDeejWindowing.MugenButton
    $notificationSettingsButton.Text = if ($script:Language -eq 'ru') { 'Уведомления…' } else { 'Notifications…' }
    $notificationSettingsButton.Location = [System.Drawing.Point]::new(950, 18)
    $notificationSettingsButton.Size = [System.Drawing.Size]::new(185, 32)
    $notificationSettingsButton.Add_Click({
        & $syncLayerNamesToWorking
        Show-AdaptiveLayerNotificationSettings -Config $working -Owner $dialog
    })
    $dialog.Controls.Add($notificationSettingsButton)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = if ($script:Language -eq 'ru') {
        'T1 и T2 могут переключать слои с отдельными действиями. Для каждого слоя можно изменить действия кнопок и энкодера.
Всё, что не изменено, работает как в основном слое.'
    }
    else {
        'T1 and T2 can switch layers with separate actions. Each layer can change button and encoder actions.
Anything unchanged works the same as the base layer.'
    }
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(1110, 45)
    $dialog.Controls.Add($hint)

    $modifierGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $modifierGroup.Text = if ($script:Language -eq 'ru') { 'Переключение слоёв' } else { 'Layer switching' }
    $modifierGroup.Location = [System.Drawing.Point]::new(22, 108)
    $modifierGroup.Size = [System.Drawing.Size]::new(816, 94)
    $dialog.Controls.Add($modifierGroup)

    $t1Check = New-Object System.Windows.Forms.CheckBox
    $t1Check.Text = if ($script:Language -eq 'ru') { 'Тумблер 1 = слой T1' } else { 'Toggle 1 = T1 layer' }
    $t1Check.AutoSize = $true
    $t1Check.Location = [System.Drawing.Point]::new(18, 31)
    $t1Check.Checked = [bool]$working.modifierToggles[0]
    $modifierGroup.Controls.Add($t1Check)

    $t2Check = New-Object System.Windows.Forms.CheckBox
    $t2Check.Text = if ($script:Language -eq 'ru') { 'Тумблер 2 = слой T2' } else { 'Toggle 2 = T2 layer' }
    $t2Check.AutoSize = $true
    $t2Check.Location = [System.Drawing.Point]::new(310, 31)
    $t2Check.Checked = ([int]$script:DetectedToggleCount -gt 1 -and [bool]$working.modifierToggles[1])
    $t2Check.Enabled = ([int]$script:DetectedToggleCount -gt 1)
    $modifierGroup.Controls.Add($t2Check)

    $modifierHint = New-Object System.Windows.Forms.Label
    $modifierHint.Text = if ($script:Language -eq 'ru') {
        'Когда тумблер переключает слой, его обычные действия ВКЛ/ВЫКЛ не выполняются.'
    }
    else {
        'When a toggle switches layers, its normal ON/OFF actions do not run.'
    }
    $modifierHint.ForeColor = [System.Drawing.Color]::DimGray
    $modifierHint.Location = [System.Drawing.Point]::new(18, 58)
    $modifierHint.Size = [System.Drawing.Size]::new(570, 25)
    $modifierGroup.Controls.Add($modifierHint)

    $encoderLayerButton = New-Object MugenDeejWindowing.MugenButton
    $encoderLayerButton.Text = if ($script:Language -eq 'ru') { 'Энкодер в слоях…' } else { 'Layered encoder…' }
    $encoderLayerButton.Location = [System.Drawing.Point]::new(604, 52)
    $encoderLayerButton.Size = [System.Drawing.Size]::new(185, 30)
    $encoderLayerButton.Enabled = ([int]$script:DetectedEncoderCount -gt 0)
    $encoderLayerButton.Add_Click({
        & $syncLayerNamesToWorking
        Show-AdaptiveLayerEncoderSettings -Config $working -Owner $dialog
    })
    $modifierGroup.Controls.Add($encoderLayerButton)

    $namesGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $namesGroup.Text = if ($script:Language -eq 'ru') { 'Имена слоёв' } else { 'Layer names' }
    $namesGroup.Location = [System.Drawing.Point]::new(22, 210)
    $namesGroup.Size = [System.Drawing.Size]::new(816, 94)
    $dialog.Controls.Add($namesGroup)

    $nameLabelsRu = @('Основной', 'T1', 'T2', 'T1 + T2')
    $nameLabelsEn = @('Base', 'T1', 'T2', 'T1 + T2')
    $layerNameBoxes = @()

    for ($layerNameIndex = 0; $layerNameIndex -lt 4; $layerNameIndex++) {
        $columnX = 16 + ($layerNameIndex * 198)

        $nameLabel = New-Object System.Windows.Forms.Label
        $nameLabel.Text = if ($script:Language -eq 'ru') { $nameLabelsRu[$layerNameIndex] } else { $nameLabelsEn[$layerNameIndex] }
        $nameLabel.Location = [System.Drawing.Point]::new($columnX, 24)
        $nameLabel.Size = [System.Drawing.Size]::new(178, 20)
        $namesGroup.Controls.Add($nameLabel)

        $nameBox = New-Object System.Windows.Forms.TextBox
        $nameBox.Tag = $layerNameIndex
        $nameBox.MaxLength = 24
        $nameBox.Location = [System.Drawing.Point]::new($columnX, 52)
        $nameBox.Size = [System.Drawing.Size]::new(178, 25)
        $nameBox.Text = Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $layerNameIndex
        $namesGroup.Controls.Add($nameBox)
        $layerNameBoxes += $nameBox
    }

    $syncLayerNamesToWorking = {
        foreach ($nameBox in $layerNameBoxes) {
            $layerIndex = [int]$nameBox.Tag
            $key = Get-AdaptiveLayerCustomNameKey -Layer $layerIndex
            $value = ConvertTo-SafeAdaptiveLayerCustomName -Value ([string]$nameBox.Text)
            $defaultValue = Get-AdaptiveLayerDefaultDisplayName -Layer $layerIndex

            if ($value -eq $defaultValue) {
                $working.names.$key = ''
            }
            else {
                $working.names.$key = $value
            }
        }
    }

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = if ($script:Language -eq 'ru') { 'Профиль:' } else { 'Profile:' }
    $profileLabel.Location = [System.Drawing.Point]::new(25, 328)
    $profileLabel.Size = [System.Drawing.Size]::new(100, 28)
    $profileLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $dialog.Controls.Add($profileLabel)

    $profileCombo = New-Object MugenDeejWindowing.MugenComboBox
    $profileCombo.DropDownStyle = 'DropDownList'
    $profileCombo.Location = [System.Drawing.Point]::new(125, 326)
    $profileCombo.Size = [System.Drawing.Size]::new(410, 30)
    $dialog.Controls.Add($profileCombo)

    $profileMap = New-Object System.Collections.ArrayList
    [void]$profileCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Общий — для всех остальных приложений' } else { 'Global — all other applications' }))
    [void]$profileMap.Add('__global__')
    foreach ($profile in @($script:AdaptiveProfiles | Sort-Object name)) {
        $processName = Normalize-TargetName -Value ([string]$profile.process)
        if ([string]::IsNullOrWhiteSpace($processName)) { continue }
        [void]$profileCombo.Items.Add(('{0}  ({1}.exe)' -f [string]$profile.name, $processName))
        [void]$profileMap.Add($processName.ToLowerInvariant())
    }
    $profileCombo.SelectedIndex = 0

    $layerLabel = New-Object System.Windows.Forms.Label
    $layerLabel.Text = if ($script:Language -eq 'ru') { 'Слой:' } else { 'Layer:' }
    $layerLabel.Location = [System.Drawing.Point]::new(558, 328)
    $layerLabel.Size = [System.Drawing.Size]::new(70, 28)
    $layerLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $dialog.Controls.Add($layerLabel)

    $layerCombo = New-Object MugenDeejWindowing.MugenComboBox
    $layerCombo.DropDownStyle = 'DropDownList'
    $layerCombo.Location = [System.Drawing.Point]::new(625, 326)
    $layerCombo.Size = [System.Drawing.Size]::new(210, 30)
    Set-AdaptiveLayerComboDisplayItems -Combo $layerCombo -Config $working
    $dialog.Controls.Add($layerCombo)

    $editorGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $editorGroup.Text = if ($script:Language -eq 'ru') { 'Действия кнопок в этом слое' } else { 'Button actions in this layer' }
    $editorGroup.Location = [System.Drawing.Point]::new(22, 370)
    $editorGroup.Size = [System.Drawing.Size]::new(816, 360)
    $dialog.Controls.Add($editorGroup)

    $layerAssignmentsGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $layerAssignmentsGroup.Text = if ($script:Language -eq 'ru') { 'Назначения в слое' } else { 'Assignments in this layer' }
    $layerAssignmentsGroup.Location = [System.Drawing.Point]::new(850, 108)
    $layerAssignmentsGroup.Size = [System.Drawing.Size]::new(286, 622)
    $dialog.Controls.Add($layerAssignmentsGroup)

    $layerAssignmentsTitle = New-Object System.Windows.Forms.Label
    $layerAssignmentsTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $layerAssignmentsTitle.Location = [System.Drawing.Point]::new(14, 30)
    $layerAssignmentsTitle.Size = [System.Drawing.Size]::new(258, 26)
    $layerAssignmentsGroup.Controls.Add($layerAssignmentsTitle)

    $layerAssignmentsHint = New-Object System.Windows.Forms.Label
    $layerAssignmentsHint.Text = if ($script:Language -eq 'ru') {
        'Здесь только отдельные действия слоя. Нажмите строку, чтобы перейти к кнопке.'
    }
    else {
        'Only separate actions for this layer are shown. Select a row to jump to that button.'
    }
    $layerAssignmentsHint.ForeColor = [System.Drawing.Color]::DimGray
    $layerAssignmentsHint.Location = [System.Drawing.Point]::new(14, 57)
    $layerAssignmentsHint.Size = [System.Drawing.Size]::new(258, 56)
    $layerAssignmentsGroup.Controls.Add($layerAssignmentsHint)

    $layerAssignmentsList = New-Object System.Windows.Forms.ListView
    $layerAssignmentsList.Location = [System.Drawing.Point]::new(14, 116)
    $layerAssignmentsList.Size = [System.Drawing.Size]::new(258, 484)
    $layerAssignmentsList.View = [System.Windows.Forms.View]::Details
    $layerAssignmentsList.FullRowSelect = $true
    $layerAssignmentsList.HideSelection = $false
    $layerAssignmentsList.MultiSelect = $false
    [void]$layerAssignmentsList.Columns.Add($(if ($script:Language -eq 'ru') { 'Кнопка' } else { 'Button' }), 62)
    [void]$layerAssignmentsList.Columns.Add($(if ($script:Language -eq 'ru') { 'Назначение' } else { 'Assignment' }), 172)
    $layerAssignmentsGroup.Controls.Add($layerAssignmentsList)

    $selectorFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $selectorFlow.Location = [System.Drawing.Point]::new(14, 30)
    $selectorFlow.Size = [System.Drawing.Size]::new(286, 312)
    $selectorFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $selectorFlow.WrapContents = $true
    $selectorFlow.AutoScroll = $true
    $editorGroup.Controls.Add($selectorFlow)

    $selectors = @()
    for ($i = 0; $i -lt $buttonCount; $i++) {
        $selector = New-Object MugenDeejWindowing.MugenButtonTile
        $selector.Text = [string]($i + 1)
        $selector.Tag = $i
        $selector.Size = [System.Drawing.Size]::new(42, 28)
        $selector.Margin = New-Object System.Windows.Forms.Padding(3, 2, 3, 2)
        $selector.TextAlign = 'MiddleCenter'
        $selector.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
        $selectorFlow.Controls.Add($selector)
        $selectors += $selector
    }

    $selectedHeading = New-Object System.Windows.Forms.Label
    $selectedHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $selectedHeading.Location = [System.Drawing.Point]::new(320, 35)
    $selectedHeading.Size = [System.Drawing.Size]::new(472, 30)
    $editorGroup.Controls.Add($selectedHeading)

    $baseLabel = New-Object System.Windows.Forms.Label
    $baseLabel.ForeColor = [System.Drawing.Color]::DimGray
    $baseLabel.Location = [System.Drawing.Point]::new(320, 72)
    $baseLabel.Size = [System.Drawing.Size]::new(472, 54)
    $editorGroup.Controls.Add($baseLabel)

    $overrideLabel = New-Object System.Windows.Forms.Label
    $overrideLabel.Text = if ($script:Language -eq 'ru') { 'Действие в этом слое:' } else { 'Action in this layer:' }
    $overrideLabel.Location = [System.Drawing.Point]::new(320, 138)
    $overrideLabel.Size = [System.Drawing.Size]::new(220, 26)
    $editorGroup.Controls.Add($overrideLabel)

    $actionCombo = New-Object MugenDeejWindowing.MugenComboBox
    $actionCombo.DropDownStyle = 'DropDownList'
    $actionCombo.Location = [System.Drawing.Point]::new(320, 168)
    $actionCombo.Size = [System.Drawing.Size]::new(472, 30)
    $editorGroup.Controls.Add($actionCombo)

    $editorHint = New-Object System.Windows.Forms.Label
    $editorHint.Text = if ($script:Language -eq 'ru') {
        '«Как в основном слое» — оставить обычное действие.' + "`r`n" + '«Не использовать» — отключить кнопку только в этом слое.' + "`r`n" +
        'Обычные действия выполняются один раз при нажатии.' + "`r`n" + 'Виртуальный геймпад Xbox удерживает кнопку, пока вы держите кнопку на контроллере.'
    }
    else {
        '“Same as base layer” keeps the normal action.' + "`r`n" + '“Do nothing” disables the button only in this layer.' + "`r`n" +
        'Regular actions fire once per press.' + "`r`n" + 'The virtual Xbox gamepad stays held while you hold the controller button.'
    }
    $editorHint.ForeColor = [System.Drawing.Color]::DimGray
    $editorHint.Location = [System.Drawing.Point]::new(320, 211)
    $editorHint.Size = [System.Drawing.Size]::new(472, 70)
    $editorGroup.Controls.Add($editorHint)

    $activePreview = New-Object System.Windows.Forms.Label
    $activePreview.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $activePreview.Location = [System.Drawing.Point]::new(320, 294)
    $activePreview.Size = [System.Drawing.Size]::new(472, 28)
    $editorGroup.Controls.Add($activePreview)

    $layerButtonState = [pscustomobject]@{
        Selected = 0
        Suppress = $false
        SummarySuppress = $false
        VirtualMappingConfigured = $false
        ActionMap = New-Object System.Collections.ArrayList
        LastButtons = @($script:LatestButtons)
    }
    $refreshSelectorTiles = {
        $palette = $script:ThemePalettes[[string](Get-EffectiveTheme)]
        $latest = @($script:LatestButtons)

        for ($tileIndex = 0; $tileIndex -lt $selectors.Count; $tileIndex++) {
            $tile = $selectors[$tileIndex]
            if ($null -eq $tile -or $tile.IsDisposed) { continue }

            $isPressed = (
                $tileIndex -lt $latest.Count -and
                [int]$latest[$tileIndex] -eq 0
            )
            $isSelected = ($tileIndex -eq [int]$layerButtonState.Selected)

            # MugenButtonTile owns the semantic selected/pressed state and paints
            # it internally. External invalidations can no longer temporarily
            # restore normal BackColor/BorderColor between 40 ms timer ticks.
            $tile.ApplySemanticStateTheme(
                $palette.Control,
                $palette.Text,
                $palette.Border,
                $palette.Accent,
                $palette.AccentText,
                $palette.Accent,
                $isSelected,
                $isPressed
            )
        }
    }

    $getContextKey = {
        $index = [int]$profileCombo.SelectedIndex
        if ($index -lt 0 -or $index -ge $profileMap.Count) { return '__global__' }
        return [string]$profileMap[$index]
    }

    $getLayer = {
        return ([int]$layerCombo.SelectedIndex + 1)
    }

    $refreshLayerAssignments = {
        $contextKey = & $getContextKey
        $layer = & $getLayer
        $layerName = Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $layer
        $rows = @()

        $context = Get-AdaptiveLayerContextObject -Config $working -Key $contextKey -Create
        Ensure-AdaptiveLayerContextCapacity -Context $context -ButtonCount $buttonCount

        for ($buttonIndex = 0; $buttonIndex -lt $buttonCount; $buttonIndex++) {
            $override = Get-AdaptiveLayerButtonOverride -Config $working -ContextKey $contextKey -Layer $layer -ButtonIndex $buttonIndex
            if ([string]$override -eq 'inherit') { continue }

            $rows += [pscustomobject]@{
                ButtonIndex = $buttonIndex
                Button = [string]($buttonIndex + 1)
                Action = Get-AdaptiveLayerOverrideDisplay -Action ([string]$override)
            }
        }

        $layerAssignmentsTitle.Text = if ($script:Language -eq 'ru') {
            '{0} · назначено: {1}' -f $layerName, $rows.Count
        }
        else {
            '{0} · assigned: {1}' -f $layerName, $rows.Count
        }

        $layerButtonState.SummarySuppress = $true
        $layerAssignmentsList.BeginUpdate()
        try {
            $layerAssignmentsList.Items.Clear()

            if ($rows.Count -eq 0) {
                $emptyItem = New-Object System.Windows.Forms.ListViewItem('—')
                [void]$emptyItem.SubItems.Add($(if ($script:Language -eq 'ru') { 'Нет отдельных действий' } else { 'No separate actions' }))
                $emptyItem.Tag = -1
                [void]$layerAssignmentsList.Items.Add($emptyItem)
            }
            else {
                foreach ($row in $rows) {
                    $item = New-Object System.Windows.Forms.ListViewItem([string]$row.Button)
                    [void]$item.SubItems.Add([string]$row.Action)
                    $item.Tag = [int]$row.ButtonIndex
                    [void]$layerAssignmentsList.Items.Add($item)

                    if ([int]$row.ButtonIndex -eq [int]$layerButtonState.Selected) {
                        $item.Selected = $true
                        $item.Focused = $true
                    }
                }
            }
        }
        finally {
            $layerAssignmentsList.EndUpdate()
            $layerButtonState.SummarySuppress = $false
        }
    }

    $refreshEditor = {
        $index = [int]$layerButtonState.Selected
        $contextKey = & $getContextKey
        $layer = & $getLayer

        $context = Get-AdaptiveLayerContextObject -Config $working -Key $contextKey -Create
        Ensure-AdaptiveLayerContextCapacity -Context $context -ButtonCount $buttonCount

        $baseAction = Get-AdaptiveLayerBaseButtonAction -ContextKey $contextKey -ButtonIndex $index
        $override = Get-AdaptiveLayerButtonOverride -Config $working -ContextKey $contextKey -Layer $layer -ButtonIndex $index

        $selectedHeading.Text = if ($script:Language -eq 'ru') {
            'Кнопка {0} · слой {1}' -f ($index + 1), (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $layer)
        }
        else {
            'Button {0} · layer {1}' -f ($index + 1), (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $layer)
        }

        $baseLabel.Text = if ($script:Language -eq 'ru') {
            'Основное действие: ' + (Get-LargeButtonActionDisplay -Action $baseAction)
        }
        else {
            'Base action: ' + (Get-LargeButtonActionDisplay -Action $baseAction)
        }

        $layerButtonState.Suppress = $true
        try {
            Populate-AdaptiveLayerButtonActionCombo -Combo $actionCombo -Map $layerButtonState.ActionMap -CurrentAction $override
        }
        finally {
            $layerButtonState.Suppress = $false
        }

        $currentLayer = Get-AdaptiveLayerIndex
        $activePreview.Text = if ($script:Language -eq 'ru') {
            'Сейчас активен слой: ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $currentLayer)
        }
        else {
            'Active layer: ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $currentLayer)
        }

        & $refreshLayerAssignments
    }

    $selectButton = {
        param([int]$Index)

        if ($Index -lt 0 -or $Index -ge $buttonCount) { return }
        $layerButtonState.Selected = $Index
        & $refreshEditor
        & $refreshSelectorTiles
    }

    foreach ($selector in $selectors) {
        $selector.Add_Click({
            param($sender, $eventArgs)
            & $selectButton -Index ([int]$sender.Tag)
        })
    }

    $layerAssignmentsList.Add_SelectedIndexChanged({
        if ($layerButtonState.SummarySuppress) { return }
        if ($layerAssignmentsList.SelectedItems.Count -le 0) { return }

        $targetIndex = [int]$layerAssignmentsList.SelectedItems[0].Tag
        if ($targetIndex -ge 0 -and $targetIndex -lt $buttonCount) {
            & $selectButton -Index $targetIndex
        }
    })

    $refreshLayerNames = {
        & $syncLayerNamesToWorking

        Set-AdaptiveLayerComboDisplayItems -Combo $layerCombo -Config $working

        $t1Check.Text = if ($script:Language -eq 'ru') {
            'Тумблер 1 = слой ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer 1)
        }
        else {
            'Toggle 1 = layer ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer 1)
        }

        $t2Check.Text = if ($script:Language -eq 'ru') {
            'Тумблер 2 = слой ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer 2)
        }
        else {
            'Toggle 2 = layer ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer 2)
        }

        & $refreshEditor
    }

    foreach ($nameBox in $layerNameBoxes) {
        $nameBox.Add_TextChanged({
            if (-not $layerButtonState.Suppress) {
                & $refreshLayerNames
            }
        })
    }

    $profileCombo.Add_SelectedIndexChanged({
        if (-not $layerButtonState.Suppress) { & $refreshEditor }
    })
    $layerCombo.Add_SelectedIndexChanged({
        if (-not $layerButtonState.Suppress) { & $refreshEditor }
    })

    $actionCombo.Add_SelectedIndexChanged({
        if ($layerButtonState.Suppress) { return }

        $selectedIndex = [int]$actionCombo.SelectedIndex
        if ($selectedIndex -lt 0 -or $selectedIndex -ge $layerButtonState.ActionMap.Count) { return }

        $selectedAction = [string]$layerButtonState.ActionMap[$selectedIndex]
        $index = [int]$layerButtonState.Selected
        $contextKey = & $getContextKey
        $layer = & $getLayer
        $previous = Get-AdaptiveLayerButtonOverride -Config $working -ContextKey $contextKey -Layer $layer -ButtonIndex $index

        $configure = @(
            'virtual:xbox:configure',
            'hotkey:configure',
            'launch:configure',
            'folder:configure',
            'command:configure',
            'url:configure'
        )

        $configured = if ($selectedAction -in $configure) {
            Resolve-AdaptiveLayerConfiguredButtonAction -SelectedAction $selectedAction -PreviousAction $previous -Owner $dialog
        }
        else {
            $selectedAction
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$configured)) {
            Set-AdaptiveLayerButtonOverride -Config $working -ContextKey $contextKey -Layer $layer -ButtonIndex $index -Action ([string]$configured) -ButtonCount $buttonCount

            if (
                $script:VirtualGamepadFeatureAvailable -and
                (Test-MugenVirtualGamepadAction -Action ([string]$configured))
            ) {
                $layerButtonState.VirtualMappingConfigured = $true
            }
        }

        & $refreshEditor
    })

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(910, 760)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $dialog.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(1027, 760)
    $save.Size = [System.Drawing.Size]::new(108, 36)
    $dialog.Controls.Add($save)

    $save.Add_Click({
        & $syncLayerNamesToWorking

        $working.modifierToggles = @(
            [bool]$t1Check.Checked,
            $(if ([int]$script:DetectedToggleCount -gt 1) { [bool]$t2Check.Checked } else { $false })
        )

        $script:AdaptiveLayerConfig = ConvertTo-NormalizedAdaptiveLayerConfig -Data $working
        $script:AdaptiveLayersLoaded = $true
        Save-AdaptiveLayers

        if (
            $layerButtonState.VirtualMappingConfigured -and
            $script:VirtualGamepadFeatureAvailable -and
            [string]$script:ControllerProtocol -eq 'adaptive'
        ) {
            try {
                if (-not (Get-MugenVirtualGamepadEnabled)) {
                    Set-MugenVirtualGamepadEnabled -Enabled $true
                    Write-Log 'Virtual controller auto-enabled because an Xbox gamepad mapping was configured in Control layers.' 'INFO'
                }
            }
            catch {
                Write-Log ('Could not auto-enable virtual controller after layer mapping save: {0}' -f $_.Exception.Message) 'WARN'
            }
        }

        if (
            $script:VirtualGamepadFeatureAvailable -and
            $script:IsConnected -and
            [string]$script:ControllerProtocol -eq 'adaptive' -and
            @($script:LatestButtons).Count -gt 0
        ) {
            try {
                [void](Sync-MugenVirtualGamepadState -Values @($script:LatestButtons))
                Update-MugenVirtualGamepadButtonStates -Values @($script:LatestButtons) -ForceProfileCheck
            }
            catch {}
        }

        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    $liveTimer = New-Object System.Windows.Forms.Timer
    $liveTimer.Interval = 40
    $liveTimer.Add_Tick({
        $latest = @($script:LatestButtons)
        $compareCount = [Math]::Min($latest.Count, @($layerButtonState.LastButtons).Count)
        for ($i = 0; $i -lt $compareCount; $i++) {
            if ([int]$latest[$i] -eq 0 -and [int]$layerButtonState.LastButtons[$i] -ne 0) {
                & $selectButton -Index $i
                break
            }
        }
        $layerButtonState.LastButtons = @($latest)
        & $refreshSelectorTiles

        $currentLayer = Get-AdaptiveLayerIndex
        $preview = if ($script:Language -eq 'ru') {
            'Сейчас активен слой: ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $currentLayer)
        }
        else {
            'Active layer: ' + (Get-AdaptiveLayerDisplayNameFromConfig -Config $working -Layer $currentLayer)
        }
        if ($activePreview.Text -ne $preview) {
            $activePreview.Text = $preview
        }
    })

    Apply-ThemeToForm -Form $dialog
    & $refreshLayerNames
    & $refreshSelectorTiles

    $dialog.Add_Shown({
        Ensure-FormVisible -Form $dialog -CenterIfOffscreen
        $liveTimer.Start()
    })
    $dialog.Add_FormClosed({
        $liveTimer.Stop()
        $liveTimer.Dispose()
    })

    $dialog.AcceptButton = $save
    $dialog.CancelButton = $cancel
    [void]$dialog.ShowDialog($form)
    if (-not $dialog.IsDisposed) { $dialog.Dispose() }
}
function Show-AdaptiveControlSettings {
    if (-not $script:IsConnected -or ([int]$script:DetectedToggleCount + [int]$script:DetectedEncoderCount) -le 0) { return }

    Ensure-AdaptiveActionCapacity -ToggleCount ([int]$script:DetectedToggleCount) -EncoderCount ([int]$script:DetectedEncoderCount)

    Initialize-AdaptiveProfiles
    Initialize-ButtonActions

    $pendingToggles = New-Object System.Collections.ArrayList
    foreach ($item in @($script:AdaptiveToggleActions)) {
        [void]$pendingToggles.Add([pscustomobject][ordered]@{ on = [string]$item.on; off = [string]$item.off })
    }
    $pendingEncoders = New-Object System.Collections.ArrayList
    foreach ($item in @($script:AdaptiveEncoderActions)) {
        [void]$pendingEncoders.Add([pscustomobject][ordered]@{ cw = [string]$item.cw; ccw = [string]$item.ccw; push = [string]$item.push })
    }

    $workingProfiles = New-Object System.Collections.ArrayList
    foreach ($profile in @($script:AdaptiveProfiles)) {
        $profileButtons = @()
        if ($null -ne $profile.PSObject.Properties['buttons']) {
            $profileButtons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
        }

        [void]$workingProfiles.Add([pscustomobject][ordered]@{
            name = [string]$profile.name
            process = [string]$profile.process
            buttons = @($profileButtons)
            toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
            encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
        })
    }

    $profileDrafts = @{}
    $profileState = [pscustomobject]@{
        Process = ''
        Suppress = $false
        Map = New-Object System.Collections.ArrayList
    }

    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = if ($script:Language -eq 'ru') { 'Действия тумблеров и энкодеров — Mugen Deej' } else { 'Toggle and encoder actions — Mugen Deej' }
    $settingsForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $settingsForm.ClientSize = [System.Drawing.Size]::new(820, 846)
    $settingsForm.MinimumSize = [System.Drawing.Size]::new(836, 885)
    $settingsForm.MaximumSize = [System.Drawing.Size]::new(836, 885)
    $settingsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $settingsForm.MaximizeBox = $false
    $settingsForm.MinimizeBox = $false
    $settingsForm.Font = $form.Font
    Set-FormAppIcon -Form $settingsForm

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = if ($script:Language -eq 'ru') { 'Действия тумблеров и энкодеров' } else { 'Toggle and encoder actions' }
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $settingsForm.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = if ($script:Language -eq 'ru') {
        'Выберите тумблер или энкодер слева либо используйте его на контроллере.' + "`r`n" +
        'Тумблеру можно назначить действия или переключение слоя; энкодеру — вращение и нажатие.'
    }
    else {
        'Choose a toggle or encoder on the left, or use it on the controller.' + "`r`n" +
        'A toggle can run actions or switch layers; an encoder uses rotation and push.'
    }
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(770, 44)
    $settingsForm.Controls.Add($hint)

    $saveNotice = New-Object System.Windows.Forms.Label
    $saveNotice.Text = if ($script:Language -eq 'ru') { 'Изменения начнут работать только после нажатия «Сохранить».' } else { 'Changes take effect only after you click Save.' }
    $saveNotice.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    $saveNotice.Location = [System.Drawing.Point]::new(25, 102)
    $saveNotice.Size = [System.Drawing.Size]::new(770, 26)
    $settingsForm.Controls.Add($saveNotice)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = if ($script:Language -eq 'ru') { 'Профиль:' } else { 'Profile:' }
    $profileLabel.Location = [System.Drawing.Point]::new(25, 143)
    $profileLabel.Size = [System.Drawing.Size]::new(145, 30)
    $profileLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $settingsForm.Controls.Add($profileLabel)

    $profileCombo = New-Object MugenDeejWindowing.MugenComboBox
    $profileCombo.DropDownStyle = 'DropDownList'
    $profileCombo.Location = [System.Drawing.Point]::new(170, 140)
    $profileCombo.Size = [System.Drawing.Size]::new(410, 30)
    $settingsForm.Controls.Add($profileCombo)

    $addProfileButton = New-Object MugenDeejWindowing.MugenButton
    $addProfileButton.Text = if ($script:Language -eq 'ru') { 'Добавить…' } else { 'Add…' }
    $addProfileButton.Location = [System.Drawing.Point]::new(592, 139)
    $addProfileButton.Size = [System.Drawing.Size]::new(206, 32)
    $settingsForm.Controls.Add($addProfileButton)

    $profileHint = New-Object System.Windows.Forms.Label
    $profileHint.Text = if ($script:Language -eq 'ru') {
        'Общий профиль работает везде; профиль приложения включается автоматически, когда это приложение активно.'
    }
    else {
        'Global works everywhere; an application profile is selected automatically while that app is active.'
    }
    $profileHint.ForeColor = [System.Drawing.Color]::DimGray
    $profileHint.Location = [System.Drawing.Point]::new(25, 176)
    $profileHint.Size = [System.Drawing.Size]::new(770, 30)
    $settingsForm.Controls.Add($profileHint)

    $layerSettingsButton = New-Object MugenDeejWindowing.MugenButton
    $layerSettingsButton.Text = if ($script:Language -eq 'ru') { 'Слои управления…' } else { 'Control layers…' }
    $layerSettingsButton.Location = [System.Drawing.Point]::new(25, 211)
    $layerSettingsButton.Size = [System.Drawing.Size]::new(220, 32)
    $layerSettingsButton.Enabled = ([string]$script:ControllerProtocol -eq 'adaptive' -and [int]$script:DetectedToggleCount -gt 0 -and [int]$script:DetectedButtonCount -gt 0)
    $layerSettingsButton.Add_Click({
        Show-AdaptiveLayerSettings

        # Control layers are saved directly into the live Adaptive layer config.
        # Refresh this parent editor immediately after the child dialog closes so
        # modifier roles and disabled ON/OFF actions never stay visually stale
        # until some later click/toggle/encoder event happens to refresh them.
        & $refreshEditor
        & $refreshAssignmentList
    })
    $settingsForm.Controls.Add($layerSettingsButton)

    $layerSettingsHint = New-Object System.Windows.Forms.Label
    $layerSettingsHint.Text = if ($script:Language -eq 'ru') {
        'Для T1 и T2 можно задать отдельные действия кнопок и энкодера.'
    }
    else {
        'T1 and T2 can have separate button and encoder actions.'
    }
    $layerSettingsHint.ForeColor = [System.Drawing.Color]::DimGray
    $layerSettingsHint.Location = [System.Drawing.Point]::new(260, 215)
    $layerSettingsHint.Size = [System.Drawing.Size]::new(535, 28)
    $settingsForm.Controls.Add($layerSettingsHint)

    $selectorGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $selectorGroup.Text = if ($script:Language -eq 'ru') { 'Тумблеры и энкодеры' } else { 'Toggles and encoders' }
    $selectorGroup.Location = [System.Drawing.Point]::new(22, 252)
    $selectorGroup.Size = [System.Drawing.Size]::new(248, 516)
    $settingsForm.Controls.Add($selectorGroup)

    $selectorFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $selectorFlow.Location = [System.Drawing.Point]::new(12, 30)
    $selectorFlow.Size = [System.Drawing.Size]::new(224, 472)
    $selectorFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $selectorFlow.WrapContents = $true
    $selectorFlow.AutoScroll = $true
    $selectorGroup.Controls.Add($selectorFlow)

    $editorGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $editorGroup.Text = if ($script:Language -eq 'ru') { 'Выбранный элемент' } else { 'Selected control' }
    $editorGroup.Location = [System.Drawing.Point]::new(282, 252)
    $editorGroup.Size = [System.Drawing.Size]::new(516, 516)
    $settingsForm.Controls.Add($editorGroup)

    $selectedHeading = New-Object System.Windows.Forms.Label
    $selectedHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $selectedHeading.Location = [System.Drawing.Point]::new(18, 32)
    $selectedHeading.Size = [System.Drawing.Size]::new(480, 30)
    $editorGroup.Controls.Add($selectedHeading)

    $liveState = New-Object System.Windows.Forms.Label
    $liveState.ForeColor = [System.Drawing.Color]::DimGray
    $liveState.Location = [System.Drawing.Point]::new(18, 63)
    $liveState.Size = [System.Drawing.Size]::new(480, 28)
    $editorGroup.Controls.Add($liveState)

    $row1Label = New-Object System.Windows.Forms.Label
    $row1Label.Location = [System.Drawing.Point]::new(18, 112)
    $row1Label.Size = [System.Drawing.Size]::new(150, 26)
    $editorGroup.Controls.Add($row1Label)
    $row1Combo = New-Object MugenDeejWindowing.MugenComboBox
    $row1Combo.DropDownStyle = 'DropDownList'
    $row1Combo.Location = [System.Drawing.Point]::new(174, 108)
    $row1Combo.Size = [System.Drawing.Size]::new(320, 30)
    $editorGroup.Controls.Add($row1Combo)

    $row2Label = New-Object System.Windows.Forms.Label
    $row2Label.Location = [System.Drawing.Point]::new(18, 164)
    $row2Label.Size = [System.Drawing.Size]::new(150, 26)
    $editorGroup.Controls.Add($row2Label)
    $row2Combo = New-Object MugenDeejWindowing.MugenComboBox
    $row2Combo.DropDownStyle = 'DropDownList'
    $row2Combo.Location = [System.Drawing.Point]::new(174, 160)
    $row2Combo.Size = [System.Drawing.Size]::new(320, 30)
    $editorGroup.Controls.Add($row2Combo)

    $row3Label = New-Object System.Windows.Forms.Label
    $row3Label.Location = [System.Drawing.Point]::new(18, 216)
    $row3Label.Size = [System.Drawing.Size]::new(150, 26)
    $editorGroup.Controls.Add($row3Label)
    $row3Combo = New-Object MugenDeejWindowing.MugenComboBox
    $row3Combo.DropDownStyle = 'DropDownList'
    $row3Combo.Location = [System.Drawing.Point]::new(174, 212)
    $row3Combo.Size = [System.Drawing.Size]::new(320, 30)
    $editorGroup.Controls.Add($row3Combo)

    $editorHint = New-Object System.Windows.Forms.Label
    $editorHint.Text = if ($script:Language -eq 'ru') {
        'Каждый шаг поворота энкодера выполняет назначенное действие один раз. Точка • означает, что энкодер можно ещё и нажать.'
    }
    else {
        'Each encoder step runs the assigned action once. A • means the encoder can also be pressed.'
    }
    $editorHint.ForeColor = [System.Drawing.Color]::DimGray
    $editorHint.Location = [System.Drawing.Point]::new(18, 258)
    $editorHint.Size = [System.Drawing.Size]::new(476, 46)
    $editorGroup.Controls.Add($editorHint)

    $assignmentCount = New-Object System.Windows.Forms.Label
    $assignmentCount.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $assignmentCount.Location = [System.Drawing.Point]::new(18, 315)
    $assignmentCount.Size = [System.Drawing.Size]::new(250, 26)
    $editorGroup.Controls.Add($assignmentCount)

    $assignmentFilter = New-Object MugenDeejWindowing.MugenComboBox
    $assignmentFilter.DropDownStyle = 'DropDownList'
    $assignmentFilter.Location = [System.Drawing.Point]::new(322, 310)
    $assignmentFilter.Size = [System.Drawing.Size]::new(172, 30)
    [void]$assignmentFilter.Items.Add($(if ($script:Language -eq 'ru') { 'Назначенные' } else { 'Assigned' }))
    [void]$assignmentFilter.Items.Add($(if ($script:Language -eq 'ru') { 'Все назначения' } else { 'All mappings' }))
    $assignmentFilter.SelectedIndex = 0
    $editorGroup.Controls.Add($assignmentFilter)

    $assignmentList = New-Object System.Windows.Forms.ListView
    $assignmentList.Location = [System.Drawing.Point]::new(18, 348)
    $assignmentList.Size = [System.Drawing.Size]::new(476, 144)
    $assignmentList.View = [System.Windows.Forms.View]::Details
    $assignmentList.FullRowSelect = $true
    $assignmentList.HideSelection = $false
    $assignmentList.MultiSelect = $false
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Элемент' } else { 'Control' }), 78)
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Когда' } else { 'When' }), 120)
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Действие' } else { 'Action' }), 250)
    $editorGroup.Controls.Add($assignmentList)

    $selectors = @()
    for ($i = 0; $i -lt [int]$script:DetectedToggleCount; $i++) {
        $tile = New-Object MugenDeejWindowing.MugenButtonTile
        $tile.Text = ('T' + ($i + 1))
        $tile.Tag = ('t:' + $i)
        $tile.Size = [System.Drawing.Size]::new(54, 30)
        $tile.Margin = New-Object System.Windows.Forms.Padding(4, 3, 4, 3)
        $tile.TextAlign = 'MiddleCenter'
        $selectorFlow.Controls.Add($tile)
        $selectors += $tile
    }
    for ($i = 0; $i -lt [int]$script:DetectedEncoderCount; $i++) {
        $tile = New-Object MugenDeejWindowing.MugenButtonTile
        $hasPush = (@($script:LatestEncoders).Count -gt $i -and [bool]$script:LatestEncoders[$i].HasPush)
        $tile.Text = if ($hasPush) { ('E' + ($i + 1) + '•') } else { ('E' + ($i + 1)) }
        $tile.Tag = ('e:' + $i)
        $tile.Size = [System.Drawing.Size]::new(54, 30)
        $tile.Margin = New-Object System.Windows.Forms.Padding(4, 3, 4, 3)
        $tile.TextAlign = 'MiddleCenter'
        $selectorFlow.Controls.Add($tile)
        $selectors += $tile
    }

    $state = [pscustomobject]@{
        Kind = $(if ([int]$script:DetectedToggleCount -gt 0) { 't' } else { 'e' })
        Index = 0
        Suppress = $false
        Map1 = New-Object System.Collections.ArrayList
        Map2 = New-Object System.Collections.ArrayList
        Map3 = New-Object System.Collections.ArrayList
        LastToggles = @($script:LatestToggles)
        LastEncoderPositions = @($script:LatestEncoders | ForEach-Object { [int64]$_.Position })
        LastEncoderPush = @($script:LatestEncoders | ForEach-Object { if ([bool]$_.HasPush) { [int]$_.Push } else { 1 } })
    }

    $getProfileDraftKey = {
        param([string]$ProcessName)
        $normalized = Normalize-TargetName -Value $ProcessName
        if ([string]::IsNullOrWhiteSpace($normalized)) { return '__global__' }
        return $normalized.ToLowerInvariant()
    }

    $findWorkingProfile = {
        param([string]$ProcessName)
        $normalized = Normalize-TargetName -Value $ProcessName
        if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }
        foreach ($profile in @($workingProfiles)) {
            if ((Normalize-TargetName -Value ([string]$profile.process)) -ieq $normalized) { return $profile }
        }
        return $null
    }

    $captureCurrentProfileDraft = {
        $key = & $getProfileDraftKey ([string]$profileState.Process)
        $profileDrafts[$key] = [pscustomobject][ordered]@{
            toggles = @(Copy-AdaptiveProfileToggles -Items @($pendingToggles))
            encoders = @(Copy-AdaptiveProfileEncoders -Items @($pendingEncoders))
        }
    }

    $loadProfileDraft = {
        param([string]$ProcessName)

        $normalized = Normalize-TargetName -Value $ProcessName
        $key = & $getProfileDraftKey $normalized
        $draft = $null

        if ($profileDrafts.ContainsKey($key)) {
            $draft = $profileDrafts[$key]
        }
        elseif ([string]::IsNullOrWhiteSpace($normalized)) {
            $draft = [pscustomobject][ordered]@{
                toggles = @(Copy-AdaptiveProfileToggles -Items @($script:AdaptiveToggleActions))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($script:AdaptiveEncoderActions))
            }
            $profileDrafts[$key] = $draft
        }
        else {
            $profile = & $findWorkingProfile $normalized
            if ($null -eq $profile) { return }
            $draft = [pscustomobject][ordered]@{
                toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
            }
            $profileDrafts[$key] = $draft
        }

        $pendingToggles.Clear()
        foreach ($item in @($draft.toggles)) {
            [void]$pendingToggles.Add([pscustomobject][ordered]@{
                on = [string]$item.on
                off = [string]$item.off
            })
        }
        while ($pendingToggles.Count -lt [int]$script:DetectedToggleCount) {
            [void]$pendingToggles.Add([pscustomobject][ordered]@{ on = 'none'; off = 'none' })
        }

        $pendingEncoders.Clear()
        foreach ($item in @($draft.encoders)) {
            [void]$pendingEncoders.Add([pscustomobject][ordered]@{
                cw = [string]$item.cw
                ccw = [string]$item.ccw
                push = [string]$item.push
            })
        }
        while ($pendingEncoders.Count -lt [int]$script:DetectedEncoderCount) {
            [void]$pendingEncoders.Add([pscustomobject][ordered]@{ cw = 'none'; ccw = 'none'; push = 'none' })
        }

        $profileState.Process = $normalized
    }

    $populateProfileCombo = {
        param([string]$SelectProcess = '')

        $selectedNormalized = Normalize-TargetName -Value $SelectProcess
        $profileState.Suppress = $true
        try {
            $profileCombo.BeginUpdate()
            try {
                $profileCombo.Items.Clear()
                $profileState.Map.Clear()

                [void]$profileCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Общий — для всех остальных приложений' } else { 'Global — all other applications' }))
                [void]$profileState.Map.Add('')

                foreach ($profile in @($workingProfiles | Sort-Object name)) {
                    $processName = Normalize-TargetName -Value ([string]$profile.process)
                    [void]$profileCombo.Items.Add(('{0}  ({1}.exe)' -f [string]$profile.name, $processName))
                    [void]$profileState.Map.Add($processName)
                }

                $selectedIndex = 0
                for ($i = 0; $i -lt $profileState.Map.Count; $i++) {
                    if ([string]$profileState.Map[$i] -ieq $selectedNormalized) {
                        $selectedIndex = $i
                        break
                    }
                }
                $profileCombo.SelectedIndex = $selectedIndex
            }
            finally {
                $profileCombo.EndUpdate()
            }
        }
        finally {
            $profileState.Suppress = $false
        }
    }

    $showAddProfileDialog = {
        $existing = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($profile in @($workingProfiles)) {
            $name = Normalize-TargetName -Value ([string]$profile.process)
            if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$existing.Add($name) }
        }

        $runningProcesses = @(
            Get-RunningApplicationProcessNames |
            Where-Object { -not $existing.Contains((Normalize-TargetName -Value ([string]$_))) } |
            Sort-Object { Get-FriendlyProcessName -ProcessName $_ }
        )

        if ($runningProcesses.Count -eq 0) {
            [void](Show-MugenDeejStyledDialog -Message ($(if ($script:Language -eq 'ru') {
                'Не нашлось запущенного приложения без профиля. Запустите нужную программу и попробуйте снова.'
            } else {
                'No running application without a profile was found. Start the app you want and try again.'
            })) -Buttons 'OK' -Kind 'Info')
            return ''
        }

        $picker = New-Object System.Windows.Forms.Form
        $picker.Text = if ($script:Language -eq 'ru') { 'Добавить профиль приложения — Mugen Deej' } else { 'Add application profile — Mugen Deej' }
        $picker.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
        $picker.ClientSize = [System.Drawing.Size]::new(560, 220)
        $picker.MinimumSize = [System.Drawing.Size]::new(576, 259)
        $picker.MaximumSize = [System.Drawing.Size]::new(576, 259)
        $picker.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $picker.MaximizeBox = $false
        $picker.MinimizeBox = $false
        $picker.ShowInTaskbar = $false
        $picker.Font = $settingsForm.Font
        Set-FormAppIcon -Form $picker

        $pickerHeading = New-Object System.Windows.Forms.Label
        $pickerHeading.Text = if ($script:Language -eq 'ru') { 'Для какого приложения создать профиль?' } else { 'Which application should have its own profile?' }
        $pickerHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
        $pickerHeading.AutoSize = $true
        $pickerHeading.Location = [System.Drawing.Point]::new(20, 18)
        $picker.Controls.Add($pickerHeading)

        $pickerHint = New-Object System.Windows.Forms.Label
        $pickerHint.Text = if ($script:Language -eq 'ru') {
            'Новый профиль получит копию текущих назначений Общего профиля.'
        } else {
            'The new profile will start with a copy of the current Global mappings.'
        }
        $pickerHint.ForeColor = [System.Drawing.Color]::DimGray
        $pickerHint.Location = [System.Drawing.Point]::new(22, 52)
        $pickerHint.Size = [System.Drawing.Size]::new(516, 30)
        $picker.Controls.Add($pickerHint)

        $pickerCombo = New-Object MugenDeejWindowing.MugenComboBox
        $pickerCombo.DropDownStyle = 'DropDownList'
        $pickerCombo.Location = [System.Drawing.Point]::new(22, 92)
        $pickerCombo.Size = [System.Drawing.Size]::new(516, 30)
        foreach ($processName in $runningProcesses) {
            [void]$pickerCombo.Items.Add(('{0}  ({1}.exe)' -f (Get-FriendlyProcessName -ProcessName $processName), $processName))
        }
        $pickerCombo.SelectedIndex = 0
        $picker.Controls.Add($pickerCombo)

        $pickerCancel = New-Object MugenDeejWindowing.MugenButton
        $pickerCancel.Text = Get-ButtonFeatureText -Key 'Cancel'
        $pickerCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $pickerCancel.Location = [System.Drawing.Point]::new(330, 164)
        $pickerCancel.Size = [System.Drawing.Size]::new(100, 36)
        $picker.Controls.Add($pickerCancel)

        $pickerAdd = New-Object MugenDeejWindowing.MugenButton
        $pickerAdd.Text = if ($script:Language -eq 'ru') { 'Создать' } else { 'Create' }
        $pickerAdd.Tag = 'MugenPrimary'
        $pickerAdd.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $pickerAdd.Location = [System.Drawing.Point]::new(438, 164)
        $pickerAdd.Size = [System.Drawing.Size]::new(100, 36)
        $picker.Controls.Add($pickerAdd)

        Apply-ThemeToForm -Form $picker -ThemeName (Get-EffectiveTheme)
        $picker.Add_Shown({ Ensure-FormVisible -Form $picker -CenterIfOffscreen })
        $picker.AcceptButton = $pickerAdd
        $picker.CancelButton = $pickerCancel

        $result = $picker.ShowDialog($settingsForm)
        $chosen = if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            [string]$runningProcesses[[int]$pickerCombo.SelectedIndex]
        } else {
            ''
        }
        $picker.Dispose()
        return (Normalize-TargetName -Value $chosen)
    }

    & $captureCurrentProfileDraft

    $refreshAssignmentList = {
        $showAll = ($assignmentFilter.SelectedIndex -eq 1)
        $rows = @()
        $assignedCount = 0
        $totalCount = 0

        for ($i = 0; $i -lt [int]$script:DetectedToggleCount; $i++) {
            if ($i -ge $pendingToggles.Count) { continue }

            $toggleEntries = @(
                [pscustomobject]@{ Event = $(if ($script:Language -eq 'ru') { 'Включение' } else { 'Switch ON' }); Action = [string]$pendingToggles[$i].on },
                [pscustomobject]@{ Event = $(if ($script:Language -eq 'ru') { 'Выключение' } else { 'Switch OFF' }); Action = [string]$pendingToggles[$i].off }
            )

            foreach ($entry in $toggleEntries) {
                $totalCount++
                $action = ConvertTo-SafeAdaptiveAction -Action ([string]$entry.Action)
                if ($action -ne 'none') { $assignedCount++ }
                if ($showAll -or $action -ne 'none') {
                    $rows += [pscustomobject]@{
                        Control = ('T' + ($i + 1))
                        Event = [string]$entry.Event
                        Action = (Get-AdaptiveActionDisplay -Action $action)
                        Target = ('t:' + $i)
                    }
                }
            }
        }

        for ($i = 0; $i -lt [int]$script:DetectedEncoderCount; $i++) {
            if ($i -ge $pendingEncoders.Count) { continue }
            $hasPush = (@($script:LatestEncoders).Count -gt $i -and [bool]$script:LatestEncoders[$i].HasPush)

            $encoderEntries = @(
                [pscustomobject]@{ Event = $(if ($script:Language -eq 'ru') { 'По часовой' } else { 'Clockwise' }); Action = [string]$pendingEncoders[$i].cw },
                [pscustomobject]@{ Event = $(if ($script:Language -eq 'ru') { 'Против часовой' } else { 'Counter-clockwise' }); Action = [string]$pendingEncoders[$i].ccw }
            )
            if ($hasPush) {
                $encoderEntries += [pscustomobject]@{ Event = $(if ($script:Language -eq 'ru') { 'Нажатие' } else { 'Push' }); Action = [string]$pendingEncoders[$i].push }
            }

            foreach ($entry in $encoderEntries) {
                $totalCount++
                $action = ConvertTo-SafeAdaptiveAction -Action ([string]$entry.Action)
                if ($action -ne 'none') { $assignedCount++ }
                if ($showAll -or $action -ne 'none') {
                    $rows += [pscustomobject]@{
                        Control = ('E' + ($i + 1))
                        Event = [string]$entry.Event
                        Action = (Get-AdaptiveActionDisplay -Action $action)
                        Target = ('e:' + $i)
                    }
                }
            }
        }

        $assignmentCount.Text = if ($script:Language -eq 'ru') {
            'Назначено: {0} из {1}' -f $assignedCount, $totalCount
        }
        else {
            'Assigned: {0} of {1}' -f $assignedCount, $totalCount
        }

        $assignmentList.BeginUpdate()
        try {
            $assignmentList.Items.Clear()
            foreach ($row in $rows) {
                $item = New-Object System.Windows.Forms.ListViewItem([string]$row.Control)
                [void]$item.SubItems.Add([string]$row.Event)
                [void]$item.SubItems.Add([string]$row.Action)
                $item.Tag = [string]$row.Target
                [void]$assignmentList.Items.Add($item)
            }
        }
        finally {
            $assignmentList.EndUpdate()
        }
    }

    $getCurrentAction = {
        param([string]$Slot)
        $index = [int]$state.Index
        if ($state.Kind -eq 't') {
            if ($index -ge $pendingToggles.Count) { return 'none' }
            if ($Slot -eq '1') { return [string]$pendingToggles[$index].on }
            return [string]$pendingToggles[$index].off
        }
        if ($index -ge $pendingEncoders.Count) { return 'none' }
        switch ($Slot) {
            '1' { return [string]$pendingEncoders[$index].cw }
            '2' { return [string]$pendingEncoders[$index].ccw }
            default { return [string]$pendingEncoders[$index].push }
        }
    }

    $setCurrentAction = {
        param([string]$Slot, [string]$Action)
        $index = [int]$state.Index
        $Action = ConvertTo-SafeAdaptiveAction -Action $Action
        if ($state.Kind -eq 't') {
            if ($Slot -eq '1') { $pendingToggles[$index].on = $Action }
            else { $pendingToggles[$index].off = $Action }
            return
        }
        switch ($Slot) {
            '1' { $pendingEncoders[$index].cw = $Action }
            '2' { $pendingEncoders[$index].ccw = $Action }
            default { $pendingEncoders[$index].push = $Action }
        }
    }

    $refreshSelectors = {
        $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
        foreach ($tile in $selectors) {
            $parts = ([string]$tile.Tag).Split(':')
            $kind = [string]$parts[0]
            $index = [int]$parts[1]
            $selected = ($kind -eq [string]$state.Kind -and $index -eq [int]$state.Index)
            $active = $false
            if ($kind -eq 't' -and @($script:LatestToggles).Count -gt $index) {
                $active = ([int]$script:LatestToggles[$index] -eq 1)
            }
            elseif ($kind -eq 'e' -and @($script:LatestEncoders).Count -gt $index) {
                $enc = $script:LatestEncoders[$index]
                $active = ([bool]$enc.HasPush -and [int]$enc.Push -eq 0)
            }
            $tile.BackColor = if ($active) { $palette.Accent } else { $palette.Control }
            $tile.ForeColor = if ($active) { $palette.AccentText } else { $palette.Text }
            $tile.BorderColor = if ($selected) { $palette.Accent } else { $palette.Border }
        }
    }

    $refreshEditor = {
        $state.Suppress = $true
        try {
            $index = [int]$state.Index
            if ($state.Kind -eq 't') {
                $isLayerModifier = Test-AdaptiveToggleIsLayerModifier -Index $index
                $modifierLayer = if ($index -eq 0) { 1 } elseif ($index -eq 1) { 2 } else { 0 }
                $modifierLayerName = if ($modifierLayer -gt 0) {
                    Get-AdaptiveLayerDisplayName -Layer $modifierLayer
                }
                else { '' }

                $selectedHeading.Text = if ($script:Language -eq 'ru') {
                    'Тумблер ' + ($index + 1) + $(if ($isLayerModifier) { ': переключает слой «' + $modifierLayerName + '»' } else { '' })
                }
                else {
                    'Toggle ' + ($index + 1) + $(if ($isLayerModifier) { ': switches to layer ' + $modifierLayerName } else { '' })
                }

                $row1Label.Text = if ($script:Language -eq 'ru') { 'При включении' } else { 'When switched ON' }
                $row2Label.Text = if ($script:Language -eq 'ru') { 'При выключении' } else { 'When switched OFF' }
                $row3Label.Visible = $false
                $row3Combo.Visible = $false

                Populate-AdaptiveActionCombo -Combo $row1Combo -Map $state.Map1 -CurrentAction (& $getCurrentAction '1')
                Populate-AdaptiveActionCombo -Combo $row2Combo -Map $state.Map2 -CurrentAction (& $getCurrentAction '2')

                $row1Combo.Enabled = (-not $isLayerModifier)
                $row2Combo.Enabled = (-not $isLayerModifier)

                $editorHint.Text = if ($isLayerModifier) {
                    if ($script:Language -eq 'ru') {
                        'Переключает слой «' + $modifierLayerName + '». Обычные действия ВКЛ/ВЫКЛ для него недоступны. Изменить это можно в «Слои управления…».'
                    }
                    else {
                        'This toggle selects the “' + $modifierLayerName + '” layer. Its normal ON/OFF actions are unavailable. Change this in Control layers…'
                    }
                }
                else {
                    if ($script:Language -eq 'ru') {
                        'Для обычного тумблера можно отдельно назначить действие при включении и выключении.'
                    }
                    else {
                        'A normal toggle can have separate actions for ON and OFF.'
                    }
                }
            }
            else {
                $row1Combo.Enabled = $true
                $row2Combo.Enabled = $true
                $hasPush = $false
                if (@($script:LatestEncoders).Count -gt $index) { $hasPush = [bool]$script:LatestEncoders[$index].HasPush }
                $selectedHeading.Text = if ($script:Language -eq 'ru') {
                    'Энкодер ' + ($index + 1) + $(if ($hasPush) { ': с нажатием' } else { ': только вращение' })
                }
                else {
                    'Encoder ' + ($index + 1) + $(if ($hasPush) { ': with push' } else { ': rotation only' })
                }
                $row1Label.Text = if ($script:Language -eq 'ru') { 'По часовой' } else { 'Clockwise' }
                $row2Label.Text = if ($script:Language -eq 'ru') { 'Против часовой' } else { 'Counter-clockwise' }
                $row3Label.Text = if ($script:Language -eq 'ru') { 'Нажатие' } else { 'Push' }
                $hasPush = $false
                if (@($script:LatestEncoders).Count -gt $index) { $hasPush = [bool]$script:LatestEncoders[$index].HasPush }
                $row3Label.Visible = $hasPush
                $row3Combo.Visible = $hasPush
                $row3Combo.Enabled = $true
                $editorHint.Text = if ($script:Language -eq 'ru') {
                    'Поворот выполняет назначенное действие на каждом шаге. Точка • означает отдельное действие по нажатию.'
                }
                else {
                    'Each encoder step runs the assigned action once. A • means the encoder can also be pressed.'
                }
                Populate-AdaptiveActionCombo -Combo $row1Combo -Map $state.Map1 -CurrentAction (& $getCurrentAction '1')
                Populate-AdaptiveActionCombo -Combo $row2Combo -Map $state.Map2 -CurrentAction (& $getCurrentAction '2')
                if ($hasPush) { Populate-AdaptiveActionCombo -Combo $row3Combo -Map $state.Map3 -CurrentAction (& $getCurrentAction '3') }
            }
        }
        finally { $state.Suppress = $false }
        & $refreshSelectors
    }

    $selectControl = {
        param([string]$Kind, [int]$Index)
        if ($Kind -eq 't') {
            if ($Index -lt 0 -or $Index -ge [int]$script:DetectedToggleCount) { return }
        }
        else {
            if ($Index -lt 0 -or $Index -ge [int]$script:DetectedEncoderCount) { return }
        }
        $state.Kind = $Kind
        $state.Index = $Index
        & $refreshEditor
    }

    foreach ($tile in $selectors) {
        $tile.Add_Click({
            param($sender, $eventArgs)
            $parts = ([string]$sender.Tag).Split(':')
            & $selectControl -Kind ([string]$parts[0]) -Index ([int]$parts[1])
        })
    }

    $handleCombo = {
        param($Combo, $Map, [string]$Slot)
        if ($state.Suppress) { return }
        $selectedIndex = [int]$Combo.SelectedIndex
        if ($selectedIndex -lt 0 -or $selectedIndex -ge $Map.Count) { return }
        $chosen = [string]$Map[$selectedIndex]
        $previous = [string](& $getCurrentAction $Slot)
        $configured = Resolve-AdaptiveConfiguredAction -SelectedAction $chosen -PreviousAction $previous
        if (-not [string]::IsNullOrWhiteSpace($configured)) { & $setCurrentAction $Slot ([string]$configured) }
        & $refreshEditor
        & $refreshAssignmentList
    }

    $row1Combo.Add_SelectedIndexChanged({ & $handleCombo $row1Combo $state.Map1 '1' })
    $row2Combo.Add_SelectedIndexChanged({ & $handleCombo $row2Combo $state.Map2 '2' })
    $row3Combo.Add_SelectedIndexChanged({ & $handleCombo $row3Combo $state.Map3 '3' })
    $profileCombo.Add_SelectedIndexChanged({
        if ($profileState.Suppress) { return }
        $index = [int]$profileCombo.SelectedIndex
        if ($index -lt 0 -or $index -ge $profileState.Map.Count) { return }

        & $captureCurrentProfileDraft
        & $loadProfileDraft ([string]$profileState.Map[$index])
        & $refreshEditor
        & $refreshAssignmentList
    })
    $addProfileButton.Add_Click({
        & $captureCurrentProfileDraft
        $processName = [string](& $showAddProfileDialog)
        if ([string]::IsNullOrWhiteSpace($processName)) { return }

        $existingProfile = & $findWorkingProfile $processName
        if ($null -eq $existingProfile) {
            $globalDraft = $profileDrafts['__global__']
            $profile = [pscustomobject][ordered]@{
                name = (Get-FriendlyProcessName -ProcessName $processName)
                process = $processName
                buttons = @(Copy-AdaptiveProfileButtons -Items @($script:ButtonActions))
                toggles = @(Copy-AdaptiveProfileToggles -Items @($globalDraft.toggles))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($globalDraft.encoders))
            }
            [void]$workingProfiles.Add($profile)
            $key = & $getProfileDraftKey $processName
            $profileDrafts[$key] = [pscustomobject][ordered]@{
                toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
            }
        }

        & $populateProfileCombo $processName
        & $loadProfileDraft $processName
        & $refreshEditor
        & $refreshAssignmentList
    })
    $assignmentFilter.Add_SelectedIndexChanged({ & $refreshAssignmentList })
    $assignmentList.Add_SelectedIndexChanged({
        if ($assignmentList.SelectedItems.Count -eq 0) { return }
        $parts = ([string]$assignmentList.SelectedItems[0].Tag).Split(':')
        if ($parts.Count -ne 2) { return }
        & $selectControl -Kind ([string]$parts[0]) -Index ([int]$parts[1])
    })

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(580, 794)
    $cancel.Size = [System.Drawing.Size]::new(100, 36)
    $settingsForm.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(692, 794)
    $save.Size = [System.Drawing.Size]::new(106, 36)
    $settingsForm.Controls.Add($save)
    $save.Add_Click({
        & $captureCurrentProfileDraft

        $globalDraft = $profileDrafts['__global__']
        $script:AdaptiveToggleActions = @(Copy-AdaptiveProfileToggles -Items @($globalDraft.toggles))
        $script:AdaptiveEncoderActions = @(Copy-AdaptiveProfileEncoders -Items @($globalDraft.encoders))
        Save-AdaptiveActions

        foreach ($profile in @($workingProfiles)) {
            $key = & $getProfileDraftKey ([string]$profile.process)
            if ($profileDrafts.ContainsKey($key)) {
                $draft = $profileDrafts[$key]
                $profile.toggles = @(Copy-AdaptiveProfileToggles -Items @($draft.toggles))
                $profile.encoders = @(Copy-AdaptiveProfileEncoders -Items @($draft.encoders))
            }
        }

        $script:AdaptiveProfiles = @($workingProfiles)
        $script:AdaptiveProfilesLoaded = $true
        Save-AdaptiveProfiles

        Write-Log ('Adaptive profile settings saved: profiles={0}; selected={1}' -f @($script:AdaptiveProfiles).Count, $(if ([string]::IsNullOrWhiteSpace([string]$profileState.Process)) { 'Global' } else { [string]$profileState.Process + '.exe' })) 'INFO'
        $settingsForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $settingsForm.Close()
    })

    $liveTimer = New-Object System.Windows.Forms.Timer
    $liveTimer.Interval = 50
    $liveTimer.Add_Tick({
        $latestToggles = @($script:LatestToggles)
        for ($i = 0; $i -lt [Math]::Min($latestToggles.Count, @($state.LastToggles).Count); $i++) {
            if ([int]$latestToggles[$i] -ne [int]$state.LastToggles[$i]) {
                & $selectControl -Kind 't' -Index $i
                break
            }
        }

        $latestEncoders = @($script:LatestEncoders)
        for ($i = 0; $i -lt $latestEncoders.Count; $i++) {
            $oldPos = if (@($state.LastEncoderPositions).Count -gt $i) { [int64]$state.LastEncoderPositions[$i] } else { [int64]$latestEncoders[$i].Position }
            $oldPush = if (@($state.LastEncoderPush).Count -gt $i) { [int]$state.LastEncoderPush[$i] } else { 1 }
            $newPos = [int64]$latestEncoders[$i].Position
            $newPush = if ([bool]$latestEncoders[$i].HasPush) { [int]$latestEncoders[$i].Push } else { 1 }
            if ($newPos -ne $oldPos -or ($newPush -eq 0 -and $oldPush -ne 0)) {
                & $selectControl -Kind 'e' -Index $i
                break
            }
        }

        $state.LastToggles = @($latestToggles)
        $state.LastEncoderPositions = @($latestEncoders | ForEach-Object { [int64]$_.Position })
        $state.LastEncoderPush = @($latestEncoders | ForEach-Object { if ([bool]$_.HasPush) { [int]$_.Push } else { 1 } })

        if ($state.Kind -eq 't') {
            $toggleIndex = [int]$state.Index
            $isOn = (@($script:LatestToggles).Count -gt $toggleIndex -and [int]$script:LatestToggles[$toggleIndex] -eq 1)
            $isLayerModifier = Test-AdaptiveToggleIsLayerModifier -Index $toggleIndex

            $liveState.Text = if ($script:Language -eq 'ru') {
                'Состояние: ' + $(if ($isOn) { 'ВКЛ' } else { 'ВЫКЛ' }) + $(if ($isLayerModifier) { '' } else { '' })
            }
            else {
                'Now: ' + $(if ($isOn) { 'ON' } else { 'OFF' }) + $(if ($isLayerModifier) { '' } else { '' })
            }
        }
        else {
            $index = [int]$state.Index
            if (@($script:LatestEncoders).Count -gt $index) {
                $enc = $script:LatestEncoders[$index]
                $pushText = if ([bool]$enc.HasPush) {
                    if ([int]$enc.Push -eq 0) { $(if ($script:Language -eq 'ru') { 'нажат' } else { 'pressed' }) } else { $(if ($script:Language -eq 'ru') { 'отпущен' } else { 'released' }) }
                }
                else { $(if ($script:Language -eq 'ru') { 'без кнопки' } else { 'no push' }) }
                $liveState.Text = if ($script:Language -eq 'ru') { 'Позиция: {0} · {1}' -f [int64]$enc.Position, $pushText } else { 'Position: {0} · {1}' -f [int64]$enc.Position, $pushText }
            }
        }
        & $refreshSelectors
    })

    & $populateProfileCombo ''
    & $loadProfileDraft ''

    Apply-ThemeToForm -Form $settingsForm -ThemeName (Get-EffectiveTheme)
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    & $refreshEditor
    & $refreshAssignmentList

    $settingsForm.Add_Shown({
        Ensure-FormVisible -Form $settingsForm -CenterIfOffscreen
        $liveTimer.Start()
    })
    $settingsForm.Add_FormClosed({ $liveTimer.Stop(); $liveTimer.Dispose() })
    $settingsForm.AcceptButton = $save
    $settingsForm.CancelButton = $cancel
    [void]$settingsForm.ShowDialog($form)
    if (-not $settingsForm.IsDisposed) { $settingsForm.Dispose() }
}
function Initialize-AdaptiveControlStates {
    param([Parameter(Mandatory = $true)]$Packet)

    $script:LatestToggles = @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles')
    $script:LatestEncoders = @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders')
    $script:LastEncoderPositions = @()
    $script:AdaptiveDebounceDiagnostics = Get-AdaptiveDebounceDiagnostics -Packet $Packet

    foreach ($encoder in $script:LatestEncoders) {
        $script:LastEncoderPositions += [int64]$encoder.Position
    }

    if ($null -ne $script:AdaptiveDebounceDiagnostics) {
        Write-Log (
            'Firmware debounce diagnostics active: matrixDebounce={0} ms; filtered={1}; rapid={2}' -f
            [int]$script:AdaptiveDebounceDiagnostics.DebounceMs,
            [uint64]$script:AdaptiveDebounceDiagnostics.FilteredCount,
            [uint64]$script:AdaptiveDebounceDiagnostics.RapidCount
        ) 'INFO'
    }
}

function Update-AdaptiveControlStates {
    param([Parameter(Mandatory = $true)]$Packet)

    $newToggles = @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles')
    $newEncoders = @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders')
    Initialize-AdaptiveActions

    $oldToggles = @($script:LatestToggles)
    $oldLayer = Get-AdaptiveLayerIndexFromValues -Values $oldToggles
    $newLayer = Get-AdaptiveLayerIndexFromValues -Values $newToggles

    for ($i = 0; $i -lt $newToggles.Count; $i++) {
        if ($i -lt $oldToggles.Count -and [int]$oldToggles[$i] -ne [int]$newToggles[$i]) {
            $newState = [int]$newToggles[$i]
            $stateText = if ($newState -eq 1) { 'ON' } else { 'OFF' }
            Write-Log ('Toggle {0} changed: {1}' -f ($i + 1), $stateText) 'INFO'
            if (Test-AdaptiveToggleIsLayerModifier -Index $i) {
                Write-Log ('Toggle {0} is a layer modifier; ordinary {1} action suppressed' -f ($i + 1), $stateText) 'DEBUG'
            }
            else {
                $action = Get-AdaptiveToggleMappedAction -Index $i -State $newState
                Invoke-AdaptiveMappedAction -Action $action -Source ('Toggle {0} {1}' -f ($i + 1), $stateText)
            }
        }
    }

    # From this point onward encoder edges in this same Adaptive packet use
    # the newly selected T1/T2 layer.
    $script:LatestToggles = @($newToggles)

    $oldEncoders = @($script:LatestEncoders)
    for ($i = 0; $i -lt $newEncoders.Count; $i++) {
        $position = [int64]$newEncoders[$i].Position

        if ($i -lt $script:LastEncoderPositions.Count) {
            $delta = $position - [int64]$script:LastEncoderPositions[$i]
            if ($delta -ne 0) {
                Write-Log ('Encoder {0} moved: delta={1}; position={2}' -f ($i + 1), $delta, $position) 'INFO'
                $kind = if ($delta -gt 0) { 'cw' } else { 'ccw' }
                $action = Get-AdaptiveEncoderMappedAction -Index $i -Kind $kind
                $requestedSteps = [Math]::Abs([double]$delta)
                $steps = [int][Math]::Min(32.0, $requestedSteps)
                if ($requestedSteps -gt 32.0) {
                    Write-Log ('Encoder {0} delta requested {1:N0} actions; safety cap limited this packet to 32' -f ($i + 1), $requestedSteps) 'WARN'
                }
                for ($step = 0; $step -lt $steps; $step++) {
                    Invoke-AdaptiveMappedAction -Action $action -Source ('Encoder {0} {1}' -f ($i + 1), $kind.ToUpperInvariant())
                }
            }
        }

        if ($i -lt $oldEncoders.Count) {
            $oldHasPush = [bool]$oldEncoders[$i].HasPush
            $newHasPush = [bool]$newEncoders[$i].HasPush
            if ($oldHasPush -and $newHasPush -and [int]$oldEncoders[$i].Push -ne [int]$newEncoders[$i].Push) {
                $pressed = ([int]$newEncoders[$i].Push -eq 0)
                $pushText = if ($pressed) { 'pressed' } else { 'released' }
                Write-Log ('Encoder {0} push {1}' -f ($i + 1), $pushText) 'INFO'
                if ($pressed) {
                    $action = Get-AdaptiveEncoderMappedAction -Index $i -Kind 'push'
                    Invoke-AdaptiveMappedAction -Action $action -Source ('Encoder {0} push' -f ($i + 1))
                }
            }
        }
    }

    if ($oldLayer -ne $newLayer) {
        Write-Log (
            'Adaptive layer changed: {0} -> {1}' -f
            (Get-AdaptiveLayerDisplayName -Layer $oldLayer),
            (Get-AdaptiveLayerDisplayName -Layer $newLayer)
        ) 'INFO'

        Show-AdaptiveLayerNotification -Layer $newLayer

        # The virtual-controller profile context includes the active layer.
        # Force a boundary check so a held XInput mapping is neutralized and
        # suppressed until release instead of morphing into another layer.
        if (
            $script:VirtualGamepadFeatureAvailable -and
            $script:IsConnected -and
            @($script:LatestButtons).Count -gt 0
        ) {
            try {
                Update-MugenVirtualGamepadButtonStates -Values @($script:LatestButtons) -ForceProfileCheck
            }
            catch {}
        }
    }

    $script:LatestEncoders = @($newEncoders)
    $script:LastEncoderPositions = @()
    foreach ($encoder in $newEncoders) {
        $script:LastEncoderPositions += [int64]$encoder.Position
    }
}
function Get-ControllerConnectedStatusText {
    param([Parameter(Mandatory = $true)][string]$PortName)

    $sliderCount = [int]$script:DetectedSliderCount
    $buttonCount = [int]$script:DetectedButtonCount
    $toggleCount = [int]$script:DetectedToggleCount
    $encoderCount = [int]$script:DetectedEncoderCount

    if ($sliderCount -le 0 -and $script:ControllerProtocol -eq 'unknown') {
        $sliderCount = [int]$script:Config.connection.expectedSliders
    }

    # Legacy and Extended retain the stable wording they had before Adaptive
    # added extra control families. Their shorter topology already fits.
    if ($script:ControllerProtocol -ne 'adaptive') {
        if ($script:Language -eq 'ru') {
            if ($buttonCount -gt 0) {
                return ('Контроллер · {1} регуляторов · {2} кнопок' -f $PortName, $sliderCount, $buttonCount)
            }
            return ('Контроллер · {1} регуляторов' -f $PortName, $sliderCount)
        }

        if ($buttonCount -gt 0) {
            return ('Controller · {1} controls · {2} buttons' -f $PortName, $sliderCount, $buttonCount)
        }
        return ('Controller · {1} controls' -f $PortName, $sliderCount)
    }

    # Keep this formatter inside the status function. The final Adaptive
    # mappings stage rewrites the block immediately before this function.
    $formatRussianCount = {
        param(
            [int]$Count,
            [string]$One,
            [string]$Few,
            [string]$Many
        )

        $absolute = [Math]::Abs($Count)
        $mod100 = $absolute % 100
        $mod10 = $absolute % 10

        $noun = if ($mod100 -ge 11 -and $mod100 -le 14) {
            $Many
        }
        elseif ($mod10 -eq 1) {
            $One
        }
        elseif ($mod10 -ge 2 -and $mod10 -le 4) {
            $Few
        }
        else {
            $Many
        }

        return ('{0} {1}' -f $Count, $noun)
    }

    # Adaptive v3 can expose four independent families, so omit only the
    # redundant "controller connected" prefix. Keep the nouns fully written.
    if ($script:Language -eq 'ru') {
        $parts = New-Object 'System.Collections.Generic.List[string]'
        if ($sliderCount -gt 0) {
            $parts.Add((& $formatRussianCount $sliderCount 'регулятор' 'регулятора' 'регуляторов'))
        }
        if ($buttonCount -gt 0) {
            $parts.Add((& $formatRussianCount $buttonCount 'кнопка' 'кнопки' 'кнопок'))
        }
        if ($toggleCount -gt 0) {
            $parts.Add((& $formatRussianCount $toggleCount 'тумблер' 'тумблера' 'тумблеров'))
        }
        if ($encoderCount -gt 0) {
            $parts.Add((& $formatRussianCount $encoderCount 'энкодер' 'энкодера' 'энкодеров'))
        }
        if ($parts.Count -eq 0) { $parts.Add('нет органов управления') }
        return ($(if ($script:Language -eq 'ru') { 'Контроллер · ' } else { 'Controller · ' }) + ($parts -join ' · '))
    }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    if ($sliderCount -gt 0) { $parts.Add(('{0} {1}' -f $sliderCount, $(if ($sliderCount -eq 1) { 'control' } else { 'controls' }))) }
    if ($buttonCount -gt 0) { $parts.Add(('{0} {1}' -f $buttonCount, $(if ($buttonCount -eq 1) { 'button' } else { 'buttons' }))) }
    if ($toggleCount -gt 0) { $parts.Add(('{0} {1}' -f $toggleCount, $(if ($toggleCount -eq 1) { 'toggle' } else { 'toggles' }))) }
    if ($encoderCount -gt 0) { $parts.Add(('{0} {1}' -f $encoderCount, $(if ($encoderCount -eq 1) { 'encoder' } else { 'encoders' }))) }
    if ($parts.Count -eq 0) { $parts.Add('no controls') }
    return ($(if ($script:Language -eq 'ru') { 'Контроллер · ' } else { 'Controller · ' }) + ($parts -join ' · '))
}function Set-DetectedControllerCapabilities {
    param(
        [Parameter(Mandatory = $true)]$Packet,
        [string]$PortName = ''
    )

    $protocol = [string]$Packet.Protocol
    $sliderCount = @($Packet.Sliders).Count
    $buttonCount = @($Packet.Buttons).Count
    $toggleCount = @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles').Count
    $encoderCount = @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders').Count

    $changed = (
        $script:ControllerProtocol -ne $protocol -or
        $script:DetectedSliderCount -ne $sliderCount -or
        $script:DetectedButtonCount -ne $buttonCount -or
        $script:DetectedToggleCount -ne $toggleCount -or
        $script:DetectedEncoderCount -ne $encoderCount
    )

    $script:ControllerProtocol = $protocol
    $script:DetectedSliderCount = $sliderCount
    $script:DetectedButtonCount = $buttonCount
    $script:DetectedToggleCount = $toggleCount
    $script:DetectedEncoderCount = $encoderCount
    Ensure-SliderConfigCapacity -Count $sliderCount
    $script:PacketRateWindowStartedAt = [DateTime]::MinValue
    $script:PacketRateWindowCount = 0
    $script:PacketRateHz = 0.0
    $script:SoftMutedSliders = @{}
    $script:LastButtonActionAt = @{}
    if ($buttonCount -gt 0) {
        Normalize-ButtonActions -Count $buttonCount
    }
    Update-ButtonFeatureUi
    Initialize-SliderInversionProfileForCurrentController

    if ($changed) {
        Write-Log (
            'Controller capabilities detected: port={0}; protocol={1}; sliders={2}; buttons={3}; toggles={4}; encoders={5}' -f
            $PortName, $protocol, $sliderCount, $buttonCount, $toggleCount, $encoderCount
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

    if ($script:VirtualGamepadFeatureAvailable) {
        Update-MugenVirtualGamepadButtonStates -Values $valuesArray
    }

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
        $xinputHotPath = (
            $script:VirtualGamepadFeatureAvailable -and
            $script:VirtualGamepadActive
        )
        if (-not $xinputHotPath) {
            Write-Log ('Button {0} {1} (raw={2})' -f ($i + 1), $state, $newValue) 'INFO'
        }
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
            if ($ru) { return 'Действия кнопок' }
            else { return 'Button actions' }
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
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Actions
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
            $validFixedActions -contains $action -or
            (
                $script:VirtualGamepadFeatureAvailable -and
                (Test-MugenVirtualGamepadAction -Action $action)
            )
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

        # Preserve virtual gamepad actions during button normalization.
        if (
            -not $valid -and
            $script:VirtualGamepadFeatureAvailable -and
            (Test-MugenVirtualGamepadAction -Action $action)
        ) {
            $valid = $true
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
    if ($null -eq $data) { throw 'Backup file is empty.' }
    if ([string]$data.format -cne 'MugenDeejBackup') { throw 'This file is not a Mugen Deej backup.' }
    if ($null -eq $data.PSObject.Properties['schemaVersion']) { throw 'Backup schema version is missing.' }
    $schema = [int]$data.schemaVersion
    if ($schema -notin @(1, 2, 3)) { throw ('Unsupported backup schema version: {0}' -f $schema) }
    if ($null -eq $data.PSObject.Properties['config'] -or $null -eq $data.config) { throw 'Backup does not contain the main configuration.' }
    if ($null -eq $data.PSObject.Properties['buttonActions'] -or $null -eq $data.buttonActions) { throw 'Backup does not contain button actions.' }
    if ($null -eq $data.buttonActions.PSObject.Properties['version'] -or [int]$data.buttonActions.version -ne 1) { throw 'Unsupported or missing button-action configuration version in backup.' }
    if ($null -eq $data.buttonActions.PSObject.Properties['actions']) { throw 'Backup button-action list is missing.' }
    foreach ($item in @($data.buttonActions.actions)) { if ($null -eq $item) { throw 'Backup button-action list contains a null item.' } }

    if ($schema -ge 2) {
        if ($null -eq $data.PSObject.Properties['adaptiveActions'] -or $null -eq $data.adaptiveActions) { throw 'Backup does not contain Adaptive actions.' }
        if ($null -eq $data.adaptiveActions.PSObject.Properties['version'] -or [int]$data.adaptiveActions.version -ne 1) { throw 'Unsupported Adaptive action schema in backup.' }
        if ($null -eq $data.adaptiveActions.PSObject.Properties['toggles'] -or $null -eq $data.adaptiveActions.PSObject.Properties['encoders']) { throw 'Backup Adaptive action payload is incomplete.' }

        if ($null -ne $data.PSObject.Properties['adaptiveProfiles'] -and $null -ne $data.adaptiveProfiles) {
            if ($null -eq $data.adaptiveProfiles.PSObject.Properties['version'] -or [int]$data.adaptiveProfiles.version -ne 1) { throw 'Unsupported Adaptive application-profile schema in backup.' }
            if ($null -eq $data.adaptiveProfiles.PSObject.Properties['profiles']) { throw 'Backup Adaptive application-profile list is missing.' }
        }

        if ($schema -eq 3) {
            if ($null -eq $data.PSObject.Properties['adaptiveLayers'] -or $null -eq $data.adaptiveLayers) { throw 'Backup v3 does not contain Adaptive layers.' }
            if ($null -eq $data.adaptiveLayers.PSObject.Properties['version'] -or [int]$data.adaptiveLayers.version -ne 1) { throw 'Unsupported Adaptive layer schema in backup.' }

            if ($null -eq $data.PSObject.Properties['virtualController'] -or $null -eq $data.virtualController) { throw 'Backup v3 does not contain virtual-controller settings.' }
            if ($null -eq $data.virtualController.PSObject.Properties['configVersion'] -or [int]$data.virtualController.configVersion -ne 1) { throw 'Unsupported virtual-controller schema in backup.' }
            if ($null -eq $data.virtualController.PSObject.Properties['enabled'] -or $null -eq $data.virtualController.PSObject.Properties['type']) { throw 'Backup virtual-controller payload is incomplete.' }
            if ([string]$data.virtualController.type -ne 'xbox360') { throw 'Unsupported virtual-controller type in backup.' }
        }
    }
    return $data
}
function New-MugenDeejBackupSnapshot {
    Initialize-ButtonActions
    Initialize-AdaptiveActions
    Initialize-AdaptiveProfiles
    Initialize-AdaptiveLayers
    if ($script:VirtualGamepadFeatureAvailable) {
        Initialize-MugenVirtualGamepadConfig
    }

    $configClone = $script:Config | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $actions = @($script:ButtonActions | ForEach-Object { [string]$_ })
    $typedToggles = @($script:AdaptiveToggleActions | ForEach-Object { [pscustomobject][ordered]@{ on = [string]$_.on; off = [string]$_.off } })
    $typedEncoders = @($script:AdaptiveEncoderActions | ForEach-Object { [pscustomobject][ordered]@{ cw = [string]$_.cw; ccw = [string]$_.ccw; push = [string]$_.push } })
    $typedProfiles = @(
        $script:AdaptiveProfiles | ForEach-Object {
            [pscustomobject][ordered]@{
                name = [string]$_.name
                process = [string]$_.process
                buttons = @(Copy-AdaptiveProfileButtons -Items @($_.buttons))
                toggles = @(Copy-AdaptiveProfileToggles -Items @($_.toggles))
                encoders = @(Copy-AdaptiveProfileEncoders -Items @($_.encoders))
            }
        }
    )
    $layerConfig = Copy-AdaptiveLayerConfig -Config $script:AdaptiveLayerConfig
    $virtualConfig = if ($script:VirtualGamepadFeatureAvailable -and $null -ne $script:VirtualGamepadConfig) {
        [pscustomobject][ordered]@{
            configVersion = 1
            enabled = [bool]$script:VirtualGamepadConfig.enabled
            type = [string]$script:VirtualGamepadConfig.type
        }
    }
    else {
        [pscustomobject][ordered]@{
            configVersion = 1
            enabled = $false
            type = 'xbox360'
        }
    }

    return [pscustomobject][ordered]@{
        format = 'MugenDeejBackup'
        schemaVersion = 3
        createdAt = (Get-Date).ToString('o')
        createdBy = $script:AppVersion
        sourceController = [pscustomobject][ordered]@{
            protocol = [string]$script:ControllerProtocol
            sliders = [int]$script:DetectedSliderCount
            buttons = [int]$script:DetectedButtonCount
            toggles = [int]$script:DetectedToggleCount
            encoders = [int]$script:DetectedEncoderCount
        }
        config = $configClone
        buttonActions = [pscustomobject][ordered]@{ version = 1; actions = @($actions) }
        adaptiveActions = [pscustomobject][ordered]@{ version = 1; toggles = @($typedToggles); encoders = @($typedEncoders) }
        adaptiveProfiles = [pscustomobject][ordered]@{ version = 1; profiles = @($typedProfiles) }
        adaptiveLayers = $layerConfig
        virtualController = $virtualConfig
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
    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try { $backup = Read-MugenDeejBackupFile -Path $dialog.FileName }
    catch {
        Write-Log ('Backup validation failed: {0}' -f $_.Exception.Message) 'WARN'
        [void](Show-MugenDeejStyledDialog -Message ((T -Key 'BackupInvalid') + "`r`n`r`n" + $_.Exception.Message) -Buttons 'OK' -Kind 'Warning')
        return
    }

    $schema = [int]$backup.schemaVersion
    $compatibility = ''
    if ($schema -ge 2 -and $null -ne $backup.PSObject.Properties['sourceController']) {
        $src = $backup.sourceController
        $current = if ($script:IsConnected) {
            '{0} — {1}/{2}/{3}/{4}' -f (Get-ControllerProtocolDisplayText), $script:DetectedSliderCount, $script:DetectedButtonCount, $script:DetectedToggleCount, $script:DetectedEncoderCount
        }
        else { $(if ($script:Language -eq 'ru') { 'контроллер не подключён' } else { 'no controller connected' }) }
        $sourceProtocol = if ([string]$src.protocol -eq 'adaptive') { 'Adaptive v3' } elseif ([string]$src.protocol -eq 'extended') { 'Extended' } elseif ([string]$src.protocol -eq 'legacy') { 'Legacy' } else { 'Unknown' }
        $compatibility = if ($script:Language -eq 'ru') {
            "`r`n`r`nБэкап создан при: $sourceProtocol — $($src.sliders)/$($src.buttons)/$($src.toggles)/$($src.encoders).`r`nСейчас: $current.`r`nОтсутствующие назначения будут сохранены как неактивные."
        }
        else {
            "`r`n`r`nBackup source: $sourceProtocol — $($src.sliders)/$($src.buttons)/$($src.toggles)/$($src.encoders).`r`nCurrent: $current.`r`nMappings for absent controls will remain dormant."
        }
    }

    $confirmation = Show-MugenDeejStyledDialog -Message ((T -Key 'BackupRestoreConfirm') + $compatibility) -Buttons 'YesNo' -Kind 'Warning'
    if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Initialize-ButtonActions
    Initialize-AdaptiveActions
    $preRestoreSnapshot = New-MugenDeejBackupSnapshot
    $preRestorePath = Join-Path $script:BaseDir ('MugenDeej_PreRestore_{0}.backup' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    try { Write-MugenDeejBackupFile -Path $preRestorePath -Snapshot $preRestoreSnapshot }
    catch {
        Write-Log ('Restore aborted because emergency backup could not be created: {0}' -f $_.Exception.Message) 'ERROR'
        [void](Show-MugenDeejStyledDialog -Message ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $_.Exception.Message) -Buttons 'OK' -Kind 'Error')
        return
    }

    try {
        $configClone = $backup.config | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $restoredConfig = Ensure-ConfigShape -Config $configClone
        $restoredActions = @($backup.buttonActions.actions | ForEach-Object { [string]$_ })

        Save-Config -Config $restoredConfig
        Write-ButtonActionConfigFile -Path $script:ButtonActionConfigPath -Actions $restoredActions

        if ($schema -ge 2) {
            $restoredToggles = @($backup.adaptiveActions.toggles | ForEach-Object { [pscustomobject][ordered]@{ on = [string]$_.on; off = [string]$_.off } })
            $restoredEncoders = @($backup.adaptiveActions.encoders | ForEach-Object { [pscustomobject][ordered]@{ cw = [string]$_.cw; ccw = [string]$_.ccw; push = [string]$_.push } })
            Write-AdaptiveActionConfigFile -Path $script:AdaptiveActionConfigPath -Toggles $restoredToggles -Encoders $restoredEncoders
            $script:AdaptiveToggleActions = @($restoredToggles)
            $script:AdaptiveEncoderActions = @($restoredEncoders)
            $script:AdaptiveActionsLoaded = $true

            if ($null -ne $backup.PSObject.Properties['adaptiveProfiles'] -and $null -ne $backup.adaptiveProfiles) {
                $restoredProfiles = @()
                foreach ($profile in @($backup.adaptiveProfiles.profiles)) {
                    $processName = Normalize-TargetName -Value ([string]$profile.process)
                    if ([string]::IsNullOrWhiteSpace($processName)) { continue }
                    $profileButtons = @()
                    if ($null -ne $profile.PSObject.Properties['buttons']) {
                        $profileButtons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
                    }

                    $restoredProfiles += [pscustomobject][ordered]@{
                        name = [string]$profile.name
                        process = $processName
                        buttons = @($profileButtons)
                        toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
                        encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
                    }
                }
                $script:AdaptiveProfiles = @($restoredProfiles)
                $script:AdaptiveProfilesLoaded = $true
                Save-AdaptiveProfiles
                Write-Log ('Adaptive application profiles restored from backup: {0}' -f @($restoredProfiles).Count) 'INFO'
            }
            else {
                Write-Log 'Restored older backup without application profiles; current application profiles were preserved.' 'INFO'
            }

            if ($schema -eq 3) {
                $restoredLayers = ConvertTo-NormalizedAdaptiveLayerConfig -Data $backup.adaptiveLayers
                Write-AdaptiveLayerConfigFile -Path $script:AdaptiveLayerConfigPath -Config $restoredLayers
                $script:AdaptiveLayerConfig = $restoredLayers
                $script:AdaptiveLayersLoaded = $true
                Write-Log ('Adaptive layers restored from backup: contexts={0}' -f @($restoredLayers.contexts).Count) 'INFO'

                $script:VirtualGamepadConfig = [pscustomobject][ordered]@{
                    configVersion = 1
                    enabled = [bool]$backup.virtualController.enabled
                    type = 'xbox360'
                }
                $script:VirtualGamepadConfigLoaded = $true
                if ($script:VirtualGamepadFeatureAvailable) {
                    Save-MugenVirtualGamepadConfig
                }
                Write-Log ('Virtual controller setting restored from backup: enabled={0}; type=xbox360' -f [bool]$script:VirtualGamepadConfig.enabled) 'INFO'
            }
            else {
                Write-Log 'Restored backup schema v2: current Adaptive layers and virtual-controller setting were preserved because v2 did not contain those setting families.' 'INFO'
            }
        }
        else {
            Write-Log 'Restored backup schema v1: current Adaptive mappings, application profiles, layers and virtual-controller setting were preserved because v1 did not contain those setting families.' 'INFO'
        }

        $script:Config = $restoredConfig
        $script:ButtonActions = @($restoredActions)
        $script:ButtonActionsLoaded = $true
        Write-Log ('Settings restored from backup: {0}; schema={1}; emergencyBackup={2}' -f $dialog.FileName, $schema, $preRestorePath) 'INFO'

        $restartMessage = ((T -Key 'BackupRestored') + "`r`n`r`n" + (T -Key 'BackupEmergencyCopy') + "`r`n" + $preRestorePath + "`r`n`r`n" + (T -Key 'BackupRestartPrompt'))
        $restartResult = Show-MugenDeejStyledDialog -Message $restartMessage -Buttons 'YesNo' -Kind 'Info'
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
            $rollbackConfig = Ensure-ConfigShape -Config ($rollback.config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
            $rollbackActions = @($rollback.buttonActions.actions | ForEach-Object { [string]$_ })
            $rollbackToggles = @($rollback.adaptiveActions.toggles | ForEach-Object { [pscustomobject][ordered]@{ on = [string]$_.on; off = [string]$_.off } })
            $rollbackEncoders = @($rollback.adaptiveActions.encoders | ForEach-Object { [pscustomobject][ordered]@{ cw = [string]$_.cw; ccw = [string]$_.ccw; push = [string]$_.push } })
            Save-Config -Config $rollbackConfig
            Write-ButtonActionConfigFile -Path $script:ButtonActionConfigPath -Actions $rollbackActions
            Write-AdaptiveActionConfigFile -Path $script:AdaptiveActionConfigPath -Toggles $rollbackToggles -Encoders $rollbackEncoders
            $script:Config = $rollbackConfig
            $script:ButtonActions = @($rollbackActions)
            $script:ButtonActionsLoaded = $true
            $script:AdaptiveToggleActions = @($rollbackToggles)
            $script:AdaptiveEncoderActions = @($rollbackEncoders)
            $script:AdaptiveActionsLoaded = $true

            if ($null -ne $rollback.PSObject.Properties['adaptiveProfiles'] -and $null -ne $rollback.adaptiveProfiles) {
                $rollbackProfiles = @()
                foreach ($profile in @($rollback.adaptiveProfiles.profiles)) {
                    $processName = Normalize-TargetName -Value ([string]$profile.process)
                    if ([string]::IsNullOrWhiteSpace($processName)) { continue }
                    $profileButtons = @()
                    if ($null -ne $profile.PSObject.Properties['buttons']) {
                        $profileButtons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
                    }

                    $rollbackProfiles += [pscustomobject][ordered]@{
                        name = [string]$profile.name
                        process = $processName
                        buttons = @($profileButtons)
                        toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
                        encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
                    }
                }
                $script:AdaptiveProfiles = @($rollbackProfiles)
                $script:AdaptiveProfilesLoaded = $true
                Save-AdaptiveProfiles
            }

            if ($null -ne $rollback.PSObject.Properties['adaptiveLayers'] -and $null -ne $rollback.adaptiveLayers) {
                $rollbackLayers = ConvertTo-NormalizedAdaptiveLayerConfig -Data $rollback.adaptiveLayers
                Write-AdaptiveLayerConfigFile -Path $script:AdaptiveLayerConfigPath -Config $rollbackLayers
                $script:AdaptiveLayerConfig = $rollbackLayers
                $script:AdaptiveLayersLoaded = $true
            }

            if ($null -ne $rollback.PSObject.Properties['virtualController'] -and $null -ne $rollback.virtualController) {
                $script:VirtualGamepadConfig = [pscustomobject][ordered]@{
                    configVersion = 1
                    enabled = [bool]$rollback.virtualController.enabled
                    type = 'xbox360'
                }
                $script:VirtualGamepadConfigLoaded = $true
                if ($script:VirtualGamepadFeatureAvailable) {
                    Save-MugenVirtualGamepadConfig
                }
            }

            Write-Log 'Rollback after failed restore completed successfully.' 'WARN'
        }
        catch { Write-Log ('Rollback after failed restore also failed: {0}' -f $_.Exception.Message) 'ERROR' }
        [void](Show-MugenDeejStyledDialog -Message ((T -Key 'BackupRestoreFailed') + "`r`n`r`n" + $restoreError) -Buttons 'OK' -Kind 'Error')
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

function Ensure-SliderConfigCapacity {
    param([int]$Count)

    if ($Count -le 0) { return }
    $items = @($script:Config.sliders)
    while ($items.Count -lt $Count) {
        $index = $items.Count
        $items += [pscustomobject]@{
            name = (T -Key 'KnobN' -Args @($index + 1))
            defaultName = $true
            targets = @()
            inputDeviceId = ''
            inputDeviceName = ''
        }
    }
    $script:Config.sliders = @($items)
}

function Register-ControllerPacketTiming {
    $now = Get-Date
    $script:LastSerialPacketAt = $now

    if ($script:PacketRateWindowStartedAt -eq [DateTime]::MinValue) {
        $script:PacketRateWindowStartedAt = $now
        $script:PacketRateWindowCount = 1
        return
    }

    $script:PacketRateWindowCount++
    $elapsed = ($now - $script:PacketRateWindowStartedAt).TotalSeconds
    if ($elapsed -ge 1.0) {
        $script:PacketRateHz = [double]$script:PacketRateWindowCount / $elapsed
        $script:PacketRateWindowStartedAt = $now
        $script:PacketRateWindowCount = 0
    }
}

function Get-ControllerProtocolDisplayText {
    switch ([string]$script:ControllerProtocol) {
        'legacy' { return 'Legacy' }
        'extended' { return 'Extended' }
        'adaptive' { return 'Adaptive v3' }
        default { return '—' }
    }
}

function Format-ControllerStateTokenRows {
    param(
        [string[]]$Tokens,
        [int]$PerRow = 8
    )

    if ($null -eq $Tokens -or $Tokens.Count -eq 0) { return @('  —') }
    $rows = @()
    for ($start = 0; $start -lt $Tokens.Count; $start += $PerRow) {
        $end = [Math]::Min($Tokens.Count - 1, $start + $PerRow - 1)
        $slice = @()
        for ($i = $start; $i -le $end; $i++) { $slice += [string]$Tokens[$i] }
        $rows += ('  ' + ($slice -join '    '))
    }
    return @($rows)
}

function Get-FullControllerStateText {
    $ru = ($script:Language -eq 'ru')
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add($(if ($ru) { 'Полное состояние контроллера' } else { 'Full controller state' }))
    $lines.Add(('{0}: {1}    COM: {2}' -f $(if ($ru) { 'Протокол' } else { 'Protocol' }), (Get-ControllerProtocolDisplayText), $(if ([string]::IsNullOrWhiteSpace($script:ConnectedPort)) { '—' } else { $script:ConnectedPort })))
    $lines.Add('')

    $sliderTokens = @()
    for ($i = 0; $i -lt [int]$script:DetectedSliderCount; $i++) {
        $value = if (@($script:LatestLevels).Count -gt $i) {
            ('{0}%' -f [int][Math]::Round([double]$script:LatestLevels[$i] * 100.0))
        }
        else { '—' }
        $sliderTokens += ('{0}:{1}' -f ($i + 1), $value)
    }
    $lines.Add($(if ($ru) { 'Регуляторы' } else { 'Controls' }))
    foreach ($row in @(Format-ControllerStateTokenRows -Tokens $sliderTokens -PerRow 8)) { $lines.Add($row) }
    $lines.Add('')

    $buttonTokens = @()
    for ($i = 0; $i -lt [int]$script:DetectedButtonCount; $i++) {
        $pressed = (@($script:LatestButtons).Count -gt $i -and [int]$script:LatestButtons[$i] -eq 0)
        $buttonTokens += ('{0}:{1}' -f ($i + 1), $(if ($pressed) { '●' } else { '○' }))
    }
    $lines.Add($(if ($ru) { 'Кнопки' } else { 'Buttons' }))
    foreach ($row in @(Format-ControllerStateTokenRows -Tokens $buttonTokens -PerRow 10)) { $lines.Add($row) }
    $lines.Add('')

    $toggleTokens = @()
    for ($i = 0; $i -lt [int]$script:DetectedToggleCount; $i++) {
        $on = (@($script:LatestToggles).Count -gt $i -and [int]$script:LatestToggles[$i] -eq 1)
        $toggleTokens += ('{0}:{1}' -f ($i + 1), $(if ($on) { $(if ($ru) { 'Вкл' } else { 'On' }) } else { $(if ($ru) { 'Выкл' } else { 'Off' }) }))
    }
    $lines.Add($(if ($ru) { 'Тумблеры' } else { 'Toggles' }))
    foreach ($row in @(Format-ControllerStateTokenRows -Tokens $toggleTokens -PerRow 8)) { $lines.Add($row) }
    $lines.Add('')

    $encoderTokens = @()
    for ($i = 0; $i -lt [int]$script:DetectedEncoderCount; $i++) {
        $encoder = if (@($script:LatestEncoders).Count -gt $i) { $script:LatestEncoders[$i] } else { $null }
        $position = if ($null -ne $encoder) { [int64]$encoder.Position } else { 0 }
        $push = ''
        if ($null -ne $encoder -and [bool]$encoder.HasPush) {
            $push = if ([int]$encoder.Push -eq 0) { $(if ($ru) { ' наж.' } else { ' down' }) } else { '' }
        }
        $encoderTokens += ('{0}:{1}{2}' -f ($i + 1), $position, $push)
    }
    $lines.Add($(if ($ru) { 'Энкодеры' } else { 'Encoders' }))
    foreach ($row in @(Format-ControllerStateTokenRows -Tokens $encoderTokens -PerRow 6)) { $lines.Add($row) }

    return ($lines -join "`r`n")
}

function Show-FullControllerStateWindow {
    if (-not $script:IsConnected) { return }

    $stateForm = New-Object System.Windows.Forms.Form
    $stateForm.Text = if ($script:Language -eq 'ru') { 'Состояние контроллера' } else { 'Controller state' }
    $stateForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $stateForm.ClientSize = [System.Drawing.Size]::new(760, 620)
    $stateForm.MinimumSize = [System.Drawing.Size]::new(676, 500)
    $stateForm.Font = $form.Font
    $stateForm.ShowInTaskbar = $false
    Set-FormAppIcon -Form $stateForm

    $summary = New-Object MugenDeejWindowing.MugenCardPanel
    $summary.Location = [System.Drawing.Point]::new(18, 16)
    $summary.Size = [System.Drawing.Size]::new(724, 72)
    $summary.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Top -bor
        [System.Windows.Forms.AnchorStyles]::Left -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )
    $stateForm.Controls.Add($summary)

    $summaryTitle = New-Object System.Windows.Forms.Label
    $summaryTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $summaryTitle.Location = [System.Drawing.Point]::new(16, 12)
    $summaryTitle.Size = [System.Drawing.Size]::new(690, 24)
    $summary.Controls.Add($summaryTitle)

    $summaryDetail = New-Object System.Windows.Forms.Label
    $summaryDetail.ForeColor = [System.Drawing.Color]::DimGray
    $summaryDetail.Location = [System.Drawing.Point]::new(16, 39)
    $summaryDetail.Size = [System.Drawing.Size]::new(690, 23)
    $summary.Controls.Add($summaryDetail)

    $scroll = New-Object System.Windows.Forms.Panel
    $scroll.Location = [System.Drawing.Point]::new(18, 100)
    $scroll.Size = [System.Drawing.Size]::new(724, 502)
    $scroll.Anchor = (
        [System.Windows.Forms.AnchorStyles]::Top -bor
        [System.Windows.Forms.AnchorStyles]::Bottom -bor
        [System.Windows.Forms.AnchorStyles]::Left -bor
        [System.Windows.Forms.AnchorStyles]::Right
    )
    $scroll.AutoScroll = $true
    $stateForm.Controls.Add($scroll)

    $sliderViews = @()
    $buttonViews = @()
    $toggleViews = @()
    $encoderViews = @()
    $contentY = 0
    $contentWidth = 696

    if ([int]$script:DetectedSliderCount -gt 0) {
        $count = [int]$script:DetectedSliderCount
        $groupHeight = 38 + ($count * 31)
        $group = New-Object MugenDeejWindowing.MugenGroupBox
        $group.Text = if ($script:Language -eq 'ru') { 'Регуляторы ({0})' -f $count } else { 'Controls ({0})' -f $count }
        $group.Location = [System.Drawing.Point]::new(0, $contentY)
        $group.Size = [System.Drawing.Size]::new($contentWidth, $groupHeight)
        $scroll.Controls.Add($group)

        for ($i = 0; $i -lt $count; $i++) {
            $y = 31 + ($i * 31)
            $name = New-Object System.Windows.Forms.Label
            $name.Text = if ($i -lt @($script:Config.sliders).Count) { [string]$script:Config.sliders[$i].name } else { (T -Key 'KnobN' -Args @($i + 1)) }
            if ([string]::IsNullOrWhiteSpace($name.Text)) { $name.Text = (T -Key 'KnobN' -Args @($i + 1)) }
            $name.Location = [System.Drawing.Point]::new(14, $y)
            $name.Size = [System.Drawing.Size]::new(180, 24)
            $name.AutoEllipsis = $true
            $group.Controls.Add($name)

            $bar = New-Object MugenDeejWindowing.MugenProgressBar
            $bar.Location = [System.Drawing.Point]::new(202, $y)
            $bar.Size = [System.Drawing.Size]::new(380, 21)
            $bar.Minimum = 0
            $bar.Maximum = 1000
            $group.Controls.Add($bar)

            $value = New-Object System.Windows.Forms.Label
            $value.Location = [System.Drawing.Point]::new(590, $y)
            $value.Size = [System.Drawing.Size]::new(82, 23)
            $value.TextAlign = 'MiddleRight'
            $group.Controls.Add($value)
            $sliderViews += [pscustomobject]@{ Bar = $bar; Value = $value }
        }
        $contentY += $groupHeight + 10
    }

    if ([int]$script:DetectedButtonCount -gt 0) {
        $count = [int]$script:DetectedButtonCount
        $columns = 12
        $rows = [int][Math]::Ceiling($count / [double]$columns)
        $flowHeight = ($rows * 34) + 4
        $group = New-Object MugenDeejWindowing.MugenGroupBox
        $group.Text = if ($script:Language -eq 'ru') { 'Кнопки ({0})' -f $count } else { 'Buttons ({0})' -f $count }
        $group.Location = [System.Drawing.Point]::new(0, $contentY)
        $group.Size = [System.Drawing.Size]::new($contentWidth, (38 + $flowHeight))
        $scroll.Controls.Add($group)

        $flow = New-Object System.Windows.Forms.FlowLayoutPanel
        $flow.Location = [System.Drawing.Point]::new(12, 29)
        $flow.Size = [System.Drawing.Size]::new(672, $flowHeight)
        $flow.WrapContents = $true
        $flow.AutoScroll = $false
        $flow.BackColor = $group.BackColor
        $group.Controls.Add($flow)

        for ($i = 0; $i -lt $count; $i++) {
            $tile = New-Object MugenDeejWindowing.MugenButtonTile
            $tile.Text = [string]($i + 1)
            $tile.Size = [System.Drawing.Size]::new(46, 28)
            $tile.Margin = New-Object System.Windows.Forms.Padding(4, 2, 4, 2)
            $tile.TextAlign = 'MiddleCenter'
            $flow.Controls.Add($tile)
            $buttonViews += $tile
        }
        $contentY += $group.Height + 10
    }

    if ([int]$script:DetectedToggleCount -gt 0) {
        $count = [int]$script:DetectedToggleCount
        $columns = 5
        $rows = [int][Math]::Ceiling($count / [double]$columns)
        $flowHeight = ($rows * 34) + 4
        $group = New-Object MugenDeejWindowing.MugenGroupBox
        $group.Text = if ($script:Language -eq 'ru') { 'Тумблеры ({0})' -f $count } else { 'Toggles ({0})' -f $count }
        $group.Location = [System.Drawing.Point]::new(0, $contentY)
        $group.Size = [System.Drawing.Size]::new($contentWidth, (38 + $flowHeight))
        $scroll.Controls.Add($group)

        $flow = New-Object System.Windows.Forms.FlowLayoutPanel
        $flow.Location = [System.Drawing.Point]::new(12, 29)
        $flow.Size = [System.Drawing.Size]::new(672, $flowHeight)
        $flow.WrapContents = $true
        $flow.AutoScroll = $false
        $flow.BackColor = $group.BackColor
        $group.Controls.Add($flow)

        for ($i = 0; $i -lt $count; $i++) {
            $hostPanel = New-Object System.Windows.Forms.Panel
            $hostPanel.Size = [System.Drawing.Size]::new(124, 30)
            $hostPanel.Margin = New-Object System.Windows.Forms.Padding(3, 1, 3, 1)
            $hostPanel.BackColor = $group.BackColor

            $number = New-Object System.Windows.Forms.Label
            $number.Text = [string]($i + 1)
            $number.Location = [System.Drawing.Point]::new(0, 3)
            $number.Size = [System.Drawing.Size]::new(22, 24)
            $number.TextAlign = 'MiddleCenter'
            $number.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $hostPanel.Controls.Add($number)

            $switchView = New-Object System.Windows.Forms.Panel
            $switchView.Tag = $i
            $switchView.Location = [System.Drawing.Point]::new(24, 2)
            $switchView.Size = [System.Drawing.Size]::new(42, 26)
            $switchView.BackColor = $group.BackColor
            Enable-AdaptiveIndicatorDoubleBuffer -Control $switchView
            $switchView.Add_Paint({
                param($sender, $eventArgs)
                $index = [int]$sender.Tag
                $on = (@($script:LatestToggles).Count -gt $index -and [int]$script:LatestToggles[$index] -eq 1)
                $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
                $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
                try {
                    $path.AddArc(1, 4, 18, 18, 90, 180)
                    $path.AddArc(22, 4, 18, 18, 270, 180)
                    $path.CloseFigure()
                    $trackBrush = New-Object System.Drawing.SolidBrush($(if ($on) { $palette.Accent } else { $palette.ControlPressed }))
                    $borderPen = New-Object System.Drawing.Pen($palette.Border)
                    try { $eventArgs.Graphics.FillPath($trackBrush, $path); $eventArgs.Graphics.DrawPath($borderPen, $path) }
                    finally { $trackBrush.Dispose(); $borderPen.Dispose() }
                    $knobBrush = New-Object System.Drawing.SolidBrush($(if ($on) { $palette.AccentText } else { $palette.Muted }))
                    try { $eventArgs.Graphics.FillEllipse($knobBrush, $(if ($on) { 22 } else { 3 }), 6, 14, 14) }
                    finally { $knobBrush.Dispose() }
                }
                finally { $path.Dispose() }
            })
            $hostPanel.Controls.Add($switchView)

            $stateLabel = New-Object System.Windows.Forms.Label
            $stateLabel.Location = [System.Drawing.Point]::new(70, 3)
            $stateLabel.Size = [System.Drawing.Size]::new(50, 24)
            $hostPanel.Controls.Add($stateLabel)

            $flow.Controls.Add($hostPanel)
            $toggleViews += [pscustomobject]@{ Switch = $switchView; Label = $stateLabel; Last = $null }
        }
        $contentY += $group.Height + 10
    }

    if ([int]$script:DetectedEncoderCount -gt 0) {
        $count = [int]$script:DetectedEncoderCount
        $columns = 5
        $rows = [int][Math]::Ceiling($count / [double]$columns)
        $flowHeight = ($rows * 36) + 4
        $group = New-Object MugenDeejWindowing.MugenGroupBox
        $group.Text = if ($script:Language -eq 'ru') { 'Энкодеры ({0})' -f $count } else { 'Encoders ({0})' -f $count }
        $group.Location = [System.Drawing.Point]::new(0, $contentY)
        $group.Size = [System.Drawing.Size]::new($contentWidth, (38 + $flowHeight))
        $scroll.Controls.Add($group)

        $flow = New-Object System.Windows.Forms.FlowLayoutPanel
        $flow.Location = [System.Drawing.Point]::new(12, 29)
        $flow.Size = [System.Drawing.Size]::new(672, $flowHeight)
        $flow.WrapContents = $true
        $flow.AutoScroll = $false
        $flow.BackColor = $group.BackColor
        $group.Controls.Add($flow)

        for ($i = 0; $i -lt $count; $i++) {
            $hostPanel = New-Object System.Windows.Forms.Panel
            $hostPanel.Size = [System.Drawing.Size]::new(124, 32)
            $hostPanel.Margin = New-Object System.Windows.Forms.Padding(3, 1, 3, 1)
            $hostPanel.BackColor = $group.BackColor

            $number = New-Object System.Windows.Forms.Label
            $number.Text = [string]($i + 1)
            $number.Location = [System.Drawing.Point]::new(0, 4)
            $number.Size = [System.Drawing.Size]::new(22, 24)
            $number.TextAlign = 'MiddleCenter'
            $number.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $hostPanel.Controls.Add($number)

            $knob = New-Object System.Windows.Forms.Panel
            $knob.Tag = $i
            $knob.Location = [System.Drawing.Point]::new(24, 2)
            $knob.Size = [System.Drawing.Size]::new(28, 28)
            $knob.BackColor = $group.BackColor
            Enable-AdaptiveIndicatorDoubleBuffer -Control $knob
            $knob.Add_Paint({
                param($sender, $eventArgs)
                $index = [int]$sender.Tag
                $position = [int64]0
                $hasPush = $false
                $pressed = $false
                if (@($script:LatestEncoders).Count -gt $index) {
                    $enc = $script:LatestEncoders[$index]
                    $position = [int64]$enc.Position
                    $hasPush = [bool]$enc.HasPush
                    $pressed = ($hasPush -and [int]$enc.Push -eq 0)
                }
                $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
                $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $fillBrush = New-Object System.Drawing.SolidBrush($(if ($pressed) { $palette.Accent } else { $palette.Control }))
                $borderPen = New-Object System.Drawing.Pen($(if ($pressed) { $palette.Accent } else { $palette.Border }), 1)
                try { $eventArgs.Graphics.FillEllipse($fillBrush, 2, 2, 24, 24); $eventArgs.Graphics.DrawEllipse($borderPen, 2, 2, 24, 24) }
                finally { $fillBrush.Dispose(); $borderPen.Dispose() }
                $phase = (($position % 24) + 24) % 24
                $angle = (($phase * 15.0) - 90.0) * [Math]::PI / 180.0
                $center = 14.0
                $innerRadius = if ($hasPush) { 5.5 } else { 3.5 }
                $x1 = $center + ([Math]::Cos($angle) * $innerRadius)
                $y1 = $center + ([Math]::Sin($angle) * $innerRadius)
                $x2 = $center + ([Math]::Cos($angle) * 9.0)
                $y2 = $center + ([Math]::Sin($angle) * 9.0)
                $marker = New-Object System.Drawing.Pen($(if ($pressed) { $palette.AccentText } else { $palette.Accent }), 2)
                try { $eventArgs.Graphics.DrawLine($marker, [single]$x1, [single]$y1, [single]$x2, [single]$y2) }
                finally { $marker.Dispose() }

                if ($hasPush) {
                    $pushCueColor = if ($pressed) { $palette.AccentText } else { $palette.Accent }
                    $pushCuePen = New-Object System.Drawing.Pen($pushCueColor, 1.5)
                    try {
                        $eventArgs.Graphics.DrawEllipse($pushCuePen, 11, 11, 6, 6)
                        if ($pressed) {
                            $pushCueBrush = New-Object System.Drawing.SolidBrush($pushCueColor)
                            try { $eventArgs.Graphics.FillEllipse($pushCueBrush, 12, 12, 4, 4) }
                            finally { $pushCueBrush.Dispose() }
                        }
                    }
                    finally { $pushCuePen.Dispose() }
                }
            })
            $hostPanel.Controls.Add($knob)

            $positionLabel = New-Object System.Windows.Forms.Label
            $positionLabel.Location = [System.Drawing.Point]::new(58, 4)
            $positionLabel.Size = [System.Drawing.Size]::new(62, 24)
            $positionLabel.TextAlign = 'MiddleCenter'
            $positionLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $hostPanel.Controls.Add($positionLabel)
            $flow.Controls.Add($hostPanel)
            $encoderViews += [pscustomobject]@{ Knob = $knob; Label = $positionLabel; LastPosition = $null; LastHasPush = $null; LastPressed = $null }
        }
        $contentY += $group.Height + 10
    }

    $scroll.AutoScrollMinSize = [System.Drawing.Size]::new(696, [Math]::Max(0, $contentY))

    $refreshState = {
        $summaryTitle.Text = if ($script:IsConnected) {
            '{0} · {1}' -f (Get-ControllerProtocolDisplayText), $(if ([string]::IsNullOrWhiteSpace($script:ConnectedPort)) { 'COM —' } else { $script:ConnectedPort })
        }
        else { $(if ($script:Language -eq 'ru') { 'Связь с контроллером потеряна' } else { 'Controller disconnected' }) }
        $summaryDetail.Text = if ($script:Language -eq 'ru') {
            '{0} регуляторов · {1} кнопок · {2} тумблеров · {3} энкодеров' -f $script:DetectedSliderCount, $script:DetectedButtonCount, $script:DetectedToggleCount, $script:DetectedEncoderCount
        }
        else {
            '{0} controls · {1} buttons · {2} toggles · {3} encoders' -f $script:DetectedSliderCount, $script:DetectedButtonCount, $script:DetectedToggleCount, $script:DetectedEncoderCount
        }

        for ($i = 0; $i -lt $sliderViews.Count; $i++) {
            $level = if (@($script:LatestLevels).Count -gt $i) { [double]$script:LatestLevels[$i] } else { 0.0 }
            $level = [Math]::Max(0.0, [Math]::Min(1.0, $level))
            $sliderViews[$i].Bar.Value = [int][Math]::Round($level * 1000.0)
            $sliderViews[$i].Value.Text = ('{0}%' -f [int][Math]::Round($level * 100.0))
        }
        for ($i = 0; $i -lt $buttonViews.Count; $i++) {
            Set-ButtonIndicatorAppearance -Indicator $buttonViews[$i] -ButtonIndex $i
        }
        for ($i = 0; $i -lt $toggleViews.Count; $i++) {
            $on = (@($script:LatestToggles).Count -gt $i -and [int]$script:LatestToggles[$i] -eq 1)
            $toggleViews[$i].Label.Text = if ($script:Language -eq 'ru') { if ($on) { 'Вкл' } else { 'Выкл' } } else { if ($on) { 'On' } else { 'Off' } }
            if ($null -eq $toggleViews[$i].Last -or [bool]$toggleViews[$i].Last -ne $on) {
                $toggleViews[$i].Last = $on
                $toggleViews[$i].Switch.Invalidate()
            }
        }
        for ($i = 0; $i -lt $encoderViews.Count; $i++) {
            $position = [int64]0
            $hasPush = $false
            $pressed = $false
            if (@($script:LatestEncoders).Count -gt $i) {
                $enc = $script:LatestEncoders[$i]
                $position = [int64]$enc.Position
                $hasPush = [bool]$enc.HasPush
                $pressed = ($hasPush -and [int]$enc.Push -eq 0)
            }
            $encoderViews[$i].Label.Text = [string]$position
            if ($null -eq $encoderViews[$i].LastPosition -or [int64]$encoderViews[$i].LastPosition -ne $position -or $null -eq $encoderViews[$i].LastHasPush -or [bool]$encoderViews[$i].LastHasPush -ne $hasPush -or $null -eq $encoderViews[$i].LastPressed -or [bool]$encoderViews[$i].LastPressed -ne $pressed) {
                $encoderViews[$i].LastPosition = $position
                $encoderViews[$i].LastHasPush = $hasPush
                $encoderViews[$i].LastPressed = $pressed
                $encoderViews[$i].Knob.Invalidate()
            }
        }
    }

    $stateTimer = New-Object System.Windows.Forms.Timer
    $stateTimer.Interval = 75
    $stateTimer.Add_Tick({ & $refreshState })

    try {
        Apply-ThemeToForm -Form $stateForm -ThemeName (Get-EffectiveTheme)
        & $refreshState
        $stateTimer.Start()
        [void]$stateForm.ShowDialog($form)
    }
    finally {
        $stateTimer.Stop()
        $stateTimer.Dispose()
        if (-not $stateForm.IsDisposed) { $stateForm.Dispose() }
    }
}
function Get-MainInputOverflowCount {
    $buttonMetrics = Get-AdaptiveButtonLayoutMetrics -Count ([int]$script:DetectedButtonCount)
    $typedMetrics = Get-AdaptiveInputStatusLayoutMetrics
    return (
        [int]$buttonMetrics.OverflowCount +
        [int]$typedMetrics.ToggleOverflowCount +
        [int]$typedMetrics.EncoderOverflowCount
    )
}

function Update-SliderCapabilityUi {
    $count = if ($script:IsConnected) {
        [int]$script:DetectedSliderCount
    }
    else {
        [int]$script:Config.connection.expectedSliders
    }

    $visibleCount = [Math]::Min($count, @($script:KnobProgressBars).Count)
    $hasSliders = ($count -gt 0)
    $knobGroup.Visible = $hasSliders
    $settingsButton.Visible = $hasSliders
    $settingsButton.Enabled = $hasSliders

    for ($i = 0; $i -lt @($script:KnobProgressBars).Count; $i++) {
        $visible = ($i -lt $visibleCount)
        $script:KnobNameLabels[$i].Visible = $visible
        $script:KnobProgressBars[$i].Visible = $visible
        $script:KnobPercentLabels[$i].Visible = $visible
    }

    if ($null -eq $script:SliderOverflowButton -or $script:SliderOverflowButton.IsDisposed) {
        $script:SliderOverflowButton = New-Object MugenDeejWindowing.MugenButton
        $script:SliderOverflowButton.Tag = 'MugenSection'
        $script:SliderOverflowButton.Size = [System.Drawing.Size]::new(180, 28)
        $script:SliderOverflowButton.Add_Click({ Show-FullControllerStateWindow })
        $knobGroup.Controls.Add($script:SliderOverflowButton)
    }

    $hidden = [Math]::Max(0, $count - $visibleCount)
    $script:SliderOverflowButton.Visible = ($hidden -gt 0)
    if ($hidden -gt 0) {
        $script:SliderOverflowButton.Text = if ($script:Language -eq 'ru') {
            ('Показать все… (+{0})' -f $hidden)
        }
        else {
            ('Show all… (+{0})' -f $hidden)
        }
        $script:SliderOverflowButton.Location = [System.Drawing.Point]::new(16, (34 + ($visibleCount * 29)))
    }

    if ($hasSliders) {
        $height = 42 + ($visibleCount * 29)
        if ($hidden -gt 0) { $height += 34 }
        $knobGroup.Size = [System.Drawing.Size]::new(632, [Math]::Max(76, $height))
    }

    return $hasSliders
}
function Get-AdaptiveButtonLayoutMetrics {
    param([int]$Count)

    if ($Count -le 11) {
        return [pscustomobject]@{
            Compact = $false
            TileWidth = 46
            TileHeight = 28
            MarginX = 4
            MarginY = 1
            Columns = 11
            Rows = $(if ($Count -gt 0) { 1 } else { 0 })
            VisibleCount = [Math]::Max(0, $Count)
            OverflowCount = 0
            FlowHeight = 34
            GroupHeight = 72
        }
    }

    $tileWidth = 30
    $tileHeight = 24
    $marginX = 2
    $marginY = 1
    $stride = $tileWidth + ($marginX * 2)
    $columns = [Math]::Max(1, [Math]::Floor(606 / $stride))
    $actualRows = [Math]::Max(1, [int][Math]::Ceiling($Count / [double]$columns))
    $rows = [Math]::Min(2, $actualRows)
    $visibleCount = [Math]::Min($Count, ($columns * $rows))
    $overflowCount = [Math]::Max(0, $Count - $visibleCount)
    $flowHeight = ($rows * ($tileHeight + ($marginY * 2))) + 2
    $groupHeight = 38 + $flowHeight

    return [pscustomobject]@{
        Compact = $true
        TileWidth = $tileWidth
        TileHeight = $tileHeight
        MarginX = $marginX
        MarginY = $marginY
        Columns = $columns
        Rows = $rows
        VisibleCount = $visibleCount
        OverflowCount = $overflowCount
        FlowHeight = $flowHeight
        GroupHeight = $groupHeight
    }
}
function Ensure-MainButtonIndicators {
    $actualCount = if ($script:IsConnected) { [int]$script:DetectedButtonCount } else { 0 }

    if ($null -eq $script:ButtonStateFlow -or $script:ButtonStateFlow.IsDisposed) { return }

    $metrics = Get-AdaptiveButtonLayoutMetrics -Count $actualCount
    $count = [int]$metrics.VisibleCount
    $script:ButtonStateFlow.WrapContents = [bool]$metrics.Compact
    $script:ButtonStateFlow.AutoScroll = $false

    if (@($script:MainButtonIndicators).Count -eq $count) { return }

    $script:ButtonStateFlow.SuspendLayout()
    try {
        $script:ButtonStateFlow.Controls.Clear()
        $script:MainButtonIndicators = @()

        for ($i = 0; $i -lt $count; $i++) {
            $indicator = New-Object MugenDeejWindowing.MugenButtonTile
            $indicator.Text = [string]($i + 1)
            $indicator.Size = [System.Drawing.Size]::new(
                [int]$metrics.TileWidth,
                [int]$metrics.TileHeight
            )
            $indicator.Margin = New-Object System.Windows.Forms.Padding(
                [int]$metrics.MarginX,
                [int]$metrics.MarginY,
                [int]$metrics.MarginX,
                [int]$metrics.MarginY
            )
            $indicator.TextAlign = 'MiddleCenter'
            $indicator.BorderStyle = 'None'
            $indicator.Font = New-Object System.Drawing.Font(
                'Segoe UI Semibold',
                $(if ($metrics.Compact) { 8.5 } else { 9 })
            )
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

    # Adaptive high-button main-grid UI: keep the live physical identification
    # surface visible in every controller size instead of replacing it with a
    # count-only summary.
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

function Get-AdaptiveInputUiText {
    param([Parameter(Mandatory = $true)][string]$Key)

    $ru = ($script:Language -eq 'ru')
    switch ($Key) {
        'Group' {
            if ($ru) { return 'Тумблеры и энкодеры' }
            else { return 'Toggles and encoders' }
        }
        'Toggles' {
            if ($ru) { return 'Тумблеры' }
            else { return 'Toggles' }
        }
        'Encoders' {
            if ($ru) { return 'Энкодеры' }
            else { return 'Encoders' }
        }
        'Push' {
            if ($ru) { return 'Кнопка' }
            else { return 'Push' }
        }
        'On' {
            if ($ru) { return 'ВКЛ' }
            else { return 'ON' }
        }
        'Off' {
            if ($ru) { return 'ВЫКЛ' }
            else { return 'OFF' }
        }
        default { return $Key }
    }
}

function Get-AdaptiveInputStatusLayoutMetrics {
    $toggleCount = if ($script:IsConnected) { [int]$script:DetectedToggleCount } else { 0 }
    $encoderCount = if ($script:IsConnected) { [int]$script:DetectedEncoderCount } else { 0 }

    $visibleToggleCount = [Math]::Min($toggleCount, 6)
    $visibleEncoderCount = [Math]::Min($encoderCount, 3)
    $toggleRows = if ($visibleToggleCount -gt 0) { 1 } else { 0 }
    $encoderRows = if ($visibleEncoderCount -gt 0) { 1 } else { 0 }

    $toggleHeight = $toggleRows * 30
    $encoderHeight = $encoderRows * 32
    $sectionGap = if ($toggleCount -gt 0 -and $encoderCount -gt 0) { 4 } else { 0 }
    $hasControls = ($toggleCount -gt 0 -or $encoderCount -gt 0)
    $groupHeight = if ($hasControls) {
        42 + $toggleHeight + $encoderHeight + $sectionGap
    }
    else { 0 }

    return [pscustomobject]@{
        HasControls = $hasControls
        ToggleCount = $toggleCount
        EncoderCount = $encoderCount
        VisibleToggleCount = $visibleToggleCount
        VisibleEncoderCount = $visibleEncoderCount
        ToggleOverflowCount = [Math]::Max(0, $toggleCount - $visibleToggleCount)
        EncoderOverflowCount = [Math]::Max(0, $encoderCount - $visibleEncoderCount)
        ToggleRows = $toggleRows
        EncoderRows = $encoderRows
        ToggleHeight = $toggleHeight
        EncoderHeight = $encoderHeight
        SectionGap = $sectionGap
        GroupHeight = $groupHeight
    }
}
function Enable-AdaptiveIndicatorDoubleBuffer {
    param([Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Control)

    try {
        $flags = (
            [System.Reflection.BindingFlags]::Instance -bor
            [System.Reflection.BindingFlags]::NonPublic
        )
        $property = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', $flags)
        if ($null -ne $property) {
            $property.SetValue($Control, $true, $null)
        }
    }
    catch {
        # Double-buffering is a visual optimization only. If reflection is
        # unavailable for any reason, state rendering must still keep working.
    }
}

function Ensure-MainToggleIndicators {
    $metrics = Get-AdaptiveInputStatusLayoutMetrics
    $count = [int]$metrics.VisibleToggleCount
    if ($null -eq $script:ToggleStateFlow -or $script:ToggleStateFlow.IsDisposed) { return }
    if (@($script:MainToggleIndicators).Count -eq $count) { return }

    $script:ToggleStateFlow.SuspendLayout()
    try {
        $script:ToggleStateFlow.Controls.Clear()
        $script:MainToggleIndicators = @()

        for ($i = 0; $i -lt $count; $i++) {
            $surfaceBack = if ($null -ne $script:AdaptiveStateGroup) {
                $script:AdaptiveStateGroup.BackColor
            }
            else {
                $script:ThemePalettes[(Get-EffectiveTheme)].SurfaceAlt
            }

            $toggleItemHost = New-Object System.Windows.Forms.Panel
            # Keep the main-card toggle compact enough to share one row with
            # two encoder indicators on the fixed-width dashboard.
            $toggleItemHost.Size = [System.Drawing.Size]::new(96, 28)
            $toggleItemHost.Margin = New-Object System.Windows.Forms.Padding(1, 0, 2, 0)
            $toggleItemHost.BorderStyle = [System.Windows.Forms.BorderStyle]::None
            $toggleItemHost.BackColor = $surfaceBack

            $numberLabel = New-Object System.Windows.Forms.Label
            $numberLabel.Text = [string]($i + 1)
            $numberLabel.Location = [System.Drawing.Point]::new(0, 2)
            $numberLabel.Size = [System.Drawing.Size]::new(16, 24)
            $numberLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $numberLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $toggleItemHost.Controls.Add($numberLabel)

            $switchView = New-Object System.Windows.Forms.Panel
            $switchView.Tag = $i
            $switchView.Location = [System.Drawing.Point]::new(18, 1)
            $switchView.Size = [System.Drawing.Size]::new(42, 26)
            $switchView.BackColor = $surfaceBack
            Enable-AdaptiveIndicatorDoubleBuffer -Control $switchView
            $switchView.Add_Paint({
                param($sender, $eventArgs)

                $index = [int]$sender.Tag
                $isOn = (
                    @($script:LatestToggles).Count -gt $index -and
                    [int]$script:LatestToggles[$index] -eq 1
                )
                $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
                $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
                try {
                    $path.AddArc(1, 4, 18, 18, 90, 180)
                    $path.AddArc(22, 4, 18, 18, 270, 180)
                    $path.CloseFigure()

                    $trackColor = if ($isOn) { $palette.Accent } else { $palette.ControlPressed }
                    $trackBrush = New-Object System.Drawing.SolidBrush($trackColor)
                    $borderPen = New-Object System.Drawing.Pen($palette.Border)
                    try {
                        $eventArgs.Graphics.FillPath($trackBrush, $path)
                        $eventArgs.Graphics.DrawPath($borderPen, $path)
                    }
                    finally {
                        $trackBrush.Dispose()
                        $borderPen.Dispose()
                    }

                    $knobX = if ($isOn) { 22 } else { 3 }
                    $knobColor = if ($isOn) { $palette.AccentText } else { $palette.Muted }
                    $knobBrush = New-Object System.Drawing.SolidBrush($knobColor)
                    try {
                        $eventArgs.Graphics.FillEllipse($knobBrush, $knobX, 6, 14, 14)
                    }
                    finally {
                        $knobBrush.Dispose()
                    }
                }
                finally {
                    $path.Dispose()
                }
            })
            $toggleItemHost.Controls.Add($switchView)

            $stateLabel = New-Object System.Windows.Forms.Label
            $stateLabel.Location = [System.Drawing.Point]::new(62, 2)
            $stateLabel.Size = [System.Drawing.Size]::new(34, 24)
            $stateLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $stateLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
            $toggleItemHost.Controls.Add($stateLabel)

            $script:ToggleStateFlow.Controls.Add($toggleItemHost)
            $script:MainToggleIndicators += [pscustomobject]@{
                Host = $toggleItemHost
                NumberLabel = $numberLabel
                SwitchView = $switchView
                StateLabel = $stateLabel
                LastOn = $null
                LastTheme = ''
            }
        }
    }
    finally {
        $script:ToggleStateFlow.ResumeLayout($true)
    }
}

function Ensure-MainEncoderIndicators {
    $metrics = Get-AdaptiveInputStatusLayoutMetrics
    $count = [int]$metrics.VisibleEncoderCount
    if ($null -eq $script:EncoderStateFlow -or $script:EncoderStateFlow.IsDisposed) { return }
    if (@($script:MainEncoderIndicators).Count -eq $count) { return }

    $script:EncoderStateFlow.SuspendLayout()
    try {
        $script:EncoderStateFlow.Controls.Clear()
        $script:MainEncoderIndicators = @()

        for ($i = 0; $i -lt $count; $i++) {
            $surfaceBack = if ($null -ne $script:AdaptiveStateGroup) {
                $script:AdaptiveStateGroup.BackColor
            }
            else {
                $script:ThemePalettes[(Get-EffectiveTheme)].SurfaceAlt
            }

            $encoderItemHost = New-Object System.Windows.Forms.Panel
            # Two compact encoder indicators must fit beside the two-toggle
            # block in the shared typed-control row.
            $encoderItemHost.Size = [System.Drawing.Size]::new(96, 30)
            $encoderItemHost.Margin = New-Object System.Windows.Forms.Padding(2, 0, 5, 0)
            $encoderItemHost.BorderStyle = [System.Windows.Forms.BorderStyle]::None
            $encoderItemHost.BackColor = $surfaceBack

            $numberLabel = New-Object System.Windows.Forms.Label
            $numberLabel.Text = [string]($i + 1)
            $numberLabel.Location = [System.Drawing.Point]::new(0, 3)
            $numberLabel.Size = [System.Drawing.Size]::new(16, 24)
            $numberLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $numberLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $encoderItemHost.Controls.Add($numberLabel)

            $knobView = New-Object System.Windows.Forms.Panel
            $knobView.Tag = $i
            $knobView.Location = [System.Drawing.Point]::new(20, 1)
            $knobView.Size = [System.Drawing.Size]::new(28, 28)
            $knobView.BackColor = $surfaceBack
            Enable-AdaptiveIndicatorDoubleBuffer -Control $knobView
            $knobView.Add_Paint({
                param($sender, $eventArgs)

                $index = [int]$sender.Tag
                $position = [int64]0
                $hasPush = $false
                $pressed = $false
                if (@($script:LatestEncoders).Count -gt $index) {
                    $currentEncoder = $script:LatestEncoders[$index]
                    if ($null -ne $currentEncoder) {
                        $position = [int64]$currentEncoder.Position
                        $hasPush = [bool]$currentEncoder.HasPush
                        $pressed = (
                            $hasPush -and
                            [int]$currentEncoder.Push -eq 0
                        )
                    }
                }

                $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
                $eventArgs.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

                # The encoder itself is also its push indicator. Pressing the
                # shaft lights the knob instead of showing a detached "Push"
                # button next to a rotary control.
                $fillColor = if ($pressed) { $palette.Accent } else { $palette.Control }
                $borderColor = if ($pressed) { $palette.Accent } else { $palette.Border }
                $fillBrush = New-Object System.Drawing.SolidBrush($fillColor)
                $borderPen = New-Object System.Drawing.Pen($borderColor, 1)
                try {
                    $eventArgs.Graphics.FillEllipse($fillBrush, 2, 2, 24, 24)
                    $eventArgs.Graphics.DrawEllipse($borderPen, 2, 2, 24, 24)
                }
                finally {
                    $fillBrush.Dispose()
                    $borderPen.Dispose()
                }

                # Endless encoders have no absolute min/max. Rotate the marker
                # by one 15-degree step per detent so movement is visible while
                # the numeric cumulative position remains the source of truth.
                $phase = (($position % 24) + 24) % 24
                $angle = (($phase * 15.0) - 90.0) * [Math]::PI / 180.0
                $centerX = 14.0
                $centerY = 14.0
                $innerRadius = if ($hasPush) { 5.5 } else { 3.5 }
                $outerRadius = 9.0
                $x1 = $centerX + ([Math]::Cos($angle) * $innerRadius)
                $y1 = $centerY + ([Math]::Sin($angle) * $innerRadius)
                $x2 = $centerX + ([Math]::Cos($angle) * $outerRadius)
                $y2 = $centerY + ([Math]::Sin($angle) * $outerRadius)

                $markerColor = if ($pressed) { $palette.AccentText } else { $palette.Accent }
                $markerPen = New-Object System.Drawing.Pen($markerColor, 2)
                try {
                    $markerPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
                    $markerPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
                    $eventArgs.Graphics.DrawLine($markerPen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
                }
                finally {
                    $markerPen.Dispose()
                }

                if ($hasPush) {
                    $pushCueColor = if ($pressed) { $palette.AccentText } else { $palette.Accent }
                    $pushCuePen = New-Object System.Drawing.Pen($pushCueColor, 1.5)
                    try {
                        $eventArgs.Graphics.DrawEllipse($pushCuePen, 11, 11, 6, 6)
                        if ($pressed) {
                            $pushCueBrush = New-Object System.Drawing.SolidBrush($pushCueColor)
                            try {
                                $eventArgs.Graphics.FillEllipse($pushCueBrush, 12, 12, 4, 4)
                            }
                            finally {
                                $pushCueBrush.Dispose()
                            }
                        }
                    }
                    finally {
                        $pushCuePen.Dispose()
                    }
                }
            })
            $encoderItemHost.Controls.Add($knobView)

            $positionLabel = New-Object System.Windows.Forms.Label
            $positionLabel.Location = [System.Drawing.Point]::new(50, 3)
            $positionLabel.Size = [System.Drawing.Size]::new(42, 24)
            $positionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $positionLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
            $encoderItemHost.Controls.Add($positionLabel)

            $script:EncoderStateFlow.Controls.Add($encoderItemHost)
            $script:MainEncoderIndicators += [pscustomobject]@{
                Host = $encoderItemHost
                NumberLabel = $numberLabel
                KnobView = $knobView
                PositionLabel = $positionLabel
                LastPosition = $null
                LastHasPush = $null
                LastPressed = $null
                LastTheme = ''
            }
        }
    }
    finally {
        $script:EncoderStateFlow.ResumeLayout($true)
    }
}

function Update-AdaptiveInputIndicators {
    Ensure-MainToggleIndicators
    Ensure-MainEncoderIndicators

    $themeKey = [string](Get-EffectiveTheme)
    $palette = $script:ThemePalettes[$themeKey]
    $surfaceBack = if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        $script:AdaptiveStateGroup.BackColor
    }
    else {
        $palette.SurfaceAlt
    }

    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        if ($null -ne $script:ToggleStateFlow -and -not $script:ToggleStateFlow.IsDisposed) {
            if ($script:ToggleStateFlow.BackColor.ToArgb() -ne $surfaceBack.ToArgb()) {
                $script:ToggleStateFlow.BackColor = $surfaceBack
            }
        }
        if ($null -ne $script:EncoderStateFlow -and -not $script:EncoderStateFlow.IsDisposed) {
            if ($script:EncoderStateFlow.BackColor.ToArgb() -ne $surfaceBack.ToArgb()) {
                $script:EncoderStateFlow.BackColor = $surfaceBack
            }
        }
    }

    for ($i = 0; $i -lt @($script:MainToggleIndicators).Count; $i++) {
        $view = $script:MainToggleIndicators[$i]
        $on = (
            @($script:LatestToggles).Count -gt $i -and
            [int]$script:LatestToggles[$i] -eq 1
        )

        $surfaceChanged = ($view.Host.BackColor.ToArgb() -ne $surfaceBack.ToArgb())
        if ($surfaceChanged) {
            $view.Host.BackColor = $surfaceBack
            $view.SwitchView.BackColor = $surfaceBack
        }

        if ($view.NumberLabel.ForeColor.ToArgb() -ne $palette.Text.ToArgb()) {
            $view.NumberLabel.ForeColor = $palette.Text
        }

        $stateText = if ($script:Language -eq 'ru') {
            $(if ($on) { 'Вкл' } else { 'Выкл' })
        }
        else {
            $(if ($on) { 'On' } else { 'Off' })
        }
        if ($view.StateLabel.Text -ne $stateText) {
            $view.StateLabel.Text = $stateText
        }

        $stateColor = if ($on) { $palette.Accent } else { $palette.Muted }
        if ($view.StateLabel.ForeColor.ToArgb() -ne $stateColor.ToArgb()) {
            $view.StateLabel.ForeColor = $stateColor
        }

        # Adaptive v3 currently streams every 25 ms. Repainting an unchanged
        # owner-drawn switch on every packet visibly flickers. Repaint only
        # when the state/theme/surface actually changes.
        if (
            $surfaceChanged -or
            $null -eq $view.LastOn -or
            [bool]$view.LastOn -ne $on -or
            [string]$view.LastTheme -ne $themeKey
        ) {
            $view.LastOn = $on
            $view.LastTheme = $themeKey
            $view.SwitchView.Invalidate()
        }
    }

    for ($i = 0; $i -lt @($script:MainEncoderIndicators).Count; $i++) {
        $view = $script:MainEncoderIndicators[$i]
        $encoder = if (@($script:LatestEncoders).Count -gt $i) { $script:LatestEncoders[$i] } else { $null }
        $position = if ($null -ne $encoder) { [int64]$encoder.Position } else { [int64]0 }
        $hasPush = ($null -ne $encoder -and [bool]$encoder.HasPush)
        $pressed = ($hasPush -and [int]$encoder.Push -eq 0)

        $surfaceChanged = ($view.Host.BackColor.ToArgb() -ne $surfaceBack.ToArgb())
        if ($surfaceChanged) {
            $view.Host.BackColor = $surfaceBack
            $view.KnobView.BackColor = $surfaceBack
        }

        if ($view.NumberLabel.ForeColor.ToArgb() -ne $palette.Text.ToArgb()) {
            $view.NumberLabel.ForeColor = $palette.Text
        }

        $positionText = [string]$position
        if ($view.PositionLabel.Text -ne $positionText) {
            $view.PositionLabel.Text = $positionText
        }
        if ($view.PositionLabel.ForeColor.ToArgb() -ne $palette.Text.ToArgb()) {
            $view.PositionLabel.ForeColor = $palette.Text
        }

        # The same packet-rate rule applies to the rotary drawing. Only a
        # detent, push transition, theme change or surface change needs paint.
        # This also prevents screenshots from catching the knob during a
        # needless erase/repaint cycle.
        if (
            $surfaceChanged -or
            $null -eq $view.LastPosition -or
            [int64]$view.LastPosition -ne $position -or
            $null -eq $view.LastHasPush -or
            [bool]$view.LastHasPush -ne $hasPush -or
            $null -eq $view.LastPressed -or
            [bool]$view.LastPressed -ne $pressed -or
            [string]$view.LastTheme -ne $themeKey
        ) {
            $view.LastPosition = $position
            $view.LastHasPush = $hasPush
            $view.LastPressed = $pressed
            $view.LastTheme = $themeKey
            $view.KnobView.Invalidate()
        }
    }
}

function Update-AdaptiveInputFeatureUi {
    $metrics = Get-AdaptiveInputStatusLayoutMetrics
    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)
    $hasAnyInput = ($hasButtons -or [bool]$metrics.HasControls)
    $hasTypedSettings = ($script:IsConnected -and ($metrics.ToggleCount -gt 0 -or $metrics.EncoderCount -gt 0))

    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) {
        $script:AdaptiveStateGroup.Visible = $false
    }

    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed) {
        $script:ButtonStateGroup.Visible = $hasAnyInput
        if ($hasButtons -and $metrics.HasControls) {
            $script:ButtonStateGroup.Text = if ($script:Language -eq 'ru') { 'Состояние кнопок и переключателей' } else { 'Buttons and controls' }
        }
        elseif ($hasButtons) { $script:ButtonStateGroup.Text = Get-ButtonFeatureText -Key 'ButtonStatus' }
        else { $script:ButtonStateGroup.Text = Get-AdaptiveInputUiText -Key 'Group' }

        foreach ($control in @($script:ToggleStateLabel, $script:ToggleStateFlow, $script:EncoderStateLabel, $script:EncoderStateFlow)) {
            if ($null -ne $control -and -not $control.IsDisposed -and $control.Parent -ne $script:ButtonStateGroup) {
                $script:ButtonStateGroup.Controls.Add($control)
            }
        }

        if ($null -eq $script:AdaptiveOverflowButton -or $script:AdaptiveOverflowButton.IsDisposed) {
            $script:AdaptiveOverflowButton = New-Object MugenDeejWindowing.MugenButton
            $script:AdaptiveOverflowButton.Tag = 'MugenSection'
            $script:AdaptiveOverflowButton.Size = [System.Drawing.Size]::new(180, 28)
            $script:AdaptiveOverflowButton.Add_Click({ Show-FullControllerStateWindow })
            $script:ButtonStateGroup.Controls.Add($script:AdaptiveOverflowButton)
        }
    }

    if ($null -eq $script:AdaptiveSettingsButton -or $script:AdaptiveSettingsButton.IsDisposed) {
        $script:AdaptiveSettingsButton = New-Object MugenDeejWindowing.MugenButton
        $script:AdaptiveSettingsButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
        $script:AdaptiveSettingsButton.Size = [System.Drawing.Size]::new(196, 42)
        $script:AdaptiveSettingsButton.Add_Click({ Show-AdaptiveControlSettings })
        $form.Controls.Add($script:AdaptiveSettingsButton)
        Apply-ThemeToControl -Control $script:AdaptiveSettingsButton -ThemeName (Get-EffectiveTheme)
    }
    $script:AdaptiveSettingsButton.Text = if ($script:Language -eq 'ru') { 'Тумблеры и энкодеры' } else { 'Toggles & encoders' }
    $script:AdaptiveSettingsButton.Visible = $hasTypedSettings
    $script:AdaptiveSettingsButton.Enabled = $hasTypedSettings

    if ($null -ne $script:ButtonStateFlow -and -not $script:ButtonStateFlow.IsDisposed) { $script:ButtonStateFlow.Visible = $hasButtons }
    if ($null -ne $script:ToggleStateLabel -and -not $script:ToggleStateLabel.IsDisposed) {
        $script:ToggleStateLabel.Text = Get-AdaptiveInputUiText -Key 'Toggles'
        $script:ToggleStateLabel.Visible = ($metrics.ToggleCount -gt 0)
    }

    if (
        ($null -eq $script:LayerStateLabel -or $script:LayerStateLabel.IsDisposed) -and
        $null -ne $script:ButtonStateGroup -and
        -not $script:ButtonStateGroup.IsDisposed
    ) {
        $script:LayerStateLabel = New-Object System.Windows.Forms.Label
        $script:LayerStateLabel.Name = 'AdaptiveLayerStateLabel'
        $script:LayerStateLabel.AutoSize = $false
        $script:LayerStateLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
        $script:LayerStateLabel.Size = [System.Drawing.Size]::new(606, 22)
        $script:ButtonStateGroup.Controls.Add($script:LayerStateLabel)
    }

    if ($null -ne $script:LayerStateLabel -and -not $script:LayerStateLabel.IsDisposed) {
        $layersEnabled = Test-AdaptiveLayersEnabled
        $script:LayerStateLabel.Visible = $layersEnabled
        if ($layersEnabled) {
            $layerName = Get-AdaptiveLayerDisplayName -Layer (Get-AdaptiveLayerIndex)
            $script:LayerStateLabel.Text = if ($script:Language -eq 'ru') {
                'Активный слой: ' + $layerName
            }
            else {
                'Active layer: ' + $layerName
            }
            $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
            $script:LayerStateLabel.ForeColor = $palette.Accent
            $script:LayerStateLabel.BackColor = $script:ButtonStateGroup.BackColor
        }
    }
    if ($null -ne $script:ToggleStateFlow -and -not $script:ToggleStateFlow.IsDisposed) { $script:ToggleStateFlow.Visible = ($metrics.ToggleCount -gt 0) }
    if ($null -ne $script:EncoderStateLabel -and -not $script:EncoderStateLabel.IsDisposed) {
        $script:EncoderStateLabel.Text = Get-AdaptiveInputUiText -Key 'Encoders'
        $script:EncoderStateLabel.Visible = ($metrics.EncoderCount -gt 0)
    }
    if ($null -ne $script:EncoderStateFlow -and -not $script:EncoderStateFlow.IsDisposed) { $script:EncoderStateFlow.Visible = ($metrics.EncoderCount -gt 0) }

    $overflow = if ($script:IsConnected) { Get-MainInputOverflowCount } else { 0 }
    if ($null -ne $script:AdaptiveOverflowButton -and -not $script:AdaptiveOverflowButton.IsDisposed) {
        $script:AdaptiveOverflowButton.Visible = ($overflow -gt 0)
        if ($overflow -gt 0) {
            $script:AdaptiveOverflowButton.Text = if ($script:Language -eq 'ru') { ('Показать все… (+{0})' -f $overflow) } else { ('Show all… (+{0})' -f $overflow) }
        }
    }
}

function Set-MainButtonLayout {
    param([Parameter(Mandatory = $true)][bool]$HasButtons)

    if ($null -eq $form -or $null -eq $startupGroup -or $null -eq $advancedToggle -or $null -eq $advancedPanel -or $null -eq $footer) { return }

    $hasSliders = [bool](Update-SliderCapabilityUi)
    $buttonCount = if ($HasButtons) { [int]$script:DetectedButtonCount } else { 0 }
    $buttonMetrics = Get-AdaptiveButtonLayoutMetrics -Count $buttonCount
    $adaptiveMetrics = Get-AdaptiveInputStatusLayoutMetrics
    $hasAnyInput = ($HasButtons -or [bool]$adaptiveMetrics.HasControls)

    # The status card grows when XInput adds its second row. Start the rest
    # of the main content below the actual card bottom rather than a fixed Y.
    $statusPanelVariable = Get-Variable -Name statusPanel -Scope Script -ErrorAction SilentlyContinue
    $mainY = if (
        $null -ne $statusPanelVariable -and
        $null -ne $statusPanelVariable.Value -and
        -not $statusPanelVariable.Value.IsDisposed
    ) {
        [int]$statusPanelVariable.Value.Bottom + 12
    }
    else {
        160
    }
    if ($hasSliders) {
        $knobGroup.Location = [System.Drawing.Point]::new(24, $mainY)
        $mainY += $knobGroup.Height + 12
    }

    $cursorY = 29
    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed) { $script:ButtonStateGroup.Location = [System.Drawing.Point]::new(24, $mainY) }
    if ($null -ne $script:ButtonStateFlow -and -not $script:ButtonStateFlow.IsDisposed -and $HasButtons) {
        $script:ButtonStateFlow.Location = [System.Drawing.Point]::new(13, $cursorY)
        $script:ButtonStateFlow.Size = [System.Drawing.Size]::new(606, [int]$buttonMetrics.FlowHeight)
        $script:ButtonStateFlow.WrapContents = [bool]$buttonMetrics.Compact
        $script:ButtonStateFlow.AutoScroll = $false
        $cursorY += [int]$buttonMetrics.FlowHeight + 4
    }

    if (
        $null -ne $script:LayerStateLabel -and
        -not $script:LayerStateLabel.IsDisposed -and
        (Test-AdaptiveLayersEnabled)
    ) {
        $script:LayerStateLabel.Location = [System.Drawing.Point]::new(13, ($cursorY + 1))
        $script:LayerStateLabel.Size = [System.Drawing.Size]::new(606, 22)
        $cursorY += 24
    }

    if ($adaptiveMetrics.HasControls) {
        $shareTypedRow = ($adaptiveMetrics.VisibleToggleCount -gt 0 -and $adaptiveMetrics.VisibleEncoderCount -gt 0 -and $adaptiveMetrics.VisibleToggleCount -le 2 -and $adaptiveMetrics.VisibleEncoderCount -le 2)
        if ($shareTypedRow) {
            $typedY = $cursorY
            $script:ToggleStateLabel.Location = [System.Drawing.Point]::new(13, ($typedY + 3))
            $script:ToggleStateLabel.Size = [System.Drawing.Size]::new(82, 24)
            $script:ToggleStateFlow.Location = [System.Drawing.Point]::new(96, $typedY)
            $script:ToggleStateFlow.Size = [System.Drawing.Size]::new(198, [int]$adaptiveMetrics.ToggleHeight)
            $script:EncoderStateLabel.Location = [System.Drawing.Point]::new(310, ($typedY + 3))
            $script:EncoderStateLabel.Size = [System.Drawing.Size]::new(84, 24)
            $script:EncoderStateFlow.Location = [System.Drawing.Point]::new(398, $typedY)
            $script:EncoderStateFlow.Size = [System.Drawing.Size]::new(221, [int]$adaptiveMetrics.EncoderHeight)
            $cursorY += [Math]::Max([int]$adaptiveMetrics.ToggleHeight, [int]$adaptiveMetrics.EncoderHeight)
        }
        else {
            if ($adaptiveMetrics.VisibleToggleCount -gt 0) {
                $script:ToggleStateLabel.Location = [System.Drawing.Point]::new(13, ($cursorY + 2))
                $script:ToggleStateLabel.Size = [System.Drawing.Size]::new(82, 24)
                $script:ToggleStateFlow.Location = [System.Drawing.Point]::new(100, $cursorY)
                $script:ToggleStateFlow.Size = [System.Drawing.Size]::new(519, [int]$adaptiveMetrics.ToggleHeight)
                $cursorY += [int]$adaptiveMetrics.ToggleHeight
            }
            if ($adaptiveMetrics.VisibleEncoderCount -gt 0) {
                if ($adaptiveMetrics.VisibleToggleCount -gt 0) { $cursorY += [int]$adaptiveMetrics.SectionGap }
                $script:EncoderStateLabel.Location = [System.Drawing.Point]::new(13, ($cursorY + 3))
                $script:EncoderStateLabel.Size = [System.Drawing.Size]::new(82, 24)
                $script:EncoderStateFlow.Location = [System.Drawing.Point]::new(100, $cursorY)
                $script:EncoderStateFlow.Size = [System.Drawing.Size]::new(519, [int]$adaptiveMetrics.EncoderHeight)
                $cursorY += [int]$adaptiveMetrics.EncoderHeight
            }
        }
    }

    $overflow = if ($script:IsConnected) { Get-MainInputOverflowCount } else { 0 }
    if ($overflow -gt 0 -and $null -ne $script:AdaptiveOverflowButton) {
        $script:AdaptiveOverflowButton.Location = [System.Drawing.Point]::new(13, ($cursorY + 3))
        $cursorY += 34
    }

    $inputGroupHeight = if ($hasAnyInput) { [Math]::Max(72, ($cursorY + 8)) } else { 0 }
    if ($null -ne $script:ButtonStateGroup -and -not $script:ButtonStateGroup.IsDisposed -and $hasAnyInput) {
        $script:ButtonStateGroup.Size = [System.Drawing.Size]::new(632, $inputGroupHeight)
        $mainY += $inputGroupHeight + 12
    }

    if ($null -ne $script:AdaptiveStateGroup -and -not $script:AdaptiveStateGroup.IsDisposed) { $script:AdaptiveStateGroup.Visible = $false }
    $advancedPanel.Visible = $false

    $settingsControls = @()
    if ($hasSliders) { $settingsControls += $settingsButton }
    if ($null -ne $script:ButtonSettingsButton -and $script:ButtonSettingsButton.Visible) { $settingsControls += $script:ButtonSettingsButton }
    if ($null -ne $script:AdaptiveSettingsButton -and $script:AdaptiveSettingsButton.Visible) { $settingsControls += $script:AdaptiveSettingsButton }

    if ($settingsControls.Count -gt 0) {
        if ($settingsControls.Count -eq 1) {
            $settingsControls[0].Location = [System.Drawing.Point]::new(24, $mainY)
            $settingsControls[0].Size = [System.Drawing.Size]::new(230, 42)
        }
        elseif ($settingsControls.Count -eq 2) {
            for ($i = 0; $i -lt 2; $i++) {
                $settingsControls[$i].Location = [System.Drawing.Point]::new((24 + ($i * 248)), $mainY)
                $settingsControls[$i].Size = [System.Drawing.Size]::new(230, 42)
            }
        }
        else {
            for ($i = 0; $i -lt 3; $i++) {
                $settingsControls[$i].Location = [System.Drawing.Point]::new((24 + ($i * 204)), $mainY)
                $settingsControls[$i].Size = [System.Drawing.Size]::new(196, 42)
            }
        }

        if ($null -ne $script:SettingsHintControl) {
            $showHint = ($settingsControls.Count -eq 1 -and $hasSliders)
            $script:SettingsHintControl.Visible = $showHint
            if ($showHint) { $script:SettingsHintControl.Location = [System.Drawing.Point]::new(272, ($mainY - 2)) }
        }
        $mainY += 54
    }
    elseif ($null -ne $script:SettingsHintControl) { $script:SettingsHintControl.Visible = $false }

    $startupGroup.Location = [System.Drawing.Point]::new(24, $mainY)
    $mainY += 102
    $advancedToggle.Location = [System.Drawing.Point]::new(24, $mainY)
    if ($null -ne $script:BackupMenuButton -and -not $script:BackupMenuButton.IsDisposed) { $script:BackupMenuButton.Location = [System.Drawing.Point]::new(292, $mainY) }
    $mainY += 52

    $collapsedHeight = $mainY + 24
    $windowHeight = $collapsedHeight + 39
    $form.MinimumSize = [System.Drawing.Size]::new(696, $windowHeight)
    $form.MaximumSize = [System.Drawing.Size]::new(696, $windowHeight)
    $form.ClientSize = [System.Drawing.Size]::new(680, $collapsedHeight)
    $footer.Location = [System.Drawing.Point]::new(24, ($form.ClientSize.Height - 28))
}
function Update-ButtonFeatureUi {
    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)

    if ($null -ne $script:ButtonSettingsButton -and -not $script:ButtonSettingsButton.IsDisposed) {
        $script:ButtonSettingsButton.Text = if ($script:Language -eq 'ru') { 'Кнопки' } else { 'Buttons' }
        $script:ButtonSettingsButton.Visible = $hasButtons
        $script:ButtonSettingsButton.Enabled = $hasButtons
    }

    $script:LastButtonUiVisible = $hasButtons
    Update-AdaptiveInputFeatureUi
    Set-MainButtonLayout -HasButtons $hasButtons

    if ($hasButtons) { Update-MainButtonIndicators }
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

function Test-MugenInputActionsSuspended {
    try {
        foreach ($openForm in @([System.Windows.Forms.Application]::OpenForms)) {
            if (
                $null -ne $openForm -and
                -not $openForm.IsDisposed -and
                $openForm.Modal
            ) {
                return $true
            }
        }
    }
    catch {}

    return $false
}

function Invoke-ButtonAction {
    param([Parameter(Mandatory = $true)][int]$ButtonIndex)

    if (Test-MugenInputActionsSuspended) {
        Write-Log ('Button {0} mapped action suppressed while a modal Mugen dialog is open' -f ($ButtonIndex + 1)) 'DEBUG'
        return
    }

    Initialize-ButtonActions

    if ($ButtonIndex -lt 0) { return }
    $action = Get-ProfiledButtonAction -ButtonIndex $ButtonIndex

    # Virtual Xbox mappings are stateful and were already submitted from the
    # complete physical-button frame before edge dispatch. Do not run them
    # through the legacy one-shot 80 ms debounce or its synchronous log path.
    if (
        $script:VirtualGamepadFeatureAvailable -and
        (Test-MugenVirtualGamepadAction -Action $action)
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

    # Foreground-profile button action was resolved before debounce handling.

    if (
        [string]::IsNullOrWhiteSpace($action) -or
        $action -eq 'none'
    ) {
        return
    }

    if (
        $script:VirtualGamepadFeatureAvailable -and
        (Test-MugenVirtualGamepadAction -Action $action)
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
function Get-MugenVirtualGamepadActionDisplay {
    param([string]$Action)

    foreach ($definition in @(Get-MugenVirtualGamepadActionDefinitions)) {
        if ([string]$definition.Action -eq [string]$Action) {
            return [string]$definition.Display
        }
    }

    return $(if ($script:Language -eq 'ru') { 'Геймпад' } else { 'Gamepad' })
}

function Show-MugenVirtualGamepadButtonPicker {
    param(
        [string]$ExistingAction,
        [System.Windows.Forms.IWin32Window]$Owner
    )

    $picker = New-Object System.Windows.Forms.Form
    $picker.Text = $(if ($script:Language -eq 'ru') { 'Настройка виртуального геймпада Xbox' } else { 'Virtual Xbox gamepad' })
    $picker.StartPosition = 'CenterParent'
    $picker.ClientSize = [System.Drawing.Size]::new(760, 625)
    $picker.MinimumSize = [System.Drawing.Size]::new(776, 664)
    $picker.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $picker.FormBorderStyle = 'FixedDialog'
    $picker.MaximizeBox = $false
    $picker.MinimizeBox = $false
    $picker.Tag = $null
    Set-FormAppIcon -Form $picker

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = $(if ($script:Language -eq 'ru') { 'Выберите элемент виртуального геймпада Xbox' } else { 'Choose a virtual Xbox gamepad control' })
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(24, 18)
    $picker.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = $(if ($script:Language -eq 'ru') { 'Выберите, что будет делать эта кнопка на виртуальном геймпаде Xbox.' + "`r`n" + 'Для LT и RT кнопка работает как полное нажатие.' } else { 'Choose what this button does on the virtual Xbox gamepad.' + "`r`n" + 'LT and RT act as a full trigger press.' })
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(27, 53)
    $hint.Size = [System.Drawing.Size]::new(706, 42)
    $picker.Controls.Add($hint)

    # Spatial Xbox-style control map: shoulders at the top, left stick / D-pad
    # on the left, ABXY / right stick on the right, View/Menu in the middle.
    $choices = @(
        @('LT',          'virtual:xbox:lt',         38, 108, 132, 36),
        @('LB',          'virtual:xbox:lb',         38, 150, 132, 36),
        @('RT',          'virtual:xbox:rt',        590, 108, 132, 36),
        @('RB',          'virtual:xbox:rb',        590, 150, 132, 36),

        @('View',        'virtual:xbox:back',      278, 150,  96, 38),
        @('Menu',        'virtual:xbox:start',     386, 150,  96, 38),

        @('↑',           'virtual:xbox:lsy:up',    154, 236,  52, 36),
        @('←',           'virtual:xbox:lsx:left',   96, 278,  52, 36),
        @('L3',          'virtual:xbox:l3',        154, 278,  52, 36),
        @('→',           'virtual:xbox:lsx:right', 212, 278,  52, 36),
        @('↓',           'virtual:xbox:lsy:down',  154, 320,  52, 36),

        @('Y',           'virtual:xbox:y',         604, 236,  52, 36),
        @('X',           'virtual:xbox:x',         546, 278,  52, 36),
        @('B',           'virtual:xbox:b',         662, 278,  52, 36),
        @('A',           'virtual:xbox:a',         604, 320,  52, 36),

        @('↑',           'virtual:xbox:dpad:up',   154, 416,  52, 36),
        @('←',           'virtual:xbox:dpad:left',  96, 458,  52, 36),
        @('→',           'virtual:xbox:dpad:right',212, 458,  52, 36),
        @('↓',           'virtual:xbox:dpad:down', 154, 500,  52, 36),

        @('↑',           'virtual:xbox:rsy:up',    604, 416,  52, 36),
        @('←',           'virtual:xbox:rsx:left',  546, 458,  52, 36),
        @('R3',          'virtual:xbox:r3',        604, 458,  52, 36),
        @('→',           'virtual:xbox:rsx:right', 662, 458,  52, 36),
        @('↓',           'virtual:xbox:rsy:down',  604, 500,  52, 36)
    )

    $leftStickLabel = New-Object System.Windows.Forms.Label
    $leftStickLabel.Text = $(if ($script:Language -eq 'ru') { 'Левый стик' } else { 'Left stick' })
    $leftStickLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $leftStickLabel.Location = [System.Drawing.Point]::new(96, 205)
    $leftStickLabel.Size = [System.Drawing.Size]::new(168, 24)
    $leftStickLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($leftStickLabel)

    $faceLabel = New-Object System.Windows.Forms.Label
    $faceLabel.Text = $(if ($script:Language -eq 'ru') { 'Основные кнопки' } else { 'Face buttons' })
    $faceLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $faceLabel.Location = [System.Drawing.Point]::new(546, 205)
    $faceLabel.Size = [System.Drawing.Size]::new(168, 24)
    $faceLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($faceLabel)

    $dpadLabel = New-Object System.Windows.Forms.Label
    $dpadLabel.Text = $(if ($script:Language -eq 'ru') { 'Крестовина' } else { 'D-pad' })
    $dpadLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $dpadLabel.Location = [System.Drawing.Point]::new(96, 385)
    $dpadLabel.Size = [System.Drawing.Size]::new(168, 24)
    $dpadLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($dpadLabel)

    $rightStickLabel = New-Object System.Windows.Forms.Label
    $rightStickLabel.Text = $(if ($script:Language -eq 'ru') { 'Правый стик' } else { 'Right stick' })
    $rightStickLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $rightStickLabel.Location = [System.Drawing.Point]::new(546, 385)
    $rightStickLabel.Size = [System.Drawing.Size]::new(168, 24)
    $rightStickLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($rightStickLabel)

    # A small non-clickable hub makes the D-pad read as a cross rather than a
    # loose set of four arrows.
    $dpadHub = New-Object System.Windows.Forms.Label
    $dpadHub.Text = '✚'
    $dpadHub.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 16)
    $dpadHub.ForeColor = [System.Drawing.Color]::DimGray
    $dpadHub.Location = [System.Drawing.Point]::new(154, 458)
    $dpadHub.Size = [System.Drawing.Size]::new(52, 36)
    $dpadHub.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($dpadHub)

    foreach ($choice in $choices) {
        $choiceButton = New-Object MugenDeejWindowing.MugenButton
        $choiceButton.Text = [string]$choice[0]
        if ([string]$choice[1] -eq [string]$ExistingAction) {
            $choiceButton.Text = '● ' + [string]$choice[0]
        }
        $choiceButton.Tag = [string]$choice[1]
        $choiceButton.Location = [System.Drawing.Point]::new([int]$choice[2], [int]$choice[3])
        $choiceButton.Size = [System.Drawing.Size]::new([int]$choice[4], [int]$choice[5])
        $choiceButton.Add_Click({
            param($sender, $eventArgs)
            $hostForm = $sender.FindForm()
            $hostForm.Tag = [string]$sender.Tag
            $hostForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $hostForm.Close()
        })
        $picker.Controls.Add($choiceButton)
    }

    # Keep the decorative D-pad hub above the surrounding clickable arrows.
    $dpadHub.BringToFront()

    $axisHint = New-Object System.Windows.Forms.Label
    $axisHint.Text = $(if ($script:Language -eq 'ru') { 'Если нажать противоположные направления одновременно, стик вернётся в центр.' } else { 'Pressing opposite directions at the same time returns the stick to center.' })
    $axisHint.ForeColor = [System.Drawing.Color]::DimGray
    $axisHint.Location = [System.Drawing.Point]::new(278, 425)
    $axisHint.Size = [System.Drawing.Size]::new(204, 72)
    $axisHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $picker.Controls.Add($axisHint)

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = $(if ($script:Language -eq 'ru') { 'Отмена' } else { 'Cancel' })
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(628, 568)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $picker.Controls.Add($cancel)
    $picker.CancelButton = $cancel

    Apply-ThemeToForm -Form $picker

    $picker.Add_Shown({
        Ensure-FormVisible -Form $picker -CenterIfOffscreen
    })

    $result = $picker.ShowDialog($Owner)
    $selectedAction = $null
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedAction = [string]$picker.Tag
    }

    $picker.Dispose()
    return $selectedAction
}

function Get-LargeButtonActionDisplay {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'none') {
        return (Get-ButtonFeatureText -Key 'None')
    }

    if (
        $script:VirtualGamepadFeatureAvailable -and
        (Test-MugenVirtualGamepadAction -Action $Action)
    ) {
        return (Get-MugenVirtualGamepadActionDisplay -Action $Action)
    }

    if ($Action -match '^mute:(\d+)$') {
        $sliderIndex = [int]$Matches[1]
        $sliderName = if ($sliderIndex -lt @($script:Config.sliders).Count) {
            [string]$script:Config.sliders[$sliderIndex].name
        }
        else {
            [string]($sliderIndex + 1)
        }
        if ([string]::IsNullOrWhiteSpace($sliderName)) {
            $sliderName = [string]($sliderIndex + 1)
        }
        return (
            (Get-ButtonFeatureText -Key 'MuteControl') +
            ' ' + ($sliderIndex + 1) + ' — ' + $sliderName
        )
    }

    $fixedDisplay = @{
        'media:playpause' = (Get-ButtonFeatureText -Key 'PlayPause')
        'media:previous' = (Get-ButtonFeatureText -Key 'PreviousTrack')
        'media:next' = (Get-ButtonFeatureText -Key 'NextTrack')
        'media:stop' = (Get-ButtonFeatureText -Key 'StopPlayback')
        'system:volumeup' = (Get-ButtonFeatureText -Key 'VolumeUp')
        'system:volumedown' = (Get-ButtonFeatureText -Key 'VolumeDown')
        'system:volumemute' = (Get-ButtonFeatureText -Key 'VolumeMute')
    }
    if ($fixedDisplay.ContainsKey($Action)) {
        return [string]$fixedDisplay[$Action]
    }

    if ($Action -match '^hotkey:') { return (Get-HotkeyActionDisplay -Action $Action) }
    if ($Action -match '^launch64:') { return (Get-LaunchActionDisplay -Action $Action) }
    if ($Action -match '^folder64:') { return (Get-FolderActionDisplay -Action $Action) }
    if ($Action -match '^command64:') { return (Get-CommandActionDisplay -Action $Action) }
    if ($Action -match '^url64:') { return (Get-UrlActionDisplay -Action $Action) }

    return $Action
}

function Show-LargeButtonSettings {
    # Application profiles belong to the PC-side button mapping layer, not to
    # a firmware generation. Legacy simply has zero buttons; Extended and
    # Adaptive can both use the same Global/per-application editor.
    $profileUiEnabled = (
        $script:IsConnected -and
        [int]$script:DetectedButtonCount -gt 0
    )
    if (-not $profileUiEnabled) { return }

    $buildStarted = Get-Date
    Normalize-ButtonActions -Count $script:DetectedButtonCount
    Initialize-AdaptiveActions
    Initialize-AdaptiveProfiles

    $pendingActions = New-Object System.Collections.ArrayList
    foreach ($action in @($script:ButtonActions)) {
        [void]$pendingActions.Add([string]$action)
    }

    $workingProfiles = New-Object System.Collections.ArrayList
    foreach ($profile in @($script:AdaptiveProfiles)) {
        $buttons = @()
        if ($null -ne $profile.PSObject.Properties['buttons']) {
            $buttons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
        }
        [void]$workingProfiles.Add([pscustomobject][ordered]@{
            name = [string]$profile.name
            process = [string]$profile.process
            buttons = @($buttons)
            toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
            encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
        })
    }

    $profileDrafts = @{}
    $profileState = [pscustomobject]@{
        Process = ''
        Suppress = $false
        Map = New-Object System.Collections.ArrayList
    }

    $buttonForm = New-Object System.Windows.Forms.Form
    $buttonForm.Text = Get-ButtonFeatureText -Key 'Title'
    $buttonForm.StartPosition = 'CenterParent'
    $dialogClientHeight = if ($profileUiEnabled) { 704 } else { 620 }
    $dialogOuterHeight = if ($profileUiEnabled) { 743 } else { 659 }
    $buttonForm.ClientSize = [System.Drawing.Size]::new(760, $dialogClientHeight)
    $buttonForm.MinimumSize = [System.Drawing.Size]::new(776, $dialogOuterHeight)
    $buttonForm.MaximumSize = [System.Drawing.Size]::new(776, $dialogOuterHeight)
    $buttonForm.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $buttonForm.FormBorderStyle = 'FixedDialog'
    $buttonForm.MaximizeBox = $false
    $buttonForm.MinimizeBox = $false
    Set-FormAppIcon -Form $buttonForm

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-ButtonFeatureText -Key 'Heading'
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $buttonForm.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = if ($script:Language -eq 'ru') {
        'Выберите кнопку в сетке или нажмите её на контроллере — она выберется здесь автоматически.' + "`r`n" + 'Справа настраивается только выбранная кнопка, а список ниже показывает все назначения.'
    }
    else {
        'Choose a button in the grid or press it on the controller — it will be selected here automatically.' + "`r`n" + 'Only the selected button is edited on the right; the list below shows all assignments.'
    }
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(710, 43)
    $buttonForm.Controls.Add($hint)

    $saveNotice = New-Object System.Windows.Forms.Label
    $saveNotice.Text = if ($script:Language -eq 'ru') {
        'Важно: изменения начнут работать только после нажатия «Сохранить».'
    }
    else {
        'Important: changes take effect only after you click Save.'
    }
    $saveNotice.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    $saveNotice.Location = [System.Drawing.Point]::new(25, 101)
    $saveNotice.Size = [System.Drawing.Size]::new(710, 27)
    $buttonForm.Controls.Add($saveNotice)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = if ($script:Language -eq 'ru') { 'Профиль:' } else { 'Profile:' }
    $profileLabel.Location = [System.Drawing.Point]::new(25, 139)
    $profileLabel.Size = [System.Drawing.Size]::new(145, 30)
    $profileLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $profileLabel.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($profileLabel)

    $profileCombo = New-Object MugenDeejWindowing.MugenComboBox
    $profileCombo.DropDownStyle = 'DropDownList'
    $profileCombo.Location = [System.Drawing.Point]::new(170, 134)
    $profileCombo.Size = [System.Drawing.Size]::new(350, 30)
    $profileCombo.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($profileCombo)

    $addProfileButton = New-Object MugenDeejWindowing.MugenButton
    $addProfileButton.Text = if ($script:Language -eq 'ru') { 'Добавить…' } else { 'Add…' }
    $addProfileButton.Location = [System.Drawing.Point]::new(532, 133)
    $addProfileButton.Size = [System.Drawing.Size]::new(203, 32)
    $addProfileButton.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($addProfileButton)

    $profileHint = New-Object System.Windows.Forms.Label
    $profileHint.Text = if ($script:Language -eq 'ru') {
        'Общий профиль работает везде; профиль приложения включается автоматически, когда это приложение активно.'
    }
    else {
        'Global works everywhere; an application profile is selected automatically while that app is active.'
    }
    $profileHint.ForeColor = [System.Drawing.Color]::DimGray
    $profileHint.Location = [System.Drawing.Point]::new(25, 170)
    $profileHint.Size = [System.Drawing.Size]::new(710, 42)
    $profileHint.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($profileHint)

    # Virtual-controller power now lives on the main window. Button settings
    # only describe mappings, so the editor starts immediately after profiles.
    $actionButtonY = if ($profileUiEnabled) { 650 } else { 570 }

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = [System.Drawing.Point]::new(22, $(if ($profileUiEnabled) { 218 } else { 139 }))
    $panel.Size = [System.Drawing.Size]::new(716, $(if ($profileUiEnabled) { 404 } else { 427 }))
    $panel.AutoScroll = $false
    $buttonForm.Controls.Add($panel)

    $selectorFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $selectorFlow.Location = [System.Drawing.Point]::new(8, 8)
    $selectorFlow.Size = [System.Drawing.Size]::new(254, $(if ($profileUiEnabled) { 386 } else { 409 }))
    $selectorFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $selectorFlow.WrapContents = $true
    $selectorFlow.AutoScroll = $true
    $panel.Controls.Add($selectorFlow)

    $selectedHeading = New-Object System.Windows.Forms.Label
    $selectedHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $selectedHeading.Location = [System.Drawing.Point]::new(282, 10)
    $selectedHeading.Size = [System.Drawing.Size]::new(420, 27)
    $panel.Controls.Add($selectedHeading)

    $selectedHint = New-Object System.Windows.Forms.Label
    $selectedHint.Text = if ($script:Language -eq 'ru') {
        'Нажмите кнопку на контроллере — Mugen выберет её автоматически.'
    }
    else {
        'Press a button on the controller and Mugen will select it automatically.'
    }
    $selectedHint.ForeColor = [System.Drawing.Color]::DimGray
    $selectedHint.Location = [System.Drawing.Point]::new(282, 39)
    $selectedHint.Size = [System.Drawing.Size]::new(420, 37)
    $panel.Controls.Add($selectedHint)

    $actionCombo = New-Object MugenDeejWindowing.MugenComboBox
    $actionCombo.DropDownStyle = 'DropDownList'
    $actionCombo.Location = [System.Drawing.Point]::new(282, 82)
    $actionCombo.Size = [System.Drawing.Size]::new(420, 30)
    $panel.Controls.Add($actionCombo)

    $assignmentsLabel = New-Object System.Windows.Forms.Label
    $assignmentsLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $assignmentsLabel.Location = [System.Drawing.Point]::new(282, 127)
    $assignmentsLabel.Size = [System.Drawing.Size]::new(235, 25)
    $panel.Controls.Add($assignmentsLabel)

    $filterCombo = New-Object MugenDeejWindowing.MugenComboBox
    $filterCombo.DropDownStyle = 'DropDownList'
    $filterCombo.Location = [System.Drawing.Point]::new(524, 123)
    $filterCombo.Size = [System.Drawing.Size]::new(178, 29)
    [void]$filterCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Назначенные' } else { 'Assigned' }))
    [void]$filterCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Все кнопки' } else { 'All buttons' }))
    $filterCombo.SelectedIndex = 0
    $panel.Controls.Add($filterCombo)

    $assignmentList = New-Object System.Windows.Forms.ListView
    $assignmentList.Location = [System.Drawing.Point]::new(282, 158)
    $assignmentList.Size = [System.Drawing.Size]::new(420, $(if ($profileUiEnabled) { 236 } else { 259 }))
    $assignmentList.View = [System.Windows.Forms.View]::Details
    $assignmentList.FullRowSelect = $true
    $assignmentList.HideSelection = $false
    $assignmentList.MultiSelect = $false
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Кнопка' } else { 'Button' }), 72)
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Действие' } else { 'Action' }), 320)
    $panel.Controls.Add($assignmentList)

    $selectors = @()
    for ($i = 0; $i -lt $script:DetectedButtonCount; $i++) {
        $selector = New-Object MugenDeejWindowing.MugenButtonTile
        $selector.Text = [string]($i + 1)
        $selector.Tag = $i
        $selector.Size = [System.Drawing.Size]::new(42, 28)
        $selector.Margin = New-Object System.Windows.Forms.Padding(3, 2, 3, 2)
        $selector.TextAlign = 'MiddleCenter'
        $selector.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
        $selectorFlow.Controls.Add($selector)
        $selectors += $selector
    }

    $buttonEditorState = [pscustomobject]@{
        Selected = 0
        LastButtons = @($script:LatestButtons)
        ActionMap = New-Object System.Collections.ArrayList
        SuppressCombo = $false
        SuppressListSelection = $false
    }

    $sliderCount = [Math]::Min(
        [int]$script:DetectedSliderCount,
        [int]$script:Config.sliders.Count
    )

    $getProfileDraftKey = {
        param([string]$ProcessName)
        $normalized = Normalize-TargetName -Value $ProcessName
        if ([string]::IsNullOrWhiteSpace($normalized)) { return '__global__' }
        return $normalized.ToLowerInvariant()
    }

    $findWorkingProfile = {
        param([string]$ProcessName)
        $normalized = Normalize-TargetName -Value $ProcessName
        if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }
        foreach ($profile in @($workingProfiles)) {
            if ((Normalize-TargetName -Value ([string]$profile.process)) -ieq $normalized) { return $profile }
        }
        return $null
    }

    $captureCurrentProfileDraft = {
        if (-not $profileUiEnabled) { return }
        $key = & $getProfileDraftKey ([string]$profileState.Process)
        $profileDrafts[$key] = [pscustomobject][ordered]@{
            buttons = @(Copy-AdaptiveProfileButtons -Items @($pendingActions))
        }
    }

    $loadProfileDraft = {
        param([string]$ProcessName)
        if (-not $profileUiEnabled) { return }

        $normalized = Normalize-TargetName -Value $ProcessName
        $key = & $getProfileDraftKey $normalized
        $draft = $null

        if ($profileDrafts.ContainsKey($key)) {
            $draft = $profileDrafts[$key]
        }
        elseif ([string]::IsNullOrWhiteSpace($normalized)) {
            $draft = [pscustomobject][ordered]@{
                buttons = @(Copy-AdaptiveProfileButtons -Items @($script:ButtonActions))
            }
            $profileDrafts[$key] = $draft
        }
        else {
            $profile = & $findWorkingProfile $normalized
            if ($null -eq $profile) { return }

            $buttons = @()
            if ($null -ne $profile.PSObject.Properties['buttons']) {
                $buttons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
            }

            # Profiles created by #89 predate button mappings. They inherit the
            # current Global draft until this dialog explicitly saves buttons.
            if ($buttons.Count -eq 0) {
                if (-not $profileDrafts.ContainsKey('__global__')) {
                    $profileDrafts['__global__'] = [pscustomobject][ordered]@{
                        buttons = @(Copy-AdaptiveProfileButtons -Items @($script:ButtonActions))
                    }
                }
                $buttons = @(Copy-AdaptiveProfileButtons -Items @($profileDrafts['__global__'].buttons))
            }

            $draft = [pscustomobject][ordered]@{ buttons = @($buttons) }
            $profileDrafts[$key] = $draft
        }

        $pendingActions.Clear()
        foreach ($action in @($draft.buttons)) {
            [void]$pendingActions.Add((ConvertTo-SafeProfileButtonAction -Action ([string]$action)))
        }
        while ($pendingActions.Count -lt [int]$script:DetectedButtonCount) {
            [void]$pendingActions.Add('none')
        }

        $profileState.Process = $normalized
        if ([int]$buttonEditorState.Selected -ge $pendingActions.Count) { $buttonEditorState.Selected = 0 }
    }

    $populateProfileCombo = {
        param([string]$SelectProcess = '')
        if (-not $profileUiEnabled) { return }

        $selectedNormalized = Normalize-TargetName -Value $SelectProcess
        $profileState.Suppress = $true
        try {
            $profileCombo.BeginUpdate()
            try {
                $profileCombo.Items.Clear()
                $profileState.Map.Clear()

                [void]$profileCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Общий — для всех остальных приложений' } else { 'Global — all other applications' }))
                [void]$profileState.Map.Add('')

                foreach ($profile in @($workingProfiles | Sort-Object name)) {
                    $processName = Normalize-TargetName -Value ([string]$profile.process)
                    [void]$profileCombo.Items.Add(('{0}  ({1}.exe)' -f [string]$profile.name, $processName))
                    [void]$profileState.Map.Add($processName)
                }

                $selectedIndex = 0
                for ($i = 0; $i -lt $profileState.Map.Count; $i++) {
                    if ([string]$profileState.Map[$i] -ieq $selectedNormalized) {
                        $selectedIndex = $i
                        break
                    }
                }
                $profileCombo.SelectedIndex = $selectedIndex
            }
            finally {
                $profileCombo.EndUpdate()
            }
        }
        finally {
            $profileState.Suppress = $false
        }
    }

    $showAddProfileDialog = {
        if (-not $profileUiEnabled) { return '' }

        $existing = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($profile in @($workingProfiles)) {
            $name = Normalize-TargetName -Value ([string]$profile.process)
            if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$existing.Add($name) }
        }

        $runningProcesses = @(
            Get-RunningApplicationProcessNames |
            Where-Object { -not $existing.Contains((Normalize-TargetName -Value ([string]$_))) } |
            Sort-Object { Get-FriendlyProcessName -ProcessName $_ }
        )

        if ($runningProcesses.Count -eq 0) {
            [void](Show-MugenDeejStyledDialog -Message ($(if ($script:Language -eq 'ru') {
                'Не нашлось запущенного приложения без профиля. Запустите нужную программу и попробуйте снова.'
            } else {
                'No running application without a profile was found. Start the app you want and try again.'
            })) -Buttons 'OK' -Kind 'Info')
            return ''
        }

        $picker = New-Object System.Windows.Forms.Form
        $picker.Text = if ($script:Language -eq 'ru') { 'Добавить профиль приложения — Mugen Deej' } else { 'Add application profile — Mugen Deej' }
        $picker.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
        $picker.ClientSize = [System.Drawing.Size]::new(560, 220)
        $picker.MinimumSize = [System.Drawing.Size]::new(576, 259)
        $picker.MaximumSize = [System.Drawing.Size]::new(576, 259)
        $picker.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $picker.MaximizeBox = $false
        $picker.MinimizeBox = $false
        $picker.ShowInTaskbar = $false
        $picker.Font = $buttonForm.Font
        Set-FormAppIcon -Form $picker

        $pickerHeading = New-Object System.Windows.Forms.Label
        $pickerHeading.Text = if ($script:Language -eq 'ru') { 'Для какого приложения создать профиль?' } else { 'Which application should have its own profile?' }
        $pickerHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
        $pickerHeading.AutoSize = $true
        $pickerHeading.Location = [System.Drawing.Point]::new(20, 18)
        $picker.Controls.Add($pickerHeading)

        $pickerHint = New-Object System.Windows.Forms.Label
        $pickerHint.Text = if ($script:Language -eq 'ru') {
            'Новый профиль получит копию текущих назначений Общего профиля.'
        }
        else {
            'The new profile will start with a copy of the current Global mappings.'
        }
        $pickerHint.ForeColor = [System.Drawing.Color]::DimGray
        $pickerHint.Location = [System.Drawing.Point]::new(22, 52)
        $pickerHint.Size = [System.Drawing.Size]::new(516, 30)
        $picker.Controls.Add($pickerHint)

        $pickerCombo = New-Object MugenDeejWindowing.MugenComboBox
        $pickerCombo.DropDownStyle = 'DropDownList'
        $pickerCombo.Location = [System.Drawing.Point]::new(22, 92)
        $pickerCombo.Size = [System.Drawing.Size]::new(516, 30)
        foreach ($processName in $runningProcesses) {
            [void]$pickerCombo.Items.Add(('{0}  ({1}.exe)' -f (Get-FriendlyProcessName -ProcessName $processName), $processName))
        }
        $pickerCombo.SelectedIndex = 0
        $picker.Controls.Add($pickerCombo)

        $pickerCancel = New-Object MugenDeejWindowing.MugenButton
        $pickerCancel.Text = Get-ButtonFeatureText -Key 'Cancel'
        $pickerCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $pickerCancel.Location = [System.Drawing.Point]::new(330, 164)
        $pickerCancel.Size = [System.Drawing.Size]::new(100, 36)
        $picker.Controls.Add($pickerCancel)

        $pickerAdd = New-Object MugenDeejWindowing.MugenButton
        $pickerAdd.Text = if ($script:Language -eq 'ru') { 'Создать' } else { 'Create' }
        $pickerAdd.Tag = 'MugenPrimary'
        $pickerAdd.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $pickerAdd.Location = [System.Drawing.Point]::new(438, 164)
        $pickerAdd.Size = [System.Drawing.Size]::new(100, 36)
        $picker.Controls.Add($pickerAdd)

        Apply-ThemeToForm -Form $picker -ThemeName (Get-EffectiveTheme)
        $picker.Add_Shown({ Ensure-FormVisible -Form $picker -CenterIfOffscreen })
        $picker.AcceptButton = $pickerAdd
        $picker.CancelButton = $pickerCancel

        $result = $picker.ShowDialog($buttonForm)
        $chosen = if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            [string]$runningProcesses[[int]$pickerCombo.SelectedIndex]
        }
        else {
            ''
        }
        $picker.Dispose()
        return (Normalize-TargetName -Value $chosen)
    }

    if ($profileUiEnabled) {
        & $captureCurrentProfileDraft
        & $populateProfileCombo ''
        & $loadProfileDraft ''
    }

    $refreshAssignmentList = {
        $assignmentList.BeginUpdate()
        try {
            $assignmentList.Items.Clear()
            $assignedCount = 0
            for ($i = 0; $i -lt $pendingActions.Count; $i++) {
                $action = [string]$pendingActions[$i]
                $assigned = (-not [string]::IsNullOrWhiteSpace($action) -and $action -ne 'none')
                if ($assigned) { $assignedCount++ }
                if ($filterCombo.SelectedIndex -eq 0 -and -not $assigned) { continue }

                $item = New-Object System.Windows.Forms.ListViewItem([string]($i + 1))
                [void]$item.SubItems.Add((Get-LargeButtonActionDisplay -Action $action))
                $item.Tag = $i
                [void]$assignmentList.Items.Add($item)
            }
            $assignmentsLabel.Text = if ($script:Language -eq 'ru') {
                'Назначено: {0} из {1}' -f $assignedCount, $pendingActions.Count
            }
            else {
                'Assigned: {0} of {1}' -f $assignedCount, $pendingActions.Count
            }
        }
        finally {
            $assignmentList.EndUpdate()
        }
    }

    $populateActionCombo = {
        $index = [int]$buttonEditorState.Selected
        if ($index -lt 0 -or $index -ge $pendingActions.Count) { return }

        $buttonEditorState.SuppressCombo = $true
        try {
            $actionCombo.BeginUpdate()
            try {
                $actionCombo.Items.Clear()
                $buttonEditorState.ActionMap.Clear()

                [void]$actionCombo.Items.Add((Get-ButtonFeatureText -Key 'None'))
                [void]$buttonEditorState.ActionMap.Add('none')

                for ($sliderIndex = 0; $sliderIndex -lt $sliderCount; $sliderIndex++) {
                    $name = [string]$script:Config.sliders[$sliderIndex].name
                    if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]($sliderIndex + 1) }
                    [void]$actionCombo.Items.Add(
                        (Get-ButtonFeatureText -Key 'MuteControl') + ' ' +
                        ($sliderIndex + 1) + ' — ' + $name
                    )
                    [void]$buttonEditorState.ActionMap.Add(('mute:' + $sliderIndex))
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
                    [void]$actionCombo.Items.Add((Get-ButtonFeatureText -Key $fixedAction[0]))
                    [void]$buttonEditorState.ActionMap.Add([string]$fixedAction[1])
                }

                $currentAction = [string]$pendingActions[$index]

                if (
                    $script:VirtualGamepadFeatureAvailable -and
                    (Test-MugenVirtualGamepadProtocolAvailable)
                ) {
                    if (Test-MugenVirtualGamepadAction -Action $currentAction) {
                        [void]$actionCombo.Items.Add((Get-MugenVirtualGamepadActionDisplay -Action $currentAction))
                        [void]$buttonEditorState.ActionMap.Add($currentAction)
                    }
                    [void]$actionCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Виртуальный геймпад Xbox…' } else { 'Virtual Xbox gamepad…' }))
                    [void]$buttonEditorState.ActionMap.Add('virtual:xbox:configure')
                }

                if (
                    $currentAction -match '^hotkey:' -or
                    $currentAction -match '^launch64:' -or
                    $currentAction -match '^folder64:' -or
                    $currentAction -match '^command64:' -or
                    $currentAction -match '^url64:'
                ) {
                    [void]$actionCombo.Items.Add((Get-LargeButtonActionDisplay -Action $currentAction))
                    [void]$buttonEditorState.ActionMap.Add($currentAction)
                }

                [void]$actionCombo.Items.Add((Get-ButtonFeatureText -Key 'HotkeyConfigure'))
                [void]$buttonEditorState.ActionMap.Add('hotkey:configure')
                if ($script:Language -eq 'ru') {
                    [void]$actionCombo.Items.Add('Запустить программу / файл…')
                    [void]$actionCombo.Items.Add('Открыть папку…')
                    [void]$actionCombo.Items.Add('Выполнить команду…')
                    [void]$actionCombo.Items.Add('Открыть URL…')
                }
                else {
                    [void]$actionCombo.Items.Add('Launch program / file…')
                    [void]$actionCombo.Items.Add('Open folder…')
                    [void]$actionCombo.Items.Add('Run command…')
                    [void]$actionCombo.Items.Add('Open URL…')
                }
                [void]$buttonEditorState.ActionMap.Add('launch:configure')
                [void]$buttonEditorState.ActionMap.Add('folder:configure')
                [void]$buttonEditorState.ActionMap.Add('command:configure')
                [void]$buttonEditorState.ActionMap.Add('url:configure')

                $selectedIndex = 0
                for ($mapIndex = 0; $mapIndex -lt $buttonEditorState.ActionMap.Count; $mapIndex++) {
                    if ([string]$buttonEditorState.ActionMap[$mapIndex] -eq $currentAction) {
                        $selectedIndex = $mapIndex
                        break
                    }
                }
                $actionCombo.SelectedIndex = $selectedIndex
            }
            finally {
                $actionCombo.EndUpdate()
            }
        }
        finally {
            $buttonEditorState.SuppressCombo = $false
        }
    }

    $refreshSelectorStyles = {
        $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
        for ($i = 0; $i -lt $selectors.Count; $i++) {
            Set-ButtonIndicatorAppearance -Indicator $selectors[$i] -ButtonIndex $i
            $assigned = (
                $i -lt $pendingActions.Count -and
                -not [string]::IsNullOrWhiteSpace([string]$pendingActions[$i]) -and
                [string]$pendingActions[$i] -ne 'none'
            )
            $pressed = (
                @($script:LatestButtons).Count -gt $i -and
                [int]$script:LatestButtons[$i] -eq 0
            )
            if ($assigned -and -not $pressed) {
                $selectors[$i].ForeColor = $palette.Accent
            }
            if ($i -eq [int]$buttonEditorState.Selected) {
                $selectors[$i].BorderColor = $palette.Accent
            }
        }
    }

    $selectButton = {
        param([int]$Index)
        if ($Index -lt 0 -or $Index -ge $pendingActions.Count) { return }
        $buttonEditorState.Selected = $Index
        $selectedHeading.Text = if ($script:Language -eq 'ru') {
            'Выбрана кнопка: ' + ($Index + 1)
        }
        else {
            'Selected button: ' + ($Index + 1)
        }
        & $populateActionCombo
        & $refreshSelectorStyles

        $buttonEditorState.SuppressListSelection = $true
        try {
            foreach ($item in $assignmentList.Items) {
                if ([int]$item.Tag -eq $Index) {
                    if (-not $item.Selected) {
                        $item.Selected = $true
                    }
                    $item.EnsureVisible()
                    break
                }
            }
        }
        finally {
            $buttonEditorState.SuppressListSelection = $false
        }
    }

    foreach ($selector in $selectors) {
        $selector.Add_Click({
            param($sender, $eventArgs)
            & $selectButton -Index ([int]$sender.Tag)
        })
    }

    if ($profileUiEnabled) {
        $profileCombo.Add_SelectedIndexChanged({
            if ($profileState.Suppress) { return }
            $index = [int]$profileCombo.SelectedIndex
            if ($index -lt 0 -or $index -ge $profileState.Map.Count) { return }

            & $captureCurrentProfileDraft
            & $loadProfileDraft ([string]$profileState.Map[$index])
            & $refreshAssignmentList
            & $selectButton -Index ([int]$buttonEditorState.Selected)
        })

        $addProfileButton.Add_Click({
            & $captureCurrentProfileDraft
            $processName = [string](& $showAddProfileDialog)
            if ([string]::IsNullOrWhiteSpace($processName)) { return }

            $existingProfile = & $findWorkingProfile $processName
            if ($null -eq $existingProfile) {
                if (-not $profileDrafts.ContainsKey('__global__')) {
                    $profileDrafts['__global__'] = [pscustomobject][ordered]@{
                        buttons = @(Copy-AdaptiveProfileButtons -Items @($script:ButtonActions))
                    }
                }
                $globalButtons = @(Copy-AdaptiveProfileButtons -Items @($profileDrafts['__global__'].buttons))

                $profile = [pscustomobject][ordered]@{
                    name = (Get-FriendlyProcessName -ProcessName $processName)
                    process = $processName
                    buttons = @($globalButtons)
                    toggles = @(Copy-AdaptiveProfileToggles -Items @($script:AdaptiveToggleActions))
                    encoders = @(Copy-AdaptiveProfileEncoders -Items @($script:AdaptiveEncoderActions))
                }
                [void]$workingProfiles.Add($profile)

                $key = & $getProfileDraftKey $processName
                $profileDrafts[$key] = [pscustomobject][ordered]@{
                    buttons = @(Copy-AdaptiveProfileButtons -Items @($globalButtons))
                }
            }

            & $populateProfileCombo $processName
            & $loadProfileDraft $processName
            & $refreshAssignmentList
            & $selectButton -Index ([int]$buttonEditorState.Selected)
        })
    }

    $filterCombo.Add_SelectedIndexChanged({ & $refreshAssignmentList })
    $assignmentList.Add_SelectedIndexChanged({
        if ($buttonEditorState.SuppressListSelection) { return }
        if ($assignmentList.SelectedItems.Count -eq 0) { return }

        $targetIndex = [int]$assignmentList.SelectedItems[0].Tag
        if ($targetIndex -eq [int]$buttonEditorState.Selected) { return }
        & $selectButton -Index $targetIndex
    })

    $actionCombo.Add_SelectedIndexChanged({
        if ($buttonEditorState.SuppressCombo) { return }
        $selectedIndex = [int]$actionCombo.SelectedIndex
        if ($selectedIndex -lt 0 -or $selectedIndex -ge $buttonEditorState.ActionMap.Count) { return }

        $selectedAction = [string]$buttonEditorState.ActionMap[$selectedIndex]
        $index = [int]$buttonEditorState.Selected
        $configureActions = @(
            'virtual:xbox:configure',
            'hotkey:configure',
            'launch:configure',
            'folder:configure',
            'command:configure',
            'url:configure'
        )

        if ($selectedAction -notin $configureActions) {
            $pendingActions[$index] = $selectedAction
            & $refreshAssignmentList
            & $refreshSelectorStyles
            return
        }

        $previousAction = [string]$pendingActions[$index]
        $configuredAction = $null
        switch ($selectedAction) {
            'virtual:xbox:configure' {
                $configuredAction = Show-MugenVirtualGamepadButtonPicker -ExistingAction $previousAction -Owner $buttonForm
            }
            'hotkey:configure' { $configuredAction = Show-HotkeyEditor -ExistingAction $previousAction }
            'launch:configure' { $configuredAction = Select-LaunchTargetAction -ExistingAction $previousAction }
            'folder:configure' { $configuredAction = Select-FolderTargetAction -ExistingAction $previousAction }
            'command:configure' { $configuredAction = Show-CommandActionEditor -ExistingAction $previousAction }
            'url:configure' { $configuredAction = Show-UrlActionEditor -ExistingAction $previousAction }
        }

        if (-not [string]::IsNullOrWhiteSpace($configuredAction)) {
            $pendingActions[$index] = [string]$configuredAction
        }
        & $populateActionCombo
        & $refreshAssignmentList
        & $refreshSelectorStyles
    })

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(512, $actionButtonY)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(628, $actionButtonY)
    $save.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($save)

    $save.Add_Click({
        if ($profileUiEnabled) {
            & $captureCurrentProfileDraft

            $globalDraft = $profileDrafts['__global__']
            $script:ButtonActions = @(Copy-AdaptiveProfileButtons -Items @($globalDraft.buttons))
            Save-ButtonActions

            foreach ($profile in @($workingProfiles)) {
                $key = & $getProfileDraftKey ([string]$profile.process)
                if ($profileDrafts.ContainsKey($key)) {
                    $profile.buttons = @(Copy-AdaptiveProfileButtons -Items @($profileDrafts[$key].buttons))
                }
            }

            $script:AdaptiveProfiles = @($workingProfiles)
            $script:AdaptiveProfilesLoaded = $true
            Save-AdaptiveProfiles
            Write-Log ('Button application-profile settings saved: profiles={0}; selected={1}' -f @($script:AdaptiveProfiles).Count, $(if ([string]::IsNullOrWhiteSpace([string]$profileState.Process)) { 'Global' } else { [string]$profileState.Process + '.exe' })) 'INFO'
        }
        else {
            $script:ButtonActions = @($pendingActions)
            Save-ButtonActions
        }

        $buttonForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $buttonForm.Close()
    })

    $liveButtonTimer = New-Object System.Windows.Forms.Timer
    $liveButtonTimer.Interval = 25
    $liveButtonTimer.Add_Tick({
        # The settings dialog is modal, but the controller connection keeps
        # running underneath it. A USB hot-unplug can therefore happen while
        # this timer is alive. Do not inspect stale button topology while the
        # controller is disconnected; keep the editor open and resume live
        # physical-button selection automatically after reconnect.
        if (-not $script:IsConnected) {
            $buttonEditorState.LastButtons = @()
            & $refreshSelectorStyles
            return
        }

        $latest = @($script:LatestButtons)
        $compareCount = [Math]::Min($latest.Count, $pendingActions.Count)
        for ($i = 0; $i -lt $compareCount; $i++) {
            $oldValue = if (@($buttonEditorState.LastButtons).Count -gt $i) { [int]$buttonEditorState.LastButtons[$i] } else { 1 }
            if ([int]$latest[$i] -eq 0 -and $oldValue -ne 0) {
                & $selectButton -Index $i
                break
            }
        }
        $buttonEditorState.LastButtons = @($latest)
        & $refreshSelectorStyles
    })

    Apply-ThemeToForm -Form $buttonForm
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    $selectorFlow.BackColor = $panel.BackColor
    & $refreshAssignmentList
    & $selectButton -Index 0

    $elapsedMs = [int](((Get-Date) - $buildStarted).TotalMilliseconds)
    Write-Log ('Large button settings UI prepared; buttons={0}; controlsCreated={1}; elapsedMs={2}' -f $script:DetectedButtonCount, $buttonForm.Controls.Count, $elapsedMs) 'INFO'

    $buttonForm.Add_Shown({
        Ensure-FormVisible -Form $buttonForm -CenterIfOffscreen
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
function Get-LargeButtonActionDisplay {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'none') {
        return (Get-ButtonFeatureText -Key 'None')
    }

    if (
        $script:VirtualGamepadFeatureAvailable -and
        (Test-MugenVirtualGamepadAction -Action $Action)
    ) {
        return (Get-MugenVirtualGamepadActionDisplay -Action $Action)
    }

    if ($Action -match '^mute:(\d+)$') {
        $sliderIndex = [int]$Matches[1]
        $sliderName = if ($sliderIndex -lt @($script:Config.sliders).Count) {
            [string]$script:Config.sliders[$sliderIndex].name
        }
        else {
            [string]($sliderIndex + 1)
        }
        if ([string]::IsNullOrWhiteSpace($sliderName)) {
            $sliderName = [string]($sliderIndex + 1)
        }
        return (
            (Get-ButtonFeatureText -Key 'MuteControl') +
            ' ' + ($sliderIndex + 1) + ' — ' + $sliderName
        )
    }

    $fixedDisplay = @{
        'media:playpause' = (Get-ButtonFeatureText -Key 'PlayPause')
        'media:previous' = (Get-ButtonFeatureText -Key 'PreviousTrack')
        'media:next' = (Get-ButtonFeatureText -Key 'NextTrack')
        'media:stop' = (Get-ButtonFeatureText -Key 'StopPlayback')
        'system:volumeup' = (Get-ButtonFeatureText -Key 'VolumeUp')
        'system:volumedown' = (Get-ButtonFeatureText -Key 'VolumeDown')
        'system:volumemute' = (Get-ButtonFeatureText -Key 'VolumeMute')
    }
    if ($fixedDisplay.ContainsKey($Action)) {
        return [string]$fixedDisplay[$Action]
    }

    if ($Action -match '^hotkey:') { return (Get-HotkeyActionDisplay -Action $Action) }
    if ($Action -match '^launch64:') { return (Get-LaunchActionDisplay -Action $Action) }
    if ($Action -match '^folder64:') { return (Get-FolderActionDisplay -Action $Action) }
    if ($Action -match '^command64:') { return (Get-CommandActionDisplay -Action $Action) }
    if ($Action -match '^url64:') { return (Get-UrlActionDisplay -Action $Action) }

    return $Action
}

function Show-LargeButtonSettings {
    # Application profiles belong to the PC-side button mapping layer, not to
    # a firmware generation. Legacy simply has zero buttons; Extended and
    # Adaptive can both use the same Global/per-application editor.
    $profileUiEnabled = (
        $script:IsConnected -and
        [int]$script:DetectedButtonCount -gt 0
    )
    if (-not $profileUiEnabled) { return }

    $buildStarted = Get-Date
    Normalize-ButtonActions -Count $script:DetectedButtonCount
    Initialize-AdaptiveActions
    Initialize-AdaptiveProfiles

    $pendingActions = New-Object System.Collections.ArrayList
    foreach ($action in @($script:ButtonActions)) {
        [void]$pendingActions.Add([string]$action)
    }

    $workingProfiles = New-Object System.Collections.ArrayList
    foreach ($profile in @($script:AdaptiveProfiles)) {
        $buttons = @()
        if ($null -ne $profile.PSObject.Properties['buttons']) {
            $buttons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
        }
        [void]$workingProfiles.Add([pscustomobject][ordered]@{
            name = [string]$profile.name
            process = [string]$profile.process
            buttons = @($buttons)
            toggles = @(Copy-AdaptiveProfileToggles -Items @($profile.toggles))
            encoders = @(Copy-AdaptiveProfileEncoders -Items @($profile.encoders))
        })
    }

    $profileDrafts = @{}
    $profileState = [pscustomobject]@{
        Process = ''
        Suppress = $false
        Map = New-Object System.Collections.ArrayList
    }

    $buttonForm = New-Object System.Windows.Forms.Form
    $buttonForm.Text = Get-ButtonFeatureText -Key 'Title'
    $buttonForm.StartPosition = 'CenterParent'
    $dialogClientHeight = if ($profileUiEnabled) { 704 } else { 620 }
    $dialogOuterHeight = if ($profileUiEnabled) { 743 } else { 659 }
    $buttonForm.ClientSize = [System.Drawing.Size]::new(760, $dialogClientHeight)
    $buttonForm.MinimumSize = [System.Drawing.Size]::new(776, $dialogOuterHeight)
    $buttonForm.MaximumSize = [System.Drawing.Size]::new(776, $dialogOuterHeight)
    $buttonForm.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $buttonForm.FormBorderStyle = 'FixedDialog'
    $buttonForm.MaximizeBox = $false
    $buttonForm.MinimizeBox = $false
    Set-FormAppIcon -Form $buttonForm

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = Get-ButtonFeatureText -Key 'Heading'
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(22, 18)
    $buttonForm.Controls.Add($heading)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = if ($script:Language -eq 'ru') {
        'Выберите кнопку в сетке или нажмите её на контроллере — она выберется здесь автоматически.' + "`r`n" + 'Справа настраивается только выбранная кнопка, а список ниже показывает все назначения.'
    }
    else {
        'Choose a button in the grid or press it on the controller — it will be selected here automatically.' + "`r`n" + 'Only the selected button is edited on the right; the list below shows all assignments.'
    }
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Location = [System.Drawing.Point]::new(25, 56)
    $hint.Size = [System.Drawing.Size]::new(710, 43)
    $buttonForm.Controls.Add($hint)

    $saveNotice = New-Object System.Windows.Forms.Label
    $saveNotice.Text = if ($script:Language -eq 'ru') {
        'Важно: изменения начнут работать только после нажатия «Сохранить».'
    }
    else {
        'Important: changes take effect only after you click Save.'
    }
    $saveNotice.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    $saveNotice.Location = [System.Drawing.Point]::new(25, 101)
    $saveNotice.Size = [System.Drawing.Size]::new(710, 27)
    $buttonForm.Controls.Add($saveNotice)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = if ($script:Language -eq 'ru') { 'Профиль:' } else { 'Profile:' }
    $profileLabel.Location = [System.Drawing.Point]::new(25, 139)
    $profileLabel.Size = [System.Drawing.Size]::new(145, 30)
    $profileLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $profileLabel.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($profileLabel)

    $profileCombo = New-Object MugenDeejWindowing.MugenComboBox
    $profileCombo.DropDownStyle = 'DropDownList'
    $profileCombo.Location = [System.Drawing.Point]::new(170, 134)
    $profileCombo.Size = [System.Drawing.Size]::new(350, 30)
    $profileCombo.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($profileCombo)

    $addProfileButton = New-Object MugenDeejWindowing.MugenButton
    $addProfileButton.Text = if ($script:Language -eq 'ru') { 'Добавить…' } else { 'Add…' }
    $addProfileButton.Location = [System.Drawing.Point]::new(532, 133)
    $addProfileButton.Size = [System.Drawing.Size]::new(203, 32)
    $addProfileButton.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($addProfileButton)

    $profileHint = New-Object System.Windows.Forms.Label
    $profileHint.Text = if ($script:Language -eq 'ru') {
        'Общий профиль работает везде; профиль приложения включается автоматически, когда это приложение активно.'
    }
    else {
        'Global works everywhere; an application profile is selected automatically while that app is active.'
    }
    $profileHint.ForeColor = [System.Drawing.Color]::DimGray
    $profileHint.Location = [System.Drawing.Point]::new(25, 170)
    $profileHint.Size = [System.Drawing.Size]::new(710, 42)
    $profileHint.Visible = $profileUiEnabled
    $buttonForm.Controls.Add($profileHint)

    # Virtual-controller power now lives on the main window. Button settings
    # only describe mappings, so the editor starts immediately after profiles.
    $actionButtonY = if ($profileUiEnabled) { 650 } else { 570 }

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = [System.Drawing.Point]::new(22, $(if ($profileUiEnabled) { 218 } else { 139 }))
    $panel.Size = [System.Drawing.Size]::new(716, $(if ($profileUiEnabled) { 404 } else { 427 }))
    $panel.AutoScroll = $false
    $buttonForm.Controls.Add($panel)

    $selectorFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $selectorFlow.Location = [System.Drawing.Point]::new(8, 8)
    $selectorFlow.Size = [System.Drawing.Size]::new(254, $(if ($profileUiEnabled) { 386 } else { 409 }))
    $selectorFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $selectorFlow.WrapContents = $true
    $selectorFlow.AutoScroll = $true
    $panel.Controls.Add($selectorFlow)

    $selectedHeading = New-Object System.Windows.Forms.Label
    $selectedHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $selectedHeading.Location = [System.Drawing.Point]::new(282, 10)
    $selectedHeading.Size = [System.Drawing.Size]::new(420, 27)
    $panel.Controls.Add($selectedHeading)

    $selectedHint = New-Object System.Windows.Forms.Label
    $selectedHint.Text = if ($script:Language -eq 'ru') {
        'Нажмите кнопку на контроллере — Mugen выберет её автоматически.'
    }
    else {
        'Press a button on the controller and Mugen will select it automatically.'
    }
    $selectedHint.ForeColor = [System.Drawing.Color]::DimGray
    $selectedHint.Location = [System.Drawing.Point]::new(282, 39)
    $selectedHint.Size = [System.Drawing.Size]::new(420, 37)
    $panel.Controls.Add($selectedHint)

    $actionCombo = New-Object MugenDeejWindowing.MugenComboBox
    $actionCombo.DropDownStyle = 'DropDownList'
    $actionCombo.Location = [System.Drawing.Point]::new(282, 82)
    $actionCombo.Size = [System.Drawing.Size]::new(420, 30)
    $panel.Controls.Add($actionCombo)

    $assignmentsLabel = New-Object System.Windows.Forms.Label
    $assignmentsLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $assignmentsLabel.Location = [System.Drawing.Point]::new(282, 127)
    $assignmentsLabel.Size = [System.Drawing.Size]::new(235, 25)
    $panel.Controls.Add($assignmentsLabel)

    $filterCombo = New-Object MugenDeejWindowing.MugenComboBox
    $filterCombo.DropDownStyle = 'DropDownList'
    $filterCombo.Location = [System.Drawing.Point]::new(524, 123)
    $filterCombo.Size = [System.Drawing.Size]::new(178, 29)
    [void]$filterCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Назначенные' } else { 'Assigned' }))
    [void]$filterCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Все кнопки' } else { 'All buttons' }))
    $filterCombo.SelectedIndex = 0
    $panel.Controls.Add($filterCombo)

    $assignmentList = New-Object System.Windows.Forms.ListView
    $assignmentList.Location = [System.Drawing.Point]::new(282, 158)
    $assignmentList.Size = [System.Drawing.Size]::new(420, $(if ($profileUiEnabled) { 236 } else { 259 }))
    $assignmentList.View = [System.Windows.Forms.View]::Details
    $assignmentList.FullRowSelect = $true
    $assignmentList.HideSelection = $false
    $assignmentList.MultiSelect = $false
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Кнопка' } else { 'Button' }), 72)
    [void]$assignmentList.Columns.Add($(if ($script:Language -eq 'ru') { 'Действие' } else { 'Action' }), 320)
    $panel.Controls.Add($assignmentList)

    $selectors = @()
    for ($i = 0; $i -lt $script:DetectedButtonCount; $i++) {
        $selector = New-Object MugenDeejWindowing.MugenButtonTile
        $selector.Text = [string]($i + 1)
        $selector.Tag = $i
        $selector.Size = [System.Drawing.Size]::new(42, 28)
        $selector.Margin = New-Object System.Windows.Forms.Padding(3, 2, 3, 2)
        $selector.TextAlign = 'MiddleCenter'
        $selector.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
        $selectorFlow.Controls.Add($selector)
        $selectors += $selector
    }

    $buttonEditorState = [pscustomobject]@{
        Selected = 0
        LastButtons = @($script:LatestButtons)
        ActionMap = New-Object System.Collections.ArrayList
        SuppressCombo = $false
        SuppressListSelection = $false
    }

    $sliderCount = [Math]::Min(
        [int]$script:DetectedSliderCount,
        [int]$script:Config.sliders.Count
    )

    $getProfileDraftKey = {
        param([string]$ProcessName)
        $normalized = Normalize-TargetName -Value $ProcessName
        if ([string]::IsNullOrWhiteSpace($normalized)) { return '__global__' }
        return $normalized.ToLowerInvariant()
    }

    $findWorkingProfile = {
        param([string]$ProcessName)
        $normalized = Normalize-TargetName -Value $ProcessName
        if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }
        foreach ($profile in @($workingProfiles)) {
            if ((Normalize-TargetName -Value ([string]$profile.process)) -ieq $normalized) { return $profile }
        }
        return $null
    }

    $captureCurrentProfileDraft = {
        if (-not $profileUiEnabled) { return }
        $key = & $getProfileDraftKey ([string]$profileState.Process)
        $profileDrafts[$key] = [pscustomobject][ordered]@{
            buttons = @(Copy-AdaptiveProfileButtons -Items @($pendingActions))
        }
    }

    $loadProfileDraft = {
        param([string]$ProcessName)
        if (-not $profileUiEnabled) { return }

        $normalized = Normalize-TargetName -Value $ProcessName
        $key = & $getProfileDraftKey $normalized
        $draft = $null

        if ($profileDrafts.ContainsKey($key)) {
            $draft = $profileDrafts[$key]
        }
        elseif ([string]::IsNullOrWhiteSpace($normalized)) {
            $draft = [pscustomobject][ordered]@{
                buttons = @(Copy-AdaptiveProfileButtons -Items @($script:ButtonActions))
            }
            $profileDrafts[$key] = $draft
        }
        else {
            $profile = & $findWorkingProfile $normalized
            if ($null -eq $profile) { return }

            $buttons = @()
            if ($null -ne $profile.PSObject.Properties['buttons']) {
                $buttons = @(Copy-AdaptiveProfileButtons -Items @($profile.buttons))
            }

            # Profiles created by #89 predate button mappings. They inherit the
            # current Global draft until this dialog explicitly saves buttons.
            if ($buttons.Count -eq 0) {
                if (-not $profileDrafts.ContainsKey('__global__')) {
                    $profileDrafts['__global__'] = [pscustomobject][ordered]@{
                        buttons = @(Copy-AdaptiveProfileButtons -Items @($script:ButtonActions))
                    }
                }
                $buttons = @(Copy-AdaptiveProfileButtons -Items @($profileDrafts['__global__'].buttons))
            }

            $draft = [pscustomobject][ordered]@{ buttons = @($buttons) }
            $profileDrafts[$key] = $draft
        }

        $pendingActions.Clear()
        foreach ($action in @($draft.buttons)) {
            [void]$pendingActions.Add((ConvertTo-SafeProfileButtonAction -Action ([string]$action)))
        }
        while ($pendingActions.Count -lt [int]$script:DetectedButtonCount) {
            [void]$pendingActions.Add('none')
        }

        $profileState.Process = $normalized
        if ([int]$buttonEditorState.Selected -ge $pendingActions.Count) { $buttonEditorState.Selected = 0 }
    }

    $populateProfileCombo = {
        param([string]$SelectProcess = '')
        if (-not $profileUiEnabled) { return }

        $selectedNormalized = Normalize-TargetName -Value $SelectProcess
        $profileState.Suppress = $true
        try {
            $profileCombo.BeginUpdate()
            try {
                $profileCombo.Items.Clear()
                $profileState.Map.Clear()

                [void]$profileCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Общий — для всех остальных приложений' } else { 'Global — all other applications' }))
                [void]$profileState.Map.Add('')

                foreach ($profile in @($workingProfiles | Sort-Object name)) {
                    $processName = Normalize-TargetName -Value ([string]$profile.process)
                    [void]$profileCombo.Items.Add(('{0}  ({1}.exe)' -f [string]$profile.name, $processName))
                    [void]$profileState.Map.Add($processName)
                }

                $selectedIndex = 0
                for ($i = 0; $i -lt $profileState.Map.Count; $i++) {
                    if ([string]$profileState.Map[$i] -ieq $selectedNormalized) {
                        $selectedIndex = $i
                        break
                    }
                }
                $profileCombo.SelectedIndex = $selectedIndex
            }
            finally {
                $profileCombo.EndUpdate()
            }
        }
        finally {
            $profileState.Suppress = $false
        }
    }

    $showAddProfileDialog = {
        if (-not $profileUiEnabled) { return '' }

        $existing = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($profile in @($workingProfiles)) {
            $name = Normalize-TargetName -Value ([string]$profile.process)
            if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$existing.Add($name) }
        }

        $runningProcesses = @(
            Get-RunningApplicationProcessNames |
            Where-Object { -not $existing.Contains((Normalize-TargetName -Value ([string]$_))) } |
            Sort-Object { Get-FriendlyProcessName -ProcessName $_ }
        )

        if ($runningProcesses.Count -eq 0) {
            [void](Show-MugenDeejStyledDialog -Message ($(if ($script:Language -eq 'ru') {
                'Не нашлось запущенного приложения без профиля. Запустите нужную программу и попробуйте снова.'
            } else {
                'No running application without a profile was found. Start the app you want and try again.'
            })) -Buttons 'OK' -Kind 'Info')
            return ''
        }

        $picker = New-Object System.Windows.Forms.Form
        $picker.Text = if ($script:Language -eq 'ru') { 'Добавить профиль приложения — Mugen Deej' } else { 'Add application profile — Mugen Deej' }
        $picker.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
        $picker.ClientSize = [System.Drawing.Size]::new(560, 220)
        $picker.MinimumSize = [System.Drawing.Size]::new(576, 259)
        $picker.MaximumSize = [System.Drawing.Size]::new(576, 259)
        $picker.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $picker.MaximizeBox = $false
        $picker.MinimizeBox = $false
        $picker.ShowInTaskbar = $false
        $picker.Font = $buttonForm.Font
        Set-FormAppIcon -Form $picker

        $pickerHeading = New-Object System.Windows.Forms.Label
        $pickerHeading.Text = if ($script:Language -eq 'ru') { 'Для какого приложения создать профиль?' } else { 'Which application should have its own profile?' }
        $pickerHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
        $pickerHeading.AutoSize = $true
        $pickerHeading.Location = [System.Drawing.Point]::new(20, 18)
        $picker.Controls.Add($pickerHeading)

        $pickerHint = New-Object System.Windows.Forms.Label
        $pickerHint.Text = if ($script:Language -eq 'ru') {
            'Новый профиль получит копию текущих назначений Общего профиля.'
        }
        else {
            'The new profile will start with a copy of the current Global mappings.'
        }
        $pickerHint.ForeColor = [System.Drawing.Color]::DimGray
        $pickerHint.Location = [System.Drawing.Point]::new(22, 52)
        $pickerHint.Size = [System.Drawing.Size]::new(516, 30)
        $picker.Controls.Add($pickerHint)

        $pickerCombo = New-Object MugenDeejWindowing.MugenComboBox
        $pickerCombo.DropDownStyle = 'DropDownList'
        $pickerCombo.Location = [System.Drawing.Point]::new(22, 92)
        $pickerCombo.Size = [System.Drawing.Size]::new(516, 30)
        foreach ($processName in $runningProcesses) {
            [void]$pickerCombo.Items.Add(('{0}  ({1}.exe)' -f (Get-FriendlyProcessName -ProcessName $processName), $processName))
        }
        $pickerCombo.SelectedIndex = 0
        $picker.Controls.Add($pickerCombo)

        $pickerCancel = New-Object MugenDeejWindowing.MugenButton
        $pickerCancel.Text = Get-ButtonFeatureText -Key 'Cancel'
        $pickerCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $pickerCancel.Location = [System.Drawing.Point]::new(330, 164)
        $pickerCancel.Size = [System.Drawing.Size]::new(100, 36)
        $picker.Controls.Add($pickerCancel)

        $pickerAdd = New-Object MugenDeejWindowing.MugenButton
        $pickerAdd.Text = if ($script:Language -eq 'ru') { 'Создать' } else { 'Create' }
        $pickerAdd.Tag = 'MugenPrimary'
        $pickerAdd.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $pickerAdd.Location = [System.Drawing.Point]::new(438, 164)
        $pickerAdd.Size = [System.Drawing.Size]::new(100, 36)
        $picker.Controls.Add($pickerAdd)

        Apply-ThemeToForm -Form $picker -ThemeName (Get-EffectiveTheme)
        $picker.Add_Shown({ Ensure-FormVisible -Form $picker -CenterIfOffscreen })
        $picker.AcceptButton = $pickerAdd
        $picker.CancelButton = $pickerCancel

        $result = $picker.ShowDialog($buttonForm)
        $chosen = if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            [string]$runningProcesses[[int]$pickerCombo.SelectedIndex]
        }
        else {
            ''
        }
        $picker.Dispose()
        return (Normalize-TargetName -Value $chosen)
    }

    if ($profileUiEnabled) {
        & $captureCurrentProfileDraft
        & $populateProfileCombo ''
        & $loadProfileDraft ''
    }

    $refreshAssignmentList = {
        $assignmentList.BeginUpdate()
        try {
            $assignmentList.Items.Clear()
            $assignedCount = 0
            for ($i = 0; $i -lt $pendingActions.Count; $i++) {
                $action = [string]$pendingActions[$i]
                $assigned = (-not [string]::IsNullOrWhiteSpace($action) -and $action -ne 'none')
                if ($assigned) { $assignedCount++ }
                if ($filterCombo.SelectedIndex -eq 0 -and -not $assigned) { continue }

                $item = New-Object System.Windows.Forms.ListViewItem([string]($i + 1))
                [void]$item.SubItems.Add((Get-LargeButtonActionDisplay -Action $action))
                $item.Tag = $i
                [void]$assignmentList.Items.Add($item)
            }
            $assignmentsLabel.Text = if ($script:Language -eq 'ru') {
                'Назначено: {0} из {1}' -f $assignedCount, $pendingActions.Count
            }
            else {
                'Assigned: {0} of {1}' -f $assignedCount, $pendingActions.Count
            }
        }
        finally {
            $assignmentList.EndUpdate()
        }
    }

    $populateActionCombo = {
        $index = [int]$buttonEditorState.Selected
        if ($index -lt 0 -or $index -ge $pendingActions.Count) { return }

        $buttonEditorState.SuppressCombo = $true
        try {
            $actionCombo.BeginUpdate()
            try {
                $actionCombo.Items.Clear()
                $buttonEditorState.ActionMap.Clear()

                [void]$actionCombo.Items.Add((Get-ButtonFeatureText -Key 'None'))
                [void]$buttonEditorState.ActionMap.Add('none')

                for ($sliderIndex = 0; $sliderIndex -lt $sliderCount; $sliderIndex++) {
                    $name = [string]$script:Config.sliders[$sliderIndex].name
                    if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]($sliderIndex + 1) }
                    [void]$actionCombo.Items.Add(
                        (Get-ButtonFeatureText -Key 'MuteControl') + ' ' +
                        ($sliderIndex + 1) + ' — ' + $name
                    )
                    [void]$buttonEditorState.ActionMap.Add(('mute:' + $sliderIndex))
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
                    [void]$actionCombo.Items.Add((Get-ButtonFeatureText -Key $fixedAction[0]))
                    [void]$buttonEditorState.ActionMap.Add([string]$fixedAction[1])
                }

                $currentAction = [string]$pendingActions[$index]

                if (
                    $script:VirtualGamepadFeatureAvailable -and
                    (Test-MugenVirtualGamepadProtocolAvailable)
                ) {
                    if (Test-MugenVirtualGamepadAction -Action $currentAction) {
                        [void]$actionCombo.Items.Add((Get-MugenVirtualGamepadActionDisplay -Action $currentAction))
                        [void]$buttonEditorState.ActionMap.Add($currentAction)
                    }
                    [void]$actionCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Виртуальный геймпад Xbox…' } else { 'Virtual Xbox gamepad…' }))
                    [void]$buttonEditorState.ActionMap.Add('virtual:xbox:configure')
                }

                if (
                    $currentAction -match '^hotkey:' -or
                    $currentAction -match '^launch64:' -or
                    $currentAction -match '^folder64:' -or
                    $currentAction -match '^command64:' -or
                    $currentAction -match '^url64:'
                ) {
                    [void]$actionCombo.Items.Add((Get-LargeButtonActionDisplay -Action $currentAction))
                    [void]$buttonEditorState.ActionMap.Add($currentAction)
                }

                [void]$actionCombo.Items.Add((Get-ButtonFeatureText -Key 'HotkeyConfigure'))
                [void]$buttonEditorState.ActionMap.Add('hotkey:configure')
                if ($script:Language -eq 'ru') {
                    [void]$actionCombo.Items.Add('Запустить программу / файл…')
                    [void]$actionCombo.Items.Add('Открыть папку…')
                    [void]$actionCombo.Items.Add('Выполнить команду…')
                    [void]$actionCombo.Items.Add('Открыть URL…')
                }
                else {
                    [void]$actionCombo.Items.Add('Launch program / file…')
                    [void]$actionCombo.Items.Add('Open folder…')
                    [void]$actionCombo.Items.Add('Run command…')
                    [void]$actionCombo.Items.Add('Open URL…')
                }
                [void]$buttonEditorState.ActionMap.Add('launch:configure')
                [void]$buttonEditorState.ActionMap.Add('folder:configure')
                [void]$buttonEditorState.ActionMap.Add('command:configure')
                [void]$buttonEditorState.ActionMap.Add('url:configure')

                $selectedIndex = 0
                for ($mapIndex = 0; $mapIndex -lt $buttonEditorState.ActionMap.Count; $mapIndex++) {
                    if ([string]$buttonEditorState.ActionMap[$mapIndex] -eq $currentAction) {
                        $selectedIndex = $mapIndex
                        break
                    }
                }
                $actionCombo.SelectedIndex = $selectedIndex
            }
            finally {
                $actionCombo.EndUpdate()
            }
        }
        finally {
            $buttonEditorState.SuppressCombo = $false
        }
    }

    $refreshSelectorStyles = {
        $palette = $script:ThemePalettes[(Get-EffectiveTheme)]
        for ($i = 0; $i -lt $selectors.Count; $i++) {
            Set-ButtonIndicatorAppearance -Indicator $selectors[$i] -ButtonIndex $i
            $assigned = (
                $i -lt $pendingActions.Count -and
                -not [string]::IsNullOrWhiteSpace([string]$pendingActions[$i]) -and
                [string]$pendingActions[$i] -ne 'none'
            )
            $pressed = (
                @($script:LatestButtons).Count -gt $i -and
                [int]$script:LatestButtons[$i] -eq 0
            )
            if ($assigned -and -not $pressed) {
                $selectors[$i].ForeColor = $palette.Accent
            }
            if ($i -eq [int]$buttonEditorState.Selected) {
                $selectors[$i].BorderColor = $palette.Accent
            }
        }
    }

    $selectButton = {
        param([int]$Index)
        if ($Index -lt 0 -or $Index -ge $pendingActions.Count) { return }
        $buttonEditorState.Selected = $Index
        $selectedHeading.Text = if ($script:Language -eq 'ru') {
            'Выбрана кнопка: ' + ($Index + 1)
        }
        else {
            'Selected button: ' + ($Index + 1)
        }
        & $populateActionCombo
        & $refreshSelectorStyles

        $buttonEditorState.SuppressListSelection = $true
        try {
            foreach ($item in $assignmentList.Items) {
                if ([int]$item.Tag -eq $Index) {
                    if (-not $item.Selected) {
                        $item.Selected = $true
                    }
                    $item.EnsureVisible()
                    break
                }
            }
        }
        finally {
            $buttonEditorState.SuppressListSelection = $false
        }
    }

    foreach ($selector in $selectors) {
        $selector.Add_Click({
            param($sender, $eventArgs)
            & $selectButton -Index ([int]$sender.Tag)
        })
    }

    if ($profileUiEnabled) {
        $profileCombo.Add_SelectedIndexChanged({
            if ($profileState.Suppress) { return }
            $index = [int]$profileCombo.SelectedIndex
            if ($index -lt 0 -or $index -ge $profileState.Map.Count) { return }

            & $captureCurrentProfileDraft
            & $loadProfileDraft ([string]$profileState.Map[$index])
            & $refreshAssignmentList
            & $selectButton -Index ([int]$buttonEditorState.Selected)
        })

        $addProfileButton.Add_Click({
            & $captureCurrentProfileDraft
            $processName = [string](& $showAddProfileDialog)
            if ([string]::IsNullOrWhiteSpace($processName)) { return }

            $existingProfile = & $findWorkingProfile $processName
            if ($null -eq $existingProfile) {
                if (-not $profileDrafts.ContainsKey('__global__')) {
                    $profileDrafts['__global__'] = [pscustomobject][ordered]@{
                        buttons = @(Copy-AdaptiveProfileButtons -Items @($script:ButtonActions))
                    }
                }
                $globalButtons = @(Copy-AdaptiveProfileButtons -Items @($profileDrafts['__global__'].buttons))

                $profile = [pscustomobject][ordered]@{
                    name = (Get-FriendlyProcessName -ProcessName $processName)
                    process = $processName
                    buttons = @($globalButtons)
                    toggles = @(Copy-AdaptiveProfileToggles -Items @($script:AdaptiveToggleActions))
                    encoders = @(Copy-AdaptiveProfileEncoders -Items @($script:AdaptiveEncoderActions))
                }
                [void]$workingProfiles.Add($profile)

                $key = & $getProfileDraftKey $processName
                $profileDrafts[$key] = [pscustomobject][ordered]@{
                    buttons = @(Copy-AdaptiveProfileButtons -Items @($globalButtons))
                }
            }

            & $populateProfileCombo $processName
            & $loadProfileDraft $processName
            & $refreshAssignmentList
            & $selectButton -Index ([int]$buttonEditorState.Selected)
        })
    }

    $filterCombo.Add_SelectedIndexChanged({ & $refreshAssignmentList })
    $assignmentList.Add_SelectedIndexChanged({
        if ($buttonEditorState.SuppressListSelection) { return }
        if ($assignmentList.SelectedItems.Count -eq 0) { return }

        $targetIndex = [int]$assignmentList.SelectedItems[0].Tag
        if ($targetIndex -eq [int]$buttonEditorState.Selected) { return }
        & $selectButton -Index $targetIndex
    })

    $actionCombo.Add_SelectedIndexChanged({
        if ($buttonEditorState.SuppressCombo) { return }
        $selectedIndex = [int]$actionCombo.SelectedIndex
        if ($selectedIndex -lt 0 -or $selectedIndex -ge $buttonEditorState.ActionMap.Count) { return }

        $selectedAction = [string]$buttonEditorState.ActionMap[$selectedIndex]
        $index = [int]$buttonEditorState.Selected
        $configureActions = @(
            'virtual:xbox:configure',
            'hotkey:configure',
            'launch:configure',
            'folder:configure',
            'command:configure',
            'url:configure'
        )

        if ($selectedAction -notin $configureActions) {
            $pendingActions[$index] = $selectedAction
            & $refreshAssignmentList
            & $refreshSelectorStyles
            return
        }

        $previousAction = [string]$pendingActions[$index]
        $configuredAction = $null
        switch ($selectedAction) {
            'virtual:xbox:configure' {
                $configuredAction = Show-MugenVirtualGamepadButtonPicker -ExistingAction $previousAction -Owner $buttonForm
            }
            'hotkey:configure' { $configuredAction = Show-HotkeyEditor -ExistingAction $previousAction }
            'launch:configure' { $configuredAction = Select-LaunchTargetAction -ExistingAction $previousAction }
            'folder:configure' { $configuredAction = Select-FolderTargetAction -ExistingAction $previousAction }
            'command:configure' { $configuredAction = Show-CommandActionEditor -ExistingAction $previousAction }
            'url:configure' { $configuredAction = Show-UrlActionEditor -ExistingAction $previousAction }
        }

        if (-not [string]::IsNullOrWhiteSpace($configuredAction)) {
            $pendingActions[$index] = [string]$configuredAction
        }
        & $populateActionCombo
        & $refreshAssignmentList
        & $refreshSelectorStyles
    })

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(512, $actionButtonY)
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(628, $actionButtonY)
    $save.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($save)

    $save.Add_Click({
        if ($profileUiEnabled) {
            & $captureCurrentProfileDraft

            $globalDraft = $profileDrafts['__global__']
            $script:ButtonActions = @(Copy-AdaptiveProfileButtons -Items @($globalDraft.buttons))
            Save-ButtonActions

            foreach ($profile in @($workingProfiles)) {
                $key = & $getProfileDraftKey ([string]$profile.process)
                if ($profileDrafts.ContainsKey($key)) {
                    $profile.buttons = @(Copy-AdaptiveProfileButtons -Items @($profileDrafts[$key].buttons))
                }
            }

            $script:AdaptiveProfiles = @($workingProfiles)
            $script:AdaptiveProfilesLoaded = $true
            Save-AdaptiveProfiles
            Write-Log ('Button application-profile settings saved: profiles={0}; selected={1}' -f @($script:AdaptiveProfiles).Count, $(if ([string]::IsNullOrWhiteSpace([string]$profileState.Process)) { 'Global' } else { [string]$profileState.Process + '.exe' })) 'INFO'
        }
        else {
            $script:ButtonActions = @($pendingActions)
            Save-ButtonActions
        }

        $buttonForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $buttonForm.Close()
    })

    $liveButtonTimer = New-Object System.Windows.Forms.Timer
    $liveButtonTimer.Interval = 25
    $liveButtonTimer.Add_Tick({
        # The settings dialog is modal, but the controller connection keeps
        # running underneath it. A USB hot-unplug can therefore happen while
        # this timer is alive. Do not inspect stale button topology while the
        # controller is disconnected; keep the editor open and resume live
        # physical-button selection automatically after reconnect.
        if (-not $script:IsConnected) {
            $buttonEditorState.LastButtons = @()
            & $refreshSelectorStyles
            return
        }

        $latest = @($script:LatestButtons)
        $compareCount = [Math]::Min($latest.Count, $pendingActions.Count)
        for ($i = 0; $i -lt $compareCount; $i++) {
            $oldValue = if (@($buttonEditorState.LastButtons).Count -gt $i) { [int]$buttonEditorState.LastButtons[$i] } else { 1 }
            if ([int]$latest[$i] -eq 0 -and $oldValue -ne 0) {
                & $selectButton -Index $i
                break
            }
        }
        $buttonEditorState.LastButtons = @($latest)
        & $refreshSelectorStyles
    })

    Apply-ThemeToForm -Form $buttonForm
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(230, 170, 70)
    $selectorFlow.BackColor = $panel.BackColor
    & $refreshAssignmentList
    & $selectButton -Index 0

    $elapsedMs = [int](((Get-Date) - $buildStarted).TotalMilliseconds)
    Write-Log ('Large button settings UI prepared; buttons={0}; controlsCreated={1}; elapsedMs={2}' -f $script:DetectedButtonCount, $buttonForm.Controls.Count, $elapsedMs) 'INFO'

    $buttonForm.Add_Shown({
        Ensure-FormVisible -Form $buttonForm -CenterIfOffscreen
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
function Show-ButtonSettings {
    $useProfiledButtonEditor = (
        $script:IsConnected -and
        $script:DetectedButtonCount -gt 0
    )
    if ($useProfiledButtonEditor) {
        Show-LargeButtonSettings
        return
    }


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

    $virtualProtocolAvailable = (
        $script:VirtualGamepadFeatureAvailable -and
        (Test-MugenVirtualGamepadProtocolAvailable)
    )
    $pendingVirtualEnabled = $false
    if ($virtualProtocolAvailable) {
        $pendingVirtualEnabled = Get-MugenVirtualGamepadEnabled
    }

    $buttonForm = New-Object System.Windows.Forms.Form
    $buttonForm.Text = Get-ButtonFeatureText -Key 'Title'
    $buttonForm.StartPosition = 'CenterParent'
    $buttonForm.ClientSize = [System.Drawing.Size]::new(720, $(if ($virtualProtocolAvailable) { 590 } else { 500 }))
    $buttonForm.MinimumSize = [System.Drawing.Size]::new(736, $(if ($virtualProtocolAvailable) { 629 } else { 539 }))
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

    $virtualCombo = $null
    if ($virtualProtocolAvailable) {
        $virtualLabel = New-Object System.Windows.Forms.Label
        $virtualLabel.Text = $(if ($script:Language -eq 'ru') { 'Виртуальный контроллер:' } else { 'Virtual controller:' })
        $virtualLabel.Location = [System.Drawing.Point]::new(25, 139)
        $virtualLabel.Size = [System.Drawing.Size]::new(180, 28)
        $buttonForm.Controls.Add($virtualLabel)

        $virtualCombo = New-Object MugenDeejWindowing.MugenComboBox
        $virtualCombo.DropDownStyle = 'DropDownList'
        $virtualCombo.Location = [System.Drawing.Point]::new(210, 134)
        $virtualCombo.Size = [System.Drawing.Size]::new(310, 30)
        [void]$virtualCombo.Items.Add($(if ($script:Language -eq 'ru') { 'Выключен' } else { 'Off' }))
        [void]$virtualCombo.Items.Add('Xbox 360 / XInput')
        $virtualCombo.SelectedIndex = $(if ($pendingVirtualEnabled) { 1 } else { 0 })
        $buttonForm.Controls.Add($virtualCombo)

        $virtualStatus = New-Object System.Windows.Forms.Label
        $virtualStatus.Text = $(if ($script:Language -eq 'ru') { 'Для создания XInput-геймпада могут потребоваться повышенные права Windows.' } else { 'Creating the XInput gamepad may require Windows administrator elevation.' })
        $virtualStatus.ForeColor = [System.Drawing.Color]::DimGray
        $virtualStatus.Location = [System.Drawing.Point]::new(25, 173)
        $virtualStatus.Size = [System.Drawing.Size]::new(660, 34)
        $buttonForm.Controls.Add($virtualStatus)
    }

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = [System.Drawing.Point]::new(22, $(if ($virtualProtocolAvailable) { 214 } else { 132 }))
    $panel.Size = [System.Drawing.Size]::new(676, $(if ($virtualProtocolAvailable) { 310 } else { 296 }))
    $panel.AutoScroll = $true
    $buttonForm.Controls.Add($panel)

    $settingsIndicators = @()
    $compactButtonMode = ($script:DetectedButtonCount -gt 12)
    $settingsRows = New-Object System.Collections.ArrayList
    $compactState = [pscustomobject]@{
        Selected = 0
        LastButtons = @($script:LatestButtons)
    }
    $buttonSelectorFlow = $null
    $compactHeading = $null
    $compactHint = $null

    $selectCompactButton = {
        param([int]$Index)

        if (-not $compactButtonMode) { return }
        if ($Index -lt 0 -or $Index -ge $settingsRows.Count) { return }

        $compactState.Selected = $Index

        for ($rowIndex = 0; $rowIndex -lt $settingsRows.Count; $rowIndex++) {
            $rowView = $settingsRows[$rowIndex]
            $isSelected = ($rowIndex -eq $Index)
            $rowView.Label.Visible = $isSelected
            $rowView.Indicator.Visible = $isSelected
            $rowView.Combo.Visible = $isSelected
        }

        if ($null -ne $compactHeading) {
            $compactHeading.Text = if ($script:Language -eq 'ru') {
                'Выбрана кнопка ' + ($Index + 1)
            }
            else {
                'Selected button ' + ($Index + 1)
            }
        }
    }

    if ($compactButtonMode) {
        $panel.AutoScroll = $false

        $buttonSelectorFlow = New-Object System.Windows.Forms.FlowLayoutPanel
        $buttonSelectorFlow.Location = [System.Drawing.Point]::new(8, 8)
        $buttonSelectorFlow.Size = [System.Drawing.Size]::new(248, 292)
        $buttonSelectorFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
        $buttonSelectorFlow.WrapContents = $true
        $buttonSelectorFlow.AutoScroll = $true
        $buttonSelectorFlow.BackColor = $panel.BackColor
        $panel.Controls.Add($buttonSelectorFlow)

        $compactHeading = New-Object System.Windows.Forms.Label
        $compactHeading.Text = $(if ($script:Language -eq 'ru') { 'Выбрана кнопка 1' } else { 'Selected button 1' })
        $compactHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
        $compactHeading.Location = [System.Drawing.Point]::new(280, 14)
        $compactHeading.Size = [System.Drawing.Size]::new(370, 27)
        $panel.Controls.Add($compactHeading)

        $compactHint = New-Object System.Windows.Forms.Label
        $compactHint.Text = $(if ($script:Language -eq 'ru') { 'Нажмите кнопку на контроллере — Mugen выберет её автоматически.' } else { 'Press a button on the controller and Mugen will select it automatically.' })
        $compactHint.ForeColor = [System.Drawing.Color]::DimGray
        $compactHint.Location = [System.Drawing.Point]::new(280, 42)
        $compactHint.Size = [System.Drawing.Size]::new(370, 48)
        $panel.Controls.Add($compactHint)
    }

    $sliderCount = [Math]::Min(
        [int]$script:DetectedSliderCount,
        [int]$script:Config.sliders.Count
    )

    for ($i = 0; $i -lt $script:DetectedButtonCount; $i++) {
        $y = if ($compactButtonMode) { 104 } else { 8 + ($i * 46) }

        $label = New-Object System.Windows.Forms.Label
        $label.Text = (
            (Get-ButtonFeatureText -Key 'ButtonN') +
            ' ' +
            ($i + 1)
        )
        $label.Location = if ($compactButtonMode) {
            [System.Drawing.Point]::new(280, ($y - 34))
        }
        else {
            [System.Drawing.Point]::new(8, ($y + 4))
        }
        $label.Size = [System.Drawing.Size]::new($(if ($compactButtonMode) { 112 } else { 92 }), 28)
        $panel.Controls.Add($label)

        $indicator = New-Object System.Windows.Forms.Label
        $indicator.Text = '●'
        $indicator.Location = if ($compactButtonMode) {
            [System.Drawing.Point]::new(394, ($y - 35))
        }
        else {
            [System.Drawing.Point]::new(101, ($y + 3))
        }
        $indicator.Size = [System.Drawing.Size]::new(28, 28)
        $indicator.TextAlign = 'MiddleCenter'
        $indicator.Font = New-Object System.Drawing.Font(
            'Segoe UI',
            13
        )
        $panel.Controls.Add($indicator)
        if (-not $compactButtonMode) { $settingsIndicators += $indicator }

        $combo = New-Object MugenDeejWindowing.MugenComboBox
        $combo.DropDownStyle = 'DropDownList'
        $combo.Location = if ($compactButtonMode) {
            [System.Drawing.Point]::new(280, $y)
        }
        else {
            [System.Drawing.Point]::new(136, $y)
        }
        $combo.Size = [System.Drawing.Size]::new($(if ($compactButtonMode) { 370 } else { 508 }), 30)

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

        if ($virtualProtocolAvailable) {
            $currentVirtualAction = [string]$pendingActions[$i]
            if (Test-MugenVirtualGamepadAction -Action $currentVirtualAction) {
                [void]$combo.Items.Add((Get-MugenVirtualGamepadActionDisplay -Action $currentVirtualAction))
                [void]$state.ActionMap.Add($currentVirtualAction)
            }

            [void]$combo.Items.Add($(if ($script:Language -eq 'ru') { 'Виртуальный геймпад Xbox…' } else { 'Virtual Xbox gamepad…' }))
            [void]$state.ActionMap.Add('virtual:xbox:configure')
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
                    'virtual:xbox:configure',
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
                'virtual:xbox:configure' {
                    $configuredAction = Show-MugenVirtualGamepadButtonPicker `
                        -ExistingAction $previousAction `
                        -Owner $buttonForm
                }
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
                        (Test-MugenVirtualGamepadAction -Action $mappedAction) -or
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
                    Test-MugenVirtualGamepadAction -Action $configuredAction
                ) {
                    Get-MugenVirtualGamepadActionDisplay -Action $configuredAction
                }
                elseif (
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

        if ($compactButtonMode) {
            $label.Visible = ($i -eq 0)
            $indicator.Visible = ($i -eq 0)
            $combo.Visible = ($i -eq 0)

            [void]$settingsRows.Add([pscustomobject]@{
                Label = $label
                Indicator = $indicator
                Combo = $combo
            })

            $selector = New-Object MugenDeejWindowing.MugenButtonTile
            $selector.Text = [string]($i + 1)
            $selector.Tag = $i
            $selector.Size = [System.Drawing.Size]::new(42, 28)
            $selector.Margin = New-Object System.Windows.Forms.Padding(3, 2, 3, 2)
            $selector.TextAlign = 'MiddleCenter'
            $selector.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
            $selector.Add_Click({
                param($sender, $eventArgs)
                & $selectCompactButton -Index ([int]$sender.Tag)
            })

            $buttonSelectorFlow.Controls.Add($selector)
            $settingsIndicators += $selector
        }
    }

    $cancel = New-Object MugenDeejWindowing.MugenButton
    $cancel.Text = Get-ButtonFeatureText -Key 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = [System.Drawing.Point]::new(472, $(if ($virtualProtocolAvailable) { 537 } else { 447 }))
    $cancel.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($cancel)

    $save = New-Object MugenDeejWindowing.MugenButton
    $save.Text = Get-ButtonFeatureText -Key 'Save'
    $save.Tag = 'MugenPrimary'
    $save.Location = [System.Drawing.Point]::new(588, $(if ($virtualProtocolAvailable) { 537 } else { 447 }))
    $save.Size = [System.Drawing.Size]::new(105, 36)
    $buttonForm.Controls.Add($save)

    $save.Add_Click({
        $script:ButtonActions = @($pendingActions)
        Save-ButtonActions

        if ($virtualProtocolAvailable -and $null -ne $virtualCombo) {
            Set-MugenVirtualGamepadEnabled -Enabled ($virtualCombo.SelectedIndex -eq 1)
            [void](Sync-MugenVirtualGamepadState -Values @($script:LatestButtons))
        }

        $buttonForm.DialogResult =
            [System.Windows.Forms.DialogResult]::OK

        $buttonForm.Close()
    })

    $liveButtonTimer = New-Object System.Windows.Forms.Timer
    $liveButtonTimer.Interval = 25

    $liveButtonTimer.Add_Tick({
        if ($compactButtonMode) {
            $latest = @($script:LatestButtons)
            $compareCount = [Math]::Min($latest.Count, $settingsRows.Count)

            for ($i = 0; $i -lt $compareCount; $i++) {
                $oldValue = if (@($compactState.LastButtons).Count -gt $i) {
                    [int]$compactState.LastButtons[$i]
                }
                else {
                    1
                }

                if ([int]$latest[$i] -eq 0 -and $oldValue -ne 0) {
                    & $selectCompactButton -Index $i
                    break
                }
            }

            $compactState.LastButtons = @($latest)
            $palette = $script:ThemePalettes[(Get-EffectiveTheme)]

            for ($i = 0; $i -lt $settingsIndicators.Count; $i++) {
                Set-ButtonIndicatorAppearance `
                    -Indicator $settingsIndicators[$i] `
                    -ButtonIndex $i

                if ($i -eq [int]$compactState.Selected) {
                    $settingsIndicators[$i].BorderColor = $palette.Accent
                }
            }

            if (
                $compactState.Selected -ge 0 -and
                $compactState.Selected -lt $settingsRows.Count
            ) {
                Set-ButtonIndicatorAppearance `
                    -Indicator $settingsRows[$compactState.Selected].Indicator `
                    -ButtonIndex ([int]$compactState.Selected) `
                    -DotOnly
            }
        }
        else {
            for ($i = 0; $i -lt $settingsIndicators.Count; $i++) {
                Set-ButtonIndicatorAppearance `
                    -Indicator $settingsIndicators[$i] `
                    -ButtonIndex $i `
                    -DotOnly
            }
        }
    })

    Apply-ThemeToForm -Form $buttonForm

    # Keep the Save note as a semantic amber accent after theme application.
    $saveNotice.ForeColor = [System.Drawing.Color]::FromArgb(
        230,
        170,
        70
    )

    if ($compactButtonMode) {
        $buttonSelectorFlow.BackColor = $panel.BackColor
        $palette = $script:ThemePalettes[(Get-EffectiveTheme)]

        for ($i = 0; $i -lt $settingsIndicators.Count; $i++) {
            Set-ButtonIndicatorAppearance `
                -Indicator $settingsIndicators[$i] `
                -ButtonIndex $i

            if ($i -eq [int]$compactState.Selected) {
                $settingsIndicators[$i].BorderColor = $palette.Accent
            }
        }

        if ($settingsRows.Count -gt 0) {
            Set-ButtonIndicatorAppearance `
                -Indicator $settingsRows[0].Indicator `
                -ButtonIndex 0 `
                -DotOnly
        }
    }
    else {
        for ($i = 0; $i -lt $settingsIndicators.Count; $i++) {
            Set-ButtonIndicatorAppearance `
                -Indicator $settingsIndicators[$i] `
                -ButtonIndex $i `
                -DotOnly
        }
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

    if ($script:ControllerProtocol -eq 'unknown') {
        return $true
    }

    return (
        [string]$Packet.Protocol -eq $script:ControllerProtocol -and
        @($Packet.Sliders).Count -eq $script:DetectedSliderCount -and
        @($Packet.Buttons).Count -eq $script:DetectedButtonCount -and
        @(Get-ControllerPacketArray -Packet $Packet -Name 'Toggles').Count -eq $script:DetectedToggleCount -and
        @(Get-ControllerPacketArray -Packet $Packet -Name 'Encoders').Count -eq $script:DetectedEncoderCount
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

    if ($script:VirtualGamepadFeatureAvailable) {
        Stop-MugenVirtualGamepad -Reason $(if ([string]::IsNullOrWhiteSpace($Reason)) { 'controller port closed' } else { $Reason })
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
    $script:DetectedToggleCount = 0
    $script:DetectedEncoderCount = 0
    $script:LatestButtons = @()
    $script:LatestToggles = @()
    $script:LatestEncoders = @()
    $script:LastEncoderPositions = @()
    $script:AdaptiveDebounceDiagnostics = $null
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

function Get-ControllerBaudCandidates {
    $configured = 9600
    try { $configured = [int]$script:Config.connection.baudRate } catch { }
    if ($configured -lt 300 -or $configured -gt 2000000) {
        $configured = 9600
    }

    $mode = 'auto'
    try { $mode = ([string]$script:Config.connection.baudRateMode).Trim().ToLowerInvariant() } catch { }
    if ($mode -eq 'fixed') {
        return @($configured)
    }

    $lastWorking = 0
    try { $lastWorking = [int]$script:Config.connection.lastWorkingBaudRate } catch { }

    $ordered = New-Object 'System.Collections.Generic.List[int]'
    # Keep the last proven rate first for existing controllers, then try the
    # high-speed Adaptive experiment before falling back to configured/legacy
    # rates. This keeps upgrades fast without dropping 115200/9600 support.
    # The current 500k hardware exercise lives in
    # dev/firmware/MugenDeejCardboardNanoE2Test/.
    foreach ($rate in @($lastWorking, 500000, $configured, 115200, 9600)) {
        $candidate = [int]$rate
        if ($candidate -lt 300 -or $candidate -gt 2000000) { continue }
        if (-not $ordered.Contains($candidate)) {
            $ordered.Add($candidate)
        }
    }

    return @($ordered.ToArray())
}

function Test-IsTransientPortOpenError {
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        $message = [string]$exception.Message
        if (
            $message -match 'port.+does not exist|specified port.+does not exist|the system cannot find the file specified|cannot find the file' -or
            $message -match 'порт.+не существует|не уда[её]тся найти указанный файл|системе не уда[её]тся найти указанный файл'
        ) {
            return $true
        }
        $exception = $exception.InnerException
    }

    return $false
}

function Open-And-ProbePort {
    param([Parameter(Mandatory = $true)][string]$PortName)

    $probeGeneration = $script:ProbeGeneration
    if (Test-ConnectionWorkCancelled -Generation $probeGeneration) { return $false }

    $baudCandidates = @(Get-ControllerBaudCandidates)
    if ($baudCandidates.Count -eq 0) {
        $baudCandidates = @(9600)
    }

    $serial = New-Object System.IO.Ports.SerialPort
    $serial.PortName = $PortName
    $serial.BaudRate = [int]$baudCandidates[0]
    $serial.Parity = [System.IO.Ports.Parity]::None
    $serial.DataBits = 8
    $serial.StopBits = [System.IO.Ports.StopBits]::One
    $serial.Handshake = [System.IO.Ports.Handshake]::None
    $serial.DtrEnable = $false
    $serial.RtsEnable = $false
    $serial.ReadTimeout = 200
    $serial.WriteTimeout = 200
    # High-rate Adaptive controllers can continue transmitting while the UI
    # thread is briefly busy. Keep enough receive headroom that a short modal,
    # theme, or device-status operation does not overflow the default ~4 KiB
    # SerialPort buffer and leave partial/concatenated protocol lines behind.
    $serial.ReadBufferSize = 65536
    $serial.NewLine = "`n"

    $accepted = $false
    $cancelled = $false
    $script:ActiveProbeSerial = $serial

    try {
        if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
            $cancelled = $true
            return $false
        }

        Write-Log ('Opening {0} for protocol probe; baud candidates={1}' -f $PortName, ($baudCandidates -join ','))
        $serial.Open()

        if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
            $cancelled = $true
            return $false
        }

        if ($script:PortProbeFailureCounts.ContainsKey($PortName)) {
            [void]$script:PortProbeFailureCounts.Remove($PortName)
        }

        # Opening a Nano/USB-serial device may reset the MCU. Wait once per
        # physical port, then switch SerialPort.BaudRate in-place so trying the
        # second rate does not cause another reset cycle.
        $readyAfter = (Get-Date).AddMilliseconds([int]$script:Config.connection.startupWaitMs)
        while ((Get-Date) -lt $readyAfter) {
            [System.Windows.Forms.Application]::DoEvents()

            if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
                $cancelled = $true
                return $false
            }

            Start-Sleep -Milliseconds 40
        }

        # Correct Mugen packets arrive frequently. 1400 ms is intentionally
        # generous enough for repeated-signature validation while keeping a
        # wrong-baud attempt from adding several seconds to every scan.
        $baudProbeWindowMs = 1400

        foreach ($baudRate in $baudCandidates) {
            if (Test-ConnectionWorkCancelled -Generation $probeGeneration) {
                $cancelled = $true
                return $false
            }

            try {
                if ($serial.BaudRate -ne [int]$baudRate) {
                    $serial.BaudRate = [int]$baudRate
                }
                try { $serial.DiscardInBuffer() } catch { }
            }
            catch {
                Write-Log ('Could not switch {0} to {1} baud: {2}' -f $PortName, $baudRate, $_.Exception.Message) 'WARN'
                continue
            }

            Write-Log ('Probing {0} at {1} baud' -f $PortName, $baudRate)

            $deadline = (Get-Date).AddMilliseconds($baudProbeWindowMs)
            $buffer = ''
            $candidateSignature = ''
            $candidateHits = 0
            $candidateFirstSeenAt = [DateTime]::MinValue

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
                            $candidateFirstSeenAt = Get-Date
                        }

                        # Explicitly typed packets are high-confidence and can win
                        # quickly. Legacy is intentionally held a little longer:
                        # opening/resetting a USB-serial device can expose a short
                        # numeric fragment that otherwise looks like a 1-slider
                        # classic deej packet. A topology that also disagrees with
                        # the configured slider count receives the longer grace.
                        $requiredHits = if ([string]$parsed.Protocol -in @('extended','adaptive')) { 2 } else { 3 }
                        if ($candidateHits -lt $requiredHits) { continue }

                        if ([string]$parsed.Protocol -eq 'legacy') {
                            $legacyObservedSliders = @($parsed.Sliders).Count
                            $legacyExpectedSliders = [Math]::Max(1, [int]$script:Config.connection.expectedSliders)
                            $legacyStableMs = ((Get-Date) - $candidateFirstSeenAt).TotalMilliseconds
                            $legacyMinStableMs = if ($legacyObservedSliders -eq $legacyExpectedSliders) { 300 } else { 900 }

                            if ($legacyStableMs -lt $legacyMinStableMs) {
                                if ($candidateHits -eq $requiredHits) {
                                    Write-Log (
                                        'Legacy probe candidate deferred: port={0}; baud={1}; observedSliders={2}; expectedSliders={3}; requireStableMs={4}' -f
                                        $PortName,
                                        $baudRate,
                                        $legacyObservedSliders,
                                        $legacyExpectedSliders,
                                        $legacyMinStableMs
                                    ) 'DEBUG'
                                }
                                continue
                            }
                        }

                        Set-DetectedControllerCapabilities -Packet $parsed -PortName $PortName
                        Initialize-ButtonStates -Values @($parsed.Buttons)
                        Initialize-AdaptiveControlStates -Packet $parsed
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
                        $script:LastSerialPacketAt = Get-Date
                        $script:Config.connection.lastWorkingPort = $PortName
                        $script:Config.connection.lastWorkingBaudRate = [int]$baudRate
                        Clear-PortProbeCooldown -PortName $PortName
                        $script:PendingNewPorts = @($script:PendingNewPorts | Where-Object { $_ -ne $PortName })
                        Save-Config -Config $script:Config
                        Write-Log ('Controller detected on {0} at {1} baud' -f $PortName, $baudRate)
                        $accepted = $true
                        return $true
                    }
                }
            }
        }

        if (-not (Test-ConnectionWorkCancelled -Generation $probeGeneration)) {
            Write-Log ('{0} opened, but Mugen Deej protocol was not detected at baud rates: {1}' -f $PortName, ($baudCandidates -join ',')) 'WARN'
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
            if (Test-IsTransientPortOpenError -ErrorRecord $_) {
                # GetPortNames() may publish a hotplugged COM name before the
                # serial device is actually openable. Do not poison that port
                # with the ordinary 60-second failed-open cooldown.
                Reset-PortProbeState -PortName $PortName
                $retrySeconds = 2
                Set-PortProbeCooldown -PortName $PortName -Seconds $retrySeconds
                Write-Log "Failed to open ${PortName}; transient hotplug state; $diagnostic; retry in $retrySeconds s" 'WARN'
            }
            elseif (Test-IsPortBusyError -ErrorRecord $_) {
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
    $invert = [bool](Get-EffectiveSliderInversion)

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
                    if ([string]$parsed.Protocol -eq 'adaptive') {
                        Update-AdaptiveControlStates -Packet $parsed
                        Update-ButtonStates -Values @($parsed.Buttons)
                    }
                    else {
                        Update-ButtonStates -Values @($parsed.Buttons)
                        Update-AdaptiveControlStates -Packet $parsed
                    }
                    Register-ControllerPacketTiming
                    $latestParsed = $parsed
                }
                else {
                    $nowMismatch = Get-Date
                    if (
                        $script:LastCapabilityMismatchLog -eq [DateTime]::MinValue -or
                        ($nowMismatch - $script:LastCapabilityMismatchLog).TotalSeconds -ge 5
                    ) {
                        Write-Log (
                            'Ignored packet whose shape changed while connected: expected={0}:{1}:{2}:{3}:{4}; got={5}' -f
                            $script:ControllerProtocol,
                            $script:DetectedSliderCount,
                            $script:DetectedButtonCount,
                            $script:DetectedToggleCount,
                            $script:DetectedEncoderCount,
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

$adaptiveStateGroup = New-Object MugenDeejWindowing.MugenGroupBox
$adaptiveStateGroup.Text = Get-AdaptiveInputUiText -Key 'Group'
$adaptiveStateGroup.Location = [System.Drawing.Point]::new(24, 356)
$adaptiveStateGroup.Size = [System.Drawing.Size]::new(632, 108)
$adaptiveStateGroup.Visible = $false
$form.Controls.Add($adaptiveStateGroup)
$script:AdaptiveStateGroup = $adaptiveStateGroup

$toggleStateLabel = New-Object System.Windows.Forms.Label
$toggleStateLabel.Text = Get-AdaptiveInputUiText -Key 'Toggles'
$toggleStateLabel.Location = [System.Drawing.Point]::new(13, 31)
$toggleStateLabel.Size = [System.Drawing.Size]::new(82, 24)
$toggleStateLabel.TextAlign = 'MiddleLeft'
$toggleStateLabel.Visible = $false
$adaptiveStateGroup.Controls.Add($toggleStateLabel)
$script:ToggleStateLabel = $toggleStateLabel

$toggleStateFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$toggleStateFlow.Location = [System.Drawing.Point]::new(100, 29)
$toggleStateFlow.Size = [System.Drawing.Size]::new(519, 30)
$toggleStateFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$toggleStateFlow.WrapContents = $true
$toggleStateFlow.AutoScroll = $false
$toggleStateFlow.BackColor = $adaptiveStateGroup.BackColor
$toggleStateFlow.Visible = $false
$adaptiveStateGroup.Controls.Add($toggleStateFlow)
$script:ToggleStateFlow = $toggleStateFlow

$encoderStateLabel = New-Object System.Windows.Forms.Label
$encoderStateLabel.Text = Get-AdaptiveInputUiText -Key 'Encoders'
$encoderStateLabel.Location = [System.Drawing.Point]::new(13, 65)
$encoderStateLabel.Size = [System.Drawing.Size]::new(82, 24)
$encoderStateLabel.TextAlign = 'MiddleLeft'
$encoderStateLabel.Visible = $false
$adaptiveStateGroup.Controls.Add($encoderStateLabel)
$script:EncoderStateLabel = $encoderStateLabel

$encoderStateFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$encoderStateFlow.Location = [System.Drawing.Point]::new(100, 63)
$encoderStateFlow.Size = [System.Drawing.Size]::new(519, 32)
$encoderStateFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$encoderStateFlow.WrapContents = $true
$encoderStateFlow.AutoScroll = $false
$encoderStateFlow.BackColor = $adaptiveStateGroup.BackColor
$encoderStateFlow.Visible = $false
$adaptiveStateGroup.Controls.Add($encoderStateFlow)
$script:EncoderStateFlow = $encoderStateFlow

$script:MainToggleIndicators = @()
$script:MainEncoderIndicators = @()

$settingsButton = New-Object MugenDeejWindowing.MugenButton
$settingsButton.Text = if ($script:Language -eq 'ru') { 'Регуляторы' } else { 'Analog controls' }
$settingsButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$settingsButton.Tag = ''
$settingsButton.Location = New-Object System.Drawing.Point(24, 360)
$settingsButton.Size = New-Object System.Drawing.Size(230, 42)
$form.Controls.Add($settingsButton)

$buttonSettingsButton = New-Object MugenDeejWindowing.MugenButton
$buttonSettingsButton.Text = if ($script:Language -eq 'ru') { 'Кнопки' } else { 'Buttons' }
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
    $settingsButton.Text = if ($script:Language -eq 'ru') { 'Регуляторы' } else { 'Analog controls' }
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

        # Do not pump a nested WinForms message loop while the temporary
        # TopMost pulse is active. A fast click can otherwise open a modal
        # child from inside DoEvents(), leaving the TopMost owner above the
        # dialog and making the application appear locked.
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
    Update-AdaptiveInputIndicators
}

function Get-ControllerDiagnosticsSnapshot {
    $connected = [bool]$script:IsConnected
    $baud = '—'
    if ($connected -and $null -ne $script:Serial) {
        try { $baud = [string][int]$script:Serial.BaudRate } catch { }
    }

    $age = '—'
    if ($connected -and $script:LastSerialPacketAt -ne [DateTime]::MinValue) {
        $ageMs = [Math]::Max(0, [int][Math]::Round(((Get-Date) - $script:LastSerialPacketAt).TotalMilliseconds))
        $age = ('{0} ms' -f $ageMs)
    }

    $rate = if ($connected -and [double]$script:PacketRateHz -gt 0.0) {
        ('~{0:N1} Hz' -f [double]$script:PacketRateHz)
    }
    else { '—' }

    $mode = if ([string]$script:Config.connection.mode -eq 'manual') {
        $(if ($script:Language -eq 'ru') { 'Вручную' } else { 'Manual' })
    }
    else {
        $(if ($script:Language -eq 'ru') { 'Автоматически' } else { 'Automatic' })
    }

    return [pscustomobject]@{
        Port = $(if ($connected -and -not [string]::IsNullOrWhiteSpace($script:ConnectedPort)) { $script:ConnectedPort } else { '—' })
        Protocol = $(if ($connected) { Get-ControllerProtocolDisplayText } else { '—' })
        Baud = $baud
        Mode = $mode
        Sliders = $(if ($connected) { [string][int]$script:DetectedSliderCount } else { '—' })
        Buttons = $(if ($connected) { [string][int]$script:DetectedButtonCount } else { '—' })
        Toggles = $(if ($connected) { [string][int]$script:DetectedToggleCount } else { '—' })
        Encoders = $(if ($connected) { [string][int]$script:DetectedEncoderCount } else { '—' })
        PacketAge = $age
        PacketRate = $rate
    }
}

function Show-ConnectionDiagnosticsWindow {
    if ($null -eq $form -or $form.IsDisposed) { return }

    # Driver status is already refreshed on startup, connect/disconnect and
    # driver-install events. Do not run the synchronous CIM/WMI query here:
    # on some systems it takes seconds, making the button look dead and, at
    # high serial rates, starving Process-SerialData long enough to overflow
    # the receive buffer. Show the cached/current status immediately instead.
    Refresh-PortList
    Update-ConnectionControls

    $dialog = New-Object System.Windows.Forms.Form
    $title = [string](T -Key 'DiagnosticsClosed')
    $dialog.Text = ($title -replace '\s*[▼▲]\s*$', '')
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.ClientSize = [System.Drawing.Size]::new(680, 478)
    $dialog.MinimumSize = [System.Drawing.Size]::new(696, 517)
    $dialog.MaximumSize = [System.Drawing.Size]::new(696, 517)
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.Font = $form.Font
    Set-FormAppIcon -Form $dialog

    $infoGroup = New-Object MugenDeejWindowing.MugenGroupBox
    $infoGroup.Text = if ($script:Language -eq 'ru') { 'Сведения о контроллере' } else { 'Controller information' }
    $infoGroup.Location = [System.Drawing.Point]::new(24, 10)
    $infoGroup.Size = [System.Drawing.Size]::new(632, 164)
    $dialog.Controls.Add($infoGroup)

    $labels = @{}
    $rows = @(
        @('Port', $(if ($script:Language -eq 'ru') { 'Порт' } else { 'Port' }), 18, 31),
        @('Protocol', $(if ($script:Language -eq 'ru') { 'Протокол' } else { 'Protocol' }), 18, 58),
        @('Baud', $(if ($script:Language -eq 'ru') { 'Скорость' } else { 'Baud rate' }), 18, 85),
        @('Mode', $(if ($script:Language -eq 'ru') { 'Выбор порта' } else { 'Port selection' }), 18, 112),
        @('Sliders', $(if ($script:Language -eq 'ru') { 'Регуляторы' } else { 'Controls' }), 322, 31),
        @('Buttons', $(if ($script:Language -eq 'ru') { 'Кнопки' } else { 'Buttons' }), 322, 58),
        @('Toggles', $(if ($script:Language -eq 'ru') { 'Тумблеры' } else { 'Toggles' }), 322, 85),
        @('Encoders', $(if ($script:Language -eq 'ru') { 'Энкодеры' } else { 'Encoders' }), 322, 112)
    )

    foreach ($row in $rows) {
        $key = [string]$row[0]
        $caption = New-Object System.Windows.Forms.Label
        $caption.Text = [string]$row[1]
        $caption.Location = [System.Drawing.Point]::new([int]$row[2], [int]$row[3])
        $caption.Size = [System.Drawing.Size]::new(118, 22)
        $caption.ForeColor = [System.Drawing.Color]::DimGray
        $infoGroup.Controls.Add($caption)

        $value = New-Object System.Windows.Forms.Label
        $value.Location = [System.Drawing.Point]::new(([int]$row[2] + 122), [int]$row[3])
        $value.Size = [System.Drawing.Size]::new(165, 22)
        $value.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
        $infoGroup.Controls.Add($value)
        $labels[$key] = $value
    }

    $freshCaption = New-Object System.Windows.Forms.Label
    $freshCaption.Text = if ($script:Language -eq 'ru') { 'Последний пакет:' } else { 'Last packet:' }
    $freshCaption.Location = [System.Drawing.Point]::new(18, 136)
    $freshCaption.Size = [System.Drawing.Size]::new(185, 22)
    $infoGroup.Controls.Add($freshCaption)

    $freshValue = New-Object System.Windows.Forms.Label
    $freshValue.Location = [System.Drawing.Point]::new(205, 136)
    $freshValue.Size = [System.Drawing.Size]::new(405, 22)
    $freshValue.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $freshValue.ForeColor = [System.Drawing.Color]::DimGray
    $infoGroup.Controls.Add($freshValue)

    $connectionGroup.Location = [System.Drawing.Point]::new(24, 182)
    $driverGroup.Location = [System.Drawing.Point]::new(24, 340)
    $dialog.Controls.Add($connectionGroup)
    $dialog.Controls.Add($driverGroup)

    $refreshInfo = {
        $snapshot = Get-ControllerDiagnosticsSnapshot
        foreach ($key in @('Port','Protocol','Baud','Mode','Sliders','Buttons','Toggles','Encoders')) {
            $labels[$key].Text = [string]$snapshot.$key
        }
        $freshValue.Text = if ($script:Language -eq 'ru') {
            $ageText = [string]$snapshot.PacketAge
            if ($ageText -ne '—') {
                $ageText = (($ageText -replace ' ms$', ' мс') + ' назад')
            }

            $rateText = ([string]$snapshot.PacketRate -replace ' Hz$', ' Гц') -replace '\.', ','
            ('{0} · Частота: {1}' -f $ageText, $rateText)
        }
        else {
            $ageText = [string]$snapshot.PacketAge
            if ($ageText -ne '—') {
                $ageText = $ageText + ' ago'
            }

            ('{0} · Rate: {1}' -f $ageText, $snapshot.PacketRate)
        }
    }

    $diagTimer = New-Object System.Windows.Forms.Timer
    $diagTimer.Interval = 250
    $diagTimer.Add_Tick({ & $refreshInfo })

    try {
        & $refreshInfo
        Apply-ThemeToForm -Form $dialog -ThemeName (Get-EffectiveTheme)

        # A modal child must never be opened while its owner is temporarily
        # TopMost. This can happen during tray restoration if another UI event
        # is delivered re-entrantly. The restore path no longer pumps DoEvents,
        # but keep this defensive reset here as well.
        if ($form.TopMost) {
            Write-Log 'Diagnostics opening while the main window is TopMost; clearing transient owner TopMost state' 'WARN'
            $form.TopMost = $false
        }

        Write-Log (
            'Opening connection diagnostics; ownerVisible={0}; ownerTopMost={1}; trayTransitionInProgress={2}' -f
            [bool]$form.Visible,
            [bool]$form.TopMost,
            [bool]$script:TrayTransitionInProgress
        ) 'DEBUG'

        $dialog.Add_Shown({
            Ensure-FormVisible -Form $dialog -CenterIfOffscreen
            try {
                # Give the newly-created owned modal one explicit z-order pulse,
                # then immediately return it to normal owned-window behavior.
                # No DoEvents() here: nested message pumping is exactly what can
                # strand a modal dialog behind its disabled owner.
                $dialog.TopMost = $true
                $dialog.BringToFront()
                [void][MugenDeejWindowing.Foreground]::BringWindowToTop($dialog.Handle)
                [void][MugenDeejWindowing.Foreground]::SetForegroundWindow($dialog.Handle)
                $dialog.Activate()
                $dialog.TopMost = $false
                Write-Log 'Connection diagnostics shown and activated' 'DEBUG'
            }
            catch {
                try { $dialog.TopMost = $false } catch { }
                Write-Log ('Failed to activate connection diagnostics: {0}' -f $_.Exception.Message) 'WARN'
            }
        })
        $diagTimer.Start()
        $dialogResult = $dialog.ShowDialog($form)
        Write-Log ('Connection diagnostics closed; result={0}' -f $dialogResult) 'DEBUG'
    }
    finally {
        $diagTimer.Stop()
        $diagTimer.Dispose()
        if (-not $connectionGroup.IsDisposed) {
            $advancedPanel.Controls.Add($connectionGroup)
            $connectionGroup.Location = [System.Drawing.Point]::new(24, 0)
        }
        if (-not $driverGroup.IsDisposed) {
            $advancedPanel.Controls.Add($driverGroup)
            $driverGroup.Location = [System.Drawing.Point]::new(24, 158)
        }
        if (-not $dialog.IsDisposed) { $dialog.Dispose() }
    }
}
function Set-AdvancedExpanded {
    param(
        [bool]$Expanded,
        [bool]$Persist = $true
    )

    # Compatibility shim for old config/localization call sites. Diagnostics is
    # now a separate dialog, so the main window never enters an expanded state.
    $advancedPanel.Visible = $false
    $label = [string](T -Key 'DiagnosticsClosed')
    $advancedToggle.Text = ($label -replace '\s*[▼▲]\s*$', '')

    $hasButtons = ($script:IsConnected -and $script:DetectedButtonCount -gt 0)
    Set-MainButtonLayout -HasButtons $hasButtons

    $script:Config.app.advancedExpanded = $false
    if ($Persist) {
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
    if ($script:IsConnected) {
        Set-Status (Get-ControllerConnectedStatusText -PortName $script:ConnectedPort) 'ok'
    }
    else {
        Set-Status (T -Key 'StatusNotConnected') 'idle'
    }
    if ($script:VirtualGamepadFeatureAvailable) {
        Refresh-MugenVirtualGamepadLocalizedStatus
    }
    if ($advancedPanel.Visible) {
        Update-DriverStatus
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
$advancedToggle.Add_Click({ Show-ConnectionDiagnosticsWindow })
$refreshButton.Add_Click({ Refresh-PortList; Update-ConnectionControls })
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
    try {
    $desiredInputInterval = if (
        $script:VirtualGamepadFeatureAvailable -and
        $script:VirtualGamepadActive
    ) { 5 } else { 20 }
    if ($timer.Interval -ne $desiredInputInterval) {
        $timer.Interval = $desiredInputInterval
    }

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
    }
    catch {
        $timerError = $_
        $diagnostic = ''
        try {
            $diagnostic = Get-ExceptionDiagnosticText -ErrorRecord $timerError
        }
        catch {
            $diagnostic = 'diagnostic formatting failed: ' + [string]$_.Exception.Message
        }

        $stackText = ''
        try {
            $stackText = ([string]$timerError.ScriptStackTrace) -replace '[\r\n]+', ' <- '
        }
        catch { }

        $categoryText = ''
        try { $categoryText = [string]$timerError.CategoryInfo } catch { }

        $fqidText = ''
        try { $fqidText = [string]$timerError.FullyQualifiedErrorId } catch { }

        try {
            Write-Log (
                'Main UI timer callback failed but was contained; {0}; category={1}; fqid={2}; stack={3}' -f
                $diagnostic,
                $categoryText,
                $fqidText,
                $stackText
            ) 'ERROR'
        }
        catch { }

        # Avoid a tight exception loop if the failure happened in controller
        # recovery. Connect-Controller's finally block has already cleared
        # IsConnecting; simply defer the next targeted attempt.
        if (
            -not $script:IsConnected -and
            -not [string]::IsNullOrWhiteSpace([string]$script:ControllerRecoveryPort)
        ) {
            $script:ControllerRecoveryAt = (Get-Date).AddSeconds(2)
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
