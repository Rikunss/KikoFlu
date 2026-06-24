# Contributing

Thanks for considering a contribution. The repository's current focus is the
driver and libraries in `libs/`. Contributions are welcome in the following
shapes:

## Most useful

- **Verifying additional DACs.** Plug a UAC2.0 DAC, run the proof-of-concept
  app, capture a logcat showing `Bit-perfect: source=Nbit → alt=X usb=Mbit`
  and `fpmf=...` matching the source rate, and open an issue with the device
  details and capture. Bonus points for raw USB descriptors
  (`adb shell lsusb -v -d <vid>:<pid>`).
- **Fixing real bugs** with a clear repro and a logcat slice.
- **Documentation improvements.** If something in `docs/` is unclear, an
  issue or a PR with the rewrite is welcome.

## Less useful (please discuss in an issue first)

- Large refactors of the driver or wrapper.
- New features beyond the current scope (e.g. DSD — there is already a
  design doc; see [`docs/libs/DSD_SUPPORT.md`](docs/libs/DSD_SUPPORT.md)).
- Cosmetic changes that touch many files.

## Ground rules

- **No comparisons to other apps in code or docs.** Describe what the driver
  does and why; don't position it against any specific commercial app.
- **No personal data, internal hostnames, or test credentials in commits.**
  `debug-secrets.properties` exists for local dev and is gitignored — keep
  it that way. There is no need to push real IPs, server names, or
  credentials anywhere in this repo.
- **Respect the licensing split.** `libs/` is MIT and original work;
  `driver/Felicity/` is an AGPL-3.0 fork. PRs that move AGPL-licensed code
  into `libs/` will not be accepted. See [NOTICE.md](NOTICE.md).
- **Sign your commits** if you can (`git commit -S`). Not required, but
  appreciated.
- **Be civil.** Audiophile debates can get heated; we are here to make
  Android sound better, not to argue over which DAC is best.

## Reporting bit-perfect failures

If the DAC reports the wrong sample rate, glitches, or refuses to open,
please include in your issue:

1. Phone or DAP model + Android version.
2. DAC vendor / model.
3. Exact app version (commit hash if built from source).
4. Logcat capture covering the connect → first-track → glitch sequence.
5. Output of `adb shell ls /proc/asound/` and
   `adb shell dumpsys media.audio_flinger | grep -i usb`.

## License of contributions

By submitting a contribution to a directory, you agree to license it under
that directory's existing license:

- `libs/`, `docs/`, root: MIT
- `driver/Felicity/`: AGPL-3.0
