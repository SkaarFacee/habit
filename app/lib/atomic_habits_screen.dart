import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'shared/neon_ribbon_background.dart';
import 'shared/theme.dart';

class AtomicHabitsScreen extends StatefulWidget {
  const AtomicHabitsScreen({super.key});

  @override
  State<AtomicHabitsScreen> createState() => _AtomicHabitsScreenState();
}

class _AtomicHabitsScreenState extends State<AtomicHabitsScreen> {
  final DocumentReference<Map<String, dynamic>> _newTrackerRef =
      FirebaseFirestore.instance.collection('habit').doc('new_tracker');

  final DocumentReference<Map<String, dynamic>> _atomicHabitsRef =
      FirebaseFirestore.instance.collection('habit').doc('atomic_habits');

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _trackerSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _habitsSub;

  Map<String, dynamic> _rawTrackerData = {};
  Map<String, Map<DateTime, int>> _habitDateMap = {};
  Map<String, List<_HabitTaskEntry>> _habitTaskMap = {};

  List<String> _allHabits = [];
  List<String> _favorites = [];

  // Cached lists so we do not re-filter + re-sort on every build.
  List<String> _combinedHabits = [];
  List<String> _filteredHabits = [];
  List<String> _visibleHabits = [];

  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  int _visibleCount = 10;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _trackerSub = _newTrackerRef.snapshots().listen(
      (snap) {
        final raw = Map<String, dynamic>.from(snap.data() ?? {});
        final taskMap = _parseHabitTaskMap(raw);
        final dateMap = _buildHabitDateMap(taskMap);

        if (!mounted) return;
        setState(() {
          _rawTrackerData = raw;
          _habitTaskMap = taskMap;
          _habitDateMap = dateMap;
          _loading = false;
          _recomputeHabitLists();
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _loading = false);
      },
    );

    _habitsSub = _atomicHabitsRef.snapshots().listen(
      (snap) {
        final raw = Map<String, dynamic>.from(snap.data() ?? {});
        if (!mounted) return;
        setState(() {
          _allHabits = _stringList(raw['habits']);
          _favorites = _stringList(raw['favorites']);
          _recomputeHabitLists();
        });
      },
    );

    _searchController.addListener(() {
      final nextQuery = _searchController.text.trim().toLowerCase();
      if (!mounted || nextQuery == _searchQuery) return;

      setState(() {
        _searchQuery = nextQuery;
        _visibleCount = 10;
        _recomputeHabitLists();
      });
    });
  }

  @override
  void dispose() {
    _trackerSub?.cancel();
    _habitsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _recomputeHabitLists() {
    final combined = _dedupeStrings([
      ..._allHabits,
      ..._habitDateMap.keys,
    ]);

    final filtered = _searchQuery.isEmpty
        ? List<String>.from(combined)
        : combined
            .where((h) => h.toLowerCase().contains(_searchQuery))
            .toList(growable: false);

    filtered.sort((a, b) {
      final aFav = _containsHabit(_favorites, a);
      final bFav = _containsHabit(_favorites, b);

      if (aFav && !bFav) return -1;
      if (!aFav && bFav) return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

    _combinedHabits = combined;
    _filteredHabits = filtered;
    _visibleHabits = filtered.take(_visibleCount).toList(growable: false);
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return [];
    return _dedupeStrings(value.whereType<String>());
  }

  List<String> _dedupeStrings(Iterable<String> values) {
    final seen = <String>{};
    final out = <String>[];

    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      final key = value.toLowerCase();
      if (seen.add(key)) out.add(value);
    }
    return out;
  }

  bool _sameHabit(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  bool _containsHabit(Iterable<String> values, String habit) {
    return values.any((v) => _sameHabit(v, habit));
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _parseDate(String input) {
    final parts = input.split('-');
    if (parts.length != 3) return _dateOnly(DateTime.now());

    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);

    if (day == null || month == null || year == null) {
      return _dateOnly(DateTime.now());
    }

    return DateTime(year, month, day);
  }

  Map<String, List<_HabitTaskEntry>> _parseHabitTaskMap(
    Map<String, dynamic> data,
  ) {
    final result = <String, List<_HabitTaskEntry>>{};

    data.forEach((dateStr, activities) {
      if (activities is! List) return;

      final date = _dateOnly(_parseDate(dateStr));

      for (final rawActivity in activities) {
        final activity = _asMap(rawActivity);
        if (activity == null) continue;

        final habit = activity['atomic_habit']?.toString().trim();
        if (habit == null || habit.isEmpty) continue;

        final title =
            activity['title']?.toString().trim().isNotEmpty == true
                ? activity['title'].toString().trim()
                : 'Untitled task';

        final category =
            activity['category']?.toString().trim().isNotEmpty == true
                ? activity['category'].toString().trim()
                : 'Other';

        final difficulty =
            activity['difficulty']?.toString().trim().isNotEmpty == true
                ? activity['difficulty'].toString().trim()
                : 'MEDIUM';

        result.putIfAbsent(habit, () => []);
        result[habit]!.add(
          _HabitTaskEntry(
            date: date,
            title: title,
            category: category,
            difficulty: difficulty,
            habit: habit,
          ),
        );
      }
    });

    for (final entries in result.values) {
      entries.sort((a, b) {
        final dateCompare = b.date.compareTo(a.date);
        if (dateCompare != 0) return dateCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }

    return result;
  }

  Map<String, Map<DateTime, int>> _buildHabitDateMap(
    Map<String, List<_HabitTaskEntry>> taskMap,
  ) {
    final result = <String, Map<DateTime, int>>{};

    taskMap.forEach((habit, entries) {
      final dateCounts = <DateTime, int>{};

      for (final entry in entries) {
        final date = _dateOnly(entry.date);
        dateCounts[date] = (dateCounts[date] ?? 0) + 1;
      }

      result[habit] = dateCounts;
    });

    return result;
  }

  Map<String, dynamic> _rewriteTracker(
    Map<String, dynamic> tracker,
    String oldName,
    String newName,
  ) {
    final output = <String, dynamic>{};

    tracker.forEach((dateStr, activities) {
      if (activities is! List) {
        output[dateStr] = activities;
        return;
      }

      output[dateStr] = activities.map((item) {
        final map = _asMap(item);
        if (map == null) return item;

        final currentHabit = map['atomic_habit']?.toString();
        if (currentHabit == null || !_sameHabit(currentHabit, oldName)) {
          return map;
        }

        return {
          ...map,
          'atomic_habit': newName,
        };
      }).toList();
    });

    return output;
  }

  List<String> _replaceInList({
    required List<String> source,
    required String oldName,
    required String newName,
    bool ensureNewName = false,
  }) {
    final seen = <String>{};
    final out = <String>[];
    var replaced = false;

    for (final item in source) {
      final next = _sameHabit(item, oldName) ? newName.trim() : item.trim();
      if (_sameHabit(item, oldName)) replaced = true;
      if (next.isEmpty) continue;

      final key = next.toLowerCase();
      if (seen.add(key)) out.add(next);
    }

    if ((replaced || ensureNewName) && !_containsHabit(out, newName)) {
      out.add(newName.trim());
    }

    return out;
  }

  String _errorText(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) return text.substring(11);
    return text;
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  String? _validateRename(String oldName, String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      return 'Please enter a habit name.';
    }

    if (_sameHabit(trimmed, oldName)) {
      return 'Enter a different name.';
    }

    final existingOtherHabit = _combinedHabits.any(
      (habit) => _sameHabit(habit, trimmed) && !_sameHabit(habit, oldName),
    );

    if (existingOtherHabit) {
      return 'A habit named "$trimmed" already exists. Use merge instead.';
    }

    return null;
  }

  Future<bool> _toggleFavorite(String habit) async {
    if (_saving) return false;

    setState(() => _saving = true);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final habitsSnap = await tx.get(_atomicHabitsRef);
        final raw = Map<String, dynamic>.from(habitsSnap.data() ?? {});

        final favorites = _stringList(raw['favorites']);

        if (_containsHabit(favorites, habit)) {
          favorites.removeWhere((h) => _sameHabit(h, habit));
        } else {
          favorites.add(habit);
        }

        tx.set(
          _atomicHabitsRef,
          {'favorites': _dedupeStrings(favorites)},
          SetOptions(merge: true),
        );
      });

      final localFavorites = List<String>.from(_favorites);
      if (_containsHabit(localFavorites, habit)) {
        localFavorites.removeWhere((h) => _sameHabit(h, habit));
      } else {
        localFavorites.add(habit);
      }

      if (!mounted) return false;
      setState(() {
        _favorites = _dedupeStrings(localFavorites);
        _recomputeHabitLists();
      });

      return true;
    } catch (e) {
      _snack('Could not update favorite. ${_errorText(e)}', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _renameHabit(String oldName, String newName) async {
    final validationError = _validateRename(oldName, newName);
    if (validationError != null) {
      _snack(validationError, error: true);
      return false;
    }

    final trimmed = newName.trim();

    if (_saving) return false;
    setState(() => _saving = true);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final trackerSnap = await tx.get(_newTrackerRef);
        final habitsSnap = await tx.get(_atomicHabitsRef);

        final trackerData = Map<String, dynamic>.from(trackerSnap.data() ?? {});
        final habitsData = Map<String, dynamic>.from(habitsSnap.data() ?? {});

        final habitList = _stringList(habitsData['habits']);
        final favoriteList = _stringList(habitsData['favorites']);

        final updatedTracker = _rewriteTracker(trackerData, oldName, trimmed);
        final updatedHabits = _replaceInList(
          source: habitList,
          oldName: oldName,
          newName: trimmed,
          ensureNewName: true,
        );
        final updatedFavorites = _replaceInList(
          source: favoriteList,
          oldName: oldName,
          newName: trimmed,
        );

        tx.set(_newTrackerRef, updatedTracker);
        tx.set(
          _atomicHabitsRef,
          {
            'habits': updatedHabits,
            'favorites': updatedFavorites,
          },
          SetOptions(merge: true),
        );
      });

      final localTracker = _rewriteTracker(_rawTrackerData, oldName, trimmed);
      final taskMap = _parseHabitTaskMap(localTracker);

      if (!mounted) return false;
      setState(() {
        _rawTrackerData = localTracker;
        _habitTaskMap = taskMap;
        _habitDateMap = _buildHabitDateMap(taskMap);
        _allHabits = _replaceInList(
          source: _allHabits,
          oldName: oldName,
          newName: trimmed,
          ensureNewName: true,
        );
        _favorites = _replaceInList(
          source: _favorites,
          oldName: oldName,
          newName: trimmed,
        );
        _recomputeHabitLists();
      });

      _snack('Renamed "$oldName" to "$trimmed"');
      return true;
    } catch (e) {
      _snack('Could not rename habit. ${_errorText(e)}', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _mergeHabits(String fromHabit, String intoHabit) async {
    if (_sameHabit(fromHabit, intoHabit)) {
      _snack('Choose a different habit to merge into.', error: true);
      return false;
    }

    if (_saving) return false;
    setState(() => _saving = true);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final trackerSnap = await tx.get(_newTrackerRef);
        final habitsSnap = await tx.get(_atomicHabitsRef);

        final trackerData = Map<String, dynamic>.from(trackerSnap.data() ?? {});
        final habitsData = Map<String, dynamic>.from(habitsSnap.data() ?? {});

        final habitList = _stringList(habitsData['habits']);
        final favoriteList = _stringList(habitsData['favorites']);

        final updatedTracker = _rewriteTracker(trackerData, fromHabit, intoHabit);
        final updatedHabits = _replaceInList(
          source: habitList,
          oldName: fromHabit,
          newName: intoHabit,
          ensureNewName: true,
        );
        final updatedFavorites = _replaceInList(
          source: favoriteList,
          oldName: fromHabit,
          newName: intoHabit,
        );

        tx.set(_newTrackerRef, updatedTracker);
        tx.set(
          _atomicHabitsRef,
          {
            'habits': updatedHabits,
            'favorites': updatedFavorites,
          },
          SetOptions(merge: true),
        );
      });

      final localTracker = _rewriteTracker(_rawTrackerData, fromHabit, intoHabit);
      final taskMap = _parseHabitTaskMap(localTracker);

      if (!mounted) return false;
      setState(() {
        _rawTrackerData = localTracker;
        _habitTaskMap = taskMap;
        _habitDateMap = _buildHabitDateMap(taskMap);
        _allHabits = _replaceInList(
          source: _allHabits,
          oldName: fromHabit,
          newName: intoHabit,
          ensureNewName: true,
        );
        _favorites = _replaceInList(
          source: _favorites,
          oldName: fromHabit,
          newName: intoHabit,
        );
        _recomputeHabitLists();
      });

      _snack('Merged "$fromHabit" into "$intoHabit"');
      return true;
    } catch (e) {
      _snack('Could not merge habits. ${_errorText(e)}', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openRenamePage(String habit) async {
    final newName = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _RenameHabitPage(
          initialName: habit,
          validator: (value) => _validateRename(habit, value),
        ),
      ),
    );

    if (!mounted || newName == null) return;
    await _renameHabit(habit, newName);
  }

  Future<void> _openMergePage(String habit) async {
    final target = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _MergeHabitPage(
          sourceHabit: habit,
          habits: _combinedHabits
              .where((h) => !_sameHabit(h, habit))
              .toList(growable: false),
          favorites: _favorites,
        ),
      ),
    );

    if (!mounted || target == null) return;
    await _mergeHabits(habit, target);
  }

  void _openHabitDetails(String habit) {
    final entries = List<_HabitTaskEntry>.from(_habitTaskMap[habit] ?? const []);
    final dates = Map<DateTime, int>.from(_habitDateMap[habit] ?? const {});
    final isFavorite = _containsHabit(_favorites, habit);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _HabitDetailsPage(
          habit: habit,
          entries: entries,
          dates: dates,
          isFavorite: isFavorite,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Atomic Habits'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Toggle theme',
            icon: Icon(
              themeNotifier.value == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
            onPressed: () {
              themeNotifier.value = themeNotifier.value == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const RepaintBoundary(
            child: NeonRibbonBackground(),
          ),
          SafeArea(
            child: _loading ? _buildLoading(isDark) : _buildContent(isDark),
          ),
          if (_saving)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(0.12),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF171717) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.10),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                        SizedBox(width: 12),
                        Text('Saving...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    final habits = _filteredHabits;
    final visibleHabits = _visibleHabits;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _SearchBar(
            controller: _searchController,
            isDark: isDark,
            hasText: _searchQuery.isNotEmpty,
            onClear: () => _searchController.clear(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.auto_awesome_rounded,
                label: '${habits.length} habits',
                isDark: isDark,
              ),
              _InfoChip(
                icon: Icons.star_rounded,
                label: '${_favorites.length} favorites',
                isDark: isDark,
              ),
              _InfoChip(
                icon: Icons.visibility_rounded,
                label: 'Showing ${visibleHabits.length}',
                isDark: isDark,
              ),
            ],
          ),
        ),
        Expanded(
          child: habits.isEmpty
              ? _buildEmpty(isDark)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  physics: const BouncingScrollPhysics(),
                  cacheExtent: 900,
                  itemCount:
                      visibleHabits.length + (habits.length > _visibleCount ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == visibleHabits.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Center(
                          child: FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _visibleCount += 10;
                                _recomputeHabitLists();
                              });
                            },
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('Show more'),
                          ),
                        ),
                      );
                    }

                    final habit = visibleHabits[index];
                    final dates = _habitDateMap[habit] ?? const <DateTime, int>{};
                    final isFavorite = _containsHabit(_favorites, habit);
                    final entries =
                        _habitTaskMap[habit] ?? const <_HabitTaskEntry>[];

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == visibleHabits.length - 1 ? 0 : 14,
                      ),
                      child: _HabitCard(
                        key: ValueKey(habit),
                        habit: habit,
                        dates: dates,
                        entries: entries,
                        isFavorite: isFavorite,
                        isDark: isDark,
                        onOpen: () => _openHabitDetails(habit),
                        onFavorite: () => _toggleFavorite(habit),
                        onRename: () => _openRenamePage(habit),
                        onMerge: _combinedHabits.length > 1
                            ? () => _openMergePage(habit)
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            const SizedBox(height: 14),
            Text(
              'No habits found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different search or add more habits to Firestore.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.65),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(bool isDark) {
    final base = isDark ? Colors.white10 : Colors.grey.shade200;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            height: 210,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        );
      },
    );
  }
}

class _HabitCard extends StatelessWidget {
  final String habit;
  final Map<DateTime, int> dates;
  final List<_HabitTaskEntry> entries;
  final bool isFavorite;
  final bool isDark;
  final VoidCallback onOpen;
  final Future<bool> Function() onFavorite;
  final VoidCallback onRename;
  final VoidCallback? onMerge;

  const _HabitCard({
    super.key,
    required this.habit,
    required this.dates,
    required this.entries,
    required this.isFavorite,
    required this.isDark,
    required this.onOpen,
    required this.onFavorite,
    required this.onRename,
    required this.onMerge,
  });

  int get _totalOccurrences => dates.values.fold(0, (sum, count) => sum + count);

  int get _activeDays => dates.keys.length;

  int get _streak {
    if (dates.isEmpty) return 0;

    final normalized = dates.keys
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();

    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    var streak = 0;

    while (normalized.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF15171C) : Colors.white;

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardColor.withOpacity(0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withOpacity(0.16)
                      : Colors.black.withOpacity(0.045),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isFavorite)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFFFFD54F).withOpacity(0.14)
                                    : const Color(0xFFFFF3CD),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 14,
                                    color: Color(0xFFF59E0B),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Favorite',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFFF59E0B),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          if (isFavorite) const SizedBox(height: 10),
                          Text(
                            habit,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${entries.length} task${entries.length == 1 ? '' : 's'} logged',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
                          onPressed: () {
                            onFavorite();
                          },
                          icon: Icon(
                            isFavorite
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: isFavorite
                                ? const Color(0xFFF59E0B)
                                : (isDark ? Colors.white60 : Colors.black45),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Edit habit',
                          icon: Icon(
                            Icons.edit_outlined,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          onSelected: (value) {
                            if (value == 'rename') {
                              onRename();
                            } else if (value == 'merge') {
                              onMerge?.call();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem<String>(
                              value: 'rename',
                              child: Row(
                                children: [
                                  Icon(Icons.drive_file_rename_outline_rounded,
                                      size: 18),
                                  SizedBox(width: 10),
                                  Text('Rename'),
                                ],
                              ),
                            ),
                            if (onMerge != null)
                              const PopupMenuItem<String>(
                                value: 'merge',
                                child: Row(
                                  children: [
                                    Icon(Icons.merge_rounded, size: 18),
                                    SizedBox(width: 10),
                                    Text('Merge'),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 15,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatPill(
                      icon: Icons.check_circle_outline_rounded,
                      label: '$_totalOccurrences total',
                      isDark: isDark,
                    ),
                    _StatPill(
                      icon: Icons.calendar_today_rounded,
                      label: '$_activeDays active days',
                      isDark: isDark,
                    ),
                    _StatPill(
                      icon: Icons.local_fire_department_rounded,
                      label: '$_streak day streak',
                      isDark: isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _HabitHeatmap(
                  dates: dates,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HabitDetailsPage extends StatelessWidget {
  final String habit;
  final List<_HabitTaskEntry> entries;
  final Map<DateTime, int> dates;
  final bool isFavorite;

  const _HabitDetailsPage({
    required this.habit,
    required this.entries,
    required this.dates,
    required this.isFavorite,
  });

  int get _totalOccurrences => entries.length;

  int get _activeDays => dates.keys.length;

  int get _streak {
    if (dates.isEmpty) return 0;

    final normalized = dates.keys
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();

    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    var streak = 0;

    while (normalized.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  Map<String, int> get _categoryBreakdown {
    final map = <String, int>{};
    for (final entry in entries) {
      map[entry.category] = (map[entry.category] ?? 0) + 1;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF15171C) : Colors.white;
    final topCategories = _categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Habit Details'),
      ),
      body: Stack(
        children: [
          const RepaintBoundary(
            child: NeonRibbonBackground(),
          ),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: RepaintBoundary(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cardColor.withOpacity(0.94),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: isDark
                                ? Colors.white12
                                : Colors.black.withOpacity(0.05),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withOpacity(0.16)
                                  : Colors.black.withOpacity(0.045),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isFavorite)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFFFFD54F).withOpacity(0.14)
                                      : const Color(0xFFFFF3CD),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: Color(0xFFF59E0B),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Favorite Habit',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFFF59E0B),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            if (isFavorite) const SizedBox(height: 12),
                            Text(
                              habit,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Every task logged for this habit, with your heatmap on top.',
                              style:
                                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.65),
                                      ),
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _InfoChip(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: '$_totalOccurrences tasks',
                                  isDark: isDark,
                                ),
                                _InfoChip(
                                  icon: Icons.calendar_today_rounded,
                                  label: '$_activeDays active days',
                                  isDark: isDark,
                                ),
                                _InfoChip(
                                  icon: Icons.local_fire_department_rounded,
                                  label: '$_streak day streak',
                                  isDark: isDark,
                                ),
                              ],
                            ),
                            if (topCategories.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: topCategories
                                    .take(3)
                                    .map(
                                      (e) => _CategoryChip(
                                        label: '${e.key} · ${e.value}',
                                        isDark: isDark,
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ],
                            const SizedBox(height: 18),
                            _HabitHeatmap(
                              dates: dates,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                    child: Row(
                      children: [
                        Text(
                          'Task History',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entries.length}',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (entries.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No tasks logged for this habit yet.',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.65),
                              ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final entry = entries[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == entries.length - 1 ? 0 : 10,
                            ),
                            child: _HabitTaskTile(
                              entry: entry,
                            ),
                          );
                        },
                        childCount: entries.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitHeatmap extends StatelessWidget {
  final Map<DateTime, int> dates;
  final bool isDark;

  const _HabitHeatmap({
    required this.dates,
    required this.isDark,
  });

  static const double _cell = 10;
  static const double _gap = 3;
  static const int _rows = 7;
  static const double _monthLabelHeight = 16;
  static const double _monthLabelGap = 6;

  Color _colorForCount(int count) {
    if (count <= 0) {
      return isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE9EDF3);
    }

    if (isDark) {
      if (count == 1) return const Color(0xFF1D7AFC).withOpacity(0.45);
      if (count == 2) return const Color(0xFF1D7AFC).withOpacity(0.65);
      if (count == 3) return const Color(0xFF1D7AFC).withOpacity(0.82);
      return const Color(0xFF63A4FF);
    }

    if (count == 1) return const Color(0xFFD6E8FF);
    if (count == 2) return const Color(0xFFA9CEFF);
    if (count == 3) return const Color(0xFF6FAEFF);
    return const Color(0xFF1D7AFC);
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final firstVisibleDay = today.subtract(const Duration(days: 364));
    final gridStart =
        firstVisibleDay.subtract(Duration(days: firstVisibleDay.weekday % 7));
    final totalDays = today.difference(gridStart).inDays + 1;
    final totalWeeks = (totalDays / 7).ceil();

    final columnWidth = _cell + _gap;
    final contentWidth = totalWeeks * columnWidth;
    final gridHeight = (_rows * (_cell + _gap)) - _gap;
    final chartHeight = _monthLabelHeight + _monthLabelGap + gridHeight;

    final normalizedDates = <DateTime, int>{};
    dates.forEach((key, value) {
      normalizedDates[DateUtils.dateOnly(key)] = value;
    });

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.04)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: contentWidth,
                height: chartHeight,
                child: CustomPaint(
                  painter: _HeatmapPainter(
                    dateCounts: normalizedDates,
                    isDark: isDark,
                    today: today,
                    firstVisibleDay: firstVisibleDay,
                    gridStart: gridStart,
                    totalWeeks: totalWeeks,
                    cell: _cell,
                    gap: _gap,
                    rows: _rows,
                    monthLabelHeight: _monthLabelHeight,
                    monthLabelGap: _monthLabelGap,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Less',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                for (int i = 0; i < 5; i++)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _colorForCount(i),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                Text(
                  'More',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final Map<DateTime, int> dateCounts;
  final bool isDark;
  final DateTime today;
  final DateTime firstVisibleDay;
  final DateTime gridStart;
  final int totalWeeks;
  final double cell;
  final double gap;
  final int rows;
  final double monthLabelHeight;
  final double monthLabelGap;

  const _HeatmapPainter({
    required this.dateCounts,
    required this.isDark,
    required this.today,
    required this.firstVisibleDay,
    required this.gridStart,
    required this.totalWeeks,
    required this.cell,
    required this.gap,
    required this.rows,
    required this.monthLabelHeight,
    required this.monthLabelGap,
  });

  static const List<String> _months = [
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

  Color _colorForCount(int count) {
    if (count <= 0) {
      return isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE9EDF3);
    }

    if (isDark) {
      if (count == 1) return const Color(0xFF1D7AFC).withOpacity(0.45);
      if (count == 2) return const Color(0xFF1D7AFC).withOpacity(0.65);
      if (count == 3) return const Color(0xFF1D7AFC).withOpacity(0.82);
      return const Color(0xFF63A4FF);
    }

    if (count == 1) return const Color(0xFFD6E8FF);
    if (count == 2) return const Color(0xFFA9CEFF);
    if (count == 3) return const Color(0xFF6FAEFF);
    return const Color(0xFF1D7AFC);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final columnWidth = cell + gap;
    final gridTop = monthLabelHeight + monthLabelGap;
    final textStyle = TextStyle(
      fontSize: 10,
      color: isDark ? Colors.white54 : Colors.black54,
      fontWeight: FontWeight.w500,
    );

    final paint = Paint()..style = PaintingStyle.fill;

    for (int weekIndex = 0; weekIndex < totalWeeks; weekIndex++) {
      final weekDate = gridStart.add(Duration(days: weekIndex * 7));
      final previousWeekDate =
          weekIndex == 0 ? null : gridStart.add(Duration(days: (weekIndex - 1) * 7));

      final showLabel = weekIndex == 0 ||
          (previousWeekDate != null && weekDate.month != previousWeekDate.month);

      if (showLabel) {
        final tp = TextPainter(
          text: TextSpan(
            text: _months[weekDate.month - 1],
            style: textStyle,
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: columnWidth + 20);

        tp.paint(canvas, Offset(weekIndex * columnWidth, 0));
      }

      for (int dayIndex = 0; dayIndex < rows; dayIndex++) {
        final date = gridStart.add(Duration(days: weekIndex * 7 + dayIndex));
        final isOutsideRange =
            date.isBefore(firstVisibleDay) || date.isAfter(today);

        if (isOutsideRange) continue;

        final count = dateCounts[date] ?? 0;
        paint.color = _colorForCount(count);

        final rect = Rect.fromLTWH(
          weekIndex * columnWidth,
          gridTop + dayIndex * (cell + gap),
          cell,
          cell,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) {
    return oldDelegate.dateCounts != dateCounts ||
        oldDelegate.isDark != isDark ||
        oldDelegate.today != today ||
        oldDelegate.firstVisibleDay != firstVisibleDay ||
        oldDelegate.gridStart != gridStart ||
        oldDelegate.totalWeeks != totalWeeks;
  }
}

class _RenameHabitPage extends StatefulWidget {
  final String initialName;
  final String? Function(String value) validator;

  const _RenameHabitPage({
    required this.initialName,
    required this.validator,
  });

  @override
  State<_RenameHabitPage> createState() => _RenameHabitPageState();
}

class _RenameHabitPageState extends State<_RenameHabitPage> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {
      if (_errorText != null) _errorText = null;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final error = widget.validator(_controller.text);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rename habit'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'New name',
                  hintText: 'Enter a new habit name',
                  errorText: _errorText,
                  suffixIcon: hasText
                      ? IconButton(
                          onPressed: () {
                            _controller.clear();
                            setState(() => _errorText = null);
                          },
                          icon: const Icon(Icons.close_rounded),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'This updates the habits list and every matching atomic_habit inside new_tracker.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.68),
                    ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MergeHabitPage extends StatefulWidget {
  final String sourceHabit;
  final List<String> habits;
  final List<String> favorites;

  const _MergeHabitPage({
    required this.sourceHabit,
    required this.habits,
    required this.favorites,
  });

  @override
  State<_MergeHabitPage> createState() => _MergeHabitPageState();
}

class _MergeHabitPageState extends State<_MergeHabitPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selected;

  bool _sameHabit(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  bool _containsHabit(Iterable<String> values, String habit) {
    return values.any((v) => _sameHabit(v, habit));
  }

  List<String> get _filteredHabits {
    final filtered = widget.habits.where((h) {
      if (_query.isEmpty) return true;
      return h.toLowerCase().contains(_query);
    }).toList();

    filtered.sort((a, b) {
      final aStarts = _query.isNotEmpty && a.toLowerCase().startsWith(_query);
      final bStarts = _query.isNotEmpty && b.toLowerCase().startsWith(_query);
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;

      final aFav = _containsHabit(widget.favorites, a);
      final bFav = _containsHabit(widget.favorites, b);
      if (aFav && !bFav) return -1;
      if (!aFav && bFav) return 1;

      return a.toLowerCase().compareTo(b.toLowerCase());
    });

    return filtered;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text.trim().toLowerCase();
      if (next == _query) return;
      if (!mounted) return;
      setState(() {
        _query = next;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredHabits;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge habit'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Move all entries from "${widget.sourceHabit}" into another habit.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.68),
                        ),
                  ),
                  const SizedBox(height: 14),
                  _SheetSearchField(
                    controller: _searchController,
                    hintText: 'Search target habit...',
                    isDark: isDark,
                    onClear: () {
                      _searchController.clear();
                      setState(() {
                        _query = '';
                      });
                    },
                  ),
                  if (_selected != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.06)
                            : const Color(0xFFF6F8FB),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.merge_rounded, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Selected target: $_selected',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No habits match your search.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.65),
                            ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final target = filtered[index];
                        final isSelected =
                            _selected != null && _sameHabit(_selected!, target);

                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == filtered.length - 1 ? 0 : 8,
                          ),
                          child: _MergeTargetTile(
                            habit: target,
                            isSelected: isSelected,
                            isFavorite: _containsHabit(widget.favorites, target),
                            onTap: () {
                              setState(() {
                                _selected = target;
                              });
                            },
                            isDark: isDark,
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _selected == null
                          ? null
                          : () => Navigator.of(context).pop(_selected),
                      icon: const Icon(Icons.merge_rounded),
                      label: const Text('Merge'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final bool hasText;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.isDark,
    required this.hasText,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final fillColor = isDark
        ? const Color(0xFF15171C).withOpacity(0.94)
        : Colors.white.withOpacity(0.94);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.14)
                  : Colors.black.withOpacity(0.045),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Search habits...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: hasText
                ? IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          ),
        ),
      ),
    );
  }
}

class _SheetSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isDark;
  final VoidCallback onClear;

  const _SheetSearchField({
    required this.controller,
    required this.hintText,
    required this.isDark,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: hasText
              ? IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class _MergeTargetTile extends StatelessWidget {
  final String habit;
  final bool isSelected;
  final bool isFavorite;
  final bool isDark;
  final VoidCallback onTap;

  const _MergeTargetTile({
    required this.habit,
    required this.isSelected,
    required this.isFavorite,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? const Color(0xFF1D7AFC)
        : (isDark ? Colors.white10 : Colors.black.withOpacity(0.06));

    final backgroundColor = isSelected
        ? (isDark
            ? const Color(0xFF1D7AFC).withOpacity(0.14)
            : const Color(0xFFEAF3FF))
        : (isDark ? Colors.white.withOpacity(0.03) : Colors.white);

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: isSelected
                      ? const Color(0xFF1D7AFC)
                      : (isDark ? Colors.white38 : Colors.black38),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    habit,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isFavorite) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: Color(0xFFF59E0B),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HabitTaskTile extends StatelessWidget {
  final _HabitTaskEntry entry;

  const _HabitTaskTile({
    required this.entry,
  });

  Color _difficultyColor(String difficulty) {
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

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Health':
        return Icons.favorite_outline_rounded;
      case 'Work':
        return Icons.work_outline_rounded;
      case 'Play':
        return Icons.sports_esports_outlined;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: (isDark ? const Color(0xFF15171C) : Colors.white).withOpacity(0.94),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.14)
                  : Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _difficultyColor(entry.difficulty).withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _categoryIcon(entry.category),
                color: _difficultyColor(entry.difficulty),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TinyMetaChip(
                        icon: Icons.event_outlined,
                        label: entry.formattedDate,
                      ),
                      _TinyMetaChip(
                        icon: Icons.category_outlined,
                        label: entry.category,
                      ),
                      _TinyMetaChip(
                        icon: Icons.bolt_outlined,
                        label: entry.difficulty.toUpperCase(),
                        color: _difficultyColor(entry.difficulty),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _TinyMetaChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = color ?? (isDark ? Colors.white60 : Colors.black54);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isDark;

  const _CategoryChip({
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF15171C).withOpacity(0.92)
            : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : const Color(0xFFF3F6FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitTaskEntry {
  final DateTime date;
  final String title;
  final String category;
  final String difficulty;
  final String habit;

  const _HabitTaskEntry({
    required this.date,
    required this.title,
    required this.category,
    required this.difficulty,
    required this.habit,
  });

  String get formattedDate {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day-$month-$year';
  }
}