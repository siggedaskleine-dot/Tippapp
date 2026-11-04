import '../api/models.dart';
import 'predictor.dart';
import 'tip.dart';

String _pct(double v) => '${(v * 100).round()}%';
String _d1(double v) => v.toStringAsFixed(1);
String _d2(double v) => v.toStringAsFixed(2);

String _formText(List<String> form) => form.isEmpty ? '' : form.take(5).join('');

/// Kort, informativ kommentar på svenska om tipset.
String buildComment(Fixture f, Prediction p, TipCandidate tip, List<String> formH, List<String> formA) {
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
  if (!tip.oddsFromModel && tip.edge <= -0.08) {
    tail += '. Spelbolaget tror mer på det (${_pct(1 / tip.odds)}) än modellen, inget spelvärde';
  }
  if (p.dataQuality < 0.4) tail += '. Tunt underlag, ta med en nypa salt';
  parts.add('$tail.');
  return parts.join(' ');
}
