import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets.dart';

/// Human-in-the-loop queue: low-confidence cases wait here for an agronomist.
class AgronomistScreen extends StatefulWidget {
  const AgronomistScreen({super.key});

  @override
  State<AgronomistScreen> createState() => _AgronomistScreenState();
}

class _AgronomistScreenState extends State<AgronomistScreen> {
  List<Diagnosis> _queue = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = await app.api.agronomistQueue(app.language);
      if (mounted) setState(() => _queue = q);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(Diagnosis dx) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReviewSheet(dx: dx),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.watch<AppState>();
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.agronomistQueue),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: _error != null
          ? ErrorRetry(message: _error!, onRetry: _load)
          : _loading && _queue.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _queue.isEmpty
                  ? EmptyState(icon: Icons.task_alt, message: l.queueEmpty)
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(l.pendingCases(_queue.length), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        for (final dx in _queue)
                          Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  CircleAvatar(
                                    backgroundColor: RiskColors.moderate.withValues(alpha: 0.15),
                                    child: const Icon(Icons.hourglass_top, color: RiskColors.high),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('${dx.diseaseName} · ${percent(dx.confidence)}',
                                          style: const TextStyle(fontWeight: FontWeight.w700)),
                                      Text(
                                        '${app.catalog.cropName(dx.crop)} · ${levelLabel(l, dx.severity)} · ${shortDate(dx.createdAt, app.language)}',
                                        style: t.textTheme.bodySmall,
                                      ),
                                    ]),
                                  ),
                                ]),
                                const SizedBox(height: 8),
                                Text(dx.explanation, style: t.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.tonalIcon(
                                    onPressed: () => _review(dx),
                                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                                    label: Text(l.reviewCase),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                      ],
                    ),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.dx});
  final Diagnosis dx;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _reviewer = TextEditingController();
  final _notes = TextEditingController();
  late String _disease = widget.dx.diseaseId;
  late String _severity = widget.dx.severity == 'none' ? 'low' : widget.dx.severity;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reviewer.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    if (_reviewer.text.trim().isEmpty) {
      setState(() => _error = l.requiredField);
      return;
    }
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.api.submitReview(
        diagnosisId: widget.dx.id,
        reviewer: _reviewer.text.trim(),
        diseaseId: _disease,
        severity: _severity,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        lang: app.language,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    final diseases = app.catalog.diseases.where((d) => d.crop == widget.dx.crop).toList();
    final options = [
      for (final d in diseases) DropdownMenuItem(value: d.id, child: Text(d.name)),
      DropdownMenuItem(value: 'healthy', child: Text(l.healthy)),
    ];
    if (!options.any((o) => o.value == _disease)) _disease = options.first.value!;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.reviewCase, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(widget.dx.explanation, style: Theme.of(context).textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 16),
        TextField(controller: _reviewer, decoration: InputDecoration(labelText: l.reviewer, prefixIcon: const Icon(Icons.badge_outlined))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _disease,
          items: options,
          onChanged: (v) => setState(() => _disease = v ?? _disease),
          decoration: InputDecoration(labelText: l.resultTitle),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _severity,
          items: [for (final s in const ['low', 'moderate', 'high', 'severe']) DropdownMenuItem(value: s, child: Text(levelLabel(l, s)))],
          onChanged: (v) => setState(() => _severity = v ?? _severity),
          decoration: InputDecoration(labelText: l.severity),
        ),
        const SizedBox(height: 12),
        TextField(controller: _notes, maxLines: 2, decoration: InputDecoration(labelText: l.notes)),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.verified_outlined),
          label: Text(l.submitReview),
        ),
      ]),
    );
  }
}
