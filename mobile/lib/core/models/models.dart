/// Data models mirroring the FungalForecast API contract (backend/app/schemas.py).
library;

double _d(dynamic v, [double fallback = 0]) =>
    v == null ? fallback : (v is num ? v.toDouble() : double.tryParse('$v') ?? fallback);
int _i(dynamic v, [int fallback = 0]) =>
    v == null ? fallback : (v is num ? v.toInt() : int.tryParse('$v') ?? fallback);
String _s(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;

class Farmer {
  const Farmer({
    required this.id,
    required this.name,
    required this.phone,
    required this.language,
    required this.country,
    required this.crop,
    required this.fieldSizeHa,
    this.lat,
    this.lon,
  });

  final String id;
  final String name;
  final String phone;
  final String language;
  final String country;
  final String crop;
  final double fieldSizeHa;
  final double? lat;
  final double? lon;

  bool get hasLocation => lat != null && lon != null;

  factory Farmer.fromJson(Map<String, dynamic> j) => Farmer(
        id: _s(j['id']),
        name: _s(j['name']),
        phone: _s(j['phone']),
        language: _s(j['language'], 'en'),
        country: _s(j['country'], 'BD'),
        crop: _s(j['crop'], 'rice'),
        fieldSizeHa: _d(j['field_size_ha'], 1),
        lat: j['lat'] == null ? null : _d(j['lat']),
        lon: j['lon'] == null ? null : _d(j['lon']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'language': language,
        'country': country,
        'crop': crop,
        'field_size_ha': fieldSizeHa,
        'lat': lat,
        'lon': lon,
      };
}

class CatalogCrop {
  const CatalogCrop({required this.id, required this.name});
  final String id;
  final String name;
  factory CatalogCrop.fromJson(Map<String, dynamic> j) =>
      CatalogCrop(id: _s(j['id']), name: _s(j['name']));
}

class CatalogDisease {
  const CatalogDisease({required this.id, required this.crop, required this.name, required this.symptoms});
  final String id;
  final String crop;
  final String name;
  final String symptoms;
  factory CatalogDisease.fromJson(Map<String, dynamic> j) => CatalogDisease(
      id: _s(j['id']), crop: _s(j['crop']), name: _s(j['name']), symptoms: _s(j['symptoms']));
}

class Catalog {
  const Catalog({required this.crops, required this.diseases});
  final List<CatalogCrop> crops;
  final List<CatalogDisease> diseases;

  static const fallback = Catalog(crops: [
    CatalogCrop(id: 'rice', name: 'Rice'),
    CatalogCrop(id: 'wheat', name: 'Wheat'),
    CatalogCrop(id: 'maize', name: 'Maize'),
    CatalogCrop(id: 'tomato', name: 'Tomato'),
    CatalogCrop(id: 'potato', name: 'Potato'),
  ], diseases: []);

  factory Catalog.fromJson(Map<String, dynamic> j) => Catalog(
        crops: (j['crops'] as List? ?? []).map((e) => CatalogCrop.fromJson(e)).toList(),
        diseases: (j['diseases'] as List? ?? []).map((e) => CatalogDisease.fromJson(e)).toList(),
      );

  String cropName(String id) => crops.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? id;
}

class DailyWeather {
  const DailyWeather({
    required this.day,
    required this.tMin,
    required this.tMax,
    required this.rhMean,
    required this.rainMm,
    required this.wetHours,
  });
  final String day;
  final double tMin;
  final double tMax;
  final double rhMean;
  final double rainMm;
  final int wetHours;
  factory DailyWeather.fromJson(Map<String, dynamic> j) => DailyWeather(
        day: _s(j['day']),
        tMin: _d(j['t_min']),
        tMax: _d(j['t_max']),
        rhMean: _d(j['rh_mean']),
        rainMm: _d(j['rain_mm']),
        wetHours: _i(j['wet_hours']),
      );
}

class DayRisk {
  const DayRisk({required this.day, required this.risk, required this.level, required this.weather});
  final String day;
  final double risk;
  final String level;
  final DailyWeather weather;
  factory DayRisk.fromJson(Map<String, dynamic> j) => DayRisk(
        day: _s(j['day']),
        risk: _d(j['risk']),
        level: _s(j['level'], 'low'),
        weather: DailyWeather.fromJson(j['weather'] as Map<String, dynamic>? ?? {}),
      );
}

class Forecast {
  const Forecast({
    required this.diseaseId,
    required this.diseaseName,
    required this.days,
    required this.overallLevel,
    required this.peakLevel,
    required this.peakRisk,
    required this.action,
    required this.weatherProvider,
  });
  final String diseaseId;
  final String diseaseName;
  final List<DayRisk> days;
  final String overallLevel;
  final String peakLevel;
  final double peakRisk;
  final String action;
  final String weatherProvider;

  factory Forecast.fromJson(Map<String, dynamic> j) {
    final summary = j['summary'] as Map<String, dynamic>? ?? {};
    return Forecast(
      diseaseId: _s(j['disease_id']),
      diseaseName: _s(j['disease_name']),
      days: (j['days'] as List? ?? []).map((e) => DayRisk.fromJson(e)).toList(),
      overallLevel: _s(summary['overall_level'], 'low'),
      peakLevel: _s(summary['peak_level'], 'low'),
      peakRisk: _d(summary['peak_risk']),
      action: _s(j['action']),
      weatherProvider: _s(j['weather_provider']),
    );
  }
}

/// Compact per-disease outlook used by the home screen.
class CropRiskItem {
  const CropRiskItem({
    required this.diseaseId,
    required this.diseaseName,
    required this.overallLevel,
    required this.peakRisk,
    required this.dailyRisk,
    required this.action,
  });
  final String diseaseId;
  final String diseaseName;
  final String overallLevel;
  final double peakRisk;
  final List<double> dailyRisk;
  final String action;
  factory CropRiskItem.fromJson(Map<String, dynamic> j) {
    final s = j['summary'] as Map<String, dynamic>? ?? {};
    return CropRiskItem(
      diseaseId: _s(j['disease_id']),
      diseaseName: _s(j['disease_name']),
      overallLevel: _s(s['overall_level'], 'low'),
      peakRisk: _d(s['peak_risk']),
      dailyRisk: (j['daily_risk'] as List? ?? []).map((e) => _d(e)).toList(),
      action: _s(j['action']),
    );
  }
}

class CropForecast {
  const CropForecast({required this.crop, required this.weather, required this.diseases, this.raw});
  final String crop;
  final List<DailyWeather> weather;
  final List<CropRiskItem> diseases;
  final Map<String, dynamic>? raw;
  factory CropForecast.fromJson(Map<String, dynamic> j) => CropForecast(
        crop: _s(j['crop']),
        weather: (j['weather'] as List? ?? []).map((e) => DailyWeather.fromJson(e)).toList(),
        diseases: (j['diseases'] as List? ?? []).map((e) => CropRiskItem.fromJson(e)).toList(),
        raw: j,
      );
}

class TreatmentOption {
  const TreatmentOption({
    required this.treatmentId,
    required this.type,
    required this.product,
    required this.unit,
    required this.quantityPerApplication,
    required this.applications,
    required this.intervalDays,
    required this.totalQuantity,
    required this.preHarvestIntervalDays,
    required this.costLocal,
    required this.valueProtectedLocal,
    required this.netBenefitLocal,
    required this.roi,
    required this.notes,
  });
  final String treatmentId;
  final String type;
  final String product;
  final String unit;
  final double quantityPerApplication;
  final int applications;
  final int intervalDays;
  final double totalQuantity;
  final int preHarvestIntervalDays;
  final double costLocal;
  final double valueProtectedLocal;
  final double netBenefitLocal;
  final double? roi;
  final String notes;
  bool get isOrganic => type == 'organic';

  factory TreatmentOption.fromJson(Map<String, dynamic> j) => TreatmentOption(
        treatmentId: _s(j['treatment_id']),
        type: _s(j['type'], 'organic'),
        product: _s(j['product']),
        unit: _s(j['unit']),
        quantityPerApplication: _d(j['quantity_per_application']),
        applications: _i(j['applications'], 1),
        intervalDays: _i(j['interval_days']),
        totalQuantity: _d(j['total_quantity']),
        preHarvestIntervalDays: _i(j['pre_harvest_interval_days']),
        costLocal: _d(j['cost_local']),
        valueProtectedLocal: _d(j['value_protected_local']),
        netBenefitLocal: _d(j['net_benefit_local']),
        roi: j['roi'] == null ? null : _d(j['roi']),
        notes: _s(j['notes']),
      );
}

class TreatmentPlan {
  const TreatmentPlan({
    required this.diseaseId,
    required this.diseaseName,
    required this.fieldSizeHa,
    required this.currencyCode,
    required this.currencySymbol,
    required this.expectedLossLocal,
    required this.recommendedTreatmentId,
    required this.options,
  });
  final String diseaseId;
  final String diseaseName;
  final double fieldSizeHa;
  final String currencyCode;
  final String currencySymbol;
  final double expectedLossLocal;
  final String recommendedTreatmentId;
  final List<TreatmentOption> options;

  TreatmentOption? get recommended =>
      options.where((o) => o.treatmentId == recommendedTreatmentId).firstOrNull;

  factory TreatmentPlan.fromJson(Map<String, dynamic> j) {
    final cur = j['currency'] as Map<String, dynamic>? ?? {};
    return TreatmentPlan(
      diseaseId: _s(j['disease_id']),
      diseaseName: _s(j['disease_name']),
      fieldSizeHa: _d(j['field_size_ha'], 1),
      currencyCode: _s(cur['code'], 'USD'),
      currencySymbol: _s(cur['symbol'], r'$'),
      expectedLossLocal: _d(j['expected_loss_local']),
      recommendedTreatmentId: _s(j['recommended_treatment_id']),
      options: (j['options'] as List? ?? []).map((e) => TreatmentOption.fromJson(e)).toList(),
    );
  }
}

class Diagnosis {
  const Diagnosis({
    required this.id,
    required this.crop,
    required this.diseaseId,
    required this.diseaseName,
    required this.pathogen,
    required this.symptoms,
    required this.confidence,
    required this.severity,
    required this.status,
    required this.routedToAgronomist,
    required this.alternatives,
    required this.forecast,
    required this.plan,
    required this.explanation,
    required this.createdAt,
    this.farmerId,
    this.lat,
    this.lon,
    this.raw,
  });
  final String id;
  final String? farmerId;
  final String crop;
  final String diseaseId;
  final String diseaseName;
  final String? pathogen;
  final String symptoms;
  final double confidence;
  final String severity;
  final String status;
  final bool routedToAgronomist;
  final List<Map<String, dynamic>> alternatives;
  final Forecast? forecast;
  final TreatmentPlan? plan;
  final String explanation;
  final String createdAt;
  final double? lat;
  final double? lon;

  /// Original JSON, kept so results can be cached offline without re-serialising.
  final Map<String, dynamic>? raw;

  bool get isHealthy => diseaseId == 'healthy';
  String get riskLevel => forecast?.overallLevel ?? (isHealthy ? 'low' : 'moderate');

  factory Diagnosis.fromJson(Map<String, dynamic> j) => Diagnosis(
        id: _s(j['id']),
        farmerId: j['farmer_id']?.toString(),
        crop: _s(j['crop']),
        diseaseId: _s(j['disease_id']),
        diseaseName: _s(j['disease_name']),
        pathogen: j['pathogen']?.toString(),
        symptoms: _s(j['symptoms']),
        confidence: _d(j['confidence']),
        severity: _s(j['severity'], 'none'),
        status: _s(j['status'], 'confirmed'),
        routedToAgronomist: j['routed_to_agronomist'] == true,
        alternatives: (j['alternatives'] as List? ?? []).cast<Map<String, dynamic>>(),
        forecast: j['forecast'] == null ? null : Forecast.fromJson(j['forecast']),
        plan: j['plan'] == null ? null : TreatmentPlan.fromJson(j['plan']),
        explanation: _s(j['explanation']),
        createdAt: _s(j['created_at']),
        lat: j['lat'] == null ? null : _d(j['lat']),
        lon: j['lon'] == null ? null : _d(j['lon']),
        raw: j,
      );
}

class OutbreakCell {
  const OutbreakCell({
    required this.lat,
    required this.lon,
    required this.reports,
    required this.diseaseId,
    required this.diseaseName,
    required this.maxSeverity,
    required this.distanceKm,
    required this.lastReportAt,
  });
  final double lat;
  final double lon;
  final int reports;
  final String diseaseId;
  final String diseaseName;
  final String maxSeverity;
  final double distanceKm;
  final String lastReportAt;
  factory OutbreakCell.fromJson(Map<String, dynamic> j) => OutbreakCell(
        lat: _d(j['lat']),
        lon: _d(j['lon']),
        reports: _i(j['reports']),
        diseaseId: _s(j['dominant_disease_id']),
        diseaseName: _s(j['dominant_disease_name']),
        maxSeverity: _s(j['max_severity'], 'low'),
        distanceKm: _d(j['distance_km']),
        lastReportAt: _s(j['last_report_at']),
      );
}

class OutbreakAlert {
  const OutbreakAlert({
    required this.diseaseId,
    required this.diseaseName,
    required this.crop,
    required this.reports,
    required this.nearestKm,
    required this.message,
    required this.recommendedAction,
  });
  final String diseaseId;
  final String diseaseName;
  final String crop;
  final int reports;
  final double nearestKm;
  final String message;
  final String recommendedAction;
  factory OutbreakAlert.fromJson(Map<String, dynamic> j) => OutbreakAlert(
        diseaseId: _s(j['disease_id']),
        diseaseName: _s(j['disease_name']),
        crop: _s(j['crop']),
        reports: _i(j['reports']),
        nearestKm: _d(j['nearest_km']),
        message: _s(j['message']),
        recommendedAction: _s(j['recommended_action']),
      );
}

class DealerItem {
  const DealerItem({
    required this.treatmentId,
    required this.product,
    required this.inStock,
    required this.stockQty,
    required this.priceLocal,
  });
  final String treatmentId;
  final String product;
  final bool inStock;
  final int stockQty;
  final double priceLocal;
  factory DealerItem.fromJson(Map<String, dynamic> j) => DealerItem(
        treatmentId: _s(j['treatment_id']),
        product: _s(j['product']),
        inStock: j['in_stock'] == true,
        stockQty: _i(j['stock_qty']),
        priceLocal: _d(j['price_local']),
      );
}

class Dealer {
  const Dealer({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.lat,
    required this.lon,
    required this.distanceKm,
    required this.openingHours,
    required this.currency,
    required this.items,
  });
  final String id;
  final String name;
  final String address;
  final String phone;
  final double lat;
  final double lon;
  final double distanceKm;
  final String openingHours;
  final String currency;
  final List<DealerItem> items;
  bool get hasStock => items.any((i) => i.inStock);
  factory Dealer.fromJson(Map<String, dynamic> j) => Dealer(
        id: _s(j['id']),
        name: _s(j['name']),
        address: _s(j['address']),
        phone: _s(j['phone']),
        lat: _d(j['lat']),
        lon: _d(j['lon']),
        distanceKm: _d(j['distance_km']),
        openingHours: _s(j['opening_hours']),
        currency: _s(j['currency']),
        items: (j['items'] as List? ?? []).map((e) => DealerItem.fromJson(e)).toList(),
      );
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.diseaseId,
    required this.crop,
    required this.treatmentId,
    required this.fieldSizeHa,
    required this.costLocal,
    required this.lossAvertedLocal,
    required this.currency,
    required this.appliedOn,
  });
  final String id;
  final String diseaseId;
  final String crop;
  final String treatmentId;
  final double fieldSizeHa;
  final double costLocal;
  final double lossAvertedLocal;
  final String currency;
  final String appliedOn;
  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: _s(j['id']),
        diseaseId: _s(j['disease_id']),
        crop: _s(j['crop']),
        treatmentId: _s(j['treatment_id']),
        fieldSizeHa: _d(j['field_size_ha']),
        costLocal: _d(j['cost_local']),
        lossAvertedLocal: _d(j['loss_averted_local']),
        currency: _s(j['currency']),
        appliedOn: _s(j['applied_on']),
      );
}

class LedgerSummary {
  const LedgerSummary({
    required this.entries,
    required this.totalCost,
    required this.totalLossAverted,
    required this.netValue,
    required this.currency,
  });
  final int entries;
  final double totalCost;
  final double totalLossAverted;
  final double netValue;
  final String? currency;
  factory LedgerSummary.fromJson(Map<String, dynamic> j) => LedgerSummary(
        entries: _i(j['entries']),
        totalCost: _d(j['total_cost_local']),
        totalLossAverted: _d(j['total_loss_averted_local']),
        netValue: _d(j['net_value_local']),
        currency: j['currency']?.toString(),
      );
}
