# Mugen Deej 0.8.3

The first release-candidate-quality build of Mugen Deej.

## Highlights

- Friendly Russian and English interface.
- Automatic controller discovery and reconnection across changing COM ports.
- Manual port selection for systems with several similar serial devices.
- Live control indicators and a beginner-friendly first-run guide.
- Windows master-volume, application-session, and microphone/input-device control.
- Application picker with separate active-audio and silent/saved lists.
- Improved diagnostics for busy ports, Code 31, and rare duplicate COM assignments.
- Custom Mugen Deej icon embedded in the executable and used throughout the UI and tray.

## Tested hardware and scenarios

- CH340/CH341 and FTDI USB–serial controllers.
- Arduino Nano-compatible five-control hardware.
- USB disconnect and automatic reconnection.
- Moving the controller to a different USB port with a new COM number.
- Multiple serial devices and ports held by other applications.
- Specific Windows recording devices and the default microphone.

## Downloads

Attach these files to the GitHub release:

- `Mugen-Deej-0.8.3.zip`
- `Mugen-Deej-0.8.3.zip.sha256`
