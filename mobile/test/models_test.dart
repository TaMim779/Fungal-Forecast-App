import 'package:flutter_test/flutter_test.dart';
import 'package:fungal_forecast/core/models/models.dart';
import 'package:fungal_forecast/shared/formatters.dart';

import 'helpers/fake_api.dart';

void main() {
  group('Diagnosis model', () {
    test('parses the full API payload', () {
      final dx = Diagnosis.fromJson(sampleDiagnosisJson());
      expect(dx.id, 'dx_test1');
      expect(dx.isHealthy, isFalse);
      expect(dx.confidence, closeTo(0.87, 1e-9));
      expect(dx.forecast!.days, hasLength(5));
      expect(dx.forecast!.overallLevel, 'high');
      expect(dx.riskLevel, 'high');
      expect(dx.plan!.currencySymbol, '৳');
      expect(dx.plan!.recommended!.treatmentId, 'rb_chem_tricyclazole');
      expect(dx.plan!.options.first.isOrganic, isTrue);
      expect(dx.alternatives, hasLength(1));
      expect(dx.raw, isNotNull);
    });

    test('healthy diagnosis has no plan and low risk', () {
      final j = sampleDiagnosisJson()
        ..['disease_id'] = 'healthy'
        ..['forecast'] = null
        ..['plan'] = null;
      final dx = Diagnosis.fromJson(j);
      expect(dx.isHealthy, isTrue);
      expect(dx.plan, isNull);
      expect(dx.riskLevel, 'low');
    });

    test('tolerates missing optional fields', () {
      final dx = Diagnosis.fromJson({'id': 'x', 'disease_id': 'rice_blast', 'confidence': '0.5'});
      expect(dx.confidence, 0.5);
      expect(dx.severity, 'none');
      expect(dx.riskLevel, 'moderate');
    });
  });

  test('Farmer round-trips through JSON', () {
    final f = Farmer.fromJson(sampleFarmerJson());
    final again = Farmer.fromJson(f.toJson());
    expect(again.id, f.id);
    expect(again.hasLocation, isTrue);
    expect(again.fieldSizeHa, 1.5);
  });

  test('Catalog resolves crop names with fallback', () {
    final c = Catalog.fromJson(sampleCatalogJson());
    expect(c.cropName('rice'), 'Rice');
    expect(c.cropName('banana'), 'banana');
    expect(Catalog.fallback.crops.map((c) => c.id), contains('potato'));
  });

  test('CropForecast keeps raw JSON for offline caching', () {
    final fc = CropForecast.fromJson(sampleCropForecastJson());
    expect(fc.diseases.single.dailyRisk, hasLength(5));
    expect(fc.raw, isNotNull);
  });

  test('dayPeriod follows morning, afternoon, evening and night windows', () {
    DateTime at(int hour) => DateTime(2026, 10, 6, hour);
    expect(dayPeriod(at(5)), DayPeriod.morning);
    expect(dayPeriod(at(11)), DayPeriod.morning);
    expect(dayPeriod(at(12)), DayPeriod.afternoon);
    expect(dayPeriod(at(15)), DayPeriod.afternoon);
    expect(dayPeriod(at(16)), DayPeriod.evening);
    expect(dayPeriod(at(18)), DayPeriod.evening);
    expect(dayPeriod(at(19)), DayPeriod.night);
    expect(dayPeriod(at(0)), DayPeriod.night);
    expect(dayPeriod(at(4)), DayPeriod.night);
  });
}
