# DSD Support: Future Implementation

This document describes a possible implementation of DSD (Direct Stream Digital) support for the Decent USB Audio libraries. DSD is used by SACD rips and high-end audio recordings.

## DSD Transmission Modes

USB Audio Class 2.0 DACs support two DSD modes:

### DoP (DSD over PCM)

DSD data is packed into PCM frames with a marker byte. The DAC detects the marker and switches to DSD mode automatically. No special USB configuration needed — uses the same PCM alt settings.

```
PCM frame (32-bit):  [0x05/0xFA marker byte] [16-bit DSD data] [8-bit padding]
PCM frame (24-bit):  [0x05/0xFA marker byte] [16-bit DSD data]
```

- **Marker bytes** alternate between `0x05` and `0xFA` every frame to signal DSD
- **Sample rate mapping**: DSD64 (2.8MHz) → 176.4kHz PCM, DSD128 (5.6MHz) → 352.8kHz PCM
- **Advantage**: works with any DAC that supports DoP, no driver changes needed for USB transport
- **Disadvantage**: half the PCM bandwidth is used by markers, requires higher PCM sample rate

### DSD Native (Raw DSD)

DSD data is sent directly as raw bitstream using a dedicated USB alt setting (typically alt 4 on DACs that support it). No PCM framing, no markers.

```
USB alt 4: DSD raw bitstream, subslotSize=4, bitResolution=32
```

- **Cayin RU7**: alt 4 is DSD (subslotSize=4, bitResolution=32)
- **Advantage**: full bandwidth, no marker overhead
- **Disadvantage**: requires driver support for the DSD alt setting

## Implementation Plan

### Phase 1: DoP (simpler, broader DAC compatibility)

DoP requires changes only at the app level — the USB driver and wrapper already handle PCM transport.

#### Wrapper changes (`UsbAudioSink`)

```kotlin
// Detect DSD content from ExoPlayer Format
// DSD is delivered as PCM with a special mime type or encoding
if (format.sampleMimeType == "audio/vnd.dsd" || isDsdContent) {
    // Pack DSD data into DoP frames (add 0x05/0xFA markers)
    val dopFrames = packDsdToDoP(rawDsdData, channelCount)
    // Set sample rate to the DoP-equivalent PCM rate
    // DSD64 → 176400, DSD128 → 352800
    val dopSampleRate = dsdRateToDoP(dsdSampleRate)
    configureUsbBitPerfect(dopSampleRate, channelCount, C.ENCODING_PCM_24BIT)
}
```

#### DoP packing function (new, in wrapper or driver)

```kotlin
fun packDsdToDoP(dsdData: ByteArray, channels: Int): ByteArray {
    // For each pair of DSD bytes (one per channel):
    // Output a 24-bit PCM sample: [marker] [dsd_byte_high] [dsd_byte_low]
    // Marker alternates 0x05 / 0xFA every frame
}
```

#### No driver changes needed

The USB driver already sends PCM via isochronous transfers. DoP frames look like regular PCM to the driver — the DAC handles the DoP detection internally.

### Phase 2: DSD Native (raw bitstream, requires driver changes)

#### Driver changes (`usb-audio-output.cpp`)

New alt setting handling for DSD:

```cpp
// DSD native uses a different alt setting (typically alt 4)
// The packet format is raw DSD bitstream, not PCM
// Each USB packet contains DSD data directly

// New function: submit DSD URBs
static void submitDsdToUrbs(UsbAudioContext *ctx, const uint8_t *dsdData, int totalBytes) {
    // Similar to submitPcmToUrbs but:
    // - No float/int conversion
    // - No frame accumulator (DSD rate is fixed)
    // - Packet sizes based on DSD rate / 8000 microframes
}
```

#### Driver changes (`UsbAudioStream.kt`)

```kotlin
// New method for DSD native write
fun writeDsd(dsdBuffer: ByteArray) {
    if (nativeHandle == 0L) return
    nativeUsbAudioWriteDsd(nativeHandle, dsdBuffer)
}

private external fun nativeUsbAudioWriteDsd(handle: Long, dsdBuffer: ByteArray)
```

#### Wrapper changes (`UsbAudioSink`)

```kotlin
// In configure(): detect DSD and use alt 4
if (isDsdNative && deviceInfo.hasDsdAltSetting) {
    // Use DSD alt setting instead of PCM alt
    configureUsbDsdNative(dsdSampleRate, channelCount)
}
```

#### UsbAudioDevice changes

```kotlin
// Parse DSD alt setting from USB descriptors
// Cayin RU7: alt=4, subslotSize=4, bitResolution=32
fun parseDsdAltSetting(conn: UsbDeviceConnection): Int? {
    // Look for alt settings with DSD-specific format type
    // UAC2 FORMAT_TYPE_IV or vendor-specific
}
```

### DSD Sample Rates

| Format | DSD Rate | DoP PCM Rate | Native USB Rate | Multiplier |
|--------|----------|-------------|-----------------|------------|
| DSD64 | 2.8224 MHz | 176.4 kHz | 2.8224 MHz | 64× 44.1kHz |
| DSD128 | 5.6448 MHz | 352.8 kHz | 5.6448 MHz | 128× 44.1kHz |
| DSD256 | 11.2896 MHz | 705.6 kHz | 11.2896 MHz | 256× 44.1kHz |
| DSD512 | 22.5792 MHz | 1411.2 kHz | 22.5792 MHz | 512× 44.1kHz |
| DSD1024 | 45.1584 MHz | N/A* | 45.1584 MHz | 1024× 44.1kHz |
| DSD2048 | 90.3168 MHz | N/A* | 90.3168 MHz | 2048× 44.1kHz |

*DSD1024+ exceeds practical DoP limits. Only native DSD transmission is viable at these rates.

**DoP limits**: DoP packs 16 DSD bits per 24-bit PCM sample. DSD512 via DoP requires 1411.2 kHz PCM — some USB controllers support this, but most cap at 768 kHz (limiting DoP to DSD256 in practice).

**Native DSD limits**: Depends entirely on the DAC's USB implementation. High-end interfaces like the [Gustard U26](https://www.linsoul.com/products/gustard-u26) support DSD2048 native (90.3 MHz) + PCM up to 1536 kHz. The [Singxer SU-2](https://kitsunehifi.com/products/singxer-su-2-dsd1024-usb-digital-interface-femto-second-clock-interface-pcm-768k-hdmi-i2s-ddc-arm-processor) supports DSD1024 native.

### ExoPlayer DSD Support

ExoPlayer/Media3 has limited DSD support. The FFmpeg extension can decode DSD-containing formats (DSF, DFF) but typically converts to PCM internally. For true DSD passthrough:

1. A custom `Extractor` that reads DSF/DFF files and outputs raw DSD data
2. A custom `Renderer` or `AudioSink` that handles the DSD encoding
3. The `UsbAudioSink` wrapper routes DSD to either DoP packing or native DSD write

### DAC Compatibility

| Mode | Cayin RU7 | iBasso DX340 | Gustard U26 | Most USB DACs |
|------|-----------|-------------|-------------|---------------|
| DoP (DSD64-256) | Yes | Yes | Yes | Widely supported |
| DSD Native (DSD64-512) | Yes (alt 4) | Yes | Yes | Common on mid/high-end |
| DSD1024 Native | No | No | Yes | Rare (high-end DDC/DAC) |
| DSD2048 Native | No | No | Yes | Very rare (latest DDCs, e.g., Gustard U26) |

## Recommendations

1. **Start with DoP** — broader compatibility, no driver changes, works with any DAC that supports DoP
2. **Add DSD Native later** — only for DACs with explicit DSD alt settings (like the Cayin RU7 alt 4)
3. **DSD source files** — require a custom DSF/DFF extractor since ExoPlayer doesn't natively extract raw DSD data for passthrough
4. **The DSD decoder (if any)** should NOT convert DSD to PCM — the whole point is bitstream passthrough to the DAC's native DSD converter

## References

- [USB Audio Class 2.0 specification (USB-IF, April 2025)](https://www.usb.org/document-library/usb-device-class-definition-audio-devices-release-20-errata-and-ecn-through-april)
- [DoP specification (dCS)](https://dsd-guide.com/dop-open-standard)
- Cayin RU7 USB descriptor: alt 4 = DSD (subslotSize=4, bitResolution=32)
