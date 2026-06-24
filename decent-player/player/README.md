# player/

> Reserved for the future standalone **decent-player** Android music player.

This directory is intentionally empty in the v0.1.0 release. It is a placeholder
for a music player application that will be built **on top of the libraries in
[`libs/`](../libs/)** once the driver and integration libraries reach a stable
public surface.

## Why the repo is named "decent-player"

The project codename `decent-player` refers to the long-term goal of shipping
a complete, standalone Android music player with bit-perfect USB output —
written from scratch, not derived from any existing player. **That player is
not in this repository yet.** Today the deliverable is the open-source bit-
perfect USB Audio driver and the Media3 integration libraries.

If you arrived here looking for the music player, you're early. Watch the
repository for releases.

## What's in the meantime

The proof-of-concept harness exercising the libraries against real hardware
lives in [`driver/Felicity/`](../driver/Felicity/) — a fork of the
[Felicity Music Player](https://github.com/Hamza417/Felicity) (AGPL-3.0)
used purely as a testing host. **It is not the future decent-player.** When
the standalone app is built, it will start fresh in this directory.

## Roadmap

See the [main README](../README.md#roadmap) for the project's current focus
(driver + libraries) and what comes after.
