import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../utils/snackbar_util.dart';

/// 通用分页控制栏组件
class PaginationBar extends StatefulWidget {
  /// 当前页码（从1开始）
  final int currentPage;

  /// 每页大小
  final int pageSize;

  /// 总条目数
  final int totalCount;

  /// 是否有更多数据
  final bool hasMore;

  /// 是否正在加载
  final bool isLoading;

  /// 上一页回调
  final VoidCallback? onPreviousPage;

  /// 下一页回调
  final VoidCallback? onNextPage;

  /// 跳转到指定页回调
  final void Function(int page)? onGoToPage;

  /// 滚动到顶部回调（可选）
  final VoidCallback? onScrollToTop;

  /// 到底提示文字
  final String? endMessage;

  const PaginationBar({
    super.key,
    required this.currentPage,
    required this.pageSize,
    required this.totalCount,
    required this.hasMore,
    required this.isLoading,
    this.onPreviousPage,
    this.onNextPage,
    this.onGoToPage,
    this.onScrollToTop,
    this.endMessage,
  });

  @override
  State<PaginationBar> createState() => _PaginationBarState();
}

class _PaginationBarState extends State<PaginationBar> {
  final TextEditingController _pageController = TextEditingController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _maxPage =>
      widget.totalCount > 0 ? (widget.totalCount / widget.pageSize).ceil() : 1;

  /// 构建到底提示
  Widget _buildEndMessage() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            widget.endMessage ?? S.of(context).reachedEnd,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建分页按钮
  Widget _buildPageButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback? onPressed,
    bool iconOnRight = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: enabled
          ? cs.primaryContainer
          : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                onPressed?.call();
              }
            : null,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!iconOnRight) ...[
                Icon(icon, size: 18, color: enabled ? cs.onPrimaryContainer : cs.onSurfaceVariant.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: enabled ? cs.onPrimaryContainer : cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
              if (iconOnRight) ...[
                const SizedBox(width: 4),
                Icon(icon, size: 18, color: enabled ? cs.onPrimaryContainer : cs.onSurfaceVariant.withValues(alpha: 0.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 构建页码跳转按钮
  Widget _buildPageJumpButton() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          _showPageJumpDialog();
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_location_alt,
                size: 18,
                color: cs.onSecondaryContainer,
              ),
              const SizedBox(width: 4),
              Text(
                S.of(context).jumpTo,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示页码跳转对话框
  void _showPageJumpDialog() {
    _pageController.text = widget.currentPage.toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).goToPageTitle),
        content: TextField(
          controller: _pageController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: S.of(context).pageNumberRange(_maxPage),
            border: const OutlineInputBorder(),
            hintText: S.of(context).enterPageNumber,
          ),
          autofocus: true,
          onSubmitted: (_) => _handleJump(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.of(context).cancel),
          ),
          ElevatedButton(
            onPressed: () => _handleJump(context),
            child: Text(S.of(context).jumpTo),
          ),
        ],
      ),
    );
  }

  /// 处理跳转
  void _handleJump(BuildContext dialogContext) {
    final pageStr = _pageController.text.trim();
    if (pageStr.isEmpty) {
      SnackBarUtil.showWarning(context, S.of(context).enterPageNumber);
      return;
    }

    final targetPage = int.tryParse(pageStr);
    if (targetPage == null || targetPage < 1 || targetPage > _maxPage) {
      SnackBarUtil.showWarning(context, S.of(context).enterValidPageNumber(_maxPage));
      return;
    }

    if (targetPage == widget.currentPage) {
      Navigator.pop(dialogContext);
      return;
    }

    Navigator.pop(dialogContext);
    widget.onGoToPage?.call(targetPage);
    widget.onScrollToTop?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (widget.totalCount <= widget.pageSize) {
      return _buildEndMessage();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Text(
                  S.of(context).pageNOfTotal(widget.currentPage, _maxPage),
                  key: ValueKey('page_${widget.currentPage}'),
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  S.of(context).totalNItems(widget.totalCount),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPageButton(
                icon: Icons.chevron_left,
                label: S.of(context).previousPage,
                enabled: widget.currentPage > 1 && !widget.isLoading,
                onPressed: widget.onPreviousPage,
              ),
              const SizedBox(width: 10),

              _buildPageJumpButton(),
              const SizedBox(width: 10),

              _buildPageButton(
                label: S.of(context).nextPage,
                icon: Icons.chevron_right,
                enabled: widget.hasMore && !widget.isLoading,
                iconOnRight: true,
                onPressed: widget.onNextPage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}