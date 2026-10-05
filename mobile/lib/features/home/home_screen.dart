import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/state/home_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<HomeController>().refresh());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.watch<AppState>();
    final home = context.watch<HomeController>();
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.eco, color: t.colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(child: Text(l.appTitle, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          if (app.fieldOfficerMode)
            IconButton(
              tooltip: l.agronomistQueue,
              icon: const Icon(Icons.medical_services_outlined),
              onPressed: () => context.push(Routes.agronomist),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: home.loading ? null : home.refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: home.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (!app.online || home.fromCache) const Padding(padding: EdgeInsets.only(bottom: 12), child: OfflineBanner()),
            _Hero(name: app.farmer?.name, tagline: l.tagline),
            const SizedBox(height: 16),
            _ScanCard(l: l),
            const SizedBox(height: 16),
            _OutlookCard(l: l, app: app, home: home),
            const SizedBox(height: 16),
            _AlertsCard(l: l, alerts: home.alerts, hasLocation: app.hasLocation),
            const SizedBox(height: 16),
            _RecentCard(l: l, items: home.diagnoses),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.name, required this.tagline});
  final String? name;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (name != null && name!.isNotEmpty)
        Text(l.greeting(name!), style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      Text(tagline, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.go(Routes.diagnose),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [t.colorScheme.primary, t.colorScheme.primary.withValues(alpha: 0.75)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: const Icon(Icons.photo_camera, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.scanLeaf, style: t.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(l.scanLeafHint, style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}

class _OutlookCard extends StatelessWidget {
  const _OutlookCard({required this.l, required this.app, required this.home});
  final AppLocalizations l;
  final AppState app;
  final HomeController home;

  @override
  Widget build(BuildContext context) {
    final fc = home.cropForecast;
    final t = Theme.of(context);
    return SectionCard(
      title: l.riskOutlook(app.catalog.cropName(app.crop)),
      icon: Icons.cloud_outlined,
      child: !app.hasLocation
          ? Row(children: [
              Icon(Icons.location_off_outlined, color: t.colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(child: Text(l.setLocationHint)),
              TextButton(onPressed: () => context.go(Routes.settings), child: Text(l.navSettings)),
            ])
          : fc == null
              ? (home.loading
                  ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                  : Text(home.error ?? l.errorGeneric))
              : Column(children: [
                  for (final d in fc.diseases) ...[
                    _DiseaseOutlookRow(item: d, weather: fc.weather, locale: app.language),
                    if (d != fc.diseases.last) const Divider(height: 20),
                  ],
                ]),
    );
  }
}

class _DiseaseOutlookRow extends StatelessWidget {
  const _DiseaseOutlookRow({required this.item, required this.weather, required this.locale});
  final CropRiskItem item;
  final List<DailyWeather> weather;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(item.diseaseName, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
        RiskBadge(level: item.overallLevel),
      ]),
      const SizedBox(height: 8),
      RiskBars(
        risks: item.dailyRisk,
        labels: [for (var i = 0; i < item.dailyRisk.length; i++) i < weather.length ? shortDay(weather[i].day, locale) : ''],
        height: 44,
      ),
      const SizedBox(height: 6),
      Text(item.action, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.l, required this.alerts, required this.hasLocation});
  final AppLocalizations l;
  final List<OutbreakAlert> alerts;
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SectionCard(
      title: l.alertsTitle,
      icon: Icons.campaign_outlined,
      trailing: alerts.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: RiskColors.high, borderRadius: BorderRadius.circular(999)),
              child: Text('${alerts.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
      child: alerts.isEmpty
          ? Text(hasLocation ? l.noAlerts : l.setLocationHint, style: TextStyle(color: t.colorScheme.onSurfaceVariant))
          : Column(children: [
              for (final a in alerts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.warning_amber_rounded, color: RiskColors.high),
                  title: Text(a.diseaseName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${a.message}\n${a.recommendedAction}'),
                  isThreeLine: true,
                  trailing: Text(l.kmAway(a.nearestKm.toStringAsFixed(1)), style: t.textTheme.labelSmall),
                  onTap: () => context.go(Routes.outbreaks),
                ),
            ]),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.l, required this.items});
  final AppLocalizations l;
  final List<Diagnosis> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return SectionCard(
      title: l.recentDiagnoses,
      icon: Icons.history,
      child: items.isEmpty
          ? Text(l.noDiagnoses, style: TextStyle(color: t.colorScheme.onSurfaceVariant))
          : Column(children: [
              for (final d in items.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: RiskColors.of(d.isHealthy ? 'low' : d.riskLevel).withValues(alpha: 0.15),
                    child: Icon(d.isHealthy ? Icons.check : Icons.coronavirus_outlined,
                        color: RiskColors.of(d.isHealthy ? 'low' : d.riskLevel)),
                  ),
                  title: Text(d.diseaseName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${shortDate(d.createdAt, locale)} · ${l.confidence} ${percent(d.confidence)}'),
                  trailing: d.routedToAgronomist
                      ? const Icon(Icons.hourglass_top, color: RiskColors.moderate)
                      : const Icon(Icons.chevron_right),
                  onTap: () => context.push('${Routes.result}/${d.id}', extra: d),
                ),
            ]),
    );
  }
}
