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
