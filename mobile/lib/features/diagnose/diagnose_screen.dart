import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/state/app_state.dart';
import '../../core/state/home_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets.dart';

class DiagnoseScreen extends StatefulWidget {
  const DiagnoseScreen({super.key, this.picker});
  final ImagePicker? picker;

  @override
  State<DiagnoseScreen> createState() => _DiagnoseScreenState();
}

class _DiagnoseScreenState extends State<DiagnoseScreen> {
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  Uint8List? _bytes;
  String _filename = 'leaf.jpg';
  String? _crop;
  late final TextEditingController _fieldSize;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _crop = app.crop;
    _fieldSize = TextEditingController(text: app.fieldSizeHa.toString());
  }

  @override
  void dispose() {
    _fieldSize.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await _picker.pickImage(source: source, maxWidth: 1280, imageQuality: 85);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        _bytes = bytes;
        _filename = x.name.isEmpty ? 'leaf.jpg' : x.name;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _analyze() async {
    final bytes = _bytes;
    if (bytes == null) return;
    final app = context.read<AppState>();
    final home = context.read<HomeController>();
    final size = double.tryParse(_fieldSize.text.replaceAll(',', '.')) ?? app.fieldSizeHa;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dx = await app.api.diagnose(
        imageBytes: bytes,
        filename: _filename,
        crop: _crop ?? app.crop,
        lang: app.language,
        country: app.country,
        fieldSizeHa: size,
        lat: app.lat,
        lon: app.lon,
        farmerId: app.farmer?.id,
      );
      home.addDiagnosis(dx);
      if (!mounted) return;
      setState(() => _bytes = null);
      context.push('${Routes.result}/${dx.id}', extra: dx);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = AppLocalizations.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.watch<AppState>();
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.scanLeaf)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (app.farmer == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: t.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  leading: const Icon(Icons.person_add_alt),
                  title: Text(l.registerFirst, style: t.textTheme.bodyMedium),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(Routes.settings),
                ),
              ),
            ),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              decoration: BoxDecoration(
                color: t.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: t.colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: _bytes == null
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.energy_savings_leaf_outlined, size: 72, color: t.colorScheme.outline),
                      const SizedBox(height: 8),
                      Text(l.scanLeafHint, textAlign: TextAlign.center, style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                    ])
                  : Image.memory(_bytes!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: Text(_bytes == null ? l.takePhoto : l.retake),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l.chooseGallery),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          SectionCard(
            child: Column(children: [
              DropdownButtonFormField<String>(
                initialValue: app.catalog.crops.any((c) => c.id == _crop) ? _crop : null,
                decoration: InputDecoration(labelText: l.selectCrop, prefixIcon: const Icon(Icons.grass)),
                items: [for (final c in app.catalog.crops) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: _busy ? null : (v) => setState(() => _crop = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fieldSize,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: l.fieldSize, suffixText: l.hectares, prefixIcon: const Icon(Icons.crop_square)),
              ),
            ]),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: t.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: (_bytes == null || _busy) ? null : _analyze,
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.biotech),
            label: Text(_busy ? l.analyzing : l.analyzeButton),
          ),
        ],
      ),
    );
  }
}
