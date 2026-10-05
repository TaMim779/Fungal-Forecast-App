import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/state/home_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets.dart';

const _countries = {
  'BD': 'Bangladesh', 'IN': 'India', 'PK': 'Pakistan', 'NP': 'Nepal', 'KE': 'Kenya',
  'NG': 'Nigeria', 'TZ': 'Tanzania', 'UG': 'Uganda', 'ID': 'Indonesia', 'VN': 'Vietnam', 'PH': 'Philippines',
};

const _languages = {'en': 'English', 'bn': 'বাংলা', 'hi': 'हिन्दी'};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _size;
  late final TextEditingController _lat;
  late final TextEditingController _lon;
  late final TextEditingController _apiUrl;
  late String _country;
  late String _crop;
  bool _saving = false;
  String? _locError;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final f = app.farmer;
    _name = TextEditingController(text: f?.name ?? '');
    _phone = TextEditingController(text: f?.phone ?? '');
    _size = TextEditingController(text: (f?.fieldSizeHa ?? 1.0).toString());
    _lat = TextEditingController(text: f?.lat?.toStringAsFixed(5) ?? '');
    _lon = TextEditingController(text: f?.lon?.toStringAsFixed(5) ?? '');
    _apiUrl = TextEditingController(text: app.apiUrl);
    _country = f?.country ?? 'BD';
    _crop = f?.crop ?? 'rice';
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _size, _lat, _lon, _apiUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    final l = AppLocalizations.of(context);
    setState(() => _locError = null);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _locError = l.locationDenied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)));
      setState(() {
        _lat.text = pos.latitude.toStringAsFixed(5);
        _lon.text = pos.longitude.toStringAsFixed(5);
      });
    } catch (e) {
      setState(() => _locError = '${l.locationDenied} ($e)');
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    final home = context.read<HomeController>();
    setState(() => _saving = true);
    final lat = double.tryParse(_lat.text.trim());
    final lon = double.tryParse(_lon.text.trim());
    final size = double.tryParse(_size.text.replaceAll(',', '.')) ?? 1.0;
    try {
      if (_apiUrl.text.trim() != app.apiUrl) await app.setApiUrl(_apiUrl.text.trim());
      try {
        await app.saveFarmer(
          name: _name.text.trim(), phone: _phone.text.trim(), country: _country, crop: _crop,
          fieldSizeHa: size, lat: lat, lon: lon,
        );
      } catch (_) {
        // Server unreachable: keep the profile locally so the app remains usable.
        await app.saveFarmerOffline(Farmer(
          id: app.farmer?.id ?? '', name: _name.text.trim(), phone: _phone.text.trim(), language: app.language,
          country: _country, crop: _crop, fieldSizeHa: size, lat: lat, lon: lon,
        ));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.saved)));
      home.refresh();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.watch<AppState>();
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: l.language,
              icon: Icons.translate,
              child: SegmentedButton<String>(
                segments: [for (final e in _languages.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                selected: {app.language},
                onSelectionChanged: (s) => app.setLanguage(s.first),
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: l.profile,
              icon: Icons.person_outline,
              child: Column(children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: l.name, prefixIcon: const Icon(Icons.badge_outlined)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? l.requiredField : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: l.phone, prefixIcon: const Icon(Icons.phone_outlined)),
                  validator: (v) => (v == null || v.trim().length < 6) ? l.requiredField : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _country,
                  decoration: InputDecoration(labelText: l.country, prefixIcon: const Icon(Icons.flag_outlined)),
                  items: [for (final e in _countries.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _country = v ?? _country),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: app.catalog.crops.any((c) => c.id == _crop) ? _crop : null,
                  decoration: InputDecoration(labelText: l.crop, prefixIcon: const Icon(Icons.grass)),
                  items: [for (final c in app.catalog.crops) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => _crop = v ?? _crop),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _size,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: l.fieldSize, suffixText: l.hectares, prefixIcon: const Icon(Icons.crop_square)),
                  validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) > 0 ? null : l.requiredField,
                ),
              ]),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: l.location,
              icon: Icons.location_on_outlined,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _lat,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(labelText: l.latitude),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lon,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(labelText: l.longitude),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: _useMyLocation, icon: const Icon(Icons.my_location), label: Text(l.useMyLocation)),
                if (_locError != null)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(_locError!, style: TextStyle(color: t.colorScheme.error))),
              ]),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: l.serverStatus,
              icon: Icons.dns_outlined,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 10, color: app.online ? RiskColors.low : RiskColors.severe),
                const SizedBox(width: 6),
                Text(app.online ? l.connected : l.disconnected, style: t.textTheme.labelMedium),
              ]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextFormField(
                  controller: _apiUrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(labelText: l.apiUrl, prefixIcon: const Icon(Icons.link)),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.fieldOfficerMode),
                  subtitle: Text(l.fieldOfficerModeHint),
                  value: app.fieldOfficerMode,
                  onChanged: app.setFieldOfficerMode,
                ),
              ]),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: Text(l.save),
            ),
          ],
        ),
      ),
    );
  }
}
