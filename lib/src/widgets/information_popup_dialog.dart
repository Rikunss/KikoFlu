import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../models/information_popup.dart';
import '../services/information_popup_service.dart';
import '../utils/snackbar_util.dart';

class InformationPopupDialog extends StatefulWidget {
  final InformationPopup popup;

  const InformationPopupDialog({super.key, required this.popup});

  /// Returns `true` if the user checked "Don't show again".
  static Future<bool?> show(BuildContext context, InformationPopup popup) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => InformationPopupDialog(popup: popup),
    );
  }

  @override
  State<InformationPopupDialog> createState() => _InformationPopupDialogState();
}

class _InformationPopupDialogState extends State<InformationPopupDialog> {
  final InformationPopupService _service = InformationPopupService();
  bool _dontShowAgain = false;
  bool _openingUrl = false;

  Future<void> _openAction() async {
    final url = widget.popup.buttonUrl.trim();
    if (url.isEmpty || _openingUrl) return;

    setState(() => _openingUrl = true);
    try {
      final uri = Uri.tryParse(url);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched && mounted) {
          SnackBarUtil.showError(
            context,
            S.of(context).cannotOpenLink,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(
          context,
          S.of(context).openLinkFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _openingUrl = false);
    }
  }

  void _close() {
    Navigator.of(context).pop(_dontShowAgain);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final hasImage = widget.popup.imageUrl.isNotEmpty;
    final hasAction =
        widget.popup.buttonText.isNotEmpty && widget.popup.buttonUrl.isNotEmpty;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: cs.surfaceContainerLow,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s.announcement,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: s.close,
                      onPressed: _close,
                    ),
                  ],
                ),
              ),

              if (hasImage)
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: CachedNetworkImage(
                      imageUrl: widget.popup.imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (context, url) => Container(
                        height: 160,
                        color: cs.surfaceContainerHighest,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 120,
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          size: 48,
                          color: cs.outline,
                        ),
                      ),
                    ),
                  ),
                ),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.popup.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.popup.message.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          widget.popup.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (hasAction)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: FilledButton(
                    onPressed: _openingUrl ? null : _openAction,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _openingUrl
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.popup.buttonText),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            setState(() => _dontShowAgain = !_dontShowAgain),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _dontShowAgain,
                                onChanged: (v) =>
                                    setState(() => _dontShowAgain = v ?? false),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  s.dontShowAgain,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (_dontShowAgain) {
                          await _service.dismiss(widget.popup.id);
                          HapticFeedback.mediumImpact();
                        }
                        if (mounted) _close();
                      },
                      child: Text(s.close),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
