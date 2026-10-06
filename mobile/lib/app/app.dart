import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api/api_client.dart';
import '../core/services/tts_service.dart';
import '../core/state/app_state.dart';
import '../core/state/home_controller.dart';
import '../core/storage/local_store.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

class FungalForecastApp extends StatefulWidget {
  const FungalForecastApp({super.key, required this.store, this.apiClient, this.tts});
  final LocalStore store;
  final ApiClient? apiClient;
  final TtsService? tts;

  @override
  State<FungalForecastApp> createState() => _FungalForecastAppState();
}

class _FungalForecastAppState extends State<FungalForecastApp> {
  late final AppState _app;
  late final HomeController _home;
  late final TtsService _tts;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final api = widget.apiClient ?? ApiClient(baseUrl: widget.store.apiUrl);
    _app = AppState(store: widget.store, api: api);
    _home = HomeController(app: _app, store: widget.store);
    _tts = widget.tts ?? TtsService();
    _router = buildRouter(_app);
    _app.init();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _app),
        ChangeNotifierProvider.value(value: _home),
        ChangeNotifierProvider.value(value: _tts),
      ],
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp.router(
          title: 'FungalForecast',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          locale: app.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: _router,
        ),
      ),
    );
  }
}
