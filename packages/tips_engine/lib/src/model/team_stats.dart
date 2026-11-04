import '../api/models.dart';

enum Venue { home, away, all }

/// Sammanställning av ett lags färdigspelade matcher.
class TeamSample {
  int played = 0;
  int points = 0;
  int goalsFor = 0;
  int goalsAgainst = 0;
  int over25 = 0;
  int btts = 0;
  int xgMatches = 0;
  double xgFor = 0;
  double xgAgainst = 0;

  double get ppg => played == 0 ? 0 : points / played;
  double get gfAvg => played == 0 ? 0 : goalsFor / played;
  double get gaAvg => played == 0 ? 0 : goalsAgainst / played;
  double get over25Rate => played == 0 ? 0 : over25 / played;
  double get bttsRate => played == 0 ? 0 : btts / played;
  double? get xgForAvg => xgMatches == 0 ? null : xgFor / xgMatches;
  double? get xgAgainstAvg => xgMatches == 0 ? null : xgAgainst / xgMatches;

  void add(int gf, int ga, double? xgf, double? xga) {
    played++;
    goalsFor += gf;
    goalsAgainst += ga;
    points += gf > ga ? 3 : (gf == ga ? 1 : 0);
    if (gf + ga > 2) over25++;
    if (gf > 0 && ga > 0) btts++;
    if (xgf != null && xga != null) {
      xgMatches++;
      xgFor += xgf;
      xgAgainst += xga;
    }
  }
}

/// En spelad match sett från ett lags håll.
class RecentMatch {
  final DateTime date;
  final String opponent;
  final bool atHome;
  final int goalsFor;
  final int goalsAgainst;
  const RecentMatch(this.date, this.opponent, this.atHome, this.goalsFor, this.goalsAgainst);

  /// 'V', 'O' eller 'F'.
  String get result => goalsFor > goalsAgainst ? 'V' : goalsFor == goalsAgainst ? 'O' : 'F';
}

class TeamProfile {
  final int teamId;
  final TeamSample all = TeamSample();
  final TeamSample home = TeamSample();
  final TeamSample away = TeamSample();

  /// Senaste resultaten, nyast först: 'V', 'O' eller 'F'.
  final List<String> form = [];

  /// De senaste färdigspelade match-id:na, nyast först (för xG-hämtning).
  final List<int> recentFixtureIds = [];

  /// Senaste resultaten som (gjorda, insläppta) mål, nyast först.
  final List<(int, int)> results = [];

  /// Senaste matcherna med motståndare och plats, nyast först.
  final List<RecentMatch> matches = [];

  /// Spelade matcher i innevarande säsong (förra säsongen kan ingå i
  /// statistiken när ligan har få matcher, men räknas inte här).
  int seasonPlayed = 0;

  TeamProfile(this.teamId);

  /// Senaste matcherna för en viss plats (hemma, borta eller alla).
  List<RecentMatch> recent(Venue v, [int n = 6]) => matches
      .where((m) => v == Venue.all || (v == Venue.home ? m.atHome : !m.atHome))
      .take(n)
      .toList();

  TeamSample sample(Venue v) => switch (v) { Venue.home => home, Venue.away => away, Venue.all => all };

  /// Poäng av max under de senaste [n] matcherna, 0..1.
  double formScore([int n = 5]) {
    final last = form.take(n).toList();
    if (last.isEmpty) return 0.5;
    final pts = last.fold<int>(0, (s, r) => s + (r == 'V' ? 3 : r == 'O' ? 1 : 0));
    return pts / (3 * last.length);
  }
}

/// Ligagenomsnitt som modellen krymper mot när ett lag har få matcher.
class LeagueAverages {
  final int matches;
  final double homeGoals;
  final double awayGoals;
  final double over25Rate;
  final double bttsRate;
  final double homeWinRate;
  final double drawRate;

  const LeagueAverages({
    required this.matches,
    required this.homeGoals,
    required this.awayGoals,
    required this.over25Rate,
    required this.bttsRate,
    required this.homeWinRate,
    required this.drawRate,
  });

  /// Generella europeiska snitt, används när ligan saknar historik.
  static const fallback = LeagueAverages(
    matches: 0,
    homeGoals: 1.50,
    awayGoals: 1.20,
    over25Rate: 0.50,
    bttsRate: 0.50,
    homeWinRate: 0.44,
    drawRate: 0.26,
  );
}

class LeagueTable {
  final Map<int, TeamProfile> teams;
  final LeagueAverages averages;
  const LeagueTable(this.teams, this.averages);

  TeamProfile? operator [](int teamId) => teams[teamId];
}

/// Bygger lagprofiler från en lista matcher. [xgById] kompletterar med xG
/// för matcher där vi hämtat statistik separat.
LeagueTable buildLeagueTable(Iterable<Fixture> fixtures,
    {Map<int, (double, double)> xgById = const {}, int? currentSeason}) {
  final done = fixtures.where((f) => f.isFinished && f.regHome != null && f.regAway != null).toList()
    ..sort((a, b) => b.kickoff.compareTo(a.kickoff)); // nyast först
  final teams = <int, TeamProfile>{};
  var hg = 0, ag = 0, o25 = 0, btts = 0, hw = 0, dr = 0;

  for (final f in done) {
    final h = f.regHome!, a = f.regAway!;
    final xg = xgById[f.id];
    final xh = f.xgHome ?? xg?.$1;
    final xa = f.xgAway ?? xg?.$2;
    hg += h;
    ag += a;
    if (h + a > 2) o25++;
    if (h > 0 && a > 0) btts++;
    if (h > a) hw++;
    if (h == a) dr++;

    final home = teams.putIfAbsent(f.home.id, () => TeamProfile(f.home.id));
    final away = teams.putIfAbsent(f.away.id, () => TeamProfile(f.away.id));
    home.all.add(h, a, xh, xa);
    home.home.add(h, a, xh, xa);
    away.all.add(a, h, xa, xh);
    away.away.add(a, h, xa, xh);
    home.form.add(h > a ? 'V' : h == a ? 'O' : 'F');
    away.form.add(a > h ? 'V' : h == a ? 'O' : 'F');
    home.recentFixtureIds.add(f.id);
    away.recentFixtureIds.add(f.id);
    home.results.add((h, a));
    away.results.add((a, h));
    if (currentSeason == null || f.league.season == currentSeason) {
      home.seasonPlayed++;
      away.seasonPlayed++;
    }
    home.matches.add(RecentMatch(f.kickoff, f.away.name, true, h, a));
    away.matches.add(RecentMatch(f.kickoff, f.home.name, false, a, h));
  }

  final n = done.length;
  // Under 30 matcher är ligasnittet för brusigt: blanda med det generella.
  LeagueAverages avg = LeagueAverages.fallback;
  if (n > 0) {
    final w = n / (n + 30);
    double mix(double v, double fb) => w * v + (1 - w) * fb;
    const fb = LeagueAverages.fallback;
    avg = LeagueAverages(
      matches: n,
      homeGoals: mix(hg / n, fb.homeGoals),
      awayGoals: mix(ag / n, fb.awayGoals),
      over25Rate: mix(o25 / n, fb.over25Rate),
      bttsRate: mix(btts / n, fb.bttsRate),
      homeWinRate: mix(hw / n, fb.homeWinRate),
      drawRate: mix(dr / n, fb.drawRate),
    );
  }
  return LeagueTable(teams, avg);
}
