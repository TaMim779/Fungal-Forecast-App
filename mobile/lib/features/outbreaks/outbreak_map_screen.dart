import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets.dart';

/// Community outbreak map: grid-aggregated reports (no exact farm points) + pre-emptive alerts.
class OutbreakMapScreen extends StatefulWidget {
  const OutbreakMapScreen({super.key, this.showMapTiles = true});

  /// Disabled in widget tests to avoid network tile requests.
  final bool showMapTiles;

  @override
  State<OutbreakMapScreen> createState() => _OutbreakMapScreenState();
}

class _OutbreakMapScreenState extends State<OutbreakMapScreen> {
  static const _radiusKm = 50.0;
  List<OutbreakCell> _cells = const [];
  List<OutbreakAlert> _alerts = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (!app.hasLocation) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        app.api.outbreaks(lat: app.lat!, lon: app.lon!, radiusKm: _radiusKm, lang: app.language),
        app.api.alerts(lat: app.lat!, lon: app.lon!, crop: app.crop, farmerId: app.farmer?.id, lang: app.language),
      ]);
      if (!mounted) return;
      setState(() {
        _cells = results[0] as List<OutbreakCell>;
        _alerts = results[1] as List<OutbreakAlert>;
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

    if (!app.hasLocation) {
      return Scaffold(
        appBar: AppBar(title: Text(l.outbreakMap)),
        body: EmptyState(
          icon: Icons.location_off_outlined,
          message: l.setLocationHint,
          action: FilledButton(onPressed: () => context.go(Routes.settings), child: Text(l.navSettings)),
        ),
      );
    }

    final centre = LatLng(app.lat!, app.lon!);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.outbreakMap),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: Column(children: [
        Expanded(
          flex: 5,
          child: Stack(children: [
            FlutterMap(
              options: MapOptions(initialCenter: centre, initialZoom: 10),
              children: [
                if (widget.showMapTiles)
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.fungalforecast.fungal_forecast',
                  ),
                CircleLayer(circles: [
                  CircleMarker(point: centre, radius: 10000, useRadiusInMeter: true,
                      color: t.colorScheme.primary.withValues(alpha: 0.06), borderColor: t.colorScheme.primary, borderStrokeWidth: 1),
                  for (final c in _cells)
                    CircleMarker(
                      point: LatLng(c.lat, c.lon),
                      radius: 2500.0 + 400.0 * c.reports.clamp(0, 10),
                      useRadiusInMeter: true,
                      color: RiskColors.of(c.maxSeverity).withValues(alpha: 0.35),
                      borderColor: RiskColors.of(c.maxSeverity),
                      borderStrokeWidth: 2,
                    ),
                ]),
                MarkerLayer(markers: [
                  Marker(point: centre, width: 36, height: 36, child: Icon(Icons.home, color: t.colorScheme.primary, size: 30)),
                  for (final c in _cells)
                    Marker(
                      point: LatLng(c.lat, c.lon),
                      width: 32,
                      height: 32,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: RiskColors.of(c.maxSeverity), shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2)),
                        child: Text('${c.reports}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                    ),
                ]),
              ],
            ),
            if (_loading) const Positioned(top: 12, right: 12, child: CircularProgressIndicator()),
            Positioned(
              left: 12,
              bottom: 12,
              child: Material(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final lv in const ['low', 'moderate', 'high', 'severe']) ...[
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: RiskColors.of(lv), shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(levelLabel(l, lv), style: t.textTheme.labelSmall),
                      const SizedBox(width: 10),
                    ],
                  ]),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          flex: 4,
          child: _error != null
              ? ErrorRetry(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(l.nearbyAlerts, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_alerts.isEmpty && _cells.isEmpty)
                      Text(l.noOutbreaks(_radiusKm.toInt()), style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                    for (final a in _alerts)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.warning_amber_rounded, color: RiskColors.high),
                          title: Text(a.diseaseName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${a.message}\n${a.recommendedAction}'),
                          isThreeLine: true,
                        ),
                      ),
                    for (final c in _cells)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: RiskColors.of(c.maxSeverity), shape: BoxShape.circle)),
                        title: Text(c.diseaseName),
                        subtitle: Text('${l.reports(c.reports)} · ${l.kmAway(c.distanceKm.toStringAsFixed(1))}'),
                        trailing: RiskBadge(level: c.maxSeverity),
                      ),
                  ],
                ),
        ),
      ]),
    );
  }
}
