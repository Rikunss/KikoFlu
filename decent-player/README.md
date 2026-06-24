# decent-player

> Open-source bit-perfect USB Audio output for Android — driver, libraries, and proof-of-concept.

The bits coming out of your decoder are the bits arriving at your DAC. No resampling, no float mixer, no system volume in the way. The driver bypasses **AudioFlinger, AudioTrack, AAudio, ALSA, and the kernel `snd-usb-audio`** entirely and writes PCM straight to the DAC over Linux `usbdevfs` isochronous transfers.

---

## About the name

`decent-player` is the long-term codename for a standalone Android music player I plan to build on top of these libraries.

**That player is not in this repository yet.** What ships today is **the driver and the integration libraries** — the foundation. The current focus is making the driver as solid, well-documented, and easy to drop into any existing Media3-based app as possible. The player application will land in a separate effort once the driver is mature.

If you're here to integrate bit-perfect USB output into your own Android app, this repo is for you. If you're here looking for a finished player — not yet.

---

## What's in this repo

```
decent-player/
├── libs/                     ← The deliverable: 3 standalone libraries (MIT)
│   ├── decent-usb-audio-driver/         Core USB Audio Class 2.0 driver
│   ├── decent-usb-audio-wrapper-media3/ ExoPlayer/Media3 AudioSink wrapper
│   └── decent-media3-decoder-flac/      Native FLAC decoder integration
├── docs/                     ← Technical documentation, USB protocol analysis
├── driver/Felicity/          ← Proof-of-concept harness (AGPL-3.0 fork — see NOTICE.md)
└── player/                   ← Reserved for the future standalone music player (empty)
```

## Where to start

- **Just want to use the driver in your app?** → [Getting Started](docs/libs/GETTING_STARTED.md) → [Integration Guide](docs/libs/INTEGRATION_GUIDE.md)
- **Building a non-Media3 audio pipeline?** → [Integration Guide § Standalone Driver](docs/libs/INTEGRATION_GUIDE.md)
- **Curious how it works under the hood?** → [Architecture](docs/libs/ARCHITECTURE.md) → [Driver deep-dive](docs/driver/01-executive-summary.md)
- **Verified your DAC and want to share?** → [Open a DAC verification issue](https://github.com/Ma145/decent-player/issues/new)

---

## The libraries

Three independent modules that any Android Media3 / ExoPlayer app can integrate.

### `com.decent:usb-audio-driver`

Core USB Audio Class 2.0 driver. Native C++ with JNI. Handles device detection, descriptor parsing, clock control, isochronous URB pipeline, float-to-integer and raw integer conversion with bit-perfect math. Includes **NativeAudioEngine** — a single C++ thread that does FLAC decode → bit-depth conversion → USB output with significant CPU headroom even on weak SoCs.

### `com.decent:usb-audio-wrapper-media3`

Drop-in ExoPlayer / Media3 `AudioSink` wrapper. Three lines to integrate:

```kotlin
// 1. In buildAudioSink():
val sink = UsbAudioSink(delegate, context)

// 2. Wrap LoadControl:
val loadControl = UsbAudioSink.wrapLoadControl(defaultLoadControl) {
    sink.isNativeEngineActive
}

// 3. After player.build():
sink.attachToPlayer(player)
```

`attachToPlayer()` handles everything automatically — NativeAudioEngine lifecycle, track-path extraction, seek-position restore, EOF-to-next-track, and seamless transitions between local files and HTTP streams.

### `com.decent:media3-decoder-flac`

Optional native FLAC decoder built from the upstream [xiph/flac](https://github.com/xiph/flac) source. When in the classpath, ExoPlayer decodes FLAC files to raw integer PCM at the extractor level — zero float math in the entire pipeline. Also provides the `FLACParser` used by `NativeAudioEngine`.

See [`docs/libs/GETTING_STARTED.md`](docs/libs/GETTING_STARTED.md) for the full quick-start guide.

---

## The driver

- Bypasses **AudioFlinger**, **AudioTrack**, **AAudio**, **ALSA**, and the kernel `snd-usb-audio` driver
- Sends PCM data directly via **Linux `usbdevfs` isochronous transfers**
- Auto-detects **Clock Source ID** and optimal bit depth from USB descriptors
- Supports any sample rate the DAC advertises (44.1 kHz — 384 kHz)
- Works on **stock Android 10+**, no root required
- Pipeline of 80 isochronous URBs (~80 ms buffer) with a dedicated streaming thread for glitch-free output
- Protocol-matched rate-transition sequence (derived from xHCI ftrace analysis)
- **Three bit-perfect paths**: native C++ engine (FLAC, zero JNI), float round-trip (`x·2^N` rescale, all formats via FFmpeg), and zero-float integer (libFLAC extractor)

### Verified

| Device | Android | DAC | Status |
|--------|---------|-----|--------|
| Samsung Galaxy S26 Ultra | 16 | Cayin RU7 | Bit-perfect confirmed |
| iBasso DX340 | 13 | Cayin RU7 | Bit-perfect confirmed |

### How we know it's bit-perfect

```
USB driver binding:     usbfs (ours, NOT snd-usb-audio)
ALSA USB card:          none (kernel doesn't touch the DAC)
AudioFlinger output:    SPEAKER only (not USB)
DAC CLOCK_VALID:        true (lock confirmed via UAC2 control endpoint)
Float conversion:       x·2^N round-trip (mathematically exact for 16/24-bit)
Raw int path:           zero float, integer shift only (libFLAC)
URB pipeline:           80 in-flight, zero drops, zero timeouts
```

A full step-by-step proof of bit-perfect delivery is in [`docs/driver/07-verification-and-diagnostics.md`](docs/driver/07-verification-and-diagnostics.md).

---

## Why this exists

Android's standard audio path resamples everything to 48 kHz before it reaches your USB DAC. A 24-bit / 96 kHz FLAC arrives at the DAC as 16-bit / 48 kHz. There has been no open-source way around this on Android — Google's own Media3 / ExoPlayer team has had an [open issue (#415)](https://github.com/androidx/media/issues/415) requesting native bit-perfect USB output since 2023.

This project is a clean-room implementation against the public USB-IF Audio Class 2.0 specification and the Linux `usbdevfs` ABI. It is not a fork of the in-tree `snd-usb-audio` driver, nor of any other audio project — see [NOTICE.md](NOTICE.md) for full provenance.

---

## Documentation

### Library docs (for developers integrating the libraries)

| Document | What's inside |
|----------|---------------|
| [Getting Started](docs/libs/GETTING_STARTED.md) | Quick-start guide with integration examples |
| [Integration Guide](docs/libs/INTEGRATION_GUIDE.md) | Full setup for Media3 apps and standalone driver usage |
| [Architecture](docs/libs/ARCHITECTURE.md) | Pipeline diagram, thread model, rate transitions, bit-perfect math |
| [FLAC Decoders](docs/libs/FLAC_DECODERS.md) | libFLAC vs FFmpeg comparison, integration details |
| [FLAC Build Instructions](docs/libs/DECODER_FLAC_BUILD.md) | How to build the native FLAC decoder from source |
| [DSD Support](docs/libs/DSD_SUPPORT.md) | Future DSD implementation plan (DoP and DSD Native) |
| [Known Limitations](docs/libs/KNOWN_LIMITATIONS.md) | Trade-offs and future improvements deferred for v0.1.0 |

### Driver investigation docs (deep technical reference)

| Document | What's inside |
|----------|---------------|
| [Executive Summary](docs/driver/01-executive-summary.md) | What was built and why it matters |
| [Investigation Journey](docs/driver/02-investigation-journey.md) | The full story — every dead end and breakthrough |
| [Technical Architecture](docs/driver/03-technical-architecture.md) | Data flow, components, USB protocol details |
| [Five Critical Bugs](docs/driver/04-five-critical-bugs.md) | Each bug that caused silence — and the fix |
| [Cayin RU7 Reference](docs/driver/05-cayin-ru7-hardware-reference.md) | Complete hardware analysis with raw USB descriptors |
| [USB Protocol Analysis](docs/driver/06-usb-protocol-analysis.md) | USB audio protocol analysis via xHCI ftrace |
| [Verification Guide](docs/driver/07-verification-and-diagnostics.md) | How to prove bit-perfect is actually happening |
| [Descriptor Parsing](docs/driver/08-usb-descriptor-parsing.md) | Auto-detecting DAC capabilities from USB descriptors |
| [Future Work](docs/driver/09-future-work.md) | Known limitations and roadmap |
| [Samsung Specifics](docs/driver/10-samsung-s26-ultra-specifics.md) | UHQA, Qualcomm PAL, kernel race condition |
| [Library Architecture](docs/driver/11-standalone-library-architecture.md) | How to package the driver for any Android app |

### Issues (investigation and resolution)

| Document | What's inside |
|----------|---------------|
| [Pipeline Latency at High Sample Rates](docs/issues/01-exoplayer-pipeline-latency-high-samplerates.md) | ExoPlayer pipeline overhead on weak CPUs, NativeAudioEngine solution, SD-card FUSE I/O contention from metadata scanner |

### Hardware traces

| File | What's inside |
|------|---------------|
| [xHCI Trace — Rate Transitions](docs/hardware/xhci-trace-rate-transitions.txt) | 449k-line ftrace capture of exact transition sequence |
| [USB DAC Behavior Analysis](docs/hardware/usb-dac-behavior-analysis.md) | Analysis of USB audio protocol behavior on Samsung S26 Ultra |
| [Cayin RU7 USB Analysis](docs/hardware/cayin-ru7-usb-analysis.md) | Raw USB descriptor dump and clock source mapping |

---

## Roadmap

The repository is in **driver-and-libraries** mode for the foreseeable future:

1. **Verify more DACs across vendors** (Topping, FiiO, iFi, Questyle, …) — community reports welcome.
2. **Stabilize the public library API surface** as third-party apps integrate.
3. **Publish to Maven Central** — once the API has been exercised by community testing across multiple DACs and proven stable, the libraries will be published to Maven Central so consumers can drop them in via standard coordinates instead of git submodules.
4. **DSD support** (DoP first, then native DSD) — see [`docs/libs/DSD_SUPPORT.md`](docs/libs/DSD_SUPPORT.md).
5. **Then** start the standalone `decent-player` app on top of these libraries.

If you'd like to verify the driver against your DAC, please open an issue with your hardware combo and a logcat capture — see [`docs/driver/07-verification-and-diagnostics.md`](docs/driver/07-verification-and-diagnostics.md).

---

## License & attribution

This repository is **multi-licensed**. Please read [NOTICE.md](NOTICE.md) for the full breakdown.

- **Original work** (`libs/`, `docs/`, root build files): MIT — see [LICENSE](LICENSE).
- **Proof-of-concept harness** (`driver/Felicity/`): a fork of the [Felicity Music Player](https://github.com/Hamza417/Felicity) by Hamza Rizwan, distributed under AGPL-3.0. The fork is used solely as a host application to exercise the libraries in `libs/` against real hardware. The libraries themselves are independent and remain MIT-licensed.
- **Bundled third-party source**: the FLAC decoder uses the upstream xiph/flac sources under their original BSD-style license.

The standalone `decent-player` application, when it is eventually built, will be a clean-room implementation — not derived from Felicity.

---

## Disclaimer

This software is provided for interoperability and personal use. It is not affiliated with, endorsed by, or sponsored by any DAC manufacturer, music-streaming service, or platform vendor mentioned in the documentation. Any device or brand reference is for descriptive purposes only.

---

<p align="center">
  <i>Built because your music deserves better than 48 kHz.</i>
</p>
