import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

class TipSite {
  final String name;
  final String description;
  final String url;
  final bool custom;
  const TipSite(this.name, this.description, this.url, {this.custom = false});

  Map<String, String> toJson() => {'n': name, 'u': url};
}

const _builtIn = [
  TipSite('Aftonbladet Spel', 'Sportbladets speltips och analyser', 'https://www.aftonbladet.se/sportbladet/spel'),
  TipSite('Expressen Spel', 'Expressens speltips', 'https://www.expressen.se/sport/spel/'),
  TipSite('Raka och klart', 'Svenska speltips', 'https://rakaochklart.se/'),
  TipSite('BetShoot', 'Dagliga fotbollstips från tipsare', 'https://www.betshoot.com/'),
  TipSite('BetRush', 'Fotbollstips och prediktioner', 'https://www.betrush.com/'),
  TipSite('Forebet', 'Statistiska prediktioner för dagens matcher',
      'https://www.forebet.com/en/football-tips-and-predictions-for-today'),
  TipSite('Bettingexpert', 'Tips från community-tipsare', 'https://www.bettingexpert.com/football'),
  TipSite('Oddsportal', 'Jämför odds mellan spelbolag', 'https://www.oddsportal.com/'),
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
  List<TipSite> _custom = [];

  @override
  void initState() {
    super.initState();
    _loadCustom();
  }

  Future<void> _loadCustom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((j) => TipSite(j['n'] as String, 'Egen sida', j['u'] as String, custom: true))
          .toList();
      if (mounted) setState(() => _custom = list);
    } catch (_) {}
  }

  Future<void> _saveCustom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_custom.map((s) => s.toJson()).toList()));
  }

  Future<void> _open(TipSite s) async {
    final uri = Uri.parse(s.url);
    final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView) ||
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunde inte öppna ${s.url}')));
    }
  }

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
    setState(() => _custom = [..._custom, TipSite(n, 'Egen sida', u, custom: true)]);
    await _saveCustom();
  }

  @override
  Widget build(BuildContext context) {
    final sites = [..._builtIn, ..._custom];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        title: const Text('Andra speltips', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF0B1020),
        icon: const Icon(Icons.add),
        label: const Text('Lägg till sida'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const Text('Jämför med vad andra tipsar. Sidorna öppnas i en webbläsarflik.',
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
    );
  }
}
