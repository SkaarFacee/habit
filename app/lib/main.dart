import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Work Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF2F2F7),
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFF1C1C1E),
            fontSize: 34,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: const WorkTrackerScreen(),
    );
  }
}

// Main screen for tracking work
class WorkTrackerScreen extends StatelessWidget {
  const WorkTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final DocumentReference trackerDoc =
        FirebaseFirestore.instance.collection('habit').doc('tracker');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Tracker'),
        centerTitle: false,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: trackerDoc.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _buildErrorState();
          if (snapshot.connectionState == ConnectionState.waiting) return _buildLoadingState();
          if (!snapshot.hasData || !snapshot.data!.exists) {
            print(snapshot.data);
            return _buildEmptyState(() => _showAddWorkDialog(context, []));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final trackerData = data['Tracker'] as Map<String, dynamic>? ?? {};
          final listNames = trackerData.keys.toList();

          return _buildContent(context, trackerData, listNames);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          trackerDoc.get().then((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            final trackerData = data?['Tracker'] as Map<String, dynamic>? ?? {};
            _showAddWorkDialog(context, trackerData.keys.toList());
          });
        },
        backgroundColor: const Color(0xFF007AFF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // Shows the dialog to add a new work entry
  void _showAddWorkDialog(BuildContext context, List<String> listNames) {
    showDialog(
      context: context,
      builder: (context) => AddWorkDialog(existingLists: listNames),
    );
  }

  // UI Widgets
  Widget _buildLoadingState() => const Center(child: CircularProgressIndicator());
  Widget _buildErrorState() => const Center(child: Text('Something went wrong'));
  Widget _buildEmptyState(VoidCallback onAdd) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.work_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No work tracked yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onAdd,
            child: const Text('Tap + to start tracking your work'),
          ),
        ],
      ),
    );
  }

  // Main content view with summary and lists
  Widget _buildContent(BuildContext context, Map<String, dynamic> trackerData, List<String> listNames) {
    if (listNames.isEmpty) {
      return _buildEmptyState(() => _showAddWorkDialog(context, []));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(trackerData),
          const SizedBox(height: 24),
          ...listNames.map((listName) {
            final listData = trackerData[listName] as Map<String, dynamic>? ?? {};
            return Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: WorkListCard(
                title: listName,
                data: listData,
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // Summary Card
  Widget _buildSummaryCard(Map<String, dynamic> tracker) {
    final stats = _calculateOverallStats(tracker);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF007AFF).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Overall Summary', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _buildSummaryItem('Work Days', stats['workDays'].toString(), Icons.calendar_today),
            _buildSummaryItem('Total Tasks', stats['totalTasks'].toString(), Icons.task_alt),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _buildSummaryItem('Work Streak', '${stats['currentStreak']} days', Icons.local_fire_department),
            _buildSummaryItem('This Week', stats['thisWeek'].toString(), Icons.date_range),
          ]),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Row(children: [
      Icon(icon, color: Colors.white70, size: 20),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    ]);
  }

  Map<String, int> _calculateOverallStats(Map<String, dynamic> tracker) {
    int totalTasks = 0, thisWeekTasks = 0;
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    Set<DateTime> workDaysList = {};

    tracker.forEach((listName, listData) {
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
  final List<String> _categories = ['Work', 'Health', 'Learning', 'Personal'];

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
    return AlertDialog(
      title: const Text('Add Entry'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // List Selection Dropdown or New List Text Field
            if (widget.existingLists.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _isNewList ? '---NEW---' : _selectedList,
                decoration: const InputDecoration(labelText: 'List', border: OutlineInputBorder()),
                items: [
                  ...widget.existingLists.map((list) => DropdownMenuItem(value: list, child: Text(list))),
                  const DropdownMenuItem(value: '---NEW---', child: Text('Create New List...')),
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
                padding: const EdgeInsets.only(top: 16.0),
                child: TextField(
                  controller: _newListController,
                  decoration: const InputDecoration(labelText: 'New List Name', border: OutlineInputBorder()),
                ),
              ),

            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Task Description', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (value) => setState(() => _selectedCategory = value!)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedDifficulty,
              decoration: const InputDecoration(labelText: 'Difficulty', border: OutlineInputBorder()),
              items: _difficulties.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (value) => setState(() => _selectedDifficulty = value!)),
            const SizedBox(height: 16),
            ListTile(
              title: Text('Date: ${_selectedDate.toLocal().toString().split(' ')[0]}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDate,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saveWorkEntry,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF), foregroundColor: Colors.white),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) setState(() => _selectedDate = picked);
  }

  Future<void> _saveWorkEntry() async {
    final listName = _isNewList ? _newListController.text.trim() : _selectedList;
    if (listName == null || listName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select or create a list.')));
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a task description.')));
      return;
    }

    final dateStr = '${_selectedDate.day.toString().padLeft(2, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.year}';
    final newEntry = {'title': _titleController.text.trim(), 'category': _selectedCategory, 'difficulty': _selectedDifficulty};
    final trackerRef = FirebaseFirestore.instance.collection('habit').doc('tracker');

    try {
      await trackerRef.set({
        'Tracker': {
          listName: {dateStr: FieldValue.arrayUnion([newEntry])}
        }
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry saved successfully!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving entry: $e'), backgroundColor: Colors.red));
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const Divider(height: 1, indent: 20, endIndent: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: ContributionGraph(data: data),
          ),
          if (_getRecentWorkEntries().isNotEmpty) ...[
            const Divider(height: 1, indent: 20, endIndent: 20),
            _buildRecentWork(),
          ]
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFF007AFF).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: const Text('Last 365 Days', style: TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRecentWork() {
    final recentEntries = _getRecentWorkEntries();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Activities', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey[700])),
          const SizedBox(height: 12),
          ...recentEntries.take(3).map((entry) => _buildWorkItem(entry)),
        ],
      ),
    );
  }

  Widget _buildWorkItem(Map<String, dynamic> entry) {
    final category = entry['category']?.toString() ?? 'Work';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey[200]!), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(_getIconForCategory(category), color: _getDifficultyColor(entry['difficulty']?.toString() ?? 'EASY'), size: 20),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry['title']?.toString() ?? 'No title', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (entry['date'] != null) ...[
            const SizedBox(height: 4),
            Text('${entry['date']} - $category', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ]
        ])),
      ]),
    );
  }

  List<Map<String, dynamic>> _getRecentWorkEntries() {
    List<Map<String, dynamic>> entries = [];
    data.forEach((dateStr, activities) {
      if (activities is List) {
        for (var activity in activities) {
          if (activity is Map<String, dynamic>) {
            entries.add({...Map<String, dynamic>.from(activity), 'date': dateStr});
          }
        }
      }
    });
    entries.sort((a, b) => _parseDate(b['date'] ?? '').compareTo(_parseDate(a['date'] ?? '')));
    return entries;
  }

  DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    return parts.length == 3 ? DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0])) : DateTime.now();
  }

  IconData _getIconForCategory(String category) {
    switch (category) {
      case 'Health': return Icons.favorite_border;
      case 'Learning': return Icons.school_outlined;
      case 'Personal': return Icons.person_outline;
      case 'Work':
      default: return Icons.work_outline;
    }
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toUpperCase()) {
      case 'EASY': return const Color(0xFF34C759);
      case 'MEDIUM': return const Color(0xFFFF9500);
      case 'HARD': return const Color(0xFFFF3B30);
      default: return Colors.grey;
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
    return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
  }

  Map<DateTime, Map<String, dynamic>> _getWorkDataMap() {
    final Map<DateTime, Map<String, dynamic>> dataMap = {};
    data.forEach((dateStr, activities) {
      if (activities is List && activities.isNotEmpty) {
        try {
          final date = _parseDate(dateStr);
          String? firstCategory;
          if (activities.first is Map) {
            firstCategory = activities.first['category']?.toString();
          }
          if (firstCategory != null) {
            dataMap[date] = {'category': firstCategory, 'count': activities.length};
          }
        } catch (e) { /* Ignore parsing errors */ }
      }
    });
    return dataMap;
  }

  Color _getColorForCategory(String? category) {
    switch (category) {
      case 'Work':
        return const Color(0xFF0077b6);
      case 'Health':
        return const Color(0xFF34C759);
      case 'Learning':
        return const Color(0xFFFF9500);
      case 'Personal':
        return const Color(0xFF5856D6);
      default:
        return const Color(0xFFEBEDF0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workDataMap = _getWorkDataMap();
    final today = DateTime.now();
    final oneYearAgo = today.subtract(const Duration(days: 365));

    final startDayOffset = oneYearAgo.weekday % 7;
    final totalDays = today.difference(oneYearAgo).inDays + 1 + startDayOffset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 140,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double cellSize = (constraints.maxHeight - (7 * 3)) / 7; // Fixed calculation
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: List.generate((totalDays / 7).ceil(), (weekIndex) {
                    return Column(
                      children: List.generate(7, (dayIndex) {
                        final overallIndex = (weekIndex * 7) + dayIndex;
                        if (overallIndex < startDayOffset) {
                          return SizedBox(width: cellSize, height: cellSize);
                        }
                        final date = oneYearAgo.add(Duration(days: overallIndex - startDayOffset));
                        if (date.isAfter(today)) {
                          return SizedBox(width: cellSize, height: cellSize);
                        }
                        return _buildCell(date, workDataMap, cellSize);
                      }),
                    );
                  }),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildLegend(),
      ],
    );
  }

  Widget _buildCell(DateTime date, Map<DateTime, Map<String, dynamic>> workDataMap, double size) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final dayData = workDataMap[dateOnly];
    final category = dayData?['category'] as String?;
    final count = dayData?['count'] as int? ?? 0;
    final color = _getColorForCategory(category);

    String tooltipMessage = '${date.day}-${date.month}-${date.year}\n';
    if (count > 0 && category != null) {
      tooltipMessage += '$count ${category.toLowerCase()} ${count == 1 ? "activity" : "activities"}';
    } else {
      tooltipMessage += 'No activities';
    }

    return Tooltip(
      message: tooltipMessage,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
    );
  }

  Widget _buildLegend() {
    final categories = ['Work', 'Health', 'Learning', 'Personal'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: categories.expand((category) => [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _getColorForCategory(category),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          category,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(width: 10),
      ]).toList(),
    );
  }
}