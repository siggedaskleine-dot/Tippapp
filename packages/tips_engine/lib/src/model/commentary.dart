import '../api/models.dart';
import 'predictor.dart';
import 'streaks.dart';
import 'team_stats.dart';
import 'tip_selector.dart';
import 'tip.dart';

String _pct(double v) => '${(v * 100).round()}%';
String _d1(double v) => v.toStringAsFixed(1);
String _d2(double v) => v.toStringAsFixed(2);

String _formText(List<String> form) => form.isEmpty ? '' : form.take(5).join('');

/// Kort, informativ kommentar på svenska om tipset.
String buildComment(Fixture f, Prediction p, TipCandidate tip, List<String> formH, List<String> formA,
    {List<Streak> streaks = const []}) {
  final h = f.home.name, a = f.away.name;
  final parts = <String>[];
  final xgLine = p.usedXg
      ? 'xG ${_d2(p.xgForHome!)}–${_d2(p.xgAgainstHome!)} mot ${_d2(p.xgForAway!)}–${_d2(p.xgAgainstAway!)}'
      : null;

  switch (tip.type) {
    case BetType.home:
      parts.add('$h tar ${_d2(p.ppgHome)} poäng/match hemma, $a ${_d2(p.ppgAway)} borta.');
      if (formH.isNotEmpty) parts.add('Form ${_formText(formH)} mot ${_formText(formA)}.');
      if (xgLine != null) parts.add('$xgLine (för–emot) stärker hemmalaget.');
    case BetType.away:
      parts.add('$a tar ${_d2(p.ppgAway)} poäng/match borta, $h bara ${_d2(p.ppgHome)} hemma.');
      if (formA.isNotEmpty) parts.add('Form ${_formText(formA)} mot ${_formText(formH)}.');
      if (xgLine != null) parts.add('$xgLine (för–emot) talar för bortalaget.');
    case BetType.draw:
      parts.add('Jämnt: ${_d2(p.ppgHome)} mot ${_d2(p.ppgAway)} poäng/match och få mål väntas '
          '(${_d1(p.lambdaHome)}–${_d1(p.lambdaAway)}).');
    case BetType.over25:
      parts.add('Över 2.5 i ${_pct(p.over25RateHome)} av ${h}s hemmamatcher och '
          '${_pct(p.over25RateAway)} av ${a}s bortamatcher.');
      parts.add('Modellen väntar ${_d1(p.lambdaHome + p.lambdaAway)} mål'
          '${p.usedXg ? ', xG inräknat' : ''}.');
    case BetType.bttsYes:
      parts.add('Båda gör mål i ${_pct(p.bttsRateHome)} av ${h}s hemmamatcher och '
          '${_pct(p.bttsRateAway)} av ${a}s bortamatcher.');
      parts.add('Väntade mål ${_d1(p.lambdaHome)}–${_d1(p.lambdaAway)}'
          '${p.usedXg ? ' med xG' : ''}.');
  }

  final oddsText = tip.oddsFromModel ? 'modellodds ${_d2(tip.odds)}' : 'odds ${_d2(tip.odds)}';
  var tail = 'Sannolikhet ${_pct(tip.probability)}, $oddsText';
  if (!tip.oddsFromModel && tip.edge > 0.03) tail += ', spelvärde +${_pct(tip.edge)}';
  final mp = tip.modelProbability, kp = tip.marketProbability;
  if (mp != null && kp != null && (mp - kp).abs() >= 0.06) {
    tail += mp > kp
        ? '. Modellen (${_pct(mp)}) tror mer på det än spelbolaget (${_pct(kp)})'
        : '. Spelbolaget (${_pct(kp)}) tror mer på det än modellen (${_pct(mp)})';
  }
  if (p.dataQuality < 0.4) tail += '. Tunt underlag, ta med en nypa salt';
  parts.add('$tail.');
  if (streaks.isNotEmpty) {
    parts.add('${streaks.map((s) => s.text).join('. ')}.');
  }
  return parts.join(' ');
}

String _odds(TipCandidate c) => c.odds.toStringAsFixed(2);

/// Längre analys i stycken till matchsidan: varför just det här spelet.
List<String> buildDeepAnalysis({
  required Fixture f,
  required Prediction p,
  required TipCandidate tip,
  required List<TipCandidate> alternatives,
  required TeamProfile? home,
  required TeamProfile? away,
  required LeagueAverages league,
  required List<Streak> streaks,
  required TipSelector selector,
}) {
  final h = f.home.name, a = f.away.name;
  final out = <String>[];

  // 1. Sannolikhet och värde
  final mp = tip.modelProbability, kp = tip.marketProbability;
  final fair = tip.probability > 0 ? 1 / tip.probability : 0;
  var value = '${tip.type.long} @ ${_odds(tip)}. ';
  if (mp != null && kp != null) {
    value += 'Modellen ger ${_pct(mp)} och spelbolaget ${_pct(kp)} (utan marginal), vägt ${_pct(tip.probability)}. ';
  } else {
    value += 'Sannolikhet ${_pct(tip.probability)}. ';
  }
  value += 'Rättvist odds blir ${fair.toStringAsFixed(2)}';
  if (tip.oddsFromModel) {
    value += ', inga spelbolagsodds finns.';
  } else if (tip.edge > 0.03) {
    value += ' mot ${_odds(tip)} hos spelbolaget, alltså spelvärde på +${_pct(tip.edge)}.';
  } else if (tip.edge > -0.03) {
    value += ', i nivå med spelbolagets odds.';
  } else {
    value += ', lite högre än spelbolagets ${_odds(tip)}. Bäst i fönstret men utan spelvärde.';
  }
  out.add(value);

  // 2. Målbild
  final hh = home?.home, aa = away?.away;
  var goals = 'Väntade mål ${_d1(p.lambdaHome)}–${_d1(p.lambdaAway)}, totalt ${_d1(p.lambdaHome + p.lambdaAway)} '
      '(ligasnitt ${_d1(league.homeGoals + league.awayGoals)}).';
  if (hh != null && hh.played > 0 && aa != null && aa.played > 0) {
    goals += ' $h gör ${_d2(hh.gfAvg)} och släpper in ${_d2(hh.gaAvg)} mål/match hemma. '
        '$a gör ${_d2(aa.gfAvg)} och släpper in ${_d2(aa.gaAvg)} borta.';
  }
  if (p.usedXg) {
    goals += ' xG för/emot: $h ${_d2(p.xgForHome!)}/${_d2(p.xgAgainstHome!)}, $a ${_d2(p.xgForAway!)}/${_d2(p.xgAgainstAway!)}.';
  }
  out.add(goals);

  // 3. PPG och form
  if (home != null && away != null) {
    out.add('PPG: $h ${_d2(home.home.ppg)} hemma (${_d2(home.all.ppg)} totalt), '
        '$a ${_d2(away.away.ppg)} borta (${_d2(away.all.ppg)} totalt). '
        'Form senaste 5: $h ${_formText(home.form)}, $a ${_formText(away.form)}.');
  }

  // 4. Speltypens egna nyckeltal
  switch (tip.type) {
    case BetType.home || BetType.draw || BetType.away:
      out.add('1X2 enligt modellen: 1 ${_pct(p.pHome)}, X ${_pct(p.pDraw)}, 2 ${_pct(p.pAway)}. '
          'PPG-skillnaden plats mot plats är ${_d2(p.ppgHome - p.ppgAway)} till '
          '${p.ppgHome >= p.ppgAway ? h : a}s fördel.');
    case BetType.over25:
      out.add('Över 2.5: ${_pct(p.over25RateHome)} av ${h}s hemmamatcher, ${_pct(p.over25RateAway)} av ${a}s '
          'bortamatcher, ligasnitt ${_pct(league.over25Rate)}. Poisson på väntade mål ger ${_pct(p.pOver25)}.');
    case BetType.bttsYes:
      final hScored = hh == null || hh.played == 0 ? null : 1 - _blank(home!, true);
      final aScored = aa == null || aa.played == 0 ? null : 1 - _blank(away!, false);
      var t = 'BLGM: ${_pct(p.bttsRateHome)} av ${h}s hemmamatcher, ${_pct(p.bttsRateAway)} av ${a}s '
          'bortamatcher, ligasnitt ${_pct(league.bttsRate)}.';
      if (hScored != null && aScored != null) {
        t += ' $h har gjort mål i ${_pct(hScored)} av hemmamatcherna och $a i ${_pct(aScored)} av bortamatcherna.';
      }
      out.add(t);
  }

  // 5. Streaks
  final real = streaks.where((s) => s.kind != StreakKind.none).toList();
  if (real.isNotEmpty) out.add('Streaks: ${real.map((s) => s.text).join('. ')}.');

  // 6. Varför inte de andra
  final why = <String>[];
  for (final c in alternatives.take(3)) {
    String reason;
    if (c.odds < selector.minOdds) {
      reason = 'för lågt odds';
    } else if (c.odds > selector.maxOdds) {
      reason = 'för högt odds';
    } else if (c.probability < selector.minProbability) {
      reason = 'för låg sannolikhet';
    } else {
      reason = 'sämre värde';
    }
    why.add('${c.type.long} ${_pct(c.probability)} @ ${_odds(c)} ($reason)');
  }
  if (why.isNotEmpty) out.add('Bortvalda: ${why.join(', ')}.');

  // 7. Underlag
  if (p.dataQuality < 0.5) {
    out.add('Obs: tunt underlag (få spelade matcher), så siffrorna är osäkrare än vanligt.');
  }
  return out;
}

/// Andel matcher utan eget mål, hemma för hemmalaget och borta för bortalaget.
double _blank(TeamProfile t, bool atHome) {
  final list = t.matches.where((m) => m.atHome == atHome).toList();
  if (list.isEmpty) return 0;
  return list.where((m) => m.goalsFor == 0).length / list.length;
}
