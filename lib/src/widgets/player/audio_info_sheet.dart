import 'dart:async' show Timer;
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../providers/audio_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/equalizer_service.dart';
import '../../services/hi_res_audio_service.dart';
import '../../services/audio_player_service.dart';
import '../../services/exclusive_audio_service.dart';
import '../../providers/exclusive_audio_provider.dart';
import '../../providers/usb_dac_provider.dart';
import '../../services/usb_dac_audio_manager.dart';

/// Shows the redesigned Audio Information sheet with glassmorphism,
/// staggered entry animations, and DraggableScrollableSheet.
Future<void> showAudioInfoSheet(BuildContext context, WidgetRef ref) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => const _AudioInfoSheetShell(),
  );
}

/// Shell widget — wraps the DraggableScrollableSheet and handles
/// the glassmorphism container styling.
class _AudioInfoSheetShell extends ConsumerStatefulWidget {
  const _AudioInfoSheetShell();

  @override
  ConsumerState<_AudioInfoSheetShell> createState() =>
      _AudioInfoSheetShellState();
}

class _AudioInfoSheetShellState extends ConsumerState<_AudioInfoSheetShell> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      expand: true,
      snap: true,
      snapSizes: const [0.35, 0.55, 0.88],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.surfaceContainerLowest.withValues(alpha: 0.95),
                cs.surface,
                cs.surface,
              ],
            ),
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.15),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: _AudioInfoSheetContent(
                scrollController: scrollController,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Main content — ConsumerStatefulWidget with staggered entry animations.
class _AudioInfoSheetContent extends ConsumerStatefulWidget {
  final ScrollController scrollController;

  const _AudioInfoSheetContent({required this.scrollController});

  @override
  ConsumerState<_AudioInfoSheetContent> createState() =>
      _AudioInfoSheetContentState();
}

class _AudioInfoSheetContentState extends ConsumerState<_AudioInfoSheetContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _staggerController;
  late List<Animation<double>> _sectionAnims;
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _sectionAnims = List.generate(6, (i) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(
            i * 0.1,
            0.45 + i * 0.1,
            curve: Curves.easeOutCubic,
          ),
        ),
      );
    });

    widget.scrollController.addListener(_onScroll);
    _staggerController.forward();
  }

  void _onScroll() {
    final offset = widget.scrollController.offset;
    if ((offset - _scrollOffset).abs() > 2) {
      setState(() => _scrollOffset = offset);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _staggerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ── Drag Handle ──
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),

        // ── Scrollable Content ──
        Expanded(
          child: CustomScrollView(
            controller: widget.scrollController,
            physics: const ClampingScrollPhysics(),
            slivers: [
              // ── Parallax Header ──
              SliverToBoxAdapter(
                child: _AnimatedEntry(
                  animation: _sectionAnims[0],
                  child: _ModernHeader(
                    scrollOffset: _scrollOffset,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              // ── File Section ──
              SliverToBoxAdapter(
                child: _AnimatedEntry(
                  animation: _sectionAnims[1],
                  child: const _FileSectionCard(),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // ── Audio Chain Section ──
              SliverToBoxAdapter(
                child: _AnimatedEntry(
                  animation: _sectionAnims[2],
                  child: const _AudioChainSectionCard(),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // ── DSP Section ──
              SliverToBoxAdapter(
                child: _AnimatedEntry(
                  animation: _sectionAnims[3],
                  child: const _DspSectionCard(),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // ── Status Section ──
              SliverToBoxAdapter(
                child: _AnimatedEntry(
                  animation: _sectionAnims[4],
                  child: const _StatusSectionCard(),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ── Footer ──
              SliverToBoxAdapter(
                child: _AnimatedEntry(
                  animation: _sectionAnims[5],
                  child: const _InfoFooter(),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// Animated Entry Wrapper
// ═══════════════════════════════════════════════

class _AnimatedEntry extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _AnimatedEntry({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, 24 * (1.0 - Curves.easeOutCubic.transform(animation.value))),
            child: child,
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════
// Modern Header with Parallax + Gradient
// ═══════════════════════════════════════════════

class _ModernHeader extends StatelessWidget {
  final double scrollOffset;

  const _ModernHeader({this.scrollOffset = 0});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Parallax effect: subtle opacity shift as user scrolls
    final headerOpacity = (1.0 - (scrollOffset / 100)).clamp(0.6, 1.0);
    final headerTranslate = (scrollOffset * 0.3).clamp(0.0, 30.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Opacity(
        opacity: headerOpacity,
        child: Transform.translate(
          offset: Offset(0, -headerTranslate),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primaryContainer.withValues(alpha: 0.35),
                  cs.primaryContainer.withValues(alpha: 0.08),
                  cs.surfaceContainerLow,
                ],
              ),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                // Icon with glow
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        cs.primary,
                        cs.primary.withValues(alpha: 0.7),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.info_outline, color: cs.onPrimary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Audio Information',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Real-time audio chain & format details',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                // Close button
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    color: cs.onSurfaceVariant,
                    splashRadius: 16,
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
// Section Card base — glassmorphism container
// ═══════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? accentColor;
  final ColorScheme cs;
  final TextTheme tt;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    this.accentColor,
    required this.cs,
    required this.tt,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.surfaceContainerLow.withValues(alpha: 0.92),
              cs.surfaceContainerLow.withValues(alpha: 0.6),
            ],
          ),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Accent top border
            Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.5),
                    accent.withValues(alpha: 0.25),
                  ],
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 14, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: tt.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            // Content
            ...children,
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// File section — watches currentTrackProvider, durationProvider,
// audioFormatInfoProvider.
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
      final rawName = uri.split('/').last.split('?').first.split('#').first;
      try {
        fileName = Uri.decodeComponent(rawName);
      } catch (_) {
        fileName = rawName;
      }
    }

    return _SectionCard(
      icon: Icons.audiotrack,
      title: 'File',
      cs: cs,
      tt: tt,
      accentColor: cs.tertiary,
      children: [
        if (fileName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.description, size: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      fileName,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Format pills row
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _FormatPill(
                  label: formatInfo?.codec.toUpperCase() ?? '-',
                  color: cs.tertiary.withValues(alpha: 0.7),
                  textColor: cs.onTertiary),
              if (formatInfo?.sampleRate != null)
                _FormatPill(
                    label: '${(formatInfo!.sampleRate! / 1000).toStringAsFixed(formatInfo.sampleRate! % 1000 == 0 ? 0 : 1)} kHz',
                    color: cs.primary.withValues(alpha: 0.7),
                    textColor: cs.onPrimary),
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
        _InfoRow(
          label: 'Duration',
          value: duration != null ? _fmtDuration(duration) : '—',
          cs: cs, tt: tt,
        ),
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
// Audio Chain section — watches only exclusiveAudioStateProvider.
// USB DAC and chain flow providers are isolated in sub-Consumers.
// ═══════════════════════════════════════════════
class _AudioChainSectionCard extends ConsumerWidget {
  const _AudioChainSectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioService = AudioPlayerService.instance;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final exclusiveStateAsync = ref.watch(exclusiveAudioStateProvider);
    final exclusiveState = exclusiveStateAsync.when(
      data: (s) => s,
      loading: () => const ExclusiveModeState(),
      error: (_, __) => const ExclusiveModeState(),
    );

    final String aaudioFormatDesc;
    if (Platform.isAndroid) {
      aaudioFormatDesc = exclusiveState.aaudioExclusive
          ? 'Exclusive'
          : exclusiveState.aaudioActive ? 'Shared'
          : exclusiveState.aaudioAvailable ? 'Available' : 'N/A';
    } else if (Platform.isWindows) {
      aaudioFormatDesc = audioService.exclusiveModeEnabled
          ? 'WASAPI Exclusive' : 'WASAPI Shared';
    } else if (Platform.isMacOS) {
      aaudioFormatDesc = audioService.exclusiveModeEnabled
          ? 'CoreAudio Exclusive' : 'Core Audio';
    } else if (Platform.isLinux) {
      aaudioFormatDesc = 'ALSA / PulseAudio';
    } else {
      aaudioFormatDesc = 'N/A';
    }

    return _SectionCard(
      icon: Icons.speaker,
      title: 'Audio Chain',
      cs: cs,
      tt: tt,
      accentColor: cs.primary,
      children: [
        // Flow visualization — isolated ConsumerWidget
        const _ChainFlowSection(),
        // USB DAC info — separate Consumer so USB plug/unplug doesn't rebuild the whole chain card
        Consumer(
          builder: (context, ref, child) {
            final dacNameAsync = ref.watch(activeUsbDacNameProvider);
            final name = dacNameAsync.when(
              data: (n) => n,
              loading: () => '',
              error: (_, __) => '',
            );
            final routingAsync = ref.watch(hiResUsbRoutingProvider);
            final routing = routingAsync.when(
              data: (r) => r,
              loading: () => const UsbRoutingState(),
              error: (_, __) => const UsbRoutingState(),
            );
            if (name.isEmpty) return const SizedBox.shrink();
            final routed = routing.routed;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.usb, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('USB DAC', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  routed
                      ? Flexible(
                          child: _ModernChip(name, cs.primaryContainer, cs.onPrimaryContainer))
                      : Flexible(
                          child: _ModernChip('$name (not routed)', cs.surfaceContainerHighest, cs.onSurfaceVariant)),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        // Audio mode
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
        // Bit-perfect indicator with glow
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
          child: _BitPerfectIndicator(cs: cs, tt: tt),
        ),
      ],
    );
  }
}

/// Chain flow visualization — isolated ConsumerWidget that computes
/// decoder / output / deviceName from all relevant providers.
/// Prevents the parent `_AudioChainSectionCard` from rebuilding when USB DAC
/// routing, active output device, or hi-res state changes.
class _ChainFlowSection extends ConsumerWidget {
  const _ChainFlowSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioService = AudioPlayerService.instance;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final dacNameAsync = ref.watch(activeUsbDacNameProvider);
    final usbDacNameValue = dacNameAsync.when(
      data: (name) => name,
      loading: () => '',
      error: (_, __) => '',
    );
    // libusb USB DAC state
    final routingAsync = ref.watch(hiResUsbRoutingProvider);
    final hiResRouting = routingAsync.when(
      data: (r) => r,
      loading: () => const UsbRoutingState(),
      error: (_, __) => const UsbRoutingState(),
    );
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
    final bitPerfectSettings = ref.watch(bitPerfectPlaybackProvider);

    final bool isUsbDacRouted =
        hiResRouting.routed || (bitPerfectSettings.enabled && usbDacNameValue.isNotEmpty);

    String decoder;
    String output;

    final bool isHiResActive = hiResActiveAsync.when(
      data: (active) => active,
      loading: () => hiResIsPlaying,
      error: (_, __) => hiResIsPlaying,
    );

    final isExclusiveOnWindows = Platform.isWindows && audioService.exclusiveModeEnabled;
    final isExclusiveOnMacOS = Platform.isMacOS && audioService.exclusiveModeEnabled;

    if (Platform.isAndroid) {
      if (audioService.playerState.processingState != ProcessingState.idle) {
        decoder = isHiResActive ? 'Hi-Res ExoPlayer' : 'ExoPlayer (just_audio)';
        output = isUsbDacRouted
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
        _ when isUsbDacRouted && hiResIsPlaying => 'USB DAC',
        _ when bitPerfectSettings.enabled && usbDacNameValue.isNotEmpty => 'USB DAC',
        _ when activeDeviceType == '' => 'Built-in Speaker',
        _ => activeDeviceType.isNotEmpty ? activeDeviceType : 'Built-in Speaker',
      };
    } else if (Platform.isWindows) {
      deviceName = isExclusiveOnWindows
          ? 'WASAPI Exclusive Device'
          : activeDeviceType.isNotEmpty
              ? activeDeviceType == 'wired_headphones' ? 'Headphones' : activeDeviceType
              : 'Default Output';
    } else if (Platform.isLinux) {
      deviceName = activeDeviceType.isNotEmpty
          ? activeDeviceType : 'Default ALSA Device';
    } else if (Platform.isMacOS) {
      deviceName = isExclusiveOnMacOS
          ? 'CoreAudio Exclusive Device'
          : activeDeviceType.isNotEmpty ? activeDeviceType : 'Built-in Output';
    } else {
      deviceName = 'Default Output';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: _ChainFlowVisual(
        stages: [
          _ChainStage(label: 'Engine', value: decoder, active: decoder != 'Idle', accent: cs.primary),
          _ChainStage(label: 'Path', value: output, active: isUsbDacRouted, accent: const Color(0xFF4CAF50)),
          _ChainStage(label: 'Device', value: deviceName, active: isUsbDacRouted, accent: cs.tertiary),
        ],
        cs: cs,
        tt: tt,
      ),
    );
  }
}

/// Horizontal chain flow visualization (StatelessWidget — all data passed in).
class _ChainFlowVisual extends StatelessWidget {
  final List<_ChainStage> stages;
  final ColorScheme cs;
  final TextTheme tt;

  const _ChainFlowVisual({
    required this.stages,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < stages.length; i++) ...[
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: stages[i].active
                          ? stages[i].accent.withValues(alpha: 0.15)
                          : cs.onSurfaceVariant.withValues(alpha: 0.06),
                      border: Border.all(
                        color: stages[i].active
                            ? stages[i].accent.withValues(alpha: 0.4)
                            : cs.outlineVariant.withValues(alpha: 0.15),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      i == 0 ? Icons.memory : (i == 1 ? Icons.router : Icons.speaker_group),
                      size: 14,
                      color: stages[i].active ? stages[i].accent : cs.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stages[i].label,
                    style: tt.labelSmall?.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: stages[i].active ? stages[i].accent : cs.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  Text(
                    stages[i].value.length > 12
                        ? '${stages[i].value.substring(0, 10)}…'
                        : stages[i].value,
                    style: tt.labelSmall?.copyWith(
                      fontSize: 7,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            if (i < stages.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: stages[i].active && stages[i + 1].active
                      ? cs.primary.withValues(alpha: 0.5)
                      : cs.onSurfaceVariant.withValues(alpha: 0.12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ChainStage {
  final String label;
  final String value;
  final bool active;
  final Color accent;
  const _ChainStage({
    required this.label,
    required this.value,
    required this.active,
    required this.accent,
  });
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
      accentColor: cs.secondary,
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
        const SizedBox(height: 4),
        // Divider with gradient
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.outlineVariant.withValues(alpha: 0.3),
                  cs.outlineVariant.withValues(alpha: 0.05),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Volume · Speed
        _DspDetailRow(
          icon: Icons.speed,
          label: 'Volume · Speed',
          cs: cs, tt: tt,
          child: _SystemVolumeWidget(
            volume: audioState.volume,
            speed: audioState.speed,
            outputDevice: Platform.isAndroid ? _getOutputDeviceType(ref) : null,
            exclusiveMode: audioService.exclusiveModeEnabled,
            cs: cs, tt: tt,
          ),
        ),
        // Repeat · Shuffle
        _DspDetailRow(
          icon: Icons.repeat,
          label: 'Repeat · Shuffle',
          cs: cs, tt: tt,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DotBadge(label: 'Repeat', active: audioState.repeatMode != LoopMode.off, cs: cs),
              const SizedBox(width: 10),
              _DotBadge(label: 'Shuffle', active: audioState.shuffleMode, cs: cs),
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  String? _getOutputDeviceType(WidgetRef ref) {
    final deviceTypeAsync = ref.read(activeOutputDeviceProvider);
    return deviceTypeAsync.valueOrNull;
  }
}

/// Detail row for DSP section with icon + label + custom child widget.
class _DspDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  final ColorScheme cs;
  final TextTheme tt;

  const _DspDetailRow({
    required this.icon,
    required this.label,
    required this.child,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const Spacer(),
          child,
        ],
      ),
    );
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
    final bitPerfectSettings = ref.watch(bitPerfectPlaybackProvider);
    final dacNameAsync = ref.watch(activeUsbDacNameProvider);
    final usbDacNameValue = dacNameAsync.when(
      data: (name) => name,
      loading: () => '',
      error: (_, __) => '',
    );

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final bool isUsbDacRouted =
        hiResRouting.routed || (bitPerfectSettings.enabled && usbDacNameValue.isNotEmpty);

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

    final isExclusiveOnAndroid = Platform.isAndroid && (exclusiveState.enabled || isUsbDacRouted);
    final isExclusiveOnWindows = Platform.isWindows && audioService.exclusiveModeEnabled;
    final isExclusiveOnMacOS = Platform.isMacOS && audioService.exclusiveModeEnabled;
    final exclusiveMode = isExclusiveOnAndroid || isExclusiveOnWindows || isExclusiveOnMacOS;

    return _SectionCard(
      icon: Icons.check_circle_outline,
      title: 'Status',
      cs: cs,
      tt: tt,
      accentColor: const Color(0xFF4CAF50),
      children: [
        // Player state with pulsing dot
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          child: Row(
            children: [
              _PulsingDot(
                active: playerStateStr == 'Playing',
                color: playerStateStr == 'Playing'
                    ? const Color(0xFF4CAF50)
                    : playerStateStr == 'Paused'
                        ? cs.primary
                        : cs.onSurfaceVariant,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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

/// Pulsing dot indicator for player state.
class _PulsingDot extends StatefulWidget {
  final bool active;
  final Color color;
  const _PulsingDot({required this.active, required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _anim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && old.active) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              if (widget.active)
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.3 + _anim.value * 0.4),
                  blurRadius: 2 + _anim.value * 4,
                ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════
// Footer
// ═══════════════════════════════════════════════
class _InfoFooter extends StatelessWidget {
  const _InfoFooter();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        children: [
          Container(
            width: 60,
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  cs.outlineVariant.withValues(alpha: 0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Data collected from active audio chain',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Utility functions
// ═══════════════════════════════════════════════

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
// System Volume — sub-widget with periodic refresh
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
// Shared UI Components
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14,
              color: enabled ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5)),
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
        borderRadius: BorderRadius.circular(6),
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

class _ModernChip extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;

  const _ModernChip(this.label, this.bgColor, this.textColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
    );
  }
}

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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
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
// Bit-Perfect Indicator
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
    final routingAsync = ref.watch(hiResUsbRoutingProvider);
    final hiResRouting = routingAsync.when(
      data: (r) => r,
      loading: () => const UsbRoutingState(),
      error: (_, __) => const UsbRoutingState(),
    );
    final isUsbAudioSinkActive = hiResRouting.routed;

    String bitPerfectLabel;
    bool active;
    if (Platform.isAndroid) {
      if (isUsbAudioSinkActive) {
        active = true;
        bitPerfectLabel = 'YES · USB Native (UsbAudioSink)';
      } else if (state.aaudioExclusive) {
        active = true;
        bitPerfectLabel = 'YES · AAudio Exclusive';
      } else {
        active = false;
        bitPerfectLabel = state.aaudioActive
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF4CAF50).withValues(alpha: 0.06)
            : cs.error.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active
              ? const Color(0xFF4CAF50).withValues(alpha: 0.2)
              : cs.error.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 14,
              color: active ? const Color(0xFF4CAF50) : cs.error.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Text('Bit-Perfect',
              style: tt.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: active ? const Color(0xFF4CAF50) : cs.onSurfaceVariant,
              )),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF4CAF50).withValues(alpha: 0.12)
                  : cs.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(bitPerfectLabel,
                style: TextStyle(
                  fontSize: 9,
                  color: active ? const Color(0xFF4CAF50) : cs.error,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// AAudio Status Row
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
