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
          _autoTargetDevice = deviceName;
        });
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
        final cleanName = name.startsWith('USB-Audio - ')
            ? name.substring('USB-Audio - '.length)
            : name;
        setState(() {
          _autoTargetDevice = cleanName;
          _usbDacConnected = true;
        });
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
          Row(

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
              ref.read(bitPerfectPlaybackProvider.notifier).toggle(v);
              if (v && _exclusiveModeEnabled) {
                await _toggleExclusiveMode(false, silent: true);
              }

              await _audioService.usbDacManager.setAutoDacEnabled(v);

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

  Future<void> _testAaudioExclusive() async {
    if (!mounted) return;
    final wasEnabled = _exclusiveModeEnabled;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Testing AAudio exclusive mode...'), duration: Duration(seconds: 1)),
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