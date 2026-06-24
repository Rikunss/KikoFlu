import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../l10n/app_localizations.dart';
import '../download_path_settings_screen.dart';
import '../../services/cache_service.dart';
import '../../services/download_path_service.dart';
import '../../services/audio_conversion_service.dart';
import '../../services/log_service.dart';
import '../../providers/settings_provider.dart';
import '../../utils/snackbar_util.dart';

/// Downloads & Storage settings screen — MD3 consolidated section.
///
/// Features: Download Path, Storage Usage visual breakdown,
/// Cache Management (size limit slider), Clear Cache actions.
class DownloadsStorageScreen extends ConsumerStatefulWidget {
  const DownloadsStorageScreen({super.key});

  @override
  ConsumerState<DownloadsStorageScreen> createState() =>
      _DownloadsStorageScreenState();
}

class _DownloadsStorageScreenState
    extends ConsumerState<DownloadsStorageScreen> {
  String _cacheSizeFormatted = '';
  Map<String, int> _cacheBreakdown = {};
  bool _isLoadingCache = true;

  @override
  void initState() {
    super.initState();
    _refreshCacheInfo();
    // Trigger runtime encoder detection (Android) so dropdown shows available formats.
    unawaited(
      AudioConversionService.instance.checkAllEncoders().then((_) {
        if (mounted) setState(() {});
      }).catchError((Object e) {
        LogService.instance.warning('[AudioConversion] Encoder check failed: $e', tag: 'AudioConversion');
      }),
    );
  }

  Future<void> _refreshCacheInfo() async {
    if (!mounted) return;
    setState(() => _isLoadingCache = true);

    try {
      final formatted = await CacheService.getFormattedCacheSize();
      final breakdown = await CacheService.getCacheBreakdown();

      if (!mounted) return;
      setState(() {
        _cacheSizeFormatted = formatted;
        _cacheBreakdown = breakdown;
        _isLoadingCache = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingCache = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for cache refresh triggers from other parts of the app
    ref.listen<int>(
      settingsCacheRefreshTriggerProvider,
      (_, __) => _refreshCacheInfo(),
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: Text(S.of(context).settingsDownloadsStorage),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // ── WAV Conversion Format Selector ──
                    _buildConversionCard(context, ref),
                    const SizedBox(height: 16),

                    // ── Download Path ──
                    _buildDownloadPathCard(context, ref),
                    const SizedBox(height: 16),

                    // ── Storage Usage Breakdown ──
                    _buildStorageBreakdown(context),
                    const SizedBox(height: 16),

                    // ── Cache Limit Slider ──
                    _CacheLimitSlider(
                      onCacheChanged: _refreshCacheInfo,
                    ),
                    const SizedBox(height: 16),

                    // ── Clear Cache Actions ──
                    _buildClearCacheCard(context),
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
  // WAV Conversion Format Selector
  // ──────────────────────────────────────────────

  Widget _buildConversionCard(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);
    final currentFormat = ref.watch(wavConversionFormatProvider);
    final platform = Theme.of(context).platform;

    // Determine which formats are available on this platform
    const allFormats = WavConversionFormat.values;
    final unsupportedFormats = allFormats
        .where((f) => !AudioConversionService.instance.isFormatSupportedOnPlatform(f))
        .toList();

    // Describe the conversion engine
    String engineText;
    if (!kIsWeb && (platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux)) {
      engineText = 'via system FFmpeg';
    } else if (platform == TargetPlatform.android) {
      engineText = 'via MediaCodec';
    } else if (platform == TargetPlatform.iOS) {
      engineText = 'via AVFoundation';
    } else {
      engineText = 'not available';
    }

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.transform_rounded,
                      color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.convertWavAfterDownload,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.convertWavAfterDownloadDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Format dropdown
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<WavConversionFormat>(
                  value: currentFormat,
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down_rounded,
                      color: colorScheme.primary),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  selectedItemBuilder: (ctx) {
                    return allFormats.map((f) {
                      final isSupported = AudioConversionService.instance
                          .isFormatSupportedOnPlatform(f);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              _formatIcon(f),
                              size: 18,
                              color: isSupported
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              f == WavConversionFormat.none
                                  ? 'Keep WAV (no conversion)'
                                  : 'WAV → ${f.displayName} (${f.extension})',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: f == WavConversionFormat.none
                                    ? colorScheme.onSurface
                                    : colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList();
                  },
                  items: allFormats.map((f) {
                    final isSupported = AudioConversionService.instance
                        .isFormatSupportedOnPlatform(f);
                    return DropdownMenuItem<WavConversionFormat>(
                      value: f,
                      enabled: isSupported,
                      child: Row(
                        children: [
                          Icon(
                            _formatIcon(f),
                            size: 20,
                            color: isSupported
                                ? colorScheme.onSurface
                                : colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f == WavConversionFormat.none
                                      ? 'No conversion'
                                      : '${f.displayName} (${f.extension})',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: isSupported
                                        ? colorScheme.onSurface
                                        : colorScheme.onSurface
                                            .withValues(alpha: 0.3),
                                  ),
                                ),
                                Text(
                                  _formatSubtitle(f, engineText, isSupported),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isSupported
                                        ? colorScheme.onSurfaceVariant
                                        : colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isSupported)
                            Icon(Icons.block,
                                size: 16,
                                color: colorScheme.error.withValues(alpha: 0.6)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (WavConversionFormat? value) {
                    if (value == null) return;
                    if (!AudioConversionService.instance
                        .isFormatSupportedOnPlatform(value)) {
                      return;
                    }
                    ref
                        .read(wavConversionFormatProvider.notifier)
                        .setFormat(value);
                    if (context.mounted) {
                      SnackBarUtil.showInfo(
                        context,
                        value == WavConversionFormat.none
                            ? s.convertWavAfterDownloadDisabled
                            : 'WAV will be converted to ${value.displayName}',
                      );
                    }
                  },
                ),
              ),
            ),

            // Engine badge + unsupported note
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.settings_rounded,
                    size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    engineText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (unsupportedFormats.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.info_outline,
                      size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${unsupportedFormats.map((f) => f.displayName).join(', ')} not available',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _formatIcon(WavConversionFormat f) {
    switch (f) {
      case WavConversionFormat.none:
        return Icons.block_rounded;
      case WavConversionFormat.flac:
        return Icons.waves_rounded;
      case WavConversionFormat.opus:
        return Icons.graphic_eq_rounded;
      case WavConversionFormat.mp3:
        return Icons.audiotrack_rounded;
      case WavConversionFormat.alac:
        return Icons.apple_rounded;
      case WavConversionFormat.aac:
        return Icons.tune_rounded;
    }
  }

  String _formatSubtitle(
      WavConversionFormat f, String engine, bool supported) {
    if (!supported) return 'Not available on this device';
    switch (f) {
      case WavConversionFormat.none:
        return 'Keep original WAV file';
      case WavConversionFormat.flac:
        return 'Lossless, ~40-60% smaller than WAV';
      case WavConversionFormat.opus:
        return 'Best compression, ~80-90% smaller';
      case WavConversionFormat.mp3:
        return 'Universal compatibility, ~80-90% smaller';
      case WavConversionFormat.alac:
        return 'Apple Lossless, same quality as FLAC';
      case WavConversionFormat.aac:
        return 'Efficient lossy, best for iOS';
    }
  }

  // ──────────────────────────────────────────────
  // Download Path Card
  // ──────────────────────────────────────────────

  Widget _buildDownloadPathCard(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);
    final hasCustomPath = DownloadPathService.hasCustomPath();

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(Icons.folder_rounded, color: colorScheme.primary, size: 22),
        ),
        title: Text(s.downloadPath),
        subtitle: Text(
          hasCustomPath ? s.customPath : s.defaultPath,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(Icons.chevron_right,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        onTap: () {
          HapticFeedback.lightImpact();
          _navigate(context, const DownloadPathSettingsScreen());
        },
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Storage Usage Breakdown
  // ──────────────────────────────────────────────

  Widget _buildStorageBreakdown(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);
    final total = _cacheBreakdown['total'] ?? 0;
    final audio = _cacheBreakdown['audio'] ?? 0;
    final image = _cacheBreakdown['image'] ?? 0;
    final other = _cacheBreakdown['other'] ?? 0;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoadingCache
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                        child: Icon(Icons.storage_rounded,
                            color: colorScheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        s.cacheManagement,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _cacheSizeFormatted,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (total > 0) ...[
                    _buildBreakdownBar(
                      theme: theme,
                      colorScheme: colorScheme,
                      label: 'Audio',
                      value: audio,
                      total: total,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    _buildBreakdownBar(
                      theme: theme,
                      colorScheme: colorScheme,
                      label: 'Images',
                      value: image,
                      total: total,
                      color: colorScheme.secondary,
                    ),
                    const SizedBox(height: 8),
                    _buildBreakdownBar(
                      theme: theme,
                      colorScheme: colorScheme,
                      label: 'Other',
                      value: other,
                      total: total,
                      color: colorScheme.tertiary,
                    ),
                  ] else ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          children: [
                            Icon(
                              Icons.storage_outlined,
                              size: 32,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No cached data',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildBreakdownBar({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String label,
    required int value,
    required int total,
    required Color color,
  }) {
    final fraction = total > 0 ? value / total : 0.0;
    final formattedSize = CacheService.formatBytes(value);
    final percent = (fraction * 100).toStringAsFixed(1);

    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: color.withValues(alpha: 0.12),
              color: color,
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            formattedSize,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 40,
          child: Text(
            '$percent%',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  // Clear Cache Card
  // ──────────────────────────────────────────────

  Widget _buildClearCacheCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.error.withValues(alpha: 0.12),
              child: Icon(Icons.delete_outline_rounded,
                  color: colorScheme.error, size: 22),
            ),
            title: Text(s.clearCache),
            subtitle: Text(
              'Remove all cached data including images and audio',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Icon(Icons.chevron_right,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            onTap: () {
              HapticFeedback.lightImpact();
              _confirmClearAllCache(context, s);
            },
          ),
          Divider(height: 1, indent: 72, color: colorScheme.outlineVariant),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.tertiary.withValues(alpha: 0.12),
              child: Icon(Icons.music_note_rounded,
                  color: colorScheme.tertiary, size: 22),
            ),
            title: const Text('Clear Audio Cache'),
            subtitle: Text(
              'Remove cached audio files only',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Icon(Icons.chevron_right,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            onTap: () {
              HapticFeedback.lightImpact();
              _confirmClearAudioCache(context, s);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearAllCache(BuildContext context, S s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.confirmClear),
        content: Text(s.confirmClearCacheMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(s.confirmClear),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await CacheService.clearAllCache();
        await _refreshCacheInfo();
        if (!context.mounted) return;
        SnackBarUtil.showSuccess(context, s.cacheCleared);
      } catch (e) {
        if (context.mounted) {
          SnackBarUtil.showError(
            context,
            s.clearCacheFailedWithError(e.toString()),
          );
        }
      }
    }
  }

  Future<void> _confirmClearAudioCache(BuildContext context, S s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.confirmClear),
        content: const Text('Clear all cached audio files? Downloaded files will not be affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.confirm),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await CacheService.clearAudioCache();
        await _refreshCacheInfo();
        if (!context.mounted) return;
        SnackBarUtil.showSuccess(context, s.cacheCleared);
      } catch (e) {
        if (context.mounted) {
          SnackBarUtil.showError(
            context,
            s.clearCacheFailedWithError(e.toString()),
          );
        }
      }
    }
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

// ──────────────────────────────────────────────
// Cache Limit Slider (standalone widget)
// ──────────────────────────────────────────────

class _CacheLimitSlider extends StatefulWidget {
  final VoidCallback onCacheChanged;
  const _CacheLimitSlider({required this.onCacheChanged});

  @override
  State<_CacheLimitSlider> createState() => _CacheLimitSliderState();
}

class _CacheLimitSliderState extends State<_CacheLimitSlider> {
  int _currentLimit = CacheService.defaultCacheSizeLimitMB;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLimit();
  }

  Future<void> _loadLimit() async {
    try {
      final limit = await CacheService.getCacheSizeLimit();
      if (mounted) {
        setState(() {
          _currentLimit = limit;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  double _limitToSliderValue(int mb) {
    if (mb <= 1000) return ((mb - 100) / 900.0) * 50;
    if (mb <= 3000) return 50 + (((mb - 1000) / 2000.0) * 25);
    if (mb <= 5000) return 75 + (((mb - 3000) / 2000.0) * 15);
    return 90 + (((mb - 5000) / 5240.0) * 10);
  }

  int _sliderValueToMB(double value) {
    if (value <= 50) return 100 + ((value / 50) * 900).toInt();
    if (value <= 75) return 1000 + (((value - 50) / 25) * 2000).toInt();
    if (value <= 90) return 3000 + (((value - 75) / 15) * 2000).toInt();
    return 5000 + (((value - 90) / 10) * 5240).toInt();
  }

  String _formatLimit(int mb) {
    if (mb < 1024) return '${mb}MB';
    return '${(mb / 1024).toStringAsFixed(1)}GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);

    if (_isLoading) {
      return Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final sliderValue = _limitToSliderValue(_currentLimit);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  s.cacheSizeLimit,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _formatLimit(_currentLimit),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Slider(
              value: sliderValue,
              min: 0,
              max: 100,
              divisions: 20,
              label: _formatLimit(_currentLimit),
              onChanged: (value) {
                setState(() {
                  _currentLimit = _sliderValueToMB(value);
                });
              },
              onChangeEnd: (value) async {
                final limit = _sliderValueToMB(value);
                await CacheService.setCacheSizeLimit(limit);
                widget.onCacheChanged();
              },
            ),
            Row(
              children: [
                Text(
                  '100MB',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  '10GB+',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.autoCleanDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
