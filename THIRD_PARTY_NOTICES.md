# Third-party notices and acknowledgements

## Original deej project

Mugen Deej was inspired by the open-source **deej** project created by Omri Harel:

- Project: https://github.com/omriharel/deej
- License: MIT License

The original project established the core concept of an Arduino-based physical volume mixer whose analog control values are sent to a desktop client over a serial connection. Mugen Deej intentionally remains compatible with that general hardware concept and serial data format.

The Mugen Deej desktop client is independently developed and is not a fork of the original Go desktop client. This repository does not include the original `deej.exe` or the original desktop-client source code. Mugen Deej is not affiliated with, maintained by, or endorsed by Omri Harel or the original deej project.

We are grateful to Omri Harel and the deej community for the original project and the ecosystem built around it.

## WCH CH340/CH341 driver

The optional CH340/CH341 driver is downloaded from the official WCH website when requested by the user. The driver installer is not redistributed in this repository or release archive.

## HIDMaestro

Mugen Deej 2.0 uses HIDMaestro as the backend for the optional virtual Xbox 360 / XInput controller feature.

- Project: https://github.com/hifihedgehog/HIDMaestro
- Bundled version: 1.8.0
- License: MIT License

The release build downloads the pinned upstream v1.8.0 archive, verifies its SHA-256 before use, publishes the Mugen Deej helper with the verified HIDMaestro.Core.dll, and includes the upstream HIDMaestro license in the release package. The virtual-controller feature is optional and remains disabled until the user enables or configures it.
