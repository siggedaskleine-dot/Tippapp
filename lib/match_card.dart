import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:tips_engine/tips_engine.dart';

import 'theme.dart';

Color ratingColor(TipRating r) => switch (r) {
      TipRating.value => AppColors.value,
      TipRating.fair => AppColors.fair,
      TipRating.weak => AppColors.weak,
      TipRating.modelOnly => AppColors.model,
    };

class MatchCard extends StatefulWidget {
  final MatchTip tip;
  const MatchCard({super.key, required this.tip});

  @override
  State<MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<MatchCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tip;
    final f = t.fixture;
    final rc = ratingColor(t.tip.rating);
    final time = DateFormat('HH:mm').format(f.kickoff.toLocal());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _open = !_open),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF18213D), Color(0xFF121A30)],
              ),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Liga och tid
                  Row(children: [
                    _Logo(url: f.league.flag ?? f.league.logo, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${f.league.country} · ${f.league.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E1428),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(time, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  // Lag
                  _TeamRow(team: f.home, form: t.formHome),
                  const SizedBox(height: 8),
                  _TeamRow(team: f.away, form: t.formAway),
                  const SizedBox(height: 14),
                  // Tips
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(colors: [rc.withValues(alpha: 0.28), rc.withValues(alpha: 0.10)]),
                        border: Border.all(color: rc.withValues(alpha: 0.6)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.tip.type.long,
                            style: TextStyle(color: rc, fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(t.tip.rating.label,
                            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      ]),
                    ),
                    const Spacer(),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(t.tip.odds.toStringAsFixed(2),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1)),
                      Text(t.tip.oddsFromModel ? 'modellodds' : (t.odds?.bookmaker ?? 'odds'),
                          style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  _ProbBar(p: t.tip.probability, color: rc),
                  const SizedBox(height: 12),
                  Text(t.comment, style: const TextStyle(color: Color(0xFFC5CCE0), fontSize: 13, height: 1.4)),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: _Details(tip: t),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  final TeamRef team;
  final List<String> form;
  const _TeamRow({required this.team, required this.form});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _Logo(url: team.logo, size: 26),
      const SizedBox(width: 10),
      Expanded(
        child: Text(team.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      for (final r in form.reversed) _FormDot(r),
    ]);
  }
}

class _FormDot extends StatelessWidget {
  final String r;
  const _FormDot(this.r);

  @override
  Widget build(BuildContext context) {
    final c = r == 'V' ? AppColors.win : r == 'O' ? AppColors.draw : AppColors.loss;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6)),
      child: Text(r, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}

class _ProbBar extends StatelessWidget {
  final double p;
  final Color color;
  const _ProbBar({required this.p, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Text('Sannolikhet', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(width: 10),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(children: [
            Container(height: 8, color: const Color(0xFF0E1428)),
            FractionallySizedBox(
              widthFactor: p.clamp(0, 1),
              child: Container(
                height: 8,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withValues(alpha: 0.6), color])),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      Text('${(p * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
    ]);
  }
}

class _Details extends StatelessWidget {
  final MatchTip tip;
  const _Details({required this.tip});

  @override
  Widget build(BuildContext context) {
    final p = tip.prediction;
    final o = tip.odds;
    String od(double? v) => v == null ? '–' : v.toStringAsFixed(2);
    Widget cell(String label, double prob, double? odds) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFF0E1428), borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              const SizedBox(height: 2),
              Text('${(prob * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(od(odds), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          cell('1', p.pHome, o?.home),
          cell('X', p.pDraw, o?.draw),
          cell('2', p.pAway, o?.away),
          cell('Ö2.5', p.pOver25, o?.over25),
          cell('BLGM', p.pBtts, o?.bttsYes),
        ]),
        const SizedBox(height: 10),
        Text(
          'Väntat resultat ${p.lambdaHome.toStringAsFixed(1)}–${p.lambdaAway.toStringAsFixed(1)} · '
          'PPG ${p.ppgHome.toStringAsFixed(2)} / ${p.ppgAway.toStringAsFixed(2)}'
          '${p.usedXg ? ' · xG med' : ' · utan xG'}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ]),
    );
  }
}

class _Logo extends StatelessWidget {
  final String? url;
  final double size;
  const _Logo({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: const Color(0xFF243055), borderRadius: BorderRadius.circular(size / 2)),
    );
    if (url == null || url!.isEmpty) return placeholder;
    if (url!.endsWith('.svg')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SvgPicture.network(url!, width: size, height: size * 0.75, fit: BoxFit.cover,
            placeholderBuilder: (_) => placeholder),
      );
    }
    return Image.network(
      url!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
