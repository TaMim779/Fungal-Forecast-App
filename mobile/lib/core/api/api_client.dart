import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thin typed wrapper over the FungalForecast REST API.
///
/// All methods throw [ApiException] on non-2xx responses and rethrow
/// transport errors so callers can decide how to degrade (e.g. offline cache).
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client, this.timeout = const Duration(seconds: 20), this.token})
      : _client = client ?? http.Client();

  String baseUrl;
  String? token;
  final http.Client _client;
  final Duration timeout;

  Map<String, String> get _jsonHeaders => {
        'content-type': 'application/json',
        if (token != null && token!.isNotEmpty) 'authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final qp = <String, String>{};
    query?.forEach((k, v) {
      if (v != null) qp[k] = v.toString();
    });
    return Uri.parse('$base/api/v1$path').replace(queryParameters: qp.isEmpty ? null : qp);
  }

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    final res = await _client.get(_uri(path, query), headers: _jsonHeaders).timeout(timeout);
    return _decode(res);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body, [Map<String, dynamic>? query]) async {
    final res = await _client
        .post(_uri(path, query), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(timeout);
    return _decode(res);
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    final res = await _client.patch(_uri(path), headers: _jsonHeaders, body: jsonEncode(body)).timeout(timeout);
    return _decode(res);
  }

  Future<({String token, Farmer farmer})> _session(String path, Map<String, dynamic> body) async {
    final j = await _post(path, body) as Map<String, dynamic>;
    return (token: _sToken(j['token']), farmer: Farmer.fromJson(j['farmer'] as Map<String, dynamic>));
  }

  String _sToken(dynamic v) => v?.toString() ?? '';

  dynamic _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String detail = text;
      try {
        final j = jsonDecode(text);
        if (j is Map && j['detail'] != null) detail = j['detail'].toString();
      } catch (_) {}
      throw ApiException(detail, statusCode: res.statusCode);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  // ---- system / catalog ------------------------------------------------------
  Future<bool> health() async {
    try {
      final j = await _get('/health');
      return j is Map && j['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<Catalog> catalog(String lang) async => Catalog.fromJson(await _get('/catalog', {'lang': lang}));

  // ---- farmers -----------------------------------------------------------------
  Future<Farmer> registerFarmer({
    required String name,
    required String phone,
    required String language,
    required String country,
    required String crop,
    required double fieldSizeHa,
    double? lat,
    double? lon,
  }) async =>
      Farmer.fromJson(await _post('/farmers', {
        'name': name,
        'phone': phone,
        'language': language,
        'country': country,
        'crop': crop,
        'field_size_ha': fieldSizeHa,
        'lat': lat,
        'lon': lon,
      }));

  Future<({String token, Farmer farmer})> registerAccount({
    required String name,
    required String phone,
    required String password,
    required String language,
    required String country,
    required String crop,
    required double fieldSizeHa,
  }) =>
      _session('/auth/register', {
        'name': name,
        'phone': phone,
        'password': password,
        'language': language,
        'country': country,
        'crop': crop,
        'field_size_ha': fieldSizeHa,
      });

  Future<({String token, Farmer farmer})> login({required String phone, required String password}) =>
      _session('/auth/login', {'phone': phone, 'password': password});

  Future<void> logout() async {
    await _post('/auth/logout', {});
  }

  Future<Farmer> updateProfile({
    required String name,
    required String phone,
    required String language,
    required String country,
    required String crop,
    required double fieldSizeHa,
    double? lat,
    double? lon,
  }) async =>
      Farmer.fromJson(await _patch('/farmers/me', {
        'name': name,
        'phone': phone,
        'language': language,
        'country': country,
        'crop': crop,
        'field_size_ha': fieldSizeHa,
        'lat': lat,
        'lon': lon,
      }));

  // ---- diagnosis ----------------------------------------------------------------
  Future<Diagnosis> diagnose({
    required List<int> imageBytes,
    required String filename,
    required String crop,
    required String lang,
    required String country,
    required double fieldSizeHa,
    double? lat,
    double? lon,
    String? farmerId,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/diagnose'))
      ..fields['crop'] = crop
      ..fields['lang'] = lang
      ..fields['country'] = country
      ..fields['field_size_ha'] = fieldSizeHa.toString()
      ..files.add(http.MultipartFile.fromBytes('image', imageBytes, filename: filename));
    if (lat != null) req.fields['lat'] = lat.toString();
    if (lon != null) req.fields['lon'] = lon.toString();
    if (farmerId != null && farmerId.isNotEmpty) req.fields['farmer_id'] = farmerId;
    final streamed = await _client.send(req).timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    return Diagnosis.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<Diagnosis> getDiagnosis(String id, String lang) async =>
      Diagnosis.fromJson(await _get('/diagnoses/$id', {'lang': lang}));

  Future<List<Diagnosis>> farmerDiagnoses(String farmerId, String lang) async =>
      ((await _get('/farmers/$farmerId/diagnoses', {'lang': lang})) as List)
          .map((e) => Diagnosis.fromJson(e))
          .toList();

  // ---- forecast ---------------------------------------------------------------
  Future<CropForecast> cropForecast({required double lat, required double lon, required String crop, required String lang}) async =>
      CropForecast.fromJson(await _get('/forecast/crop', {'lat': lat, 'lon': lon, 'crop': crop, 'lang': lang}));

  Future<Forecast> forecast({required double lat, required double lon, required String diseaseId, required String lang}) async =>
      Forecast.fromJson(await _get('/forecast', {'lat': lat, 'lon': lon, 'disease_id': diseaseId, 'lang': lang}));

  // ---- community ----------------------------------------------------------------
  Future<List<OutbreakCell>> outbreaks({required double lat, required double lon, double radiusKm = 50, required String lang}) async =>
      ((await _get('/outbreaks', {'lat': lat, 'lon': lon, 'radius_km': radiusKm, 'lang': lang})) as List)
          .map((e) => OutbreakCell.fromJson(e))
          .toList();

  Future<List<OutbreakAlert>> alerts({required double lat, required double lon, String? crop, String? farmerId, required String lang}) async =>
      ((await _get('/outbreaks/alerts', {'lat': lat, 'lon': lon, 'crop': crop, 'farmer_id': farmerId, 'lang': lang})) as List)
          .map((e) => OutbreakAlert.fromJson(e))
          .toList();

  Future<List<Dealer>> dealers({required double lat, required double lon, List<String>? treatmentIds, double radiusKm = 100}) async =>
      ((await _get('/dealers/nearby', {
        'lat': lat,
        'lon': lon,
        'treatment_ids': (treatmentIds == null || treatmentIds.isEmpty) ? null : treatmentIds.join(','),
        'radius_km': radiusKm,
      })) as List)
          .map((e) => Dealer.fromJson(e))
          .toList();

  // ---- agronomist ---------------------------------------------------------------
  Future<List<Diagnosis>> agronomistQueue(String lang) async =>
      ((await _get('/agronomist/queue', {'lang': lang})) as List).map((e) => Diagnosis.fromJson(e)).toList();

  Future<Diagnosis> submitReview({
    required String diagnosisId,
    required String reviewer,
    required String diseaseId,
    required String severity,
    String? notes,
    required String lang,
  }) async =>
      Diagnosis.fromJson(await _post('/agronomist/queue/$diagnosisId/review',
          {'reviewer': reviewer, 'disease_id': diseaseId, 'severity': severity, 'notes': notes}, {'lang': lang}));

  // ---- ledger -----------------------------------------------------------------------
  Future<LedgerEntry> addLedgerEntry({required String farmerId, required String diagnosisId, required String treatmentId}) async =>
      LedgerEntry.fromJson(await _post('/ledger/entries',
          {'farmer_id': farmerId, 'diagnosis_id': diagnosisId, 'treatment_id': treatmentId}));

  Future<List<LedgerEntry>> ledgerEntries(String farmerId) async =>
      ((await _get('/ledger/entries', {'farmer_id': farmerId})) as List).map((e) => LedgerEntry.fromJson(e)).toList();

  Future<LedgerSummary> ledgerSummary(String farmerId) async =>
      LedgerSummary.fromJson(await _get('/ledger/summary', {'farmer_id': farmerId}));

  Uri ledgerCsvUri(String farmerId) => _uri('/ledger/export.csv', {'farmer_id': farmerId});
}
