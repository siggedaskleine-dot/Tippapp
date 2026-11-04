import '../api/models.dart';
import 'predictor.dart';
import 'tip.dart';

class TipSelector {
  final double targetOdds;
  final double minOdds;
  final double maxOdds;

  /// Hur mycket avståndet från måloddset straffas mot spelvärdet.
  final double distancePenalty;

  const TipSelector({
    this.targetOdds = 1.90,
    this.minOdds = 1.70,
    this.maxOdds = 2.10,
    this.distancePenalty = 0.15,
  });

  bool inWindow(TipCandidate c) => c.odds >= minOdds && c.odds <= maxOdds;

  List<TipCandidate> candidates(Prediction p, MatchOdds? o) {
    final hasBook = o != null && !o.isEmpty;
    TipCandidate c(BetType t, double prob, double? book) {
      if (book != null && book > 1) return TipCandidate(t, prob, book, false);
      return TipCandidate(t, prob, prob > 0 ? 1 / prob : 99, true);
    }

    final all = [
      c(BetType.home, p.pHome, o?.home),
      c(BetType.draw, p.pDraw, o?.draw),
      c(BetType.away, p.pAway, o?.away),
      c(BetType.over25, p.pOver25, o?.over25),
      c(BetType.bttsYes, p.pBtts, o?.bttsYes),
    ];
    // Finns spelbolagsodds jämför vi bara marknader som faktiskt har odds.
    return hasBook ? all.where((x) => !x.oddsFromModel).toList() : all;
  }

  /// Väljer tipset: inom oddsfönstret vinner bäst spelvärde med avdrag för
  /// avstånd till mitten av fönstret (1.70–2.10). Ligger inget i fönstret tas det närmast
  /// mitten, och tipset markeras som utanför fönstret.
  (TipCandidate, List<TipCandidate>) select(Prediction p, MatchOdds? o) {
    final cands = candidates(p, o);
    final inside = cands.where(inWindow).toList();
    double score(TipCandidate c) => c.edge - distancePenalty * (c.odds - targetOdds).abs();

    final TipCandidate best;
    if (inside.isNotEmpty) {
      inside.sort((a, b) => score(b).compareTo(score(a)));
      best = inside.first;
    } else {
      final sorted = [...cands]
        ..sort((a, b) => (a.odds - targetOdds).abs().compareTo((b.odds - targetOdds).abs()));
      best = sorted.first;
    }
    final rest = cands.where((c) => c.type != best.type).toList()
      ..sort((a, b) => b.probability.compareTo(a.probability));
    return (best, rest);
  }
}
