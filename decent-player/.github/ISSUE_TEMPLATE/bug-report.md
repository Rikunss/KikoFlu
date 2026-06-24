---
name: Bug report
about: Something broken in the driver, the wrapper, or the docs
title: "[Bug] "
labels: ["bug"]
---

## Summary

One or two sentences describing what's wrong.

## Hardware

- **Phone / DAP model:**
- **Android version:**
- **DAC vendor and model (if relevant):**

## App / library version

- **Repo commit hash (or release tag) you built from:**
- **Branch:**

## Steps to reproduce

1.
2.
3.

## Expected behaviour

What should happen.

## Actual behaviour

What actually happens.

## Logs

Please attach a logcat capture covering the failure. The most useful filter is:

```
adb logcat | grep -E "UsbAudio|NativeAudioEngine|AudioSink"
```

If the failure involves USB enumeration, please also include:

```
adb shell dumpsys usb
adb shell lsusb -v -d <vid>:<pid>   # if the DAC is connected
```

Paste here, or attach as a file if it's long.

## Notes

Anything else that might be relevant — the order of events, whether it happens on first run only, whether it survives an app restart, etc.
