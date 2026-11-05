import 'team_stats.dart';
import 'tip.dart';

/// Resultatet av formkontrollen för en match: vilka speltyper som klarar
/// kraven och varför.
class FormSignals {
  /// Formstyrka 0..100 och förklaring per speltyp som klarar kraven.
  final Map<BetType, (double, String)> signals;
  const FormSignals(this.signals);

  bool allows(BetType t) => signals.containsKey(t);
  Set<BetType> get types => signals.keys.toSet();
  String? reason(BetType t) => signals[t]?.$2;
  double? strength(BetType t) => signals[t]?.$1;
  Map<BetType, String> get reasons => {for (final e in signals.entries) e.key: e.value.$2};
}

class _Form {
  final List<RecentMatch> last;
  _Form(TeamProfile? p, [int n = 6]) : last = p?.recent(Venue.all, n) ?? const [];

  int _run(bool Function(RecentMatch) test) {
    var n = 0;
    for (final m in last) {
      if (!test(m)) break;
      n++;
    }
    return n;
  }

  int get winRun => _run((m) => m.goalsFor > m.goalsAgainst);
  int get lossRun => _run((m) => m.goalsFor < m.goalsAgainst);
  int get winlessRun => _run((m) => m.goalsFor <= m.goalsAgainst);
  int get unbeatenRun => _run((m) => m.goalsFor >= m.goalsAgainst);
  int count(bool Function(RecentMatch) test, [int n = 5]) => last.take(n).where(test).length;
  int get wins5 => count((m) => m.goalsFor > m.goalsAgainst);
  int get losses5 => count((m) => m.goalsFor < m.goalsAgainst);
  int get points5 => last.take(5).fold(0, (s, m) => s + (m.goalsFor > m.goalsAgainst ? 3 : m.goalsFor == m.goalsAgainst ? 1 : 0));

  int get n6 => last.length;
  int get over6 => count((m) => m.goalsFor + m.goalsAgainst > 2, 6);
  int get btts6 => count((m) => m.goalsFor > 0 && m.goalsAgainst > 0, 6);
  int get scored6 => count((m) => m.goalsFor > 0, 6);
  int get conceded6 => count((m) => m.goalsAgainst > 0, 6);
  double get gf6 => n6 == 0 ? 0 : last.fold<int>(0, (s, m) => s + m.goalsFor) / n6;
  double get ga6 => n6 == 0 ? 0 : last.fold<int>(0, (s, m) => s + m.goalsAgainst) / n6;

  int get points6 => last.fold(0, (s, m) => s + (m.goalsFor > m.goalsAgainst ? 3 : m.goalsFor == m.goalsAgainst ? 1 : 0));

  /// Andel av maxpoängen senaste 6, 0..1.
  double get ppgShare => n6 == 0 ? 0.5 : points6 / (3 * n6);

  String _pts(String name) => '$name $points6 av ${3 * n6} p senaste $n6';

  /// Tydligaste formbeskrivningen: raka segrar, X segrar av 5 eller poäng.
  String goodText(String name) {
    if (winRun >= 3) return '$name $winRun raka segrar';
    if (wins5 >= 4) return '$name $wins5 segrar av 5';
    if (unbeatenRun >= 5) return '$name obesegrade i $unbeatenRun';
    return _pts(name);
  }

  String badText(String name) {
    if (lossRun >= 3) return '$name $lossRun raka förluster';
    if (losses5 >= 4) return '$name $losses5 förluster av 5';
    if (winlessRun >= 4) return '$name utan seger i $winlessRun';
    return _pts(name);
  }
}

/// Formstyrka 0..100 för att tippa [t] mot [o], eller null om formen inte räcker.
/// Krav: det tipsade laget tar minst 55 % av poängen senaste 6 och minst
/// 30 procentenheter mer än motståndaren.
(double, String)? _sideStrength(_Form t, String tName, _Form o, String oName) {
  if (t.n6 < 4 || o.n6 < 4) return null;
  final diff = t.ppgShare - o.ppgShare;
  if (t.ppgShare < 0.55 || diff < 0.30) return null;
  var score = 50 * t.ppgShare + 50 * (1 - o.ppgShare);
  if (t.winRun >= 3) score += 5 + 2 * (t.winRun - 3);
  if (o.lossRun >= 3) score += 5 + 2 * (o.lossRun - 3);
  return (score.clamp(0, 100).toDouble(), '${t.goodText(tName)}, ${o.badText(oName)}');
}

/// Målrika lag: Ö2.5 i minst hälften av matcherna, minst 2.7 mål per match,
/// och laget både gör och släpper in mål.
(double, String)? _overStrength(_Form h, String hName, _Form a, String aName) {
  String? one(_Form f, String name) {
    if (f.n6 < 4) return null;
    final ok = f.over6 * 2 >= f.n6 && f.gf6 + f.ga6 >= 2.7 && f.gf6 >= 0.8 && f.ga6 >= 0.8;
    return ok ? '$name: Ö2.5 i ${f.over6}/${f.n6}, ${(f.gf6 + f.ga6).toStringAsFixed(1)} mål/match' : null;
  }

  final rh = one(h, hName), ra = one(a, aName);
  if (rh == null || ra == null) return null;
  final share = (h.over6 / h.n6 + a.over6 / a.n6) / 2;
  final goals = (h.gf6 + h.ga6 + a.gf6 + a.ga6) / 2;
  final score = 70 * share + 10 * (goals - 2.5).clamp(0, 3);
  return (score.clamp(0, 100).toDouble(), '$rh. $ra');
}

/// Båda gör mål: BLGM i minst hälften av matcherna, laget har gjort mål i
/// nästan alla och släppt in i minst hälften.
(double, String)? _bttsStrength(_Form h, String hName, _Form a, String aName) {
  String? one(_Form f, String name) {
    if (f.n6 < 4) return null;
    final ok = f.btts6 * 2 >= f.n6 && f.scored6 >= f.n6 - 2 && f.conceded6 * 2 >= f.n6;
    return ok ? '$name: BLGM i ${f.btts6}/${f.n6}, gjort mål i ${f.scored6}' : null;
  }

  final rh = one(h, hName), ra = one(a, aName);
  if (rh == null || ra == null) return null;
  final share = (h.btts6 / h.n6 + a.btts6 / a.n6) / 2;
  final scored = (h.scored6 / h.n6 + a.scored6 / a.n6) / 2;
  final score = 70 * share + 30 * scored;
  return (score.clamp(0, 100).toDouble(), '$rh. $ra');
}

/// Kollar vilka speltyper som stöds av formen i lagens senaste 6 matcher.
FormSignals formSignals(String homeName, TeamProfile? home, String awayName, TeamProfile? away) {
  final h = _Form(home), a = _Form(away);
  final r = <BetType, (double, String)>{};
  void put(BetType t, (double, String)? v) {
    if (v != null) r[t] = v;
  }

  put(BetType.home, _sideStrength(h, homeName, a, awayName));
  put(BetType.away, _sideStrength(a, awayName, h, homeName));
  put(BetType.over25, _overStrength(h, homeName, a, awayName));
  put(BetType.bttsYes, _bttsStrength(h, homeName, a, awayName));
  return FormSignals(r);
}
