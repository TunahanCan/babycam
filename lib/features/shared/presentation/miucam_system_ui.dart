import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps system-bar contrast owned by the visible screen, including after a
/// dark camera/scanner route is popped or fullscreen mode is exited.
class MiuCamSystemUi extends StatelessWidget {
  const MiuCamSystemUi({
    super.key,
    required this.child,
    this.darkBackground = false,
  });

  final Widget child;
  final bool darkBackground;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              darkBackground ? Brightness.light : Brightness.dark,
          statusBarBrightness:
              darkBackground ? Brightness.dark : Brightness.light,
        ),
        child: child,
      );
}
