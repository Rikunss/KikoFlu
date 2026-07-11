import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:io' show Platform;

/// 音量控制组件，适用于桌面端平台（Windows/macOS/Linux/Web）
///
/// 功能特性：
/// - 鼠标悬浮时显示垂直滑动条
/// - 滑动条浮动显示，不影响其他组件布局
/// - 支持音量调节（0.0 - 1.0）
/// - 在移动端（Android/iOS）自动隐藏
class VolumeControl extends StatefulWidget {
  /// 当前音量值 (0.0 - 1.0)
  final double volume;

  /// 音量变化回调
  final ValueChanged<double> onVolumeChanged;

  /// 音量变化结束回调（拖动结束时调用）
  final VoidCallback? onVolumeChangeEnd;

  /// 图标大小
  final double? iconSize;

  /// 图标颜色
  final Color? iconColor;

  const VolumeControl({
    super.key,
    required this.volume,
    required this.onVolumeChanged,
    this.onVolumeChangeEnd,
    this.iconSize,
    this.iconColor,
  });

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  bool _isHovering = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  void didUpdateWidget(VolumeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.volume != widget.volume && _overlayEntry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _overlayEntry?.markNeedsBuild();
      });
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 48,
        child: CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -8),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(24),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: MouseRegion(
              onEnter: (_) {
                if (mounted) {
                  setState(() => _isHovering = true);
                }
              },
              onExit: (_) {
                if (mounted) {
                  setState(() => _isHovering = false);
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (!_isHovering && mounted) {
                      _removeOverlay();
                    }
                  });
                }
              },
              child: Container(
                height: 160,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getVolumeIcon(widget.volume),
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: -1,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                          ),
                          child: Slider(
                            value: widget.volume.clamp(0.0, 1.0),
                            onChanged: widget.onVolumeChanged,
                            onChangeEnd: (value) {
                              widget.onVolumeChangeEnd?.call();
                            },
                            min: 0.0,
                            max: 1.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(widget.volume * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  IconData _getVolumeIcon(double volume) {
    if (volume == 0) {
      return Icons.volume_off;
    } else if (volume < 0.5) {
      return Icons.volume_down;
    } else {
      return Icons.volume_up;
    }
  }

  /// 检查是否为桌面端平台（Windows/macOS/Linux/Web）
  bool get _isDesktopPlatform {
    if (kIsWeb) return true;

    try {
      return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    } catch (e) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktopPlatform) {
      return const SizedBox.shrink();
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _isHovering = true);
          _showOverlay();
        },
        onExit: (_) {
          if (mounted) {
            setState(() => _isHovering = false);
          }
          Future.delayed(const Duration(milliseconds: 100), () {
            if (!_isHovering && mounted) {
              _removeOverlay();
            }
          });
        },
        child: IconButton(
          onPressed: () {
            if (widget.volume > 0) {
              widget.onVolumeChanged(0.0);
            } else {
              widget.onVolumeChanged(0.5);
            }
          },
          icon: Icon(_getVolumeIcon(widget.volume)),
          iconSize: widget.iconSize ?? 24,
          color: widget.iconColor,
        ),
      ),
    );
  }
}