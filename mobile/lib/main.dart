import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'core/storage/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([initializeDateFormatting('bn'), initializeDateFormatting('hi')]);
  final store = await LocalStore.open();
  runApp(FungalForecastApp(store: store));
}
