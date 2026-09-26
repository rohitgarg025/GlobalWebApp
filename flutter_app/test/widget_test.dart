import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:global_buildestate_app/main.dart';

void main() {
  testWidgets('App builds and shows the auth gate', (WidgetTester tester) async {
    await tester.pumpWidget(const GlobalBuildestateApp());
    // Before AuthService.init() completes, the gate shows a loading spinner.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
