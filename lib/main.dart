import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tips_engine/tips_engine.dart';

import 'facit_page.dart';
import 'history.dart';
import 'match_card.dart';
import 'other_tips_page.dart';
import 'repository.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('sv_SE');
  final repo = TipsRepository();
  await repo.init();
  final history = TipHistory();
  await history.load();
  runApp(TipsApp(repo: repo, history: history));
}

class TipsApp extends StatelessWidget {
  final TipsRepository repo;
  final TipHistory history;
  const TipsApp({super.key, required this.repo, required this.history});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fotbollstips',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomePage(repo: repo, history: history),
    );
  }
}

class HomePage extends StatefulWidget {
  final TipsRepository repo;
  final TipHistory history;
  const HomePage({super.key, required this.repo, required this.history});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _day = 0;
  SortBy _sort = SortBy.form;
  bool _onlyOdds = true;
  bool _onlyWindow = true;
  bool _onlyTop = false;
  bool _hideCups = false;
  bool _hideYouth = true;
  int _minPlayed = 5;
  MarketFilter _market = MarketFilter.all;
  bool _onlyValue = false;
  String _query = '';
  DayResult? _result;
  String? _error;
  String? _progress;
  bool _loading = false;

  TipsRepository get repo => widget.repo;

  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Uppdatera listan varje minut så att matcher som startar försvinner.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    SharedPreferences.getInstance().then((prefs) {
      final v = prefs.getInt('min_played');
      if (v != null && mounted) setState(() => _minPlayed = v);
    });
    if (repo.hasKey) {
      _load();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askKey());
    }
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = 'Startar';
    });
    try {
      final res = await repo.load(_day, force: force, onProgress: (m) {
        if (mounted) setState(() => _progress = m);
      });
      await widget.history.record(res.tipsFor(_market));
      if (!mounted) return;
      setState(() => _result = res);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _askKey() async {
    final ctrl = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      barrierDismissible: repo.hasKey,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('API-nyckel'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Klistra in din nyckel från api-football.com. Den sparas bara på telefonen.',
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Nyckel', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          if (repo.hasKey) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Spara')),
        ],
      ),
    );
    if (key != null && key.trim().isNotEmpty) {
      await repo.setKey(key);
      _load(force: true);
    }
  }

  List<MatchTip> get _visible {
    final res = _result;
    if (res == null) return const [];
    final q = _query.toLowerCase();
    final now = DateTime.now().toUtc();
    final list = res.tipsFor(_market).where((t) {
      // Bara kommande matcher: allt som startat eller är klart döljs.
      if (!t.fixture.notStarted || !t.fixture.kickoff.isAfter(now)) return false;
      if (repo.requireForm && t.formReason == null) return false;
      if (_onlyOdds && t.tip.oddsFromModel) return false;
      if (_onlyWindow && !t.inOddsWindow) return false;
      if (t.minPlayed < _minPlayed) return false;
      if (_onlyTop && !isTopLeague(t.fixture.league.id)) return false;
      if (_hideCups && isCupCompetition(t.fixture.league.name)) return false;
      if (_hideYouth && isYouthMatch(t.fixture)) return false;
      if (_onlyValue && t.tip.rating != TipRating.value) return false;
      if (q.isNotEmpty) {
        final f = t.fixture;
        final hay = '${f.home.name} ${f.away.name} ${f.league.name} ${f.league.country}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    sortTips(list, _sort);
    return list;
  }

  String _dayLabel(int d) {
    final date = DateTime.now().add(Duration(days: d));
    final name = ['Idag', 'Imorgon', 'Övermorgon'][d];
    return '$name\n${DateFormat('d MMM', 'sv_SE').format(date)}';
  }

  @override
  Widget build(BuildContext context) {
    final tips = _visible;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgTop, AppColors.bg],
            stops: [0, 0.4],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () => _load(force: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _dayTabs()),
                SliverToBoxAdapter(child: _controls()),
                if (_loading && _result == null)
                  SliverFillRemaining(hasScrollBody: false, child: _loadingView())
                else if (_error != null && _result == null)
                  SliverFillRemaining(hasScrollBody: false, child: _errorView())
                else if (tips.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          repo.requireForm
                              ? 'Inga formspel matchar filtret.\nLag i bra form har ofta låga odds, så prova ett lägre önskat odds eller slå av Formspel.'
                              : 'Inga matcher matchar filtret',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted, height: 1.4),
                        ),
                      ),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: tips.length,
                    itemBuilder: (_, i) => MatchCard(key: ValueKey(tips[i].fixture.id), tip: tips[i]),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final res = _result;
    final sub = res == null
        ? 'Tips med odds runt ${repo.targetOdds.toStringAsFixed(2)} (${_oddsText()})'
        : '${_visible.length} av ${res.tips.length} matcher'
            '${repo.remainingToday != null ? ' · ${repo.remainingToday} anrop kvar' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accent2]),
          ),
          child: const Icon(Icons.sports_soccer, color: Color(0xFF0B1020)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Fotbollstips', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
        if (_loading && _result != null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        IconButton(
          tooltip: 'Andra speltips',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OtherTipsPage())),
          icon: const Icon(Icons.public_rounded, color: AppColors.accent2),
        ),
        IconButton(
          tooltip: 'Facit',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FacitPage(history: widget.history, repo: repo),
          )),
          icon: const Icon(Icons.insights_rounded, color: AppColors.accent),
        ),
        IconButton(onPressed: _askKey, icon: const Icon(Icons.key_rounded, color: AppColors.muted)),
      ]),
    );
  }

  Widget _dayTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFF0E1428), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          for (var d = 0; d < 3; d++)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_day == d) return;
                  setState(() {
                    _day = d;
                    _result = null;
                  });
                  _load();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: _day == d
                        ? const LinearGradient(colors: [Color(0xFF2A3A6B), Color(0xFF223058)])
                        : null,
                  ),
                  child: Text(
                    _dayLabel(d),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: _day == d ? FontWeight.w700 : FontWeight.w500,
                      color: _day == d ? AppColors.text : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  String _oddsText() => '${repo.minOdds.toStringAsFixed(2)}–${repo.maxOdds.toStringAsFixed(2)}';

  Future<void> _editOdds() async {
    var target = repo.targetOdds;
    var spread = repo.spread;
    final picked = await showModalBottomSheet<(double, double)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget pill(String label, bool selected, Color color, VoidCallback onTap) => GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? color : const Color(0xFF0E1428),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? color : AppColors.cardBorder),
                  ),
                  child: Text(label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected ? const Color(0xFF0B1020) : AppColors.text,
                      )),
                ),
              );
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Rubrik med Spara alltid synlig överst
                Row(children: [
                  const Expanded(
                    child: Text('Önskat odds', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, (target, spread)),
                    child: const Text('Spara'),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(target.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.accent)),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                        'tips mellan ${(target - spread).toStringAsFixed(2)} och ${(target + spread).toStringAsFixed(2)}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ),
                ]),
                Slider(
                  value: target.clamp(1.30, 4.00),
                  min: 1.30,
                  max: 4.00,
                  divisions: 54,
                  activeColor: AppColors.accent,
                  label: target.toStringAsFixed(2),
                  onChanged: (v) => setSheet(() => target = double.parse(v.toStringAsFixed(2))),
                ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final v in const [1.40, 1.50, 1.70, 1.90, 2.20, 2.50, 3.00])
                    pill(v.toStringAsFixed(2), (target - v).abs() < 0.001, AppColors.accent,
                        () => setSheet(() => target = v)),
                ]),
                const SizedBox(height: 16),
                const Text('Spann', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final v in const [0.10, 0.20, 0.30, 0.50])
                    pill('± ${v.toStringAsFixed(2)}', (spread - v).abs() < 0.001, AppColors.accent2,
                        () => setSheet(() => spread = v)),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, (target, spread)),
                    child: const Padding(padding: EdgeInsets.all(12), child: Text('Spara')),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (picked == null) return;
    await repo.setTargetOdds(picked.$1, picked.$2);
    setState(() => _result = null);
    _load();
  }

  Widget _marketTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        for (final m in MarketFilter.values)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: m == MarketFilter.values.last ? 0 : 6),
              child: GestureDetector(
                onTap: () {
                  setState(() => _market = m);
                  final res = _result;
                  if (res != null) widget.history.record(res.tipsFor(m));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: _market == m
                        ? const LinearGradient(colors: [AppColors.accent2, Color(0xFF6A5CFF)])
                        : null,
                    color: _market == m ? null : const Color(0xFF151D35),
                    border: Border.all(color: _market == m ? Colors.transparent : AppColors.cardBorder),
                  ),
                  child: Text(m.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _market == m ? Colors.white : AppColors.muted,
                      )),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _controls() {
    Widget chip(String label, SortBy s, IconData icon) {
      final on = _sort == s;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          avatar: Icon(icon, size: 16, color: on ? const Color(0xFF0B1020) : AppColors.muted),
          label: Text(label),
          selected: on,
          showCheckmark: false,
          selectedColor: AppColors.accent,
          backgroundColor: const Color(0xFF151D35),
          side: BorderSide(color: on ? AppColors.accent : AppColors.cardBorder),
          labelStyle: TextStyle(
            color: on ? const Color(0xFF0B1020) : AppColors.text,
            fontWeight: FontWeight.w600,
          ),
          onSelected: (_) => setState(() => _sort = s),
        ),
      );
    }

    Widget toggle(String label, bool value, ValueChanged<bool> on) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Text(label),
            selected: value,
            selectedColor: const Color(0xFF223058),
            backgroundColor: const Color(0xFF151D35),
            checkmarkColor: AppColors.accent,
            side: const BorderSide(color: AppColors.cardBorder),
            onSelected: on,
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Sök lag, liga eller land',
              prefixIcon: const Icon(Icons.search, color: AppColors.muted),
              filled: true,
              fillColor: const Color(0xFF151D35),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _marketTabs(),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            chip('Tid', SortBy.kickoff, Icons.schedule),
            chip('Odds', SortBy.odds, Icons.trending_up),
            chip('Form', SortBy.form, Icons.local_fire_department),
            chip('Sannolikhet', SortBy.probability, Icons.percent),
          ]),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.tune_rounded, size: 16, color: AppColors.accent),
                label: Text('Odds ${repo.targetOdds.toStringAsFixed(2)}'),
                backgroundColor: const Color(0xFF223058),
                side: const BorderSide(color: AppColors.cardBorder),
                onPressed: _editOdds,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PopupMenuButton<int>(
                initialValue: _minPlayed,
                color: AppColors.card,
                onSelected: (v) {
                  setState(() => _minPlayed = v);
                  SharedPreferences.getInstance().then((p) => p.setInt('min_played', v));
                },
                itemBuilder: (_) => [
                  for (var n = 0; n <= 5; n++)
                    PopupMenuItem(value: n, child: Text(n == 0 ? 'Inget krav' : n == 1 ? 'Minst 1 spelad match' : 'Minst $n spelade matcher')),
                ],
                child: Chip(
                  avatar: const Icon(Icons.filter_list_rounded, size: 16, color: AppColors.accent),
                  label: Text(_minPlayed == 0 ? 'Matcher: alla' : _minPlayed == 1 ? 'Minst 1 match' : 'Minst $_minPlayed matcher'),
                  backgroundColor: const Color(0xFF223058),
                  side: const BorderSide(color: AppColors.cardBorder),
                ),
              ),
            ),
            toggle('Formspel', repo.requireForm, (v) async {
              await repo.setRequireForm(v);
              _load();
            }),
            toggle('Kända lag', _onlyTop, (v) => setState(() => _onlyTop = v)),
            toggle('Dölj cupmatcher', _hideCups, (v) => setState(() => _hideCups = v)),
            toggle('Dölj ungdom', _hideYouth, (v) => setState(() => _hideYouth = v)),
            toggle('Bara inom oddsen', _onlyWindow, (v) => setState(() => _onlyWindow = v)),
            toggle('Bara med odds', _onlyOdds, (v) => setState(() => _onlyOdds = v)),
            toggle('Bara spelvärde', _onlyValue, (v) => setState(() => _onlyValue = v)),
          ]),
        ),
      ]),
    );
  }

  Widget _loadingView() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: AppColors.accent),
          const SizedBox(height: 16),
          Text(_progress ?? '', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 4),
          const Text('Första hämtningen för dagen tar en stund',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.weak, size: 40),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => _load(force: true), child: const Text('Försök igen')),
          ]),
        ),
      );
}
