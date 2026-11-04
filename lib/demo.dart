import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Påhittad data för att förhandsgranska gränssnittet utan API-nyckel.
/// Aktiveras bara med --dart-define=DEMO=true.
http.Client demoClient() {
  final rnd = math.Random(3);
  final leagues = [
    (1, 'Sverige', 'Demo-ligan', ['Norrby', 'Söderås', 'Västvik', 'Österlid', 'Bergsjö', 'Dalby']),
    (2, 'England', 'Demo League', ['Ashford', 'Brookfield', 'Carlton', 'Dunmore', 'Eastwick', 'Fairhaven']),
    (3, 'Spanien', 'Liga Demo', ['Alameda', 'Bravo CF', 'Costa Real', 'Dorado', 'Estrella', 'Fuente']),
  ];
  final season = <int, List<Map<String, dynamic>>>{};
  final upcoming = <Map<String, dynamic>>[];
  var id = 1000;
  final now = DateTime.now();

  int pois(double l) {
    final lim = math.exp(-l);
    var k = 0;
    var p = 1.0;
    do {
      k++;
      p *= rnd.nextDouble();
    } while (p > lim);
    return k - 1;
  }

  Map<String, dynamic> fx(int lid, String country, String lname, int h, int a, List<String> names, DateTime when,
          String st, int? gh, int? ga) =>
      {
        'fixture': {'id': id++, 'timestamp': when.millisecondsSinceEpoch ~/ 1000, 'status': {'short': st}},
        'league': {'id': lid, 'name': lname, 'country': country, 'season': 2026},
        'teams': {
          'home': {'id': lid * 100 + h, 'name': names[h]},
          'away': {'id': lid * 100 + a, 'name': names[a]},
        },
        'goals': {'home': gh, 'away': ga},
        'score': {'fulltime': {'home': gh, 'away': ga}},
      };

  for (final (lid, country, lname, names) in leagues) {
    final str = [for (var i = 0; i < names.length; i++) 0.6 + rnd.nextDouble()];
    final list = <Map<String, dynamic>>[];
    var day = now.subtract(const Duration(days: 200));
    for (var r = 0; r < 4; r++) {
      for (var h = 0; h < names.length; h++) {
        for (var a = 0; a < names.length; a++) {
          if (h == a) continue;
          list.add(fx(lid, country, lname, h, a, names, day, 'FT', pois(1.5 * str[h] / str[a]),
              pois(1.2 * str[a] / str[h])));
          day = day.add(const Duration(days: 1));
        }
      }
    }
    for (var d = 0; d < 3; d++) {
      for (var m = 0; m < 3; m++) {
        final ko = DateTime(now.year, now.month, now.day, 15 + m * 2 + lid % 2, m * 15).add(Duration(days: d));
        final f = fx(lid, country, lname, m * 2, m * 2 + 1, names, ko, 'NS', null, null);
        f['day'] = d;
        upcoming.add(f);
        list.add(f);
      }
    }
    season[lid] = list;
  }

  String odd(double p) => (1 / p * 0.94).clamp(1.05, 15).toStringAsFixed(2);

  return MockClient((req) async {
    final q = req.url.queryParameters;
    Object body;
    if (q.containsKey('date')) {
      final date = DateTime.parse(q['date']!);
      final d = DateTime(date.year, date.month, date.day).difference(DateTime(now.year, now.month, now.day)).inDays;
      final todays = upcoming.where((f) => f['day'] == d).toList();
      if (req.url.path == '/odds') {
        body = {
          'paging': {'current': 1, 'total': 1},
          'response': [
            for (final f in todays)
              {
                'fixture': {'id': f['fixture']['id']},
                'bookmakers': [
                  {
                    'name': 'Bet365',
                    'bets': [
                      {
                        'id': 1,
                        'values': [
                          {'value': 'Home', 'odd': odd(0.3 + rnd.nextDouble() * 0.35)},
                          {'value': 'Draw', 'odd': odd(0.25)},
                          {'value': 'Away', 'odd': odd(0.2 + rnd.nextDouble() * 0.3)},
                        ]
                      },
                      {
                        'id': 5,
                        'values': [
                          {'value': 'Over 2.5', 'odd': odd(0.45 + rnd.nextDouble() * 0.2)}
                        ]
                      },
                      {
                        'id': 8,
                        'values': [
                          {'value': 'Yes', 'odd': odd(0.45 + rnd.nextDouble() * 0.2)}
                        ]
                      },
                    ]
                  }
                ]
              }
          ]
        };
      } else {
        body = {'response': todays};
      }
    } else if (q.containsKey('league')) {
      body = {'response': season[int.parse(q['league']!)] ?? []};
    } else {
      body = {'response': []};
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return http.Response(jsonEncode(body), 200,
        headers: {'x-ratelimit-requests-remaining': '7342', 'content-type': 'application/json; charset=utf-8'});
  });
}
