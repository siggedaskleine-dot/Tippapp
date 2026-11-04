import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tips_engine/tips_engine.dart';

/// Ett sparat tips som följs upp i facit.
class SavedTip {
  final int fixtureId;
  final DateTime kickoff;
  final String home;
  final String away;
  final String league;
  final BetType type;
  final double odds;
  final double probability;
  TipOutcome outcome;
  String? score;

  SavedTip({
    required this.fixtureId,
    required this.kickoff,
    required this.home,
    required this.away,
    required this.league,
    required this.type,
    required this.odds,
    required this.probability,
    this.outcome = TipOutcome.pending,
    this.score,
  });

  factory SavedTip.fromTip(MatchTip t) => SavedTip(
        fixtureId: t.fixture.id,
        kickoff: t.fixture.kickoff,
        home: t.fixture.home.name,
        away: t.fixture.away.name,
        league: '${t.fixture.league.country} · ${t.fixture.league.name}',
        type: t.tip.type,
        odds: t.tip.odds,
        probability: t.tip.probability,
      );

  Map<String, dynamic> toJson() => {
        'id': fixtureId,
        'ko': kickoff.toIso8601String(),
        'h': home,
        'a': away,
        'l': league,
        't': type.name,
        'o': odds,
        'p': probability,
        'r': outcome.name,
        's': score,
      };

  factory SavedTip.fromJson(Map<String, dynamic> j) => SavedTip(
        fixtureId: j['id'] as int,
        kickoff: DateTime.parse(j['ko'] as String),
        home: j['h'] as String,
        away: j['a'] as String,
        league: j['l'] as String,
        type: BetType.values.byName(j['t'] as String),
        odds: (j['o'] as num).toDouble(),
        probability: (j['p'] as num).toDouble(),
        outcome: TipOutcome.values.byName(j['r'] as String),
        score: j['s'] as String?,
      );
}

/// Sparar visade tips lokalt och rättar dem när matcherna spelats.
class TipHistory {
  static const _key = 'tip_history_v1';
  final Map<int, SavedTip> _tips = {};

  List<SavedTip> get all => _tips.values.toList()..sort((a, b) => b.kickoff.compareTo(a.kickoff));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      for (final j in jsonDecode(raw) as List) {
        final t = SavedTip.fromJson(j as Map<String, dynamic>);
        _tips[t.fixtureId] = t;
      }
    } catch (_) {
      // Trasig data: börja om hellre än att krascha.
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    // Behåll högst 90 dagar.
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    _tips.removeWhere((_, t) => t.kickoff.isBefore(cutoff));
    await prefs.setString(_key, jsonEncode(_tips.values.map((t) => t.toJson()).toList()));
  }

  /// Lägger till eller uppdaterar tips som inte startat än.
  Future<void> record(Iterable<MatchTip> tips) async {
    final now = DateTime.now().toUtc();
    var changed = false;
    for (final t in tips) {
      if (!t.inOddsWindow || t.fixture.kickoff.isBefore(now)) continue;
      _tips[t.fixture.id] = SavedTip.fromTip(t);
      changed = true;
    }
    if (changed) await _save();
  }

  /// Rättar avslutade matcher. [fixturesOn] hämtar alla matcher ett datum.
  Future<void> settleAll(Future<List<Fixture>> Function(DateTime day) fixturesOn) async {
    final now = DateTime.now().toUtc();
    final open = _tips.values
        .where((t) => t.outcome == TipOutcome.pending && t.kickoff.add(const Duration(hours: 2)).isBefore(now))
        .toList();
    if (open.isEmpty) return;
    final days = <DateTime>{for (final t in open) DateTime(t.kickoff.toLocal().year, t.kickoff.toLocal().month, t.kickoff.toLocal().day)};
    final byId = <int, Fixture>{};
    for (final d in days) {
      try {
        for (final f in await fixturesOn(d)) {
          byId[f.id] = f;
        }
      } catch (_) {}
    }
    for (final t in open) {
      final f = byId[t.fixtureId];
      if (f == null) continue;
      t.outcome = settle(t.type, f);
      if (f.regHome != null && f.regAway != null) t.score = '${f.regHome}–${f.regAway}';
    }
    await _save();
  }
}
