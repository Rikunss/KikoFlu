import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';
import '../services/log_service.dart';

class DesktopFloatingLyric extends StatefulWidget {
  final dynamic windowId;
  final Map<String, dynamic>? arguments;

  const DesktopFloatingLyric({
    super.key,
    required this.windowId,
    this.arguments,
  });

  @override
  State<DesktopFloatingLyric> createState() => _DesktopFloatingLyricState();
}

class _DesktopFloatingLyricState extends State<DesktopFloatingLyric>
    with WindowListener {
  String _text = '♪ - ♪';

  double _fontSize = 24.0;
  Color _textColor = Colors.white;
  Color _backgroundColor = Colors.transparent;
  double _cornerRadius = 8.0;
  double _paddingHorizontal = 16.0;
  double _paddingVertical = 8.0;
  String _fontFamily = '';
  FontWeight _fontWeight = FontWeight.bold;
  bool _shadowEnabled = true;
  double _shadowBlur = 3.0;
  Color _shadowColor = const Color(0xCC000000);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initWindow();

    if (widget.arguments != null) {
      if (widget.arguments!.containsKey('text')) {
        _text = widget.arguments!['text'] as String;
      }
      _updateStyleProperties(widget.arguments!);
    }
  }

  void _updateStyleProperties(Map args) {
    if (args.containsKey('fontSize')) {
      _fontSize = (args['fontSize'] as num).toDouble();
    }
    if (args.containsKey('textColor')) {
      _textColor = Color(args['textColor'] as int);
    }
    if (args.containsKey('backgroundColor')) {
      _backgroundColor = Color(args['backgroundColor'] as int);
    }
    if (args.containsKey('cornerRadius')) {
      _cornerRadius = (args['cornerRadius'] as num).toDouble();
    }
    if (args.containsKey('paddingHorizontal')) {
      _paddingHorizontal = (args['paddingHorizontal'] as num).toDouble();
    }
    if (args.containsKey('paddingVertical')) {
      _paddingVertical = (args['paddingVertical'] as num).toDouble();
    }
    if (args.containsKey('fontFamily')) {
      _fontFamily = args['fontFamily'] as String? ?? '';
    }
    if (args.containsKey('fontWeight')) {
      final idx = args['fontWeight'] as int?;
      if (idx != null && idx < FontWeight.values.length) {
        _fontWeight = FontWeight.values[idx];
      }
    }
    if (args.containsKey('shadowEnabled')) {
      _shadowEnabled = args['shadowEnabled'] as bool? ?? true;
    }
    if (args.containsKey('shadowBlur')) {
      _shadowBlur = (args['shadowBlur'] as num?)?.toDouble() ?? 3.0;
    }
    if (args.containsKey('shadowColor')) {
      _shadowColor = Color(args['shadowColor'] as int);
    }
  }

  Future<void> _initWindow() async {
    try {
      await windowManager.setAsFrameless();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setHasShadow(false);
      await windowManager.setSize(const Size(800, 200));

      final controller = await WindowController.fromCurrentEngine();
      controller.setWindowMethodHandler(_handleMethodCall);
    } catch (e) {
      LogService.instance.error('[DesktopFloatingLyric] Failed to init window: $e', tag: 'UI');
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'updateText':
        if (mounted) {
          setState(() {
            _text = call.arguments['text'] as String;
          });
        }
        return true;
      case 'updateStyle':
        if (mounted) {
          setState(() {
            _updateStyleProperties(call.arguments as Map);
          });
        }
        return true;
      case 'close':
        await windowManager.close();
        return true;
      default:
        return null;
    }
  }

  Future<void> _closeWindow() async {
    try {
      final controller = await WindowController.fromCurrentEngine();
      await controller.invokeMethod('close');
    } catch (_) {
      await windowManager.close();
    }
  }

  void _showCloseDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Floating Lyric?'),
        content: const Text('This will hide the floating lyric window.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _closeWindow();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            // Main lyric area - drag to move, long press to close
            Expanded(
              child: GestureDetector(
                onLongPress: _showCloseDialog,
                onPanStart: (_) => windowManager.startDragging(),
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _backgroundColor,
                      borderRadius: BorderRadius.circular(_cornerRadius),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: _paddingHorizontal,
                      vertical: _paddingVertical,
                    ),
                    child: Text(
                      _text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: _fontSize,
                        fontWeight: _fontWeight,
                        fontFamily: _fontFamily.isNotEmpty ? _fontFamily : null,
                        color: _textColor,
                        shadows: _shadowEnabled
                            ? [
                                Shadow(
                                  offset: const Offset(1.0, 1.0),
                                  blurRadius: _shadowBlur,
                                  color: _shadowColor,
                                ),
                                Shadow(
                                  offset: const Offset(-1.0, -1.0),
                                  blurRadius: _shadowBlur,
                                  color: _shadowColor,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom handle - tap to close
            GestureDetector(
              onTap: _closeWindow,
              child: Container(
                height: 20,
                color: Colors.transparent,
                child: Center(
                  child: Tooltip(
                    message: 'Tap to close',
                    child: Container(
                      width: 40,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
