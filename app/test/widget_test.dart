// Firebase-free tests: never pump MyApp (it initializes Firebase) and never
// invoke plugin channels. Covers the pure stats helpers plus smoke-renders of
// the dashboard and widget heatmap widgets.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:TrackIt/main.dart';
import 'package:TrackIt/services/stats.dart';
import 'package:TrackIt/services/widget_heatmap_card.dart';
import 'package:TrackIt/shared/chunked_contribution_grid.dart';

Color _emptyCellColor(DateTime day, int count, String? category) =>
    const Color(0xFFE9EDF3);

void main() {
  group('computeAppStats', () {
    test('counts work days, tasks, today and current streak', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          '07-08-2026': [
            {'title': 'a'},
          ],
          '08-08-2026': [
            {'title': 'b'},
            {'title': 'c'},
          ],
          '09-08-2026': [
            {'title': 'd'},
          ],
        },
      };

      final stats = computeAppStats(tracker, now: DateTime(2026, 8, 9));

      expect(stats.workDays, 3);
      expect(stats.totalTasks, 4);
      expect(stats.todayTasks, 1);
      expect(stats.currentStreak, 3);
      expect(stats.bestStreak, 3);
      expect(stats.lastActiveDaysAgo, 0);
    });

    test('skips a broken current streak but keeps best streak', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          '01-08-2026': [
            {'title': 'a'},
          ],
          '02-08-2026': [
            {'title': 'b'},
          ],
          '06-08-2026': [
            {'title': 'c'},
          ],
        },
      };

      final stats = computeAppStats(tracker, now: DateTime(2026, 8, 9));

      expect(stats.bestStreak, 2);
      expect(stats.currentStreak, 0);
      expect(stats.lastActiveDaysAgo, 3);
    });
  });

  group('dailyTaskCounts', () {
    test('aggregates across lists onto date-only keys', () {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          '07-08-2026': [
            {'title': 'a'},
          ],
          '08-08-2026': [
            {'title': 'b'},
            {'title': 'c'},
          ],
        },
        'Play': <String, dynamic>{
          '08-08-2026': [
            {'title': 'd'},
          ],
          'not-a-date': [
            {'title': 'skipped'},
          ],
        },
      };

      final counts = dailyTaskCounts(tracker);

      expect(counts.length, 2);
      expect(counts[DateTime(2026, 8, 7)], 1);
      expect(counts[DateTime(2026, 8, 8)], 3);
    });

    test('returns empty for an empty tracker', () {
      expect(dailyTaskCounts(<String, dynamic>{}), isEmpty);
    });
  });

  group('ContributionGraph', () {
    testWidgets('renders a small sample map without errors',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ContributionGraph(
                data: <String, dynamic>{
                  '01-08-2026': [
                    {'category': 'Work'},
                  ],
                  '02-08-2026': [
                    {'category': 'Work'},
                    {'category': 'Health'},
                  ],
                  '03-08-2026': [
                    {'category': 'Play'},
                  ],
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.byType(ContributionGraph), findsOneWidget);
    });

    testWidgets('navigates to the older 6-month page without overflow',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ContributionGraph(data: const <String, dynamic>{}),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);

      // Tap the "older" arrow and settle: no RenderFlex overflow may occur.
      await tester.tap(find.byTooltip('Older 6 months'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Older 6 months'), findsOneWidget);
    });
  });

  group('ChunkedContributionGrid', () {
    Future<void> pumpGrid(WidgetTester tester, double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 300,
              child: const ChunkedContributionGrid(
                counts: <DateTime, int>{},
                colorFor: _emptyCellColor,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('collapses gracefully inside a zero-width container',
        (WidgetTester tester) async {
      await pumpGrid(tester, 0);
      expect(tester.takeException(), isNull);
      expect(find.byType(ChunkedContributionGrid), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 0.0),
        findsWidgets,
      );
    });

    testWidgets('collapses gracefully inside an ultra-narrow container',
        (WidgetTester tester) async {
      await pumpGrid(tester, 30);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without overflow in a small-but-valid container',
        (WidgetTester tester) async {
      await pumpGrid(tester, 150);
      expect(tester.takeException(), isNull);
      // Nav bar is present: the grid itself rendered.
      expect(find.byTooltip('Older 6 months'), findsOneWidget);
    });
  });

  group('WidgetHeatmapCard', () {
    testWidgets('renders streak, today count and grid without errors',
        (WidgetTester tester) async {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          '09-08-2026': [
            {'title': 'a'},
          ],
          '10-08-2026': [
            {'title': 'b'},
            {'title': 'c'},
          ],
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 160,
              child: WidgetHeatmapCard(
                counts: dailyTaskCounts(tracker),
                stats: computeAppStats(tracker, now: DateTime(2026, 8, 10)),
                isDark: false,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('2'), findsWidgets);
      expect(find.text('CURRENT STREAK'), findsOneWidget);
      expect(find.text('TASKS TODAY'), findsOneWidget);
    });
  });

  group('AddWorkDialog', () {
    testWidgets('builds for a fresh tracker', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AddWorkDialog(existingLists: <String>[])),
        ),
      );

      expect(find.text('Log a Task'), findsOneWidget);
      expect(find.text('Save Lap'), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('builds with existing lists preselected',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AddWorkDialog(existingLists: <String>['Work']),
          ),
        ),
      );

      expect(find.text('Log a Task'), findsOneWidget);
      expect(find.text('Sector'), findsOneWidget);
      expect(find.text('Tire Compound'), findsOneWidget);

      await tester.pumpAndSettle();
    });
  });
}
