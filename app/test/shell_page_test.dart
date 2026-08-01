import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:TrackIt/main.dart';

/// Regression: the shell used TickerMode + AnimatedOpacity, which froze the
/// outgoing page fully opaque when navigating back (its fade-out ticker was
/// disabled in the same rebuild), visually stacking a ghost page on top of
/// the dashboard.
void main() {
  testWidgets(
    'ShellPage fades fully in/out and routes taps to the visible page only',
    (WidgetTester tester) async {
      int pageATaps = 0;
      int pageBTaps = 0;
      bool showA = true;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Stack(
                  children: [
                    ShellPage(
                      visible: showA,
                      child: Material(
                        color: Colors.blue,
                        child: TextButton(
                          onPressed: () => pageATaps++,
                          child: const Text('page A'),
                        ),
                      ),
                    ),
                    ShellPage(
                      visible: !showA,
                      child: Material(
                        color: Colors.red,
                        child: TextButton(
                          onPressed: () => pageBTaps++,
                          child: const Text('page B'),
                        ),
                      ),
                    ),
                  ],
                ),
                bottomNavigationBar: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => showA = true),
                        child: const Text('show A'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => showA = false),
                        child: const Text('show B'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      Opacity opacityOf(String pageLabel) {
        final pageFinder = find.ancestor(
          of: find.text(pageLabel),
          matching: find.byType(Opacity),
        );
        return tester.widget<Opacity>(pageFinder.first);
      }

      // Visible page fully opaque, hidden page fully transparent.
      expect(opacityOf('page A').opacity, 1.0);
      expect(opacityOf('page B').opacity, 0.0);

      // Navigate away: outgoing page must fade to 0 (not freeze opaque).
      await tester.tap(find.text('show B'));
      await tester.pumpAndSettle();
      expect(opacityOf('page A').opacity, 0.0);
      expect(opacityOf('page B').opacity, 1.0);

      // Taps reach the visible page only.
      await tester.tap(find.text('page B'));
      await tester.pumpAndSettle();
      expect(pageBTaps, 1);
      expect(pageATaps, 0);

      // Navigate back: same guarantees for the return trip.
      await tester.tap(find.text('show A'));
      await tester.pumpAndSettle();
      expect(opacityOf('page B').opacity, 0.0);
      expect(opacityOf('page A').opacity, 1.0);

      await tester.tap(find.text('page A'));
      await tester.pumpAndSettle();
      expect(pageATaps, 1);
      expect(pageBTaps, 1);
    },
  );
}
