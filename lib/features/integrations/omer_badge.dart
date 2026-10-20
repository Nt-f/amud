import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';

class OmerCounted extends Notifier<int?> {
  @override
  int? build() => ref
      .watch(storageProvider)
      .readJson<int?>('omerCounted', (j) => j is int ? j : null);
  void mark(int day) {
    state = day;
    ref.read(storageProvider).writeJson('omerCounted', day);
  }
}

final omerCountedProvider = NotifierProvider<OmerCounted, int?>(
  OmerCounted.new,
);

/// The Hebrew year whose Omer last asked to turn the reminder on, so
/// tapping the Omer card asks once a season.
class OmerReminderAsked extends Notifier<int?> {
  @override
  int? build() => ref
      .watch(storageProvider)
      .readJson<int?>('omerReminderAsked', (j) => j is int ? j : null);
  void mark(int year) {
    state = year;
    ref.read(storageProvider).writeJson('omerReminderAsked', year);
  }
}

final omerReminderAskedProvider = NotifierProvider<OmerReminderAsked, int?>(
  OmerReminderAsked.new,
);
