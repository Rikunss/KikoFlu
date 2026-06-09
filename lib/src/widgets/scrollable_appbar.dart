import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 可滚动 AppBar - 默认不显示分隔线，滚动时显示
class ScrollableAppBar extends StatefulWidget implements PreferredSizeWidget {
  const ScrollableAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.toolbarHeight = kToolbarHeight,
    this.flexibleSpace,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.titleSpacing,
    this.centerTitle,
    this.systemOverlayStyle,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;
  final double toolbarHeight;
  final Widget? flexibleSpace;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final double? titleSpacing;
  final bool? centerTitle;
  final SystemUiOverlayStyle? systemOverlayStyle;

  @override
  State<ScrollableAppBar> createState() => _ScrollableAppBarState();

  @override
  Size get preferredSize => Size.fromHeight(
        toolbarHeight + (bottom?.preferredSize.height ?? 0),
      );
}

class _ScrollableAppBarState extends State<ScrollableAppBar> {
  ScrollNotificationObserverState? _scrollNotificationObserver;
  bool _scrolledUnder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollNotificationObserver?.removeListener(_handleScrollNotification);
    _scrollNotificationObserver = ScrollNotificationObserver.maybeOf(context);
    _scrollNotificationObserver?.addListener(_handleScrollNotification);
  }

  @override
  void dispose() {
    if (_scrollNotificationObserver != null) {
      _scrollNotificationObserver!.removeListener(_handleScrollNotification);
      _scrollNotificationObserver = null;
    }
    super.dispose();
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        defaultScrollNotificationPredicate(notification)) {
      final ScrollMetrics metrics = notification.metrics;

      // Compute scrolledUnder from axis direction
      final bool newScrolledUnder = switch (metrics.axisDirection) {
        AxisDirection.up => metrics.extentAfter > 0,
        AxisDirection.down => metrics.extentBefore > 0,
        AxisDirection.right || AxisDirection.left => _scrolledUnder,
      };

      if (newScrolledUnder != _scrolledUnder) {
        _scrolledUnder = newScrolledUnder;
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: widget.title,
      leading: widget.leading,
      actions: widget.actions,
      backgroundColor: widget.backgroundColor,
      foregroundColor: widget.foregroundColor,
      elevation: widget.elevation ?? 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: widget.systemOverlayStyle,
      toolbarHeight: widget.toolbarHeight,
      flexibleSpace: widget.flexibleSpace,
      automaticallyImplyLeading: widget.automaticallyImplyLeading,
      titleSpacing: widget.titleSpacing,
      centerTitle: widget.centerTitle,
      bottom: widget.bottom ?? PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 1,
                decoration: BoxDecoration(
                  gradient: _scrolledUnder
                      ? LinearGradient(
                          colors: [
                            Colors.grey.withValues(alpha: 0.1),
                            Colors.grey.withValues(alpha: 0.3),
                            Colors.grey.withValues(alpha: 0.1),
                          ],
                        )
                      : const LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.transparent,
                          ],
                        ),
                ),
              ),
            ),
    );
  }
}
