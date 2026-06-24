# USB DAC Behavior Analysis — During Active Bit-Perfect Playback on Cayin RU7 at 44.1kHz

## Driver Binding (confirmed)
- Interface 0 (AudioControl): bound to `usbfs` (NOT snd-usb-audio)
- Interface 1 (AudioStreaming): bound to `usbfs` (NOT snd-usb-audio)
- USB device permission: granted to direct USB driver app

## AudioFlinger State
- **NO AudioFlinger thread has USB as output device** during direct USB playback
- All output threads show either `SPEAKER` or `Empty device types`
- USB output thread (usb_output_dynamic) exists but at 384000 Hz, Standby=yes, **NOT active**
- The USB audio patch was RELEASED: `CFG_EVENT_RELEASE_AUDIO_PATCH: USB_DEVICE -> (empty)`
- Then switched: `Speaker -> USB_DEVICE -> Speaker` briefly during init

## Ghost AudioTrack
```
AudioTrack: uid <app_uid>, Port ID 556, Session 3513
Format: PCM_16_BIT, 48000 Hz, Stereo (0x3)
Flags: 0xa00 (FLAG_DEEP_BUFFER + FLAG_MUTE_HAPTIC)
Preferred Device Port ID: 3 (SPEAKER!)
PortVol dB: -25 (nearly muted)
State: Active
Device: SPEAKER (NOT USB!)
```

Key: The direct USB driver uses `setPreferredDevice(speaker)` on its AudioTrack.

## Audio Policy Routing
```
Port ID 3 = Built-in Speaker
Port ID 541 = USB Device Out (Cayin RU7)
```
The ghost AudioTrack has `Preferred Device Port ID: 3` = speaker.

## What the Direct USB Driver Does (Summary)
1. Claims USB interfaces 0 and 1 via UsbManager (force=true) -> detaches snd-usb-audio
2. Sets up isochronous streaming directly via usbdevfs
3. Creates a ghost AudioTrack with `setPreferredDevice(speaker)` for MediaSession
4. AudioFlinger routes the ghost AudioTrack to speaker (muted at -25dB)
5. AudioFlinger does NOT touch USB device at all (no active thread on USB)
6. USB audio comes EXCLUSIVELY from the direct isochronous transfers

## Clock Source
From our earlier testing: Cayin RU7 clock source entity ID = 0x05 (auto-detected from USB descriptors)

## Why Our Driver Had No Sound Initially
Our isochronous URBs return status=0 (kernel accepted) but:
- The data may not actually reach the hardware if packet format is wrong
- For async UAC2, we need to read the feedback endpoint to get correct timing
- Packet sizes must be variable for non-integer sample rates (44100 -> 5/6 frames alternating)
- We may need proper double-buffering with async URB pipeline
