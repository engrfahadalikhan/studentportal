import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ui/student_portal_shell.dart';
import 'fyp_group_models.dart';
import 'fyp_repository.dart';

const _green = Color(0xFF047857);
const _amber = Color(0xFFB45309);
const _red = Color(0xFFB91C1C);
const _blue = Color(0xFF1D4ED8);

String _clock(DateTime d) => DateFormat('hh:mm a').format(d);

/// The examiner's live viva turn queue.
///
/// Setup: put the groups in calling order + set minutes per group, then start.
/// Running: everyone sees the CURRENT group, the NEXT one and estimated times;
/// entering marks for the current group (Evaluations tab) advances the turn
/// automatically — the "Next turn" button does the same by hand.
class FypVivaPage extends StatefulWidget {
  const FypVivaPage({super.key, required this.examinerName});

  final String examinerName;

  @override
  State<FypVivaPage> createState() => _FypVivaPageState();
}

class _FypVivaPageState extends State<FypVivaPage> {
  FypRepository get _repo => FypRepository.instance;

  // Setup state.
  late List<FypGroup> _order;
  final _minutes = TextEditingController(text: '15');
  final _title = TextEditingController(text: 'Viva');

  @override
  void initState() {
    super.initState();
    _order = _repo.groupsWhereExaminer(widget.examinerName).toList();
  }

  @override
  void dispose() {
    _minutes.dispose();
    _title.dispose();
    super.dispose();
  }

  FypGroup? _groupById(String id) {
    for (final g in _repo.groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Viva turn queue')),
      body: AnimatedBuilder(
        animation: _repo,
        builder: (context, _) {
          // A co-panelist who opens this joins the SAME live queue instead of
          // starting a duplicate one.
          final running = _repo.runningVivaInvolvingExaminer(
            widget.examinerName,
          );
          return running == null ? _setupView() : _runningView(running);
        },
      ),
    );
  }

  // ------------------------------------------------------------- setup
  Widget _setupView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Set the calling order',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 4),
        const Text(
          'Drag the groups into the order you will call them, set the time '
          'per group, then start. Students see the live flow — current turn, '
          'next turn and their estimated time.',
          style: TextStyle(color: PortalColors.subtleText, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            labelText: 'Session title (e.g. FYP-III Viva)',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _minutes,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutes per group',
            prefixIcon: Icon(Icons.timer_outlined),
          ),
        ),
        const SizedBox(height: 14),
        if (_order.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'No groups are assigned to you as examiner yet. The coordinator '
              'assigns examiners/panels first.',
              style: TextStyle(color: PortalColors.subtleText),
            ),
          )
        else
          SizedBox(
            height: (_order.length * 68.0) + 8,
            child: ReorderableListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              itemCount: _order.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final g = _order.removeAt(oldIndex);
                  _order.insert(newIndex, g);
                });
              },
              itemBuilder: (context, i) {
                final g = _order[i];
                return Container(
                  key: ValueKey(g.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PortalColors.cardBorder),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFF1A1A1A),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Color(0xFFE7C955),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    title: Text(
                      g.title.isEmpty ? '(no title)' : g.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      g.members.map((m) => m.rollNo).join(', '),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: const Icon(Icons.drag_handle_rounded),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _order.isEmpty
              ? null
              : () {
                  final mins = int.tryParse(_minutes.text.trim()) ?? 15;
                  _repo.createVivaSession(
                    examinerName: widget.examinerName,
                    title: _title.text,
                    minutesPerGroup: mins,
                    groupIds: [for (final g in _order) g.id],
                  );
                },
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Start viva — first group\'s turn begins'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- running
  Widget _runningView(FypVivaSession s) {
    final current = s.currentGroupId == null
        ? null
        : _groupById(s.currentGroupId!);
    final next = s.nextGroupId == null ? null : _groupById(s.nextGroupId!);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: PortalColors.heroGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.record_voice_over_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${s.title} · ${s.minutesPerGroup} min/group · started '
                  '${_clock(s.startedAt)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (current != null) ...[
          _turnCard(
            label: 'NOW — turn ${s.currentIndex + 1} of ${s.groupIds.length}',
            group: current,
            color: _green,
            big: true,
          ),
          const SizedBox(height: 10),
        ],
        if (next != null) ...[
          _turnCard(label: 'NEXT', group: next, color: _blue),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _green),
              onPressed: () => _repo.advanceViva(s.id),
              icon: const Icon(Icons.skip_next_rounded),
              label: Text(
                s.nextGroupId == null
                    ? 'Marks entered — finish session'
                    : 'Marks entered — next turn',
              ),
            ),
            if (s.nextGroupId != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: _amber),
                onPressed: () => _repo.holdCurrentViva(s.id),
                icon: const Icon(Icons.low_priority_rounded),
                label: const Text('Not ready — send to end'),
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: _red),
              onPressed: () => _repo.finishViva(s.id),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End session'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Entering marks in the Evaluations tab for the CURRENT group also '
          'moves the turn forward automatically.',
          style: TextStyle(fontSize: 11.5, color: PortalColors.subtleText),
        ),
        const SizedBox(height: 14),
        const Text(
          'Full queue',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < s.groupIds.length; i++) _queueRow(s, i),
      ],
    );
  }

  Widget _turnCard({
    required String label,
    required FypGroup group,
    required Color color,
    bool big = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            group.title.isEmpty ? '(no title)' : group.title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: big ? 18 : 14.5,
            ),
          ),
          const SizedBox(height: 4),
          for (final m in group.members)
            Text(
              '•  ${m.rollNo}  ${m.name}',
              style: const TextStyle(fontSize: 12.5),
            ),
        ],
      ),
    );
  }

  Widget _queueRow(FypVivaSession s, int i) {
    final g = _groupById(s.groupIds[i]);
    final done = i < s.currentIndex;
    final isCurrent = i == s.currentIndex;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrent ? _green : PortalColors.cardBorder,
          width: isCurrent ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : isCurrent
                ? Icons.play_circle_fill_rounded
                : Icons.schedule_rounded,
            size: 18,
            color: done
                ? _green
                : isCurrent
                ? _green
                : PortalColors.subtleText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${i + 1}. ${g == null ? s.groupIds[i] : (g.title.isEmpty ? '(no title)' : g.title)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            done ? 'done' : '~${_clock(s.estimatedStartOf(i))}',
            style: TextStyle(
              fontSize: 11.5,
              color: done ? _green : _amber,
              fontWeight: FontWeight.w700,
            ),
          ),
          // Waiting groups (beyond the next one) can be pulled forward.
          if (i > s.currentIndex + 1)
            IconButton(
              tooltip: 'Call this group next',
              visualDensity: VisualDensity.compact,
              onPressed: () => _repo.moveVivaGroupNext(s.id, s.groupIds[i]),
              icon: const Icon(Icons.move_up_rounded, size: 18, color: _blue),
            ),
        ],
      ),
    );
  }
}
