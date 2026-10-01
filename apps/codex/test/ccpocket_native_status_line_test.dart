import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/ccpocket_native_session.dart';

void main() {
  testWidgets('localizes recovery statuses and stays within a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(
          body: CcpocketNativeStatusLine(status: 'reconnecting'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('重新连接中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long unknown status is ellipsized instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(
          body: CcpocketNativeStatusLine(
            status: 'an-unexpectedly-long-runtime-status-value',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OverflowBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
