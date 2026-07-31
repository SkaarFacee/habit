// Firebase-free tests: never pump MyApp (it initializes Firebase) and never
// invoke plugin channels. Covers the pure stats helpers plus smoke-renders of
// the dashboard and widget heatmap widgets.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:TrackIt/insights_screen.dart';
import 'package:TrackIt/main.dart';
import 'package:TrackIt/services/stats.dart';
import 'package:TrackIt/services/widget_cards/widget_card_large.dart';
import 'package:TrackIt/services/widget_cards/widget_card_small.dart';
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
    testWidgets('renders a small sample map without errors', (
      WidgetTester tester,
    ) async {
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

    testWidgets('navigates to the older 6-month page without overflow', (
      WidgetTester tester,
    ) async {
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

    testWidgets('collapses gracefully inside a zero-width container', (
      WidgetTester tester,
    ) async {
      await pumpGrid(tester, 0);
      expect(tester.takeException(), isNull);
      expect(find.byType(ChunkedContributionGrid), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 0.0),
        findsWidgets,
      );
    });

    testWidgets('collapses gracefully inside an ultra-narrow container', (
      WidgetTester tester,
    ) async {
      await pumpGrid(tester, 30);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without overflow in a small-but-valid container', (
      WidgetTester tester,
    ) async {
      await pumpGrid(tester, 150);
      expect(tester.takeException(), isNull);
      // Nav bar is present: the grid itself rendered.
      expect(find.byTooltip('Older 6 months'), findsOneWidget);
    });
  });

  group('WidgetHeatmapCard', () {
    testWidgets('renders streak, today count and grid without errors', (
      WidgetTester tester,
    ) async {
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

  group('WidgetCardSmall', () {
    testWidgets('renders streak, today and 14 dots without errors', (
      WidgetTester tester,
    ) async {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          '10-08-2026': [
            {'title': 'a'},
          ],
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 110,
              height: 110,
              child: WidgetCardSmall(
                counts: dailyTaskCounts(tracker),
                stats: computeAppStats(tracker, now: DateTime(2026, 8, 10)),
                isDark: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('TODAY'), findsOneWidget);
    });
  });

  group('WidgetCardLarge', () {
    testWidgets('renders header stats, heatmap and bars without errors', (
      WidgetTester tester,
    ) async {
      final tracker = <String, dynamic>{
        'Work': <String, dynamic>{
          '09-08-2026': [
            {'title': 'a'},
          ],
          '10-08-2026': [
            {'title': 'b'},
          ],
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 320,
              child: WidgetCardLarge(
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
      expect(find.text('BEST STREAK'), findsOneWidget);
      expect(find.text('LAST 7 DAYS'), findsOneWidget);
    });
  });

  group('InsightsScreen', () {
    testWidgets('renders hero stats, charts and segments', (
      WidgetTester tester,
    ) async {
      // Use data anchored to the real today so the week range is non-empty.
      final today = DateTime.now();
      final dateStr =
          '${today.day.toString().padLeft(2, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.year}';
      final liveTracker = <String, dynamic>{
        'Work': <String, dynamic>{
          dateStr: [
            {'title': 'Read', 'category': 'Work', 'difficulty': 'EASY'},
          ],
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                height: 900,
                child: InsightsScreen(trackerData: liveTracker),
              ),
            ),
          ),
        ),
      );

      // Long enough for every staggered entrance timer to fire.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('CATEGORY MIX'), findsOneWidget);
      expect(find.text('ACTIVITY'), findsOneWidget);
      expect(find.text('TOP TASKS'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
    });

    testWidgets('shows the empty state for a fresh tracker', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 900, child: InsightsScreen(trackerData: {})),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('No activity yet'), findsOneWidget);
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

    testWidgets('builds with existing lists preselected', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AddWorkDialog(existingLists: <String>['Work'])),
        ),
      );

      expect(find.text('Log a Task'), findsOneWidget);
      expect(find.text('Sector'), findsOneWidget);
      expect(find.text('Tire Compound'), findsOneWidget);

      await tester.pumpAndSettle();
    });
  });
}
