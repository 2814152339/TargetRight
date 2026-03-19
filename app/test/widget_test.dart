import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jinshi_checkin/main.dart';

void main() {
  testWidgets('renders dynamic island drip animation shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DynamicIslandDripApp());

    expect(find.byType(DynamicIslandDripPage), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
