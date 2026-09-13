package main

import (
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

//go:embed setup.ps1
var setupScript []byte

//go:embed payload.zip
var payloadZip []byte

var version = "0.0.0-dev"

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

func main() {
	exePath, err := os.Executable()
	if err != nil {
		messageBox("Mugen Deej Setup", err.Error())
		return
	}

	tempDir, err := os.MkdirTemp("", "MugenDeej-Setup-")
	if err != nil {
		messageBox("Mugen Deej Setup", localized(
			fmt.Sprintf("Не удалось создать временную папку:\n%s", err),
			fmt.Sprintf("Could not create a temporary folder:\n%s", err),
		))
		return
	}
	defer os.RemoveAll(tempDir)

	scriptPath := filepath.Join(tempDir, "setup.ps1")
	payloadPath := filepath.Join(tempDir, "payload.zip")

	// Windows PowerShell 5.1 needs a UTF-8 BOM to decode non-ASCII script text reliably.
	scriptWithBOM := make([]byte, 0, len(setupScript)+3)
	scriptWithBOM = append(scriptWithBOM, 0xEF, 0xBB, 0xBF)
	scriptWithBOM = append(scriptWithBOM, setupScript...)

	if err := os.WriteFile(scriptPath, scriptWithBOM, 0600); err != nil {
		messageBox("Mugen Deej Setup", err.Error())
		return
	}
	if err := os.WriteFile(payloadPath, payloadZip, 0600); err != nil {
		messageBox("Mugen Deej Setup", err.Error())
		return
	}

	cmd := exec.Command(
		"powershell.exe",
		"-NoProfile",
		"-ExecutionPolicy", "Bypass",
		"-STA",
		"-File", scriptPath,
		"-PayloadPath", payloadPath,
		"-Version", version,
		"-SetupExePath", exePath,
	)
	cmd.Dir = tempDir
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}

	output, err := cmd.CombinedOutput()
	if err != nil {
		details := strings.TrimSpace(string(output))
		if details == "" {
			details = err.Error()
		}
		messageBox("Mugen Deej Setup", localized(
			"Установщик завершился с ошибкой.\n\n"+details,
			"Setup exited with an error.\n\n"+details,
		))
	}
}
