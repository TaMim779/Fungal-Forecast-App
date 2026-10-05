import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../storage/local_store.dart';

/// Global app state: settings, farmer profile, catalogue and connectivity.
class AppState extends ChangeNotifier {
  AppState({required LocalStore store, required this.api})
      : _store = store,
        _language = store.language,
        _farmer = store.farmer,
        _fieldOfficerMode = store.fieldOfficerMode;

  final LocalStore _store;
  final ApiClient api;

  String _language;
  String get language => _language;
  Locale get locale => Locale(_language);

  Farmer? _farmer;
  Farmer? get farmer => _farmer;

  bool _fieldOfficerMode;
  bool get fieldOfficerMode => _fieldOfficerMode;

  Catalog _catalog = Catalog.fallback;
  Catalog get catalog => _catalog;

  bool _online = false;
  bool get online => _online;

  String get apiUrl => api.baseUrl;

  // Defaults used when no farmer profile exists yet.
  String get crop => _farmer?.crop ?? 'rice';
  String get country => _farmer?.country ?? 'BD';
  double get fieldSizeHa => _farmer?.fieldSizeHa ?? 1.0;
  double? get lat => _farmer?.lat;
  double? get lon => _farmer?.lon;
  bool get hasLocation => _farmer?.hasLocation ?? false;

  Future<void> init() async {
    await refreshConnectivity();
  }

  Future<void> refreshConnectivity() async {
    final ok = await api.health();
    if (ok != _online) {
      _online = ok;
      notifyListeners();
    }
    if (ok) await _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      _catalog = await api.catalog(_language);
      notifyListeners();
    } catch (e) {
      debugPrint('catalog load failed: $e');
    }
  }

  Future<void> setLanguage(String lang) async {
    if (lang == _language) return;
    _language = lang;
    await _store.setLanguage(lang);
    notifyListeners();
    if (_online) await _loadCatalog();
  }

  Future<void> setApiUrl(String url) async {
    api.baseUrl = url.trim();
    await _store.setApiUrl(url);
    notifyListeners();
    await refreshConnectivity();
  }

  Future<void> setFieldOfficerMode(bool v) async {
    _fieldOfficerMode = v;
    await _store.setFieldOfficerMode(v);
    notifyListeners();
  }

  /// Registers (or updates) the farmer on the server and caches locally.
  Future<Farmer> saveFarmer({
    required String name,
    required String phone,
    required String country,
    required String crop,
    required double fieldSizeHa,
    double? lat,
    double? lon,
  }) async {
    final f = await api.registerFarmer(
      name: name,
      phone: phone,
      language: _language,
      country: country,
      crop: crop,
      fieldSizeHa: fieldSizeHa,
      lat: lat,
      lon: lon,
    );
    _farmer = f;
    await _store.setFarmer(f);
    notifyListeners();
    return f;
  }

  /// Keeps a local-only profile when the server is unreachable.
  Future<void> saveFarmerOffline(Farmer f) async {
    _farmer = f;
    await _store.setFarmer(f);
    notifyListeners();
  }
}
