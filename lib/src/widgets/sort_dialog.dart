import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../models/sort_options.dart';
import '../utils/l10n_extensions.dart';
import 'responsive_dialog.dart';

/// 通用排序对话框
///
/// 支持两种使用模式：
/// 1. 回调模式：提供 currentOption, currentDirection 和 onSort 回调
/// 2. 直接模式：选择后自动关闭对话框并触发回调
///
/// 自动适配横屏/竖屏布局：
/// - 横屏：两列布局（左：排序字段，右：排序方向）
/// - 竖屏：单列布局
class CommonSortDialog extends StatefulWidget {
  final SortOrder currentOption;
  final SortDirection currentDirection;
  final Function(SortOrder, SortDirection) onSort;
  final String title;
  final bool autoClose;
  final List<SortOrder>? availableOptions;

  const CommonSortDialog({
    super.key,
    required this.currentOption,
    required this.currentDirection,
    required this.onSort,
    this.title = 'Sort',
    this.autoClose = true,
    this.availableOptions,
  });

  @override
  State<CommonSortDialog> createState() => _CommonSortDialogState();
}

class _CommonSortDialogState extends State<CommonSortDialog> {
  late SortOrder _currentOption;
  late SortDirection _currentDirection;

  @override
  void initState() {
    super.initState();
    _currentOption = widget.currentOption;
    _currentDirection = widget.currentDirection;
  }

  void _handleSort(SortOrder option, SortDirection direction) {
    setState(() {
      _currentOption = option;
      _currentDirection = direction;
    });
    widget.onSort(option, direction);
    if (widget.autoClose) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final options = widget.availableOptions ?? SortOrder.values;

    // 横屏时使用两列布局
    if (isLandscape) {
      return ResponsiveAlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(widget.title),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: S.of(context).close,
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左列：排序字段
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 8),
                      child: Text(
                        S.of(context).sortField,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: RadioGroup<SortOrder>(
                          groupValue: _currentOption,
                          onChanged: (SortOrder? value) {
                            if (value != null) {
                              _handleSort(value, _currentDirection);
                            }
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: options.map((option) {
                              return RadioListTile<SortOrder>(
                                title: Text(option.localizedLabel(context)),
                                value: option,
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              // 右列：排序方向
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 8),
                      child: Text(
                        S.of(context).sortDirection,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: RadioGroup<SortDirection>(
                          groupValue: _currentDirection,
                          onChanged: (SortDirection? value) {
                            if (value != null) {
                              _handleSort(_currentOption, value);
                            }
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: SortDirection.values.map((direction) {
                              return RadioListTile<SortDirection>(
                                title: Text(direction.localizedLabel(context)),
                                value: direction,
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: widget.autoClose
            ? null
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(S.of(context).close),
                ),
              ],
      );
    }

    // 竖屏时使用单列布局
    return ResponsiveAlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 排序字段选择
            Text(
              S.of(context).sortField,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            RadioGroup<SortOrder>(
              groupValue: _currentOption,
              onChanged: (SortOrder? value) {
                if (value != null) {
                  _handleSort(value, _currentDirection);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: options.map((option) {
                  return RadioListTile<SortOrder>(
                    title: Text(option.localizedLabel(context)),
                    value: option,
                    dense: true,
                  );
                }).toList(),
              ),
            ),
            const Divider(),
            // 排序方向选择
            Text(
              S.of(context).sortDirection,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            RadioGroup<SortDirection>(
              groupValue: _currentDirection,
              onChanged: (SortDirection? value) {
                if (value != null) {
                  _handleSort(_currentOption, value);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: SortDirection.values.map((direction) {
                  return RadioListTile<SortDirection>(
                    title: Text(direction.localizedLabel(context)),
                    value: direction,
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.autoClose ? S.of(context).cancel : S.of(context).close),
        ),
      ],
    );
  }
}
