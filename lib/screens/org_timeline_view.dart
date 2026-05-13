import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

enum _TimelineZoom {
  yearly,
  quarterly,
  monthly,
  biweekly,
  weekly,
  daily,
}

extension on _TimelineZoom {
  String get label => switch (this) {
        _TimelineZoom.yearly => 'Yearly',
        _TimelineZoom.quarterly => 'Quarterly',
        _TimelineZoom.monthly => 'Monthly',
        _TimelineZoom.biweekly => 'Biweekly',
        _TimelineZoom.weekly => 'Weekly',
        _TimelineZoom.daily => 'Daily',
      };
}


class _GrantDaySegment {
  _GrantDaySegment({
    required this.color,
    required this.continuesLeft,
    required this.continuesRight,
  });

  final Color color;
  final bool continuesLeft;
  final bool continuesRight;
}

class _GrantRange {
  _GrantRange({
    required this.id,
    required this.start,
    required this.end,
    required this.color,
    required this.title,
    required this.proposalStatus,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final Color color;
  final String title;
  final String proposalStatus;
}


class _DeliverableMarkerEvent {
  const _DeliverableMarkerEvent({required this.title, required this.color});

  final String title;
  final Color color;
}

class OrgTimelineView extends StatefulWidget {
  const OrgTimelineView({
    super.key,
    required this.organizationId,
    required this.organizationName,
  });

  final String organizationId;
  final String organizationName;

  @override
  State<OrgTimelineView> createState() => _OrgTimelineViewState();
}

class _TimelineEvent {
  _TimelineEvent({
    required this.title,
    required this.subtitle,
    required this.sortKey,
    required this.color,
    required this.icon,
    this.isDeliverable = false,
  });

  final String title;
  final String subtitle;
  final int sortKey;
  final Color color;
  final IconData icon;
  final bool isDeliverable;
}

class _OrgTimelineViewState extends State<OrgTimelineView> {
  final _supabase = Supabase.instance.client;
  late Future<_TimelineData> _future;
  late DateTime _focused;
  late DateTime _selected;
  _TimelineZoom _zoom = _TimelineZoom.monthly;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  static const List<Color> _grantPalette = [
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFF00695C),
    Color(0xFFC62828),
    Color(0xFFEF6C00),
    Color(0xFF2E7D32),
    Color(0xFFAD1457),
    Color(0xFF00838F),
    Color(0xFF4527A0),
    Color(0xFF558B2F),
    Color(0xFFD84315),
    Color(0xFF283593),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focused = DateTime(now.year, now.month, now.day);
    _selected = _focused;
    _future = _load();
  }

  @override
  void didUpdateWidget(OrgTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId) {
      _future = _load();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<_TimelineData> _load() async {
    final grantRows = await _supabase
        .from('grants')
        .select()
        .eq('organization_id', widget.organizationId)
        .order('start_date');
    final grants = List<Map<String, dynamic>>.from(grantRows);
    if (grants.isEmpty) {
      return _TimelineData(grants: [], deliverables: []);
    }
    final grantIds = grants.map((g) => g['id'] as String).toList();
    final orFilter = grantIds.map((id) => 'grant_id.eq.$id').join(',');
    final delRows =
        await _supabase.from('deliverables').select().or(orFilter).order('due_date');
    final deliverables = List<Map<String, dynamic>>.from(delRows);
    return _TimelineData(grants: grants, deliverables: deliverables);
  }

  static Color _colorForGrantId(String id) {
    var h = 0;
    for (final u in id.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return _grantPalette[h % _grantPalette.length];
  }

  static DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _mondayOfWeek(DateTime d) {
    final n = _normalize(d);
    return n.subtract(Duration(days: n.weekday - DateTime.monday));
  }

  static bool _sameCalendarWeek(DateTime a, DateTime b) {
    return _mondayOfWeek(a) == _mondayOfWeek(b);
  }

  static bool _dayInRange(DateTime day, DateTime start, DateTime end) {
    final d = _normalize(day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  static bool _continuesLeft(DateTime day, DateTime start, DateTime end) {
    final prev = _normalize(day).subtract(const Duration(days: 1));
    return _dayInRange(prev, start, end) && _sameCalendarWeek(day, prev);
  }

  static bool _continuesRight(DateTime day, DateTime start, DateTime end) {
    final next = _normalize(day).add(const Duration(days: 1));
    return _dayInRange(next, start, end) && _sameCalendarWeek(day, next);
  }

  void _setZoom(_TimelineZoom? z) {
    if (z == null) return;
    setState(() {
      _zoom = z;
      switch (z) {
        case _TimelineZoom.monthly:
          _calendarFormat = CalendarFormat.month;
        case _TimelineZoom.biweekly:
          _calendarFormat = CalendarFormat.twoWeeks;
        case _TimelineZoom.weekly:
          _calendarFormat = CalendarFormat.week;
        case _TimelineZoom.yearly:
        case _TimelineZoom.quarterly:
        case _TimelineZoom.daily:
          break;
      }
    });
  }

  void _shiftYear(int delta) {
    setState(() {
      final y = _focused.year + delta;
      final lastDay = DateTime(y, _focused.month + 1, 0).day;
      final d = _focused.day.clamp(1, lastDay);
      _focused = DateTime(y, _focused.month, d);
    });
  }

  void _shiftQuarter(int delta) {
    setState(() {
      var m = _focused.month - 1 + delta * 3;
      var y = _focused.year;
      while (m < 0) {
        m += 12;
        y--;
      }
      while (m > 11) {
        m -= 12;
        y++;
      }
      final month = m + 1;
      final lastDay = DateTime(y, month + 1, 0).day;
      final d = _focused.day.clamp(1, lastDay);
      _focused = DateTime(y, month, d);
    });
  }

  void _shiftDay(int delta) {
    setState(() {
      _selected = _normalize(_selected).add(Duration(days: delta));
      _focused = _selected;
    });
  }

  int _quarterIndex() => (_focused.month - 1) ~/ 3;

  int _quarterStartMonth() => _quarterIndex() * 3 + 1;

  Widget _zoomDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'View',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<_TimelineZoom>(
            value: _zoom,
            isExpanded: true,
            items: _TimelineZoom.values
                .map(
                  (z) => DropdownMenuItem(
                    value: z,
                    child: Text(z.label),
                  ),
                )
                .toList(),
            onChanged: _setZoom,
          ),
        ),
      ),
    );
  }

  Widget _periodNav({
    required String title,
    required VoidCallback onPrev,
    required VoidCallback onNext,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }

  Widget _timelineDayCell({
    required CalendarStyle calStyle,
    required String dayText,
    required Decoration decoration,
    required TextStyle textStyle,
    required DateTime day,
    required _TimelineData data,
  }) {
    final segments = data.grantSegmentsForDay(day);
    final marginH = calStyle.cellMargin.horizontal;
    final bleed = marginH / 2;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: calStyle.cellMargin,
      padding: calStyle.cellPadding,
      decoration: decoration,
      clipBehavior: Clip.none,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Text(dayText, style: textStyle),
          if (segments.isNotEmpty)
            Positioned(
              left: -bleed,
              right: -bleed,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in segments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _GrantThroughStripe(segment: s),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  CalendarBuilders<_DeliverableMarkerEvent> _tableCalendarBuilders(
    CalendarStyle calStyle,
    _TimelineData data,
  ) {
    return CalendarBuilders<_DeliverableMarkerEvent>(
      selectedBuilder: (context, day, focusedDay) {
        return _timelineDayCell(
          calStyle: calStyle,
          dayText: '${day.day}',
          decoration: calStyle.selectedDecoration,
          textStyle: calStyle.selectedTextStyle,
          day: day,
          data: data,
        );
      },
      todayBuilder: (context, day, focusedDay) {
        return _timelineDayCell(
          calStyle: calStyle,
          dayText: '${day.day}',
          decoration: calStyle.todayDecoration,
          textStyle: calStyle.todayTextStyle,
          day: day,
          data: data,
        );
      },
      outsideBuilder: (context, day, focusedDay) {
        final isWeekend =
            day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
        return _timelineDayCell(
          calStyle: calStyle,
          dayText: '${day.day}',
          decoration: isWeekend ? calStyle.weekendDecoration : calStyle.outsideDecoration,
          textStyle: isWeekend ? calStyle.weekendTextStyle : calStyle.outsideTextStyle,
          day: day,
          data: data,
        );
      },
      defaultBuilder: (context, day, focusedDay) {
        final isWeekend =
            day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
        return _timelineDayCell(
          calStyle: calStyle,
          dayText: '${day.day}',
          decoration: isWeekend ? calStyle.weekendDecoration : calStyle.defaultDecoration,
          textStyle: isWeekend ? calStyle.weekendTextStyle : calStyle.defaultTextStyle,
          day: day,
          data: data,
        );
      },
      markerBuilder: (context, day, events) {
        if (events.isEmpty) return null;
        return Positioned(
          bottom: 2,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: events.take(calStyle.markersMaxCount).map((e) {
              return Container(
                width: calStyle.markerSize ?? 6,
                height: calStyle.markerSize ?? 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: e.color,
                  shape: BoxShape.circle,
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

 
  static double _tableCalendarMinHeight(CalendarFormat format) {
    const header = 56.0;
    const dow = 22.0;
    const rowH = 66.0;
    final rows = switch (format) {
      CalendarFormat.month => 6,
      CalendarFormat.twoWeeks => 2,
      CalendarFormat.week => 1,
    };
    return header + dow + rows * rowH + 24;
  }

  Widget _buildTableCalendar(CalendarStyle calStyle, _TimelineData data) {
    return TableCalendar<_DeliverableMarkerEvent>(
      firstDay: DateTime.utc(2000, 1, 1),
      lastDay: DateTime.utc(2100, 12, 31),
      focusedDay: _focused,
      calendarFormat: _calendarFormat,
      availableCalendarFormats: const {
        CalendarFormat.month: 'Month',
        CalendarFormat.twoWeeks: 'Biweekly',
        CalendarFormat.week: 'Week',
      },
      shouldFillViewport: true,
      rowHeight: 66,
      daysOfWeekHeight: 22,
      selectedDayPredicate: (d) => isSameDay(_selected, d),
      onDaySelected: (sel, foc) {
        setState(() {
          _selected = sel;
          _focused = foc;
        });
      },
      onPageChanged: (foc) => setState(() => _focused = foc),
      eventLoader: (day) => data.deliverableMarkersOn(_normalize(day)),
      calendarStyle: calStyle,
      startingDayOfWeek: StartingDayOfWeek.monday,
      headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
      calendarBuilders: _tableCalendarBuilders(calStyle, data),
    );
  }

 
  Widget _buildScrollableTableCalendar(CalendarStyle calStyle, _TimelineData data) {
    final h = _tableCalendarMinHeight(_calendarFormat);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: SizedBox(
              height: h,
              width: constraints.maxWidth,
              child: _buildTableCalendar(calStyle, data),
            ),
          ),
        );
      },
    );
  }

  void _onMiniDayTap(DateTime day) {
    setState(() {
      _selected = _normalize(day);
      _focused = _selected;
    });
  }

  Widget _buildYearlyView(_TimelineData data) {
    final y = _focused.year;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _periodNav(
          title: '$y',
          onPrev: () => _shiftYear(-1),
          onNext: () => _shiftYear(1),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.92,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 12,
            itemBuilder: (context, i) {
              final month = i + 1;
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _focused = DateTime(y, month, 1);
                      _zoom = _TimelineZoom.monthly;
                      _calendarFormat = CalendarFormat.month;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          DateFormat.MMM().format(DateTime(y, month)),
                          style: Theme.of(context).textTheme.titleSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: _MiniMonthGrid(
                            year: y,
                            month: month,
                            data: data,
                            selected: _selected,
                            onDayTap: _onMiniDayTap,
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
      ],
    );
  }

  Widget _buildQuarterlyView(_TimelineData data) {
    final y = _focused.year;
    final m0 = _quarterStartMonth();
    final q = _quarterIndex() + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _periodNav(
          title: 'Q$q $y',
          onPrev: () => _shiftQuarter(-1),
          onNext: () => _shiftQuarter(1),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final month = m0 + i;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        DateFormat.yMMMM().format(DateTime(y, month)),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 200,
                        child: _MiniMonthGrid(
                          year: y,
                          month: month,
                          data: data,
                          selected: _selected,
                          onDayTap: _onMiniDayTap,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDailyView() {
    final d = _normalize(_selected);
    final label = DateFormat.yMMMMEEEEd().format(d);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _periodNav(
          title: label,
          onPrev: () => _shiftDay(-1),
          onNext: () => _shiftDay(1),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Details for this day appear in the list below.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventList(_TimelineData data) {
    final day = _normalize(_selected);
    final items = [...data.eventsOn(day)]
      ..sort((a, b) {
        final c = a.sortKey.compareTo(b.sortKey);
        if (c != 0) return c;
        return a.title.compareTo(b.title);
      });
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('Nothing on this day.')),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        return Card(
          child: ListTile(
            leading: Icon(e.icon, color: e.color),
            title: Text(e.title),
            subtitle: Text(e.subtitle),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final calStyle = CalendarStyle(
      outsideDaysVisible: false,
      markersMaxCount: 8,
      markerSize: 6,
      canMarkersOverflow: true,
      markersAutoAligned: false,
      markersOffset: const PositionedOffset(bottom: 2),
      cellMargin: const EdgeInsets.all(6),
    );

    return FutureBuilder<_TimelineData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('${snap.error}'));
        }
        final data = snap.data!;

        Widget calendarPane;
        switch (_zoom) {
          case _TimelineZoom.yearly:
            calendarPane = _buildYearlyView(data);
          case _TimelineZoom.quarterly:
            calendarPane = _buildQuarterlyView(data);
          case _TimelineZoom.daily:
            calendarPane = _buildDailyView();
          case _TimelineZoom.monthly:
          case _TimelineZoom.biweekly:
          case _TimelineZoom.weekly:
            calendarPane = _buildScrollableTableCalendar(calStyle, data);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                widget.organizationName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Grants appear as colored bars; deliverables as dots matching the grant color.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            _zoomDropdown(),
            Expanded(
              flex: 5,
              child: calendarPane,
            ),
            const Divider(height: 1),
            Expanded(
              flex: 4,
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _buildEventList(data),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GrantThroughStripe extends StatelessWidget {
  const _GrantThroughStripe({required this.segment});

  final _GrantDaySegment segment;

  @override
  Widget build(BuildContext context) {
    const r = 3.0;
    return Container(
      height: 5,
      decoration: BoxDecoration(
        color: segment.color,
        borderRadius: BorderRadius.horizontal(
          left: segment.continuesLeft ? Radius.zero : const Radius.circular(r),
          right: segment.continuesRight ? Radius.zero : const Radius.circular(r),
        ),
      ),
    );
  }
}


class _MiniMonthGrid extends StatelessWidget {
  const _MiniMonthGrid({
    required this.year,
    required this.month,
    required this.data,
    required this.selected,
    required this.onDayTap,
  });

  final int year;
  final int month;
  final _TimelineData data;
  final DateTime selected;
  final void Function(DateTime day) onDayTap;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leading = (first.weekday - DateTime.monday + 7) % 7;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = totalCells ~/ 7;
        final cellW = constraints.maxWidth / 7;
        final cellH = rows > 0 ? constraints.maxHeight / rows : constraints.maxHeight;
        final side = cellW < cellH ? cellW : cellH;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 1,
            crossAxisSpacing: 1,
            mainAxisExtent: side,
          ),
          itemCount: totalCells,
          itemBuilder: (context, i) {
            if (i < leading || i >= leading + daysInMonth) {
              return const SizedBox.shrink();
            }
            final dayNum = i - leading + 1;
            final day = DateTime(year, month, dayNum);
            final isSel = isSameDay(selected, day);
            final isToday = isSameDay(DateTime.now(), day);
            final segs = data.grantSegmentsForDay(day);
            final del = data.deliverableMarkersOn(day);

            return GestureDetector(
              onTap: () => onDayTap(day),
              behavior: HitTestBehavior.opaque,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSel
                        ? Theme.of(context).colorScheme.primary
                        : isToday
                            ? Theme.of(context).colorScheme.tertiary
                            : Colors.transparent,
                    width: isSel ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$dayNum',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            fontWeight: isToday ? FontWeight.bold : null,
                          ),
                    ),
                    if (segs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: segs
                              .take(2)
                              .map(
                                (s) => Container(
                                  width: 6,
                                  height: 2,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: s.color,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    if (del.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: del.take(3).map((e) {
                            return Container(
                              width: 3,
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: e.color,
                                shape: BoxShape.circle,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TimelineData {
  _TimelineData({required this.grants, required this.deliverables}) {
    _buildRangesAndIndex();
  }

  final List<Map<String, dynamic>> grants;
  final List<Map<String, dynamic>> deliverables;

  final List<_GrantRange> _grantRanges = [];
  final Map<DateTime, List<_TimelineEvent>> _byDay = {};
  final Map<String, Color> _grantColorById = {};

  List<_TimelineEvent> eventsOn(DateTime day) =>
      List<_TimelineEvent>.from(_byDay[_normalize(day)] ?? const []);

  List<_DeliverableMarkerEvent> deliverableMarkersOn(DateTime day) {
    final list = _byDay[_normalize(day)] ?? const [];
    return list
        .where((e) => e.isDeliverable)
        .map((e) => _DeliverableMarkerEvent(title: e.title, color: e.color))
        .toList();
  }

  List<_GrantDaySegment> grantSegmentsForDay(DateTime day) {
    final d = _normalize(day);
    final segments = <_GrantDaySegment>[];
    for (final r in _grantRanges) {
      if (d.isBefore(r.start) || d.isAfter(r.end)) continue;
      segments.add(
        _GrantDaySegment(
          color: r.color,
          continuesLeft: _OrgTimelineViewState._continuesLeft(d, r.start, r.end),
          continuesRight: _OrgTimelineViewState._continuesRight(d, r.start, r.end),
        ),
      );
    }
    return segments;
  }

  void _buildRangesAndIndex() {
    _byDay.clear();
    _grantRanges.clear();
    _grantColorById.clear();

    for (final g in grants) {
      final id = g['id'] as String;
      _grantColorById[id] = _OrgTimelineViewState._colorForGrantId(id);
    }

    final grantTitle = <String, String>{
      for (final g in grants) g['id'] as String: g['title'] as String? ?? 'Grant',
    };

    for (final g in grants) {
      final id = g['id'] as String;
      final start = _parseDate(g['start_date']);
      if (start == null) continue;
      final end = _parseDate(g['end_date']) ?? start;
      final nStart = _normalize(start);
      final nEnd = _normalize(end);
      final title = g['title'] as String? ?? 'Grant';
      final ps = g['proposal_status'] as String? ?? 'approved';
      final color = _grantColorById[id]!;

      _grantRanges.add(
        _GrantRange(
          id: id,
          start: nStart,
          end: nEnd,
          color: color,
          title: title,
          proposalStatus: ps,
        ),
      );

      var cursor = nStart;
      while (!cursor.isAfter(nEnd)) {
        _add(
          cursor,
          _TimelineEvent(
            title: title,
            subtitle: 'Grant ($ps)',
            sortKey: 0,
            color: color,
            icon: Icons.account_balance,
          ),
        );
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    _grantRanges.sort((a, b) => a.id.compareTo(b.id));

    for (final d in deliverables) {
      final due = _parseDate(d['due_date']);
      if (due == null) continue;
      final gid = d['grant_id'] as String?;
      final gTitle = gid == null ? 'Grant' : (grantTitle[gid] ?? 'Grant');
      final ps = d['proposal_status'] as String? ?? 'approved';
      final color = gid != null ? (_grantColorById[gid] ?? Colors.blueGrey) : Colors.blueGrey;

      _add(
        _normalize(due),
        _TimelineEvent(
          title: d['title'] as String? ?? 'Deliverable',
          subtitle: '$gTitle · due · $ps',
          sortKey: 1,
          color: color,
          icon: Icons.task_alt,
          isDeliverable: true,
        ),
      );
    }
  }

  void _add(DateTime day, _TimelineEvent e) {
    _byDay.putIfAbsent(_normalize(day), () => []).add(e);
  }

  static DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().split('T').first;
    return DateTime.tryParse(s);
  }
}
