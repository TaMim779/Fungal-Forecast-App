import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets.dart';

class DealersArgs {
  const DealersArgs({this.treatmentIds = const [], this.highlightTreatmentId});
  final List<String> treatmentIds;
  final String? highlightTreatmentId;
}

/// Agro-dealer integration: who has the recommended inputs in stock nearby and at what price.
class DealersScreen extends StatefulWidget {
  const DealersScreen({super.key, required this.args});
  final DealersArgs args;

  @override
  State<DealersScreen> createState() => _DealersScreenState();
}

class _DealersScreenState extends State<DealersScreen> {
  late Future<List<Dealer>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Dealer>> _load() {
    final app = context.read<AppState>();
    // Default to Dhaka sample area when the farmer has no location yet.
    final lat = app.lat ?? 23.86;
    final lon = app.lon ?? 90.27;
    return app.api.dealers(lat: lat, lon: lon, treatmentIds: widget.args.treatmentIds);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(l.dealersTitle)),
      body: FutureBuilder<List<Dealer>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return ErrorRetry(message: snap.error.toString(), onRetry: () => setState(() => _future = _load()));
          }
          final dealers = snap.data ?? const [];
          if (dealers.isEmpty) return EmptyState(icon: Icons.storefront_outlined, message: l.noDealers);
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: dealers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _DealerCard(
              dealer: dealers[i],
              highlight: widget.args.highlightTreatmentId,
              locale: app.language,
            ),
          );
        },
      ),
    );
  }
}

class _DealerCard extends StatelessWidget {
  const _DealerCard({required this.dealer, required this.highlight, required this.locale});
  final Dealer dealer;
  final String? highlight;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            backgroundColor: (dealer.hasStock ? RiskColors.low : RiskColors.none).withValues(alpha: 0.15),
            child: Icon(Icons.storefront, color: dealer.hasStock ? RiskColors.low : RiskColors.none),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dealer.name, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(dealer.address, style: t.textTheme.bodySmall),
              Text('${l.kmAway(dealer.distanceKm.toStringAsFixed(1))} · ${dealer.openingHours}', style: t.textTheme.bodySmall),
            ]),
          ),
          IconButton.filledTonal(
            tooltip: l.call,
            icon: const Icon(Icons.call),
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: dealer.phone)),
          ),
        ]),
        const Divider(height: 20),
        for (final item in dealer.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(item.inStock ? Icons.check_circle : Icons.cancel,
                  size: 18, color: item.inStock ? RiskColors.low : RiskColors.severe),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.product,
                    style: TextStyle(fontWeight: item.treatmentId == highlight ? FontWeight.w800 : FontWeight.w500)),
              ),
              Text(item.inStock ? l.inStock : l.outOfStock,
                  style: t.textTheme.labelSmall?.copyWith(color: item.inStock ? RiskColors.low : RiskColors.severe)),
              const SizedBox(width: 10),
              Text('${money(item.priceLocal, '', locale: locale)} ${dealer.currency}',
                  style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }
}
