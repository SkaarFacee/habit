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
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _habitsSub = _atomicHabitsRef.snapshots().listen(
      (snap) {
        final raw = Map<String, dynamic>.from(snap.data() ?? {});
        final rawRoutines = _stringList(raw['routines']);
        final rawHabitsByRoutine = _stringListMap(raw['habits_by_routine']);
        final rawFavoritesByRoutine =
            _stringListMap(raw['favorites_by_routine']);
        final allHabits = _stringList(raw['habits']);

        final customRoutines = rawRoutines
            .where((routine) => !_isOtherRoutine(routine))
            .toList(growable: false);

        final unassignedHabits =
            _computeUnassignedHabits(allHabits, rawHabitsByRoutine);

        final visibleRoutines = <String>[
          ...customRoutines,
          if (unassignedHabits.isNotEmpty) _otherRoutineName,
        ];

        final visibleHabitsByRoutine =
            Map<String, List<String>>.from(rawHabitsByRoutine)
              ..removeWhere((key, _) => _isOtherRoutine(key));

        final visibleFavoritesByRoutine =
            Map<String, List<String>>.from(rawFavoritesByRoutine)
              ..removeWhere((key, _) => _isOtherRoutine(key));

        if (unassignedHabits.isNotEmpty) {
          visibleHabitsByRoutine[_otherRoutineName] = unassignedHabits;

          final currentOtherFavorites =
              List<String>.from(rawFavoritesByRoutine[_otherRoutineName] ?? []);
          visibleFavoritesByRoutine[_otherRoutineName] = currentOtherFavorites
              .where((favorite) => _containsText(unassignedHabits, favorite))
              .toList(growable: false);
        }

        if (!mounted) return;

        setState(() {
          _routines = visibleRoutines;
          _habitsByRoutine = visibleHabitsByRoutine;
          _favoritesByRoutine = visibleFavoritesByRoutine;
          _allHabits = allHabits;
          _loading = false;
        });

        unawaited(
          _syncOtherRoutine(
            rawRoutines: rawRoutines,
            rawHabitsByRoutine: rawHabitsByRoutine,
            rawFavoritesByRoutine: rawFavoritesByRoutine,
            allHabits: allHabits,
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

  Future<void> _syncOtherRoutine({
    required List<String> rawRoutines,
    required Map<String, List<String>> rawHabitsByRoutine,
    required Map<String, List<String>> rawFavoritesByRoutine,
    required List<String> allHabits,
  }) async {
    final customRoutines = rawRoutines
        .where((routine) => !_isOtherRoutine(routine))
        .toList(growable: false);

    final unassignedHabits =
        _computeUnassignedHabits(allHabits, rawHabitsByRoutine);

    final currentOtherHabits =
        List<String>.from(rawHabitsByRoutine[_otherRoutineName] ?? const []);
    final currentOtherFavorites =
        List<String>.from(rawFavoritesByRoutine[_otherRoutineName] ?? const []);

    final desiredRoutines = <String>[
      ...customRoutines,
      if (unassignedHabits.isNotEmpty) _otherRoutineName,
    ];

    final desiredOtherFavorites = currentOtherFavorites
        .where((favorite) => _containsText(unassignedHabits, favorite))
        .toList(growable: false);

    final routinesChanged = !_sameStringList(rawRoutines, desiredRoutines);
    final habitsChanged =
        !_sameStringList(currentOtherHabits, unassignedHabits);
    final favoritesChanged =
        !_sameStringList(currentOtherFavorites, desiredOtherFavorites);

    final otherExistsInMap = rawHabitsByRoutine.keys.any(_isOtherRoutine) ||
        rawFavoritesByRoutine.keys.any(_isOtherRoutine);

    final shouldDeleteOther = unassignedHabits.isEmpty && otherExistsInMap;

    if (!routinesChanged &&
        !habitsChanged &&
        !favoritesChanged &&
        !shouldDeleteOther) {
      return;
    }

    try {
      if (unassignedHabits.isEmpty) {
        await _atomicHabitsRef.set(
          {
            'routines': desiredRoutines,
            'habits_by_routine.$_otherRoutineName': FieldValue.delete(),
            'favorites_by_routine.$_otherRoutineName': FieldValue.delete(),
          },
          SetOptions(merge: true),
        );
      } else {
        await _atomicHabitsRef.set(
          {
            'routines': desiredRoutines,
            'habits_by_routine.$_otherRoutineName': unassignedHabits,
            'favorites_by_routine.$_otherRoutineName': desiredOtherFavorites,
          },
          SetOptions(merge: true),
        );
      }
    } catch (_) {
      // Ignore background sync errors; UI already renders from local computed state.
    }
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

  int get _routineCount => _routines.length;

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

  int get _unassignedHabitCount =>
      _habitsByRoutine[_otherRoutineName]?.length ?? 0;

  void _openRoutine(String? routine) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AtomicHabitsScreen(routine: routine),
      ),
    );
  }

  Future<void> _addRoutine() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _RoutineNameDialog(),
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

    try {
      final customRoutines =
          _routines.where((routine) => !_isOtherRoutine(routine)).toList();
      final updatedRoutines = _dedupeStrings([...customRoutines, routineName]);

      await _atomicHabitsRef.set(
        {
          'routines': updatedRoutines,
          'habits_by_routine.$routineName': [],
          'favorites_by_routine.$routineName': [],
        },
        SetOptions(merge: true),
      );

      _snack('Routine "$routineName" added');
    } catch (e) {
      _snack('Could not add routine.', error: true);
    }
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
          'Are you sure you want to delete "$routine"? '
          'This removes its routine grouping only.',
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

    try {
      final updatedRoutines = _routines
          .where((item) => !_sameText(item, routine) && !_isOtherRoutine(item))
          .toList();

      await _atomicHabitsRef.set(
        {
          'routines': updatedRoutines,
          'habits_by_routine.$routine': FieldValue.delete(),
          'favorites_by_routine.$routine': FieldValue.delete(),
        },
        SetOptions(merge: true),
      );

      _snack('Routine "$routine" deleted');
    } catch (e) {
      _snack('Could not delete routine.', error: true);
    }
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

    try {
      await _atomicHabitsRef.set(
        {
          'habits': updatedGlobalHabits,
          'habits_by_routine.$routine': cleanedSelection,
          'favorites_by_routine.$routine': cleanedFavorites,
        },
        SetOptions(merge: true),
      );

      _snack('Updated "$routine"');
    } catch (e) {
      _snack('Could not update routine habits.', error: true);
    }
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
            icon: const Icon(Icons.add_rounded),
            onPressed: _addRoutine,
          ),
        ],
      ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _addRoutine,
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
        ],
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark) {
    final surface = isDark
        ? const Color(0xFF15171C).withOpacity(0.92)
        : Colors.white.withOpacity(0.92);

    final subtitleColor = isDark ? Colors.white70 : Colors.black54;

    return Container(
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
          Icon(
            Icons.auto_awesome_rounded,
            size: 28,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Organize habits into routines',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _routines.isEmpty
                ? 'Create routines like Morning, Evening, Workout, or Work to keep your habits grouped cleanly.'
                : _unassignedHabitCount > 0
                    ? 'Tap a routine to see only its habits. "$_otherRoutineName" appears automatically when habits are still unassigned.'
                    : 'Tap a routine to see only its habits. Use the menu on each card to manage or delete it.',
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
                label: '$_routineCount routines',
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
        ],
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
                'You can still browse all habits right now, or create a routine to group a smaller subset.',
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
      Icons.restaurant_menu_rounded,
      Icons.work_outline_rounded,
      Icons.directions_run_rounded,
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

    return Material(
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
                        : '$habitCount not assigned yet'
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
                children: [
                  _RoutineMiniPill(
                    icon: Icons.check_rounded,
                    label: '$habitCount',
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _RoutineMiniPill(
                    icon: isOther ? Icons.auto_awesome_rounded : Icons.star_rounded,
                    label: isOther ? 'Auto' : '$favoriteCount',
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
    )
        .animate()
        .fade(delay: (70 * index).ms)
        .slideY(begin: 0.08, delay: (70 * index).ms, duration: 280.ms);
  }
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
      ),
    );
  }
}

class _RoutineNameDialog extends StatefulWidget {
  const _RoutineNameDialog();

  @override
  State<_RoutineNameDialog> createState() => _RoutineNameDialogState();
}

class _RoutineNameDialogState extends State<_RoutineNameDialog> {
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
      title: const Text('Add routine'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Routine name',
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
        textCapitalization: TextCapitalization.words,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: hasText ? _submit : null,
          child: const Text('Add'),
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
  final TextEditingController _customHabitController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedHabits = _dedupeStrings(widget.currentHabits);
    _availableHabits = _dedupeStrings([
      ...widget.availableHabits,
      ...widget.currentHabits,
    ]);
  }

  @override
  void dispose() {
    _customHabitController.dispose();
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

  void _addCustomHabit() {
    final value = _customHabitController.text.trim();
    if (value.isEmpty) return;

    setState(() {
      if (!_containsText(_availableHabits, value)) {
        _availableHabits.add(value);
      }
      if (!_containsText(_selectedHabits, value)) {
        _selectedHabits.add(value);
      }

      _availableHabits = _dedupeStrings(_availableHabits);
      _selectedHabits = _dedupeStrings(_selectedHabits);
      _customHabitController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderedHabits = _dedupeStrings([
      ..._selectedHabits,
      ..._availableHabits.where(
        (habit) => !_containsText(_selectedHabits, habit),
      ),
    ]);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      title: Text('Manage habits • ${widget.routine}'),
      content: SizedBox(
        width: double.maxFinite,
        height: 470,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedHabits.isNotEmpty) ...[
              Text(
                'Selected',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
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
                }).toList(),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              'All habits',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.65),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  itemCount: orderedHabits.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, index) {
                    final habit = orderedHabits[index];
                    final selected = _containsText(_selectedHabits, habit);

                    return CheckboxListTile(
                      value: selected,
                      onChanged: (_) => _toggleHabit(habit),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                      title: Text(
                        habit,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Add custom habit',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customHabitController,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _addCustomHabit(),
                    decoration: const InputDecoration(
                      hintText: 'New habit name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addCustomHabit,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
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
          child: const Text('Save'),
        ),
      ],
    );
  }
}