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

/// USB DAC (Beta) settings screen.
///
/// Consolidates all USB DAC and AAudio exclusive mode features:
/// - USB DAC device detection and routing
/// - AAudio exclusive mode toggle (bit-perfect output, mixer bypass)
/// - Real-time status display (AAudio exclusive/active, mixer bypassed)
class UsbDacSettingsScreen extends ConsumerStatefulWidget {
  const UsbDacSettingsScreen({super.key});

  @override
  ConsumerState<UsbDacSettingsScreen> createState() => _UsbDacSettingsScreenState();
}

class _UsbDacSettingsScreenState extends ConsumerState<UsbDacSettingsScreen> {
  final _hiRes = HiResAudioService.instance;
  final _exclusive = ExclusiveAudioService.instance;
  final _audioService = AudioPlayerService.instance;

  bool _exclusiveModeEnabled = false;
  bool _aaudioExclusive = false;
  bool _aaudioActive = false;
  bool _aaudioAvailable = false;
  bool _volumeLocked = false;
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

    // Listen for exclusive mode state changes
    _exclusiveStateSub = _exclusive.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _exclusiveModeEnabled = state.enabled;
          _volumeLocked = state.volumeLocked;
          _aaudioAvailable = state.aaudioAvailable;
          _aaudioActive = state.aaudioActive;
          _aaudioExclusive = state.aaudioExclusive;
        });
      }
    });

    // Listen for USB device list changes from native (hotplug auto-detection)
    _usbDevicesSub = _hiRes.usbDevicesStream.listen((devices) {
      if (!mounted) return;
      final hasDac = devices.isNotEmpty;
      final deviceName =
          devices.isNotEmpty ? devices.first.productName : '';

      _log.info('USB devices auto-refresh: ${devices.length} device(s)',
          tag: 'USB');

      if (hasDac && !_usbDacConnected) {
        // USB DAC was just plugged in
        _log.info('USB DAC connected: $deviceName', tag: 'USB');
        setState(() {
          _usbDacConnected = true;
          _autoTargetDevice = deviceName;
        });
        _autoRouteToUsb();
        if (!_exclusiveModeEnabled) {
          _toggleExclusiveMode(true);
        }
      } else if (!hasDac && _usbDacConnected) {
        // USB DAC was just unplugged
        _log.info('USB DAC disconnected', tag: 'USB');
        setState(() {
          _usbDacConnected = false;
          _autoTargetDevice = '';
        });
        if (_exclusiveModeEnabled) {
          _toggleExclusiveMode(false);
        }
      } else if (hasDac && _usbDacConnected) {
        // Same device still connected, just update name if changed
        setState(() {
          _autoTargetDevice = deviceName;
        });
      }
    });

    // Listen for USB attach/detach from exclusive plugin (backup)
    _usbAttachedSub = _exclusive.usbAttachedStream.listen((name) {
      if (mounted) {
        setState(() {
          _autoTargetDevice = name;
          _usbDacConnected = true;
        });
        _autoRouteToUsb();
        if (!_exclusiveModeEnabled) {
          _toggleExclusiveMode(true);
        }
      }
    });
    _usbDetachedSub = _exclusive.usbDetachedStream.listen((_) {
      if (mounted) {
        setState(() {
          _autoTargetDevice = '';
          _usbDacConnected = false;
        });
        if (_exclusiveModeEnabled) {
          _toggleExclusiveMode(false);
        }
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
        _volumeLocked = _exclusive.volumeLocked;
        _aaudioAvailable = _exclusive.aaudioAvailable;
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
        body: const Center(
          child: Text('USB DAC mode is only available on Android.'),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.medium(
            title: Text('USB DAC (Beta)'),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // ── Device Status Card ──
                    _buildDeviceStatusCard(context, ref, s),
                    const SizedBox(height: 16),

                    // ── Audio Path Diagram ──
                    _buildAudioPathDiagram(context, ref, s),
                    const SizedBox(height: 16),

                    // ── AAudio Exclusive Mode Card ──
                    _buildAaudioExclusiveCard(context, ref, s),
                    const SizedBox(height: 16),

                    // ── USB DAC Routing Card ──
                    _buildUsbDacRoutingCard(context, ref, s),
                    const SizedBox(height: 16),

                    // ── Quick Test Panel ──
                    _buildQuickTestPanel(context, ref, s),
                    const SizedBox(height: 16),

                    // ── Info Banner ──
                    _buildInfoBanner(context, s),
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
  // Device Status Card
  // ──────────────────────────────────────────────

  Widget _buildDeviceStatusCard(BuildContext context, WidgetRef ref, S s) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                        if (name.isNotEmpty) {
                          _autoRouteToUsb();
                        }
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
                  Icon(Icons.high_quality, size: 24, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'AAudio Exclusive Mode',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'AAudio Exclusive Mode bypasses the Android AudioFlinger mixer '
                'to send audio data directly to your device\'s DAC at the source '
                'sample rate and bit depth — delivering true bit-perfect output.\n\n'
                'When enabled:\n'
                '• System volume is locked at 100% (hardware buttons are disabled)\n'
                '• Volume is controlled from within the app\n'
                '• AAudio requests exclusive access to the audio device\n'
                '• If exclusive access is granted → mixer is bypassed\n'
                '• If exclusive access is denied → falls back to shared mode\n\n'
                'Note: Requires Android 8.1+ (API 27+). Not all devices support '
                'exclusive mode, especially on built-in speakers — USB DACs '
                'are more likely to grant exclusive access.',
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

  // ──────────────────────────────────────────────
  // USB DAC Routing Card
  // ──────────────────────────────────────────────

  Widget _buildUsbDacRoutingCard(BuildContext context, WidgetRef ref, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = ref.watch(bitPerfectPlaybackProvider);

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
              child: Icon(Icons.usb, color: colorScheme.primary, size: 22),
            ),
            title: Row(
              children: [
                const Expanded(child: Text('USB DAC Routing')),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  onPressed: () => _showUsbDacInfoDialog(context, s),
                  tooltip: 'Info',
                ),
              ],
            ),
            subtitle: Text(
              settings.enabled
                  ? 'Routing audio to USB DAC'
                  : 'Audio via system default output',
              style: theme.textTheme.bodySmall?.copyWith(
                color: settings.enabled
                    ? colorScheme.primary.withValues(alpha: 0.8)
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            value: settings.enabled,
            onChanged: (value) async {
              HapticFeedback.lightImpact();
              if (value) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(s.bitPerfectPlayback),
                    content: Text(s.bitPerfectPlaybackConfirmDesc),
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

              if (value) {
                _log.info('Enabling USB DAC routing — discovering devices...', tag: 'USB');
                final devices = await _hiRes.getUsbAudioDevices();
                _log.info('Found ${devices.length} USB audio device(s)', tag: 'USB');

                if (devices.isNotEmpty) {
                  final firstDevice = devices.first;
                  _log.info('Routing to ${firstDevice.productName}...', tag: 'USB');
                  await _hiRes.setUsbBypassMode(true, deviceId: firstDevice.id);
                  ref.read(bitPerfectPlaybackProvider.notifier).setPreferredDevice(firstDevice.id);
                  // Pass device ID to AAudio for exclusive mode targeting
                  _exclusive.setAaudioDeviceId(firstDevice.id);
                }
              } else {
                _log.info('Disabling USB DAC routing', tag: 'USB');
                try {
                  await _hiRes.setUsbBypassMode(false);
                } catch (e) {
                  _log.warning('Failed to disable USB DAC routing: $e', tag: 'USB');
                }
              }

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
              }
            },
          ),              if (settings.enabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.usb, size: 16,
                      color: colorScheme.primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _autoTargetDevice.isNotEmpty
                          ? _autoTargetDevice
                          : s.bitPerfectPlaybackNoDevice,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _autoTargetDevice.isNotEmpty
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        fontWeight: _autoTargetDevice.isNotEmpty
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_autoTargetDevice.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.check_circle,
                          size: 14, color: Color(0xFF4CAF50)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Auto-route to the first detected USB DAC device.
  Future<void> _autoRouteToUsb() async {
    _log.info('Auto-routing to USB DAC...', tag: 'USB');
    final devices = await _hiRes.getUsbAudioDevices();
    if (devices.isNotEmpty) {
      final firstDevice = devices.first;
      _log.info('Auto-routing to ${firstDevice.productName}', tag: 'USB');
      await _hiRes.setUsbBypassMode(true, deviceId: firstDevice.id);
      ref.read(bitPerfectPlaybackProvider.notifier).setPreferredDevice(firstDevice.id);
      _exclusive.setAaudioDeviceId(firstDevice.id);
      ref.read(bitPerfectPlaybackProvider.notifier).toggle(true);
      UsbDacAudioManager.instance.setAutoDacEnabled(true);
      if (mounted) {
        setState(() => _autoTargetDevice = firstDevice.productName);
      }
    }
  }

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

  // ──────────────────────────────────────────────
  // Audio Path Diagram
  // ──────────────────────────────────────────────

  Widget _buildAudioPathDiagram(BuildContext context, WidgetRef ref, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Audio Path',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 400;
                    if (isWide) {
                      return Row(
                        children: [
                          _AudioPathNode(
                            icon: Icons.audiotrack,
                            label: 'Source',
                            detail: 'Track',
                            active: true,
                            colorScheme: colorScheme,
                            textTheme: theme.textTheme,
                          ),
                          _AudioPathArrow(colorScheme),
                          _AudioPathNode(
                            icon: Icons.memory,
                            label: 'Decoder',
                            detail: 'ExoPlayer',
                            active: true,
                            colorScheme: colorScheme,
                            textTheme: theme.textTheme,
                          ),
                          _AudioPathArrow(colorScheme),
                          _AudioPathNode(
                            icon: _aaudioExclusive
                                        ? Icons.flash_on
                                        : Icons.merge_type,
                            label: _aaudioExclusive ? 'AAudio' : 'Mixer',
                            detail: _aaudioExclusive
                                ? 'Exclusive'
                                : (_exclusiveModeEnabled && _aaudioActive)
                                    ? 'AAudio Shared'
                                    : 'Android',
                            active: _aaudioExclusive || _exclusiveModeEnabled,
                            colorScheme: colorScheme,
                            textTheme: theme.textTheme,
                            activeColor: _aaudioExclusive
                                ? Colors.green
                                : (_exclusiveModeEnabled ? Colors.orange : null),
                          ),
                          _AudioPathArrow(colorScheme),
                          _AudioPathNode(
                            icon: Icons.speaker,
                            label: 'Output',
                            detail: _usbDacConnected ? 'USB DAC' : 'Speaker',
                            active: _usbDacConnected,
                            colorScheme: colorScheme,
                            textTheme: theme.textTheme,
                            activeColor: _usbDacConnected
                                ? (_aaudioExclusive ? Colors.green : const Color(0xFFFFA000))
                                : null,
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          Row(
                            children: [
                              _AudioPathNode(
                                icon: Icons.audiotrack,
                                label: 'Source',
                                detail: 'Track',
                                active: true,
                                colorScheme: colorScheme,
                                textTheme: theme.textTheme,
                              ),
                              _AudioPathArrow(colorScheme),
                              _AudioPathNode(
                                icon: Icons.memory,
                                label: 'Decoder',
                                detail: 'ExoPlayer',
                                active: true,
                                colorScheme: colorScheme,
                                textTheme: theme.textTheme,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Spacer(),
                              _AudioPathArrow(colorScheme, vertical: true),
                              const Spacer(),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _AudioPathNode(
                                icon: _aaudioExclusive
                                        ? Icons.flash_on
                                        : Icons.merge_type,
                                label: _aaudioExclusive ? 'AAudio' : 'Mixer',
                                detail: _aaudioExclusive
                                    ? 'Exclusive'
                                    : (_exclusiveModeEnabled && _aaudioActive)
                                        ? 'AAudio Shared'
                                        : 'Android',
                                active: _aaudioExclusive || _exclusiveModeEnabled,
                                colorScheme: colorScheme,
                                textTheme: theme.textTheme,
                                activeColor: _aaudioExclusive
                                    ? Colors.green
                                    : (_exclusiveModeEnabled ? Colors.orange : null),
                              ),
                              _AudioPathArrow(colorScheme),
                              _AudioPathNode(
                                icon: Icons.speaker,
                                label: 'Output',
                                detail: _usbDacConnected ? 'USB DAC' : 'Speaker',
                                active: _usbDacConnected,
                                colorScheme: colorScheme,
                                textTheme: theme.textTheme,
                                activeColor: _usbDacConnected
                                    ? (_aaudioExclusive ? Colors.green : const Color(0xFFFFA000))
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Quick Test Panel
  // ──────────────────────────────────────────────

  Widget _buildQuickTestPanel(BuildContext context, WidgetRef ref, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        leading: CircleAvatar(
          backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(Icons.science, color: colorScheme.primary, size: 22),
        ),
        title: Text(
          'Quick Test',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Diagnose AAudio & PreferredMixerAttributes support',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        initiallyExpanded: false,
        children: [
          const Divider(height: 1),
          _QuickTestTile(
            icon: Icons.high_quality,
            title: 'Test AAudio Exclusive Mode',
            description:
                'Opens a test AAudio stream and checks if exclusive mode '
                'was granted. This tests whether your device supports '
                'AAudio exclusive mode without affecting playback.',
            onTest: () => _testAaudioExclusive(),
            colorScheme: colorScheme,
            textTheme: theme.textTheme,
          ),
          const Divider(height: 1, indent: 72),
          _QuickTestTile(
            icon: Icons.tune,
            title: 'Test PreferredMixerAttributes',
            description:
                'Attempts to set bit-perfect mixer attributes on the current '
                'USB DAC (Android 14+). This tests whether your device '
                'supports the official bit-perfect API.',
            onTest: () => _testPreferredMixerAttributes(),
            colorScheme: colorScheme,
            textTheme: theme.textTheme,
          ),
        ],
      ),
    );
  }

  Future<void> _testAaudioExclusive() async {
    if (!mounted) return;
    final wasEnabled = _exclusiveModeEnabled;

    // Show testing indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Testing AAudio exclusive mode...'),
        duration: Duration(seconds: 1),
      ),
    );

    // Temporarily enable to test
    await _toggleExclusiveMode(true, silent: true);
    await Future.delayed(const Duration(milliseconds: 500));

    final status = await _exclusive.getStatus();
    if (!mounted) return;

    setState(() {
      _aaudioActive = status.aaudioActive;
      _aaudioExclusive = status.aaudioExclusive;
      _aaudioAvailable = status.aaudioAvailable;
    });

    // Restore previous state if it was off
    if (!wasEnabled) {
      await _toggleExclusiveMode(false, silent: true);
    }

    if (!mounted) return;
    final msg = status.aaudioExclusive
        ? '✅ AAudio Exclusive: GRANTED — mixer bypassed!'
        : status.aaudioActive
            ? '⚠️ AAudio Shared: exclusive not granted'
            : '❌ AAudio not available on this device';
    SnackBarUtil.showInfo(context, msg);
  }

  Future<void> _testPreferredMixerAttributes() async {
    if (!mounted) return;
    if (_autoTargetDevice.isEmpty) {
      SnackBarUtil.showInfo(context, '⚠️ No USB DAC connected — test skipped');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Testing PreferredMixerAttributes...'),
        duration: Duration(seconds: 2),
      ),
    );
    // Get the device list to find the device ID
    final devices = await _hiRes.getUsbAudioDevices();
    if (devices.isEmpty) {
      if (mounted) {
        SnackBarUtil.showInfo(context, '❌ No USB DAC found');
      }
      return;
    }
    final device = devices.first;
    // Call the setPreferredMixerAttributes method channel directly
    final result = await _hiRes.testPreferredMixerAttributes(
      deviceId: device.id,
      sampleRate: 48000,
      bitDepth: 24,
    );
    if (!mounted) return;
    SnackBarUtil.showInfo(context, result);
  }

  // ──────────────────────────────────────────────
  // Info Banner
  // ──────────────────────────────────────────────

  Widget _buildInfoBanner(BuildContext context, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.science,
            size: 20,
            color: colorScheme.tertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Beta Notice',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.tertiary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This feature is in beta. USB DAC detection and AAudio '
                  'exclusive mode behavior may vary across devices. '
                  'If you encounter issues, please check the Audio Info '
                  'sheet for real-time status or disable the feature.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: colorScheme.onSurfaceVariant,
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

/// A small colored dot used as a status LED indicator.
class _StatusDot extends StatelessWidget {
  final Color color;
  final String label;
  final TextTheme textTheme;
  final ColorScheme colorScheme;

  const _StatusDot({
    required this.color,
    required this.label,
    required this.textTheme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// A status row with a small colored dot indicator, label, and value.
class _StatusDotRow extends StatelessWidget {
  final String label;
  final Color dotColor;
  final String value;
  final TextTheme textTheme;
  final ColorScheme colorScheme;

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
  StreamSubscription? _devicesSub;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    // Listen for device changes so the dropdown stays up-to-date
    _devicesSub = HiResAudioService.instance.usbDevicesStream.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    final devices = await HiResAudioService.instance.getUsbAudioDevices();
    if (mounted) {
      setState(() => _devices = devices);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_devices.length <= 1) {
      return Text(
        widget.currentName.isNotEmpty ? widget.currentName : 'No device',
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _devices.any((d) => d.productName == widget.currentName)
            ? widget.currentName
            : null,
        isDense: true,
        hint: Text('Select device', style: theme.textTheme.bodySmall),
        items: _devices.map((d) {
          return DropdownMenuItem(
            value: d.productName,
            child: Text(
              d.productName,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (name) {
          if (name != null) widget.onChanged(name);
        },
      ),
    );
  }
}

/// A node in the audio path diagram.
class _AudioPathNode extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final bool active;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final Color? activeColor;

  const _AudioPathNode({
    required this.icon,
    required this.label,
    required this.detail,
    required this.active,
    required this.colorScheme,
    required this.textTheme,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final fgColor = active
        ? (activeColor ?? colorScheme.primary)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active
                  ? fgColor.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? fgColor.withValues(alpha: 0.3)
                    : colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Icon(icon, size: 18, color: fgColor),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
          Text(
            detail,
            style: textTheme.labelSmall?.copyWith(
              fontSize: 8,
              color: fgColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// An arrow connector between audio path nodes.
class _AudioPathArrow extends StatelessWidget {
  final ColorScheme colorScheme;
  final bool vertical;

  const _AudioPathArrow(this.colorScheme, {this.vertical = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Icon(
        vertical ? Icons.arrow_downward : Icons.arrow_forward,
        size: 14,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
  }
}

/// A tile with a test button inside the Quick Test panel.
class _QuickTestTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTest;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _QuickTestTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTest,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  State<_QuickTestTile> createState() => _QuickTestTileState();
}

class _QuickTestTileState extends State<_QuickTestTile> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: widget.colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(widget.icon, size: 16, color: widget.colorScheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: widget.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.description,
                  style: widget.textTheme.bodySmall?.copyWith(
                    color: widget.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 30,
                  child: _testing
                      ? SizedBox(
                          width: 30,
                          height: 30,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: widget.colorScheme.primary,
                            ),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: () async {
                            setState(() => _testing = true);
                            // Run the test and wait for completion
                            widget.onTest();
                            // Give the test a moment to complete, then hide spinner
                            await Future.delayed(const Duration(milliseconds: 1500));
                            if (mounted) setState(() => _testing = false);
                          },
                          icon: const Icon(Icons.play_arrow, size: 14),
                          label: Text('Run Test',
                              style: widget.textTheme.labelSmall),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide(
                              color: widget.colorScheme.primary.withValues(alpha: 0.5),
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
