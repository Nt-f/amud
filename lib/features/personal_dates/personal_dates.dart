import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../alerts/alerts.dart';
import '../home/today.dart';

enum PersonalDateKind { yahrzeit, birthday, barMitzvah }

class PersonalDate {
  final String id;
  final String name;
  final PersonalDateKind kind;
  final HDate date;
  final bool reminder;
  final bool eveningBefore;
  const PersonalDate({
    required this.id,
    required this.name,
    required this.kind,
    required this.date,
    this.reminder = true,
    this.eveningBefore = true,
  });

  /// Bar mitzvah dates are entered as the birth date. The anniversary is the
  /// thirteenth Hebrew birthday; the associated parsha follows that date.
  HDate? occurrence(int year) {
    if (kind == PersonalDateKind.yahrzeit) return getYahrzeit(year, date);
    if (kind == PersonalDateKind.barMitzvah && year < date.getFullYear() + 13) {
      return null;
    }
    return getBirthdayOrAnniversary(year, date);
  }

  HDate? nextOccurrence(HDate today) {
    final start =
        kind == PersonalDateKind.barMitzvah &&
            today.getFullYear() < date.getFullYear() + 13
        ? date.getFullYear() + 13
        : today.getFullYear();
    for (var year = start; year <= start + 2; year++) {
      final next = occurrence(year);
      if (next != null && next.abs() >= today.abs()) return next;
    }
    return null;
  }

  String? parsha(HDate occurrence, bool il) =>
      kind == PersonalDateKind.barMitzvah
      ? upcomingParsha(occurrence, il, 'en').name
      : null;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'date': date.abs(),
    'reminder': reminder,
    'eveningBefore': eveningBefore,
  };
  factory PersonalDate.fromJson(Map<String, Object?> json) => PersonalDate(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: PersonalDateKind.values.byName(json['kind'] as String),
    date: HDate.fromAbs((json['date'] as num).toInt()),
    reminder: json['reminder'] != false,
    eveningBefore: json['eveningBefore'] != false,
  );
}

class PersonalDatesNotifier extends Notifier<List<PersonalDate>> {
  @override
  List<PersonalDate> build() =>
      ref
          .watch(storageProvider)
          .readJson(
            'personalDates',
            (json) => [
              for (final value in json as List)
                PersonalDate.fromJson((value as Map).cast<String, Object?>()),
            ],
          ) ??
      const [];
  void _save(List<PersonalDate> dates) {
    state = dates;
    ref
        .read(storageProvider)
        .writeJson('personalDates', dates.map((d) => d.toJson()).toList());
  }

  void upsert(PersonalDate date) =>
      _save([...state.where((d) => d.id != date.id), date]);
  void remove(String id) => _save(state.where((d) => d.id != id).toList());
}

final personalDatesProvider =
    NotifierProvider<PersonalDatesNotifier, List<PersonalDate>>(
      PersonalDatesNotifier.new,
    );

List<PlannedNotification> planPersonalDates(
  List<PersonalDate> dates,
  AppSettings settings,
  DateTime now, {
  int days = 366,
}) {
  final loc = settings.location.toLocation();
  final local = tz.TZDateTime.from(now, loc.tzLocation);
  final year = HDate.fromDate(local).getFullYear();
  final end = now.add(Duration(days: days));
  final out = <PlannedNotification>[];
  for (final date in dates.where((d) => d.reminder)) {
    for (var y = year; y <= year + 2; y++) {
      final occurrence = date.occurrence(y);
      if (occurrence == null) continue;
      final civil = occurrence.plainDate();
      DateTime? fire;
      if (date.eveningBefore) {
        fire = Zmanim(loc, civil.addDays(-1), settings.useElevation).sunset();
      } else {
        fire = tz.TZDateTime(
          loc.tzLocation,
          civil.year,
          civil.month,
          civil.day,
          9,
        );
      }
      if (fire == null || !fire.isAfter(now) || !fire.isBefore(end)) continue;
      final parsha = date.parsha(occurrence, settings.location.il);
      final label = switch (date.kind) {
        PersonalDateKind.yahrzeit => 'Yahrzeit',
        PersonalDateKind.birthday => 'Hebrew birthday',
        PersonalDateKind.barMitzvah => 'Bar mitzvah anniversary',
      };
      out.add(
        PlannedNotification(
          notificationId('personal:${date.id}', civil),
          fire,
          '${date.name} · $label',
          '${occurrence.render('en')}${parsha == null ? '' : ' · $parsha'}',
          'personal:${date.id}',
          route: '/personal-dates',
        ),
      );
    }
  }
  return out;
}
