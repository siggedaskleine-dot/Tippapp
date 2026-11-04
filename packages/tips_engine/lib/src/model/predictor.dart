import 'dart:math' as math;

import 'team_stats.dart';

/// Vikter i modellen, samlade här så de är lätta att justera.
class ModelWeights {
  /// Hur mycket xG får väga i målförväntningen när full xG-historik finns.
  final double xgMax;

  /// Matcher med xG som krävs för full xG-vikt.
  final int xgFullAt;

  /// Andel Poisson (mål/xG) mot PPG i 1X2.
  final double poisson1x2;

  /// Andel Poisson mot lagens faktiska frekvens för Ö2.5 och BTTS.
  final double poissonGoals;

  /// Antal "låtsasmatcher" på ligasnittet som varje lagvärde krymps mot.
  final double shrinkK;

  const ModelWeights({
    this.xgMax = 0.5,
    this.xgFullAt = 6,
    this.poisson1x2 = 0.6,
    this.poissonGoals = 0.55,
    this.shrinkK = 4,
    this.recentFormPower = 0.35,
  });

  /// Hur starkt senaste 6 matchernas målsnitt påverkar målförväntan (0 = inte alls).
  final double recentFormPower;
}

class Prediction {
  final double lambdaHome; // förväntade mål hemmalag
  final double lambdaAway;
  final double pHome;
  final double pDraw;
  final double pAway;
  final double pOver25;
  final double pBtts;

  // Underlag för kommentarer och visning.
  final double ppgHome; // hemmalagets PPG hemma (krympt)
  final double ppgAway; // bortalagets PPG borta (krympt)
  final double over25RateHome;
  final double over25RateAway;
  final double bttsRateHome;
  final double bttsRateAway;
  final double? xgForHome;
  final double? xgAgainstHome;
  final double? xgForAway;
  final double? xgAgainstAway;
  final bool usedXg;

  /// 0..1, hur mycket data prognosen vilar på.
  final double dataQuality;

  const Prediction({
    required this.lambdaHome,
    required this.lambdaAway,
    required this.pHome,
    required this.pDraw,
    required this.pAway,
    required this.pOver25,
    required this.pBtts,
    required this.ppgHome,
    required this.ppgAway,
    required this.over25RateHome,
    required this.over25RateAway,
    required this.bttsRateHome,
    required this.bttsRateAway,
    required this.xgForHome,
    required this.xgAgainstHome,
    required this.xgForAway,
    required this.xgAgainstAway,
    required this.usedXg,
    required this.dataQuality,
  });

  Map<String, dynamic> toJson() => {
        'lambdaHome': lambdaHome,
        'lambdaAway': lambdaAway,
        'pHome': pHome,
        'pDraw': pDraw,
        'pAway': pAway,
        'pOver25': pOver25,
        'pBtts': pBtts,
        'ppgHome': ppgHome,
        'ppgAway': ppgAway,
        'over25RateHome': over25RateHome,
        'over25RateAway': over25RateAway,
        'bttsRateHome': bttsRateHome,
        'bttsRateAway': bttsRateAway,
        'xgForHome': xgForHome,
        'xgAgainstHome': xgAgainstHome,
        'xgForAway': xgForAway,
        'xgAgainstAway': xgAgainstAway,
        'usedXg': usedXg,
        'dataQuality': dataQuality,
      };
}

double _shrink(double x, int n, double prior, double k) => (n * x + k * prior) / (n + k);
double _clamp(double v, double lo, double hi) => math.max(lo, math.min(hi, v));

class Predictor {
  final ModelWeights w;
  const Predictor([this.w = const ModelWeights()]);

  static const _leaguePpg = 1.37; // ungefärligt snitt poäng/match

  Prediction predict(LeagueTable table, int homeId, int awayId) {
    final avg = table.averages;
    final h = table[homeId] ?? TeamProfile(homeId);
    final a = table[awayId] ?? TeamProfile(awayId);
    final k = w.shrinkK;
    final lh = avg.homeGoals, la = avg.awayGoals;
    final mean = (lh + la) / 2;

    // --- Målförväntan från faktiska mål, plats-specifikt med krympning ---
    // Prior för ett plats-specifikt värde: lagets totala snitt omräknat till
    // hemma/borta-nivå, i sin tur krympt mot ligans snitt.
    double venuePrior(TeamSample all, double allValue, double leagueVenue) =>
        _shrink(allValue * leagueVenue / mean, all.played, leagueVenue, k);

    final hAttPrior = venuePrior(h.all, h.all.gfAvg, lh);
    final hAtt = _shrink(h.home.gfAvg, h.home.played, hAttPrior, k) / lh;
    final aDefPrior = venuePrior(a.all, a.all.gaAvg, lh);
    final aDef = _shrink(a.away.gaAvg, a.away.played, aDefPrior, k) / lh;
    final aAttPrior = venuePrior(a.all, a.all.gfAvg, la);
    final aAtt = _shrink(a.away.gfAvg, a.away.played, aAttPrior, k) / la;
    final hDefPrior = venuePrior(h.all, h.all.gaAvg, la);
    final hDef = _shrink(h.home.gaAvg, h.home.played, hDefPrior, k) / la;

    var lambdaH = lh * hAtt * aDef;
    var lambdaA = la * aAtt * hDef;

    // --- Aktuell form: de 6 senaste matcherna väger extra ---
    // Jämför målsnittet nyligen med säsongssnittet och justerar försiktigt.
    double recent(TeamProfile t, bool scored) {
      final last = t.results.take(6).toList();
      if (last.length < 3 || t.all.played < 6) return 1.0;
      final r = last.fold<int>(0, (s, x) => s + (scored ? x.$1 : x.$2)) / last.length;
      final season = scored ? t.all.gfAvg : t.all.gaAvg;
      return _clamp((r + 0.5) / (season + 0.5), 0.6, 1.6);
    }

    lambdaH *= _clamp(math.pow(recent(h, true) * recent(a, false), w.recentFormPower).toDouble(), 0.8, 1.25);
    lambdaA *= _clamp(math.pow(recent(a, true) * recent(h, false), w.recentFormPower).toDouble(), 0.8, 1.25);

    // --- xG/xGA vävs in när båda lagen har xG-historik ---
    final xgN = math.min(h.all.xgMatches, a.all.xgMatches);
    final usedXg = xgN >= 2;
    if (usedXg) {
      final hx = _shrink(h.all.xgForAvg!, h.all.xgMatches, mean, k) / mean;
      final hxa = _shrink(h.all.xgAgainstAvg!, h.all.xgMatches, mean, k) / mean;
      final ax = _shrink(a.all.xgForAvg!, a.all.xgMatches, mean, k) / mean;
      final axa = _shrink(a.all.xgAgainstAvg!, a.all.xgMatches, mean, k) / mean;
      final xgLambdaH = lh * hx * axa;
      final xgLambdaA = la * ax * hxa;
      final wx = w.xgMax * math.min(1.0, xgN / w.xgFullAt);
      lambdaH = wx * xgLambdaH + (1 - wx) * lambdaH;
      lambdaA = wx * xgLambdaA + (1 - wx) * lambdaA;
    }
    lambdaH = _clamp(lambdaH, 0.2, 4.0);
    lambdaA = _clamp(lambdaA, 0.15, 4.0);

    final pois = poissonMarkets(lambdaH, lambdaA);

    // --- PPG-modell för 1X2 ---
    final ppgH = _shrink(h.home.ppg, h.home.played, _shrink(h.all.ppg, h.all.played, _leaguePpg, k), k);
    final ppgA = _shrink(a.away.ppg, a.away.played, _shrink(a.all.ppg, a.all.played, _leaguePpg, k), k);
    final diff = ppgH - ppgA;
    var ph = _clamp(avg.homeWinRate + 0.16 * diff, 0.05, 0.9);
    var pd = _clamp(avg.drawRate - 0.05 * diff.abs(), 0.10, 0.35);
    var pa = math.max(0.03, 1 - ph - pd);
    final s = ph + pd + pa;
    ph /= s;
    pd /= s;
    pa /= s;

    final wp = w.poisson1x2;
    final pHome = wp * pois.home + (1 - wp) * ph;
    final pDraw = wp * pois.draw + (1 - wp) * pd;
    final pAway = wp * pois.away + (1 - wp) * pa;

    // --- Lagens faktiska frekvens Ö2.5 och BTTS (hemma hemma, borta borta) ---
    double rate(TeamSample venue, TeamSample all, double Function(TeamSample) f, double league) =>
        _shrink(f(venue), venue.played, _shrink(f(all), all.played, league, k), k);

    final o25H = rate(h.home, h.all, (t) => t.over25Rate, avg.over25Rate);
    final o25A = rate(a.away, a.all, (t) => t.over25Rate, avg.over25Rate);
    final bttsH = rate(h.home, h.all, (t) => t.bttsRate, avg.bttsRate);
    final bttsA = rate(a.away, a.all, (t) => t.bttsRate, avg.bttsRate);
    final wg = w.poissonGoals;
    final pOver = wg * pois.over25 + (1 - wg) * (o25H + o25A) / 2;
    final pBtts = wg * pois.btts + (1 - wg) * (bttsH + bttsA) / 2;

    final minPlayed = math.min(h.all.played, a.all.played);
    final quality = _clamp(minPlayed / 10, 0, 1) * (usedXg ? 1.0 : 0.85);

    return Prediction(
      lambdaHome: lambdaH,
      lambdaAway: lambdaA,
      pHome: pHome,
      pDraw: pDraw,
      pAway: pAway,
      pOver25: pOver,
      pBtts: pBtts,
      ppgHome: ppgH,
      ppgAway: ppgA,
      over25RateHome: o25H,
      over25RateAway: o25A,
      bttsRateHome: bttsH,
      bttsRateAway: bttsA,
      xgForHome: h.all.xgForAvg,
      xgAgainstHome: h.all.xgAgainstAvg,
      xgForAway: a.all.xgForAvg,
      xgAgainstAway: a.all.xgAgainstAvg,
      usedXg: usedXg,
      dataQuality: quality,
    );
  }
}

class PoissonMarkets {
  final double home, draw, away, over25, btts;
  const PoissonMarkets(this.home, this.draw, this.away, this.over25, this.btts);
}

/// Oberoende Poisson med Dixon–Coles-justering för låga resultat
/// (rättar till att ren Poisson underskattar oavgjort).
PoissonMarkets poissonMarkets(double lh, double la, {double rho = -0.08, int maxGoals = 10}) {
  double pmf(int k, double l) {
    var f = 1.0;
    for (var i = 2; i <= k; i++) {
      f *= i;
    }
    return math.exp(-l) * math.pow(l, k) / f;
  }

  double tau(int x, int y) {
    if (x == 0 && y == 0) return 1 - lh * la * rho;
    if (x == 0 && y == 1) return 1 + lh * rho;
    if (x == 1 && y == 0) return 1 + la * rho;
    if (x == 1 && y == 1) return 1 - rho;
    return 1;
  }

  var home = 0.0, draw = 0.0, away = 0.0, over = 0.0, btts = 0.0, total = 0.0;
  for (var x = 0; x <= maxGoals; x++) {
    for (var y = 0; y <= maxGoals; y++) {
      final p = pmf(x, lh) * pmf(y, la) * tau(x, y);
      total += p;
      if (x > y) home += p;
      if (x == y) draw += p;
      if (x < y) away += p;
      if (x + y > 2) over += p;
      if (x > 0 && y > 0) btts += p;
    }
  }
  return PoissonMarkets(home / total, draw / total, away / total, over / total, btts / total);
}
