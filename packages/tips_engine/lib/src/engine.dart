import 'dart:async';

import 'api/api_client.dart';
import 'api/models.dart';
import 'model/commentary.dart';
import 'model/predictor.dart';
import 'model/streaks.dart';
import 'model/top_leagues.dart';
import 'model/team_stats.dart';
import 'model/tip.dart';
import 'model/tip_selector.dart';

enum SortBy { kickoff, odds, form, probability }

class EngineOptions {
  /// Hämta xG via matchstatistik (kostar anrop första gången, cachas sedan).
  final bool fetchXg;

  /// Antal senaste matcher per lag som xG hämtas för.
  final int xgMatchesPerTeam;

  /// xG-hämtning hoppas över när färre anrop än så återstår idag.
  final int reserveCalls;

  /// Bookmaker-id i api-football (8 = Bet365).
  final int bookmaker;

  /// Visa även matcher som redan startat/är klara.
  final bool includeStarted;

  /// Hämta inbördes möten (1 anrop per match, cachas 3 dygn).
  final bool fetchH2h;

  /// Hämta inbördes möten bara för tips i oddsfönstret (de som visas).
  final bool h2hOnlyInWindow;

  /// Om ligans säsong har färre färdiga matcher än så tas förra säsongen med.
  final int minLeagueMatches;

  const EngineOptions({
    this.fetchXg = true,
    this.xgMatchesPerTeam = 6,
    this.reserveCalls = 500,
    this.bookmaker = 8,
    this.includeStarted = false,
    this.minLeagueMatches = 40,
    this.fetchH2h = true,
    this.h2hOnlyInWindow = true,
  });
}

class DayResult {
  final DateTime date;

  /// Bästa tipset per match oavsett speltyp.
  final List<MatchTip> tips;

  /// Bästa tipset per match inom varje speltyp.
  final Map<MarketFilter, List<MatchTip>> byMarket;
  final int networkCalls;
  final int? remainingToday;
  final List<String> warnings;
  const DayResult(this.date, this.tips, this.networkCalls, this.remainingToday, this.warnings,
      {this.byMarket = const {}});

  List<MatchTip> tipsFor(MarketFilter m) => m == MarketFilter.all ? tips : (byMarket[m] ?? const []);
}

class TipsEngine {
  final ApiFootballClient api;
  final Predictor predictor;
  /// Kan bytas när användaren ändrar oddsfönstret.
  TipSelector selector;
  final EngineOptions options;

  /// Ligor där vi sett att xG saknas, så vi inte frågar igen i onödan.
  final Set<String> _noXg = {};

  TipsEngine(
    this.api, {
    this.predictor = const Predictor(),
    this.selector = const TipSelector(),
    this.options = const EngineOptions(),
  });

  /// [dayOffset] 0 = idag, 1 = imorgon, 2 = övermorgon.
  Future<DayResult> tipsForDay(int dayOffset, {DateTime? now, void Function(String)? onProgress}) async {
    final base = now ?? DateTime.now();
    final date = DateTime(base.year, base.month, base.day).add(Duration(days: dayOffset));
    final callsBefore = api.networkCalls;
    final warnings = <String>[];

    onProgress?.call('Hämtar matcher');
    var fixtures = await api.fixturesByDate(date, isToday: dayOffset == 0);
    if (!options.includeStarted) fixtures = fixtures.where((f) => f.notStarted).toList();

    onProgress?.call('Hämtar odds');
    Map<int, MatchOdds> odds = {};
    try {
      odds = await api.oddsByDate(date, bookmaker: options.bookmaker);
    } on ApiException catch (e) {
      warnings.add('Odds kunde inte hämtas: ${e.message}');
    }

    // Gruppera per liga och säsong: ett anrop per liga ger hela historiken.
    final byLeague = <(int, int), List<Fixture>>{};
    for (final f in fixtures) {
      byLeague.putIfAbsent((f.league.id, f.league.season), () => []).add(f);
    }

    onProgress?.call('Hämtar lagstatistik för ${byLeague.length} ligor');
    final tables = <(int, int), LeagueTable>{};
    await Future.wait(byLeague.entries.map((e) async {
      final (leagueId, season) = e.key;
      try {
        tables[e.key] = await _leagueTable(leagueId, season, e.value);
      } on ApiException catch (err) {
        warnings.add('Liga $leagueId: ${err.message}');
        tables[e.key] = buildLeagueTable(const []);
      }
    }));

    // Först modell och tipsval för alla matcher, ett tips per speltyp.
    final picked = <(Fixture, LeagueTable, Prediction, MatchOdds?, Map<MarketFilter, (TipCandidate, List<TipCandidate>, bool)>)>[];
    for (final e in byLeague.entries) {
      final table = tables[e.key]!;
      for (final f in e.value) {
        final p = predictor.predict(table, f.home.id, f.away.id);
        final o = odds[f.id];
        final per = <MarketFilter, (TipCandidate, List<TipCandidate>, bool)>{};
        for (final m in MarketFilter.values) {
          final (tip, alts) = selector.select(p, o, market: m);
          per[m] = (tip, alts, !tip.oddsFromModel && selector.inWindow(tip) && m.allows(tip.type));
        }
        picked.add((f, table, p, o, per));
      }
    }

    // Inbördes möten hämtas parallellt för de matcher som kan visas.
    final h2h = <int, List<Fixture>>{};
    if (options.fetchH2h) {
      onProgress?.call('Hämtar inbördes möten');
      await Future.wait(picked
          .where((x) => (!options.h2hOnlyInWindow || x.$5.values.any((v) => v.$3)) && !isYouthMatch(x.$1))
          .map((x) async {
        final remaining = api.remainingToday;
        if (remaining != null && remaining < options.reserveCalls) return;
        try {
          h2h[x.$1.id] = await api.headToHead(x.$1.home.id, x.$1.away.id);
        } on ApiException {
          // Utan möten blir det bara lagens egna streaks.
        }
      }));
    }

    final byMarket = {for (final m in MarketFilter.values) m: <MatchTip>[]};
    for (final (f, table, p, o, per) in picked) {
      final hp = table[f.home.id];
      final ap = table[f.away.id];
      final formH = hp?.form.take(5).toList() ?? const <String>[];
      final formA = ap?.form.take(5).toList() ?? const <String>[];
      final streaks = pickStreaks([
        ...teamStreaks(f.home.name, hp?.results ?? const []),
        ...teamStreaks(f.away.name, ap?.results ?? const []),
        ...h2hStreaks(f.home, f.away, h2h[f.id] ?? const []),
      ]);
      for (final MapEntry(key: m, value: (tip, alts, inWindow)) in per.entries) {
        byMarket[m]!.add(MatchTip(
          fixture: f,
          prediction: p,
          odds: o,
          tip: tip,
          alternatives: alts,
          comment: buildComment(f, p, tip, formH, formA, streaks: streaks),
          analysis: buildComment(f, p, tip, formH, formA),
          formHome: formH,
          formAway: formA,
          formScoreHome: hp?.formScore() ?? 0.5,
          formScoreAway: ap?.formScore() ?? 0.5,
          inOddsWindow: inWindow,
          streaks: streaks,
          homeProfile: hp,
          awayProfile: ap,
          deepAnalysis: buildDeepAnalysis(
            f: f,
            p: p,
            tip: tip,
            alternatives: alts,
            home: hp,
            away: ap,
            league: table.averages,
            streaks: streaks,
            selector: selector,
          ),
        ));
      }
    }
    for (final l in byMarket.values) {
      sortTips(l, SortBy.kickoff);
    }
    final tips = byMarket[MarketFilter.all]!;
    return DayResult(date, tips, api.networkCalls - callsBefore, api.remainingToday, warnings,
        byMarket: byMarket);
  }

  Future<LeagueTable> _leagueTable(int leagueId, int season, List<Fixture> upcoming) async {
    var history = await api.leagueSeason(leagueId, season);
    final finished = history.where((f) => f.isFinished).length;
    if (finished < options.minLeagueMatches) {
      try {
        final prev = await api.leagueSeason(leagueId, season - 1, pastSeason: true);
        history = [...history, ...prev];
      } on ApiException {
        // Ingen förra säsong (ny liga/cup), kör på det som finns.
      }
    }

    var table = buildLeagueTable(history, currentSeason: season);
    if (!options.fetchXg) return table;

    final key = '$leagueId:$season';
    if (_noXg.contains(key) || await api.cache.get('noxg:$key') != null) return table;
    final remaining = api.remainingToday;
    if (remaining != null && remaining < options.reserveCalls) return table;

    // Samla de senaste matcherna för lagen som spelar i fönstret.
    final ids = <int>{};
    for (final f in upcoming) {
      for (final t in [f.home.id, f.away.id]) {
        ids.addAll(table[t]?.recentFixtureIds.take(options.xgMatchesPerTeam) ?? const <int>[]);
      }
    }
    if (ids.isEmpty) return table;

    final list = ids.toList();
    final xgById = <int, (double, double)>{};
    for (var i = 0; i < list.length; i += 20) {
      final batch = list.sublist(i, i + 20 > list.length ? list.length : i + 20);
      final withStats = await api.fixturesWithStats(batch);
      var found = 0;
      for (final f in withStats) {
        if (f.xgHome != null && f.xgAway != null) {
          xgById[f.id] = (f.xgHome!, f.xgAway!);
          found++;
        }
      }
      // Första omgången utan xG: ligan saknar det, sluta fråga.
      if (i == 0 && found == 0) {
        _noXg.add(key);
        await api.cache.put('noxg:$key', '1', const Duration(days: 7));
        return table;
      }
    }
    return buildLeagueTable(history, xgById: xgById, currentSeason: season);
  }
}

void sortTips(List<MatchTip> tips, SortBy by) {
  int cmp(MatchTip a, MatchTip b) => switch (by) {
        SortBy.kickoff => a.fixture.kickoff.compareTo(b.fixture.kickoff),
        SortBy.odds => b.tip.odds.compareTo(a.tip.odds),
        SortBy.form => b.formScore.compareTo(a.formScore),
        SortBy.probability => b.tip.probability.compareTo(a.tip.probability),
      };
  tips.sort((a, b) {
    final c = cmp(a, b);
    return c != 0 ? c : a.fixture.kickoff.compareTo(b.fixture.kickoff);
  });
}
