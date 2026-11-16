import 'package:flutter/material.dart';
import '../../services/release_notes_api.dart';

const Color _kBrand = Color(0xFF0066CC);
const Color _kInk = Color(0xFF1A1A2E);
const List<String> _kMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _fmtDate(DateTime d) => '${d.day} ${_kMonths[d.month - 1]} ${d.year}';

/// Admin-only list of what changed in the app and on which date.
class VersionHistoryScreen extends StatefulWidget {
  const VersionHistoryScreen({super.key});

  @override
  State<VersionHistoryScreen> createState() => _VersionHistoryScreenState();
}

class _VersionHistoryScreenState extends State<VersionHistoryScreen> {
  List<ReleaseNote> _notes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notes = await ReleaseNotesApi.list();
      if (mounted) setState(() => _notes = notes);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kBrand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.history, color: _kBrand, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Version History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kInk)),
                Text('What changed in the app, and when',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ]),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final pad = c.maxWidth < 600 ? 16.0 : 24.0;
      return ListView.separated(
        padding: EdgeInsets.all(pad),
        itemCount: _notes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            // the newest entry starts open
            child: _NoteCard(note: _notes[i], initiallyExpanded: i == 0),
          ),
        ),
      );
    });
  }
}

class _NoteCard extends StatelessWidget {
  final ReleaseNote note;
  final bool initiallyExpanded;

  const _NoteCard({required this.note, required this.initiallyExpanded});

  @override
  Widget build(BuildContext context) {
    final live = note.date != null;
    final hasDetails = note.sections.isNotEmpty;

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Pill(
              live ? _fmtDate(note.date!) : 'Not live yet',
              fg: live ? _kBrand : const Color(0xFF9A5B00),
              bg: live ? _kBrand.withValues(alpha: 0.08) : const Color(0xFFFFF1D6),
              icon: live ? Icons.event : Icons.schedule,
            ),
            if (note.area.isNotEmpty) _Pill(note.area, fg: Colors.grey.shade700, bg: Colors.grey.shade100),
          ],
        ),
        const SizedBox(height: 8),
        Text(note.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _kInk)),
        if (note.summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(note.summary, style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade800)),
        ],
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: !hasDetails
          ? Padding(padding: const EdgeInsets.all(16), child: head)
          : Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: initiallyExpanded,
                tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: head,
                children: [for (final s in note.sections) _SectionView(s)],
              ),
            ),
    );
  }
}

class _SectionView extends StatelessWidget {
  final ReleaseSection section;
  const _SectionView(this.section);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.heading,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kInk)),
          const SizedBox(height: 6),
          for (final p in section.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade500, shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(
                    child: Text(p, style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade800)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;
  const _Pill(this.text, {required this.fg, required this.bg, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}
