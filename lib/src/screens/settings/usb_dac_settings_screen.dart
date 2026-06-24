import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';
import '../../services/hi_res_audio_service.dart';
import '../../services/exclusive_audio_service.dart';
import '../../services/audio_player_service.dart';
import '../../services/usb_dac_audio_manager.dart';
import '../../services/log_service.dart';
import '../../utils/snackbar_util.dart';

final _log = LogService.instance;

class UsbDacSettingsScreen extends ConsumerStatefulWidget {
  const UsbDacSettingsScreen({super.key});

  @override
  ConsumerState<UsbDacSettingsScreen> createState() =>
      _UsbDacSettingsScreenState();
}

class _UsbDacSettingsScreenState
    extends ConsumerState<UsbDacSettingsScreen> {
  final _hiRes = HiResAudioService.instance;
  final _exclusive = ExclusiveAudioService.instance;
  final _audioService = AudioPlayerService.instance;

  bool _exclusiveModeEnabled = false;
  bool _aaudioExclusive = false;
  bool _aaudioActive = false;

  bool _usbDacConnected = false;
  String _autoTargetDevice = '';

  StreamSubscription? _exclusiveStateSub;
  StreamSubscription? _usbAttachedSub;
  StreamSubscription? _usbDetachedSub;
  StreamSubscription? _usbDevicesSub;

  @override
  void initState() {
    super.initState();

    _loadInitialState();
    _exclusiveStateSub = _exclusive.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _exclusiveModeEnabled = state.enabled;
          _aaudioActive = state.aaudioActive;
          _aaudioExclusive = state.aaudioExclusive;
        });
      }
    });
    _usbDevicesSub = _hiRes.usbDevicesStream.listen((devices) {
      if (!mounted) return;
      final hasDac = devices.isNotEmpty;
      final deviceName = devices.isNotEmpty ? devices.first.productName : '';
      if (hasDac && !_usbDacConnected) {
        _log.info('USB DAC connected: $deviceName', tag: 'USB');
        setState(() {
          _usbDacConnected = true;
          // Use deviceName from HiResAudio (no "USB-Audio - " prefix)
          _autoTargetDevice = deviceName;
        });
<<<<<<< HEAD
        if (!_exclusiveModeEnabled) {
          _toggleExclusiveMode(true);
        }
=======
        _autoRouteToUsb();
>>>>>>> 96f3b38
      } else if (!hasDac && _usbDacConnected) {
        _log.info('USB DAC disconnected', tag: 'USB');
        setState(() {
          _usbDacConnected = false;
          _autoTargetDevice = '';
        });
      } else if (hasDac && _usbDacConnected) {
        setState(() => _autoTargetDevice = deviceName);
      }
    });
    _usbAttachedSub = _exclusive.usbAttachedStream.listen((name) {
      if (mounted) {
        // Strip "USB-Audio - " prefix if present to match HiResAudio format
        final cleanName = name.startsWith('USB-Audio - ')
            ? name.substring('USB-Audio - '.length)
            : name;
        setState(() {
          _autoTargetDevice = cleanName;
          _usbDacConnected = true;
        });
<<<<<<< HEAD
        if (!_exclusiveModeEnabled) {
          _toggleExclusiveMode(true);
        }
=======
        _autoRouteToUsb();
>>>>>>> 96f3b38
      }
    });
    _usbDetachedSub = _exclusive.usbDetachedStream.listen((_) {
      if (mounted) {
        setState(() {
          _autoTargetDevice = '';
          _usbDacConnected = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _exclusiveStateSub?.cancel();
    _usbAttachedSub?.cancel();
    _usbDetachedSub?.cancel();
    _usbDevicesSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    final devices = await _hiRes.getUsbAudioDevices();
    if (mounted) {
      final hasDac = devices.isNotEmpty;
      setState(() {
        _usbDacConnected = hasDac;
        if (hasDac && _autoTargetDevice.isEmpty) {
          _autoTargetDevice = devices.first.productName;
        }
        _exclusiveModeEnabled = _exclusive.enabled;
        _aaudioActive = _exclusive.aaudioActive;
        _aaudioExclusive = _exclusive.aaudioExclusive;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (!Platform.isAndroid) {
      return Scaffold(
        appBar: AppBar(title: const Text('USB DAC (Beta)')),
        body: const Center(child: Text('USB DAC mode is only available on Android.')),
      );
    }
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(s),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildConnectionCard(s),
                    const SizedBox(height: 16),
                    _buildAudioPathFlow(s),
                    const SizedBox(height: 16),
                    _buildFeatureToggles(s),
                    const SizedBox(height: 16),
                    _buildTestSection(s),
                    const SizedBox(height: 16),
                    _buildInfoBanner(s),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // AppBar
  // ──────────────────────────────────────────────

  Widget _buildAppBar(S s) {
    final cs = Theme.of(context).colorScheme;
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      title: Text(
        'USB DAC',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 22,
          color: cs.onSurface,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primaryContainer.withValues(alpha: 0.6),
                cs.surface,
                cs.surface,
              ],
            ),
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(32),
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Connection Card
  // ──────────────────────────────────────────────

  Widget _buildConnectionCard(S s) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = ref.watch(bitPerfectPlaybackProvider);
    final usbDacRoutingActive = settings.enabled && _usbDacConnected;
    final isBitPerfect = _aaudioExclusive || usbDacRoutingActive;

    final statusColor = _usbDacConnected
        ? (isBitPerfect ? const Color(0xFF4CAF50) : const Color(0xFFFFA000))
        : cs.onSurfaceVariant.withValues(alpha: 0.3);

    final statusLabel = _usbDacConnected
        ? (isBitPerfect ? 'Bit-Perfect' : 'Connected')
        : 'Disconnected';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cs.surfaceContainerLow,
        border: Border.all(
          color: _usbDacConnected
              ? cs.primary.withValues(alpha: 0.25)
              : cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _usbDacConnected
                  ? cs.primary.withValues(alpha: 0.1)
                  : cs.onSurfaceVariant.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _usbDacConnected ? Icons.usb : Icons.usb_off,
              size: 20,
              color: _usbDacConnected
                  ? cs.primary
                  : cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _usbDacConnected
                            ? (_autoTargetDevice.isNotEmpty
                                ? _autoTargetDevice
                                : 'USB DAC')
                            : 'No USB DAC',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _usbDacConnected
                      ? (usbDacRoutingActive
                          ? 'USB DAC Routing active'
                          : (_exclusiveModeEnabled
                              ? 'AAudio exclusive mode'
                              : 'USB DAC detected'))
                      : 'Connect a USB DAC',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Audio Signal Path (Compact Card Row)
  // ──────────────────────────────────────────────

  Widget _buildAudioPathFlow(S s) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = ref.watch(bitPerfectPlaybackProvider);
    final usbDacRoutingActive = settings.enabled && _usbDacConnected;
    final isBitPerfect = _aaudioExclusive || usbDacRoutingActive;

    String pathDetail;
    if (_aaudioExclusive) {
      pathDetail = 'AAudio';
    } else if (usbDacRoutingActive) {
      pathDetail = 'USB Direct';
    } else if (_exclusiveModeEnabled && _aaudioActive) {
      pathDetail = 'AAudio Shared';
    } else {
      pathDetail = 'AudioTrack';
    }

    final stages = [
      const _AudioStage(icon: Icons.audiotrack, label: 'Player', detail: 'ExoPlayer', active: true),
      const _AudioStage(icon: Icons.memory, label: 'Codec', detail: 'Decoder', active: true),
      _AudioStage(
        icon: isBitPerfect ? Icons.flash_on : Icons.merge_type,
        label: isBitPerfect ? 'Direct' : 'Mixer',
        detail: pathDetail,
        active: isBitPerfect || _exclusiveModeEnabled,
      ),
      _AudioStage(
        icon: Icons.speaker,
        label: 'Output',
        detail: _usbDacConnected ? 'USB DAC' : 'Speaker',
        active: _usbDacConnected,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cs.surfaceContainerLow,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
<<<<<<< HEAD
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.monitor_heart, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Device Status',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                const Spacer(),
                // Connection LED
                _StatusDot(
                  color: _usbDacConnected
                      ? (_aaudioExclusive ? Colors.green : const Color(0xFFFFA000))
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  label: _usbDacConnected
                      ? (_aaudioExclusive ? 'Active' : 'Connected')
                      : 'Disconnected',
                  textTheme: theme.textTheme,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── USB DAC Device Info ──
          if (_usbDacConnected) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.usb, size: 16, color: colorScheme.primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Text('Device',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  // Device picker (dropdown if multiple devices)
                  Expanded(
                    child: _DevicePicker(
                      currentName: _autoTargetDevice,
                      onChanged: (name) {
                        setState(() => _autoTargetDevice = name);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],

          // ── Status Rows with Dots ──
          _StatusDotRow(
            label: 'Exclusive Mode',
            dotColor: _exclusiveModeEnabled ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
            value: _exclusiveModeEnabled ? 'Active (Vol Locked)' : 'Off',
            textTheme: theme.textTheme,
            colorScheme: colorScheme,
          ),
          _StatusDotRow(
            label: 'Volume Lock',
            dotColor: _volumeLocked ? Colors.green : colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
            value: _volumeLocked ? 'Active' : 'Inactive',
            textTheme: theme.textTheme,
            colorScheme: colorScheme,
          ),
          _StatusDotRow(
            label: 'AAudio',
            dotColor: _aaudioExclusive
                ? Colors.green
                : _aaudioActive
                    ? Colors.orange
                    : _aaudioAvailable
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
            value: _aaudioExclusive
                ? 'Exclusive (mixer bypassed)'
                : _aaudioActive
                    ? 'Shared'
                    : _aaudioAvailable
                        ? 'Available'
                        : 'Unavailable',
            textTheme: theme.textTheme,
            colorScheme: colorScheme,
          ),
          _StatusDotRow(
            label: 'Android Mixer',
            dotColor: _aaudioExclusive ? Colors.green : colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
            value: _aaudioExclusive ? 'Bypassed (AAudio)' : 'Active',
            textTheme: theme.textTheme,
            colorScheme: colorScheme,
          ),
          _StatusDotRow(
            label: 'Bit-Perfect',
            dotColor: _aaudioExclusive
                ? Colors.green
                : _aaudioActive
                    ? Colors.orange
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
            value: _aaudioExclusive
                ? 'YES — Exclusive'
                : _aaudioActive
                    ? 'NO — Shared mode'
                    : _exclusiveModeEnabled
                        ? 'NO — Vol Lock only'
                        : 'NO — Android Mixer',
            textTheme: theme.textTheme,
            colorScheme: colorScheme,
          ),
          _StatusDotRow(
            label: 'DSP Bypass',
            dotColor: _exclusiveModeEnabled ? Colors.green : colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
            value: _exclusiveModeEnabled ? 'Active' : 'Inactive',
            textTheme: theme.textTheme,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // AAudio Exclusive Mode Card
  // ──────────────────────────────────────────────

  Widget _buildAaudioExclusiveCard(BuildContext context, WidgetRef ref, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.high_quality, color: colorScheme.primary, size: 22),
            ),
            title: Row(
              children: [
                const Expanded(child: Text('AAudio Exclusive Mode')),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  onPressed: () => _showAaudioInfoDialog(context, s),
                  tooltip: 'Info',
                ),
              ],
            ),              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _exclusiveModeEnabled
                        ? _aaudioExclusive
                            ? 'Bit-perfect active — mixer bypassed'
                            : _aaudioActive
                                ? 'AAudio shared mode (exclusive not granted)'
                                : 'Volume locked (no AAudio stream)'
                        : 'Android AudioTrack (mixer active)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _exclusiveModeEnabled
                          ? colorScheme.primary.withValues(alpha: 0.8)
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_exclusiveModeEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 12,
                              color: Color(0xFF4CAF50)),
                          const SizedBox(width: 4),
                          Text(
                            'DSP bypassed · Pure PCM',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF4CAF50),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            // Disable toggle when no USB DAC connected
            value: _exclusiveModeEnabled,
            onChanged: (!_usbDacConnected && !_exclusiveModeEnabled)
                ? null
                : (value) async {
              HapticFeedback.lightImpact();
              if (value) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('AAudio Exclusive Mode'),
                    content: const Text(
                      'When enabled:\n'
                      '• System volume locked at max\n'
                      '• Volume controlled only via app slider\n'
                      '• AAudio exclusive stream requested\n'
                      '• Android mixer bypassed (if exclusive granted)\n'
                      '• True bit-perfect output\n\n'
                      '⚠️ May not work on all devices.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(s.cancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(s.enable),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
              }

              await _toggleExclusiveMode(value);
            },
          ),
        ],
      ),
    );
  }

  void _showAaudioInfoDialog(BuildContext context, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
=======
          Row(
>>>>>>> 96f3b38
            children: [
              Icon(Icons.route, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Audio Signal Path',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(stages.length * 2 - 1, (i) {
              if (i.isOdd) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 14,
                    color: stages[i ~/ 2].active && stages[(i ~/ 2) + 1].active
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.15),
                  ),
                );
              }
              final idx = i ~/ 2;
              final stage = stages[idx];
              final active = stage.active;
              final fg = active ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.3);
              return Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: active ? cs.primary.withValues(alpha: 0.08) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? cs.primary.withValues(alpha: 0.3)
                          : cs.outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(stage.icon, size: 18, color: fg),
                      const SizedBox(height: 4),
                      Text(
                        stage.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                      Text(
                        stage.detail,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 8,
                          color: fg.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Feature Toggles
  // ──────────────────────────────────────────────

  Widget _buildFeatureToggles(S s) {
    final cs = Theme.of(context).colorScheme;
    final settings = ref.watch(bitPerfectPlaybackProvider);
    final usbDacRoutingActive = settings.enabled && _usbDacConnected;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cs.surfaceContainerLow,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          _ModernToggleTile(
            icon: Icons.flash_on,
            title: 'AAudio Exclusive Mode',
            subtitle: usbDacRoutingActive
                ? 'Not needed \u2014 USB DAC Routing active'
                : _exclusiveModeEnabled
                    ? (_aaudioExclusive
                        ? 'Volume locked \u00B7 Mixer bypassed'
                        : _aaudioActive
                            ? 'AAudio shared mode'
                            : 'Volume locked')
                    : 'Android AudioTrack (mixer active)',
            trailing: IconButton(
              icon: const Icon(Icons.info_outline, size: 18),
              onPressed: () => _showInfoSheet(context, s, isAAudio: true),
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            value: _exclusiveModeEnabled,
            onChanged: !usbDacRoutingActive && (_usbDacConnected || _exclusiveModeEnabled)
                ? (v) async {
                    HapticFeedback.lightImpact();
                    if (v && mounted) {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          title: const Text('AAudio Exclusive Mode'),
                          content: const Text(
                            '• System volume locked at max\n'
                            '• Volume controlled via app slider\n'
                            '• AAudio exclusive stream requested\n'
                            '• Android mixer bypassed (if granted)\n'
                            '• True bit-perfect output\n\n'
                            'May not work on all devices.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: Text(s.cancel),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: Text(s.enable),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                    }
                    await _toggleExclusiveMode(v);
                  }
                : null,
            colorScheme: cs,
          ),
          const Divider(height: 1, indent: 64, endIndent: 16),
          _ModernToggleTile(
            icon: Icons.usb,
            title: 'USB DAC Routing',
            subtitle: settings.enabled
                ? 'Routing to ${_autoTargetDevice.isNotEmpty ? _autoTargetDevice : "USB DAC"}'
                : 'Audio via system default output',
            trailing: IconButton(
              icon: const Icon(Icons.info_outline, size: 18),
              onPressed: () => _showInfoSheet(context, s, isAAudio: false),
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            value: settings.enabled,
            onChanged: (v) async {
              HapticFeedback.lightImpact();
              if (v && mounted) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: Text(s.bitPerfectPlayback),
                    content: Text(s.bitPerfectPlaybackConfirmDesc),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(s.cancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(s.enable),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
              }
              if (v) {
                final devices = await _hiRes.getUsbAudioDevices();
                if (devices.isNotEmpty) {
                  final d = devices.first;
                  await _hiRes.setUseLibusbSink(true);
                  await _hiRes.release();
                  ref.read(bitPerfectPlaybackProvider.notifier).setPreferredDevice(d.id);
                }
              } else {
                await _hiRes.setUseLibusbSink(false);
                await _hiRes.release();
              }
<<<<<<< HEAD

              ref.read(bitPerfectPlaybackProvider.notifier).toggle(value);
              // Sync with libusb USB DAC manager
              UsbDacAudioManager.instance.setAutoDacEnabled(value);
              if (context.mounted) {
                SnackBarUtil.showInfo(
                  context,
                  value
                      ? s.bitPerfectPlaybackEnabled
                      : s.bitPerfectPlaybackDisabled,
                );
=======
              ref.read(bitPerfectPlaybackProvider.notifier).toggle(v);
              if (v && _exclusiveModeEnabled) {
                await _toggleExclusiveMode(false, silent: true);
>>>>>>> 96f3b38
              }
              if (!mounted) return;
              SnackBarUtil.showInfo(
                context,
                v ? s.bitPerfectPlaybackEnabled : s.bitPerfectPlaybackDisabled,
              );
            },
            colorScheme: cs,
          ),
          if (settings.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.usb, size: 14, color: cs.primary.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _autoTargetDevice.isNotEmpty
                          ? _autoTargetDevice
                          : 'No device selected',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _autoTargetDevice.isNotEmpty
                                ? cs.primary
                                : cs.onSurfaceVariant,
                            fontWeight:
                                _autoTargetDevice.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_autoTargetDevice.isNotEmpty) const Icon(Icons.check_circle, size: 14, color: Color(0xFF4CAF50)),
                ],
              ),
            ),
        ],
      ),
    );
  }

<<<<<<< HEAD


  /// Toggle exclusive mode on/off, handling the full flow.
  ///
  /// If [silent] is true, skips the confirmation snackbar (used by Quick Test).
  Future<void> _toggleExclusiveMode(bool enable, {bool silent = false}) async {
    await _audioService.setExclusiveMode(enable);
    if (!mounted) return;
    setState(() {
      _exclusiveModeEnabled = enable;
      _volumeLocked = enable;
    });

    if (enable) {
      final status = await _exclusive.getStatus();
      if (mounted) {
        setState(() {
          _aaudioActive = status.aaudioActive;
          _aaudioExclusive = status.aaudioExclusive;
          _volumeLocked = status.volumeLocked;
        });
      }
    } else {
      setState(() {
        _aaudioActive = false;
        _aaudioExclusive = false;
        _volumeLocked = false;
      });
    }

    final restartNeeded = enable && _audioService.playing;
    if (restartNeeded) {
      _log.info('Exclusive mode toggled while playing — restart playback for AAudio', tag: 'USB');
    }

    if (!silent && mounted) {
      final message = enable
          ? (_aaudioExclusive
              ? 'AAudio Exclusive: bit-perfect active'
              : 'Exclusive mode: volume locked')
          : 'Exclusive mode disabled';
      SnackBarUtil.showInfo(
        context,
        restartNeeded ? '$message — restart playback to apply' : message,
      );
    }
  }

  void _showUsbDacInfoDialog(BuildContext context, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.usb, size: 24, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'USB DAC Routing',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'USB DAC Routing sends audio to an external USB DAC '
                'via Android\'s AudioManager API. This allows you to:\n\n'
                '• Use an external DAC for better audio quality\n'
                '• Automatically detect connected USB audio devices\n'
                '• Select which device to route audio to\n\n'
                'Note: This uses Android\'s built-in audio routing and DOES NOT '
                'bypass the Android mixer. For true bit-perfect (mixer bypass), '
                'use the AAudio Exclusive Mode toggle above.\n\n'
                'Use both together: USB DAC Routing + AAudio Exclusive Mode '
                'for the best audio quality.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(s.gotIt),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

=======
>>>>>>> 96f3b38
  // ──────────────────────────────────────────────
  // Test Section
  // ──────────────────────────────────────────────

  Widget _buildTestSection(S s) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cs.surfaceContainerLow,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.science_outlined, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Test',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('AAudio & mixer attributes',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _ModernQuickTestTile(
            icon: Icons.high_quality,
            title: 'AAudio Exclusive Mode',
            description: 'Test if exclusive mode is granted on this device.',
            onTest: _testAaudioExclusive,
            cs: cs,
            tt: theme.textTheme,
          ),
          const Divider(height: 1, indent: 64),
          _ModernQuickTestTile(
            icon: Icons.tune,
            title: 'PreferredMixerAttributes',
            description: 'Try setting bit-perfect mixer attributes on USB DAC.',
            onTest: _testPreferredMixerAttributes,
            cs: cs,
            tt: theme.textTheme,
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Info Banner
  // ──────────────────────────────────────────────

  Widget _buildInfoBanner(S s) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cs.tertiaryContainer.withValues(alpha: 0.2),
        border: Border.all(
          color: cs.tertiary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cs.tertiary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.info_outline, size: 16, color: cs.tertiary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Beta',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.tertiary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Behavior may vary across devices. Check Audio Info sheet for real-time status.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.4,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Bottom Sheet Info
  // ──────────────────────────────────────────────

  void _showInfoSheet(BuildContext context, S s, {required bool isAAudio}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(
                    isAAudio ? Icons.high_quality : Icons.usb,
                    size: 24,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isAAudio ? 'AAudio Exclusive Mode' : 'USB DAC Routing',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isAAudio
                    ? 'Bypasses Android AudioFlinger mixer to send audio directly to your DAC at the source sample rate and bit depth.\n\n'
                        'When enabled:\n'
                        '• System volume locked at 100%\n'
                        '• Volume controlled from within app\n'
                        '• AAudio requests exclusive access\n'
                        '• If granted: mixer bypassed\n'
                        '• If denied: falls back to shared mode\n\n'
                        'Requires Android 8.1+ (API 27+). USB DACs are more likely to grant exclusive access.'
                    : 'Sends audio to an external USB DAC via Android\'s AudioManager API.\n\n'
                        '• Use an external DAC for better quality\n'
                        '• Auto-detect connected USB devices\n'
                        '• Select which device to route to\n\n'
                        'Note: Uses Android\'s built-in routing and does NOT bypass the mixer. '
                        'For true bit-perfect, also enable AAudio Exclusive Mode.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(s.gotIt),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────────
  // Actions
  // ──────────────────────────────────────────────

<<<<<<< HEAD
  const _StatusDotRow({
    required this.label,
    required this.dotColor,
    required this.value,
    required this.textTheme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // LED dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.3),
                  blurRadius: 3,
                  spreadRadius: 0.5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: dotColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// A dropdown picker for selecting from available USB DAC devices.
/// Reactively updates when USB devices are plugged/unplugged.
class _DevicePicker extends StatefulWidget {
  final String currentName;
  final ValueChanged<String> onChanged;

  const _DevicePicker({
    required this.currentName,
    required this.onChanged,
  });

  @override
  State<_DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<_DevicePicker> {
  List<UsbAudioDevice> _devices = [];
  int? _selectedDeviceId;
  StreamSubscription? _devicesSub;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    // Listen for device changes so the dropdown stays up-to-date
    _devicesSub = HiResAudioService.instance.usbDevicesStream.listen((devices) {
      if (mounted) _updateDevices(devices);
    });
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    super.dispose();
  }

  /// Update device list, deduplicating by ID, and sync selected device.
  void _updateDevices(List<UsbAudioDevice> devices) {
    // Deduplicate by ID (keep first occurrence)
    final seen = <int>{};
    final unique = <UsbAudioDevice>[];
    for (final d in devices) {
      if (seen.add(d.id)) {
        unique.add(d);
      }
    }
    setState(() {
      _devices = unique;
      // If current device name matches one of our devices, select it
      if (widget.currentName.isNotEmpty) {
        final match =
            unique.cast<UsbAudioDevice?>().firstWhere(
              (d) => d!.productName == widget.currentName,
              orElse: () => null,
            );
        if (match != null) {
          _selectedDeviceId = match.id;
        }
      }
    });
  }

  Future<void> _loadDevices() async {
    final devices = await HiResAudioService.instance.getUsbAudioDevices();
    if (mounted) {
      _updateDevices(devices);
=======
  Future<void> _autoRouteToUsb() async {
    _log.info('Auto-routing to USB DAC via UsbAudioSink...', tag: 'USB');
    await _hiRes.requestUsbPermission();
    final devices = await _hiRes.getUsbAudioDevices();
    if (devices.isNotEmpty) {
      final firstDevice = devices.first;
      await _hiRes.setUseLibusbSink(true);
      await _hiRes.release();
      ref.read(bitPerfectPlaybackProvider.notifier).setPreferredDevice(firstDevice.id);
      ref.read(bitPerfectPlaybackProvider.notifier).toggle(true);
      if (mounted) setState(() => _autoTargetDevice = firstDevice.productName);
>>>>>>> 96f3b38
    }
  }

  Future<void> _toggleExclusiveMode(bool enable, {bool silent = false}) async {
    await _audioService.setExclusiveMode(enable);
    if (!mounted) return;
    setState(() {
      _exclusiveModeEnabled = enable;
    });
    if (enable) {
      final status = await _exclusive.getStatus();
      if (mounted) {
        setState(() {
          _aaudioActive = status.aaudioActive;
          _aaudioExclusive = status.aaudioExclusive;
        });
      }
    } else {
      setState(() { _aaudioActive = false; _aaudioExclusive = false; });
    }
    if (!silent && mounted) {
      SnackBarUtil.showInfo(
        context,
        enable
            ? (_aaudioExclusive ? 'Bit-perfect active' : 'Volume locked')
            : 'Exclusive mode disabled',
      );
    }
  }

<<<<<<< HEAD
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: _devices.any((d) => d.id == _selectedDeviceId)
            ? _selectedDeviceId
            : null,
        isDense: true,
        hint: Text('Select device', style: theme.textTheme.bodySmall),
        items: _devices.map((d) {
          return DropdownMenuItem<int>(
            value: d.id,
            child: Text(
              d.productName,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (deviceId) {
          if (deviceId == null) return;
          setState(() => _selectedDeviceId = deviceId);
          // Find the device name and call back
          final match = _devices.cast<UsbAudioDevice?>().firstWhere(
            (d) => d!.id == deviceId,
            orElse: () => null,
          );
          if (match != null) {
            widget.onChanged(match.productName);
          }
        },
      ),
=======
  Future<void> _testAaudioExclusive() async {
    if (!mounted) return;
    final wasEnabled = _exclusiveModeEnabled;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Testing AAudio exclusive mode...'), duration: Duration(seconds: 1)),
>>>>>>> 96f3b38
    );
    await _toggleExclusiveMode(true, silent: true);
    await Future.delayed(const Duration(milliseconds: 500));
    final status = await _exclusive.getStatus();
    if (mounted) {
      setState(() {
        _aaudioActive = status.aaudioActive;
        _aaudioExclusive = status.aaudioExclusive;
      });
    }
    if (!wasEnabled) await _toggleExclusiveMode(false, silent: true);
    if (mounted) {
      final msg = status.aaudioExclusive
          ? 'AAudio Exclusive: GRANTED'
          : status.aaudioActive
              ? 'AAudio Shared mode'
              : 'AAudio not available';
      SnackBarUtil.showInfo(context, msg);
    }
  }

  Future<void> _testPreferredMixerAttributes() async {
    if (!mounted) return;
    if (_autoTargetDevice.isEmpty) {
      SnackBarUtil.showInfo(context, 'No USB DAC connected');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Testing PreferredMixerAttributes...'), duration: Duration(seconds: 2)),
    );
    final devices = await _hiRes.getUsbAudioDevices();
    if (devices.isEmpty) {
      if (mounted) SnackBarUtil.showInfo(context, 'No USB DAC');
      return;
    }
    final result = await _hiRes.testPreferredMixerAttributes(
      deviceId: devices.first.id, sampleRate: 48000, bitDepth: 24,
    );
    if (mounted) SnackBarUtil.showInfo(context, result);
  }
}

// ═══════════════════════════════════════════════
// Private Helper Widgets
// ═══════════════════════════════════════════════

class _AudioStage {
  final IconData icon;
  final String label;
  final String detail;
  final bool active;
  const _AudioStage({
    required this.icon,
    required this.label,
    required this.detail,
    required this.active,
  });
}

class _ModernToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final ColorScheme colorScheme;
  const _ModernToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.value,
    required this.onChanged,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: value
                  ? colorScheme.primary.withValues(alpha: 0.1)
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon,
                color: value ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                          color: value
                              ? colorScheme.primary.withValues(alpha: 0.8)
                              : colorScheme.onSurfaceVariant,
                        )),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ModernQuickTestTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTest;
  final ColorScheme cs;
  final TextTheme tt;
  const _ModernQuickTestTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTest,
    required this.cs,
    required this.tt,
  });

  @override
  State<_ModernQuickTestTile> createState() => _ModernQuickTestTileState();
}

class _ModernQuickTestTileState extends State<_ModernQuickTestTile> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, size: 18, color: widget.cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    style: widget.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(widget.description,
                    style: widget.tt.bodySmall?.copyWith(
                        color: widget.cs.onSurfaceVariant, height: 1.4)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: _testing
                      ? SizedBox(
                          width: 32,
                          height: 32,
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: widget.cs.primary,
                            ),
                          ),
                        )
                      : AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              setState(() => _testing = true);
                              widget.onTest();
                              await Future.delayed(const Duration(milliseconds: 1500));
                              if (mounted) setState(() => _testing = false);
                            },
                            icon: const Icon(Icons.play_arrow, size: 14),
                            label: Text('Run', style: widget.tt.labelSmall),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              visualDensity: VisualDensity.compact,
                              side: BorderSide(
                                  color: widget.cs.primary.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
