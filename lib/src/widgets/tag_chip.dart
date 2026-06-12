import 'package:flutter/material.dart';
import '../services/log_service.dart';
import '../models/work.dart';
import '../screens/search_result_screen.dart';
import '../../l10n/app_localizations.dart';
import '../utils/tag_localizer.dart';

class TagChip extends StatelessWidget {
  final Tag tag;
  final VoidCallback? onDeleted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool compact;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final FontWeight? fontWeight;

  const TagChip({
    super.key,
    required this.tag,
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
    final locale = Localizations.localeOf(context);
    final localizedName = TagLocalizer.localize(tag.id, tag.name, locale);
    final isUserAdded = tag.isUserAdded;

    // 如果提供了自定义样式参数，使用自定义样式
    if (fontSize != null || padding != null || borderRadius != null) {
      Widget chip = GestureDetector(
        onTap: onTap ??
            () {
              LogService.instance.debug('[TagChip] Clicked tag: ${tag.name}, id: ${tag.id}', tag: 'UI');
              // 默认跳转到标签搜索结果页面
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchResultScreen(
                    keyword: localizedName,
                    searchTypeLabel: S.of(context).searchTypeTag,
                    searchParams: {'tagId': tag.id, 'tagName': tag.name},
                  ),
                ),
              );
            },
        onLongPress: onLongPress,
        child: Container(
          padding:
              padding ?? const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: isUserAdded ? 0.5 : 1.0),
            borderRadius: BorderRadius.circular(borderRadius ?? 12),
          ),
          child: Text(
            localizedName,
            style: TextStyle(
              fontSize: fontSize ?? 11,
              color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: isUserAdded ? 0.55 : 1.0),
              fontWeight: fontWeight ?? FontWeight.w500,
            ),
          ),
        ),
      );
      return chip;
    }

    // 使用默认的 Chip 样式
    if (onDeleted != null) {
      // 如果有删除功能，使用 InputChip
      return InputChip(
        label: Text(localizedName),
        onPressed: onTap ??
            () {
              LogService.instance.debug('[TagChip] Clicked tag: ${tag.name}, id: ${tag.id}', tag: 'UI');
              // 默认跳转到标签搜索结果页面
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchResultScreen(
                    keyword: localizedName,
                    searchTypeLabel: S.of(context).searchTypeTag,
                    searchParams: {'tagId': tag.id, 'tagName': tag.name},
                  ),
                ),
              );
            },
        onDeleted: onDeleted,
        deleteIcon: const Icon(Icons.close, size: 18),
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: isUserAdded ? 0.5 : 1.0),
        labelStyle: TextStyle(
          fontSize: compact ? 10 : null,
          color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: isUserAdded ? 0.55 : 1.0),
        ),
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 0)
            : null,
        visualDensity: compact ? VisualDensity.compact : null,
      );
    } else {
      // 如果没有删除功能，使用 ActionChip
      return ActionChip(
        label: Text(localizedName),
        onPressed: onTap ??
            () {
              LogService.instance.debug('[TagChip] Clicked tag: ${tag.name}, id: ${tag.id}', tag: 'UI');
              // 默认跳转到标签搜索结果页面
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchResultScreen(
                    keyword: localizedName,
                    searchTypeLabel: S.of(context).searchTypeTag,
                    searchParams: {'tagId': tag.id, 'tagName': tag.name},
                  ),
                ),
              );
            },
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: isUserAdded ? 0.5 : 1.0),
        labelStyle: TextStyle(
          fontSize: compact ? 10 : null,
          color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: isUserAdded ? 0.55 : 1.0),
        ),
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 0)
            : null,
        visualDensity: compact ? VisualDensity.compact : null,
      );
    }
  }
}
