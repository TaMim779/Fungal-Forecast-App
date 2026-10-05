import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets.dart';

/// Yield-loss-averted ledger: quantifies the value protected for the farmer and
/// for microfinance / crop-insurance partners (CSV export).
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  LedgerSummary? _summary;
  List<LedgerEntry> _entries = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final farmer = app.farmer;
    if (farmer == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([app.api.ledgerSummary(farmer.id), app.api.ledgerEntries(farmer.id)]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as LedgerSummary;
        _entries = results[1] as List<LedgerEntry>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.watch<AppState>();
    final t = Theme.of(context);
    final farmer = app.farmer;
    final locale = app.language;

    if (farmer == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.ledgerTitle)),
        body: EmptyState(
          icon: Icons.person_outline,
          message: l.registerFirst,
          action: FilledButton(onPressed: () => context.go(Routes.settings), child: Text(l.navSettings)),
        ),
      );
    }

    final s = _summary;
    final sym = s?.currency ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(l.ledgerTitle),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: _error != null
          ? ErrorRetry(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (s != null) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [t.colorScheme.primary, t.colorScheme.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.netValue, style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                        Text('${money(s.netValue, '', locale: locale)} $sym',
                            style: t.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(l.entriesCount(s.entries), style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: StatTile(label: l.lossAverted, value: '${money(s.totalLossAverted, '', locale: locale)} $sym', color: RiskColors.low)),
                      const SizedBox(width: 10),
                      Expanded(child: StatTile(label: l.totalCost, value: '${money(s.totalCost, '', locale: locale)} $sym', color: RiskColors.high)),
                    ]),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: s.entries == 0 ? null : () => launchUrl(app.api.ledgerCsvUri(farmer.id), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.download_outlined),
                      label: Text(l.exportCsv),
                    ),
                    const SizedBox(height: 8),
                    Text(l.partnerNote, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 20),
                  ],
                  if (_loading && s == null) const Center(child: CircularProgressIndicator()),
                  if (!_loading && _entries.isEmpty) EmptyState(icon: Icons.receipt_long_outlined, message: l.noLedger),
                  for (final e in _entries)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.agriculture_outlined)),
                        title: Text(_diseaseName(app, e.diseaseId), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${shortDate(e.appliedOn, locale)} · ${qty(e.fieldSizeHa)} ${l.hectares}\n${e.treatmentId}'),
                        isThreeLine: true,
                        trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('+${money(e.lossAvertedLocal, '', locale: locale)}', style: const TextStyle(color: RiskColors.low, fontWeight: FontWeight.w800)),
                          Text('-${money(e.costLocal, '', locale: locale)}', style: const TextStyle(color: RiskColors.high)),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  String _diseaseName(AppState app, String id) =>
      app.catalog.diseases.where((d) => d.id == id).map((d) => d.name).firstOrNull ?? id;
}
