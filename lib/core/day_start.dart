import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

import 'settings.dart';

/// Dawn (alot hashachar) by the user's [opinion], as the zmanim list shows
/// it: the app's day starts here, not at midnight.
DateTime? dawnFor(Zmanim z, ZmanimOpinion opinion) => switch (opinion) {
      ZmanimOpinion.gra => z.alotHaShachar(),
      ZmanimOpinion.mga => z.alotHaShachar72(),
      ZmanimOpinion.baalHatanya => z.alosBaalHatanya(),
    };

/// The day at [now]: the wall-clock date at [loc], except that it turns over
/// at dawn, so the hours after midnight still belong to the night before
/// (its Maariv, its zmanim). Where there's no dawn (summer far north), at
/// midnight.
PlainDate dayAt(DateTime now, Location loc, {required bool useElevation, required ZmanimOpinion opinion}) {
  final local = tz.TZDateTime.from(now, loc.tzLocation);
  final date = PlainDate(local.year, local.month, local.day);
  final dawn = dawnFor(Zmanim(loc, date, useElevation), opinion);
  return dawn != null && now.isBefore(dawn) ? date.addDays(-1) : date;
}
