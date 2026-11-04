import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tips_engine/tips_engine.dart';

/// Syntetisk liga i api-footballs svarsformat. Lag 1 är starkast, lag 10 svagast.
class FakeApi {
  final rnd = math.Random(7);
  final season = <Map<String, dynamic>>[];
  final upcoming = <Map<String, dynamic>>[];
  final calls = <Uri>[];
  final upcomingDate = DateTime.utc(2026, 11, 4, 19);

  Map<String, dynamic> league() =>
      {'id': 113, 'name': 'Allsvenskan', 'country': 'Sweden', 'season': 2026, 'logo': null, 'flag': null};

  Map<String, dynamic> fixture(int id, int home, int away, DateTime when, String status, int? gh, int? ga) => {
        'fixture': {'id': id, 'timestamp': when.millisecondsSinceEpoch ~/ 1000, 'status': {'short': status}},
        'league': league(),
        'teams': {
          'home': {'id': home, 'name': 'Lag $home', 'logo': null},
          'away': {'id': away, 'name': 'Lag $away', 'logo': null},
        },
        'goals': {'home': gh, 'away': ga},
        'score': {
          'fulltime': {'home': gh, 'away': ga}
        },
      };

  int poisson(double l) {
    final L = math.exp(-l);
    var k = 0;
    var p = 1.0;
    do {
      k++;
      p *= rnd.nextDouble();
    } while (p > L);
    return k - 1;
  }

  double strength(int team) => 1.6 - (team - 1) * 0.12; // 1.6 .. 0.52

  FakeApi() {
    var id = 1000;
    var day = DateTime.utc(2026, 4, 1, 15);
    for (var round = 0; round < 2; round++) {
      for (var h = 1; h <= 10; h++) {
        for (var a = 1; a <= 10; a++) {
          if (h == a) continue;
          final lh = 1.45 * strength(h) / strength(a) * 0.9;
          final la = 1.15 * strength(a) / strength(h) * 0.9;
          season.add(fixture(id++, h, a, day, 'FT', poisson(lh), poisson(la)));
          day = day.add(const Duration(hours: 20));
        }
      }
    }
    upcoming.add(fixture(1, 1, 10, upcomingDate, 'NS', null, null)); // stark hemma mot svag
    upcoming.add(fixture(2, 5, 6, upcomingDate.add(const Duration(hours: 1)), 'NS', null, null)); // jämn
    upcoming.add(fixture(3, 2, 3, upcomingDate.subtract(const Duration(hours: 2)), 'NS', null, null));
    season.addAll(upcoming);
  }

  Map<String, dynamic> withXg(Map<String, dynamic> f) {
    final h = f['teams']['home']['id'] as int, a = f['teams']['away']['id'] as int;
    return {
      ...f,
      'statistics': [
        {
          'team': {'id': h},
          'statistics': [
            {'type': 'expected_goals', 'value': (1.4 * strength(h) / strength(a)).toStringAsFixed(2)}
          ]
        },
        {
          'team': {'id': a},
          'statistics': [
            {'type': 'expected_goals', 'value': (1.1 * strength(a) / strength(h)).toStringAsFixed(2)}
          ]
        },
      ],
    };
  }

  http.Response json(Object body, {int remaining = 7000}) => http.Response(
        jsonEncode(body),
        200,
        headers: {'x-ratelimit-requests-remaining': '$remaining'},
      );

  Future<http.Response> handle(http.Request req) async {
    calls.add(req.url);
    expect(req.headers['x-apisports-key'], 'test-key');
    final q = req.url.queryParameters;
    if (req.url.path == '/fixtures/headtohead') {
      final ids = q['h2h']!.split('-').map(int.parse).toSet();
      final m = season.where((f) =>
          ids.contains(f['teams']['home']['id']) && ids.contains(f['teams']['away']['id']) && f['fixture']['status']['short'] == 'FT');
      return json({'errors': [], 'response': m.toList()});
    }
    if (req.url.path == '/fixtures' && q.containsKey('date')) {
      return json({'errors': [], 'response': upcoming});
    }
    if (req.url.path == '/fixtures' && q.containsKey('ids')) {
      final ids = q['ids']!.split('-').map(int.parse).toSet();
      return json({'errors': [], 'response': season.where((f) => ids.contains(f['fixture']['id'])).map(withXg).toList()});
    }
    if (req.url.path == '/fixtures' && q['season'] == '2026') {
      return json({'errors': [], 'response': season});
    }
    if (req.url.path == '/fixtures') {
      return json({'errors': [], 'response': []});
    }
    if (req.url.path == '/odds') {
      final page = int.parse(q['page']!);
      Map<String, dynamic> odds(int id, String h, String d, String a, String o, String b) => {
            'fixture': {'id': id},
            'bookmakers': [
              {
                'id': 8,
                'name': 'Bet365',
                'bets': [
                  {
                    'id': 1,
                    'name': 'Match Winner',
                    'values': [
                      {'value': 'Home', 'odd': h},
                      {'value': 'Draw', 'odd': d},
                      {'value': 'Away', 'odd': a},
                    ]
                  },
                  {
                    'id': 5,
                    'name': 'Goals Over/Under',
                    'values': [
                      {'value': 'Over 1.5', 'odd': '1.20'},
                      {'value': 'Over 2.5', 'odd': o},
                    ]
                  },
                  {
                    'id': 8,
                    'name': 'Both Teams Score',
                    'values': [
                      {'value': 'Yes', 'odd': b},
                      {'value': 'No', 'odd': '1.90'},
                    ]
                  },
                ]
              }
            ],
          };
      // Två sidor för att testa sidindelningen.
      final resp = page == 1
          ? [odds(1, '1.35', '5.00', '8.50', '1.65', '2.10'), odds(2, '2.60', '3.20', '2.75', '2.00', '1.75')]
          : [odds(3, '2.10', '3.40', '3.40', '1.80', '1.72')];
      return json({
        'errors': [],
        'paging': {'current': page, 'total': 2},
        'response': resp
      });
    }
    return http.Response('not found', 404);
  }
}

void main() {
  late FakeApi fake;
  late ApiFootballClient api;
  late TipsEngine engine;

  setUp(() {
    fake = FakeApi();
    api = ApiFootballClient(apiKey: 'test-key', cache: MemoryCache(), httpClient: MockClient(fake.handle));
    engine = TipsEngine(api);
  });

  test('poisson-marknader summerar rätt', () {
    final m = poissonMarkets(1.5, 1.1);
    expect(m.home + m.draw + m.away, closeTo(1, 1e-9));
    expect(m.home, greaterThan(m.away));
    expect(m.over25, inInclusiveRange(0.4, 0.6));
  });

  test('odds tolkas från api-formatet', () {
    final o = MatchOdds.fromJson({
      'fixture': {'id': 9},
      'bookmakers': [
        {
          'name': 'Bet365',
          'bets': [
            {
              'id': 5,
              'values': [
                {'value': 'Over 2.5', 'odd': '1.72'}
              ]
            }
          ]
        }
      ]
    });
    expect(o.over25, 1.72);
    expect(o.home, isNull);
  });

  test('hela dagen: tips, odds, xG, kommentarer och sortering', () async {
    final res = await engine.tipsForDay(0, now: DateTime(2026, 11, 4, 9));
    expect(res.tips, hasLength(3));
    expect(res.warnings, isEmpty);

    final strong = res.tips.firstWhere((t) => t.fixture.id == 1);
    expect(strong.prediction.pHome, greaterThan(0.6));
    expect(strong.prediction.usedXg, isTrue);
    expect(strong.tip.oddsFromModel, isFalse);
    expect(strong.formScoreHome, greaterThan(strong.formScoreAway));
    expect(strong.comment, isNotEmpty);

    for (final t in res.tips) {
      if (t.inOddsWindow) {
        expect(t.tip.odds, inInclusiveRange(1.70, 2.10), reason: 'tips i oddsfönstret');
        expect(t.tip.probability, greaterThanOrEqualTo(0.40));
      }
      // ignore: avoid_print
      print('${t.fixture.home.name}–${t.fixture.away.name}: ${t.tip.type.long} @ ${t.tip.odds}  '
          '(1 ${(t.prediction.pHome * 100).round()}% X ${(t.prediction.pDraw * 100).round()}% '
          '2 ${(t.prediction.pAway * 100).round()}% Ö2.5 ${(t.prediction.pOver25 * 100).round()}% '
          'BLGM ${(t.prediction.pBtts * 100).round()}%)\n  ${t.comment}');
    }

    // Sorterat på starttid som standard.
    expect(res.tips.map((t) => t.fixture.id), [3, 1, 2]);
    sortTips(res.tips, SortBy.probability);
    expect(res.tips.first.tip.probability, greaterThanOrEqualTo(res.tips.last.tip.probability));
    sortTips(res.tips, SortBy.odds);
    expect(res.tips.first.tip.odds, greaterThanOrEqualTo(res.tips.last.tip.odds));

    expect(api.remainingToday, 7000);
    // Lag 1–Lag 10 har inget spelbart i fönstret (hemmafavorit @ 1.35), de andra två har det.
    expect(res.tips.where((t) => t.inOddsWindow).map((t) => t.fixture.id), [3, 2]);
    expect(fake.calls.where((u) => u.path == '/fixtures/headtohead'), hasLength(2));
    for (final t in res.tips) {
      expect(t.streaks, isNotEmpty); // lagens egna streaks eller raden "Inga tydliga streaks"
      // ignore: avoid_print
      print('  streaks: ${t.streaks.map((s) => s.text).join(' | ')}');
    }
  });

  test('andra körningen går helt från cache', () async {
    await engine.tipsForDay(0, now: DateTime(2026, 11, 4, 9));
    final first = fake.calls.length;
    final res = await engine.tipsForDay(0, now: DateTime(2026, 11, 4, 9));
    expect(fake.calls.length, first);
    expect(res.networkCalls, 0);
  });

  test('utan spelbolagsodds används modellodds', () {
    const sel = TipSelector();
    final table = buildLeagueTable(const []);
    final p = const Predictor().predict(table, 1, 2);
    final (tip, _) = sel.select(p, null);
    expect(tip.oddsFromModel, isTrue);
    expect(tip.odds, closeTo(1 / tip.probability, 1e-9));
  });

  group('streaks', () {
    test('raka vinster och mål', () {
      final s = teamStreaks('Landskrona', const [(2, 1), (3, 0), (1, 0), (0, 0), (2, 2)]);
      expect(s.map((x) => x.text), contains('Landskrona har vunnit 3 raka ligamatcher'));
    });

    test('X av senaste Y', () {
      final s = teamStreaks('Lag', const [(2, 1), (0, 1), (3, 0), (1, 0), (2, 0), (4, 1), (2, 1)]);
      expect(s.map((x) => x.text), contains('Lag har vunnit 6 av 7 senaste'));
    });

    test('inbördes möten', () {
      const home = TeamRef(1, 'Landskrona', null);
      const away = TeamRef(2, 'Trelleborg', null);
      Fixture m(int i, bool landskronaHome, int lg, int tg) => Fixture(
            id: i,
            kickoff: DateTime.utc(2025, 1, 1).add(Duration(days: 30 * i)),
            status: 'FT',
            league: const LeagueRef(1, 'L', 'S', null, null, 2025, null),
            home: landskronaHome ? home : away,
            away: landskronaHome ? away : home,
            goalsHome: landskronaHome ? lg : tg,
            goalsAway: landskronaHome ? tg : lg,
          );
      final meetings = [m(6, true, 2, 1), m(5, false, 3, 1), m(4, true, 2, 2), m(3, false, 2, 1), m(2, true, 1, 0), m(1, false, 0, 1)];
      final s = h2hStreaks(home, away, meetings).map((x) => x.text).toList();
      expect(s, contains('Båda lagen har gjort mål i de 4 senaste mötena'));
      expect(s, contains('Över 2.5 mål i de 4 senaste mötena'));
    });

    test('inga streaks ger en rad om det', () {
      final picked = pickStreaks(const []);
      expect(picked.single.kind, StreakKind.none);
    });
  });

  test('cupmatcher och kända lag', () {
    expect(isCupCompetition('FA Cup'), isTrue);
    expect(isCupCompetition('Svenska Cupen'), isTrue);
    expect(isCupCompetition('DFB Pokal'), isTrue);
    expect(isCupCompetition('Copa del Rey'), isTrue);
    expect(isCupCompetition('Club Friendlies'), isTrue);
    expect(isCupCompetition('Premier League'), isFalse);
    expect(isCupCompetition('UEFA Champions League'), isFalse);
    expect(isCupCompetition('Allsvenskan'), isFalse);
    expect(isTopLeague(39), isTrue);
    expect(isTopLeague(99999), isFalse);
  });
}
