import 'package:flutter/material.dart';

/// GitHub-style contribution grid split into ~6-month pages.
///
/// Renders the trailing 365 days in chunks of weeks (default: two ~26-week
/// pages), navigated with prev/next arrows. Cells are sized to fit the
/// available width so there is no horizontal scrolling.
///
/// Callers supply the per-day counts (and optionally categories) plus a color
/// resolver so the same grid can render category colors (dashboard) or
/// count-intensity colors (habit heatmaps).
class ChunkedContributionGrid extends StatefulWidget {
  final Map<DateTime, int> counts;
  final Map<DateTime, String> categories;
  final Color Function(DateTime day, int count, String? category) colorFor;
  final String? Function(DateTime day)? tooltipFor;

  const ChunkedContributionGrid({
    super.key,
    required this.counts,
    this.categories = const <DateTime, String>{},
    required this.colorFor,
    this.tooltipFor,
  });

  @override
  State<ChunkedContributionGrid> createState() =>
      _ChunkedContributionGridState();
}

class _HeatmapChunk {
  final int startWeek;
  final int weekCount;
  final DateTime startDate;
  final DateTime endDate;

  const _HeatmapChunk({
    required this.startWeek,
    required this.weekCount,
    required this.startDate,
    required this.endDate,
  });
}

class _ChunkedContributionGridState extends State<ChunkedContributionGrid> {
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

  static const double _gap = 2;
  static const double _monthLabelHeight = 16;
  static const double _monthLabelGap = 4;
  static const double _minCell = 6;
  static const double _maxCell = 16;

  /// Below this column pitch the grid is unreadable and is not rendered.
  static const double _minReadableColumn = 5;

  late final DateTime _today;
  late final DateTime _windowStart;
  late final DateTime _gridStart;
  late final List<bool> _showLabelByWeek;
  late final List<_HeatmapChunk> _chunks;
  late int _pageIndex;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _windowStart = _today.subtract(const Duration(days: 364));
    _gridStart = _windowStart.subtract(
      Duration(days: _windowStart.weekday % 7),
    );

    final totalDays = _today.difference(_gridStart).inDays + 1;
    final totalWeeks = (totalDays / 7).ceil();
    final chunkWeeks = (totalWeeks / 2).ceil();

    _showLabelByWeek = List<bool>.filled(totalWeeks, false);
    int? lastMonth;
    for (int week = 0; week < totalWeeks; week++) {
      final date = _gridStart.add(Duration(days: week * 7));
      _showLabelByWeek[week] = lastMonth == null || date.month != lastMonth;
      lastMonth = date.month;
    }

    _chunks = <_HeatmapChunk>[];
    for (int start = 0; start < totalWeeks; start += chunkWeeks) {
      final weekCount =
          start + chunkWeeks <= totalWeeks ? chunkWeeks : totalWeeks - start;
      final startDate = _gridStart.add(Duration(days: start * 7));
      var endDate = _gridStart.add(Duration(days: (start + weekCount) * 7 - 1));
      if (endDate.isAfter(_today)) endDate = _today;
      _chunks.add(
        _HeatmapChunk(
          startWeek: start,
          weekCount: weekCount,
          startDate: startDate,
          endDate: endDate,
        ),
      );
    }

    _pageIndex = _chunks.length - 1;
  }

  int get _maxChunkWeeks =>
      _chunks.map((c) => c.weekCount).reduce((a, b) => a > b ? a : b);

  bool get _canGoOlder => _pageIndex > 0;

  bool get _canGoNewer => _pageIndex < _chunks.length - 1;

  void _goOlder() {
    if (_canGoOlder) setState(() => _pageIndex--);
  }

  void _goNewer() {
    if (_canGoNewer) setState(() => _pageIndex++);
  }

  @override
  Widget build(BuildContext context) {
    final chunk = _chunks[_pageIndex];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCols = _maxChunkWeeks;
        final maxWidth = constraints.maxWidth;

        // Transient zero/near-zero-width layouts (route transitions,
        // collapsed viewports) would otherwise force negative cell sizes or
        // unshrinkable nav buttons to overflow. Below the smallest readable
        // grid (~5px columns), render nothing instead.
        if (maxWidth <= 0 ||
            !maxWidth.isFinite ||
            maxWidth < maxCols * _minReadableColumn) {
          return const SizedBox.shrink();
        }

        var cell = (maxWidth / maxCols) - _gap;
        cell = cell.clamp(_minCell, _maxCell);
        var pitch = cell + _gap;

        if (maxCols * pitch > maxWidth) {
          // Narrow container: shrink to fit instead of overflowing.
          pitch = maxWidth / maxCols;
          cell = pitch - _gap;
        }

        final gridWidth = maxCols * pitch;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildNavBar(chunk, isDark),
            const SizedBox(height: 6),
            SizedBox(
              width: gridWidth,
              height: _monthLabelHeight + _monthLabelGap + 7 * pitch,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey(_pageIndex),
                  child: _buildGrid(chunk, pitch, cell, isDark),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNavBar(_HeatmapChunk chunk, bool isDark) {
    final labelColor = isDark ? Colors.white70 : Colors.black54;

    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Older 6 months',
          onPressed: _canGoOlder ? _goOlder : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            _rangeLabel(chunk),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: labelColor,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Newer 6 months',
          onPressed: _canGoNewer ? _goNewer : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  String _rangeLabel(_HeatmapChunk chunk) {
    final start =
        '${_months[chunk.startDate.month - 1]} ${chunk.startDate.year}';
    final end = '${_months[chunk.endDate.month - 1]} ${chunk.endDate.year}';
    return start == end ? start : '$start – $end';
  }

  Widget _buildGrid(
    _HeatmapChunk chunk,
    double pitch,
    double cell,
    bool isDark,
  ) {
    final labelColor = isDark ? Colors.white54 : Colors.black54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _monthLabelHeight,
          width: chunk.weekCount * pitch,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (int week = 0; week < chunk.weekCount; week++)
                if (week == 0 || _showLabelByWeek[chunk.startWeek + week])
                  Positioned(
                    left: week * pitch,
                    top: 0,
                    child: Text(
                      _months[
                          _gridStart
                              .add(Duration(days: (chunk.startWeek + week) * 7))
                              .month -
                          1],
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: labelColor,
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: _monthLabelGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int week = 0; week < chunk.weekCount; week++)
              SizedBox(
                width: pitch,
                height: 7 * pitch,
                child: Column(
                  children: [
                    for (int dayIndex = 0; dayIndex < 7; dayIndex++)
                      SizedBox(
                        width: pitch,
                        height: pitch,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            right: _gap,
                            bottom: _gap,
                          ),
                          child: _buildCell(
                            _gridStart.add(
                              Duration(
                                days: (chunk.startWeek + week) * 7 + dayIndex,
                              ),
                            ),
                            cell,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCell(DateTime day, double size) {
    if (day.isBefore(_windowStart) || day.isAfter(_today)) {
      return SizedBox(width: size, height: size);
    }

    final normalized = DateTime(day.year, day.month, day.day);
    final count = widget.counts[normalized] ?? 0;
    final category = widget.categories[normalized];
    final color = widget.colorFor(day, count, category);

    Widget cell = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );

    final tooltip = widget.tooltipFor?.call(day);
    if (tooltip != null) {
      cell = Tooltip(message: tooltip, child: cell);
    }

    return cell;
  }
}
