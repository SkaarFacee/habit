import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Goals Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const FirestoreListScreen(title: 'Daily Goals Tracker'),
    );
  }
}

class Task {
  final String title;
  final String category;
  final String difficulty;

  Task({
    required this.title,
    required this.category,
    required this.difficulty,
  });

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      title: map['title'] ?? '',
      category: map['category'] ?? '',
      difficulty: map['difficulty'] ?? 'EASY',
    );
  }

  int get difficultyWeight {
    switch (difficulty.toUpperCase()) {
      case 'EASY':
        return 1;
      case 'MEDIUM':
        return 2;
      case 'HARD':
        return 3;
      default:
        return 1;
    }
  }
}

class DayContribution {
  final DateTime date;
  final List<Task> tasks;
  final Map<String, int> categoryWeights;
  final String dominantCategory;
  final int totalWeight;

  DayContribution({
    required this.date,
    required this.tasks,
    required this.categoryWeights,
    required this.dominantCategory,
    required this.totalWeight,
  });
}

class FirestoreListScreen extends StatelessWidget {
  const FirestoreListScreen({super.key, required this.title});
  final String title;

  static const Map<String, Color> categoryColors = {
    'Work': Color(0xFF1DB954),
    'Health': Color(0xFFFF6B6B),
    'Personal': Color(0xFF4ECDC4),
    'Education': Color(0xFFFFE66D),
    'Social': Color(0xFF9B59B6),
    'Finance': Color(0xFF3498DB),
    'Hobbies': Color(0xFFFF8C00),
  };

  Color getCategoryColor(String category) {
    return categoryColors[category] ?? Colors.grey;
  }

  Color getContributionColor(DayContribution contribution) {
    if (contribution.totalWeight == 0) {
      return Colors.grey[200]!;
    }

    final baseColor = getCategoryColor(contribution.dominantCategory);
    final intensity = math.min(contribution.totalWeight / 10.0, 1.0);

    return Color.lerp(
      baseColor.withOpacity(0.2),
      baseColor,
      intensity,
    )!;
  }

  List<DayContribution> processTrackerData(Map<String, dynamic> trackerData) {
    final contributions = <DayContribution>[];

    trackerData.forEach((listName, listData) {
      if (listData is Map<String, dynamic>) {
        listData.forEach((dateStr, tasksData) {
          try {
            final date = _parseDate(dateStr);
            final tasks = <Task>[];

            if (tasksData is List) {
              for (var taskData in tasksData) {
                if (taskData is Map<String, dynamic>) {
                  tasks.add(Task.fromMap(taskData));
                }
              }
            }

            final categoryWeights = <String, int>{};
            var totalWeight = 0;

            for (var task in tasks) {
              categoryWeights[task.category] =
                  (categoryWeights[task.category] ?? 0) + task.difficultyWeight;
              totalWeight += task.difficultyWeight;
            }

            String dominantCategory = '';
            int maxWeight = 0;
            categoryWeights.forEach((category, weight) {
              if (weight > maxWeight) {
                maxWeight = weight;
                dominantCategory = category;
              }
            });

            contributions.add(DayContribution(
              date: date,
              tasks: tasks,
              categoryWeights: categoryWeights,
              dominantCategory: dominantCategory,
              totalWeight: totalWeight,
            ));
          } catch (e) {
            print('Error parsing date: $dateStr, $e');
          }
        });
      }
    });

    return contributions;
  }

  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length == 3) {
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      return DateTime(year, month, day);
    }
    throw FormatException('Invalid date format: $dateStr');
  }

  Widget buildContributionGraph(BuildContext context, List<DayContribution> contributions) {
    final now = DateTime.now();
    final startDate = DateTime(now.year, 1, 1);
    final endDate = DateTime(now.year, 12, 31);

    final contributionMap = <String, DayContribution>{};
    for (var contribution in contributions) {
      final key = '${contribution.date.day}-${contribution.date.month}-${contribution.date.year}';
      contributionMap[key] = contribution;
    }

    final weeks = <List<DateTime>>[];
    var currentDate = startDate;

    while (currentDate.weekday != DateTime.monday) {
      currentDate = currentDate.subtract(const Duration(days: 1));
    }

    while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
      final week = <DateTime>[];
      for (int i = 0; i < 7; i++) {
        if (currentDate.year == now.year) {
          week.add(DateTime(currentDate.year, currentDate.month, currentDate.day));
        }
        currentDate = currentDate.add(const Duration(days: 1));
      }
      if (week.isNotEmpty) {
        weeks.add(week);
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contribution Activity',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: weeks.map((week) {
                return Column(
                  children: week.map((date) {
                    final key = '${date.day}-${date.month}-${date.year}';
                    final contribution = contributionMap[key];

                    return Tooltip(
                      message: contribution != null
                          ? '${date.day}/${date.month}/${date.year}\n'
                              '${contribution.tasks.length} tasks\n'
                              'Total weight: ${contribution.totalWeight}'
                          : '${date.day}/${date.month}/${date.year}\nNo activity',
                      child: Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: contribution != null
                              ? getContributionColor(contribution)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          buildLegend(),
        ],
      ),
    );
  }

  Widget buildLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Categories:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: categoryColors.entries.map((entry) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: entry.value,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(entry.key),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Less'),
            const SizedBox(width: 8),
            ...List.generate(5, (index) {
              return Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2 + (index * 0.2)),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
            const SizedBox(width: 8),
            const Text('More'),
          ],
        ),
      ],
    );
  }

  Widget buildCategoryBreakdown(BuildContext context, List<DayContribution> contributions) {
    final categoryTotals = <String, int>{};
    final categoryDays = <String, int>{};

    for (var contribution in contributions) {
      contribution.categoryWeights.forEach((category, weight) {
        categoryTotals[category] = (categoryTotals[category] ?? 0) + weight;
        categoryDays[category] = (categoryDays[category] ?? 0) + 1;
      });
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Category Breakdown',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...categoryTotals.entries.map((entry) {
            final category = entry.key;
            final totalWeight = entry.value;
            final days = categoryDays[category] ?? 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: getCategoryColor(category).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: getCategoryColor(category).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: getCategoryColor(category),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '$days days • Total weight: $totalWeight',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DocumentReference trackerDoc =
        FirebaseFirestore.instance.collection('habit').doc('tracker');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: trackerDoc.get(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('No tracker data found.'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final trackerData = data['Tracker'] as Map<String, dynamic>? ?? {};
          final contributions = processTrackerData(trackerData);

          return SingleChildScrollView(
            child: Column(
              children: [
                buildContributionGraph(context, contributions),
                const Divider(),
                buildCategoryBreakdown(context, contributions),
              ],
            ),
          );
        },
      ),
    );
  }
}
