import 'dart:async' show Timer;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../providers/audio_provider.dart';
import '../../services/equalizer_service.dart';
import '../../services/hi_res_audio_service.dart';
import '../../services/audio_player_service.dart';
import '../../services/exclusive_audio_service.dart';
import '../../providers/exclusive_audio_provider.dart';
import '../../providers/usb_dac_provider.dart';
import '../../services/usb_dac_audio_manager.dart';

/// Shows the Audio Information dialog in the center of the screen.
Future<void> showAudioInfoSheet(BuildContext context, WidgetRef ref) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Audio Information',
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, anim1, anim2) => const _AudioInfoDialog(),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return FadeTransition(
        opacity: anim1,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

/// Shell dialog — no ref.watch. Each section is a ConsumerWidget that
/// independently watches only the providers it needs. This prevents the
/// entire dialog from rebuilding when a single provider (e.g. position at
/// 200ms) emits.
class _AudioInfoDialog extends ConsumerStatefulWidget {
  const _AudioInfoDialog();

  @override
  ConsumerState<_AudioInfoDialog> createState() => _AudioInfoDialogState();
}

class _AudioInfoDialogState extends ConsumerState<_AudioInfoDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final size = MediaQuery.of(context).size;
    final orientation = MediaQuery.orientationOf(context);

    final isLandscape = orientation == Orientation.landscape;
    final maxH = isLandscape ? 0.70 : 0.80;
    final screenWidth = size.width;
    final dialogWidth = screenWidth > 480 ? 380.0 : screenWidth * 0.88;

    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: dialogWidth,
              maxHeight: size.height * maxH,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              children: [
                // ── Title bar ──
                _TitleBar(cs: cs, tt: tt),
                // ── Scrollable content — each section watches its own providers ──
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    shrinkWrap: true,
                    children: const [
                      _FileSectionCard(),
                      SizedBox(height: 8),
                      _AudioChainSectionCard(),
                      SizedBox(height: 8),
                      _DspSectionCard(),
                      SizedBox(height: 8),
                      _StatusSectionCard(),
                      SizedBox(height: 12),
                      // Footer
                      _InfoFooter(),
                      SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// File section — watches currentTrackProvider, durationProvider,
// audioFormatInfoProvider. Rebuilds only when track or format info changes.
// ═══════════════════════════════════════════════
class _FileSectionCard extends ConsumerWidget {
  const _FileSectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).valueOrNull;
    final duration = ref.watch(durationProvider).valueOrNull;
    final formatInfo = ref.watch(audioFormatInfoProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    String? fileName;
    if (track?.url != null) {
      final uri = track!.url;
      fileName = uri.split('/').last.split('?').first.split('#').first;
    }

    return _SectionCard(
      icon: Icons.audiotrack,
      title: 'File',
      cs: cs,
      tt: tt,
      children: [
        if (fileName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Text(
              fileName,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        // Format pills row
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _FormatPill(
                  label: formatInfo?.codec.toUpperCase() ?? '-',
                  color: cs.primary.withValues(alpha: 0.7),
                  textColor: cs.onPrimary),
              if (formatInfo?.sampleRate != null)
                _FormatPill(
                    label: '${(formatInfo!.sampleRate! / 1000).toStringAsFixed(formatInfo.sampleRate! % 1000 == 0 ? 0 : 1)} kHz',
                    color: cs.tertiary.withValues(alpha: 0.7),
                    textColor: cs.onTertiary),
              if (formatInfo?.bitDepth != null)
                _FormatPill(
                    label: '${formatInfo!.bitDepth} bit',
                    color: cs.secondary.withValues(alpha: 0.7),
                    textColor: cs.onSecondary),
              if (formatInfo?.channels != null)
                _FormatPill(
                    label: '${formatInfo!.channels}ch',
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
                    textColor: cs.onSurfaceVariant),
              if ((formatInfo?.sampleRate ?? 0) > 48000)
                _FormatPill(
                    label: 'HI-RES',
                    color: cs.primaryContainer,
                    textColor: cs.onPrimaryContainer,
                    bold: true),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Text(
            duration != null ? _fmtDuration(duration) : '—',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // Bitrate row (if available)
        if (formatInfo?.estimatedBitrateKbps != null) ...[
          const SizedBox(height: 2),
          _InfoRow(
            label: 'Bitrate',
            value: formatInfo!.estimatedBitrateKbps! >= 1000
                ? '${(formatInfo.estimatedBitrateKbps! / 1000).toStringAsFixed(1)} Mbps'
                : '${formatInfo.estimatedBitrateKbps} kbps',
            cs: cs, tt: tt,
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// Audio Chain section — watches exclusive/hi-res/output providers.
// ═══════════════════════════════════════════════
class _AudioChainSectionCard extends ConsumerWidget {
  const _AudioChainSectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioService = AudioPlayerService.instance;

    // Exclusive mode + USB DAC
    final exclusiveStateAsync = ref.watch(exclusiveAudioStateProvider);
    final exclusiveState = exclusiveStateAsync.when(
      data: (s) => s,
      loading: () => const ExclusiveModeState(),
      error: (_, __) => const ExclusiveModeState(),
    );
    final dacNameAsync = ref.watch(activeUsbDacNameProvider);
    final usbDacNameValue = dacNameAsync.when(
      data: (name) => name,
      loading: () => '',
      error: (_, __) => '',
    );
    // libusb USB DAC state
    final libusbStateAsync = ref.watch(usbDacManagerStateProvider);
    final libusbState = libusbStateAsync.when(
      data: (s) => s,
      loading: () => const UsbDacManagerState(),
      error: (_, __) => const UsbDacManagerState(),
    );
    final routingAsync = ref.watch(hiResUsbRoutingProvider);
    final hiResRouting = routingAsync.when(
      data: (r) => r,
      loading: () => const UsbRoutingState(),
      error: (_, __) => const UsbRoutingState(),
    );
    // Use hiResActiveProvider instead of hiResPlaybackStateProvider for the
    // decoder label. hiResPlaybackStateProvider only tracks isPlaying (native
    // play state), so it would incorrectly show "ExoPlayer (just_audio)"
    // when a hi-res track is paused. hiResActiveProvider tracks the Dart-side
    // _hiResActive flag, which is true whenever the hi-res ExoPlayer is
    // configured, regardless of play/pause state.
    final hiResActiveAsync = ref.watch(hiResActiveProvider);
    final hiResIsPlaying = ref.watch(hiResPlaybackStateProvider).when(
      data: (p) => p,
      loading: () => false,
      error: (_, __) => false,
    );
    final activeDeviceAsync = ref.watch(activeOutputDeviceProvider);
    final activeDeviceType = activeDeviceAsync.when(
      data: (t) => t,
      loading: () => '',
      error: (_, __) => '',
    );

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Compute decoder, output, device name
    String decoder;
    String output;
    // Use hiResActiveProvider for decoder label (true even when paused)
    final bool isHiResActive = hiResActiveAsync.when(
      data: (active) => active,
      loading: () => hiResIsPlaying,
      error: (_, __) => hiResIsPlaying,
    );

    final String aaudioFormatDesc;
    if (Platform.isAndroid) {
      aaudioFormatDesc = exclusiveState.aaudioExclusive
          ? 'Exclusive'
          : exclusiveState.aaudioActive
              ? 'Shared'
              : exclusiveState.aaudioAvailable
                  ? 'Available'
                  : 'N/A';
    } else if (Platform.isWindows) {
      aaudioFormatDesc = audioService.exclusiveModeEnabled
          ? 'WASAPI Exclusive'
          : 'WASAPI Shared';
    } else if (Platform.isMacOS) {
      aaudioFormatDesc = audioService.exclusiveModeEnabled
          ? 'CoreAudio Exclusive'
          : 'Core Audio';
    } else if (Platform.isLinux) {
      aaudioFormatDesc = 'ALSA / PulseAudio';
    } else {
      aaudioFormatDesc = 'N/A';
    }

    final isExclusiveOnWindows = Platform.isWindows && audioService.exclusiveModeEnabled;
    final isExclusiveOnMacOS = Platform.isMacOS && audioService.exclusiveModeEnabled;

    if (Platform.isAndroid) {
      if (audioService.playerState.processingState != ProcessingState.idle) {
        decoder = isHiResActive ? 'Hi-Res ExoPlayer' : 'ExoPlayer (just_audio)';
        output = hiResRouting.routed
            ? 'USB Native (AudioTrack)'
            : 'Android AudioTrack';

      } else {
        decoder = 'Idle';
        output = '—';
      }
    } else if (Platform.isIOS) {
      decoder = 'AVPlayer (AudioQueue)';
      output = 'Core Audio';
    } else if (Platform.isMacOS) {
      decoder = 'AVPlayer (AudioUnit)';
      output = isExclusiveOnMacOS ? 'CoreAudio Exclusive' : 'Core Audio';

    } else if (Platform.isWindows) {
      decoder = 'just_audio (WASAPI)';
      output = isExclusiveOnWindows
          ? 'WASAPI Exclusive (bit-perfect)'
          : 'WASAPI Shared';

    } else if (Platform.isLinux) {
      decoder = 'just_audio';
      output = 'ALSA / PulseAudio';
    } else {
      decoder = 'Unknown';
      output = 'Unknown';
    }

    String? deviceName;
    if (Platform.isAndroid) {
      deviceName = switch (activeDeviceType) {
        'usb_dac' => 'USB DAC (routed)',
        'usb_detected' => 'USB DAC (not routed)',
        'wired_headphones' => 'Wired Headphones',
        'bluetooth' => 'Bluetooth',
        'builtin' => 'Built-in Speaker',
        _ when hiResRouting.routed && hiResIsPlaying => 'USB DAC',
        _ when activeDeviceType == '' => 'Built-in Speaker',
        _ => activeDeviceType.isNotEmpty ? activeDeviceType : 'Built-in Speaker',
      };
    } else if (Platform.isIOS) {
      deviceName = 'iPhone / iPad';
    } else if (Platform.isWindows) {
      if (isExclusiveOnWindows) {
        deviceName = 'WASAPI Exclusive Device';
      } else if (activeDeviceType.isNotEmpty) {
        deviceName = activeDeviceType == 'wired_headphones'
            ? 'Headphones'
            : activeDeviceType == 'builtin'
                ? 'Built-in Speaker'
                : activeDeviceType;
      } else {
        deviceName = 'Default Output';
      }
    } else if (Platform.isLinux) {
      deviceName = activeDeviceType.isNotEmpty
          ? activeDeviceType
          : 'Default ALSA Device';
    } else if (Platform.isMacOS) {
      deviceName = isExclusiveOnMacOS
          ? 'CoreAudio Exclusive Device'
          : activeDeviceType.isNotEmpty
              ? activeDeviceType
              : 'Built-in Output';
    }

    return _SectionCard(
      icon: Icons.speaker,
      title: 'Audio Chain',
      cs: cs,
      tt: tt,
      children: [
        _FlowRow(
          icon: Icons.memory, label: 'Engine', value: decoder,
          cs: cs, tt: tt,
        ),
        _FlowArrow(cs: cs),
        _FlowRow(
          icon: Icons.router, label: 'Path', value: output,
          cs: cs, tt: tt,
        ),
        _FlowArrow(cs: cs),
        _FlowRow(
          icon: Icons.speaker_group, label: 'Device', value: deviceName ?? '—',
          cs: cs, tt: tt,
        ),
        const SizedBox(height: 4),
        if (usbDacNameValue.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Icon(Icons.usb, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('USB DAC', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 6),
                hiResRouting.routed
                    ? _MiniChip(usbDacNameValue, cs.primaryContainer, cs.onPrimaryContainer)
                    : _MiniChip('$usbDacNameValue (not routed)', cs.surfaceContainerHighest, cs.onSurfaceVariant),
              ],
            ),
          ),
        // libusb USB DAC status row
        if (libusbState.initialized)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Icon(Icons.usb, size: 13,
                    color: libusbState.dacActive
                        ? const Color(0xFF4CAF50)
                        : cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('libusb DAC', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 6),
                libusbState.dacActive
                    ? _MiniChip('${libusbState.deviceName} (bit-perfect)',
                        const Color(0xFF4CAF50).withValues(alpha: 0.15),
                        const Color(0xFF4CAF50))
                    : libusbState.dacConnected
                        ? _MiniChip('Connected (idle)',
                            cs.surfaceContainerHighest, cs.onSurfaceVariant)
                        : _MiniChip('Not connected',
                            cs.surfaceContainerHighest, cs.onSurfaceVariant),
              ],
            ),
          ),
        const SizedBox(height: 2),
        _InfoRow(
          label: 'Audio Mode',
          value: aaudioFormatDesc,
          cs: cs, tt: tt,
          valueColor: exclusiveState.aaudioExclusive
              ? const Color(0xFF4CAF50)
              : aaudioFormatDesc.contains('Exclusive')
                  ? cs.primary
                  : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: _BitPerfectIndicator(cs: cs, tt: tt),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// DSP section — watches audioPlayerControllerProvider.
// ═══════════════════════════════════════════════
class _DspSectionCard extends ConsumerWidget {
  const _DspSectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioState = ref.watch(audioPlayerControllerProvider);
    final eqService = EqualizerService.instance;
    final audioService = AudioPlayerService.instance;
    final currentGain = audioService.currentReplayGain;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return _SectionCard(
      icon: Icons.tune,
      title: 'DSP',
      cs: cs,
      tt: tt,
      children: [
        _ToggleRow(
          icon: Icons.equalizer,
          label: 'Equalizer',
          enabled: eqService.state.enabled,
          value: eqService.state.enabled
              ? _formatPresetName(eqService.state.activePresetId)
              : null,
          cs: cs, tt: tt,
        ),
        _ToggleRow(
          icon: Icons.swap_horiz,
          label: 'Crossfade',
          enabled: audioState.crossfadeDuration.inMilliseconds > 0,
          value: audioState.crossfadeDuration.inMilliseconds > 0
              ? '${audioState.crossfadeDuration.inMilliseconds} ms'
              : null,
          cs: cs, tt: tt,
        ),
        _ToggleRow(
          icon: Icons.trending_up,
          label: 'ReplayGain',
          enabled: audioService.replayGainActive,
          value: currentGain?.trackGain != null
              ? '${currentGain!.trackGain!.toStringAsFixed(1)} dB'
              : null,
          cs: cs, tt: tt,
        ),
        _ToggleRow(
          icon: Icons.volume_up,
          label: 'Vol Norm',
          enabled: audioService.volumeNormalizationActive,
          cs: cs, tt: tt,
        ),
        const Divider(height: 12, indent: 12, endIndent: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Row(
            children: [
              Icon(Icons.speed, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('Volume · Speed', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const Spacer(),
              // Sub-widget dengan timer sendiri — tidak rebuild dialog utama
              _SystemVolumeWidget(
                volume: audioState.volume,
                speed: audioState.speed,
                outputDevice: Platform.isAndroid ? _getOutputDeviceType(ref) : null,
                exclusiveMode: audioService.exclusiveModeEnabled,
                cs: cs, tt: tt,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Row(
            children: [
              Icon(Icons.repeat, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('Repeat · Shuffle', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DotBadge(label: 'Repeat', active: audioState.repeatMode != LoopMode.off, cs: cs),
                  const SizedBox(width: 10),
                  _DotBadge(label: 'Shuffle', active: audioState.shuffleMode, cs: cs),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  /// Helper to read output device type without subscribing the parent.
  String? _getOutputDeviceType(WidgetRef ref) {
    final deviceTypeAsync = ref.read(activeOutputDeviceProvider);
    return deviceTypeAsync.valueOrNull;
  }
}

// ═══════════════════════════════════════════════
// Status section — watches exclusiveAudioStateProvider + playerStateProvider.
// ═══════════════════════════════════════════════
class _StatusSectionCard extends ConsumerWidget {
  const _StatusSectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerStateValue = ref.watch(playerStateProvider).valueOrNull;
    final audioService = AudioPlayerService.instance;
    final exclusiveStateAsync = ref.watch(exclusiveAudioStateProvider);
    final exclusiveState = exclusiveStateAsync.when(
      data: (s) => s,
      loading: () => const ExclusiveModeState(),
      error: (_, __) => const ExclusiveModeState(),
    );
    final hiResRoutingAsync = ref.watch(hiResUsbRoutingProvider);
    final hiResRouting = hiResRoutingAsync.when(
      data: (r) => r,
      loading: () => const UsbRoutingState(),
      error: (_, __) => const UsbRoutingState(),
    );

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Player state string
    String playerStateStr;
    if (playerStateValue == null ||
        audioService.playerState.processingState == ProcessingState.idle) {
      playerStateStr = 'Stopped';
    } else if (audioService.playerState.processingState ==
            ProcessingState.loading ||
        audioService.playerState.processingState == ProcessingState.buffering) {
      playerStateStr = 'Loading';
    } else if (playerStateValue.playing) {
      playerStateStr = 'Playing';
    } else {
      playerStateStr = 'Paused';
    }

    // Exclusive mode
    final isExclusiveOnAndroid = Platform.isAndroid && (exclusiveState.enabled || hiResRouting.routed);
    final isExclusiveOnWindows = Platform.isWindows && audioService.exclusiveModeEnabled;
    final isExclusiveOnMacOS = Platform.isMacOS && audioService.exclusiveModeEnabled;
    final exclusiveMode = isExclusiveOnAndroid || isExclusiveOnWindows || isExclusiveOnMacOS;

    return _SectionCard(
      icon: Icons.check_circle_outline,
      title: 'Status',
      cs: cs,
      tt: tt,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: playerStateStr == 'Playing'
                      ? const Color(0xFF4CAF50)
                      : playerStateStr == 'Paused'
                          ? cs.primary
                          : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Text('Player State', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const Spacer(),
              _StateBadge(
                label: playerStateStr,
                color: playerStateStr == 'Playing'
                    ? const Color(0xFF4CAF50)
                    : playerStateStr == 'Paused'
                        ? cs.primary
                        : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
        _ToggleRow(
          icon: Icons.volume_off,
          label: 'Exclusive Mode',
          enabled: exclusiveMode,
          value: exclusiveMode ? 'Vol Locked' : null,
          cs: cs, tt: tt,
        ),
        if (Platform.isAndroid)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: _AAudioStatusRow(cs: cs, tt: tt),
          ),
        _ToggleRow(
          icon: Icons.deblur,
          label: 'Android Mixer',
          enabled: exclusiveState.aaudioExclusive,
          value: exclusiveState.aaudioExclusive ? 'Bypassed' : null,
          cs: cs, tt: tt,
          valueActiveColor: const Color(0xFF4CAF50),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Footer text — no reactive providers.
class _InfoFooter extends StatelessWidget {
  const _InfoFooter();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Text(
        'Data collected from active audio chain',
        style: tt.bodySmall?.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

String _fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}

String _formatPresetName(String id) {
  for (final p in EqualizerService.presets) {
    if (p.id == id) return p.name;
  }
  return id == 'custom' ? 'Custom' : id;
}

// ═══════════════════════════════════════════════
// System Volume — sub-widget dengan periodic refresh sendiri
// Timer 2 detik hanya rebuild widget kecil ini, bukan seluruh dialog.
// ═══════════════════════════════════════════════
class _SystemVolumeWidget extends ConsumerStatefulWidget {
  final double volume;
  final double speed;
  final String? outputDevice;
  final bool exclusiveMode;
  final ColorScheme cs;
  final TextTheme tt;

  const _SystemVolumeWidget({
    required this.volume,
    required this.speed,
    this.outputDevice,
    this.exclusiveMode = false,
    required this.cs,
    required this.tt,
  });

  @override
  ConsumerState<_SystemVolumeWidget> createState() => _SystemVolumeWidgetState();
}

class _SystemVolumeWidgetState extends ConsumerState<_SystemVolumeWidget> {
  Map<String, int>? _systemVolume;
  Timer? _volumeTimer;

  @override
  void initState() {
    super.initState();
    _fetchSystemVolume();
    _volumeTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _fetchSystemVolume();
    });
  }

  @override
  void dispose() {
    _volumeTimer?.cancel();
    super.dispose();
  }

  void _fetchSystemVolume() {
    if (!Platform.isAndroid) return;
    ExclusiveAudioService.instance.getSystemVolume().then((vol) {
      if (mounted) {
        setState(() => _systemVolume = vol);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // In exclusive mode on Android, system volume control is locked
    // (bypassed by AAudio/WASAPI exclusive). Show app volume instead.
    final isSystemVolume = Platform.isAndroid && !widget.exclusiveMode;
    if (isSystemVolume) {
      final deviceLabel = _outputDeviceLabel(widget.outputDevice);
      final sv = _systemVolume;
      if (sv != null) {
        final maxVol = sv['maxVolume'];
        final curVol = sv['currentVolume'];
        if (maxVol != null && curVol != null && maxVol > 0) {
          final percent = (curVol / maxVol * 100).round();
          return Text('$deviceLabel ($percent%) · ${widget.speed.toStringAsFixed(2)}x',
              style: widget.tt.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: widget.cs.onSurface));
        }
      }
      return Text('$deviceLabel · ${widget.speed.toStringAsFixed(2)}x',
          style: widget.tt.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: widget.cs.onSurface));
    }
    return Text('${(widget.volume * 100).round()}%  ·  ${widget.speed.toStringAsFixed(2)}x',
        style: widget.tt.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: widget.cs.onSurface));
  }

  String _outputDeviceLabel(String? outputDevice) {
    return switch (outputDevice) {
      'builtin' => 'Speaker',
      'wired_headphones' => 'Earphone',
      'usb_dac' || 'usb_detected' => 'USB DAC',
      'bluetooth' => 'TWS',
      _ => 'Speaker',
    };
  }
}

// ═══════════════════════════════════════════════
// Title bar
// ═══════════════════════════════════════════════
class _TitleBar extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;
  const _TitleBar({required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.info_outline, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Text('Audio Info',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const Spacer(),
          SizedBox(
            width: 32, height: 32,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              iconSize: 18,
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Section card — with left accent border
// ═══════════════════════════════════════════════
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final ColorScheme cs;
  final TextTheme tt;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.cs,
    required this.tt,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: cs.primary.withValues(alpha: 0.4),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: Row(
              children: [
                Icon(icon, size: 15, color: cs.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: tt.labelLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Info row — label on left, value on right
// ═══════════════════════════════════════════════
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  final TextTheme tt;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.cs,
    required this.tt,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        children: [
          Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const Spacer(),
          Text(value,
              style: tt.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor ?? cs.onSurface,
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Flow row — for audio chain visual flow
// ═══════════════════════════════════════════════
class _FlowRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;
  final TextTheme tt;

  const _FlowRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: tt.labelSmall?.copyWith(fontSize: 9, color: cs.onSurfaceVariant, letterSpacing: 0.5)),
              Text(value, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Downward arrow connector for audio chain flow.
class _FlowArrow extends StatelessWidget {
  final ColorScheme cs;
  const _FlowArrow({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 22, top: 1, bottom: 1),
      child: Icon(Icons.arrow_downward, size: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
    );
  }
}

// ═══════════════════════════════════════════════
// Toggle row — with ON/OFF badge
// ═══════════════════════════════════════════════
class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final String? value;
  final ColorScheme cs;
  final TextTheme tt;
  final Color? valueActiveColor;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.enabled,
    this.value,
    required this.cs,
    required this.tt,
    this.valueActiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: enabled ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const Spacer(),
          _DotBadge(label: enabled ? 'ON' : 'OFF', active: enabled, cs: cs),
          if (value != null && enabled) ...[
            const SizedBox(width: 6),
            Text(value!, style: tt.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueActiveColor ?? cs.primary,
            )),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Dot badge — green/gray dot + text
// ═══════════════════════════════════════════════
class _DotBadge extends StatelessWidget {
  final String label;
  final bool active;
  final ColorScheme cs;

  const _DotBadge({
    required this.label,
    required this.active,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF4CAF50) : cs.onSurfaceVariant.withValues(alpha: 0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5,
            )),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// State badge — colored background pill
// ═══════════════════════════════════════════════
class _StateBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StateBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.3,
          )),
    );
  }
}

// ═══════════════════════════════════════════════
// Mini chip — small label with icon
// ═══════════════════════════════════════════════
class _MiniChip extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;

  const _MiniChip(this.label, this.bgColor, this.textColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: textColor,
          )),
    );
  }
}

// ═══════════════════════════════════════════════
// Format pill — colored pill for format info
// ═══════════════════════════════════════════════
class _FormatPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final bool bold;

  const _FormatPill({
    required this.label,
    required this.color,
    required this.textColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: textColor,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Bit-Perfect indicator
// ═══════════════════════════════════════════════
class _BitPerfectIndicator extends ConsumerWidget {
  final ColorScheme cs;
  final TextTheme tt;

  const _BitPerfectIndicator({required this.cs, required this.tt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(exclusiveAudioStateProvider);
    final state = stateAsync.when(
      data: (s) => s,
      loading: () => const ExclusiveModeState(),
      error: (_, __) => const ExclusiveModeState(),
    );
    String bitPerfectLabel;
    bool active;
    if (Platform.isAndroid) {
      // Check if libusb USB DAC is active first (higher priority)
      final dacActive = ref.watch(isLibusbActiveProvider);
      if (dacActive) {
        active = true;
        bitPerfectLabel = 'YES · libusb USB DAC';
      } else {
        active = state.aaudioExclusive;
        bitPerfectLabel = state.aaudioExclusive
            ? 'YES · AAudio Exclusive'
            : state.aaudioActive
                ? 'NO · AAudio Shared'
                : state.enabled
                    ? 'NO · Vol Lock only'
                    : 'NO · Android Mixer';
      }
    } else if (Platform.isWindows) {
      active = state.enabled;
      bitPerfectLabel = state.enabled
          ? 'YES · WASAPI Exclusive'
          : 'NO · WASAPI Shared';
    } else if (Platform.isMacOS) {
      active = state.enabled;
      bitPerfectLabel = state.enabled
          ? 'YES · CoreAudio Exclusive'
          : 'NO · Core Audio';
    } else if (Platform.isLinux) {
      active = false;
      bitPerfectLabel = 'N/A · ALSA / PulseAudio';
    } else if (Platform.isIOS) {
      active = false;
      bitPerfectLabel = 'N/A · Core Audio';
    } else {
      active = false;
      bitPerfectLabel = 'N/A';
    }

    return Row(
      children: [
        Icon(Icons.check_circle, size: 13,
            color: active ? const Color(0xFF4CAF50) : cs.error.withValues(alpha: 0.7)),
        const SizedBox(width: 6),
        Text('Bit-Perfect',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                : cs.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(bitPerfectLabel,
              style: TextStyle(
                fontSize: 10,
                color: active ? const Color(0xFF4CAF50) : cs.error,
                fontWeight: FontWeight.w700,
              )),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// AAudio status row
// ═══════════════════════════════════════════════
class _AAudioStatusRow extends ConsumerWidget {
  final ColorScheme cs;
  final TextTheme tt;

  const _AAudioStatusRow({required this.cs, required this.tt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(exclusiveAudioStateProvider);
    final state = stateAsync.when(
      data: (s) => s,
      loading: () => const ExclusiveModeState(),
      error: (_, __) => const ExclusiveModeState(),
    );
    final (String value, Color color) = state.aaudioExclusive
        ? ('Exclusive (bypassed)', const Color(0xFF4CAF50))
        : state.aaudioActive
            ? ('Shared', cs.primary)
            : state.aaudioAvailable
                ? ('Available', cs.onSurfaceVariant)
                : ('Unavailable', cs.onSurfaceVariant);

    return Row(
      children: [
        Icon(Icons.memory, size: 13, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('AAudio',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const Spacer(),
        _StateBadge(label: value, color: color),
      ],
    );
  }
}
