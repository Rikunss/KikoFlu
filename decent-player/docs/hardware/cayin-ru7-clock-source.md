# CRITICAL FIX: Cayin RU7 Clock Source Entity ID

## The Bug
Our `setSampleRate()` was using clock source ID **0x0B** which was found by brute-force
trying multiple IDs. The DAC accepted the control transfer (returned ret=4 bytes) but
**DID NOT ACTUALLY CHANGE THE CLOCK** because entity 0x0B doesn't exist.

## The Fix
The real Clock Source entity ID is **0x05**, as declared in the USB AudioControl descriptor.

From the raw USB descriptors (parsed from `/sys/bus/usb/devices/1-1/descriptors`):
```
Clock Source Descriptor:
  bDescriptorSubtype = 0x0A (CLOCK_SOURCE)
  bClockID = 0x05           ← THIS IS THE CORRECT ID
  bmAttributes = 0x03
  bmControls = 0x07
```

All terminal entities reference clock source 0x05:
- Input Terminal (0x01): bCSourceID = 0x05
- Output Terminal (0x04): bCSourceID = 0x05

## The Control Transfer
```
wIndex = (clockSourceId << 8) | audioControlInterfaceNumber
       = (0x05 << 8) | 0
       = 0x0500
```

## Why 0x0B Appeared to Work
The DAC firmware accepts SET_CUR/GET_CUR control transfers to any entity ID without
returning an error (STALL). The transfer completes with ret=4, but only entity 0x05
actually controls the clock PLL. GET_CUR to any ID may return a cached value from a
shadow register, not the actual clock state.
