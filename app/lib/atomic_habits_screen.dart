import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'habit_details_screen.dart';
import 'shared/neon_ribbon_background.dart';
import 'shared/theme.dart';

class AtomicHabitsScreen extends StatefulWidget {
  final String? routine;

  const AtomicHabitsScreen({super.key, this.routine});

  @override
  State<AtomicHabitsScreen> createState() => _AtomicHabitsScreenState();
}

class _AtomicHabitsScreenState extends State<AtomicHabitsScreen> {
  static const String _trackerRootKey = 'Tracker';
  static const String _otherRoutineName = 'Other';

  final DocumentReference<Map<String, dynamic>> _trackerRef =
      FirebaseFirestore.instance.collection('habit').doc('tracker');

  final DocumentReference<Map<String, dynamic>> _atomicHabitsRef =
      FirebaseFirestore.instance.collection('habit').doc('atomic_habits');

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _trackerSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _habitsSub;

  Map<String, dynamic> _rawTrackerData = {};
  Map<String, Map<DateTime, int>> _habitDateMap = {};
  Map<String, List<HabitTaskEntry>> _habitTaskMap = {};

  List<String> _screenHabits = [];
  List<String> _globalHabits = [];
  List<String> _globalFavorites = [];
  Map<String, List<String>> _habitsByRoutine = {};
  Map<String, List<String>> _favoritesByRoutine = {};
  List<String> _favorites = [];

  List<String> _combinedHabits = [];
  List<String> _filteredHabits = [];
  List<String> _visibleHabits = [];

  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  int _visibleCount = 5;
  bool _trackerLoaded = false;
  bool _habitsLoaded = false;
  bool _saving = false;

  bool get _isRoutineMode => widget.routine?.trim().isNotEmpty == true;

  String? get _activeRoutine => _isRoutineMode ? widget.routine!.trim() : null;

  bool get _loading => !_trackerLoaded || !_habitsLoaded;

  bool _sameHabit(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  bool _containsHabit(Iterable<String> values, String habit) {
    return values.any((v) => _sameHabit(v, habit));
  }

  bool _isOtherRoutineName(String? routine) {
    if (routine == null) return false;
    return _sameHabit(routine, _otherRoutineName);
  }

  String? _matchingRoutineKey(
    Map<String, List<String>> map,
    String routineName,
  ) {
    for (final key in map.keys) {
      if (_sameHabit(key, routineName)) return key;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();

    _trackerSub = _trackerRef.snapshots().listen(
      (snap) {
        final raw = Map<String, dynamic>.from(snap.data() ?? {});
        final flattenedTracker = _flattenTrackerEntries(raw);
        final taskMap = _parseHabitTaskMap(flattenedTracker);
        final dateMap = _buildHabitDateMap(taskMap);

        if (!mounted) return;
        setState(() {
          _rawTrackerData = raw;
          _habitTaskMap = taskMap;
          _habitDateMap = dateMap;
          _trackerLoaded = true;
          _recomputeHabitLists();
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _trackerLoaded = true);
      },
    );

    _habitsSub = _atomicHabitsRef.snapshots().listen(
      (snap) {
        final raw = Map<String, dynamic>.from(snap.data() ?? {});
        if (!mounted) return;

        final globalHabits = _stringList(raw['habits']);
        final globalFavorites = _stringList(raw['favorites']);
        final habitsByRoutine = _stringListMap(raw['habits_by_routine']);
        final favoritesByRoutine = _stringListMap(raw['favorites_by_routine']);

        final routineName = _activeRoutine;
        final screenHabits = _routineHabitsFor(
          routineName: routineName,
          globalHabits: globalHabits,
          habitsByRoutine: habitsByRoutine,
        );

        final favorites = _routineFavoritesFor(
          routineName: routineName,
          globalFavorites: globalFavorites,
          screenHabits: screenHabits,
          favoritesByRoutine: favoritesByRoutine,
        );

        setState(() {
          _globalHabits = globalHabits;
          _globalFavorites = globalFavorites;
          _habitsByRoutine = habitsByRoutine;
          _favoritesByRoutine = favoritesByRoutine;
          _screenHabits = screenHabits;
          _favorites = favorites;
          _habitsLoaded = true;
          _recomputeHabitLists();
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _habitsLoaded = true);
      },
    );

    _searchController.addListener(() {
      final nextQuery = _searchController.text.trim().toLowerCase();
      if (!mounted || nextQuery == _searchQuery) return;

      setState(() {
        _searchQuery = nextQuery;
        _visibleCount = 5;
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
    final base = _isRoutineMode
        ? List<String>.from(_screenHabits)
        : _dedupeStrings([
            ..._screenHabits,
            ..._habitDateMap.keys,
          ]);

    final filtered = _searchQuery.isEmpty
        ? List<String>.from(base)
        : base
            .where((h) => h.toLowerCase().contains(_searchQuery))
            .toList(growable: false);

    filtered.sort((a, b) {
      final aFav = _containsHabit(_favorites, a);
      final bFav = _containsHabit(_favorites, b);

      if (aFav && !bFav) return -1;
      if (!aFav && bFav) return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

    _combinedHabits = base;
    _filteredHabits = filtered;
    _visibleHabits = filtered.take(_visibleCount).toList(growable: false);
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return [];
    return _dedupeStrings(value.whereType<String>());
  }

  Map<String, List<String>> _stringListMap(dynamic value) {
    if (value is! Map) return {};
    final out = <String, List<String>>{};
    value.forEach((key, rawValue) {
      out[key.toString()] = _stringList(rawValue);
    });
    return out;
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

  List<String> _allKnownHabits() {
    return _dedupeStrings([
      ..._globalHabits,
      ..._habitDateMap.keys,
      ..._habitsByRoutine.values.expand((items) => items),
    ]);
  }

  List<String> _computeUnassignedHabits(
    List<String> globalHabits,
    Map<String, List<String>> habitsByRoutine,
  ) {
    final assigned = <String>{};

    habitsByRoutine.forEach((routine, habits) {
      if (_isOtherRoutineName(routine)) return;

      for (final habit in habits) {
        final normalized = habit.trim().toLowerCase();
        if (normalized.isNotEmpty) {
          assigned.add(normalized);
        }
      }
    });

    return globalHabits
        .where((habit) => !assigned.contains(habit.trim().toLowerCase()))
        .toList(growable: false);
  }

  List<String> _routineHabitsFor({
    required String? routineName,
    required List<String> globalHabits,
    required Map<String, List<String>> habitsByRoutine,
  }) {
    if (routineName == null) {
      return globalHabits;
    }

    if (_isOtherRoutineName(routineName)) {
      return _computeUnassignedHabits(globalHabits, habitsByRoutine);
    }

    final key = _matchingRoutineKey(habitsByRoutine, routineName);
    return List<String>.from(key == null ? const [] : habitsByRoutine[key] ?? const []);
  }

  List<String> _routineFavoritesFor({
    required String? routineName,
    required List<String> globalFavorites,
    required List<String> screenHabits,
    required Map<String, List<String>> favoritesByRoutine,
  }) {
    if (routineName == null) {
      return globalFavorites;
    }

    final key = _matchingRoutineKey(favoritesByRoutine, routineName);
    final routineFavorites =
        List<String>.from(key == null ? const [] : favoritesByRoutine[key] ?? const []);

    return routineFavorites
        .where((favorite) => _containsHabit(screenHabits, favorite))
        .toList(growable: false);
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _parseDate(String input) {
    final trimmed = input.trim();

    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) return _dateOnly(parsed);

    final parts = trimmed.split('-');
    if (parts.length != 3) return _dateOnly(DateTime.now());

    if (parts[0].length == 4) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);

      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    } else {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);

      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return _dateOnly(DateTime.now());
  }

  Map<String, dynamic> _flattenTrackerEntries(Map<String, dynamic> data) {
    final trackerRoot = _asMap(data[_trackerRootKey]);
    if (trackerRoot == null) return {};

    final flattened = <String, dynamic>{};

    trackerRoot.forEach((_, rawListValue) {
      final listMap = _asMap(rawListValue);
      if (listMap == null) return;

      listMap.forEach((dateStr, activities) {
        if (activities is! List) return;

        final existing = flattened[dateStr];
        if (existing is List) {
          flattened[dateStr] = [...existing, ...activities];
        } else {
          flattened[dateStr] = List<dynamic>.from(activities);
        }
      });
    });

    return flattened;
  }

  Map<String, List<HabitTaskEntry>> _parseHabitTaskMap(
    Map<String, dynamic> data,
  ) {
    final result = <String, List<HabitTaskEntry>>{};

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
          HabitTaskEntry(
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
    Map<String, List<HabitTaskEntry>> taskMap,
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
    Map<String, dynamic> trackerDoc,
    String oldName,
    String newName,
  ) {
    final output = Map<String, dynamic>.from(trackerDoc);
    final trackerRoot = _asMap(output[_trackerRootKey]) ?? {};

    final updatedTrackerRoot = <String, dynamic>{};

    trackerRoot.forEach((listName, rawListValue) {
      final listMap = _asMap(rawListValue);

      if (listMap == null) {
        updatedTrackerRoot[listName] = rawListValue;
        return;
      }

      final updatedList = <String, dynamic>{};

      listMap.forEach((dateStr, activities) {
        if (activities is! List) {
          updatedList[dateStr] = activities;
          return;
        }

        updatedList[dateStr] = activities.map((item) {
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

      updatedTrackerRoot[listName] = updatedList;
    });

    output[_trackerRootKey] = updatedTrackerRoot;
    return output;
  }

  List<String> _replaceInList({
    required List<String> source,
    required String oldName,
    required String newName,
  }) {
    final seen = <String>{};
    final out = <String>[];

    for (final item in source) {
      final next = _sameHabit(item, oldName) ? newName.trim() : item.trim();
      if (next.isEmpty) continue;

      final key = next.toLowerCase();
      if (seen.add(key)) out.add(next);
    }

    return out;
  }

  Map<String, List<String>> _replaceInListMap({
    required Map<String, List<String>> source,
    required String oldName,
    required String newName,
  }) {
    final out = <String, List<String>>{};

    source.forEach((key, values) {
      out[key] = _replaceInList(
        source: values,
        oldName: oldName,
        newName: newName,
      );
    });

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

    final existingOtherHabit = _allKnownHabits().any(
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
        final routineName = _activeRoutine;

        if (routineName != null) {
          final favoritesByRoutine = _stringListMap(raw['favorites_by_routine']);
          final routineKey =
              _matchingRoutineKey(favoritesByRoutine, routineName) ?? routineName;
          final favorites =
              List<String>.from(favoritesByRoutine[routineKey] ?? const []);

          if (_containsHabit(favorites, habit)) {
            favorites.removeWhere((h) => _sameHabit(h, habit));
          } else {
            favorites.add(habit);
          }

          tx.set(
            _atomicHabitsRef,
            {
              'favorites_by_routine.$routineKey': _dedupeStrings(favorites),
            },
            SetOptions(merge: true),
          );
        } else {
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
        }
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

        if (_activeRoutine != null) {
          final routineKey = _matchingRoutineKey(
                _favoritesByRoutine,
                _activeRoutine!,
              ) ??
              _activeRoutine!;
          _favoritesByRoutine = {
            ..._favoritesByRoutine,
            routineKey: List<String>.from(_favorites),
          };
        } else {
          _globalFavorites = List<String>.from(_favorites);
        }

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
        final trackerSnap = await tx.get(_trackerRef);
        final habitsSnap = await tx.get(_atomicHabitsRef);

        final trackerData = Map<String, dynamic>.from(trackerSnap.data() ?? {});
        final habitsData = Map<String, dynamic>.from(habitsSnap.data() ?? {});

        final habitList = _stringList(habitsData['habits']);
        final favoriteList = _stringList(habitsData['favorites']);
        final habitsByRoutine = _stringListMap(habitsData['habits_by_routine']);
        final favoritesByRoutine =
            _stringListMap(habitsData['favorites_by_routine']);

        final updatedTracker = _rewriteTracker(trackerData, oldName, trimmed);
        final updatedHabits = _replaceInList(
          source: habitList,
          oldName: oldName,
          newName: trimmed,
        );
        final updatedFavorites = _replaceInList(
          source: favoriteList,
          oldName: oldName,
          newName: trimmed,
        );
        final updatedHabitsByRoutine = _replaceInListMap(
          source: habitsByRoutine,
          oldName: oldName,
          newName: trimmed,
        );
        final updatedFavoritesByRoutine = _replaceInListMap(
          source: favoritesByRoutine,
          oldName: oldName,
          newName: trimmed,
        );

        tx.set(_trackerRef, updatedTracker);
        tx.set(
          _atomicHabitsRef,
          {
            'habits': updatedHabits,
            'favorites': updatedFavorites,
            'habits_by_routine': updatedHabitsByRoutine,
            'favorites_by_routine': updatedFavoritesByRoutine,
          },
          SetOptions(merge: true),
        );
      });

      final localTracker = _rewriteTracker(_rawTrackerData, oldName, trimmed);
      final taskMap = _parseHabitTaskMap(_flattenTrackerEntries(localTracker));
      final updatedGlobalHabits = _replaceInList(
        source: _globalHabits,
        oldName: oldName,
        newName: trimmed,
      );
      final updatedHabitsByRoutine = _replaceInListMap(
        source: _habitsByRoutine,
        oldName: oldName,
        newName: trimmed,
      );
      final updatedFavoritesByRoutine = _replaceInListMap(
        source: _favoritesByRoutine,
        oldName: oldName,
        newName: trimmed,
      );
      final updatedGlobalFavorites = _replaceInList(
        source: _globalFavorites,
        oldName: oldName,
        newName: trimmed,
      );
      final updatedScreenHabits = _routineHabitsFor(
        routineName: _activeRoutine,
        globalHabits: updatedGlobalHabits,
        habitsByRoutine: updatedHabitsByRoutine,
      );
      final updatedScreenFavorites = _routineFavoritesFor(
        routineName: _activeRoutine,
        globalFavorites: updatedGlobalFavorites,
        screenHabits: updatedScreenHabits,
        favoritesByRoutine: updatedFavoritesByRoutine,
      );

      if (!mounted) return false;
      setState(() {
        _rawTrackerData = localTracker;
        _habitTaskMap = taskMap;
        _habitDateMap = _buildHabitDateMap(taskMap);
        _globalHabits = updatedGlobalHabits;
        _globalFavorites = updatedGlobalFavorites;
        _habitsByRoutine = updatedHabitsByRoutine;
        _favoritesByRoutine = updatedFavoritesByRoutine;
        _screenHabits = updatedScreenHabits;
        _favorites = updatedScreenFavorites;
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
        final trackerSnap = await tx.get(_trackerRef);
        final habitsSnap = await tx.get(_atomicHabitsRef);

        final trackerData = Map<String, dynamic>.from(trackerSnap.data() ?? {});
        final habitsData = Map<String, dynamic>.from(habitsSnap.data() ?? {});

        final habitList = _stringList(habitsData['habits']);
        final favoriteList = _stringList(habitsData['favorites']);
        final habitsByRoutine = _stringListMap(habitsData['habits_by_routine']);
        final favoritesByRoutine =
            _stringListMap(habitsData['favorites_by_routine']);

        final updatedTracker = _rewriteTracker(trackerData, fromHabit, intoHabit);
        final updatedHabits = _replaceInList(
          source: habitList,
          oldName: fromHabit,
          newName: intoHabit,
        );
        final updatedFavorites = _replaceInList(
          source: favoriteList,
          oldName: fromHabit,
          newName: intoHabit,
        );
        final updatedHabitsByRoutine = _replaceInListMap(
          source: habitsByRoutine,
          oldName: fromHabit,
          newName: intoHabit,
        );
        final updatedFavoritesByRoutine = _replaceInListMap(
          source: favoritesByRoutine,
          oldName: fromHabit,
          newName: intoHabit,
        );

        tx.set(_trackerRef, updatedTracker);
        tx.set(
          _atomicHabitsRef,
          {
            'habits': updatedHabits,
            'favorites': updatedFavorites,
            'habits_by_routine': updatedHabitsByRoutine,
            'favorites_by_routine': updatedFavoritesByRoutine,
          },
          SetOptions(merge: true),
        );
      });

      final localTracker = _rewriteTracker(_rawTrackerData, fromHabit, intoHabit);
      final taskMap = _parseHabitTaskMap(_flattenTrackerEntries(localTracker));
      final updatedGlobalHabits = _replaceInList(
        source: _globalHabits,
        oldName: fromHabit,
        newName: intoHabit,
      );
      final updatedHabitsByRoutine = _replaceInListMap(
        source: _habitsByRoutine,
        oldName: fromHabit,
        newName: intoHabit,
      );
      final updatedFavoritesByRoutine = _replaceInListMap(
        source: _favoritesByRoutine,
        oldName: fromHabit,
        newName: intoHabit,
      );
      final updatedGlobalFavorites = _replaceInList(
        source: _globalFavorites,
        oldName: fromHabit,
        newName: intoHabit,
      );
      final updatedScreenHabits = _routineHabitsFor(
        routineName: _activeRoutine,
        globalHabits: updatedGlobalHabits,
        habitsByRoutine: updatedHabitsByRoutine,
      );
      final updatedScreenFavorites = _routineFavoritesFor(
        routineName: _activeRoutine,
        globalFavorites: updatedGlobalFavorites,
        screenHabits: updatedScreenHabits,
        favoritesByRoutine: updatedFavoritesByRoutine,
      );

      if (!mounted) return false;
      setState(() {
        _rawTrackerData = localTracker;
        _habitTaskMap = taskMap;
        _habitDateMap = _buildHabitDateMap(taskMap);
        _globalHabits = updatedGlobalHabits;
        _globalFavorites = updatedGlobalFavorites;
        _habitsByRoutine = updatedHabitsByRoutine;
        _favoritesByRoutine = updatedFavoritesByRoutine;
        _screenHabits = updatedScreenHabits;
        _favorites = updatedScreenFavorites;
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
          habits: _allKnownHabits()
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
    final entries = List<HabitTaskEntry>.from(_habitTaskMap[habit] ?? const []);
    final dates = Map<DateTime, int>.from(_habitDateMap[habit] ?? const {});
    final isFavorite = _containsHabit(_favorites, habit);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HabitDetailsScreen(
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
        title: Text(_activeRoutine ?? 'Atomic Habits'),
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
          const RepaintBoundary(child: NeonRibbonBackground()),
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
              if (_isRoutineMode)
                InfoChip(
                  icon: _isOtherRoutineName(_activeRoutine)
                      ? Icons.category_outlined
                      : Icons.folder_special_rounded,
                  label: _activeRoutine ?? 'Routine',
                  isDark: isDark,
                ),
              InfoChip(
                icon: Icons.auto_awesome_rounded,
                label: '${habits.length} habits',
                isDark: isDark,
              ),
              InfoChip(
                icon: Icons.star_rounded,
                label: '${_favorites.length} favorites',
                isDark: isDark,
              ),
              InfoChip(
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
                                _visibleCount += 5;
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
                    final entries = _habitTaskMap[habit] ?? const <HabitTaskEntry>[];

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == visibleHabits.length - 1 ? 0 : 12,
                      ),
                      child: _CompactHabitCard(
                        key: ValueKey(habit),
                        habit: habit,
                        dates: dates,
                        entries: entries,
                        isFavorite: isFavorite,
                        isDark: isDark,
                        onOpen: () => _openHabitDetails(habit),
                        onFavorite: () => _toggleFavorite(habit),
                        onRename: () => _openRenamePage(habit),
                        onMerge: _allKnownHabits().length > 1
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
    final title = _isRoutineMode ? 'No habits in this routine' : 'No habits found';
    final subtitle = _isRoutineMode
        ? _isOtherRoutineName(_activeRoutine)
            ? 'There are currently no unassigned habits.'
            : 'Add habits to "${_activeRoutine ?? 'this routine'}" from the routines screen.'
        : 'Try a different search or add more habits to Firestore.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isRoutineMode
                  ? Icons.playlist_add_check_rounded
                  : Icons.search_off_rounded,
              size: 56,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
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
      itemCount: 6,
      itemBuilder: (_, __) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 132,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        );
      },
    );
  }
}

class _CompactHabitCard extends StatefulWidget {
  final String habit;
  final Map<DateTime, int> dates;
  final List<HabitTaskEntry> entries;
  final bool isFavorite;
  final bool isDark;
  final VoidCallback onOpen;
  final Future<bool> Function() onFavorite;
  final VoidCallback onRename;
  final VoidCallback? onMerge;

  const _CompactHabitCard({
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

  @override
  State<_CompactHabitCard> createState() => _CompactHabitCardState();
}

class _CompactHabitCardState extends State<_CompactHabitCard> {
  bool _showHeatmap = false;

  int get _totalOccurrences =>
      widget.dates.values.fold(0, (sum, count) => sum + count);

  int get _activeDays => widget.dates.keys.length;

  int get _streak {
    if (widget.dates.isEmpty) return 0;

    final normalized = widget.dates.keys
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
    final cardColor = widget.isDark ? const Color(0xFF15171C) : Colors.white;
    final subtitleColor = widget.isDark ? Colors.white60 : Colors.black54;

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor.withOpacity(0.95),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color:
                widget.isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isDark
                  ? Colors.black.withOpacity(0.16)
                  : Colors.black.withOpacity(0.045),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: widget.onOpen,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (widget.isFavorite) ...[
                                const Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: Color(0xFFF59E0B),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  widget.habit,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        height: 1.15,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${widget.entries.length} tasks logged',
                            style: TextStyle(
                              fontSize: 12,
                              color: subtitleColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _MiniIconButton(
                  tooltip:
                      widget.isFavorite ? 'Remove favorite' : 'Add favorite',
                  icon: widget.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  iconColor: widget.isFavorite
                      ? const Color(0xFFF59E0B)
                      : (widget.isDark ? Colors.white60 : Colors.black45),
                  onTap: () {
                    widget.onFavorite();
                  },
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: widget.isDark ? Colors.white70 : Colors.black54,
                  ),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (value) {
                    if (value == 'details') {
                      widget.onOpen();
                    } else if (value == 'rename') {
                      widget.onRename();
                    } else if (value == 'merge') {
                      widget.onMerge?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: 'details',
                      child: Row(
                        children: [
                          Icon(Icons.open_in_new_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Open details'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(
                            Icons.drive_file_rename_outline_rounded,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Text('Rename'),
                        ],
                      ),
                    ),
                    if (widget.onMerge != null)
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
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricPill(
                  icon: Icons.check_circle_outline_rounded,
                  label: '$_totalOccurrences',
                  helper: 'Total',
                  isDark: widget.isDark,
                ),
                _MetricPill(
                  icon: Icons.calendar_today_rounded,
                  label: '$_activeDays',
                  helper: 'Days',
                  isDark: widget.isDark,
                ),
                _MetricPill(
                  icon: Icons.local_fire_department_rounded,
                  label: '$_streak',
                  helper: 'Streak',
                  isDark: widget.isDark,
                ),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() {
                  _showHeatmap = !_showHeatmap;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? Colors.white.withOpacity(0.05)
                      : const Color(0xFFF6F8FB),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.grid_view_rounded,
                      size: 17,
                      color: widget.isDark ? Colors.white70 : Colors.black54,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Heatmap',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: widget.isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _showHeatmap ? 'Hide' : 'Show',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: subtitleColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _showHeatmap ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: widget.isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: _showHeatmap
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: HabitHeatmap(
                  dates: widget.dates,
                  isDark: widget.isDark,
                ),
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
                'This updates the habits list, every routine mapping, and every matching atomic_habit inside tracker.',
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

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String helper;
  final bool isDark;

  const _MetricPill({
    required this.icon,
    required this.label,
    required this.helper,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : const Color(0xFFF4F7FB),
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
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            helper,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _MiniIconButton({
    required this.tooltip,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              icon,
              size: 18,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const InfoChip({
    super.key,
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.07)
            : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
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
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class HabitHeatmap extends StatelessWidget {
  final Map<DateTime, int> dates;
  final bool isDark;

  const HabitHeatmap({
    super.key,
    required this.dates,
    required this.isDark,
  });

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final dayList = List<DateTime>.generate(
      28,
      (index) => today.subtract(Duration(days: 27 - index)),
    );

    final normalized = <DateTime, int>{};
    for (final entry in dates.entries) {
      normalized[_dateOnly(entry.key)] = entry.value;
    }

    var maxCount = 0;
    for (final count in normalized.values) {
      if (count > maxCount) maxCount = count;
    }

    Color cellColor(int count) {
      if (count <= 0) {
        return isDark ? Colors.white10 : Colors.black12;
      }

      final ratio = maxCount == 0 ? 0.4 : (count / maxCount);
      final opacity = 0.22 + (ratio * 0.72);
      return Theme.of(context).colorScheme.primary.withOpacity(
            opacity.clamp(0.22, 0.94),
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: dayList.map((day) {
            final count = normalized[day] ?? 0;

            return Tooltip(
              message: '${day.day}/${day.month}: $count',
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: cellColor(count),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Text(
          'Last 28 days',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
      ],
    );
  }
}