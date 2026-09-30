---
name: amud-js-card
description: Write custom JavaScript cards for the Amud app's Home screen. Use when someone asks for an Amud (siddur app) home card, widget or "custom JS card", e.g. a countdown to a zman, today's learning, a Shabbat summary, or data fetched from a web API such as Sefaria or Hebcal.
---

# Amud custom JS cards

A custom JS card is a small script on Amud's Home screen. The app calls its
`render(ctx)` function with the day's data (Hebrew date, zmanim, holidays,
learning and more) and draws what it returns: a card built from a fixed set
of pieces (text, rows, chips, progress bars). The script never touches the
screen directly.

To add one in the app: **Home → Edit dashboard → Add card → Custom JS card**,
then tap the card's menu → **Configure**. Paste the script, tap **Run
preview**, and save. **API** in the editor shows a short version of this
reference.

## The contract

```js
// Sync or async; the app waits for a returned promise.
async function render(ctx) {
  return {
    title: 'Card title',   // optional; the card's title otherwise
    icon: 'sun',           // optional, see Icons
    children: [ /* nodes */ ]
  };
}
```

- Define `render` at the top level of the script. Anything else in the script
  is fine: helpers, constants and so on.
- Return plain JSON-able data: objects, arrays, strings, numbers, booleans. No
  functions, `Date`s (use `.toISOString()` or format them yourself) or classes.
- A thrown error, or a rejected promise, shows the error message on the card.
- The script runs again every minute, and whenever the day's data changes.
  While a run is going, the card keeps showing the last result.

### Nodes

| Node | Fields |
| --- | --- |
| `{type: 'text', text, style?, color?}` | `style`: `title`, `headline`, `caption` or `hebrew` (the user's Hebrew font). Hebrew text is laid out right to left automatically. |
| `{type: 'row', children: [...]}` | Side by side. Children share the width; a `spacer` pushes the rest to the end. |
| `{type: 'column', children: [...]}` | Stacked. |
| `{type: 'chip', text, color?}` | A small label. |
| `{type: 'progress', value, color?}` | A bar, `value` from 0 to 1. |
| `{type: 'divider'}` | A line. |
| `{type: 'spacer'}` | Flexible space inside a `row`. |
| `'plain string'` or a number | Plain text. |

Nesting goes at most 8 levels deep. Unknown node types are skipped.

**Colors:** `amber`, `blue`, `green`, `red`, `purple`, `teal`, `grey`.
**Icons:** `star`, `sun`, `moon`, `book`, `clock`, `candle`, `calendar`,
`heart`, `info`, `code`.

## `ctx`: the day's data

| Field | What it holds |
| --- | --- |
| `ctx.now` | Current time, UTC, `YYYY-MM-DDTHH:MM` (changes once a minute) |
| `ctx.gregorian` | Civil date, `YYYY-MM-DD` |
| `ctx.hebrewDate` | `{day, month, monthName, year, en, he, heNikud}` for the civil day |
| `ctx.afterSunset` | `true` after sunset, when the Hebrew date has moved on |
| `ctx.halachicDate` | Same fields as `hebrewDate` (no `heNikud`), the Hebrew date now (tomorrow's after sunset) |
| `ctx.location` | `{name, latitude, longitude, elevation, tzid, il}` |
| `ctx.holidays` | `[{en, he, emoji}]` today |
| `ctx.parsha` | `{en, he}`: this week's parsha |
| `ctx.omerTonight` | Tonight's Omer count, 0 outside the Omer |
| `ctx.zmanim.<key>` | `{time: 'HH:MM' (local), iso (UTC), name, he}`; `time` is `''` when there's none (polar days) |
| `ctx.learning.<schedule>` | Today's portion in English, for the schedules the user starred in Daily learning |
| `ctx.learningHe.<schedule>` | The same in Hebrew |
| `ctx.day.<flag>` | Halachic day flags (below) |

Month numbers follow Hebcal: Nisan = 1 … Adar II = 13. Custom zmanim the
user made appear in `ctx.zmanim` as `custom:<id>`.

### Zmanim keys

| Key | Zman |
| --- | --- |
| `alot72` | Dawn (72 min) (MGA) |
| `alot16_1` | Dawn (16.1°) (16.1°) |
| `alotBaalHatanya` | Dawn (Baal HaTanya) (16.9°) |
| `misheyakir` | Earliest tallit & tefillin (11.5°) |
| `misheyakirMachmir` | Misheyakir (machmir) (10.2°) |
| `dawn` | Civil dawn (6°) |
| `sunrise` | Sunrise (Netz) |
| `seaLevelSunrise` | Sea-level sunrise |
| `sofZmanShmaMGA` | Latest Shema (MGA) (MGA 72) |
| `sofZmanShmaMGA16` | Latest Shema (MGA 16.1°) (MGA 16.1°) |
| `sofZmanShma` | Latest Shema (GRA) (GRA) |
| `sofZmanShmaBaalHatanya` | Latest Shema (Baal HaTanya) |
| `sofZmanTfillaMGA` | Latest Shacharit (MGA) (MGA 72) |
| `sofZmanTfilla` | Latest Shacharit (GRA) (GRA) |
| `sofZmanTfilaBaalHatanya` | Latest Shacharit (Baal HaTanya) |
| `chatzot` | Midday (Chatzot) |
| `minchaGedola` | Earliest Mincha (GRA) |
| `minchaGedolaMGA` | Earliest Mincha (MGA) (MGA) |
| `minchaGedolaBaalHatanya` | Earliest Mincha (Baal HaTanya) |
| `minchaKetana` | Mincha Ketana (GRA) |
| `minchaKetanaBaalHatanya` | Mincha Ketana (Baal HaTanya) |
| `plagHaMincha` | Plag HaMincha (GRA) |
| `plagHaminchaBaalHatanya` | Plag HaMincha (Baal HaTanya) |
| `sunset` | Sunset (Shkiah) |
| `seaLevelSunset` | Sea-level sunset |
| `dusk` | Civil dusk (6°) |
| `beinHaShmashos` | Bein HaShmashot (R. Tam) |
| `tzeitBaalHatanya` | Nightfall (Baal HaTanya) (6°) |
| `tzeit7_083` | Nightfall (3 medium stars) (7.083°) |
| `tzeit8_5` | Nightfall (3 small stars) (8.5°) |
| `tzeit6_45` | Nightfall (R. Tucazinsky) (6.45°) |
| `tzeit72` | Nightfall (Rabbeinu Tam, 72 min) (72 min) |
| `chatzotNight` | Midnight (Chatzot HaLailah) |

### Learning schedules

Only schedules the user starred are filled in; check before using one
(`ctx.learning.dafYomi || 'not starred'`).

| Key | Schedule |
| --- | --- |
| `dafYomi` | Daf Yomi (Bavli) |
| `mishnaYomi` | Mishna Yomi |
| `nachYomi` | Nach Yomi |
| `yerushalmi-vilna` | Yerushalmi Yomi (Vilna) |
| `yerushalmi-schottenstein` | Yerushalmi Yomi (Schottenstein) |
| `rambam1` | Daily Rambam (1 chapter) |
| `rambam3` | Daily Rambam (3 chapters) |
| `seferHaMitzvot` | Sefer HaMitzvot |
| `chofetzChaim` | Chofetz Chaim |
| `shemiratHaLashon` | Shemirat HaLashon |
| `psalms` | Daily Tehillim (monthly cycle) |
| `pirkeiAvotSummer` | Pirkei Avot (summer Shabbatot) |
| `dafWeekly` | Daf a Week |
| `dafWeeklySunday` | Daf a Week (Sundays) |
| `kitzurShulchanAruch` | Kitzur Shulchan Arukh Yomi |
| `arukhHaShulchanYomi` | Arukh HaShulchan Yomi |
| `perekYomi` | Perek Yomi (Mishnah) |
| `tanakhYomi` | Tanakh Yomi |
| `929` | 929 (Tanakh chapter a day) |
| `dirshuAmudYomi` | Dirshu Amud HaYomi |
| `dirshuDafHalacha` | Dirshu Daf HaYomi B'Halacha |

### Day flags (`ctx.day`)

Booleans unless noted. They describe the day as a whole; flags tied to a
service (`tachanun`, `torahReading`, `shacharit`…) aren't specific to one.

| Flag | Meaning |
| --- | --- |
| `dow` | Day of week, 0=Sunday … 6=Shabbat |
| `hDay` | Day of Hebrew month |
| `hMonth` | Hebrew month number (Nisan=1 … Adar II=13) |
| `hYear` | Hebrew year |
| `il` | Israel customs (vs diaspora) |
| `diaspora` | Diaspora customs |
| `shacharit` | Service is Shacharit |
| `musaf` | Service is Musaf |
| `mincha` | Service is Mincha |
| `maariv` | Service is Maariv/Arvit |
| `weekday` | Not Shabbat and not Yom Tov |
| `shabbat` | Shabbat |
| `erevShabbat` | Friday |
| `motzaeiShabbat` | Saturday night (Maariv after Shabbat) |
| `yomTov` | Yom Tov (including Rosh Hashana, Yom Kippur) |
| `motzaeiYomTov` | Night after Yom Tov |
| `cholHamoed` | Chol HaMoed (Pesach or Sukkot) |
| `cholHamoedPesach` | Chol HaMoed Pesach |
| `cholHamoedSukkot` | Chol HaMoed Sukkot (incl. Hoshana Raba) |
| `roshChodesh` | Rosh Chodesh |
| `roshChodeshDay` | Which day of a 2-day Rosh Chodesh (1 or 2) |
| `erevRoshChodesh` | Day before Rosh Chodesh |
| `roshHashana` | Rosh Hashana |
| `yomKippur` | Yom Kippur |
| `erevYomKippur` | Erev Yom Kippur |
| `aseretYemeiTeshuva` | Rosh Hashana through Yom Kippur |
| `shabbatShuva` | Shabbat between RH and YK |
| `sukkot` | Sukkot (1st day through Hoshana Raba) |
| `hoshanaRaba` | Hoshana Raba |
| `shminiAtzeret` | Shmini Atzeret |
| `simchatTorah` | Simchat Torah (Shmini Atzeret in Israel) |
| `pesach` | Pesach (all days) |
| `pesachFirstDays` | First day(s) of Pesach |
| `pesachLastDays` | Last day(s) of Pesach |
| `shavuot` | Shavuot |
| `chanukah` | Chanukah |
| `chanukahDay` | Day of Chanukah 1-8 (0 if not Chanukah) |
| `purim` | Purim (14 Adar, or 15 in a walled city) |
| `shushanPurim` | 15 Adar |
| `purimKatan` | Purim Katan (14/15 Adar I) |
| `publicFast` | Public fast day (not Yom Kippur/Tisha B'Av) |
| `fastDay` | Any fast day (incl. Tisha B'Av, not Yom Kippur) |
| `tishaBav` | Tisha B'Av |
| `tzomGedaliah` | Tzom Gedaliah |
| `asaraBTevet` | Asara B'Tevet |
| `taanitEsther` | Ta'anit Esther |
| `tzomTammuz` | 17 Tammuz |
| `yomKippurKatan` | Yom Kippur Katan |
| `behab` | Ta'anit BeHaB |
| `threeWeeks` | Bein HaMetzarim |
| `nineDays` | Rosh Chodesh Av – Tisha B'Av |
| `elul` | Month of Elul |
| `ledavid` | LeDavid (Psalm 27) season |
| `mashivHaruach` | Say Mashiv HaRuach (winter) |
| `moridHatal` | Say Morid HaTal (summer, Sefard/Israel) |
| `talUmatar` | Say V'ten tal u'matar |
| `omer` | During Sefirat HaOmer (day count > 0) |
| `omerDay` | Omer day 1-49 for this Hebrew date (0 if none) |
| `hallel` | Hallel said (half or whole) |
| `wholeHallel` | Whole Hallel |
| `halfHallel` | Half Hallel |
| `tachanun` | Tachanun said at this service |
| `tachanunShacharit` | Tachanun said at Shacharit |
| `tachanunMincha` | Tachanun said at Mincha |
| `monThu` | Monday or Thursday |
| `torahReading` | Torah reading at this service |
| `avinuMalkeinu` | Avinu Malkeinu said |
| `tzidkatcha` | Tzidkatcha Tzedek said (Shabbat Mincha) |
| `avHarachamim` | Av HaRachamim said |
| `barchiNafshiShabbat` | Barchi Nafshi at Shabbat Mincha (winter) |
| `pirkeiAvot` | Pirkei Avot at Shabbat Mincha (summer) |
| `shabbatMevarchim` | Shabbat before Rosh Chodesh (not Tishrei) |
| `yomHaatzmaut` | Yom HaAtzma'ut |
| `yomYerushalayim` | Yom Yerushalayim |
| `yomHazikaron` | Yom HaZikaron |
| `isruChag` | Day after a Pilgrimage festival |
| `kiddushLevana` | Within the Kiddush Levana window (by day) |
| `eruvTavshilin` | Eruv Tavshilin needed today |
| `yizkor` | Yizkor day |
| `minyan` | Praying with a minyan |
| `mourner` | User is a mourner |
| `aveilut` | Sefira or Three Weeks mourning period |
| `leapYear` | Hebrew leap year |

## Fetching data

`fetch(url, {method, headers, body})` works like the browser's, returning a
promise of a response with `ok`, `status`, `statusText`, `url`,
`headers.get(name)`, `text()` and `json()`. Limits:

- **https only.** Other URLs are refused.
- **At most 10 requests** each time the card runs.
- **2 MB** per response, **10 seconds** per request, **15 seconds** for the
  whole script.
- **GET responses are cached for 5 minutes**, shared by every card, so a
  card that runs every minute doesn't hit the server every minute.
- `headers` is a plain object; `body` a string (use `JSON.stringify`).
- Methods: GET, HEAD, POST, PUT, PATCH, DELETE.
- **On the web app**, the server must allow cross-origin requests (CORS).
  Sefaria's and Hebcal's APIs do.
- `XMLHttpRequest`, `WebSocket` and `importScripts` aren't available.

Always handle failure: no connection is normal (Shabbat mode, airplanes,
the offline web app).

```js
async function render(ctx) {
  try {
    var res = await fetch('https://www.sefaria.org/api/calendars');
    if (!res.ok) throw new Error('Sefaria returned ' + res.status);
    var data = await res.json();
    var daf = data.calendar_items.filter(function (i) { return i.title.en === 'Daf Yomi'; })[0];
    return {title: 'Daf Yomi', icon: 'book', children: [
      {type: 'text', text: daf.displayValue.en, style: 'title'},
      {type: 'text', text: daf.displayValue.he, style: 'hebrew'}
    ]};
  } catch (e) {
    return {title: 'Daf Yomi', icon: 'book', children: [
      {type: 'text', text: ctx.learning.dafYomi || 'Offline', style: 'title'},
      {type: 'text', text: String(e.message || e), style: 'caption'}
    ]};
  }
}
```

## The sandbox

Scripts run on the device in the platform's own engine: JavaScriptCore on
iPhone and Mac, QuickJS on Android, Windows and Linux, a Web Worker in the
web app. That means:

- **No DOM**: no `document`, `window`, `localStorage` or `alert`.
- **No stored state between runs**: each run starts fresh. Compute from `ctx`,
  or fetch.
- **Plain JavaScript** (ES2020 or so), with `async`/`await` and `Promise`.
  Avoid newer syntax: QuickJS and older iOS versions may not have it.
- `console.log` goes nowhere useful. Put debug output in the card while
  testing.
- **Time:** use `ctx.now`, which is UTC. `new Date()` works too, but its
  time zone is the device's, not necessarily the location's.

## Examples

**Countdown to a zman**

```js
function render(ctx) {
  var z = ctx.zmanim.sofZmanShma;
  if (!z.iso) return {title: 'Latest Shema', children: ['No zman today']};
  var mins = Math.round((Date.parse(z.iso) - Date.parse(ctx.now + 'Z')) / 60000);
  return {title: 'Latest Shema', icon: 'clock', children: [
    {type: 'row', children: [
      {type: 'text', text: z.time, style: 'headline'},
      {type: 'spacer'},
      mins > 0 ? {type: 'chip', text: 'in ' + Math.floor(mins / 60) + 'h ' + (mins % 60) + 'm', color: 'amber'}
               : {type: 'chip', text: 'passed', color: 'grey'}
    ]}
  ]};
}
```

**What's special today**

```js
function render(ctx) {
  var d = ctx.day, items = [];
  if (d.roshChodesh) items.push({type: 'chip', text: "Ya'aleh VeYavo", color: 'blue'});
  if (d.hallel) items.push({type: 'chip', text: d.wholeHallel ? 'Whole Hallel' : 'Half Hallel', color: 'green'});
  if (!d.tachanun) items.push({type: 'chip', text: 'No Tachanun', color: 'teal'});
  if (ctx.omerTonight) items.push({type: 'chip', text: 'Omer tonight: ' + ctx.omerTonight, color: 'purple'});
  return {title: 'Today', icon: 'star', children: [
    {type: 'text', text: ctx.hebrewDate.he, style: 'hebrew'},
    items.length ? {type: 'row', children: items} : {type: 'text', text: 'A regular day', style: 'caption'}
  ]};
}
```

**Omer progress**

```js
function render(ctx) {
  var n = ctx.omerTonight;
  if (!n) return {title: 'Sefirat HaOmer', children: [{type: 'text', text: 'Not during the Omer', style: 'caption'}]};
  return {title: 'Sefirat HaOmer', icon: 'moon', children: [
    {type: 'text', text: 'Tonight: day ' + n, style: 'title'},
    {type: 'progress', value: n / 49, color: 'purple'}
  ]};
}
```

## Checklist before handing a card over

- `render` is defined at the top level and returns `{children: [...]}`.
- Every `ctx` field used exists here, and missing data (no zman, an unstarred
  schedule, no network) still gives a sensible card.
- Fetches are https, at most 10, and failures are caught.
- The output uses only the nodes, colors and icons listed above.
