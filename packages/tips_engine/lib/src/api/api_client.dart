import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cache.dart';
import 'models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => 'ApiException: $message';
}

/// Klient för api-football v3 med cache, begränsad samtidighet och
/// koll på dagskvoten (Pro: 7500 anrop/dag, 300/min).
class ApiFootballClient {
  final String apiKey;
  final CacheStore cache;
  final http.Client _http;
  final String baseUrl;
  final String timezone;
  final int maxConcurrent;

  /// Senast kända antal anrop kvar idag (från svarshuvudet).
  int? remainingToday;

  /// Antal anrop som faktiskt gick ut mot API:t (ej cacheträffar).
  int networkCalls = 0;

  int _active = 0;
  final _queue = <Completer<void>>[];

  ApiFootballClient({
    required this.apiKey,
    required this.cache,
    http.Client? httpClient,
    this.baseUrl = 'https://v3.football.api-sports.io',
    this.timezone = 'Europe/Stockholm',
    this.maxConcurrent = 6,
  }) : _http = httpClient ?? http.Client();

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  /// GET mot [path] med cache. Returnerar hela JSON-svaret.
  Future<Map<String, dynamic>> get(String path, Map<String, String> params, Duration ttl) async {
    final sorted = Map.fromEntries(params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: sorted);
    final key = uri.toString();
    final cached = await cache.get(key);
    if (cached != null) return jsonDecode(cached) as Map<String, dynamic>;

    await _acquire();
    try {
      for (var attempt = 0;; attempt++) {
        networkCalls++;
        final res = await _http.get(uri, headers: {'x-apisports-key': apiKey});
        final rem = int.tryParse(res.headers['x-ratelimit-requests-remaining'] ?? '');
        if (rem != null) remainingToday = rem;
        if (res.statusCode == 429 && attempt < 3) {
          await Future<void>.delayed(Duration(seconds: 2 << attempt));
          continue;
        }
        if (res.statusCode != 200) {
          throw ApiException('HTTP ${res.statusCode} för $path');
        }
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final errors = body['errors'];
        final hasErrors = (errors is Map && errors.isNotEmpty) || (errors is List && errors.isNotEmpty);
        if (hasErrors) {
          final text = errors.toString();
          // Minutgränsen rapporteras som fel i kroppen, inte som 429.
          if (text.contains('rateLimit') && attempt < 3) {
            await Future<void>.delayed(Duration(seconds: 2 << attempt));
            continue;
          }
          throw ApiException('API-fel för $path: $text');
        }
        await cache.put(key, res.body, ttl);
        return body;
      }
    } finally {
      _release();
    }
  }

  List<Map<String, dynamic>> _resp(Map<String, dynamic> body) =>
      ((body['response'] as List?) ?? const []).cast<Map<String, dynamic>>();

  static String fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Alla matcher ett visst datum, alla ligor (1 anrop).
  Future<List<Fixture>> fixturesByDate(DateTime date, {bool isToday = false}) async {
    final body = await get(
      '/fixtures',
      {'date': fmtDate(date), 'timezone': timezone},
      isToday ? const Duration(minutes: 20) : const Duration(hours: 3),
    );
    return _resp(body).map(Fixture.fromJson).toList();
  }

  /// Hela säsongens matcher i en liga (1 anrop). Grunden för PPG, Ö2.5 och BTTS.
  Future<List<Fixture>> leagueSeason(int leagueId, int season, {bool pastSeason = false}) async {
    final body = await get(
      '/fixtures',
      {'league': '$leagueId', 'season': '$season'},
      pastSeason ? const Duration(days: 30) : const Duration(hours: 12),
    );
    return _resp(body).map(Fixture.fromJson).toList();
  }

  /// Upp till 20 matcher per anrop, inklusive matchstatistik (där xG finns).
  /// Färdigspelade matcher ändras inte, så de cachas länge.
  Future<List<Fixture>> fixturesWithStats(List<int> ids) async {
    if (ids.isEmpty) return const [];
    if (ids.length > 20) throw ArgumentError('Max 20 id:n per anrop');
    final sorted = [...ids]..sort();
    final body = await get('/fixtures', {'ids': sorted.join('-')}, const Duration(days: 60));
    return _resp(body).map(Fixture.fromJson).toList();
  }

  /// De senaste inbördes mötena mellan två lag (1 anrop, cachas 3 dygn).
  Future<List<Fixture>> headToHead(int teamA, int teamB, {int last = 10}) async {
    final ids = [teamA, teamB]..sort();
    final body = await get(
      '/fixtures/headtohead',
      {'h2h': '${ids[0]}-${ids[1]}', 'last': '$last', 'timezone': timezone},
      const Duration(days: 3),
    );
    return _resp(body).map(Fixture.fromJson).toList();
  }

  /// Odds för ett datum från en bookmaker (standard 8 = Bet365). Sidindelat.
  Future<Map<int, MatchOdds>> oddsByDate(DateTime date, {int bookmaker = 8}) async {
    final out = <int, MatchOdds>{};
    Future<int> fetchPage(int page) async {
      final body = await get(
        '/odds',
        {'date': fmtDate(date), 'bookmaker': '$bookmaker', 'timezone': timezone, 'page': '$page'},
        const Duration(hours: 2),
      );
      for (final r in _resp(body)) {
        final o = MatchOdds.fromJson(r);
        if (!o.isEmpty) out[o.fixtureId] = o;
      }
      return ((body['paging'] as Map?)?['total'] as num?)?.toInt() ?? 1;
    }

    // Första sidan berättar hur många sidor det finns, resten hämtas parallellt.
    final total = await fetchPage(1);
    await Future.wait([for (var p = 2; p <= total; p++) fetchPage(p)]);
    return out;
  }

  void close() => _http.close();
}
