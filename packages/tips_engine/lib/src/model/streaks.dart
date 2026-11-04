import '../api/models.dart';

/// En upptäckt streak eller ett mönster, med en vikt för hur anmärkningsvärt
/// det är så att de mest intressanta visas först.
class Streak {
  final String text;
  final double weight;
  final StreakKind kind;
  const Streak(this.text, this.weight, this.kind);
}

enum StreakKind { team, h2h, none }

int _run(List<(int, int)> r, bool Function(int gf, int ga) test) {
  var n = 0;
  for (final (gf, ga) in r) {
    if (!test(gf, ga)) break;
    n++;
  }
  return n;
}

/// Streaks för ett lag utifrån senaste ligamatcherna (nyast först).
List<Streak> teamStreaks(String name, List<(int, int)> results) {
  if (results.length < 3) return const [];
  final out = <Streak>[];

  final wins = _run(results, (f, a) => f > a);
  final losses = _run(results, (f, a) => f < a);
  final unbeaten = _run(results, (f, a) => f >= a);
  final winless = _run(results, (f, a) => f <= a);
  final over = _run(results, (f, a) => f + a > 2);
  final under = _run(results, (f, a) => f + a < 3);
  final btts = _run(results, (f, a) => f > 0 && a > 0);
  final scored = _run(results, (f, a) => f > 0);
  final blank = _run(results, (f, a) => f == 0);
  final clean = _run(results, (f, a) => a == 0);

  if (wins >= 3) {
    out.add(Streak('$name har vunnit $wins raka ligamatcher', 1.0 + wins * 0.3, StreakKind.team));
  } else if (unbeaten >= 5) {
    out.add(Streak('$name är obesegrade i $unbeaten raka ligamatcher', 0.8 + unbeaten * 0.15, StreakKind.team));
  }
  if (losses >= 3) {
    out.add(Streak('$name har förlorat $losses raka ligamatcher', 1.0 + losses * 0.3, StreakKind.team));
  } else if (winless >= 5) {
    out.add(Streak('$name har inte vunnit på $winless matcher', 0.8 + winless * 0.15, StreakKind.team));
  }
  if (over >= 4) out.add(Streak('Över 2.5 mål i ${name}s $over senaste', 0.7 + over * 0.2, StreakKind.team));
  if (under >= 4) out.add(Streak('Under 2.5 mål i ${name}s $under senaste', 0.6 + under * 0.2, StreakKind.team));
  if (btts >= 4) out.add(Streak('Båda lagen har gjort mål i ${name}s $btts senaste', 0.7 + btts * 0.2, StreakKind.team));
  if (scored >= 8) out.add(Streak('$name har gjort mål i $scored raka', 0.5 + scored * 0.08, StreakKind.team));
  if (blank >= 3) out.add(Streak('$name har inte gjort mål på $blank matcher', 0.9 + blank * 0.25, StreakKind.team));
  if (clean >= 3) out.add(Streak('$name har hållit nollan $clean raka', 0.9 + clean * 0.25, StreakKind.team));

  // "X av senaste Y" när det inte redan finns en rak svit.
  final last = results.take(7).toList();
  if (wins < 3 && last.length >= 6) {
    final w = last.where((r) => r.$1 > r.$2).length;
    if (w >= last.length - 1) {
      out.add(Streak('$name har vunnit $w av ${last.length} senaste', 0.9 + w * 0.12, StreakKind.team));
    }
  }
  return out;
}

/// Mönster i inbördes möten. [home] och [away] är dagens hemma- och bortalag.
List<Streak> h2hStreaks(TeamRef home, TeamRef away, List<Fixture> meetings) {
  final done = meetings.where((f) => f.isFinished && f.regHome != null && f.regAway != null).toList()
    ..sort((a, b) => b.kickoff.compareTo(a.kickoff));
  if (done.length < 3) return const [];
  final last = done.take(8).toList();
  final n = last.length;

  // Resultat sett från dagens hemmalag: (hemmalagets mål, bortalagets mål).
  final r = [
    for (final f in last) f.home.id == home.id ? (f.regHome!, f.regAway!) : (f.regAway!, f.regHome!)
  ];
  final out = <Streak>[];

  final hw = r.where((x) => x.$1 > x.$2).length;
  final aw = r.where((x) => x.$1 < x.$2).length;
  final hWinRun = _run(r, (a, b) => a > b);
  final aWinRun = _run(r, (a, b) => a < b);
  final hUnbeaten = _run(r, (a, b) => a >= b);
  final aUnbeaten = _run(r, (a, b) => a <= b);

  if (hWinRun >= 3) {
    out.add(Streak('${home.name} har vunnit de $hWinRun senaste mötena', 1.3 + hWinRun * 0.3, StreakKind.h2h));
  } else if (aWinRun >= 3) {
    out.add(Streak('${away.name} har vunnit de $aWinRun senaste mötena', 1.3 + aWinRun * 0.3, StreakKind.h2h));
  } else if (hw >= (n * 0.7).ceil()) {
    out.add(Streak('${home.name} har vunnit $hw av $n senaste möten', 1.1 + hw / n, StreakKind.h2h));
  } else if (aw >= (n * 0.7).ceil()) {
    out.add(Streak('${away.name} har vunnit $aw av $n senaste möten', 1.1 + aw / n, StreakKind.h2h));
  } else if (hUnbeaten >= 4) {
    out.add(Streak('${home.name} är obesegrade i $hUnbeaten raka möten', 1.0 + hUnbeaten * 0.2, StreakKind.h2h));
  } else if (aUnbeaten >= 4) {
    out.add(Streak('${away.name} är obesegrade i $aUnbeaten raka möten', 1.0 + aUnbeaten * 0.2, StreakKind.h2h));
  }

  final overRun = _run(r, (a, b) => a + b > 2);
  final underRun = _run(r, (a, b) => a + b < 3);
  final over = r.where((x) => x.$1 + x.$2 > 2).length;
  if (overRun >= 3) {
    out.add(Streak('Över 2.5 mål i de $overRun senaste mötena', 1.2 + overRun * 0.25, StreakKind.h2h));
  } else if (over >= (n * 0.75).ceil()) {
    out.add(Streak('Över 2.5 mål i $over av $n senaste möten', 1.0 + over / n, StreakKind.h2h));
  } else if (underRun >= 3) {
    out.add(Streak('Under 2.5 mål i de $underRun senaste mötena', 1.1 + underRun * 0.25, StreakKind.h2h));
  } else if (n - over >= (n * 0.75).ceil()) {
    out.add(Streak('Under 2.5 mål i ${n - over} av $n senaste möten', 0.9 + (n - over) / n, StreakKind.h2h));
  }

  final bttsRun = _run(r, (a, b) => a > 0 && b > 0);
  final btts = r.where((x) => x.$1 > 0 && x.$2 > 0).length;
  if (bttsRun >= 3) {
    out.add(Streak('Båda lagen har gjort mål i de $bttsRun senaste mötena', 1.2 + bttsRun * 0.25, StreakKind.h2h));
  } else if (btts >= (n * 0.75).ceil()) {
    out.add(Streak('Båda lagen har gjort mål i $btts av $n senaste möten', 1.0 + btts / n, StreakKind.h2h));
  }
  return out;
}

/// Väljer de mest anmärkningsvärda, högst [max] stycken. Finns inga blir det
/// en rad som säger det.
List<Streak> pickStreaks(List<Streak> all, {int max = 3}) {
  if (all.isEmpty) return const [Streak('Inga tydliga streaks för lagen eller i inbördes möten', 0, StreakKind.none)];
  final sorted = [...all]..sort((a, b) => b.weight.compareTo(a.weight));
  return sorted.take(max).toList();
}
