# Notice

This repository contains components under different licenses. Please respect each.

## Original work — MIT (this repository's primary license)

Copyright (c) 2026 Marcelo Silva

The following directories contain original work licensed under the MIT License
(see [LICENSE](LICENSE) for the full text):

- `libs/decent-usb-audio-driver/` — USB Audio Class 2.0 driver (native C++ + Kotlin/JNI)
- `libs/decent-usb-audio-wrapper-media3/` — ExoPlayer/Media3 `AudioSink` wrapper
- `libs/decent-media3-decoder-flac/` — Native FLAC decoder integration
- `docs/` — Technical documentation
- `tools/` (if present) — Helper scripts
- Root build files (`build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`, `.gitignore`)

These components do not include any code, headers, or documentation derived
from third-party music applications, drivers, or frameworks beyond what is
explicitly attributed below. The USB driver implementation was written from
scratch against the public USB-IF Audio Class 2.0 specification and the Linux
`usbdevfs` ABI; it is **not** a fork of the in-tree `snd-usb-audio` driver or
of any user-space project.

## Third-party fork — AGPL-3.0

`driver/Felicity/` is a fork of the [Felicity Music Player](https://github.com/Hamza417/Felicity)
by Hamza Rizwan, distributed under the GNU Affero General Public License v3.0.

Felicity is used in this repository **only** as a proof-of-concept harness to
demonstrate the libraries in `libs/` running inside a real Android player.
Modifications to Felicity are limited to wiring the decent USB Audio libraries
into its existing playback path.

If you redistribute or modify the contents of `driver/Felicity/`, you must
comply with AGPL-3.0 (see [`driver/Felicity/LICENSE`](driver/Felicity/LICENSE)).
The MIT licensing of `libs/` is **not** affected: the libraries are independent
modules referenced by Felicity via Gradle composite-build paths, not derivative
works of Felicity.

## Bundled third-party source

The native FLAC decoder in `libs/decent-media3-decoder-flac/src/main/jni/libflac/`
is the upstream [xiph/flac](https://github.com/xiph/flac) source, distributed
under its original BSD-style license — see the headers of those files for the
full notice.

## Trademarks

"Android" is a trademark of Google LLC. Mention of any device or DAC brand in
this repository is for descriptive interoperability purposes only and does not
imply affiliation, sponsorship, or endorsement by those brands.

## Disclaimer

This software is provided "as is" without warranty of any kind. See the
respective LICENSE files for full warranty disclaimers.
