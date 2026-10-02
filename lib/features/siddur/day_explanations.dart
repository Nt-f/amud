import 'package:siddur_engine/siddur_engine.dart';
import 'today_summary.dart';

/// Explanations of the summary's calendar decisions; the reader's own
/// section and line rules remain authoritative for each text version.
String explainDayChange(
  LiturgyChange change,
  DayContext day,
  DayContext mincha,
  DayContext night,
) {
  final name = change.en;
  if (name.contains('Ya\'aleh')) {
    return day['roshChodesh']
        ? 'Today is Rosh Chodesh, so Ya’aleh VeYavo is added.'
        : 'Today is Chol HaMoed, so Ya’aleh VeYavo is added.';
  }
  if (name.contains('Chanukah')) {
    return 'Today is Chanukah. Al HaNissim gives thanks for the deliverance commemorated on these days.';
  }
  if (name.contains('Purim')) {
    return 'Today is Purim according to your selected walled-city custom.';
  }
  if (name.contains('Hallel')) {
    return '${day['wholeHallel'] ? 'Whole' : 'Half'} Hallel applies to today’s calendar observance: ${day.labels.join(', ')}. The siddur’s rules determine which passages appear.';
  }
  if (name.contains('Teshuva')) {
    return 'Today falls within the Ten Days of Repentance, from Rosh Hashana through Yom Kippur.';
  }
  if (name.contains('Avinu')) {
    return 'The calendar marks Avinu Malkeinu for this weekday during the Ten Days of Repentance or a public fast.';
  }
  if (name.contains('Aneinu')) {
    return 'Today is a public fast. The siddur’s instructions distinguish the individual’s prayer from the chazzan’s repetition.';
  }
  if (name == 'Musaf') {
    return 'An additional service is included for ${day['shabbat']
        ? 'Shabbat'
        : day['roshChodesh']
        ? 'Rosh Chodesh'
        : day['cholHamoed']
        ? 'Chol HaMoed'
        : 'Yom Tov'}.';
  }
  if (name == 'Torah reading') {
    return day['roshChodesh'] ||
            day['publicFast'] ||
            day['chanukah'] ||
            day['purim'] ||
            day['yomTov'] ||
            day['cholHamoed']
        ? 'Today’s special observance includes a Torah reading: ${day.labels.join(', ')}.'
        : 'Today is Monday or Thursday, when the weekday Torah reading is included.';
  }
  if (name.contains('Tachanun')) {
    final customs = day.minhagim;
    if (customs.houseOfMourning) {
      return 'Your selected custom marks prayer in a house of mourning, so Tachanun is omitted.';
    }
    if (customs.bris || customs.chatan) {
      return 'Your selected custom marks a bris or a chatan in the congregation, so Tachanun is omitted.';
    }
    if (name.contains('Mincha')) {
      return 'Tachanun is omitted at Mincha before a day on which it is not said, according to the calendar rules.';
    }
    return 'The calendar omits Tachanun on this date${day.labels.isEmpty ? '' : ': ${day.labels.join(', ')}'}. Some omissions apply throughout a festive month or period even without a holiday label.';
  }
  if (name.contains('LeDavid')) {
    return 'Your selected custom includes Psalm 27 during Elul and the autumn holidays, ending ${day.minhagim.ledavidThroughShminiAtzeret ? 'on Shmini Atzeret' : 'on Hoshana Raba'}.';
  }
  if (name.contains('Mashiv') || name.contains('Morid')) {
    return '${day['mashivHaruach'] ? 'The winter mention of rain' : 'The summer wording'} applies. The switch occurs at Musaf of Shmini Atzeret or the first day of Pesach; each service is resolved separately. Wording also depends on nusach.';
  }
  if (name.contains('tal u') || name.contains('bracha')) {
    return day['talUmatar']
        ? 'The rain-request season is active for your selected ${day.il ? 'Israel' : 'diaspora'} location.'
        : 'The rain-request season is not active for your selected ${day.il ? 'Israel' : 'diaspora'} location, so the summer request appears.';
  }
  if (name.contains('Omer')) {
    return 'The evening following this civil date is day ${night.number('omerDay').toInt()} of the Omer. Maariv uses the next Hebrew date.';
  }
  if (name.contains('Chonantanu')) {
    return 'The evening following this date is after Shabbat; Maariv includes the weekday transition and Havdalah.';
  }
  if (name.contains('Levana')) {
    return 'The date falls within the moon-blessing window for your selected three-day or seven-day custom.';
  }
  if (name.contains('Eruv')) {
    return 'Yom Tov leads into Shabbat in this calendar configuration, so preparation is marked today.';
  }
  if (name == 'Yizkor') {
    return 'The calendar marks Yizkor for this festival day, using your Israel or diaspora setting.';
  }
  if (name.contains('Kinot')) {
    return 'Today is the observed fast of Tisha B’Av. The siddur includes its special passages and Nachem at Mincha.';
  }
  return 'Based on the calendar, location, and customs selected in Amud.';
}
