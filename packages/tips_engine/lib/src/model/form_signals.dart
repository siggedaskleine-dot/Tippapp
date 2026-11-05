import 'team_stats.dart';
import 'tip.dart';

/// Resultatet av formkontrollen för en match: vilka speltyper som klarar
/// kraven och varför.
class FormSignals {
  final Map<BetType, String> reasons;
  const FormSignals(this.reasons);

  bool allows(BetType t) => reasons.containsKey(t);
  Set<BetType> get types => reasons.keys.toSet();
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

  /// Bra form: 3+ raka segrar, eller 4 segrar av 5, eller obesegrade i 5 med 3+ segrar.
  String? good(String name) {
    if (last.length < 4) return null;
    if (winRun >= 3) return '$name $winRun raka segrar';
    if (wins5 >= 4) return '$name $wins5 segrar av 5';
    if (unbeatenRun >= 5 && wins5 >= 3) return '$name obesegrade i $unbeatenRun ($wins5 segrar)';
    return null;
  }

  /// Dålig form: 3+ raka förluster, eller 4 förluster av 5, eller utan seger i 5 och högst 2 poäng.
  String? bad(String name) {
    if (last.length < 4) return null;
    if (lossRun >= 3) return '$name $lossRun raka förluster';
    if (losses5 >= 4) return '$name $losses5 förluster av 5';
    if (winlessRun >= 5 && points5 <= 2) return '$name utan seger i $winlessRun';
    return null;
  }

  /// Målrikt: Över 2.5 i 4+ av 6, snitt 3+ mål per match, och laget både gör och släpper in mål.
  String? goalRich(String name) {
    if (n6 < 4) return null;
    final ok = over6 >= (n6 * 2 / 3).ceil() && gf6 + ga6 >= 3.0 && gf6 >= 1.0 && ga6 >= 1.0;
    return ok ? '$name: Ö2.5 i $over6/$n6, ${(gf6 + ga6).toStringAsFixed(1)} mål/match' : null;
  }

  /// Båda gör mål: BLGM i 4+ av 6, laget har gjort mål i 5+ och släppt in i 4+.
  String? bothScore(String name) {
    if (n6 < 4) return null;
    final ok = btts6 >= (n6 * 2 / 3).ceil() && scored6 >= n6 - 1 && conceded6 >= (n6 * 2 / 3).ceil();
    return ok ? '$name: BLGM i $btts6/$n6, gjort mål i $scored6' : null;
  }
}

/// Kollar vilka speltyper som stöds av formen i lagens senaste 6 matcher.
FormSignals formSignals(String homeName, TeamProfile? home, String awayName, TeamProfile? away) {
  final h = _Form(home), a = _Form(away);
  final r = <BetType, String>{};

  final hGood = h.good(homeName), aBad = a.bad(awayName);
  if (hGood != null && aBad != null) r[BetType.home] = '$hGood, $aBad';
  final aGood = a.good(awayName), hBad = h.bad(homeName);
  if (aGood != null && hBad != null) r[BetType.away] = '$aGood, $hBad';

  final hg = h.goalRich(homeName), ag = a.goalRich(awayName);
  if (hg != null && ag != null) r[BetType.over25] = '$hg. $ag';

  final hb = h.bothScore(homeName), ab = a.bothScore(awayName);
  if (hb != null && ab != null) r[BetType.bttsYes] = '$hb. $ab';

  return FormSignals(r);
}
