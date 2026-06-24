# decent-player documentation

The full documentation index is in the [root README](../README.md#documentation).
This file is just a brief map of what lives where in `docs/`:

| Directory | Audience | What's inside |
|-----------|----------|---------------|
| [`libs/`](libs/) | Android developers integrating the libraries | Getting Started, Integration Guide, Architecture, FLAC decoder paths, DSD plan |
| [`driver/`](driver/) | Technical readers wanting the deep dive | Executive summary, investigation journey, USB protocol analysis, descriptor parsing, bug history, samsung specifics, USB pops resolution, diagnostics reference |
| [`hardware/`](hardware/) | Anyone reverse-engineering specific DACs | Cayin RU7 analysis, clock-source discovery, USB DAC behaviour observations, raw xHCI ftrace |
| [`issues/`](issues/) | Curious readers who like post-mortems | Detailed write-ups of specific issues encountered during development |

For navigation **by use case** (e.g. "I want to integrate this into my Media3 app"), see the
**"Where to start"** section of the [root README](../README.md#where-to-start).
