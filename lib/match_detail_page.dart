import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tips_engine/tips_engine.dart';

import 'match_card.dart';
import 'theme.dart';

/// Matchsidan: lagen sida vid sida med PPG, nyckeltal, senaste matcher och
/// en djupare analys av varför tipset valdes.
class MatchDetailPage extends StatefulWidget {
  final MatchTip tip;
  const MatchDetailPage({super.key, required this.tip});

  @override
  State<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends State<MatchDetailPage> {
  /// false = hemmalaget hemma och bortalaget borta, true = totalt.
  bool _total = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tip;
    final f = t.fixture;
    final rc = ratingColor(t.tip.rating);
    final hp = t.homeProfile, ap = t.awayProfile;
    final hs = _total ? hp?.all : hp?.home;
    final as_ = _total ? ap?.all : ap?.away;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgTop, AppColors.bg],
            stops: [0, 0.35],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Row(children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text('${f.league.country} · ${f.league.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ),
                Text(DateFormat('EEE d MMM HH:mm', 'sv_SE').format(f.kickoff.toLocal()),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
              const SizedBox(height: 12),
              _Header(tip: t),
              const SizedBox(height: 16),
              // Tipset
              _Panel(
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('TIPS', style: TextStyle(color: AppColors.muted, fontSize: 11, letterSpacing: 1.2)),
                      const SizedBox(height: 4),
                      Text(t.tip.type.long, style: TextStyle(color: rc, fontSize: 22, fontWeight: FontWeight.w800)),
                      Text('${t.tip.rating.label} · sannolikhet ${(t.tip.probability * 100).round()}%',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(t.tip.odds.toStringAsFixed(2),
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1)),
                    Text(t.tip.oddsFromModel ? 'modellodds' : (t.odds?.bookmaker ?? 'odds'),
                        style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              // Hemma/borta eller totalt
              _ScopeToggle(total: _total, onChanged: (v) => setState(() => _total = v)),
              const SizedBox(height: 12),
              _Panel(
                child: Column(children: [
                  _PpgRow(home: hs?.ppg ?? 0, away: as_?.ppg ?? 0, played: (hs?.played ?? 0, as_?.played ?? 0)),
                  const SizedBox(height: 14),
                  _CompareRow('Gjorda mål/match', hs?.gfAvg, as_?.gfAvg, higherIsBetter: true),
                  _CompareRow('Insläppta mål/match', hs?.gaAvg, as_?.gaAvg, higherIsBetter: false),
                  _CompareRow('Över 2.5', hs?.over25Rate, as_?.over25Rate, percent: true),
                  _CompareRow('Båda gör mål', hs?.bttsRate, as_?.bttsRate, percent: true),
                  if (hs?.xgForAvg != null && as_?.xgForAvg != null) ...[
                    _CompareRow('xG för', hs!.xgForAvg, as_!.xgForAvg, higherIsBetter: true),
                    _CompareRow('xG emot', hs.xgAgainstAvg, as_.xgAgainstAvg, higherIsBetter: false),
                  ],
                ]),
              ),
              const SizedBox(height: 16),
              Text(_total ? 'Senaste matcherna' : 'Senaste hemma / borta',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: _RecentList(
                    title: f.home.name,
                    matches: hp?.recent(_total ? Venue.all : Venue.home) ?? const [],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _RecentList(
                    title: f.away.name,
                    matches: ap?.recent(_total ? Venue.all : Venue.away) ?? const [],
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              const Text('Sannolikheter', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              _ProbGrid(tip: t),
              const SizedBox(height: 16),
              if (t.streaks.isNotEmpty) ...[
                const Text('Streaks', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                for (final s in t.streaks) StreakRow(s),
                const SizedBox(height: 10),
              ],
              const Text('Analys', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              _Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final para in (t.deepAnalysis.isEmpty ? [t.comment] : t.deepAnalysis))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(para, style: const TextStyle(color: Color(0xFFC5CCE0), fontSize: 14, height: 1.45)),
                    ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [Color(0xFF18213D), Color(0xFF121A30)]),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: child,
      );
}

class _Header extends StatelessWidget {
  final MatchTip tip;
  const _Header({required this.tip});

  @override
  Widget build(BuildContext context) {
    final f = tip.fixture;
    Widget team(TeamRef t, List<String> form) => Expanded(
          child: Column(children: [
            TeamLogo(url: t.logo, size: 56),
            const SizedBox(height: 8),
            Text(t.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final r in form.reversed) FormDot(r)]),
          ]),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      team(f.home, tip.formHome),
      const Padding(
        padding: EdgeInsets.only(top: 18),
        child: Text('vs', style: TextStyle(color: AppColors.muted, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      team(f.away, tip.formAway),
    ]);
  }
}

class _ScopeToggle extends StatelessWidget {
  final bool total;
  final ValueChanged<bool> onChanged;
  const _ScopeToggle({required this.total, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool value) => Expanded(
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: total == value ? const Color(0xFF2A3A6B) : Colors.transparent,
              ),
              child: Text(label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: total == value ? AppColors.text : AppColors.muted,
                  )),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFF0E1428), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [seg('Hemma / Borta', false), seg('Totalt', true)]),
    );
  }
}

class _PpgRow extends StatelessWidget {
  final double home;
  final double away;
  final (int, int) played;
  const _PpgRow({required this.home, required this.away, required this.played});

  @override
  Widget build(BuildContext context) {
    final total = home + away;
    final share = total == 0 ? 0.5 : home / total;
    Widget big(double v, int n, bool better) => Column(children: [
          Text(v.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: better ? AppColors.accent : AppColors.text,
              )),
          Text('$n matcher', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ]);
    return Column(children: [
      Row(children: [
        Expanded(child: big(home, played.$1, home > away)),
        const Text('PPG', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        Expanded(child: big(away, played.$2, away > home)),
      ]),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          Expanded(flex: (share * 1000).round().clamp(1, 999), child: Container(height: 8, color: AppColors.accent)),
          Expanded(
              flex: ((1 - share) * 1000).round().clamp(1, 999),
              child: Container(height: 8, color: AppColors.accent2)),
        ]),
      ),
    ]);
  }
}

class _CompareRow extends StatelessWidget {
  final String label;
  final double? home;
  final double? away;
  final bool percent;
  final bool? higherIsBetter;
  const _CompareRow(this.label, this.home, this.away, {this.percent = false, this.higherIsBetter});

  @override
  Widget build(BuildContext context) {
    String fmt(double? v) => v == null ? '–' : (percent ? '${(v * 100).round()}%' : v.toStringAsFixed(2));
    bool best(double? a, double? b) {
      if (a == null || b == null || higherIsBetter == null || a == b) return false;
      return higherIsBetter! ? a > b : a < b;
    }

    TextStyle style(bool b) => TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: b ? AppColors.accent : AppColors.text,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(width: 64, child: Text(fmt(home), style: style(best(home, away)))),
        Expanded(
          child: Text(label,
              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ),
        SizedBox(
          width: 64,
          child: Text(fmt(away), textAlign: TextAlign.right, style: style(best(away, home))),
        ),
      ]),
    );
  }
}

class _RecentList extends StatelessWidget {
  final String title;
  final List<RecentMatch> matches;
  const _RecentList({required this.title, required this.matches});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        if (matches.isEmpty) const Text('Inga matcher', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        for (final m in matches)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              FormDot(m.result, margin: false),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${m.atHome ? 'H' : 'B'} ${m.opponent}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              ),
              Text('${m.goalsFor}–${m.goalsAgainst}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }
}

class _ProbGrid extends StatelessWidget {
  final MatchTip tip;
  const _ProbGrid({required this.tip});

  @override
  Widget build(BuildContext context) {
    final p = tip.prediction;
    final o = tip.odds;
    String od(double? v) => v == null ? '–' : v.toStringAsFixed(2);
    Widget cell(String label, double prob, double? odds, bool chosen) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: chosen ? AppColors.accent.withValues(alpha: 0.15) : const Color(0xFF0E1428),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: chosen ? AppColors.accent : Colors.transparent),
            ),
            child: Column(children: [
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              const SizedBox(height: 2),
              Text('${(prob * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(od(odds), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
          ),
        );
    final ty = tip.tip.type;
    return Row(children: [
      cell('1', p.pHome, o?.home, ty == BetType.home),
      cell('X', p.pDraw, o?.draw, ty == BetType.draw),
      cell('2', p.pAway, o?.away, ty == BetType.away),
      cell('Ö2.5', p.pOver25, o?.over25, ty == BetType.over25),
      cell('BLGM', p.pBtts, o?.bttsYes, ty == BetType.bttsYes),
    ]);
  }
}
