# Known Limitations and Future Improvements

This document tracks **deliberate trade-offs and known rough edges** in the
v0.1.0 release of the libraries. None of these prevent bit-perfect playback;
they are quality-of-life and architecture items deferred until the public
API is exercised by community DAC verification.

When something here gets fixed, it should be removed from this file and
added to a release note.

---

## API surface

### `UsbAudioSink` is one large class

`UsbAudioSink` (`libs/decent-usb-audio-wrapper-media3/.../UsbAudioSink.kt`)
manages USB streams, the native engine, the streaming-thread fallback,
LoadControl integration, position tracking, and player attachment in a single
class (~860 lines). The public surface is intentionally tiny —
`UsbAudioSink(delegate, context)`, `attachToPlayer(player)`, and
`UsbAudioSink.wrapLoadControl(...)` — but the internals are densely coupled
because the ExoPlayer / USB lifecycles are tightly interleaved.

Refactoring into smaller publicly-extensible pieces is desirable, but pre-
mature: the right boundaries will be clearer once third-party apps have
actually integrated the library and pushed back on what they need to extend.

### `UsbAudioDevice` is a process-wide singleton

`UsbAudioDevice.getInstance(context)` returns a singleton for the whole
process. This is fine for the dominant use case (one DAC, one music app at
a time) but does not currently support:

- Hot-swapping between two DACs without an app restart.
- Multiple `UsbAudioSink` instances on different DACs simultaneously.

A non-singleton, per-device factory is on the roadmap once a real use case
arrives.

### Missing KDoc on several public symbols

The following public entry points lack thorough KDoc covering ownership /
lifecycle / threading expectations:

- `UsbAudioSink` constructor (who owns `delegate`?)
- `UsbAudioDevice.getInstance()` (threading; reset semantics)
- `UsbAudioStream` constructor (rate-transition lifecycle)
- `NativeAudioEngine.createFromFd(...)` (fd ownership / closing)
- `SftpDataSource.open(...)` (URI parsing rules; session caching)

Behaviour is documented at module level in `docs/libs/`, but per-symbol
KDoc would help IDE tooltips and is on the cleanup list.

## Concurrency

### Thread-safety contract is implicit

`UsbAudioSink` holds a number of mutable fields (`currentEncoding`,
`currentSampleRate`, `usbAudioStream`, `nativeEngine`, etc.) that are
written from `configure()` / `handleBuffer()` (render thread) and read from
the player listener thread (`onMediaItemTransition`). In practice these
calls are serialised by ExoPlayer's own threading model, but the contract
is not spelled out in code or KDoc. Marking the relevant fields `@Volatile`
or guarding with a single lock is a low-risk hardening that should be done
before the API is published as a Maven artifact.

### `NativeEngineAwareLoadControl` has no liveness check

When `isNativeEngineActive()` returns true, ExoPlayer's loading is fully
suppressed. If the native engine ever crashes or stalls without notifying
the LoadControl, ExoPlayer would never resume loading. In practice the
engine has been reliable across hundreds of hours of testing, but a
watchdog timeout (e.g. "if engine has not produced audio for 5 s, treat as
inactive") would be a sound safety net.

### `UsbAudioDevice` does not invalidate `cachedDeviceInfo` on replug

If the DAC is unplugged and plugged back in, the cached file descriptor
becomes stale. The current behaviour relies on the Activity's
`USB_DEVICE_ATTACHED` handler to re-claim and the singleton to be re-
initialised on next use. A more defensive approach would observe USB
detach events and proactively invalidate the cache.

## Native code

### Magic numbers in USB descriptor parsing

`UsbAudioDevice.parseClockSourceId()` and `parseBestAltSetting()` use
literal hex constants for USB descriptor types and subtypes (`0x04`,
`0x0A`, `0x24`, `0x02`). These match the USB Audio Class 2.0 specification
verbatim, but named constants (`DESCRIPTOR_TYPE_INTERFACE`,
`AC_DESCRIPTOR_SUBTYPE_CLOCK_SOURCE`, etc.) would improve readability.

### `Feedback #N` log emitted every 10 000 URBs

`usb-audio-output.cpp:Feedback #...` is gated by a modulo and is harmless
at the current rate (~one line every two seconds), but it could be wrapped
in `#ifndef NDEBUG` so production builds emit nothing on the hot path.

## Streaming

### Plain-text passwords in SFTP URIs

`SftpDataSource` accepts `sftp://user:password@host/path` URIs because
that is the standard URI form for SFTP and is what JSch consumes. The
password is held in memory while the session is alive (so it can be reused
across seeks without re-authenticating) and discarded when the process
ends. The library does **not** persist credentials anywhere on disk.

If a host application wants stronger guarantees (clearing the password
right after authentication, key-based auth only, or a custom credential
provider), that's a feature to layer on top of the current minimal
implementation.

### `UsbStreamingThread` drops the oldest queued buffer when full

When the ExoPlayer pipeline outpaces the USB consumption rate (rare, but
possible during cross-rate transitions or extreme load), the oldest
queued buffer is dropped. This produces a brief audio glitch but keeps
playback alive. The drop count is logged (first 3, then every 100th); a
public observable counter would let host apps surface a quality-of-output
metric, and is a reasonable future addition.

## Testing

### No automated test suite

The libraries do not currently ship unit tests. The components most worth
covering are:

- `PcmUtils` — float ↔ int conversion across all encodings and boundary
  cases (±1.0, beyond range, alignment).
- `UsbAudioDevice.parseClockSourceId()` and `parseBestAltSetting()` — with
  static USB descriptor byte arrays as fixtures.
- `UsbAudioSink` position tracking / ENGINE-vs-PIPELINE switching, against
  a fake `NativeAudioEngine`.

The ISO USB I/O path can only really be exercised on hardware, so the
verification model is the **community DAC verification report** template
(`.github/ISSUE_TEMPLATE/dac-verification.md`).

## Distribution

### Not on Maven Central yet

The libraries are currently consumed via Gradle composite-build / project
paths from sibling repositories. Publication to Maven Central is planned
**after** the public API has been validated by community DAC verification
across multiple vendors and the API surface is stable. See the [main
README roadmap](../../README.md#roadmap).
