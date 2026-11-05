import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feeds.dart';
import 'theme.dart';
import 'web_page.dart';

const _builtIn = [
  TipSource('Aftonbladet Spel', 'Sportbladets speltips och analyser', 'https://www.aftonbladet.se/sportbladet/spel',
      feeds: ['https://rss.aftonbladet.se/rss2/small/pages/sections/sportbladet/'], onlyBetting: true),
  TipSource('Expressen Spel', 'Expressens speltips', 'https://www.expressen.se/sport/spel/',
      feeds: ['https://feeds.expressen.se/sport/'], onlyBetting: true),
  TipSource('Raka och klart', 'Svenska speltips', 'https://rakaochklart.se/'),
  TipSource('BetShoot', 'Dagliga fotbollstips från tipsare', 'https://www.betshoot.com/'),
  TipSource('BetRush', 'Fotbollstips och prediktioner', 'https://www.betrush.com/'),
  TipSource('Forebet', 'Statistiska prediktioner för dagens matcher',
      'https://www.forebet.com/en/football-tips-and-predictions-for-today'),
  TipSource('Bettingexpert', 'Tips från community-tipsare', 'https://www.bettingexpert.com/football'),
  TipSource('Oddsportal', 'Jämför odds mellan spelbolag', 'https://www.oddsportal.com/'),
];

/// Länkar till speltips på andra sidor. Sidorna öppnas i en webbläsarflik
/// inne i appen (eller i webbläsaren om det inte går).
class OtherTipsPage extends StatefulWidget {
  const OtherTipsPage({super.key});

  @override
  State<OtherTipsPage> createState() => _OtherTipsPageState();
}

class _OtherTipsPageState extends State<OtherTipsPage> {
  static const _prefKey = 'custom_tip_sites';
  List<TipSource> _custom = [];
  final _feeds = FeedService();
  List<FeedItem> _items = [];
  Set<String> _missing = {};
  bool _loading = true;
  String? _sourceFilter;

  @override
  void initState() {
    super.initState();
    _loadCustom().then((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    setState(() => _loading = true);
    final (items, missing) = await _feeds.fetchAll([..._builtIn, ..._custom], force: force);
    if (!mounted) return;
    setState(() {
      _items = items;
      _missing = missing;
      _loading = false;
    });
  }

  Future<void> _loadCustom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((j) => TipSource(j['n'] as String, 'Egen sida', j['u'] as String, custom: true))
          .toList();
      if (mounted) setState(() => _custom = list);
    } catch (_) {}
  }

  Future<void> _saveCustom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_custom.map((s) => {'n': s.name, 'u': s.url}).toList()));
  }

  Future<void> _open(TipSource s) => openInApp(context, s.url, s.name);

  Future<void> _add() async {
    final name = TextEditingController();
    final url = TextEditingController(text: 'https://');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Lägg till sida'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Namn')),
          const SizedBox(height: 8),
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Adress'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lägg till')),
        ],
      ),
    );
    if (ok != true) return;
    var u = url.text.trim();
    if (!u.startsWith('http')) u = 'https://$u';
    final n = name.text.trim().isEmpty ? Uri.parse(u).host : name.text.trim();
    setState(() => _custom = [..._custom, TipSource(n, 'Egen sida', u, custom: true)]);
    await _saveCustom();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final sites = [..._builtIn, ..._custom];
    final sources = {for (final i in _items) i.source}.toList();
    final shown = _sourceFilter == null ? _items : _items.where((i) => i.source == _sourceFilter).toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.bgTop,
          title: const Text('Andra speltips', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: const TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.text,
            unselectedLabelColor: AppColors.muted,
            tabs: [Tab(text: 'Senaste tipsen'), Tab(text: 'Sidor')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          backgroundColor: AppColors.accent,
          foregroundColor: const Color(0xFF0B1020),
          icon: const Icon(Icons.add),
          label: const Text('Lägg till sida'),
        ),
        body: TabBarView(children: [
          RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () => _refresh(force: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                if (sources.length > 1)
                  SizedBox(
                    height: 40,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final src in [null, ...sources])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(src ?? 'Alla'),
                            selected: _sourceFilter == src,
                            showCheckmark: false,
                            selectedColor: AppColors.accent,
                            labelStyle: TextStyle(
                              color: _sourceFilter == src ? const Color(0xFF0B1020) : AppColors.text,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) => setState(() => _sourceFilter = src),
                          ),
                        ),
                    ]),
                  ),
                const SizedBox(height: 8),
                if (_loading && _items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                  )
                else if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Text('Hittade inga flöden just nu. Dra nedåt för att försöka igen, eller öppna sidorna under "Sidor".',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                  ),
                for (final i in shown) _FeedCard(item: i, onTap: () => openInApp(context, i.link, i.source)),
                if (!_loading && _missing.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Utan flöde (öppna under Sidor): ${_missing.join(', ')}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ),
              ],
            ),
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              const Text('Tryck för att öppna i appen. Håll inne på en egen sida för att ta bort den.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 12),
          for (final s in sites)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _open(s),
                  onLongPress: s.custom
                      ? () async {
                          setState(() => _custom = _custom.where((c) => c.url != s.url).toList());
                          await _saveCustom();
                        }
                      : null,
                  child: Ink(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(colors: [Color(0xFF18213D), Color(0xFF121A30)]),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(colors: [AppColors.accent2, Color(0xFF6A5CFF)]),
                        ),
                        child: Text(s.name.characters.first.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          Text(s.custom ? '${s.url} · håll inne för att ta bort' : s.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ]),
                      ),
                      const Icon(Icons.open_in_new_rounded, color: AppColors.muted, size: 20),
                    ]),
                  ),
                ),
              ),
            ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _FeedCard extends StatelessWidget {
  final FeedItem item;
  final VoidCallback onTap;
  const _FeedCard({required this.item, required this.onTap});

  String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().toUtc().difference(d.toUtc());
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)} min sedan';
    if (diff.inHours < 24) return '${diff.inHours} tim sedan';
    return '${diff.inDays} d sedan';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(colors: [Color(0xFF18213D), Color(0xFF121A30)]),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (item.imageUrl != null)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  child: AspectRatio(
                    aspectRatio: 16 / 8,
                    child: Image.network(item.imageUrl!,
                        fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: const Color(0xFF0E1428))),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent2.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(item.source,
                          style: const TextStyle(color: AppColors.accent2, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    const Spacer(),
                    Text(_ago(item.published), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ]),
                  const SizedBox(height: 8),
                  Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.25)),
                  if (item.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(item.summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFC5CCE0), fontSize: 13, height: 1.4)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
