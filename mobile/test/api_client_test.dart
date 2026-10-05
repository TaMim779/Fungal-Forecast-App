import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fungal_forecast/core/api/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers/fake_api.dart';

void main() {
  group('ApiClient', () {
    test('health returns true when server answers ok', () async {
      final api = ApiClient(baseUrl: 'http://x', client: fakeApiClient());
      expect(await api.health(), isTrue);
    });

    test('health returns false on transport error', () async {
      final api = ApiClient(baseUrl: 'http://x', client: MockClient((_) async => throw Exception('down')));
      expect(await api.health(), isFalse);
    });

    test('non-2xx responses surface the server detail', () async {
      final api = ApiClient(baseUrl: 'http://x', client: fakeApiClient());
      expect(
        () => api.getDiagnosis('missing', 'en'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    });

    test('diagnose sends multipart fields and parses the result', () async {
      http.BaseRequest? captured;
      final client = MockClient((req) async {
        captured = req;
        return jsonResponse(sampleDiagnosisJson());
      });
      final api = ApiClient(baseUrl: 'http://x/', client: client);
      final dx = await api.diagnose(
        imageBytes: [1, 2, 3],
        filename: 'leaf.png',
        crop: 'rice',
        lang: 'bn',
        country: 'BD',
        fieldSizeHa: 1.5,
        lat: 23.86,
        lon: 90.27,
        farmerId: 'frm_1',
      );
      expect(dx.id, 'dx_test1');
      expect(captured!.url.toString(), 'http://x/api/v1/diagnose');
      expect(captured!.headers['content-type'], startsWith('multipart/form-data'));
      final body = utf8.decode((captured as http.Request).bodyBytes, allowMalformed: true);
      expect(body, contains('name="crop"'));
      expect(body, contains('bn'));
      expect(body, contains('frm_1'));
      expect(body, contains('filename="leaf.png"'));
    });

    test('query parameters omit nulls and join treatment ids', () async {
      Uri? seen;
      final client = MockClient((req) async {
        seen = req.url;
        return http.Response('[]', 200);
      });
      final api = ApiClient(baseUrl: 'http://x', client: client);
      await api.dealers(lat: 1, lon: 2, treatmentIds: ['a', 'b']);
      expect(seen!.queryParameters['treatment_ids'], 'a,b');
      await api.alerts(lat: 1, lon: 2, lang: 'en');
      expect(seen!.queryParameters.containsKey('crop'), isFalse);
      expect(seen!.queryParameters.containsKey('farmer_id'), isFalse);
    });
  });
}
