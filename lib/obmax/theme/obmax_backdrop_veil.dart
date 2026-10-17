import 'package:flutter/widgets.dart';

/// The OB Max veil over blurred artwork (home and detail backdrops): night
/// blue at 70 % on the side the text sits, fading to transparent, so the
/// artwork keeps its colour and the text keeps its contrast.
class ObMaxBackdropVeil extends StatelessWidget {
  const ObMaxBackdropVeil({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [Color(0xB3080A23), Color(0x66080A23), Color(0x00080A23)],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
