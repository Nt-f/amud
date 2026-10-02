"""Reconciles the tagging with the app at build time (build_assets.py): the
customs the taggers named x_…, conditions and roles found wrong in review,
and leaf conditions that belong to the service. corpus/tagged stays as the
taggers wrote it; every correction lives here.

A custom resolves per nusach to:
  True / False   the siddur's own practice (said / not said)
  'if: label'    a personal circumstance: shown, marked "If: label", for
                 the reader to decide (zimun, which foods, his or her name)
  'var: name'    really a calendar or app variable
Unlisted x_ customs stay as they are, which the engine reads as not said.
"""
import re

_IF = 'if: '
_VAR = 'var: '

CUSTOMS = {
    '*': {
        # Personal circumstances: the siddur prints both, the reader decides.
        'x_patientMale': 'if: For a man',
        'x_misheberachSick': 'if: For someone who is ill',
        'x_prayForSick': 'if: Praying for someone who is ill',
        'x_prayerForSick': 'if: Praying for someone who is ill',
        'x_deceasedMale': 'if: For a man',
        'x_deceasedFemale': 'if: For a woman',
        'x_deceasedChild': 'if: For a child',
        'x_woman': 'if: Said by a woman',
        'x_zimun': 'if: Three or more ate together',
        'x_zimunTen': 'if: Ten or more ate together',
        'x_festiveMeal': 'if: At a festive meal (wedding, bris, pidyon haben)',
        'x_ateGrain': 'if: Ate grain foods (not bread)',
        'x_drankWine': 'if: Drank wine or grape juice',
        'x_ateSevenSpecies': 'if: Ate fruit of the seven species',
        'x_ateOtherFood': 'if: Ate other foods',
        'x_guest': "if: Eating at someone else's table",
        'x_eatingAtParentsTable': "if: Eating at one's parents' table",
        'x_eatingAtOwnTable': "if: Eating at one's own table",
        'x_birkatHagomel': 'if: Saying Birkat HaGomel',
        'x_saysGomel': 'if: Saying Birkat HaGomel',
        'x_barMitzvah': 'if: At a bar mitzvah',
        'x_batMitzvah': 'if: At a bat mitzvah',
        'x_barMitzvahFather': 'if: Father of the bar mitzvah',
        'x_birthOfSon': 'if: After the birth of a son',
        'x_birthOfDaughter': 'if: After the birth of a daughter',
        'x_firstDaughter': 'if: Naming a daughter',
        'x_namedInSynagogue': 'if: Naming in the synagogue',
        'x_grandparentsPresent': 'if: Grandparents present',
        'x_firstLulavBlessing': 'if: The first time taking the lulav this year',
        'x_interruptedTefillin': 'if: Interrupted between the tefillin',
        'x_multipleVessels': 'if: Immersing more than one vessel',
        'x_returnImmediately': 'if: Returning the same day',
        'x_returningSameDay': 'if: Returning the same day',
        'x_crossingRiver': 'if: Crossing water',
        'x_captivesPresent': 'if: While there are captives',
        # Calendar and app variables.
        'x_lagBaOmer': 'var: lagBaomer',
        'x_noTefillinCholHamoed': 'var: noTefillinCholHamoed',
        # Other communities' wording and optional extras: not said.
        'x_nusachHaGra': False,
        'x_avodahUS': False,
        'x_karlinVariant': False,
        'x_saysNesVafele': False,
        'x_toratchaLishma': False,
        'x_saysKetzMeshicheh': False,
        'x_peaceEndsOsehHaShalom': False,
        'x_saysSixRemembrances': False,
        'x_saysAniMaamin': False,
        'x_saysAseretHadibrot': False,
        'x_avHarachamimWeekday': False,
        'x_sevenCandles': False,
        'x_kiddushLevanaAddition': False,
        'x_parashatBeshalach': False,
        'x_saysPrayerState': 'if: Communities that say the prayer for the State of Israel',
        'x_saysPrayerSoldiers': 'if: Communities that say the prayer for soldiers',
        'x_saysPrayerHostages': 'if: Communities that say the prayer for captives',
    },
    'ashkenaz': {
        # Printed as the congregation's in the common Ashkenaz siddurim.
        'x_saysKabelBerachamim': True,
        'x_saysYehiShemEzri': True,
        'x_anaBekoach': True,
        'x_saysAnaBekoach': True,
        'x_saysYedidNefesh': True,
        'x_saysBarchiNafshi': True,  # after the Song of the Day on Rosh Chodesh
        'x_uvaLetzionShabbatMincha': True,
        'x_adirBamarom': True,
        'x_ribonoShelOlam': True,
        'x_kohanimYehiRatzon': True,
        'x_viduiDaily': False,  # Monday and Thursday only, in Ashkenaz
        'x_saysYitzmachPurkane': False,  # the Chassidic addition to Kaddish
        'x_addBerachamav': False,  # the Edot HaMizrach addition
    },
    'sefard': {
        'x_saysYitzmachPurkane': True,
        'x_viduiDaily': True,
        'x_yehiRatzonAfterAmidah': True,
    },
    'chabad': {
        'x_saysYitzmachPurkane': True,
        'x_viduiDaily': True,
        'x_wearsRabbenuTam': True,
        'x_saysKadeshVehayaKiYeviacha': True,
        'x_saysSixRemembrances': True,
    },
    'edot_hamizrach': {
        'x_saysPatachEliyahu': True,
        'x_viduiDaily': True,
        'x_addBerachamav': True,
    },
    'koren': {
        'x_saysKabelBerachamim': True,
        'x_saysYehiShemEzri': True,
    },
}

# Exact conditions found wrong in review, per nusach.
CONDITIONS = {
    'ashkenaz': {
        # Tal is said on the first day of Pesach, not the seventh.
        'pesach && yomTovDay == 1': 'pesachFirstDays && yomTovDay == 1',
    },
}

# Leaf conditions. A leaf condition shows or hides the whole leaf, so it
# is the costliest tag to get wrong; the local taggers often set one from a
# single batch's view (a note "on days without Tachanun, omit this" became
# the leaf's condition). Every leaf condition of the local-model siddurim
# was reviewed by hand; these are the corrections (None: removed), by path
# or path prefix.
LEAF_WHEN = {
    'ashkenaz': {
        # Printed under Rosh Chodesh but said on every Hallel day; the
        # service decides when it is inserted.
        'Festivals/Rosh Chodesh/Hallel/': None,
    },
    'sefard': {
        'Weekday Shacharit/Morning Prayer': None,  # the Akeidah, daily
        'Weekday Shacharit/Tachanun': 'tachanunShacharit',  # was inverted
        'Weekday Shacharit/Beit Yaakov': None,  # its note is about the psalm before it
        'Weekday Shacharit/For Monday & Thursday': 'tachanunShacharit',  # both day forms
        'Weekday Shacharit/Torah Reading': 'torahReading',
        'Weekday Shacharit/Avinu Malkeinu': 'avinuMalkeinu',
        'Weekday Mincha/Avinu Malkeinu': 'avinuMalkeinu',
        'Shabbat Morning Services/Bar Mitzva': 'if_barMitzvahFather',
        'Shabbat Morning Services/Av HaRachamim': 'avHarachamim',
        'Shabbat Morning Services/Prayer for Deceased': 'avHarachamim',
        'Shabbat Mincha/Pirkei Avot': 'pirkeiAvot',
        'Holidays/Prayer for Dew': None,
        'Holidays/Prayer for Rain': None,  # was Simchat Torah: the wrong day abroad
        'Yotzerot/Musaf for Hachodesh': 'shabbatHachodesh',
        'Fast Days/Selichot for First Monday': 'behab',
        'Fast Days/Selichot for Thursday': 'behab',
        'Fast Days/Selichot for Concluding Monday': 'behab',
        'Fast Days/Selichot for 20 Sivan': None,  # was month 4: Sivan is 3
        'Fast Days/El Maleh Prayer': None,
        'Nissan/Pesach Offering': None,  # said on Erev Pesach
        'Torah Readings/': None,
        'Various Prayers & Segulot/': None,
    },
    'edot_hamizrach': {
        'The Midnight Rite/': None,
        'Weekday Shacharit/Amida': None,  # was "Ten Days" and node Avinu Malkeinu
        'Weekday Shacharit/Beit Yaakov': None,
        'Weekday Mincha/Vidui': 'tachanunMincha',
        'Shabbat Shacharit/Pesukei D\'Zimra': None,  # was Shabbat Shuva only
        'Shabbat Shacharit/Zeved HaBat': 'false',  # a personal occasion: opened directly
        'Rosh Hodesh/Hallel': None,
        'Nissan/Learning of the Day': None,
    },
    'koren': {
        'Weekdays/Blessings of the Shema': None,  # was "minyan"
        'Weekdays/Viduy': 'tachanunShacharit && (il || monThu)',
        'Weekdays/Avinu Malkenu': 'avinuMalkeinu',
        'Shabbat/Shaharit for Shabbat and Yom Tov': None,  # was "mourner"
        'Shabbat/Blessing the New Month': 'shabbatMevarchim',  # was Shekalim
        'Shabbat/Reading of the Torah': None,
        'Shabbat/Ethics of the Fathers': 'pirkeiAvot',
        # Tagged with a condition negating every variable.
        'Shabbat/Barekhi Nafshi': 'barchiNafshiShabbat',
        'Festivals/Ka Keli': None,
        'Festivals/Birkat Kohanim': 'kohanim',  # the kohanim's own
        'Festivals/Prayer for Dew': None,
        'Festivals/Prayer for Rain': None,
        'Festivals/Selihot; All Days': None,
        'Festivals/Annulment of Vows before Rosh HaShana': None,  # Erev Rosh HaShana
        'Torah Readings/': None,
        'Gates to Prayer/': None,
    },
}

# Sections said every day, where a leaf condition picks out a day. In the
# other sections (Shabbat, festivals, the Haggadah…) a condition that only
# names the section's own occasion is dropped: it adds nothing, and the
# date can be the day before (Friday afternoon, Erev Yom Tov) when one
# reads ahead.
DAILY = re.compile(r'^(Weekday|Weekdays|Upon Arising|Preparatory|Additional Prayers|Additions for|Bedtime|'
                   r'Shacharit|Mincha|Maariv|Arvit|Blessings|Birchat HaMazon|Post Meal|Berachot|Kaddish)')
OCCASIONS = {'shabbat', 'erevShabbat', 'motzaeiShabbat', 'yomTov', 'motzaeiYomTov', 'weekday', 'pesach',
             'sukkot', 'shavuot', 'chanukah', 'purim', 'roshChodesh', 'simchatTorah', 'shminiAtzeret',
             'roshHashana', 'yomKippur', 'pesachFirstDays', 'pesachLastDays', 'cholHamoed',
             'shacharit', 'mincha', 'maariv', 'musaf', 'true'}


def _occasion_only(when):
    ids = set(re.findall(r'[A-Za-z_]\w*', when))
    return ids <= OCCASIONS and '!' not in when.replace('!=', '')


# Roles by graph node: Mourner's Kaddish and Kaddish d'Rabbanan are said
# by the mourners, the aliyah blessings by the one called up. Tagged
# "chazzan" before those roles existed.
ROLE_BY_NODE = {
    'kaddish.mourners': ('chazzan', 'mourner'),
    'kaddish.derabbanan': ('chazzan', 'mourner'),
    'kaddish.burial': ('chazzan', 'mourner'),
    'kaddish.siyum': ('chazzan', 'mourner'),
    'torah.aliyah_blessings': ('chazzan', 'oleh'),
}

# Identifiers that aren't days but where the reader is: shown, marked.
SITUATIONS = {
    'chazarah': "In the chazzan's repetition",
}


def labels():
    """Labels for the if_ identifiers, for the app ("If: For a man")."""
    out = {}
    for table in CUSTOMS.values():
        for name, value in table.items():
            if isinstance(value, str) and value.startswith(_IF):
                out['if_' + name[2:]] = value[len(_IF):]
    for name, label in SITUATIONS.items():
        out['if_' + name] = label
    return out


def condition(nusach, when):
    """The reconciled form of a condition."""
    when = CONDITIONS.get(nusach, {}).get(when, when)
    table = {**CUSTOMS['*'], **CUSTOMS.get(nusach, {})}

    def custom(m):
        value = table.get(m.group(0))
        if value is True:
            return 'true'
        if value is False:
            return 'false'
        if isinstance(value, str) and value.startswith(_IF):
            return 'if_' + m.group(0)[2:]
        if isinstance(value, str) and value.startswith(_VAR):
            return value[len(_VAR):]
        return m.group(0)

    when = re.sub(r'\bx_\w+', custom, when)
    for name in SITUATIONS:
        when = re.sub(rf'\b{name}\b', 'if_' + name, when)
    return when


def leaf(nusach, path, value):
    value = dict(value)
    if 'when' in value:
        value['when'] = condition(nusach, value['when'])
        if not DAILY.match(path) and _occasion_only(value['when']):
            value.pop('when')
    fixes = LEAF_WHEN.get(nusach, {})
    for prefix in sorted(fixes, key=len, reverse=True):
        if path == prefix or (prefix.endswith('/') and path.startswith(prefix)):
            value.pop('when', None)
            if fixes[prefix]:
                value['when'] = fixes[prefix]
            break
    return value


def part(nusach, value, leaf_node):
    value = dict(value)
    if 'when' in value:
        value['when'] = condition(nusach, value['when'])
    fix = ROLE_BY_NODE.get(value.get('node') or leaf_node)
    if fix and value.get('role') == fix[0]:
        value['role'] = fix[1]
    return value
