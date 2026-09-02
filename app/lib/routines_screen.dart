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
  List<String> _allHabits = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _habitsSub = _atomicHabitsRef.snapshots().listen(
      (snap) {
        final raw = Map<String, dynamic>.from(snap.data() ?? {});
        _applySnapshot(raw);
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

  /// Reads routine maps from Firestore even if the document is in a mixed
  /// format (nested map or legacy dotted root fields). Read-only: the daily
  /// pipeline owns routines, so nothing here is ever written back.
  Map<String, List<String>> _readRoutineListMapFromRaw({
    required Map<String, dynamic> raw,
    required String rootField,
  }) {
    final out = <String, List<String>>{};

    final nested = raw[rootField];
    if (nested is Map) {
      _stringListMap(nested).forEach((key, value) {
        final routine = key.trim();
        if (routine.isEmpty) return;
        out[routine] = value;
      });
    }

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

  /// Display-only canonicalization: pipeline-owned routines keep their
  /// habits and anything unmapped shows up under "Other". Nothing is
  /// written back — favorites are global and live on the habits screen.
  void _applySnapshot(Map<String, dynamic> raw) {
    if (!mounted) return;

    final rawRoutines = _stringList(raw['routines']);
    final habitsByRoutine =
        _readRoutineListMapFromRaw(raw: raw, rootField: 'habits_by_routine');
    final allHabits = _stringList(raw['habits']);

    final routines = <String>[];
    final displayHabits = <String, List<String>>{};

    for (final routine in rawRoutines) {
      if (_isOtherRoutine(routine)) continue;

      final habitsKey = _matchingRoutineKey(habitsByRoutine, routine);
      final routineHabits = List<String>.from(
        habitsKey == null ? const [] : habitsByRoutine[habitsKey] ?? const [],
      );

      routines.add(routine);
      displayHabits[routine] = routineHabits;
    }

    final unassignedHabits = _computeUnassignedHabits(allHabits, displayHabits);
    if (unassignedHabits.isNotEmpty) {
      displayHabits[_otherRoutineName] = unassignedHabits;
    }

    setState(() {
      _routines = routines;
      _habitsByRoutine = displayHabits;
      _allHabits = List<String>.from(allHabits);
      _loading = false;
    });
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
        ],
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
                      if (_routines.isEmpty && _allHabits.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                            child: _buildEmptyState(isDark),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
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
                'Routines, assigned automatically',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'The daily pipeline groups every habit into a routine for you — nothing to maintain. Tap a routine to browse its habits, or open all habits together.',
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
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openRoutine(null),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text('Open all habits (${_allHabits.length})'),
                ),
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
                'No habits yet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Habits appear automatically once the daily pipeline tags your completed tasks.',
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
                  label: const Text('Open all habits'),
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

    final surface = isDark
        ? const Color(0xFF15171C).withOpacity(0.96)
        : Colors.white.withOpacity(0.97);

    return KeyedSubtree(
      key: ValueKey(
        '$routine|$habitCount|${(_habitsByRoutine[routine] ?? const []).join(",")}',
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
                    if (isOther)
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
