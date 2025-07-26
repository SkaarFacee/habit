import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'shared/neon_ribbon_background.dart';
import 'shared/theme.dart';

class InsightsScreen extends StatefulWidget {
  final Map<String, dynamic> trackerData;

  const InsightsScreen({super.key, required this.trackerData});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedWeek = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Insights'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Weekly Review'),
          ],
        ),
      ),
      body: Stack(
        children: [
          const NeonRibbonBackground(),
          SafeArea(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildWeeklyReviewTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverallPerformanceCard(),
          const SizedBox(height: 24),
          _buildCategoryBreakdownCard(),
        ],
      ),
    );
  }

  Widget _buildOverallPerformanceCard() {
    final stats = _calculateOverallStats();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1E1E1E) : Colors.white).withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: isDark ? Border.all(color: Colors.white12) : null,
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overall Performance', style: TextStyle(color: isDark ? const Color(0xFFE84545) : const Color(0xFF0066CC), fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('Total Tasks', stats['totalTasks'].toString()),
              _buildStatItem('Active Days', stats['workDays'].toString()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('Current Streak', stats['currentStreak'].toString()),
              _buildStatItem('Tasks This Week', stats['thisWeek'].toString()),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, curve: Curves.easeOutCubic);
  }

  Widget _buildCategoryBreakdownCard() {
    final categoryStats = _calculateCategoryStats();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1E1E1E) : Colors.white).withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: isDark ? Border.all(color: Colors.white12) : null,
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Category Breakdown', style: TextStyle(color: isDark ? const Color(0xFFE84545) : const Color(0xFF0066CC), fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          ...categoryStats.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(entry.key, style: const TextStyle(fontSize: 16)),
                  Text(entry.value.toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, curve: Curves.easeOutCubic);
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  Map<String, int> _calculateOverallStats() {
    int totalTasks = 0, thisWeekTasks = 0;
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    Set<DateTime> workDaysList = {};

    widget.trackerData.forEach((listName, listData) {
      if (listData is Map<String, dynamic>) {
        listData.forEach((dateStr, activities) {
          if (activities is List && activities.isNotEmpty) {
            try {
              final parts = dateStr.split('-');
              if (parts.length == 3) {
                final date = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                workDaysList.add(date);
                int tasksOnDay = activities.length;
                totalTasks += tasksOnDay;
                if (!date.isBefore(weekStartDate)) thisWeekTasks += tasksOnDay;
              }
            } catch (e) { /* Ignore invalid date format */ }
          }
        });
      }
    });

    int currentStreak = 0;
    if (workDaysList.isNotEmpty) {
      List<DateTime> sortedDays = workDaysList.toList()..sort((a, b) => b.compareTo(a));
      DateTime checkDate = DateTime(now.year, now.month, now.day);
      if (sortedDays.first.isAtSameMomentAs(checkDate) || sortedDays.first.isAtSameMomentAs(checkDate.subtract(const Duration(days: 1)))) {
        currentStreak = 1;
        for (int i = 0; i < sortedDays.length - 1; i++) {
          if (sortedDays[i].difference(sortedDays[i + 1]).inDays == 1) {
            currentStreak++;
          } else {
            break;
          }
        }
      }
    }
    return {'workDays': workDaysList.length, 'totalTasks': totalTasks, 'currentStreak': currentStreak, 'thisWeek': thisWeekTasks};
  }

  Map<String, int> _calculateCategoryStats() {
    Map<String, int> categoryCounts = {};
    widget.trackerData.forEach((listName, listData) {
      if (listData is Map<String, dynamic>) {
        listData.forEach((dateStr, activities) {
          if (activities is List) {
            for (var activity in activities) {
              if (activity is Map<String, dynamic> && activity.containsKey('category')) {
                final category = activity['category'] as String;
                categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
              }
            }
          }
        });
      }
    });
    return categoryCounts;
  }

  Widget _buildWeeklyReviewTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final weeklyStats = _calculateWeeklyStats(_selectedWeek);
    final topTasks = _getTopTasks(_selectedWeek);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Weekly Review', style: TextStyle(color: isDark ? const Color(0xFFE84545) : const Color(0xFF0066CC), fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
              TextButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text('${_selectedWeek.day}/${_selectedWeek.month}/${_selectedWeek.year}'),
                onPressed: () => _selectWeek(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xFF1E1E1E) : Colors.white).withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
              border: isDark ? Border.all(color: Colors.white12) : null,
              boxShadow: isDark ? null : [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Summary for the Week', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                _buildStatItem('Total Tasks', weeklyStats['totalTasks'].toString()),
                const SizedBox(height: 12),
                _buildStatItem('Most Active Day', weeklyStats['mostActiveDay']),
                const SizedBox(height: 12),
                Text(weeklyStats['summary'] as String),
              ],
            ),
          ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, curve: Curves.easeOutCubic),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xFF1E1E1E) : Colors.white).withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
              border: isDark ? Border.all(color: Colors.white12) : null,
              boxShadow: isDark ? null : [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Work Rating', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        _buildStatItem('Rating', '${weeklyStats['workRating']}/10'),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 20, thickness: 1),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Weekly Change', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        _buildStatItem(
                          weeklyStats['weeklyChange'] >= 0 ? 'Increase 🚀' : 'Decrease 📉',
                          weeklyStats['weeklyChange'].abs().toString(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, curve: Curves.easeOutCubic),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xFF1E1E1E) : Colors.white).withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
              border: isDark ? Border.all(color: Colors.white12) : null,
              boxShadow: isDark ? null : [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Top 3 Tasks', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                if (topTasks.isEmpty)
                  const Text('No tasks recorded for this week.')
                else
                  ...topTasks.map((task) => Text('- ${task['title']}')).toList(),
              ],
            ),
          ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }

  Future<void> _selectWeek(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedWeek,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedWeek) {
      setState(() {
        _selectedWeek = picked;
      });
    }
  }

  Map<String, dynamic> _calculateWeeklyStats(DateTime week) {
    int totalTasks = 0;
    Map<String, int> dailyTaskCounts = {};
    List<String> categories = [];
    List<String> taskTitles = [];

    final startOfWeek = week.subtract(Duration(days: week.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    widget.trackerData.forEach((listName, listData) {
      if (listData is Map<String, dynamic>) {
        listData.forEach((dateStr, activities) {
          if (activities is List) {
            final date = _parseDate(dateStr);
            if (!date.isBefore(startOfWeek) && !date.isAfter(endOfWeek)) {
              totalTasks += activities.length;
              final day = _dayOfWeek(date.weekday);
              dailyTaskCounts[day] = (dailyTaskCounts[day] ?? 0) + activities.length;
              for (var activity in activities) {
                if (activity is Map<String, dynamic>) {
                  categories.add(activity['category']);
                  taskTitles.add(activity['title']);
                }
              }
            }
          }
        });
      }
    });

    String mostActiveDay = 'N/A';
    if (dailyTaskCounts.isNotEmpty) {
      mostActiveDay = dailyTaskCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }

    String summary = 'This week you completed $totalTasks tasks. ';
    if (categories.isNotEmpty) {
      summary += 'You focused on ${categories.toSet().join(', ')}. ';
    }
    if (taskTitles.isNotEmpty) {
      summary += 'Some of the tasks you worked on were: ${taskTitles.take(2).join(', ')}.';
    }

    final workRating = (totalTasks / 10 * 10).clamp(0, 10).toInt();

    int previousWeekTasks = 0;
    final startOfPreviousWeek = startOfWeek.subtract(const Duration(days: 7));
    final endOfPreviousWeek = startOfWeek.subtract(const Duration(days: 1));
    widget.trackerData.forEach((listName, listData) {
      if (listData is Map<String, dynamic>) {
        listData.forEach((dateStr, activities) {
          if (activities is List) {
            final date = _parseDate(dateStr);
            if (!date.isBefore(startOfPreviousWeek) && !date.isAfter(endOfPreviousWeek)) {
              previousWeekTasks += activities.length;
            }
          }
        });
      }
    });

    final weeklyChange = totalTasks - previousWeekTasks;

    return {
      'totalTasks': totalTasks,
      'mostActiveDay': mostActiveDay,
      'summary': summary,
      'workRating': workRating,
      'weeklyChange': weeklyChange
    };
  }

  List<Map<String, dynamic>> _getTopTasks(DateTime week) {
    Map<String, int> taskCounts = {};
    final startOfWeek = week.subtract(Duration(days: week.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    widget.trackerData.forEach((listName, listData) {
      if (listData is Map<String, dynamic>) {
        listData.forEach((dateStr, activities) {
          if (activities is List) {
            final date = _parseDate(dateStr);
            if (!date.isBefore(startOfWeek) && !date.isAfter(endOfWeek)) {
              for (var activity in activities) {
                if (activity is Map<String, dynamic>) {
                  final title = activity['title'] as String;
                  taskCounts[title] = (taskCounts[title] ?? 0) + 1;
                }
              }
            }
          }
        });
      }
    });

    final sortedTasks = taskCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sortedTasks
        .take(3)
        .map((e) => {'title': e.key})
        .toList();
  }

  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    return parts.length == 3 ? DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0])) : DateTime.now();
  }

  String _dayOfWeek(int day) {
    switch (day) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return '';
    }
  }
}