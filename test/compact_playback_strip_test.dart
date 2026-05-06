import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_summ/ui/premium_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compact playback strip is full width and text-light', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    Duration? lastSeek;
    var toggled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: CompactPlaybackStrip(
                isPlaying: false,
                position: const Duration(seconds: 12),
                duration: const Duration(minutes: 2, seconds: 30),
                onTogglePlay: () {
                  toggled = true;
                },
                onSeek: (value) {
                  lastSeek = value;
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('sample.m4a'), findsNothing);
    expect(find.text('Play voice note'), findsNothing);
    expect(find.text('Voice note'), findsNothing);
    expect(find.byType(CompactPlaybackStrip), findsOneWidget);
    expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
    expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    final dockSize = tester.getSize(find.byType(CompactPlaybackStrip));
    expect(dockSize.width, 400);

    await tester.tap(find.byIcon(Icons.replay_10_rounded));
    await tester.pump();
    expect(lastSeek, const Duration(seconds: 2));

    await tester.tap(find.byIcon(Icons.forward_10_rounded));
    await tester.pump();
    expect(lastSeek, const Duration(seconds: 22));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(toggled, isTrue);
  });

  testWidgets('compact playback strip avoids seeking to the exact end', (
    WidgetTester tester,
  ) async {
    Duration? lastSeek;

    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactPlaybackStrip(
            isPlaying: false,
            position: const Duration(seconds: 2),
            duration: const Duration(seconds: 8),
            onTogglePlay: () {},
            onSeek: (value) {
              lastSeek = value;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.forward_10_rounded));
    await tester.pump();

    expect(lastSeek, const Duration(milliseconds: 7500));
  });
}
