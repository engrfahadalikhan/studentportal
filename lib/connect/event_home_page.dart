import 'package:flutter/material.dart';

import '../ui/student_portal_shell.dart' show PortalColors;
import 'connect_models.dart' show ConnectIdentity, ConnectNotification;
import 'event_models.dart';
import 'event_repository.dart';
import 'profanity_filter.dart';

/// AUST Event — campus events board shared by students, teachers and admin.
/// Anyone can post (goes to a pending queue), staff approve/reject, and
/// approved events show in everyone's feed. Reached from a tile on every home
/// screen and kept live through Firebase.
class EventHomePage extends StatefulWidget {
  const EventHomePage({super.key, required this.identity});

  final ConnectIdentity identity;

  @override
  State<EventHomePage> createState() => _EventHomePageState();
}

class _EventHomePageState extends State<EventHomePage>
    with SingleTickerProviderStateMixin {
  final _repo = EventRepository.instance;
  late final TabController _tabs;

  ConnectIdentity get _me => widget.identity;
  bool get _canModerate => _me.isStaff; // teacher or admin

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _canModerate ? 4 : 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _repo.sync(_me));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _repo,
      builder: (context, _) {
        final unread = _repo.unreadFor(_me);
        final pending = _repo.pendingEvents.length;
        return Scaffold(
          backgroundColor: PortalColors.pageBackground,
          appBar: AppBar(
            title: const Text('AUST Event'),
            actions: [
              if (_repo.syncing)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => _repo.sync(_me),
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(text: 'Events'),
                const Tab(text: 'Post Event'),
                if (_canModerate)
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Review'),
                        if (pending > 0) ...[
                          const SizedBox(width: 6),
                          _badge(pending, const Color(0xFFB45309)),
                        ],
                      ],
                    ),
                  ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Alerts'),
                      if (unread > 0) ...[
                        const SizedBox(width: 6),
                        _badge(unread, const Color(0xFFB91C1C)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              _FeedTab(me: _me),
              _PostTab(me: _me, onPosted: () => _tabs.animateTo(0)),
              if (_canModerate) _ReviewTab(me: _me),
              _AlertsTab(me: _me),
            ],
          ),
        );
      },
    );
  }

  Widget _badge(int n, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$n',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

// -------- shared poster art (local, no network image) --------
LinearGradient eventPosterGradient(int i) {
  const palettes = <List<Color>>[
    [Color(0xFF1A1A1A), Color(0xFFB8860B)], // black -> gold (brand)
    [Color(0xFF0E7A53), Color(0xFF38B98C)], // green -> mint
    [Color(0xFF4C1D95), Color(0xFF7C3AED)], // violet
    [Color(0xFF9A3412), Color(0xFFF59E0B)], // orange -> amber
    [Color(0xFF0C4A6E), Color(0xFF0EA5E9)], // blue
    [Color(0xFF831843), Color(0xFFDB2777)], // magenta
  ];
  final p = palettes[i % palettes.length];
  return LinearGradient(
    colors: p,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

IconData _deptIcon(String dept) {
  final d = dept.toLowerCase();
  if (d.contains('computer')) return Icons.memory_rounded;
  if (d.contains('software')) return Icons.code_rounded;
  if (d.contains('management')) return Icons.business_center_rounded;
  if (d.contains('material')) return Icons.build_rounded;
  if (d.contains('mlt')) return Icons.medical_services_rounded;
  if (d.contains('pak')) return Icons.flag_rounded;
  if (d.contains('math')) return Icons.functions_rounded;
  if (d.contains('physics')) return Icons.science_rounded;
  if (d.contains('chem')) return Icons.biotech_rounded;
  return Icons.celebration_rounded;
}

Color _eventStatusColor(String s) => switch (s) {
  'approved' => const Color(0xFF047857),
  'rejected' => const Color(0xFFB91C1C),
  _ => const Color(0xFFB45309),
};

// ================================================================= FEED
class _FeedTab extends StatelessWidget {
  const _FeedTab({required this.me});
  final ConnectIdentity me;

  EventRepository get _repo => EventRepository.instance;

  @override
  Widget build(BuildContext context) {
    final events = _repo.approvedEvents;
    return RefreshIndicator(
      onRefresh: () => _repo.sync(me),
      child: events.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Icon(
                  Icons.celebration_outlined,
                  size: 56,
                  color: PortalColors.subtleText,
                ),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'No events yet.\nPost one from the "Post Event" tab.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: PortalColors.subtleText),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: events.length,
              itemBuilder: (_, i) =>
                  _EventCard(event: events[i], me: me, showActions: false),
            ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.me,
    required this.showActions,
  });

  final CampusEvent event;
  final ConnectIdentity me;
  final bool showActions;

  EventRepository get _repo => EventRepository.instance;

  @override
  Widget build(BuildContext context) {
    final past = event.isPast;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // poster header
          Container(
            height: 118,
            width: double.infinity,
            decoration: BoxDecoration(gradient: eventPosterGradient(event.poster)),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _deptIcon(event.department),
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        event.department,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (past)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Past',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.caption,
                  style: const TextStyle(
                    color: PortalColors.textPrimary,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                _iconLine(Icons.calendar_today_rounded,
                    '${event.dateLabel}  •  ${event.timeLabel}'),
                const SizedBox(height: 6),
                _iconLine(Icons.location_on_outlined, event.location),
                const SizedBox(height: 6),
                _iconLine(
                  Icons.person_outline_rounded,
                  'Posted by ${event.byName} (${event.byRole})',
                ),
                if (showActions) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _repo.approveEvent(event, me),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Approve'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF047857),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmReject(context),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!showActions && (me.isAdmin || _isOwner)) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _confirmDelete(context),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Remove'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB91C1C),
                      ),
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

  bool get _isOwner =>
      event.byId.trim().toLowerCase() == me.id.trim().toLowerCase();

  Future<void> _confirmReject(BuildContext context) async {
    final ok = await _confirm(
      context,
      'Reject event?',
      'The poster will be notified it was not approved.',
    );
    if (ok) _repo.rejectEvent(event, me);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await _confirm(
      context,
      'Remove event?',
      'It will be removed from the board on all devices.',
    );
    if (ok) _repo.deleteEvent(event);
  }

  Widget _iconLine(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: PortalColors.subtleText),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: PortalColors.subtleText,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return res == true;
}

// ================================================================= REVIEW
class _ReviewTab extends StatelessWidget {
  const _ReviewTab({required this.me});
  final ConnectIdentity me;

  EventRepository get _repo => EventRepository.instance;

  @override
  Widget build(BuildContext context) {
    final pending = _repo.pendingEvents;
    return RefreshIndicator(
      onRefresh: () => _repo.sync(me),
      child: pending.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Icon(
                  Icons.inbox_outlined,
                  size: 56,
                  color: PortalColors.subtleText,
                ),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'Nothing waiting for review.',
                    style: TextStyle(color: PortalColors.subtleText),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: pending.length,
              itemBuilder: (_, i) =>
                  _EventCard(event: pending[i], me: me, showActions: true),
            ),
    );
  }
}

// ================================================================= POST
class _PostTab extends StatefulWidget {
  const _PostTab({required this.me, required this.onPosted});
  final ConnectIdentity me;
  final VoidCallback onPosted;

  @override
  State<_PostTab> createState() => _PostTabState();
}

class _PostTabState extends State<_PostTab> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _caption = TextEditingController();
  final _location = TextEditingController();
  String _department = eventDepartments.first;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  int _poster = 0;
  bool _busy = false;

  EventRepository get _repo => EventRepository.instance;

  @override
  void dispose() {
    _title.dispose();
    _caption.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Keep the board clean — block obviously abusive text.
    final bad = ProfanityFilter.firstMatch('${_title.text} ${_caption.text}');
    if (bad != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please remove inappropriate word: "$bad"')),
      );
      return;
    }
    setState(() => _busy = true);
    await _repo.postEvent(
      who: widget.me,
      title: _title.text.trim(),
      caption: _caption.text.trim(),
      date: _date,
      minuteOfDay: _time.hour * 60 + _time.minute,
      location: _location.text.trim(),
      department: _department,
      poster: _poster,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.me.isAdmin
              ? 'Event published to the board.'
              : 'Event sent for approval.',
        ),
      ),
    );
    _title.clear();
    _caption.clear();
    _location.clear();
    setState(() {});
    widget.onPosted();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // live poster preview
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: eventPosterGradient(_poster),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(14),
            alignment: Alignment.bottomLeft,
            child: Text(
              _title.text.trim().isEmpty ? 'Event title' : _title.text.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kEventPosterCount,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => setState(() => _poster = i),
                child: Container(
                  width: 52,
                  decoration: BoxDecoration(
                    gradient: eventPosterGradient(i),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _poster == i
                          ? PortalColors.textPrimary
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _title,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Event title',
              prefixIcon: Icon(Icons.title_rounded),
            ),
            onChanged: (_) => setState(() {}),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _caption,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Description',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_rounded),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _location,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Location',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _department,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Department',
              prefixIcon: Icon(Icons.school_outlined),
            ),
            items: [
              for (final d in eventDepartments)
                DropdownMenuItem(value: d, child: Text(d)),
            ],
            onChanged: (v) => setState(() => _department = v ?? _department),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(
                    '${_date.day}/${_date.month}/${_date.year}',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time_rounded, size: 18),
                  label: Text(_time.format(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(widget.me.isAdmin ? 'Publish event' : 'Send for approval'),
          ),
          const SizedBox(height: 10),
          if (!widget.me.isAdmin)
            const Text(
              'Your event will appear on the board once a teacher or admin '
              'approves it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: PortalColors.subtleText, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

// ================================================================= ALERTS
class _AlertsTab extends StatelessWidget {
  const _AlertsTab({required this.me});
  final ConnectIdentity me;

  EventRepository get _repo => EventRepository.instance;

  @override
  Widget build(BuildContext context) {
    final items = _repo.notificationsFor(me);
    return RefreshIndicator(
      onRefresh: () => _repo.sync(me),
      child: items.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Icon(
                  Icons.notifications_none_rounded,
                  size: 56,
                  color: PortalColors.subtleText,
                ),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'No alerts yet.',
                    style: TextStyle(color: PortalColors.subtleText),
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _alertTile(items[i]),
            ),
    );
  }

  Widget _alertTile(ConnectNotification n) => Container(
    decoration: BoxDecoration(
      color: n.unread ? const Color(0xFFFFFBEB) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: n.unread ? const Color(0xFFFDE68A) : PortalColors.cardBorder,
      ),
    ),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: PortalColors.pageBackground,
        child: Icon(
          Icons.celebration_rounded,
          color: _eventStatusColor(n.title.contains('approved')
              ? 'approved'
              : (n.title.contains('not approved') ? 'rejected' : 'pending')),
          size: 20,
        ),
      ),
      title: Text(
        n.title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
      subtitle: Text(n.body),
      trailing: n.unread
          ? const Icon(Icons.circle, size: 10, color: Color(0xFFB91C1C))
          : null,
      onTap: () => _repo.markNotificationRead(n),
    ),
  );
}
