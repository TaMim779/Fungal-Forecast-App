import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fungal_forecast/app/app.dart';
import 'package:fungal_forecast/core/api/api_client.dart';
import 'package:fungal_forecast/core/models/models.dart';
import 'package:fungal_forecast/core/services/tts_service.dart';
import 'package:fungal_forecast/core/state/app_state.dart';
import 'package:fungal_forecast/core/state/home_controller.dart';
import 'package:fungal_forecast/core/storage/local_store.dart';
import 'package:fungal_forecast/features/diagnose/result_screen.dart';
import 'package:fungal_forecast/features/outbreaks/outbreak_map_screen.dart';
import 'package:fungal_forecast/features/settings/settings_screen.dart';
import 'package:fungal_forecast/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_api.dart';

Future<LocalStore> storeWith({String lang = 'en', bool withFarmer = true}) async {
  SharedPreferences.setMockInitialValues({
    'lang': lang,
    if (withFarmer) 'farmer': jsonEncode(sampleFarmerJson()),
    if (withFarmer) 'auth_token': 'test-token',
  });
  return LocalStore.open();
}

Widget harness({required LocalStore store, required Widget child, String lang = 'en'}) {
  final app = AppState(store: store, api: ApiClient(baseUrl: 'http://x', client: fakeApiClient()));
  app.init(); // health check + catalogue, as the real app does on start-up
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider.value(value: HomeController(app: app, store: store)),
      ChangeNotifierProvider.value(value: TtsService()),
    ],
    child: MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots to home and shows outlook, alerts and recent diagnoses', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = await storeWith();
    await tester.pumpWidget(FungalForecastApp(
      store: store,
      apiClient: ApiClient(baseUrl: 'http://x', client: fakeApiClient()),
      tts: TtsService(),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data?.contains('Rahim') ?? false),
      ),
      findsWidgets,
    );
    expect(find.text('Scan a leaf'), findsOneWidget);
    expect(find.text('5-day risk outlook for your Rice'), findsOneWidget);
    expect(find.textContaining('Sheath blight'), findsWidgets); // community alert
    expect(find.text('Rice blast'), findsWidgets); // outlook row + recent diagnosis

    // Bottom navigation works.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Farmer profile'), findsOneWidget);
  });

  testWidgets('settings shows server connectivity and profile fields', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000); // tall so the whole form is built
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = await storeWith();
    await tester.pumpWidget(harness(store: store, child: const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Farmer profile'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Rahim'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Field officer mode'), findsOneWidget);
  });

  testWidgets('home renders in Bengali when language is bn', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = await storeWith(lang: 'bn');
    await tester.pumpWidget(FungalForecastApp(
      store: store,
      apiClient: ApiClient(baseUrl: 'http://x', client: fakeApiClient()),
      tts: TtsService(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('পাতা স্ক্যান করুন'), findsOneWidget);
    expect(find.text('হোম'), findsOneWidget);
  });

  testWidgets('result screen shows diagnosis, risk forecast and costed plan', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = await storeWith();
    final dx = Diagnosis.fromJson(sampleDiagnosisJson());
    await tester.pumpWidget(harness(store: store, child: ResultScreen(diagnosisId: dx.id, initial: dx)));
    await tester.pumpAndSettle();

    expect(find.text('Rice blast'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    expect(find.text('5-day infection risk'), findsWidgets); // header stat + section title
    expect(find.text('Treat within 48 hours.'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Tricyclazole 75 WP'), 300);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Trichoderma viride'), findsOneWidget);
    expect(find.text('৳5,184'), findsOneWidget); // cost in local currency
    expect(find.text('Stop 21 days before harvest'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('I applied this'), 300);
    await tester.ensureVisible(find.text('I applied this'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'I applied this'));
    await tester.pumpAndSettle();
    expect(find.text('Saved to your impact ledger'), findsWidgets);
  });

  testWidgets('result screen flags agronomist review for low-confidence cases', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = await storeWith();
    final dx = Diagnosis.fromJson(sampleDiagnosisJson(routed: true));
    await tester.pumpWidget(harness(store: store, child: ResultScreen(diagnosisId: dx.id, initial: dx)));
    await tester.pumpAndSettle();
    expect(find.textContaining('agronomist will double-check'), findsOneWidget);
  });

  testWidgets('outbreak map lists nearby cells and alerts', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = await storeWith();
    await tester.pumpWidget(harness(store: store, child: const OutbreakMapScreen(showMapTiles: false)));
    await tester.pumpAndSettle();
    expect(find.text('Community outbreak map'), findsOneWidget);
    expect(find.text('3 reports · 1.7 km away'), findsOneWidget);
    expect(find.textContaining('within 10 km'), findsOneWidget);
  });

  testWidgets('outbreak map asks for location when farmer has none', (tester) async {
    final store = await storeWith(withFarmer: false);
    await tester.pumpWidget(harness(store: store, child: const OutbreakMapScreen(showMapTiles: false)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Set your field location'), findsOneWidget);
  });

  testWidgets('logged-out users land on login', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = await storeWith(withFarmer: false);
    await tester.pumpWidget(FungalForecastApp(
      store: store,
      apiClient: ApiClient(baseUrl: 'http://x', client: fakeApiClient()),
      tts: TtsService(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsWidgets);
    expect(find.text('New here? Create an account'), findsOneWidget);
  });
}
