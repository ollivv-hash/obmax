import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui/navigation/app_router.dart' show appRouter;
import '../enroll/obmax_enrollment.dart';
import '../ota/obmax_updater.dart';

import '../theme/obmax_theme.dart';
import 'obmax_splash.dart';

/// Shows the OB Max splash while `main()` initializes the app (DI,
/// certificates, capabilities), then swaps in the real app once both the
/// animation and the initialization are done.
///
/// `main()` calls [showSplash] right after the binding is ready, and
/// [finish] where it used to call `runApp`.
abstract final class ObMaxBoot {
  static final _app = ValueNotifier<Widget?>(null);

  static void showSplash() {
    ObMaxTheme.install();
    runApp(const _ObMaxBootHost());
  }

  static void finish(Widget app) {
    _app.value = app;
    // Update check once the app is up (at most once a day, Android only).
    Timer(const Duration(seconds: 12), () {
      unawaited(
        ObMaxUpdater.checkIfDue(
          () => appRouter.routerDelegate.navigatorKey.currentContext,
        ),
      );
    });
    // V2: the device certificate renews itself well before it expires.
    Timer(const Duration(seconds: 20), () {
      unawaited(ObMaxEnroller.renewIfDue());
    });
    Timer.periodic(const Duration(hours: 24), (_) {
      unawaited(ObMaxEnroller.renewIfDue());
    });
  }
}

class _ObMaxBootHost extends StatefulWidget {
  const _ObMaxBootHost();

  @override
  State<_ObMaxBootHost> createState() => _ObMaxBootHostState();
}

class _ObMaxBootHostState extends State<_ObMaxBootHost> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Widget?>(
      valueListenable: ObMaxBoot._app,
      builder: (context, app, _) {
        if (app != null && _splashDone) return app;
        return Directionality(
          textDirection: TextDirection.ltr,
          child: ObMaxSplash(
            ready: app != null,
            onFinished: () => setState(() => _splashDone = true),
          ),
        );
      },
    );
  }
}
