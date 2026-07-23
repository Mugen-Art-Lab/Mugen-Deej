# Troubleshooting

## Controller is not found

- Keep automatic COM-port detection enabled.
- Disconnect and reconnect the controller.
- Try another USB port.
- Open **Connection and diagnostics** and inspect the log.

## COM port is busy

Another application has the port open. Close serial monitors, Arduino IDE serial tools, display-controller software, or other programs that may scan COM ports.

## Windows reports Code 31 or a COM-number conflict

Try another physical USB port first. Rarely, Windows can retain a conflicting COM assignment for a specific device path or hub port. Avoid deleting a working driver package unless the driver itself is genuinely broken.

## Application does not appear in the picker

If the application is running silently, look in **Running silently or already saved**. If it is still absent, play any sound in it and refresh the list, or add its process name manually.

## Microphone is missing

Open the microphone list again to refresh available input devices. The default microphone option follows the current Windows default; a specific saved device remains selected and is marked unavailable when disconnected.
