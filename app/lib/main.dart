import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'shared/neon_ribbon_background.dart';
import 'shared/theme.dart';
import 'insights_screen.dart';
import 'atomic_habits_screen.dart';

// Main app entry point
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

// Root application widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Work Tracker',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: const WorkTrackerScreen(),
        );
      },
    );
  }
}

// Main screen for tracking work
class WorkTrackerScreen extends StatelessWidget {
  const WorkTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final DocumentReference<Map<String, dynamic>> trackerDoc =
        FirebaseFirestore.instance.collection('habit').doc('tracker');

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Dashboard'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Atomic Habits',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AtomicHabitsScreen(),
                ),
              );
            },
          ).animate().fade(delay: 200.ms).scale(),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              themeNotifier.value == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            onPressed: () {
              themeNotifier.value = themeNotifier.value == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
            },
          ).animate().fade(delay: 200.ms).scale(),
        ],
      ),
      body: Stack(
        children: [
          const NeonRibbonBackground(),
          SafeArea(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: trackerDoc.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return _buildErrorState();
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState(context);
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return _buildEmptyState(
                    () => _showAddWorkDialog(context, []),
                  );
                }

                final data = snapshot.data!.data() ?? {};
                final trackerData =
                    (data['Tracker'] as Map<String, dynamic>?) ?? {};
                final listNames = trackerData.keys.toList();

                return _buildContent(context, trackerData, listNames);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add-lap-button',
        onPressed: () async {
          final doc = await trackerDoc.get();
          final data = doc.data();
          final trackerData = data?['Tracker'] as Map<String, dynamic>? ?? {};
          _showAddWorkDialog(context, trackerData.keys.toList());
        },
        child: const Icon(Icons.add, color: Colors.white),
      ).animate().scale(delay: 300.ms),
    );
  }

  void _showAddWorkDialog(BuildContext context, List<String> listNames) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      pageBuilder: (context, animation, secondaryAnimation) {
        return AddWorkDialog(existingLists: listNames);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            ),
          ),
          child: child,
        );
      },
      transitionDuration: 400.ms,
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white10 : Colors.grey.shade200;
    final highlightColor =
        isDark ? Colors.white.withOpacity(0.2) : Colors.grey.shade50;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            height: 230,
            width: double.infinity,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: 400,
            width: double.infinity,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      ),
    ).animate(onPlay: (controller) => controller.repeat()).shimmer(
          duration: 1200.ms,
          color: highlightColor,
        );
  }

  Widget _buildErrorState() {
    return const Center(child: Text('Something went wrong'));
  }

  Widget _buildEmptyState(VoidCallback onAdd) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.flag_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No Tracks Yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onAdd,
            child: const Text('Tap + to start a new track'),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms);
  }

  Widget _buildContent(
    BuildContext context,
    Map<String, dynamic> trackerData,
    List<String> listNames,
  ) {
    if (listNames.isEmpty) {
      return _buildEmptyState(() => _showAddWorkDialog(context, []));
    }

    final workListCards = listNames.map((listName) {
      final listData = trackerData[listName] as Map<String, dynamic>? ?? {};
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: WorkListCard(
          title: listName,
          data: listData,
        ),
      );
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(context, trackerData)
              .animate()
              .fadeIn(duration: 600.ms)
              .slideY(begin: 0.2, curve: Curves.easeOutCubic),
          const SizedBox(height: 24),
          ...workListCards
              .animate(interval: 100.ms)
              .fadeIn(duration: 500.ms)
              .slideX(begin: -0.2, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, Map<String, dynamic> tracker) {
    final stats = _calculateOverallStats(tracker);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardColor = isDark
        ? const Color(0xFF1E1E1E).withOpacity(0.88)
        : Colors.white.withOpacity(0.96);

    final primaryAccent =
        isDark ? const Color(0xFFE84545) : const Color(0xFF0066CC);

    final subtitleColor = isDark ? Colors.white60 : Colors.black54;
    final dividerColor = isDark ? Colors.white12 : Colors.black.withOpacity(0.06);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OVERVIEW',
            style: TextStyle(
              color: primaryAccent,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Quick summary of your tracker',
            style: TextStyle(
              fontSize: 13,
              color: subtitleColor,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Active Days',
                  stats['workDays'] ?? 0,
                  Icons.calendar_today_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Total Tasks',
                  stats['totalTasks'] ?? 0,
                  Icons.outlined_flag,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'Current Streak',
                  stats['currentStreak'] ?? 0,
                  Icons.local_fire_department_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryItem(
                  context,
                  'This Week',
                  stats['thisWeek'] ?? 0,
                  Icons.date_range_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(color: dividerColor, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => InsightsScreen(
                          trackerData: tracker,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.insights_outlined),
                  label: const Text('Insights'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AtomicHabitsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Atomic Habits'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    BuildContext context,
    String label,
    int value,
    IconData icon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    final labelColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Animate()
                    .custom(
                      duration: 1000.ms,
                      curve: Curves.easeOutCubic,
                      begin: 0,
                      end: value.toDouble(),
                      builder: (_, val, __) => Text(
                        val.toInt().toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                    .fadeIn(),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: labelColor),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, int> _calculateOverallStats(Map<String, dynamic> tracker) {
    int totalTasks = 0;
    int thisWeekTasks = 0;
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate =
        DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final Set<DateTime> workDaysList = {};

    tracker.forEach((listName, listData) {
      if (listData is Map<String, dynamic>) {
        listData.forEach((dateStr, activities) {
          if (activities is List && activities.isNotEmpty) {
            try {
              final parts = dateStr.split('-');
              if (parts.length == 3) {
                final date = DateTime(
                  int.parse(parts[2]),
                  int.parse(parts[1]),
                  int.parse(parts[0]),
                );
                final dayOnly = DateTime(date.year, date.month, date.day);
                workDaysList.add(dayOnly);
                final tasksOnDay = activities.length;
                totalTasks += tasksOnDay;
                if (!dayOnly.isBefore(weekStartDate)) {
                  thisWeekTasks += tasksOnDay;
                }
              }
            } catch (_) {}
          }
        });
      }
    });

    int currentStreak = 0;
    if (workDaysList.isNotEmpty) {
      final sortedDays = workDaysList.toList()
        ..sort((a, b) => b.compareTo(a));

      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      if (sortedDays.first == today || sortedDays.first == yesterday) {
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

    return {
      'workDays': workDaysList.length,
      'totalTasks': totalTasks,
      'currentStreak': currentStreak,
      'thisWeek': thisWeekTasks,
    };
  }
}

// Dialog for adding a new work entry
class AddWorkDialog extends StatefulWidget {
  final List<String> existingLists;
  const AddWorkDialog({super.key, required this.existingLists});

  @override
  State<AddWorkDialog> createState() => _AddWorkDialogState();
}

class _AddWorkDialogState extends State<AddWorkDialog> {
  final _titleController = TextEditingController();
  final _newListController = TextEditingController();
  String? _selectedList;
  bool _isNewList = false;

  String _selectedDifficulty = 'EASY';
  String _selectedCategory = 'Work';
  DateTime _selectedDate = DateTime.now();

  final List<String> _difficulties = ['EASY', 'MEDIUM', 'HARD'];
  final List<String> _categories = ['Work', 'Health', 'Play'];

  @override
  void initState() {
    super.initState();
    if (widget.existingLists.isNotEmpty) {
      _selectedList = widget.existingLists.first;
    } else {
      _isNewList = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Hero(
      tag: 'add-lap-button',
      child: AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: const Text('Log a Task'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.existingLists.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _isNewList ? '---NEW---' : _selectedList,
                  decoration: const InputDecoration(
                    labelText: 'Track',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    ...widget.existingLists.map(
                      (list) => DropdownMenuItem(
                        value: list,
                        child: Text(list),
                      ),
                    ),
                    const DropdownMenuItem(
                      value: '---NEW---',
                      child: Text('Create New Track...'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      if (value == '---NEW---') {
                        _isNewList = true;
                        _selectedList = null;
                      } else {
                        _isNewList = false;
                        _selectedList = value;
                      }
                    });
                  },
                ),
              if (_isNewList)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextField(
                    controller: _newListController,
                    decoration: const InputDecoration(
                      labelText: 'New Track Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Lap Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Sector',
                  border: OutlineInputBorder(),
                ),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedCategory = value!);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDifficulty,
                decoration: const InputDecoration(
                  labelText: 'Tire Compound',
                  border: OutlineInputBorder(),
                ),
                items: _difficulties
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedDifficulty = value!);
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text(
                  'Date: ${_selectedDate.toLocal().toString().split(' ')[0]}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: _selectDate,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _saveWorkEntry,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isDark ? const Color(0xFFE84545) : const Color(0xFF0066CC),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save Lap'),
          ),
        ],
      ).animate().fadeIn(),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveWorkEntry() async {
    final listName = _isNewList ? _newListController.text.trim() : _selectedList;

    if (listName == null || listName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or create a track.')),
      );
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task description.')),
      );
      return;
    }

    final dateStr =
        '${_selectedDate.day.toString().padLeft(2, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.year}';

    final newEntry = {
      'title': _titleController.text.trim(),
      'category': _selectedCategory,
      'difficulty': _selectedDifficulty,
    };

    final trackerRef =
        FirebaseFirestore.instance.collection('habit').doc('tracker');

    try {
      await trackerRef.set(
        {
          'Tracker': {
            listName: {dateStr: FieldValue.arrayUnion([newEntry])}
          }
        },
        SetOptions(merge: true),
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lap saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _newListController.dispose();
    super.dispose();
  }
}

// Card for displaying a list of work items
class WorkListCard extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;

  const WorkListCard({super.key, required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1E1E1E) : Colors.white).withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
        ),
        boxShadow: isDark
            ? null
            : [
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
          _buildHeader(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: ContributionGraph(data: data),
          ),
          if (_getRecentWorkEntries().isNotEmpty) ...[
            Divider(
              height: 1,
              indent: 20,
              endIndent: 20,
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
            _buildRecentWork(context),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        isDark ? const Color(0xFFE84545) : const Color(0xFF0066CC);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Last 365 Days',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentWork(BuildContext context) {
    final recentEntries = _getRecentWorkEntries();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Tasks',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          ...recentEntries
              .take(3)
              .map((entry) => _buildWorkItem(context, entry))
              .toList()
              .animate(interval: 50.ms)
              .fadeIn(duration: 300.ms)
              .slideX(begin: -0.1, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }

  Widget _buildWorkItem(BuildContext context, Map<String, dynamic> entry) {
    final category = entry['category']?.toString() ?? 'Work';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            _getIconForCategory(category),
            color: _getDifficultyColor(entry['difficulty']?.toString() ?? 'EASY'),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['title']?.toString() ?? 'No title',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry['date'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${entry['date']} - $category',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getRecentWorkEntries() {
    final entries = <Map<String, dynamic>>[];

    data.forEach((dateStr, activities) {
      if (activities is List) {
        for (final activity in activities) {
          if (activity is Map<String, dynamic>) {
            entries.add({...Map<String, dynamic>.from(activity), 'date': dateStr});
          }
        }
      }
    });

    entries.sort(
      (a, b) => _parseDate(
        b['date'] ?? '',
      ).compareTo(_parseDate(a['date'] ?? '')),
    );

    return entries;
  }

  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    return parts.length == 3
        ? DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          )
        : DateTime.now();
  }

  IconData _getIconForCategory(String category) {
    switch (category) {
      case 'Health':
        return Icons.directions_run;
      case 'Work':
        return Icons.menu_book;
      case 'Play':
        return Icons.sentiment_satisfied;
      default:
        return Icons.flag;
    }
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toUpperCase()) {
      case 'EASY':
        return const Color(0xFF34C759);
      case 'MEDIUM':
        return const Color(0xFFFF9500);
      case 'HARD':
        return const Color(0xFFE84545);
      default:
        return Colors.grey;
    }
  }
}

// GitHub-style contribution graph widget
class ContributionGraph extends StatelessWidget {
  final Map<String, dynamic> data;
  const ContributionGraph({super.key, required this.data});

  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return DateTime.now();
    return DateTime(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );
  }

  Map<DateTime, Map<String, dynamic>> _getWorkDataMap() {
    final Map<DateTime, Map<String, dynamic>> dataMap = {};

    data.forEach((dateStr, activities) {
      if (activities is List && activities.isNotEmpty) {
        try {
          final date = _parseDate(dateStr);
          final normalized = DateTime(date.year, date.month, date.day);
          String? firstCategory;

          if (activities.first is Map) {
            firstCategory = activities.first['category']?.toString();
          }

          if (firstCategory != null) {
            dataMap[normalized] = {
              'category': firstCategory,
              'count': activities.length,
            };
          }
        } catch (_) {}
      }
    });

    return dataMap;
  }

  Color _getColorForCategory(BuildContext context, String? category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (category) {
      case 'Work':
        return isDark ? const Color(0xFF5E5CE6) : const Color(0xFF0066CC);
      case 'Health':
        return const Color(0xFF34C759);
      case 'Play':
        return const Color(0xFFFF9500);
      default:
        return isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;
    }
  }

  @override
  Widget build(BuildContext context) {
    final workDataMap = _getWorkDataMap();
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final oneYearAgo = todayOnly.subtract(const Duration(days: 365));

    final startDayOffset = oneYearAgo.weekday % 7;
    final totalDays =
        todayOnly.difference(oneYearAgo).inDays + 1 + startDayOffset;
    final totalWeeks = (totalDays / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 120,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellSize = (constraints.maxHeight - (7 * 3)) / 7;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: List.generate(totalWeeks, (weekIndex) {
                    return Column(
                      children: List.generate(7, (dayIndex) {
                        final overallIndex = (weekIndex * 7) + dayIndex;

                        if (overallIndex < startDayOffset) {
                          return SizedBox(width: cellSize, height: cellSize);
                        }

                        final date = oneYearAgo.add(
                          Duration(days: overallIndex - startDayOffset),
                        );

                        if (date.isAfter(todayOnly)) {
                          return SizedBox(width: cellSize, height: cellSize);
                        }

                        return _buildCell(
                          context,
                          date,
                          workDataMap,
                          cellSize,
                        )
                            .animate()
                            .fadeIn(
                              delay: (overallIndex * 2).ms,
                              duration: 400.ms,
                            )
                            .scale(
                              delay: (overallIndex * 2).ms,
                              duration: 400.ms,
                              curve: Curves.elasticOut,
                              begin: const Offset(0.5, 0.5),
                            );
                      }),
                    );
                  }),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildMonthLabelsRow(oneYearAgo, startDayOffset, totalWeeks),
        const SizedBox(height: 16),
        _buildLegend(context),
      ],
    );
  }

  Widget _buildMonthLabelsRow(
    DateTime startDate,
    int startDayOffset,
    int totalWeeks,
  ) {
    const monthAbbreviations = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final labels = <Widget>[];
    int? lastMonth;
    const double weekWidth = 15.0;

    for (int i = 0; i < totalWeeks; i++) {
      final date = startDate.add(Duration(days: (i * 7) - startDayOffset));

      if (lastMonth == null || date.month != lastMonth) {
        labels.add(
          SizedBox(
            width: weekWidth * 1.5,
            child: Text(
              monthAbbreviations[date.month - 1],
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        );
        lastMonth = date.month;
      } else {
        labels.add(const SizedBox(width: weekWidth));
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(children: labels),
    );
  }

  Widget _buildCell(
    BuildContext context,
    DateTime date,
    Map<DateTime, Map<String, dynamic>> workDataMap,
    double size,
  ) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final dayData = workDataMap[dateOnly];
    final category = dayData?['category'] as String?;
    final count = dayData?['count'] as int? ?? 0;
    final color = _getColorForCategory(context, category);

    String tooltipMessage = '${date.day}-${date.month}-${date.year}\n';
    if (count > 0 && category != null) {
      tooltipMessage += '$count ${category.toLowerCase()} ${count == 1 ? 'task' : 'tasks'}';
    } else {
      tooltipMessage += 'No tasks';
    }

    return Tooltip(
      message: tooltipMessage,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    const categories = ['Work', 'Health', 'Play'];

    final legendItems = categories
        .expand(
          (category) => [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _getColorForCategory(context, category),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              category,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(width: 10),
          ],
        )
        .toList();

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: legendItems
          .animate(interval: 50.ms)
          .fadeIn(duration: 300.ms)
          .slideX(begin: -0.1),
    );
  }
}