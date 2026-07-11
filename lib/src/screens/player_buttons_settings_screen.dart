import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/player_buttons_provider.dart';
import '../utils/l10n_extensions.dart';
import '../utils/snackbar_util.dart';
import '../widgets/scrollable_appbar.dart';

/// 播放器按钮设置页面
class PlayerButtonsSettingsScreen extends ConsumerStatefulWidget {
  const PlayerButtonsSettingsScreen({super.key});

  @override
  ConsumerState<PlayerButtonsSettingsScreen> createState() =>
      _PlayerButtonsSettingsScreenState();
}

class _PlayerButtonsSettingsScreenState
    extends ConsumerState<PlayerButtonsSettingsScreen> {
  final bool _isDesktop = !Platform.isAndroid && !Platform.isIOS;
  List<PlayerButtonType> _buttonOrder = [];

  @override
  void initState() {
    super.initState();
    final config = _isDesktop
        ? ref.read(playerButtonsConfigDesktopProvider)
        : ref.read(playerButtonsConfigMobileProvider);
    _buttonOrder = List.from(config.buttonOrder);
  }

  IconData _getButtonIcon(PlayerButtonType type) {
    switch (type) {
      case PlayerButtonType.seekBackward:
        return Icons.replay_10;
      case PlayerButtonType.seekForward:
        return Icons.forward_10;
      case PlayerButtonType.sleepTimer:
        return Icons.timer;
      case PlayerButtonType.volume:
        return Icons.volume_up;
      case PlayerButtonType.mark:
        return Icons.bookmark_border;
      case PlayerButtonType.detail:
        return Icons.info_outline;
      case PlayerButtonType.speed:
        return Icons.speed;
      case PlayerButtonType.repeat:
        return Icons.repeat;
      case PlayerButtonType.subtitleAdjustment:
        return Icons.tune;
      case PlayerButtonType.floatingLyric:
        return Icons.picture_in_picture_alt;
      case PlayerButtonType.equalizer:
        return Icons.equalizer;
      case PlayerButtonType.bookmark:
        return Icons.bookmark_rounded;
    }
  }

  Future<void> _saveSettings() async {
    if (_isDesktop) {
      await ref
          .read(playerButtonsConfigDesktopProvider.notifier)
          .updateButtonOrder(_buttonOrder);
    } else {
      await ref
          .read(playerButtonsConfigMobileProvider.notifier)
          .updateButtonOrder(_buttonOrder);
    }

    if (mounted) {
      SnackBarUtil.showSuccess(context, S.of(context).settingsSaved);
      Navigator.of(context).pop();
    }
  }

  Future<void> _resetToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).restoreDefaultSettings),
        content: Text(S.of(context).confirmRestoreButtonOrder),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(S.of(context).confirm),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (_isDesktop) {
        await ref
            .read(playerButtonsConfigDesktopProvider.notifier)
            .resetToDefault();
        final config = ref.read(playerButtonsConfigDesktopProvider);
        setState(() {
          _buttonOrder = List.from(config.buttonOrder);
        });
      } else {
        await ref
            .read(playerButtonsConfigMobileProvider.notifier)
            .resetToDefault();
        final config = ref.read(playerButtonsConfigMobileProvider);
        setState(() {
          _buttonOrder = List.from(config.buttonOrder);
        });
      }

      if (mounted) {
        SnackBarUtil.showSuccess(context, S.of(context).restoredToDefault);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxVisible = _isDesktop ? 5 : 4;

    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(S.of(context).playerButtonSettings, style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton.icon(
            onPressed: _resetToDefault,
            icon: const Icon(Icons.restart_alt),
            label: Text(S.of(context).restoreDefault),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buttonOrder.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              S.of(context).buttonDisplayRules,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          S.of(context).buttonDisplayRulesDesc(maxVisible),
                          style: const TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _buttonOrder.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final item = _buttonOrder.removeAt(oldIndex);
                        _buttonOrder.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final button = _buttonOrder[index];
                      final isVisible = index < maxVisible;

                      return Card(
                        key: ValueKey(button),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            _getButtonIcon(button),
                            color: isVisible
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                          title: Text(button.localizedLabel(context)),
                          subtitle: Text(
                            isVisible ? S.of(context).shownInPlayer : S.of(context).shownInMoreMenu,
                            style: TextStyle(
                              color: isVisible
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                          ),
                          trailing: ReorderableDragStartListener(
                            index: index,
                            child: Icon(
                              Icons.drag_handle,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.check),
                        label: Text(S.of(context).saveSettings),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}