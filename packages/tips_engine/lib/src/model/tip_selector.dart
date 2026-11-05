import '../api/models.dart';
import 'predictor.dart';
import 'tip.dart';

/// Vilka speltyper användaren vill se tips på.
enum MarketFilter { all, matchResult, over25, btts }

extension MarketFilterX on MarketFilter {
  bool allows(BetType t) => switch (this) {
        MarketFilter.all => true,
        MarketFilter.matchResult => t == BetType.home || t == BetType.draw || t == BetType.away,
        MarketFilter.over25 => t == BetType.over25,
        MarketFilter.btts => t == BetType.bttsYes,
      };

  String get label => switch (this) {
        MarketFilter.all => 'Alla',
        MarketFilter.matchResult => '1X2',
        MarketFilter.over25 => 'Över 2.5',
        MarketFilter.btts => 'BLGM',
      };
}

class TipSelector {
  final double targetOdds;
  final double minOdds;
  final double maxOdds;

  /// Lägsta modellsannolikhet för att ett tips ska räknas som spelbart.
  /// Ligger inget spelbart i oddsfönstret markeras matchen som utanför.
  final double minProbability;

  /// Hur mycket avståndet från måloddset straffas mot spelvärdet.
  final double distancePenalty;

  const TipSelector({
    this.targetOdds = 1.90,
    this.minOdds = 1.70,
    this.maxOdds = 2.10,
    this.distancePenalty = 0.15,
    this.minProbability = 0.40,
    this.marketWeight = 0.4,
  });

  /// Selector för ett valfritt oddsfönster. Måloddset blir mitten av
  /// fönstret och sannolikhetskravet följer med: minst 85 % av den
  /// sannolikhet som måloddset motsvarar, högst 40 %.
  factory TipSelector.forRange(double minOdds, double maxOdds) {
    final target = (minOdds + maxOdds) / 2;
    final minProb = (0.85 / target).clamp(0.10, 0.40).toDouble();
    return TipSelector(minOdds: minOdds, maxOdds: maxOdds, targetOdds: target, minProbability: minProb);
  }

  /// Selector kring ett önskat odds, t.ex. 1.50 ± 0.20. Tipset som ligger
  /// närmast önskat odds vinner om spelvärdet är likvärdigt.
  factory TipSelector.forTarget(double target, double spread) {
    final minProb = (0.85 / target).clamp(0.10, 0.40).toDouble();
    return TipSelector(
      targetOdds: target,
      minOdds: target - spread,
      maxOdds: target + spread,
      minProbability: minProb,
      distancePenalty: 0.4,
    );
  }

  /// Hur mycket spelbolagets (marginalrensade) sannolikhet vägs in.
  /// Marknaden fångar skador, avstängningar och laguttagningar som modellen
  /// inte ser, så en blandning träffar oftare än modellen ensam.
  final double marketWeight;

  bool inWindow(TipCandidate c) => c.odds >= minOdds && c.odds <= maxOdds && c.probability >= minProbability;

  List<TipCandidate> candidates(Prediction p, MatchOdds? o) {
    final hasBook = o != null && !o.isEmpty;
    final m = hasBook ? MarketProbabilities.from(o) : null;
    TipCandidate c(BetType t, double prob, double? book, double? market) {
      if (book != null && book > 1) {
        final blended = market == null ? prob : (1 - marketWeight) * prob + marketWeight * market;
        return TipCandidate(t, blended, book, false, modelProbability: prob, marketProbability: market);
      }
      return TipCandidate(t, prob, prob > 0 ? 1 / prob : 99, true, modelProbability: prob);
    }

    final all = [
      c(BetType.home, p.pHome, o?.home, m?.home),
      c(BetType.draw, p.pDraw, o?.draw, m?.draw),
      c(BetType.away, p.pAway, o?.away, m?.away),
      c(BetType.over25, p.pOver25, o?.over25, m?.over25),
      c(BetType.bttsYes, p.pBtts, o?.bttsYes, m?.bttsYes),
    ];
    // Finns spelbolagsodds jämför vi bara marknader som faktiskt har odds.
    return hasBook ? all.where((x) => !x.oddsFromModel).toList() : all;
  }

  /// Väljer tipset: inom oddsfönstret vinner bäst spelvärde med avdrag för
  /// avstånd till mitten av fönstret (standard 1.70–2.10). Ligger inget i fönstret tas det närmast
  /// mitten, och tipset markeras som utanför fönstret.
  /// [only] begränsar till speltyper som klarar formkraven (null = inga krav).
  (TipCandidate, List<TipCandidate>) select(Prediction p, MatchOdds? o,
      {MarketFilter market = MarketFilter.all, Set<BetType>? only}) {
    final all = candidates(p, o);
    final allowed = all.where((c) => market.allows(c.type) && (only == null || only.contains(c.type))).toList();
    final cands = allowed.isEmpty ? all : allowed;
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
    final rest = all.where((c) => c.type != best.type).toList()
      ..sort((a, b) => b.probability.compareTo(a.probability));
    return (best, rest);
  }
}
