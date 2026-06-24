# 08 — USB Descriptor Parsing: Making the Driver Generic

## The Problem

Every USB Audio Class 2.0 DAC has a different Clock Source entity ID and different alt settings. Hardcoding these values means the driver only works with one DAC. To support any DAC, we must parse the USB descriptors at runtime.

## Solution: `UsbDeviceConnection.getRawDescriptors()`

Android provides `getRawDescriptors()` which returns the complete USB descriptor hierarchy as a byte array. We parse this to find:

1. **Clock Source entity ID** — from the AudioControl interface
2. **Best alt setting** — highest bit depth available in AudioStreaming

## Descriptor Format Reference

USB descriptors are a flat array of Type-Length-Value (TLV) records:
```
[bLength][bDescriptorType][...payload...]
```

### Relevant Descriptor Types

| Type | Value | Context |
|------|-------|---------|
| DEVICE | 0x01 | Device-level info |
| CONFIGURATION | 0x02 | Configuration info |
| INTERFACE | 0x04 | Interface info (class, subclass, alt setting) |
| ENDPOINT | 0x05 | Endpoint info (address, type, max packet) |
| CS_INTERFACE | 0x24 | Class-specific interface (Audio) |
| CS_ENDPOINT | 0x25 | Class-specific endpoint (Audio) |

### AudioControl CS_INTERFACE Subtypes

| Subtype | Value | Contains |
|---------|-------|----------|
| AC_HEADER | 0x01 | AudioControl header |
| INPUT_TERMINAL | 0x02 | Input terminal (USB streaming source) |
| OUTPUT_TERMINAL | 0x03 | Output terminal (speaker/headphone) |
| FEATURE_UNIT | 0x06 | Volume/mute/EQ controls |
| **CLOCK_SOURCE** | **0x0A** | **Clock entity — THIS IS WHAT WE NEED** |
| CLOCK_SELECTOR | 0x0B | Clock multiplexer |
| CLOCK_MULTIPLIER | 0x0C | Clock frequency multiplier |

### AudioStreaming CS_INTERFACE Subtypes

| Subtype | Value | Contains |
|---------|-------|----------|
| AS_GENERAL | 0x01 | Format type, terminal link |
| **FORMAT_TYPE** | **0x02** | **Bit depth — THIS IS WHAT WE NEED** |

## Parsing Algorithm

### Clock Source ID

```kotlin
fun parseClockSourceId(conn: UsbDeviceConnection): Int {
    val raw = conn.rawDescriptors ?: return -1
    var i = 0
    var inAudioControl = false

    while (i + 1 < raw.size) {
        val bLength = raw[i].toInt() and 0xFF
        if (bLength < 2) break
        val bDescriptorType = raw[i + 1].toInt() and 0xFF

        // Track when we're inside AudioControl interface
        if (bDescriptorType == 0x04 && bLength >= 9) {
            val bClass = raw[i + 5].toInt() and 0xFF
            val bSubClass = raw[i + 6].toInt() and 0xFF
            inAudioControl = (bClass == 1 && bSubClass == 1)
        }

        // Look for CLOCK_SOURCE (CS_INTERFACE 0x24, subtype 0x0A)
        if (inAudioControl && bDescriptorType == 0x24 && bLength >= 5) {
            val subtype = raw[i + 2].toInt() and 0xFF
            if (subtype == 0x0A) {
                return raw[i + 3].toInt() and 0xFF  // bClockID
            }
        }

        i += bLength
    }
    return -1
}
```

### Best Alt Setting

```kotlin
fun parseBestAltSetting(conn: UsbDeviceConnection): Pair<Int, Int> {
    val raw = conn.rawDescriptors ?: return Pair(1, 16)
    var i = 0
    var currentAlt = 0
    var inAudioStreaming = false
    var bestAlt = 1
    var bestBits = 16

    while (i + 1 < raw.size) {
        val bLength = raw[i].toInt() and 0xFF
        if (bLength < 2) break
        val bDescriptorType = raw[i + 1].toInt() and 0xFF

        // Track AudioStreaming interface and alt setting
        if (bDescriptorType == 0x04 && bLength >= 9) {
            val bClass = raw[i + 5].toInt() and 0xFF
            val bSubClass = raw[i + 6].toInt() and 0xFF
            inAudioStreaming = (bClass == 1 && bSubClass == 2)
            if (inAudioStreaming) currentAlt = raw[i + 3].toInt() and 0xFF
        }

        // Look for FORMAT_TYPE (CS_INTERFACE 0x24, subtype 0x02)
        if (inAudioStreaming && bDescriptorType == 0x24 && bLength >= 6) {
            val subtype = raw[i + 2].toInt() and 0xFF
            if (subtype == 0x02) {
                val bBitResolution = raw[i + 5].toInt() and 0xFF
                if (bBitResolution > bestBits && currentAlt > 0) {
                    bestBits = bBitResolution
                    bestAlt = currentAlt
                }
            }
        }

        i += bLength
    }
    return Pair(bestAlt, bestBits)
}
```

## Validation

Tested on Cayin RU7:
```
parseClockSourceId: found CLOCK_SOURCE bClockID=0x5
parseBestAltSetting: alt=1 subslotSize=2 bitResolution=16
parseBestAltSetting: alt=2 subslotSize=3 bitResolution=24
parseBestAltSetting: alt=3 subslotSize=4 bitResolution=32
parseBestAltSetting: alt=4 subslotSize=4 bitResolution=32
parseBestAltSetting: best alt=3 bits=32
Auto-detected: clockSourceId=0x5, bestAlt=3, bestBits=32
```

## UAC1 Compatibility

This parser targets UAC2 (protocol=0x20). UAC1 devices use different descriptor formats:
- Sample rate is set per-endpoint (not per-clock-source)
- Different CS_INTERFACE subtypes
- No CLOCK_SOURCE descriptor — uses FEATURE_UNIT for sampling rate

Supporting UAC1 would require a separate parsing path. Most modern DACs are UAC2.

## Edge Cases

1. **Multiple Clock Sources** — our parser returns the first one found. DACs with clock selectors may need the CLOCK_SELECTOR entity parsed to find which clock is active.

2. **Alt setting 4 (DSD)** — some DACs report 32-bit for DSD/DoP alt settings. Our parser may select this over the PCM 32-bit alt. The FORMAT_TYPE descriptor's `bFormatType` field should be checked (Type I = PCM, others = special).

3. **No CLOCK_SOURCE** — UAC1 devices won't have this. The fallback brute-force array is used in that case.
