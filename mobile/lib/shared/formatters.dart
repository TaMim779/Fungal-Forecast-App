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

/// 5–11: morning, 12–15: afternoon, 16–18: evening, otherwise night.
enum DayPeriod { morning, afternoon, evening, night }

DayPeriod dayPeriod([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour >= 5 && hour < 12) return DayPeriod.morning;
  if (hour >= 12 && hour < 16) return DayPeriod.afternoon;
  if (hour >= 16 && hour < 19) return DayPeriod.evening;
  return DayPeriod.night;
}

String greetingFor(AppLocalizations l, String name, [DateTime? now]) => switch (dayPeriod(now)) {
      DayPeriod.morning => l.greetingMorning(name),
      DayPeriod.afternoon => l.greetingAfternoon(name),
      DayPeriod.evening => l.greetingEvening(name),
      DayPeriod.night => l.greetingNight(name),
    };
