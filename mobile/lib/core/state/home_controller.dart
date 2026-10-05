import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../storage/local_store.dart';
import 'app_state.dart';

/// Loads the home dashboard: crop risk outlook, community alerts, recent diagnoses.
/// Falls back to the local cache when the server is unreachable.
class HomeController extends ChangeNotifier {
  HomeController({required this.app, required LocalStore store})
      : _store = store,
        _diagnoses = store.cachedDiagnoses {
    final cached = store.cachedCropForecast;
    if (cached != null) _cropForecast = CropForecast.fromJson(cached);
  }

  final AppState app;
  final LocalStore _store;
  AppState get _app => app;
  ApiClient get _api => _app.api;

  bool _loading = false;
  bool get loading => _loading;

  bool _fromCache = false;
  bool get fromCache => _fromCache;

  String? _error;
  String? get error => _error;

  CropForecast? _cropForecast;
  CropForecast? get cropForecast => _cropForecast;

  List<OutbreakAlert> _alerts = const [];
  List<OutbreakAlert> get alerts => _alerts;

  List<Diagnosis> _diagnoses;
  List<Diagnosis> get diagnoses => _diagnoses;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final lang = _app.language;
    final lat = _app.lat;
    final lon = _app.lon;
    try {
      if (lat != null && lon != null) {
        final results = await Future.wait([
          _api.cropForecast(lat: lat, lon: lon, crop: _app.crop, lang: lang),
          _api.alerts(lat: lat, lon: lon, crop: _app.crop, farmerId: _app.farmer?.id, lang: lang),
        ]);
        _cropForecast = results[0] as CropForecast;
        _alerts = results[1] as List<OutbreakAlert>;
        await _store.cacheCropForecast(_cropForecast?.raw);
      }
      final farmer = _app.farmer;
      if (farmer != null) {
        _diagnoses = await _api.farmerDiagnoses(farmer.id, lang);
        await _store.cacheDiagnoses(_diagnoses);
      }
      _fromCache = false;
    } catch (e) {
      debugPrint('home refresh failed: $e');
      _fromCache = true;
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Called after a new diagnosis so the dashboard updates without a round-trip.
  void addDiagnosis(Diagnosis d) {
    _diagnoses = [d, ..._diagnoses.where((x) => x.id != d.id)];
    _store.cacheDiagnoses(_diagnoses);
    notifyListeners();
  }
}
