# Code signing policy

## Application status

Mugen Deej is currently applying for the SignPath Foundation open-source
code signing program.

Existing releases, including Mugen Deej 1.0.0, are unsigned and will not be
retroactively modified.

If the application is accepted, future release artifacts may be signed through
SignPath.io using a certificate issued to SignPath Foundation.

> Free code signing provided by SignPath.io, certificate by SignPath Foundation.

## Scope

Only first-party Mugen Deej release artifacts built from the source code and
build scripts in this repository may be submitted for signing.

Third-party open-source components may be included in release packages when
their licenses permit it, but they will not be signed as Mugen Deej components
using this project's signing subscription.

Every signing request for a release must be manually approved.

## Team roles

Mugen Deej is currently maintained by a single maintainer.

- Authors / committers: MrSoichi
- Reviewers: MrSoichi
- Approvers: MrSoichi

External contributions are reviewed before they are accepted into the project.

## Privacy

This program will not transfer any information to other networked systems
unless specifically requested by the user or the person installing or
operating it.

Mugen Deej may download the official CH340/CH341 driver only after explicit
user confirmation. User-configured actions may also open network URLs specified
by the user.

## Historical releases

Releases published before SignPath Foundation approval are unsigned and are not
retroactively covered by a future SignPath signing configuration.
