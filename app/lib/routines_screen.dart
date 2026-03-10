import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'atomic_habits_screen.dart';
import 'shared/neon_ribbon_background.dart';
import 'shared/theme.dart';

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  static const String _otherRoutineName = 'Other';

  final DocumentReference<Map<String, dynamic>> _atomicHabitsRef =
      FirebaseFirestore.instance.collection('habit').doc('atomic_habits');

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _habitsSub;

  List<String> _routines = [];
  Map<String, List<String>> _habitsByRoutine = {};
  Map<String, List<String>> _favoritesByRoutine = {};
  List<String> _allHabits = [];
  List<String> _globalFavorites = [];
  Map<String, dynamic> _extraRootFields = {};

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _habitsSub = _atomicHabitsRef.snapshots().listen(
      (snap) {
        final raw = Map<String, dynamic>.from(snap.data() ?? {});

        final rawRoutines = _stringList(raw['routines']);
        final mergedHabitsByRoutine = _readRoutineListMapFromRaw(
          raw: raw,
          rootField: 'habits_by_routine',
        );
        final mergedFavoritesByRoutine = _readRoutineListMapFromRaw(
          raw: raw,
          rootField: 'favorites_by_routine',
        );
        final allHabits = _stringList(raw['habits']);
        final globalFavorites = _stringList(raw['favorites']);
        final extraRootFields = _extractExtraRootFields(raw);

        final canonical = _buildCanonicalState(
          routines: rawRoutines,
          allHabits: allHabits,
          habitsByRoutine: mergedHabitsByRoutine,
          favoritesByRoutine: mergedFavoritesByRoutine,
        );

        if (!mounted) return;

        setState(() {
          _routines = canonical.routines;
          _habitsByRoutine = _cloneListMap(canonical.habitsByRoutine);
          _favoritesByRoutine = _cloneListMap(canonical.favoritesByRoutine);
          _allHabits = List<String>.from(allHabits);
          _globalFavorites = List<String>.from(globalFavorites);
          _extraRootFields = Map<String, dynamic>.from(extraRootFields);
          _loading = false;
        });

        unawaited(
          _normalizeDocumentIfNeeded(
            raw: raw,
            canonical: canonical,
            allHabits: allHabits,
            globalFavorites: globalFavorites,
            extraRootFields: extraRootFields,
          ),
        );
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _loading = false);
      },
    );
  }

  @override
  void dispose() {
    _habitsSub?.cancel();
    super.dispose();
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

  Map<String, List<String>> _readRoutineListMapFromRaw({
    required Map<String, dynamic> raw,
    required String rootField,
  }) {
    final out = <String, List<String>>{};

    final nested = raw[rootField];
    if (nested is Map) {
      final nestedMap = _stringListMap(nested);
      nestedMap.forEach((key, value) {
        final routine = key.trim();
        if (routine.isEmpty) return;
        out[routine] = value;
      });
    }

    // Legacy support:
    // if fields like habits_by_routine.Wakeup exist at the root level,
    // read them too and let them override the nested map.
    final prefix = '$rootField.';
    raw.forEach((key, value) {
      if (!key.startsWith(prefix)) return;

      final routine = key.substring(prefix.length).trim();
      if (routine.isEmpty) return;

      final existingKey = _matchingRoutineKey(out, routine);
      if (existingKey != null && existingKey != routine) {
        out.remove(existingKey);
      }

      out[routine] = _stringList(value);
    });

    return out;
  }

  Map<String, dynamic> _extractExtraRootFields(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};

    for (final entry in raw.entries) {
      final key = entry.key;

      final isManaged = key == 'routines' ||
          key == 'habits' ||
          key == 'favorites' ||
          key == 'habits_by_routine' ||
          key == 'favorites_by_routine' ||
          key.startsWith('habits_by_routine.') ||
          key.startsWith('favorites_by_routine.');

      if (isManaged) continue;
      out[key] = entry.value;
    }

    return out;
  }

  Map<String, List<String>> _cloneListMap(Map<String, List<String>> source) {
    return source.map(
      (key, value) => MapEntry(key, List<String>.from(value)),
    );
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

  bool _sameText(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  bool _containsText(Iterable<String> items, String value) {
    return items.any((item) => _sameText(item, value));
  }

  bool _isOtherRoutine(String routine) => _sameText(routine, _otherRoutineName);

  String? _matchingRoutineKey(
    Map<String, List<String>> map,
    String routineName,
  ) {
    for (final key in map.keys) {
      if (_sameText(key, routineName)) return key;
    }
    return null;
  }

  List<String> _computeUnassignedHabits(
    List<String> allHabits,
    Map<String, List<String>> habitsByRoutine,
  ) {
    final assigned = <String>{};

    habitsByRoutine.forEach((routine, habits) {
      if (_isOtherRoutine(routine)) return;

      for (final habit in habits) {
        final normalized = habit.trim().toLowerCase();
        if (normalized.isNotEmpty) {
          assigned.add(normalized);
        }
      }
    });

    return allHabits
        .where((habit) => !assigned.contains(habit.trim().toLowerCase()))
        .toList(growable: false);
  }

  bool _sameStringList(List<String> a, List<String> b) {
    final left = a.map((e) => e.trim().toLowerCase()).toList(growable: false);
    final right = b.map((e) => e.trim().toLowerCase()).toList(growable: false);

    if (left.length != right.length) return false;

    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }

    return true;
  }

  bool _sameStringListMap(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    if (a.length != b.length) return false;

    for (final entry in a.entries) {
      final otherKey = _matchingRoutineKey(b, entry.key);
      if (otherKey == null) return false;
      if (!_sameStringList(entry.value, b[otherKey] ?? const [])) return false;
    }

    return true;
  }

  bool _hasLegacyDottedKeys(Map<String, dynamic> raw) {
    return raw.keys.any(
      (key) =>
          key.startsWith('habits_by_routine.') ||
          key.startsWith('favorites_by_routine.'),
    );
  }

  _CanonicalRoutineState _buildCanonicalState({
    required List<String> routines,
    required List<String> allHabits,
    required Map<String, List<String>> habitsByRoutine,
    required Map<String, List<String>> favoritesByRoutine,
  }) {
    final cleanedAllHabits = _dedupeStrings(allHabits);

    final customRoutines = _dedupeStrings(
      routines.where((routine) => !_isOtherRoutine(routine)),
    );

    final cleanedHabitsByRoutine = <String, List<String>>{};
    final cleanedFavoritesByRoutine = <String, List<String>>{};

    for (final routine in customRoutines) {
      final habitsKey = _matchingRoutineKey(habitsByRoutine, routine);
      final favoritesKey = _matchingRoutineKey(favoritesByRoutine, routine);

      final routineHabits = _dedupeStrings(
        habitsKey != null ? habitsByRoutine[habitsKey] ?? const [] : const [],
      );

      final routineFavorites = _dedupeStrings(
        favoritesKey != null
            ? favoritesByRoutine[favoritesKey] ?? const []
            : const [],
      ).where((favorite) => _containsText(routineHabits, favorite)).toList(
            growable: false,
          );

      cleanedHabitsByRoutine[routine] = routineHabits;
      cleanedFavoritesByRoutine[routine] = routineFavorites;
    }

    final unassignedHabits =
        _computeUnassignedHabits(cleanedAllHabits, cleanedHabitsByRoutine);

    final otherFavoritesKey =
        _matchingRoutineKey(favoritesByRoutine, _otherRoutineName);
    final otherFavorites = _dedupeStrings(
      otherFavoritesKey != null
          ? favoritesByRoutine[otherFavoritesKey] ?? const []
          : const [],
    ).where((favorite) => _containsText(unassignedHabits, favorite)).toList(
          growable: false,
        );

    final storedRoutines = <String>[
      ...customRoutines,
      if (unassignedHabits.isNotEmpty) _otherRoutineName,
    ];

    final storedHabitsByRoutine = _cloneListMap(cleanedHabitsByRoutine);
    final storedFavoritesByRoutine = _cloneListMap(cleanedFavoritesByRoutine);

    if (unassignedHabits.isNotEmpty) {
      storedHabitsByRoutine[_otherRoutineName] = unassignedHabits;
      storedFavoritesByRoutine[_otherRoutineName] = otherFavorites;
    }

    return _CanonicalRoutineState(
      routines: storedRoutines,
      habitsByRoutine: storedHabitsByRoutine,
      favoritesByRoutine: storedFavoritesByRoutine,
    );
  }

  Future<void> _writeCanonicalDocument({
    required _CanonicalRoutineState state,
    required List<String> allHabits,
    required List<String> globalFavorites,
    required Map<String, dynamic> extraRootFields,
  }) async {
    await _atomicHabitsRef.set({
      ...extraRootFields,
      'routines': List<String>.from(state.routines),
      'habits': List<String>.from(allHabits),
      'favorites': List<String>.from(globalFavorites),
      'habits_by_routine': state.habitsByRoutine.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
      'favorites_by_routine': state.favoritesByRoutine.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    });
  }

  Future<void> _normalizeDocumentIfNeeded({
    required Map<String, dynamic> raw,
    required _CanonicalRoutineState canonical,
    required List<String> allHabits,
    required List<String> globalFavorites,
    required Map<String, dynamic> extraRootFields,
  }) async {
    final currentNestedHabitsByRoutine = _stringListMap(raw['habits_by_routine']);
    final currentNestedFavoritesByRoutine =
        _stringListMap(raw['favorites_by_routine']);
    final currentRoutines = _stringList(raw['routines']);

    final needsRewrite = _hasLegacyDottedKeys(raw) ||
        !_sameStringList(currentRoutines, canonical.routines) ||
        !_sameStringListMap(
          currentNestedHabitsByRoutine,
          canonical.habitsByRoutine,
        ) ||
        !_sameStringListMap(
          currentNestedFavoritesByRoutine,
          canonical.favoritesByRoutine,
        );

    if (!needsRewrite) return;

    try {
      await _writeCanonicalDocument(
        state: canonical,
        allHabits: allHabits,
        globalFavorites: globalFavorites,
        extraRootFields: extraRootFields,
      );
    } catch (_) {
      // Ignore background normalization errors.
    }
  }

  _LocalScreenState _captureLocalState() {
    return _LocalScreenState(
      routines: List<String>.from(_routines),
      habitsByRoutine: _cloneListMap(_habitsByRoutine),
      favoritesByRoutine: _cloneListMap(_favoritesByRoutine),
      allHabits: List<String>.from(_allHabits),
      globalFavorites: List<String>.from(_globalFavorites),
      extraRootFields: Map<String, dynamic>.from(_extraRootFields),
    );
  }

  void _restoreLocalState(_LocalScreenState state) {
    if (!mounted) return;

    setState(() {
      _routines = List<String>.from(state.routines);
      _habitsByRoutine = _cloneListMap(state.habitsByRoutine);
      _favoritesByRoutine = _cloneListMap(state.favoritesByRoutine);
      _allHabits = List<String>.from(state.allHabits);
      _globalFavorites = List<String>.from(state.globalFavorites);
      _extraRootFields = Map<String, dynamic>.from(state.extraRootFields);
    });
  }

  void _applyLocalCanonicalState({
    required _CanonicalRoutineState state,
    required List<String> allHabits,
  }) {
    if (!mounted) return;

    setState(() {
      _routines = List<String>.from(state.routines);
      _habitsByRoutine = _cloneListMap(state.habitsByRoutine);
      _favoritesByRoutine = _cloneListMap(state.favoritesByRoutine);
      _allHabits = List<String>.from(allHabits);
    });
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

  int get _customRoutineCount =>
      _routines.where((routine) => !_isOtherRoutine(routine)).length;

  int get _assignedHabitCount {
    final unique = <String>{};

    _habitsByRoutine.forEach((routine, habits) {
      if (_isOtherRoutine(routine)) return;

      for (final habit in habits) {
        unique.add(habit.trim().toLowerCase());
      }
    });

    return unique.length;
  }

  int get _unassignedHabitCount {
    final computed = _computeUnassignedHabits(_allHabits, _habitsByRoutine);
    return computed.length;
  }

  void _openRoutine(String? routine) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AtomicHabitsScreen(routine: routine),
      ),
    );
  }

  Future<void> _runSaving(Future<void> Function() action) async {
    if (_saving) return;

    setState(() => _saving = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _addRoutine() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _SingleTextInputDialog(
        title: 'Create routine',
        hintText: 'Routine name',
        actionLabel: 'Create',
        icon: Icons.add_rounded,
      ),
    );

    if (result == null || result.trim().isEmpty) return;

    final routineName = result.trim();

    if (_isOtherRoutine(routineName)) {
      _snack(
        '"$_otherRoutineName" is automatic and only appears for unassigned habits.',
        error: true,
      );
      return;
    }

    if (_containsText(_routines, routineName)) {
      _snack('A routine named "$routineName" already exists.', error: true);
      return;
    }

    await _runSaving(() async {
      final previous = _captureLocalState();

      final customRoutines = _routines
          .where((routine) => !_isOtherRoutine(routine))
          .toList(growable: false);

      final nextHabitsByRoutine = _cloneListMap(_habitsByRoutine)
        ..removeWhere((key, _) => _isOtherRoutine(key))
        ..[routineName] = [];

      final nextFavoritesByRoutine = _cloneListMap(_favoritesByRoutine)
        ..removeWhere((key, _) => _isOtherRoutine(key))
        ..[routineName] = [];

      final nextState = _buildCanonicalState(
        routines: [...customRoutines, routineName],
        allHabits: _allHabits,
        habitsByRoutine: nextHabitsByRoutine,
        favoritesByRoutine: nextFavoritesByRoutine,
      );

      _applyLocalCanonicalState(
        state: nextState,
        allHabits: _allHabits,
      );

      try {
        await _writeCanonicalDocument(
          state: nextState,
          allHabits: _allHabits,
          globalFavorites: _globalFavorites,
          extraRootFields: _extraRootFields,
        );

        _snack('Routine "$routineName" created');
      } catch (_) {
        _restoreLocalState(previous);
        _snack('Could not create routine.', error: true);
      }
    });
  }

  Future<void> _addHabit() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _SingleTextInputDialog(
        title: 'Create habit',
        hintText: 'Habit name',
        actionLabel: 'Add habit',
        icon: Icons.auto_awesome_rounded,
      ),
    );

    if (result == null || result.trim().isEmpty) return;

    final habitName = result.trim();

    if (_containsText(_allHabits, habitName)) {
      _snack('A habit named "$habitName" already exists.', error: true);
      return;
    }

    await _runSaving(() async {
      final previous = _captureLocalState();

      final nextAllHabits = _dedupeStrings([..._allHabits, habitName]);

      final nextState = _buildCanonicalState(
        routines: _routines,
        allHabits: nextAllHabits,
        habitsByRoutine: _habitsByRoutine,
        favoritesByRoutine: _favoritesByRoutine,
      );

      _applyLocalCanonicalState(
        state: nextState,
        allHabits: nextAllHabits,
      );

      try {
        await _writeCanonicalDocument(
          state: nextState,
          allHabits: nextAllHabits,
          globalFavorites: _globalFavorites,
          extraRootFields: _extraRootFields,
        );

        _snack('Habit "$habitName" added');
      } catch (_) {
        _restoreLocalState(previous);
        _snack('Could not add habit.', error: true);
      }
    });
  }

  Future<void> _deleteRoutine(String routine) async {
    if (_isOtherRoutine(routine)) {
      _snack(
        '"$_otherRoutineName" is automatic and cannot be deleted manually.',
        error: true,
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete routine'),
        content: Text(
          'Delete "$routine"? The routine will be removed, but the habits themselves will stay and become unassigned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _runSaving(() async {
      final previous = _captureLocalState();

      final customRoutines = _routines
          .where((item) => !_sameText(item, routine) && !_isOtherRoutine(item))
          .toList(growable: false);

      final nextHabitsByRoutine = _cloneListMap(_habitsByRoutine)
        ..removeWhere((key, _) => _isOtherRoutine(key) || _sameText(key, routine));

      final nextFavoritesByRoutine = _cloneListMap(_favoritesByRoutine)
        ..removeWhere((key, _) => _isOtherRoutine(key) || _sameText(key, routine));

      final nextState = _buildCanonicalState(
        routines: customRoutines,
        allHabits: _allHabits,
        habitsByRoutine: nextHabitsByRoutine,
        favoritesByRoutine: nextFavoritesByRoutine,
      );

      _applyLocalCanonicalState(
        state: nextState,
        allHabits: _allHabits,
      );

      try {
        await _writeCanonicalDocument(
          state: nextState,
          allHabits: _allHabits,
          globalFavorites: _globalFavorites,
          extraRootFields: _extraRootFields,
        );

        _snack('Routine "$routine" deleted');
      } catch (_) {
        _restoreLocalState(previous);
        _snack('Could not delete routine.', error: true);
      }
    });
  }

  Future<void> _manageHabitsInRoutine(String routine) async {
    if (_isOtherRoutine(routine)) {
      _snack(
        '"$_otherRoutineName" updates automatically when a habit is not assigned to any routine.',
      );
      return;
    }

    final currentHabits =
        List<String>.from(_habitsByRoutine[routine] ?? const []);
    final currentFavorites =
        List<String>.from(_favoritesByRoutine[routine] ?? const []);
    final availableHabits = _dedupeStrings([..._allHabits, ...currentHabits]);

    final selectedHabits = await showDialog<List<String>>(
      context: context,
      builder: (_) => _ManageHabitsDialog(
        routine: routine,
        currentHabits: currentHabits,
        availableHabits: availableHabits,
      ),
    );

    if (selectedHabits == null) return;

    final cleanedSelection = _dedupeStrings(selectedHabits);
    final cleanedFavorites = currentFavorites
        .where((favorite) => _containsText(cleanedSelection, favorite))
        .toList(growable: false);

    final updatedGlobalHabits = _dedupeStrings([
      ..._allHabits,
      ...cleanedSelection,
    ]);

    await _runSaving(() async {
      final previous = _captureLocalState();

      final customRoutines = _routines
          .where((item) => !_isOtherRoutine(item))
          .toList(growable: false);

      final nextHabitsByRoutine = _cloneListMap(_habitsByRoutine)
        ..removeWhere((key, _) => _isOtherRoutine(key))
        ..[routine] = cleanedSelection;

      final nextFavoritesByRoutine = _cloneListMap(_favoritesByRoutine)
        ..removeWhere((key, _) => _isOtherRoutine(key))
        ..[routine] = cleanedFavorites;

      final nextState = _buildCanonicalState(
        routines: customRoutines,
        allHabits: updatedGlobalHabits,
        habitsByRoutine: nextHabitsByRoutine,
        favoritesByRoutine: nextFavoritesByRoutine,
      );

      _applyLocalCanonicalState(
        state: nextState,
        allHabits: updatedGlobalHabits,
      );

      try {
        await _writeCanonicalDocument(
          state: nextState,
          allHabits: updatedGlobalHabits,
          globalFavorites: _globalFavorites,
          extraRootFields: _extraRootFields,
        );

        _snack('Updated "$routine"');
      } catch (_) {
        _restoreLocalState(previous);
        _snack('Could not update routine habits.', error: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Routines'),
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
          IconButton(
            tooltip: 'Add routine',
            onPressed: _saving ? null : _addRoutine,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _addRoutine,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New routine'),
            ),
      body: Stack(
        children: [
          const NeonRibbonBackground(),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                          child: _buildHeaderCard(isDark),
                        ),
                      ),
                      if (_routines.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                            child: _buildEmptyState(isDark),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final routine = _routines[index];
                                return _buildRoutineCard(
                                  routine: routine,
                                  index: index,
                                  isDark: isDark,
                                );
                              },
                              childCount: _routines.length,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              childAspectRatio: 0.80,
                            ),
                          ),
                        ),
                    ],
                  ),
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

  Widget _buildHeaderCard(bool isDark) {
    final surface = isDark
        ? const Color(0xFF15171C).withOpacity(0.92)
        : Colors.white.withOpacity(0.92);

    final subtitleColor = isDark ? Colors.white70 : Colors.black54;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => _openRoutine(null),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withOpacity(0.18)
                    : Colors.black.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color:
                          Theme.of(context).colorScheme.primary.withOpacity(0.12),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 26,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : const Color(0xFFF5F7FB),
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Organize habits into routines',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _allHabits.isEmpty
                    ? 'Create your first habit or routine to start building a clean, structured system.'
                    : 'Tap this card to open all atomic habits together. Use routines to group them neatly and keep unassigned habits out of the way.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: subtitleColor,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _RoutineSummaryPill(
                    icon: Icons.grid_view_rounded,
                    label: '$_customRoutineCount routines',
                    isDark: isDark,
                  ),
                  _RoutineSummaryPill(
                    icon: Icons.checklist_rounded,
                    label: '${_allHabits.length} total habits',
                    isDark: isDark,
                  ),
                  _RoutineSummaryPill(
                    icon: Icons.link_rounded,
                    label: '$_assignedHabitCount assigned',
                    isDark: isDark,
                  ),
                  if (_unassignedHabitCount > 0)
                    _RoutineSummaryPill(
                      icon: Icons.category_outlined,
                      label: '$_unassignedHabitCount in $_otherRoutineName',
                      isDark: isDark,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : () => _openRoutine(null),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Open all habits'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _addHabit,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('New habit'),
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

  Widget _buildEmptyState(bool isDark) {
    final surface = isDark
        ? const Color(0xFF15171C).withOpacity(0.92)
        : Colors.white.withOpacity(0.92);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withOpacity(0.16)
                    : Colors.black.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                ),
                child: Icon(
                  Icons.dashboard_customize_rounded,
                  size: 34,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No routines yet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'You can still browse all habits together, create a new habit, or create a routine to start grouping them beautifully.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white70 : Colors.black54,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openRoutine(null),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text('Open all habits (${_allHabits.length})'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addHabit,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Create new habit'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addRoutine,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create first routine'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoutineCard({
    required String routine,
    required int index,
    required bool isDark,
  }) {
    final isOther = _isOtherRoutine(routine);

    final icons = <IconData>[
      Icons.wb_sunny_outlined,
      Icons.bedtime_outlined,
      Icons.fitness_center_rounded,
      Icons.work_outline_rounded,
      Icons.school_outlined,
      Icons.psychology_alt_outlined,
      Icons.self_improvement_rounded,
      Icons.menu_book_rounded,
      Icons.favorite_border_rounded,
      Icons.nightlight_round,
    ];

    final icon = isOther ? Icons.category_outlined : icons[index % icons.length];
    final habitCount = _habitsByRoutine[routine]?.length ?? 0;
    final favoriteCount = _favoritesByRoutine[routine]?.length ?? 0;

    final surface = isDark
        ? const Color(0xFF15171C).withOpacity(0.96)
        : Colors.white.withOpacity(0.97);

    return KeyedSubtree(
      key: ValueKey(
        '$routine|$habitCount|$favoriteCount|${(_habitsByRoutine[routine] ?? const []).join(",")}',
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openRoutine(routine),
          borderRadius: BorderRadius.circular(26),
          child: Container(
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withOpacity(0.18)
                      : Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color:
                            Theme.of(context).colorScheme.primary.withOpacity(0.12),
                      ),
                      child: Icon(
                        icon,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    if (!isOther)
                      PopupMenuButton<String>(
                        tooltip: 'Routine actions',
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        onSelected: (value) {
                          if (value == 'manage') {
                            _manageHabitsInRoutine(routine);
                          } else if (value == 'delete') {
                            _deleteRoutine(routine);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem<String>(
                            value: 'manage',
                            child: Row(
                              children: [
                                Icon(Icons.tune_rounded, size: 18),
                                SizedBox(width: 10),
                                Text('Manage habits'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Delete routine',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: isDark
                                ? Colors.white.withOpacity(0.05)
                                : const Color(0xFFF5F7FB),
                          ),
                          child: Icon(
                            Icons.more_horiz_rounded,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: isDark
                              ? Colors.white.withOpacity(0.05)
                              : const Color(0xFFF5F7FB),
                        ),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  routine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  isOther
                      ? habitCount == 0
                          ? 'No unassigned habits'
                          : '$habitCount waiting to be assigned'
                      : habitCount == 0
                          ? 'No habits assigned yet'
                          : '$habitCount habit${habitCount == 1 ? '' : 's'} in this routine',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoutineMiniPill(
                      icon: Icons.check_rounded,
                      label: '$habitCount',
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _RoutineMiniPill(
                      icon:
                          isOther ? Icons.auto_awesome_rounded : Icons.star_rounded,
                      label: isOther ? '' : '$favoriteCount',
                      isDark: isDark,
                    ),
                    const Spacer(),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isDark
                            ? Colors.white.withOpacity(0.06)
                            : const Color(0xFFF5F7FB),
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fade(delay: (70 * index).ms)
        .slideY(begin: 0.08, delay: (70 * index).ms, duration: 280.ms);
  }
}

class _CanonicalRoutineState {
  final List<String> routines;
  final Map<String, List<String>> habitsByRoutine;
  final Map<String, List<String>> favoritesByRoutine;

  const _CanonicalRoutineState({
    required this.routines,
    required this.habitsByRoutine,
    required this.favoritesByRoutine,
  });
}

class _LocalScreenState {
  final List<String> routines;
  final Map<String, List<String>> habitsByRoutine;
  final Map<String, List<String>> favoritesByRoutine;
  final List<String> allHabits;
  final List<String> globalFavorites;
  final Map<String, dynamic> extraRootFields;

  const _LocalScreenState({
    required this.routines,
    required this.habitsByRoutine,
    required this.favoritesByRoutine,
    required this.allHabits,
    required this.globalFavorites,
    required this.extraRootFields,
  });
}

class _RoutineSummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _RoutineSummaryPill({
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
            ? Colors.white.withOpacity(0.06)
            : const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
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

class _RoutineMiniPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _RoutineMiniPill({
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
            : const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SingleTextInputDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final String actionLabel;
  final IconData icon;

  const _SingleTextInputDialog({
    required this.title,
    required this.hintText,
    required this.actionLabel,
    required this.icon,
  });

  @override
  State<_SingleTextInputDialog> createState() => _SingleTextInputDialogState();
}

class _SingleTextInputDialogState extends State<_SingleTextInputDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
            ),
            child: Icon(
              widget.icon,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
          suffixIcon: hasText
              ? IconButton(
                  onPressed: () {
                    _controller.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
        ),
        onChanged: (_) => setState(() {}),
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: hasText ? _submit : null,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

class _ManageHabitsDialog extends StatefulWidget {
  final String routine;
  final List<String> currentHabits;
  final List<String> availableHabits;

  const _ManageHabitsDialog({
    required this.routine,
    required this.currentHabits,
    required this.availableHabits,
  });

  @override
  State<_ManageHabitsDialog> createState() => _ManageHabitsDialogState();
}

class _ManageHabitsDialogState extends State<_ManageHabitsDialog> {
  late List<String> _selectedHabits;
  late List<String> _availableHabits;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedHabits = _dedupeStrings(widget.currentHabits);
    _availableHabits = _dedupeStrings([
      ...widget.availableHabits,
      ...widget.currentHabits,
    ]);

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

  bool _sameText(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  bool _containsText(Iterable<String> items, String value) {
    return items.any((item) => _sameText(item, value));
  }

  void _toggleHabit(String habit) {
    setState(() {
      if (_containsText(_selectedHabits, habit)) {
        _selectedHabits.removeWhere((item) => _sameText(item, habit));
      } else {
        _selectedHabits.add(habit);
      }
      _selectedHabits = _dedupeStrings(_selectedHabits);
    });
  }

  List<String> get _orderedHabits {
    final selected = _selectedHabits.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final unselected = _availableHabits
        .where((habit) => !_containsText(_selectedHabits, habit))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return [...selected, ...unselected];
  }

  List<String> get _filteredHabits {
    final items = _orderedHabits;
    if (_query.isEmpty) return items;

    return items
        .where((habit) => habit.toLowerCase().contains(_query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filteredHabits = _filteredHabits;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Manage habits',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.routine,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedHabits.isNotEmpty) ...[
              Text(
                'Selected (${_selectedHabits.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedHabits.map((habit) {
                  return Chip(
                    label: Text(habit),
                    deleteIcon: const Icon(Icons.close_rounded, size: 18),
                    onDeleted: () => _toggleHabit(habit),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search habits...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        onPressed: () => _searchController.clear(),
                        icon: const Icon(Icons.close_rounded),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withOpacity(0.04)
                    : const Color(0xFFF5F7FB),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'All habits',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: isDark
                      ? Colors.white.withOpacity(0.04)
                      : const Color(0xFFF7F9FC),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                  ),
                ),
                child: filteredHabits.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No habits match your search.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        itemCount: filteredHabits.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, index) {
                          final habit = filteredHabits[index];
                          final selected = _containsText(_selectedHabits, habit);

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _toggleHabit(habit),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: selected
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withOpacity(0.10)
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: selected
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withOpacity(0.24)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: selected,
                                      onChanged: (_) => _toggleHabit(habit),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        habit,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _dedupeStrings(_selectedHabits),
          ),
          child: const Text('Save changes'),
        ),
      ],
    );
  }
}