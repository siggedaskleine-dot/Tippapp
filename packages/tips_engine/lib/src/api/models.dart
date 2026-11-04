/// Typade modeller för de delar av api-football v3 som motorn använder.
library;

double? _toDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll('%', ''));
}

int? _toInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

class TeamRef {
  final int id;
  final String name;
  final String? logo;
  const TeamRef(this.id, this.name, this.logo);

  factory TeamRef.fromJson(Map<String, dynamic> j) =>
      TeamRef(_toInt(j['id']) ?? 0, (j['name'] ?? '') as String, j['logo'] as String?);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'logo': logo};
}

class LeagueRef {
  final int id;
  final String name;
  final String country;
  final String? logo;
  final String? flag;
  final int season;
  final String? round;
  const LeagueRef(this.id, this.name, this.country, this.logo, this.flag, this.season, this.round);

  factory LeagueRef.fromJson(Map<String, dynamic> j) => LeagueRef(
        _toInt(j['id']) ?? 0,
        (j['name'] ?? '') as String,
        (j['country'] ?? '') as String,
        j['logo'] as String?,
        j['flag'] as String?,
        _toInt(j['season']) ?? 0,
        j['round'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'country': country,
        'logo': logo,
        'flag': flag,
        'season': season,
        'round': round,
      };
}

/// Statuskoder som räknas som färdigspelade matcher.
const finishedStatuses = {'FT', 'AET', 'PEN'};

class Fixture {
  final int id;
  final DateTime kickoff; // UTC
  final String status; // NS, FT, 1H, ...
  final LeagueRef league;
  final TeamRef home;
  final TeamRef away;
  final int? goalsHome; // efter full tid (inkl. förlängning)
  final int? goalsAway;
  final int? ftHome; // efter 90 min, används för statistik
  final int? ftAway;

  /// xG per lag om svaret innehöll statistik (fixtures?ids=...).
  final double? xgHome;
  final double? xgAway;

  const Fixture({
    required this.id,
    required this.kickoff,
    required this.status,
    required this.league,
    required this.home,
    required this.away,
    this.goalsHome,
    this.goalsAway,
    this.ftHome,
    this.ftAway,
    this.xgHome,
    this.xgAway,
  });

  bool get isFinished => finishedStatuses.contains(status);
  bool get notStarted => status == 'NS' || status == 'TBD';

  /// Mål efter ordinarie tid (det spel som O2.5/BTTS/1X2 avgörs på).
  int? get regHome => ftHome ?? goalsHome;
  int? get regAway => ftAway ?? goalsAway;

  factory Fixture.fromJson(Map<String, dynamic> j) {
    final f = j['fixture'] as Map<String, dynamic>;
    final teams = j['teams'] as Map<String, dynamic>;
    final goals = (j['goals'] as Map<String, dynamic>?) ?? const {};
    final score = (j['score'] as Map<String, dynamic>?) ?? const {};
    final ft = (score['fulltime'] as Map<String, dynamic>?) ?? const {};
    final homeTeam = TeamRef.fromJson(teams['home'] as Map<String, dynamic>);
    final awayTeam = TeamRef.fromJson(teams['away'] as Map<String, dynamic>);

    double? xgH, xgA;
    final stats = j['statistics'];
    if (stats is List) {
      for (final s in stats) {
        final teamId = _toInt((s['team'] as Map?)?['id']);
        final list = s['statistics'];
        if (list is! List) continue;
        for (final row in list) {
          if (row['type'] == 'expected_goals') {
            final v = _toDouble(row['value']);
            if (teamId == homeTeam.id) xgH = v;
            if (teamId == awayTeam.id) xgA = v;
          }
        }
      }
    }

    final ts = _toInt(f['timestamp']);
    return Fixture(
      id: _toInt(f['id']) ?? 0,
      kickoff: ts != null
          ? DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true)
          : DateTime.parse(f['date'] as String).toUtc(),
      status: ((f['status'] as Map?)?['short'] ?? 'NS') as String,
      league: LeagueRef.fromJson(j['league'] as Map<String, dynamic>),
      home: homeTeam,
      away: awayTeam,
      goalsHome: _toInt(goals['home']),
      goalsAway: _toInt(goals['away']),
      ftHome: _toInt(ft['home']),
      ftAway: _toInt(ft['away']),
      xgHome: xgH,
      xgAway: xgA,
    );
  }
}

/// De odds motorn bryr sig om för en match. Null = marknaden saknas.
class MatchOdds {
  final int fixtureId;
  final String? bookmaker;
  final double? home;
  final double? draw;
  final double? away;
  final double? over25;
  final double? bttsYes;

  const MatchOdds({
    required this.fixtureId,
    this.bookmaker,
    this.home,
    this.draw,
    this.away,
    this.over25,
    this.bttsYes,
  });

  bool get isEmpty =>
      home == null && draw == null && away == null && over25 == null && bttsYes == null;

  /// Bet-id i api-football: 1 = Match Winner, 5 = Goals Over/Under, 8 = Both Teams Score.
  factory MatchOdds.fromJson(Map<String, dynamic> j) {
    final fixtureId = _toInt((j['fixture'] as Map?)?['id']) ?? 0;
    final books = (j['bookmakers'] as List?) ?? const [];
    if (books.isEmpty) return MatchOdds(fixtureId: fixtureId);
    final book = books.first as Map<String, dynamic>;
    double? h, d, a, o25, btts;
    for (final bet in (book['bets'] as List? ?? const [])) {
      final id = _toInt(bet['id']);
      for (final v in (bet['values'] as List? ?? const [])) {
        final label = v['value']?.toString();
        final odd = _toDouble(v['odd']);
        if (id == 1) {
          if (label == 'Home') h = odd;
          if (label == 'Draw') d = odd;
          if (label == 'Away') a = odd;
        } else if (id == 5 && label == 'Over 2.5') {
          o25 = odd;
        } else if (id == 8 && label == 'Yes') {
          btts = odd;
        }
      }
    }
    return MatchOdds(
      fixtureId: fixtureId,
      bookmaker: book['name'] as String?,
      home: h,
      draw: d,
      away: a,
      over25: o25,
      bttsYes: btts,
    );
  }
}
