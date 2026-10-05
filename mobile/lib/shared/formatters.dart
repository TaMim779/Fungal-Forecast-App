import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

String money(double value, String symbol, {String locale = 'en'}) {
  final f = NumberFormat.decimalPattern(locale == 'bn' ? 'bn' : locale == 'hi' ? 'hi' : 'en');
  f.maximumFractionDigits = 0;
  return '$symbol${f.format(value)}';
}

String qty(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

String percent(double v) => '${(v * 100).round()}%';

String levelLabel(AppLocalizations l, String level) => switch (level) {
      'low' => l.levelLow,
      'moderate' => l.levelModerate,
      'high' => l.levelHigh,
      'severe' => l.levelSevere,
      'none' => l.sevNone,
      _ => level,
    };

String shortDay(String isoDate, String locale) {
  final d = DateTime.tryParse(isoDate);
  if (d == null) return isoDate;
  return DateFormat.E(locale).format(d);
}

String shortDate(String iso, String locale) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  return DateFormat.MMMd(locale).format(d);
}
