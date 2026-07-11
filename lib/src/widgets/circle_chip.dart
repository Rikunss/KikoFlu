import 'package:flutter/material.dart';
import '../services/log_service.dart';
import '../../l10n/app_localizations.dart';
import '../screens/search_result_screen.dart';

class CircleChip extends StatelessWidget {
  final int circleId;
  final String circleName;
  final VoidCallback? onDeleted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool compact;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final FontWeight? fontWeight;

  const CircleChip({
    super.key,
    required this.circleId,
    required this.circleName,
    this.onDeleted,
    this.onTap,
    this.onLongPress,
    this.compact = false,
    this.fontSize,
    this.padding,
    this.borderRadius,
    this.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (fontSize != null || padding != null || borderRadius != null) {
      return GestureDetector(
        onTap: onTap ??
            () {
              LogService.instance.debug('[CircleChip] Clicked circle: $circleName, id: $circleId', tag: 'UI');
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchResultScreen(
                    keyword: circleName,
                    searchTypeLabel: S.of(context).searchTypeCircle,
                    searchParams: {
                      'circleId': circleId,
                      'circleName': circleName
                    },
                  ),
                ),
              );
            },
        onLongPress: onLongPress,
        child: Container(
          padding:
              padding ?? const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(borderRadius ?? 12),
          ),
          child: Text(
            circleName,
            style: TextStyle(
              fontSize: fontSize ?? 11,
              color: cs.onSecondaryContainer,
              fontWeight: fontWeight ?? FontWeight.w500,
            ),
          ),
        ),
      );
    }

    if (onDeleted != null) {
      return InputChip(
        label: Text(circleName),
        onPressed: onTap ??
            () {
              LogService.instance.debug('[CircleChip] Clicked circle: $circleName, id: $circleId', tag: 'UI');
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchResultScreen(
                    keyword: circleName,
                    searchTypeLabel: S.of(context).searchTypeCircle,
                    searchParams: {
                      'circleId': circleId,
                      'circleName': circleName
                    },
                  ),
                ),
              );
            },
        onDeleted: onDeleted,
        deleteIcon: const Icon(Icons.close, size: 16),
        visualDensity: compact ? VisualDensity.compact : null,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        labelStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        deleteIconColor: Theme.of(context).colorScheme.onSecondaryContainer,
      );
    }

    return ActionChip(
      label: Text(circleName),
      onPressed: onTap ??
          () {
            LogService.instance.debug('[CircleChip] Clicked circle: $circleName, id: $circleId', tag: 'UI');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SearchResultScreen(
                  keyword: circleName,
                  searchTypeLabel: S.of(context).searchTypeCircle,
                  searchParams: {
                    'circleId': circleId,
                    'circleName': circleName
                  },
                ),
              ),
            );
          },
      visualDensity: compact ? VisualDensity.compact : null,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
      ),
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      labelStyle: TextStyle(
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
  }
}