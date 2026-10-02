/// Stable names shared by links, launcher shortcuts and voice assistants.
const prayerShortcuts = <String, String>{
  'shacharit': 'Shacharis',
  'mincha': 'Mincha',
  'maariv': 'Maariv',
  'birkat': 'Birkat HaMazon',
  'derech': 'Tefillat HaDerech',
};

String normalizePrayer(String name) => switch (name.toLowerCase()) {
  'shacharis' || 'shacharit' => 'shacharit',
  'birkat-hamazon' || 'birkat_hamazon' || 'birkathamazon' => 'birkat',
  'tefillat-haderech' || 'tefillat_haderech' || 'tefillathaderech' => 'derech',
  'kiddushlevana' || 'kiddush-levana' => 'kiddushLevana',
  'birkathachama' || 'birkat-hachama' => 'birkatHaChama',
  _ => name,
};

/// Accept only Amud links; never navigate to an arbitrary external URL.
String? routeFromLink(Uri uri) {
  if (!{'amud', 'https', 'http'}.contains(uri.scheme)) return null;
  if (uri.scheme != 'amud' &&
      !{'amud.page', 'www.amud.page'}.contains(uri.host)) {
    return null;
  }
  if (uri.userInfo.isNotEmpty) return null;
  if (uri.scheme == 'amud' && uri.host == 'voice') {
    if (uri.pathSegments.length != 1) return '/siddur';
    final feature = normalizePrayer(uri.pathSegments.single);
    if (feature == 'zmanim') return '/zmanim';
    if (feature == 'omer' || prayerShortcuts.containsKey(feature)) {
      return '/pray/$feature';
    }
    return '/siddur';
  }
  Uri target;
  try {
    if (uri.fragment.startsWith('/')) {
      target = Uri.parse(uri.fragment);
    } else {
      var path = uri.path;
      if (uri.scheme == 'amud' && uri.host.isNotEmpty) {
        path = '/${uri.host}$path';
      }
      if (path.startsWith('/app/')) path = path.substring(4);
      target = Uri(path: path, query: uri.hasQuery ? uri.query : null);
    }
  } on FormatException {
    return null;
  }
  final p = target.path;
  if (p.contains('..') || p.contains('\\') || p.startsWith('//')) return null;
  if (p.startsWith('/pray/')) {
    final parts = target.pathSegments;
    if (parts.length != 2) return null;
    final prayer = normalizePrayer(parts[1]);
    if (!{
      ...prayerShortcuts.keys,
      'musaf',
      'bedtime',
      'omer',
      'hallel',
      'havdalah',
      'kiddushLevana',
      'birkatHaChama',
    }.contains(prayer)) {
      return null;
    }
    return Uri(
      path: '/pray/$prayer',
      query: target.hasQuery ? target.query : null,
    ).toString();
  }
  if (p == '/' ||
      p == '/zmanim' ||
      p == '/personal-dates' ||
      p == '/calendar' ||
      p == '/siddur' ||
      p.startsWith('/read/') ||
      p.startsWith('/siddur/')) {
    return target.toString();
  }
  return null;
}

Uri sharePrayerLink(String prayer, {String? nusach}) => Uri.https(
  'amud.page',
  nusach == null
      ? '/app/pray/${normalizePrayer(prayer)}'
      : '/app/siddur/$nusach/${normalizePrayer(prayer)}',
);

bool isReaderRoute(String path) =>
    path.startsWith('/pray/') ||
    path.startsWith('/read/') ||
    path.endsWith('/read') ||
    RegExp(r'^/siddur/(ashkenaz|sefard|mizrach)/[^/]+$').hasMatch(path);
