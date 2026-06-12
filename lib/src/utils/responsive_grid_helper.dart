import 'package:flutter/material.dart';

/// 响应式布局工具类
/// 根据屏幕尺寸和方向自动计算最佳列数
///
/// 所有方法现已拆分为 *_ForSize 变体，接受显式的 Size 和 Orientation
/// 参数，避免在 build 中重复调用 MediaQuery.of(context)。
class ResponsiveGridHelper {
  /// 根据屏幕尺寸计算大网格的列数
  ///
  /// 逻辑：
  /// - 竖屏：固定2列
  /// - 横屏：
  ///   - 屏幕宽度 < 1200px 或宽高比 < 1.3：3列
  ///   - 屏幕宽度 >= 1200px 且宽高比 >= 1.3：4列
  static int getBigGridCrossAxisCountForSize(Size size, Orientation orientation) {
    // 竖屏固定2列
    if (orientation == Orientation.portrait) {
      return 2;
    }

    // 横屏根据屏幕尺寸决定3列或4列
    final aspectRatio = size.width / size.height;
    final width = size.width;

    // 宽度较小或宽高比不够宽时使用3列
    if (width < 1200 || aspectRatio < 1.3) {
      return 3;
    }

    return 4;
  }

  /// 根据屏幕尺寸计算小网格的列数
  ///
  /// 逻辑：
  /// - 竖屏：固定3列
  /// - 横屏：固定5列
  static int getSmallGridCrossAxisCountForOrientation(Orientation orientation) {
    return orientation == Orientation.landscape ? 5 : 3;
  }

  /// 获取推荐的卡片最小宽度
  /// 用于确保卡片在不同列数下保持合适的尺寸
  static double getRecommendedCardMinWidth(int crossAxisCount) {
    switch (crossAxisCount) {
      case 2:
        return 160.0;
      case 3:
        return 220.0;
      case 4:
        return 200.0;
      case 5:
        return 140.0;
      default:
        return 180.0;
    }
  }

  /// 获取屏幕宽度分类 (compact / medium / expanded / large)
  static ScreenWidthClass getScreenWidthClassForWidth(double width) {
    if (width < 600) {
      return ScreenWidthClass.compact;
    } else if (width < 840) {
      return ScreenWidthClass.medium;
    } else if (width < 1200) {
      return ScreenWidthClass.expanded;
    } else {
      return ScreenWidthClass.large;
    }
  }

  /// 获取推荐的间距
  static double getRecommendedSpacingForSize(Size size, Orientation orientation) {
    final widthClass = getScreenWidthClassForWidth(size.width);

    if (orientation == Orientation.landscape) {
      return widthClass == ScreenWidthClass.large ? 24.0 : 16.0;
    }

    return 8.0;
  }

  /// 获取推荐的边距
  static double getRecommendedPaddingForSize(Size size, Orientation orientation) {
    final widthClass = getScreenWidthClassForWidth(size.width);

    if (orientation == Orientation.landscape) {
      return widthClass == ScreenWidthClass.large ? 24.0 : 16.0;
    }

    return 8.0;
  }

  /// 判断是否为宽屏设备
  static bool isWideScreenForSize(Size size) {
    final aspectRatio = size.width / size.height;
    return aspectRatio >= 1.6;
  }

  // ═══════════════════════════════════════════════════════════
  // Legacy convenience methods — still accept BuildContext
  // internally delegate to the *_ForSize overloads.
  // Prefer the *_ForSize variants in performance-sensitive builds.
  // ═══════════════════════════════════════════════════════════

  static int getBigGridCrossAxisCount(BuildContext context) {
    return getBigGridCrossAxisCountForSize(
      MediaQuery.of(context).size,
      MediaQuery.orientationOf(context),
    );
  }

  static int getSmallGridCrossAxisCount(BuildContext context) {
    return getSmallGridCrossAxisCountForOrientation(
      MediaQuery.orientationOf(context),
    );
  }

  static ScreenWidthClass getScreenWidthClass(BuildContext context) {
    return getScreenWidthClassForWidth(MediaQuery.of(context).size.width);
  }

  static double getRecommendedSpacing(BuildContext context) {
    return getRecommendedSpacingForSize(
      MediaQuery.of(context).size,
      MediaQuery.orientationOf(context),
    );
  }

  static double getRecommendedPadding(BuildContext context) {
    return getRecommendedPaddingForSize(
      MediaQuery.of(context).size,
      MediaQuery.orientationOf(context),
    );
  }

  static bool isWideScreen(BuildContext context) {
    return isWideScreenForSize(MediaQuery.of(context).size);
  }
}

/// 屏幕宽度分类
enum ScreenWidthClass {
  compact, // < 600px  (手机)
  medium, // < 840px  (小平板)
  expanded, // < 1200px (大平板)
  large, // >= 1200px (桌面)
}
