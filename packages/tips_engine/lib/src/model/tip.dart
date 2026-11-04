import '../api/models.dart';
import 'predictor.dart';
import 'streaks.dart';

enum BetType { home, draw, away, over25, bttsYes }

extension BetTypeLabel on BetType {
  /// Kort etikett för kortet.
  String get short => switch (this) {
        BetType.home => '1',
        BetType.draw => 'X',
        BetType.away => '2',
        BetType.over25 => 'Ö 2.5',
        BetType.bttsYes => 'BLGM',
      };

  String get long => switch (this) {
        BetType.home => 'Hemmavinst',
        BetType.draw => 'Oavgjort',
        BetType.away => 'Bortavinst',
        BetType.over25 => 'Över 2.5 mål',
        BetType.bttsYes => 'Båda lagen gör mål',
      };
}

class TipCandidate {
  final BetType type;
  final double probability;
  final double odds;

  /// true = inga spelbolagsodds, oddset är modellens rättvisa odds (1/p).
  final bool oddsFromModel;

  /// Modellens egen sannolikhet och marknadens (utan marginal), före vägning.
  final double? modelProbability;
  final double? marketProbability;

  const TipCandidate(this.type, this.probability, this.odds, this.oddsFromModel,
      {this.modelProbability, this.marketProbability});

  /// Förväntat värde per satsad krona minus 1. Positivt = spelvärde.
  double get edge => probability * odds - 1;

  /// Grov bedömning för kortets färgmärkning.
  TipRating get rating {
    if (oddsFromModel) return TipRating.modelOnly;
    if (edge > 0.03) return TipRating.value;
    if (edge > -0.08) return TipRating.fair;
    return TipRating.weak;
  }
}

enum TipRating { value, fair, weak, modelOnly }

extension TipRatingLabel on TipRating {
  String get label => switch (this) {
        TipRating.value => 'Spelvärde',
        TipRating.fair => 'Rimligt',
        TipRating.weak => 'Svagt',
        TipRating.modelOnly => 'Inga odds',
      };
}

class MatchTip {
  final Fixture fixture;
  final Prediction prediction;
  final MatchOdds? odds;
  final TipCandidate tip;
  final List<TipCandidate> alternatives;
  final String comment;

  /// Kommentaren utan streaks (appen visar streaks som egna rader).
  final String analysis;
  final List<String> formHome; // nyast först, V/O/F
  final List<String> formAway;
  final double formScoreHome; // 0..1
  final double formScoreAway;

  /// true när tipsets odds ligger i oddsfönstret (1.70–2.10).
  final bool inOddsWindow;

  /// Streaks och mönster, de mest anmärkningsvärda först.
  final List<Streak> streaks;

  const MatchTip({
    required this.fixture,
    required this.prediction,
    required this.odds,
    required this.tip,
    required this.alternatives,
    required this.comment,
    this.analysis = '',
    required this.formHome,
    required this.formAway,
    required this.formScoreHome,
    required this.formScoreAway,
    this.inOddsWindow = true,
    this.streaks = const [],
  });

  /// Formvärde för sortering, kopplat till tipset: hemmalagets form för 1,
  /// bortalagets för 2, annars snittet av båda.
  double get formScore => switch (tip.type) {
        BetType.home => formScoreHome,
        BetType.away => formScoreAway,
        BetType.draw => 1 - (formScoreHome - formScoreAway).abs(),
        _ => (formScoreHome + formScoreAway) / 2,
      };

  Map<String, dynamic> toJson() => {
        'fixtureId': fixture.id,
        'kickoff': fixture.kickoff.toIso8601String(),
        'status': fixture.status,
        'league': fixture.league.toJson(),
        'home': fixture.home.toJson(),
        'away': fixture.away.toJson(),
        'tip': {
          'type': tip.type.name,
          'short': tip.type.short,
          'label': tip.type.long,
          'odds': tip.odds,
          'oddsFromModel': tip.oddsFromModel,
          'probability': tip.probability,
          'edge': tip.edge,
          'modelProbability': tip.modelProbability,
          'marketProbability': tip.marketProbability,
          'rating': tip.rating.name,
          'ratingLabel': tip.rating.label,
        },
        'comment': comment,
        'analysis': analysis,
        'formHome': formHome,
        'formAway': formAway,
        'formScore': formScore,
        'inOddsWindow': inOddsWindow,
        'streaks': [for (final s in streaks) {'text': s.text, 'kind': s.kind.name}],
        'bookmaker': odds?.bookmaker,
        'prediction': prediction.toJson(),
      };
}
