import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tips_engine/tips_engine.dart';

import 'history.dart';
import 'repository.dart';
import 'theme.dart';

/// Visar hur de sparade tipsen har gått: träffprocent och resultat om man
/// satsat 1 enhet på varje tips.
class FacitPage extends StatefulWidget {
  final TipHistory history;
  final TipsRepository repo;
  const FacitPage({super.key, required this.history, required this.repo});

  @override
  State<FacitPage> createState() => _FacitPageState();
}

class _FacitPageState extends State<FacitPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await widget.history.settleAll(widget.repo.fixturesOn);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.history.all;
    final settled = all.where((t) => t.outcome == TipOutcome.won || t.outcome == TipOutcome.lost).toList();
    final won = settled.where((t) => t.outcome == TipOutcome.won).toList();
    final profit = won.fold<double>(0, (s, t) => s + t.odds) - settled.length;
    final hit = settled.isEmpty ? 0.0 : won.length / settled.length;
    final roi = settled.isEmpty ? 0.0 : profit / settled.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        title: const Text('Facit', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              _Stat('Rättade tips', '${settled.length}'),
              _Stat('Träff', '${(hit * 100).round()}%'),
              _Stat('Netto (1 kr/tips)', '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(1)} kr',
                  color: profit >= 0 ? AppColors.win : AppColors.loss),
            ]),
            const SizedBox(height: 8),
            Text(
              settled.isEmpty
                  ? 'Tips i oddsfönstret sparas automatiskt när du öppnar en dag, och rättas här när matcherna är spelade.'
                  : 'Avkastning ${(roi * 100).toStringAsFixed(1)} % per spelad krona.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            for (final type in BetType.values) _TypeRow(type: type, tips: settled),
            const SizedBox(height: 16),
            for (final t in all) _TipRow(t),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Stat(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
        ),
      );
}

class _TypeRow extends StatelessWidget {
  final BetType type;
  final List<SavedTip> tips;
  const _TypeRow({required this.type, required this.tips});

  @override
  Widget build(BuildContext context) {
    final mine = tips.where((t) => t.type == type).toList();
    if (mine.isEmpty) return const SizedBox.shrink();
    final won = mine.where((t) => t.outcome == TipOutcome.won).toList();
    final profit = won.fold<double>(0, (s, t) => s + t.odds) - mine.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 150, child: Text(type.long, style: const TextStyle(fontWeight: FontWeight.w600))),
        Text('${won.length}/${mine.length}', style: const TextStyle(color: AppColors.muted)),
        const Spacer(),
        Text('${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(1)} kr',
            style: TextStyle(color: profit >= 0 ? AppColors.win : AppColors.loss, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _TipRow extends StatelessWidget {
  final SavedTip t;
  const _TipRow(this.t);

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (t.outcome) {
      TipOutcome.won => (Icons.check_circle_rounded, AppColors.win),
      TipOutcome.lost => (Icons.cancel_rounded, AppColors.loss),
      TipOutcome.voided => (Icons.remove_circle_outline, AppColors.muted),
      TipOutcome.pending => (Icons.schedule_rounded, AppColors.muted),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t.home} – ${t.away}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '${DateFormat('d MMM HH:mm', 'sv_SE').format(t.kickoff.toLocal())} · ${t.type.long} @ ${t.odds.toStringAsFixed(2)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ]),
        ),
        if (t.score != null) Text(t.score!, style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
