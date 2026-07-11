import 'dart:async';

import 'package:flutter/material.dart';

/// 通用滚动优化工具类
///
/// 统一管理滚动物理属性、缓存范围和防抖/节流逻辑，
/// 提升 120Hz 高刷新率设备上的列表滚动流畅度。
///
/// 使用方法：
/// ```dart
/// CustomScrollView(
///   cacheExtent: ScrollOptimization.cacheExtent,
///   physics: ScrollOptimization.physics,
///   ...
/// )
/// ```
class ScrollOptimization {
  ScrollOptimization._();

  /// 推荐的缓存范围（像素）
  ///
  /// 1500px memberikan waktu lebih bagi CachedNetworkImage untuk memulai download
  /// sebelum card masuk viewport. Untuk scroll cepat (~1000px/s), ini memberi ~1.5s
  /// lead time — cukup untuk sebagian besar download gambar.
  ///
  /// Nilai 500px sebelumnya hanya memberi ~0.5s lead time, menyebabkan placeholder
  /// masih terlihat saat scroll cepat karena image belum sempat selesai di-download.
  static const double cacheExtent = 1500;

  /// 平台自适应的滚动物理属性
  ///
  /// 使用平台默认父级物理：
  /// - iOS → BouncingScrollPhysics（原生回弹效果，与 ProMotion 120Hz 兼容良好）
  /// - Android → ClampingScrollPhysics（原生 overscroll glow 效果）
  ///
  /// 外层包裹 AlwaysScrollableScrollPhysics，确保 RefreshIndicator 等组件可用。
  static const ScrollPhysics physics = AlwaysScrollableScrollPhysics();
}

/// 滚动事件节流器
///
/// 在滚动监听中使用，避免在 120Hz 设备上每帧（~8ms）都触发昂贵的回调
/// （如 setState、网络请求、加载更多判断等）。
///
/// 支持两种模式：
/// - [throttle]：节流 —— 在 interval 内最多执行一次，适合"加载更多"等场景
/// - [debounce]：防抖 —— 等滚动停止后才执行，适合"保存滚动位置"等场景
///
/// 使用方法：
/// ```dart
/// final _scrollThrottler = ScrollThrottler();
///
/// void _onScroll() {
///   _scrollThrottler.throttle(() {
///     // 节流后的滚动回调
///   });
/// }
///
/// @override
/// void dispose() {
///   _scrollThrottler.dispose();
///   super.dispose();
/// }
/// ```
class ScrollThrottler {
  /// 节流/防抖的时间间隔
  final Duration interval;

  /// 位置变化阈值（像素），小于此值的滚动不触发回调
  final double positionThreshold;

  Timer? _timer;
  double _lastPosition = 0;

  ScrollThrottler({
    this.interval = const Duration(milliseconds: 32),
    this.positionThreshold = 0,
  });

  /// 节流执行：在 [interval] 内最多触发一次 [callback]
  ///
  /// 可选传入 [controller] 来启用位置变化阈值过滤。
  /// 如果滚动距离小于 [positionThreshold]，直接跳过。
  void throttle(VoidCallback callback, {ScrollController? controller}) {
    if (controller != null && controller.hasClients) {
      final pos = controller.position.pixels;
      if ((pos - _lastPosition).abs() < positionThreshold) return;
      _lastPosition = pos;
    }

    if (_timer?.isActive ?? false) return;

    callback();
    _timer = Timer(interval, () {});
  }

  /// 防抖执行：等调用停止 [interval] 后才执行 [callback]
  ///
  /// 每次调用都会重置计时器，只有最后一次调用后
  /// 经过 [interval] 才会真正执行 callback。
  void debounce(VoidCallback callback) {
    _timer?.cancel();
    _timer = Timer(interval, callback);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}