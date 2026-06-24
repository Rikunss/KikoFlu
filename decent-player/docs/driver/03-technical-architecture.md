# 03 — Technical Architecture: USB Audio Driver

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     Felicity App Process (https://github.com/Hamza417/Felicity)                      │
│                                                               │
│  ┌──────────┐     ┌──────────────────┐     ┌──────────────┐ │
│  │ ExoPlayer │────>│ AaudioAudioSink  │────>│ UsbAudioOut- │ │
│  │ (decode)  │     │ (intercept PCM)  │     │ putProcessor │ │
│  │           │     │                  │     │ (JNI wrapper)│ │
│  └──────────┘     └──────────────────┘     └──────┬───────┘ │
│                          │ (muted)                  │ JNI     │
│                          ↓                          ↓         │
│                   ┌──────────────┐          ┌─────────────┐  │
│                   │ DefaultAudio │          │ usb-audio-  │  │
│                   │ Sink(speaker)│          │ output.cpp  │  │
│                   └──────┬───────┘          └──────┬──────┘  │
│                          │                         │          │
└──────────────────────────┼─────────────────────────┼──────────┘
                           │                         │
                           ↓                         ↓
                    ┌──────────────┐          ┌─────────────┐
                    │ AudioFlinger │          │  usbdevfs   │
                    │ (SPEAKER)    │          │  ioctl()    │
                    └──────────────┘          └──────┬──────┘
                           │                         │
                           ↓                         ↓
                    ┌──────────────┐          ┌─────────────┐
                    │   Speaker    │          │  USB Host   │
                    │  (silence)   │          │ Controller  │
                    └──────────────┘          │  (xHCI)     │
                                              └──────┬──────┘
                                                     │
                                                     ↓
                                              ┌─────────────┐
                                              │  Cayin RU7  │
                                              │  USB DAC    │
                                              │ (bit-perfect)│
                                              └─────────────┘
```

## Component Responsibilities

### AaudioAudioSink.kt (Engine Module)
- **Entry point** for all audio buffers from ExoPlayer
- Checks `AudioPreferences.isBitPerfectUsbEnabled()`
- If USB bit-perfect: routes PCM to `UsbAudioOutputProcessor`
- If not: falls through to existing AAudio or default AudioTrack path
- Manages the delegate AudioTrack (muted, routed to speaker)
- Handles configure/play/pause/stop/release lifecycle

### UsbAudioManager.kt (Engine Module — Singleton)
- **USB device lifecycle**: detect, permission, open, close
- **Descriptor parsing**: auto-detect Clock Source ID, best alt setting/bit depth
- **Sample rate control**: SET_CUR/GET_CUR via `controlTransfer()`
- **Interface management**: claim, setInterface (Java API for bandwidth allocation)
- Singleton pattern ensures one connection shared across all callers

### UsbAudioOutputProcessor.kt (Engine Module)
- **JNI wrapper** matching the pattern of existing `AaudioOutputProcessor`
- Maps Kotlin calls to native `nativeUsbAudio*` functions
- Lifecycle: create → setAltSetting → start → write(FloatArray) → stop → release

### usb-audio-output.cpp (Native — JNI)
- **Core isochronous transfer logic**
- Float→PCM conversion (16/24/32-bit)
- Variable packet size calculation (fractional accumulator for non-integer rates)
- URB pipeline management (8 URBs in flight)
- Feedback endpoint reading (UAC2 16.16 fixed-point)
- `USBDEVFS_URB_ISO_ASAP` flag on all URBs
- USB reset + immediate native claim for race condition mitigation

### MainActivity.kt (Music Module)
- **USB_DEVICE_ATTACHED** intent handler
- Claims USB device ASAP when connected (before snd-usb-audio can configure)
- Requests permission if needed

## USB Protocol Details

### UAC2 Initialization Sequence
```
1. UsbDeviceConnection.claimInterface(AudioControl, force=true)
   → Detaches snd-usb-audio kernel driver from interface 0

2. UsbDeviceConnection.claimInterface(AudioStreaming, force=true)
   → Detaches snd-usb-audio kernel driver from interface 1

3. Java setInterface(streaming, alt=0)
   → Zero-bandwidth, stops any active streaming

4. controlTransfer(SET_CUR, clockSourceId, sampleRate)
   → Configures DAC clock PLL while interface is deselected

5. Java setInterface(streaming, alt=N)
   → Activates streaming endpoint + allocates ISO bandwidth in xHCI

6. Pre-submit 8 silence URBs (fire-and-forget)
   → Fills the xHCI isochronous schedule pipeline

7. Stream audio: for each ExoPlayer buffer:
   a. Convert float→PCM (32-bit)
   b. Pack into variable-size isochronous packets
   c. If pipeline full (>=8 URBs): reap one completed URB
   d. Submit new URB with ISO_ASAP flag
```

### Isochronous Packet Format

For USB high-speed (480 Mbps), microframes are 125μs (8000/sec).

**44100 Hz, 32-bit stereo:**
- Frames per microframe: 44100 / 8000 = 5.5125
- Bytes per frame: 4 bytes × 2 channels = 8 bytes
- Packet sizes alternate: 5 frames (40 bytes) and 6 frames (48 bytes)
- Average: 5.5125 × 8 = 44.1 bytes/microframe

**96000 Hz, 32-bit stereo:**
- Frames per microframe: 96000 / 8000 = 12.0
- Bytes per frame: 8 bytes
- Packet size: exactly 12 frames (96 bytes) per microframe

**384000 Hz, 32-bit stereo:**
- Frames per microframe: 384000 / 8000 = 48.0
- Bytes per frame: 8 bytes
- Packet size: exactly 48 frames (384 bytes) per microframe

### URB Structure
```c
struct usbdevfs_urb {
    type = USBDEVFS_URB_TYPE_ISO;      // Isochronous transfer
    flags = USBDEVFS_URB_ISO_ASAP;     // Schedule at next available microframe
    endpoint = 0x01;                    // OUT endpoint address
    buffer = pcmData;                   // PCM audio data
    buffer_length = totalBytes;
    number_of_packets = N;              // Typically 64 packets per URB (8ms)
    iso_frame_desc[0..N-1].length = bytesPerPacket;  // Variable per packet
};
```

### Feedback Endpoint
- Endpoint 0x81 IN, isochronous, 4 bytes
- UAC2 format: 16.16 fixed-point (frames per microframe)
- Read periodically (every ~1 second) to verify clock stability
- Example: 5.5127 = 0x00058333 → 44101.6 Hz (correct for 44.1kHz)

## File Map

```
engine/
├── src/main/jni/
│   ├── usb-audio-output.cpp          # Core native driver (V4)
│   ├── usb-audio-output.h            # UsbAudioContext struct
│   └── CMakeLists.txt                # Added usb-audio-output.cpp
├── src/main/java/app/simple/felicity/engine/
│   ├── audio/
│   │   ├── AaudioAudioSink.kt        # USB branch in configure/handleBuffer
│   │   └── UsbAudioManager.kt        # Singleton, descriptor parser, device lifecycle
│   └── processors/
│       └── UsbAudioOutputProcessor.kt # JNI wrapper

preferences/
└── src/main/java/.../AudioPreferences.kt  # BIT_PERFECT_USB_ENABLED

music/
├── src/main/AndroidManifest.xml       # USB_DEVICE_ATTACHED intent filter
├── src/main/res/xml/
│   └── usb_audio_device_filter.xml    # USB Audio Class filter (class=1)
├── src/main/java/.../activities/
│   └── MainActivity.kt               # handleUsbDeviceAttached()
├── src/main/java/.../extensions/fragments/
│   └── PreferenceFragment.kt         # Bit-Perfect USB toggle
├── src/main/java/.../dialogs/app/
│   └── UsbAudioDiagnosticDialog.kt   # USB diagnostic bottom sheet
└── src/main/res/layout/
    └── dialog_usb_audio_diagnostic.xml

shared/
└── src/main/res/values/strings.xml    # Bit-perfect strings
```
