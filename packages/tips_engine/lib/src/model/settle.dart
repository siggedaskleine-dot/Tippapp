import '../api/models.dart';
import 'tip.dart';

enum TipOutcome { won, lost, voided, pending }

/// Avgör ett tips mot resultatet efter ordinarie tid.
TipOutcome settle(BetType type, Fixture f) {
  const voidStatuses = {'PST', 'CANC', 'ABD', 'AWD', 'WO'};
  if (voidStatuses.contains(f.status)) return TipOutcome.voided;
  if (!f.isFinished) return TipOutcome.pending;
  final h = f.regHome, a = f.regAway;
  if (h == null || a == null) return TipOutcome.pending;
  final won = switch (type) {
    BetType.home => h > a,
    BetType.draw => h == a,
    BetType.away => h < a,
    BetType.over25 => h + a > 2,
    BetType.bttsYes => h > 0 && a > 0,
  };
  return won ? TipOutcome.won : TipOutcome.lost;
}
