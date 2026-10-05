import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Canned API responses mirroring the backend contract.
Map<String, dynamic> sampleDiagnosisJson({bool routed = false}) => {
      'id': 'dx_test1',
      'farmer_id': 'frm_1',
      'crop': 'rice',
      'disease_id': 'rice_blast',
      'disease_name': 'Rice blast',
      'pathogen': 'Magnaporthe oryzae',
      'symptoms': 'Diamond-shaped lesions',
      'confidence': 0.87,
      'severity': 'high',
      'lesion_fraction': 0.4,
      'status': routed ? 'pending_review' : 'confirmed',
      'routed_to_agronomist': routed,
      'alternatives': [
        {'disease_id': 'rice_brown_spot', 'disease_name': 'Brown spot', 'confidence': 0.06}
      ],
      'forecast': {
        'disease_id': 'rice_blast',
        'disease_name': 'Rice blast',
        'crop': 'rice',
        'lat': 23.86,
        'lon': 90.27,
        'weather_provider': 'mock',
        'days': [
          for (var i = 0; i < 5; i++)
            {
              'day': '2026-10-0${6 + i}',
              'risk': 0.3 + i * 0.12,
              'level': i < 2 ? 'moderate' : 'high',
              'weather_component': 0.3,
              'diagnosis_component': 0.5,
              'weather': {'day': '2026-10-0${6 + i}', 't_min': 24, 't_max': 31, 't_mean': 27, 'rh_mean': 88, 'rh_max': 96, 'rain_mm': 2.0, 'wet_hours': 9},
            }
        ],
        'summary': {'peak_risk': 0.78, 'peak_level': 'severe', 'peak_day': '2026-10-10', 'mean_risk': 0.54, 'overall_level': 'high'},
        'action': 'Treat within 48 hours.',
      },
      'plan': {
        'disease_id': 'rice_blast',
        'disease_name': 'Rice blast',
        'crop': 'rice',
        'field_size_ha': 1.5,
        'currency': {'code': 'BDT', 'symbol': '৳'},
        'expected_loss_local': 77760,
        'recommended_treatment_id': 'rb_chem_tricyclazole',
        'options': [
          {
            'treatment_id': 'rb_org_trichoderma', 'type': 'organic', 'product': 'Trichoderma viride', 'dose_per_ha': 2.5, 'unit': 'kg',
            'quantity_per_application': 3.75, 'applications': 2, 'interval_days': 10, 'total_quantity': 7.5, 'pre_harvest_interval_days': 0,
            'cost_usd': 60, 'cost_local': 7200, 'value_protected_local': 42768, 'net_benefit_local': 35568, 'roi': 5.9, 'notes': 'Spray in the evening.'
          },
          {
            'treatment_id': 'rb_chem_tricyclazole', 'type': 'chemical', 'product': 'Tricyclazole 75 WP', 'dose_per_ha': 0.3, 'unit': 'kg',
            'quantity_per_application': 0.45, 'applications': 2, 'interval_days': 12, 'total_quantity': 0.9, 'pre_harvest_interval_days': 21,
            'cost_usd': 43.2, 'cost_local': 5184, 'value_protected_local': 62208, 'net_benefit_local': 57024, 'roi': 12.0, 'notes': 'Wear mask.'
          },
        ],
      },
      'explanation': 'Your rice leaf shows signs of Rice blast (87% confidence, high severity).',
      'model_version': 'heuristic-0.1',
      'created_at': '2026-10-06T06:00:00+00:00',
      'lat': 23.86,
      'lon': 90.27,
    };

Map<String, dynamic> sampleFarmerJson() => {
      'id': 'frm_1', 'name': 'Rahim', 'phone': '+8801700000000', 'language': 'en', 'country': 'BD',
      'crop': 'rice', 'field_size_ha': 1.5, 'lat': 23.86, 'lon': 90.27, 'created_at': '2026-10-01T00:00:00+00:00',
    };

Map<String, dynamic> sampleCatalogJson() => {
      'languages': ['en', 'bn', 'hi'],
      'crops': [
        {'id': 'rice', 'name': 'Rice'},
        {'id': 'wheat', 'name': 'Wheat'},
      ],
      'diseases': [
        {'id': 'rice_blast', 'crop': 'rice', 'name': 'Rice blast', 'pathogen': 'M. oryzae', 'symptoms': 'Lesions'},
        {'id': 'rice_brown_spot', 'crop': 'rice', 'name': 'Brown spot', 'pathogen': 'B. oryzae', 'symptoms': 'Spots'},
      ],
    };

Map<String, dynamic> sampleCropForecastJson() => {
      'crop': 'rice',
      'lat': 23.86,
      'lon': 90.27,
      'weather_provider': 'mock',
      'weather': [
        for (var i = 0; i < 5; i++)
          {'day': '2026-10-0${6 + i}', 't_min': 24, 't_max': 31, 't_mean': 27, 'rh_mean': 88, 'rh_max': 96, 'rain_mm': 0, 'wet_hours': 8}
      ],
      'diseases': [
        {
          'disease_id': 'rice_blast', 'disease_name': 'Rice blast',
          'summary': {'peak_risk': 0.6, 'peak_level': 'high', 'peak_day': '2026-10-08', 'mean_risk': 0.45, 'overall_level': 'moderate'},
          'daily_risk': [0.3, 0.4, 0.6, 0.5, 0.4], 'action': 'Apply a preventive spray.'
        },
      ],
    };

List<Map<String, dynamic>> sampleAlertsJson() => [
      {
        'disease_id': 'rice_sheath_blight', 'disease_name': 'Sheath blight', 'crop': 'rice', 'reports': 3, 'nearest_km': 2.4,
        'message': 'Sheath blight reported on 3 farm(s) within 10 km of you in the last 14 days.',
        'recommended_action': 'Treat within 48 hours.'
      }
    ];

http.Response jsonResponse(dynamic body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Builds a [MockClient] that routes requests by path.
http.Client fakeApiClient({Map<String, dynamic Function(http.Request)>? overrides}) {
  return MockClient((req) async {
    final path = req.url.path;
    final handler = overrides?[path];
    if (handler != null) return jsonResponse(handler(req));
    dynamic body;
    switch (path) {
      case '/api/v1/health':
        body = {'status': 'ok', 'version': 'test', 'weather_provider': 'mock'};
      case '/api/v1/catalog':
        body = sampleCatalogJson();
      case '/api/v1/farmers':
        body = sampleFarmerJson();
      case '/api/v1/farmers/frm_1/diagnoses':
        body = [sampleDiagnosisJson()];
      case '/api/v1/diagnose':
        body = sampleDiagnosisJson();
      case '/api/v1/diagnoses/dx_test1':
        body = sampleDiagnosisJson();
      case '/api/v1/forecast/crop':
        body = sampleCropForecastJson();
      case '/api/v1/outbreaks/alerts':
        body = sampleAlertsJson();
      case '/api/v1/outbreaks':
        body = [
          {'lat': 23.875, 'lon': 90.275, 'reports': 3, 'dominant_disease_id': 'rice_sheath_blight', 'dominant_disease_name': 'Sheath blight',
           'max_severity': 'high', 'distance_km': 1.7, 'last_report_at': '2026-10-05T10:00:00+00:00'}
        ];
      case '/api/v1/dealers/nearby':
        body = [
          {'id': 'd1', 'name': 'Krishi Bandhu Agro Store', 'address': 'Savar Bazar', 'phone': '+88017', 'lat': 23.85, 'lon': 90.26,
           'distance_km': 1.2, 'opening_hours': '08:00-20:00', 'currency': 'BDT',
           'items': [{'treatment_id': 'rb_chem_tricyclazole', 'product': 'Tricyclazole 75 WP', 'in_stock': true, 'stock_qty': 25, 'price_local': 5600}]}
        ];
      case '/api/v1/agronomist/queue':
        body = [sampleDiagnosisJson(routed: true)];
      case '/api/v1/ledger/entries':
        body = req.method == 'POST'
            ? {'id': 'led_1', 'farmer_id': 'frm_1', 'diagnosis_id': 'dx_test1', 'treatment_id': 'rb_chem_tricyclazole', 'disease_id': 'rice_blast',
               'crop': 'rice', 'field_size_ha': 1.5, 'cost_local': 5184, 'loss_averted_local': 62208, 'currency': 'BDT',
               'applied_on': '2026-10-06', 'created_at': '2026-10-06T00:00:00+00:00'}
            : [
                {'id': 'led_1', 'farmer_id': 'frm_1', 'diagnosis_id': 'dx_test1', 'treatment_id': 'rb_chem_tricyclazole', 'disease_id': 'rice_blast',
                 'crop': 'rice', 'field_size_ha': 1.5, 'cost_local': 5184, 'loss_averted_local': 62208, 'currency': 'BDT',
                 'applied_on': '2026-10-06', 'created_at': '2026-10-06T00:00:00+00:00'}
              ];
      case '/api/v1/ledger/summary':
        body = {'farmer_id': 'frm_1', 'entries': 1, 'total_cost_local': 5184, 'total_loss_averted_local': 62208, 'net_value_local': 57024,
                'currency': 'BDT', 'by_disease': {}};
      default:
        return jsonResponse({'detail': 'not found: $path'}, 404);
    }
    return jsonResponse(body);
  });
}
