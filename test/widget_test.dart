// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vm_summ/main.dart';

void main() {
  testWidgets('App loads redesigned home surface', (WidgetTester tester) async {
    await tester.pumpWidget(
      const VoiceNoteSummarizerApp(
        enableBackgroundServices: false,
        enableNotifications: false,
      ),
    );

    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Voice Note Summarizer'), findsOneWidget);
    expect(find.text('Tap to record'), findsOneWidget);
    expect(find.text('Pick Audio File'), findsOneWidget);
    expect(find.text('Model status'), findsOneWidget);
    expect(find.text('Queue'), findsWidgets);
  });

  testWidgets('App shell still boots', (WidgetTester tester) async {
    await tester.pumpWidget(
      const VoiceNoteSummarizerApp(
        enableBackgroundServices: false,
        enableNotifications: false,
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
