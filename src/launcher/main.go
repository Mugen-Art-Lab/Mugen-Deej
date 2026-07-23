package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

var (
	user32                       = syscall.NewLazyDLL("user32.dll")
	kernel32                     = syscall.NewLazyDLL("kernel32.dll")
	procMessageBoxW              = user32.NewProc("MessageBoxW")
	procGetUserDefaultLocaleName = kernel32.NewProc("GetUserDefaultLocaleName")
)

func messageBox(title, text string) {
	titlePtr, _ := syscall.UTF16PtrFromString(title)
	textPtr, _ := syscall.UTF16PtrFromString(text)
	procMessageBoxW.Call(
		0,
		uintptr(unsafe.Pointer(textPtr)),
		uintptr(unsafe.Pointer(titlePtr)),
		0x10,
	)
}

func russianUI() bool {
	buffer := make([]uint16, 85)
	result, _, _ := procGetUserDefaultLocaleName.Call(
		uintptr(unsafe.Pointer(&buffer[0])),
		uintptr(len(buffer)),
	)
	if result == 0 {
		return false
	}
	locale := syscall.UTF16ToString(buffer)
	return strings.HasPrefix(strings.ToLower(locale), "ru")
}

func localized(ru, en string) string {
	if russianUI() {
		return ru
	}
	return en
}

func tailFile(path string, limit int64) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		return ""
	}

	start := info.Size() - limit
	if start < 0 {
		start = 0
	}
	if _, err := f.Seek(start, io.SeekStart); err != nil {
		return ""
	}

	data, err := io.ReadAll(f)
	if err != nil {
		return ""
	}
	return string(data)
}

func main() {
	exe, err := os.Executable()
	if err != nil {
		messageBox("Mugen Deej", err.Error())
		return
	}

	baseDir := filepath.Dir(exe)
	script := filepath.Join(baseDir, "MugenDeej.ps1")
	if _, err := os.Stat(script); err != nil {
		messageBox("Mugen Deej", localized(
			"Рядом с MugenDeej.exe не найден MugenDeej.ps1",
			"MugenDeej.ps1 was not found next to MugenDeej.exe",
		))
		return
	}

	logDir := filepath.Join(baseDir, "logs")
	if err := os.MkdirAll(logDir, 0755); err != nil {
		messageBox("Mugen Deej", localized(
			fmt.Sprintf("Не удалось создать папку журналов:\n%s", err),
			fmt.Sprintf("Failed to create the log folder:\n%s", err),
		))
		return
	}

	launcherLog := filepath.Join(logDir, "launcher.log")
	logFile, err := os.OpenFile(launcherLog, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		messageBox("Mugen Deej", localized(
			fmt.Sprintf("Не удалось открыть журнал запуска:\n%s", err),
			fmt.Sprintf("Failed to open the launcher log:\n%s", err),
		))
		return
	}
	defer logFile.Close()

	fmt.Fprintln(logFile, "\r\n===== Mugen Deej launcher start =====")

	escapedScript := strings.ReplaceAll(script, "'", "''")
	powerShellCommand := fmt.Sprintf(
		"$utf8=[System.Text.UTF8Encoding]::new($false); "+
			"[Console]::OutputEncoding=$utf8; $OutputEncoding=$utf8; "+
			"$tokens=$null; $parseErrors=$null; "+
			"[System.Management.Automation.Language.Parser]::ParseFile('%s',[ref]$tokens,[ref]$parseErrors) | Out-Null; "+
			"if ($parseErrors.Count -gt 0) { "+
			"foreach ($parseError in $parseErrors) { "+
			"[Console]::Error.WriteLine(('PowerShell parse error at {0}:{1}: {2}' -f $parseError.Extent.StartLineNumber,$parseError.Extent.StartColumnNumber,$parseError.Message)) "+
			"}; exit 2 }; & '%s'",
		escapedScript,
		escapedScript,
	)

	cmd := exec.Command(
		"powershell.exe",
		"-NoProfile",
		"-ExecutionPolicy", "Bypass",
		"-STA",
		"-WindowStyle", "Hidden",
		"-Command", powerShellCommand,
	)
	cmd.Dir = baseDir
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}

	if err := cmd.Run(); err != nil {
		_ = logFile.Sync()
		details := tailFile(launcherLog, 6000)
		text := localized(
			fmt.Sprintf("Mugen Deej завершился с ошибкой.\n\nЖурнал:\n%s", launcherLog),
			fmt.Sprintf("Mugen Deej exited with an error.\n\nLog:\n%s", launcherLog),
		)
		if details != "" {
			text += localized("\n\nПоследние строки:\n", "\n\nLast lines:\n") + details
		}
		messageBox(localized("Mugen Deej — ошибка запуска", "Mugen Deej — startup error"), text)
	}
}
