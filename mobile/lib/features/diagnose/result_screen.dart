import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/services/tts_service.dart';
import '../../core/state/app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets.dart';
import '../dealers/dealers_screen.dart';

/// Diagnosis result: disease, voice explanation, 5-day risk, costed plan, actions.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.diagnosisId, this.initial});
  final String diagnosisId;
  final Diagnosis? initial;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  Diagnosis? _dx;
  String? _error;
  bool _logging = false;
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    _dx = widget.initial;
    if (_dx == null) _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final dx = await app.api.getDiagnosis(widget.diagnosisId, app.language);
      if (mounted) setState(() => _dx = dx);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _logTreatment(TreatmentOption option) async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final farmer = app.farmer;
    if (farmer == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.registerFirst)));
      return;
    }
    setState(() => _logging = true);
    try {
      await app.api.addLedgerEntry(farmerId: farmer.id, diagnosisId: _dx!.id, treatmentId: option.treatmentId);
      if (!mounted) return;
      setState(() => _logged = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.treatmentLogged)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final dx = _dx;
    return Scaffold(
      appBar: AppBar(title: Text(l.resultTitle)),
      body: dx == null
          ? (_error != null
              ? ErrorRetry(message: _error!, onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : _ResultBody(
              dx: dx,
              logging: _logging,
              logged: _logged,
              onLog: _logTreatment,
            ),
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.dx, required this.logging, required this.logged, required this.onLog});
  final Diagnosis dx;
  final bool logging;
  final bool logged;
  final ValueChanged<TreatmentOption> onLog;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.watch<AppState>();
    final locale = app.language;
    final plan = dx.plan;
    final fc = dx.forecast;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _HeaderCard(dx: dx),
        const SizedBox(height: 16),
        _VoiceCard(text: dx.explanation, lang: locale),
        if (dx.routedToAgronomist) ...[
          const SizedBox(height: 16),
          Material(
            color: RiskColors.moderate.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              leading: const Icon(Icons.support_agent, color: RiskColors.high),
              title: Text(l.agronomistReview),
            ),
          ),
        ],
        if (!dx.isHealthy && dx.symptoms.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: l.symptoms,
            icon: Icons.search,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dx.symptoms),
              if (dx.pathogen != null) ...[
                const SizedBox(height: 8),
                Text('${l.pathogen}: ${dx.pathogen}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
              ],
              if (dx.alternatives.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(l.alternatives, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(spacing: 8, children: [
                  for (final a in dx.alternatives)
                    Chip(label: Text('${a['disease_name']} · ${percent((a['confidence'] as num?)?.toDouble() ?? 0)}')),
                ]),
              ],
            ]),
          ),
        ],
        if (fc != null) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: l.riskForecast,
            icon: Icons.show_chart,
            trailing: RiskBadge(level: fc.overallLevel),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RiskBars(
                risks: [for (final d in fc.days) d.risk],
                labels: [for (final d in fc.days) shortDay(d.day, locale)],
                height: 80,
              ),
              const SizedBox(height: 12),
              _WeatherStrip(days: fc.days),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.tips_and_updates_outlined, size: 20, color: RiskColors.high),
                const SizedBox(width: 8),
                Expanded(child: Text(fc.action, style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ]),
          ),
        ],
        if (plan != null) ...[
          const SizedBox(height: 16),
          _PlanCard(plan: plan, dx: dx, logging: logging, logged: logged, onLog: onLog),
        ],
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.dx});
  final Diagnosis dx;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context);
    final color = RiskColors.of(dx.isHealthy ? 'low' : dx.riskLevel);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(dx.isHealthy ? Icons.check_circle : Icons.coronavirus, color: Colors.white, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(dx.diseaseName,
                style: t.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _Stat(label: l.confidence, value: percent(dx.confidence)),
          const SizedBox(width: 24),
          _Stat(label: l.severity, value: levelLabel(l, dx.severity)),
          if (dx.forecast != null) ...[
            const SizedBox(width: 24),
            _Stat(label: l.riskForecast, value: levelLabel(l, dx.forecast!.overallLevel)),
          ],
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
      );
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({required this.text, required this.lang});
  final String text;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tts = context.watch<TtsService>();
    final t = Theme.of(context);
    return SectionCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(text, style: t.textTheme.bodyLarge?.copyWith(height: 1.4))),
        const SizedBox(width: 12),
        Column(children: [
          IconButton.filled(
            iconSize: 28,
            tooltip: tts.speaking ? l.stop : l.listen,
            onPressed: () => tts.speaking ? tts.stop() : tts.speak(text, lang),
            icon: Icon(tts.speaking ? Icons.stop : Icons.volume_up),
          ),
          Text(tts.speaking ? l.stop : l.listen, style: t.textTheme.labelSmall),
        ]),
      ]),
    );
  }
}

class _WeatherStrip extends StatelessWidget {
  const _WeatherStrip({required this.days});
  final List<DayRisk> days;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.labelSmall;
    return Row(children: [
      for (final d in days)
        Expanded(
          child: Column(children: [
            Text('${d.weather.tMax.round()}°', style: t?.copyWith(fontWeight: FontWeight.w700)),
            Text('${d.weather.rhMean.round()}%', style: t),
            Icon(d.weather.rainMm > 0.5 ? Icons.water_drop : Icons.wb_sunny_outlined,
                size: 14, color: d.weather.rainMm > 0.5 ? Colors.blue : Colors.orange),
          ]),
        ),
    ]);
  }
}

class _PlanCard extends StatefulWidget {
  const _PlanCard({required this.plan, required this.dx, required this.logging, required this.logged, required this.onLog});
  final TreatmentPlan plan;
  final Diagnosis dx;
  final bool logging;
  final bool logged;
  final ValueChanged<TreatmentOption> onLog;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  late String _selected = widget.plan.recommendedTreatmentId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    final plan = widget.plan;
    final t = Theme.of(context);
    final sym = plan.currencySymbol;
    final selected = plan.options.where((o) => o.treatmentId == _selected).firstOrNull ?? plan.options.first;

    return SectionCard(
      title: l.treatmentPlan,
      icon: Icons.medication_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: StatTile(
              label: l.expectedLoss,
              value: money(plan.expectedLossLocal, sym, locale: app.language),
              color: RiskColors.severe,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(label: l.fieldSize, value: '${qty(plan.fieldSizeHa)} ${l.hectares}'),
          ),
        ]),
        const SizedBox(height: 16),
        for (final o in plan.options) ...[
          _OptionTile(
            option: o,
            symbol: sym,
            selected: o.treatmentId == _selected,
            recommended: o.treatmentId == plan.recommendedTreatmentId,
            onTap: () => setState(() => _selected = o.treatmentId),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push(
                Routes.dealers,
                extra: DealersArgs(
                  treatmentIds: [for (final o in plan.options) o.treatmentId],
                  highlightTreatmentId: selected.treatmentId,
                ),
              ),
              icon: const Icon(Icons.storefront_outlined),
              label: Text(l.findDealers),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: (widget.logging || widget.logged) ? null : () => widget.onLog(selected),
              icon: Icon(widget.logged ? Icons.check : Icons.task_alt),
              label: Text(widget.logged ? l.treatmentLogged : l.logTreatment, overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
        if (widget.logged)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l.partnerNote, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
      ]),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.symbol,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });
  final TreatmentOption option;
  final String symbol;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context);
    final app = context.read<AppState>();
    final accent = option.isOrganic ? RiskColors.low : Colors.indigo;
    return Material(
      color: selected ? accent.withValues(alpha: 0.08) : t.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? accent : t.colorScheme.outlineVariant, width: selected ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 6, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: Text(option.isOrganic ? l.organic : l.chemical,
                        style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  if (recommended)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star, size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(l.recommended,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(width: 8),
              Text(money(option.costLocal, symbol, locale: app.language),
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Text(option.product, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(l.perApplication(qty(option.quantityPerApplication), option.unit), style: t.textTheme.bodySmall),
            Text(l.applicationsEvery(option.applications, option.intervalDays), style: t.textTheme.bodySmall),
            if (option.preHarvestIntervalDays > 0)
              Text(l.preHarvest(option.preHarvestIntervalDays), style: t.textTheme.bodySmall?.copyWith(color: RiskColors.high)),
            if (option.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(option.notes, style: t.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 10),
            Row(children: [
              _Mini(label: l.valueProtected, value: money(option.valueProtectedLocal, symbol, locale: app.language)),
              const SizedBox(width: 12),
              _Mini(label: l.netBenefit, value: money(option.netBenefitLocal, symbol, locale: app.language),
                  color: option.netBenefitLocal >= 0 ? RiskColors.low : RiskColors.severe),
              if (option.roi != null) ...[
                const SizedBox(width: 12),
                _Mini(label: 'ROI', value: '${option.roi!.toStringAsFixed(1)}×'),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.labelSmall, overflow: TextOverflow.ellipsis),
        Text(value, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: color), overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
