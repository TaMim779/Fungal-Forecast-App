import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Persists settings, the farmer profile and the last results so the app stays
/// useful on intermittent connectivity (the user sees their last forecast/plan).
class LocalStore {
  LocalStore(this._prefs);

  static Future<LocalStore> open() async => LocalStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _kApiUrl = 'api_url';
  static const _kLang = 'lang';
  static const _kFarmer = 'farmer';
  static const _kDiagnoses = 'diagnoses_cache';
  static const _kCropForecast = 'crop_forecast_cache';
  static const _kOfficer = 'field_officer_mode';
  static const _kToken = 'auth_token';

  /// Default server URL. Override at build time with
  /// `--dart-define=FF_API_URL=http://10.0.2.2:8000` (Android emulator) or
  /// change it later from Settings.
  static const defaultApiUrl = String.fromEnvironment(
    'FF_API_URL',
    defaultValue: 'http://localhost:8000',
  );

  String get apiUrl => _prefs.getString(_kApiUrl) ?? defaultApiUrl;
  Future<void> setApiUrl(String v) => _prefs.setString(_kApiUrl, v.trim());

  String get language => _prefs.getString(_kLang) ?? 'en';
  Future<void> setLanguage(String v) => _prefs.setString(_kLang, v);

  bool get fieldOfficerMode => _prefs.getBool(_kOfficer) ?? false;
  Future<void> setFieldOfficerMode(bool v) => _prefs.setBool(_kOfficer, v);

  String? get token => _prefs.getString(_kToken);
  Future<void> setToken(String? v) async {
    if (v == null || v.isEmpty) {
      await _prefs.remove(_kToken);
    } else {
      await _prefs.setString(_kToken, v);
    }
  }

  Farmer? get farmer {
    final raw = _prefs.getString(_kFarmer);
    if (raw == null) return null;
    try {
      return Farmer.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> setFarmer(Farmer? f) async {
    if (f == null) {
      await _prefs.remove(_kFarmer);
    } else {
      await _prefs.setString(_kFarmer, jsonEncode(f.toJson()));
    }
  }

  List<Diagnosis> get cachedDiagnoses {
    final raw = _prefs.getString(_kDiagnoses);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => Diagnosis.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> cacheDiagnoses(List<Diagnosis> items) async {
    final raws = items.map((d) => d.raw).whereType<Map<String, dynamic>>().take(20).toList();
    await _prefs.setString(_kDiagnoses, jsonEncode(raws));
  }

  Map<String, dynamic>? get cachedCropForecast {
    final raw = _prefs.getString(_kCropForecast);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheCropForecast(Map<String, dynamic>? json) async {
    if (json == null) return;
    await _prefs.setString(_kCropForecast, jsonEncode(json));
  }
}
