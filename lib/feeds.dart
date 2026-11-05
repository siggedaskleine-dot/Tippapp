import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

/// En artikel från en tipssidas RSS/Atom-flöde.
class FeedItem {
  final String source;
  final String title;
  final String summary;
  final String link;
  final String? imageUrl;
  final DateTime? published;
  const FeedItem({
    required this.source,
    required this.title,
    required this.summary,
    required this.link,
    this.imageUrl,
    this.published,
  });
}

/// En tipssida. [feeds] är kända flödesadresser att prova först, annars letar
/// appen själv efter ett flöde på sidan.
class TipSource {
  final String name;
  final String description;
  final String url;
  final List<String> feeds;

  /// Filtrera bort artiklar som inte handlar om spel (för breda sportflöden).
  final bool onlyBetting;
  final bool custom;
  const TipSource(this.name, this.description, this.url,
      {this.feeds = const [], this.onlyBetting = false, this.custom = false});
}

final _bettingWords = RegExp(
  r'spel|tips|odds|stryktips|europatips|topptips|bet|v75|v86|bomben|måltips|lång|trav',
  caseSensitive: false,
);

String _stripHtml(String s) {
  var t = s.replaceAll(RegExp(r'<[^>]*>'), ' ');
  const entities = {
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&nbsp;': ' ',
    '&#8217;': '’',
    '&#8211;': '–',
    '&#8220;': '“',
    '&#8221;': '”',
    '&hellip;': '…',
    '&#8230;': '…',
  };
  entities.forEach((k, v) => t = t.replaceAll(k, v));
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? _firstImg(String html) => RegExp(r'''<img[^>]+src=["']([^"']+)["']''').firstMatch(html)?.group(1);

DateTime? _date(String? s) {
  if (s == null || s.isEmpty) return null;
  final iso = DateTime.tryParse(s.trim());
  if (iso != null) return iso;
  // RFC 822 med tidszon som +0100.
  final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2})(?::(\d{2}))? ?([+-]\d{4})?').firstMatch(s);
  if (m == null) return null;
  const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  final mo = months.indexOf(m.group(2)!.toLowerCase()) + 1;
  if (mo == 0) return null;
  var d = DateTime.utc(int.parse(m.group(3)!), mo, int.parse(m.group(1)!), int.parse(m.group(4)!),
      int.parse(m.group(5)!), int.tryParse(m.group(6) ?? '0') ?? 0);
  final tz = m.group(7);
  if (tz != null) {
    final sign = tz.startsWith('-') ? -1 : 1;
    d = d.subtract(Duration(hours: sign * int.parse(tz.substring(1, 3)), minutes: sign * int.parse(tz.substring(3))));
  }
  return d;
}

/// Tolkar RSS 2.0 eller Atom. Returnerar null om texten inte är ett flöde.
List<FeedItem>? parseFeed(String body, String source) {
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(body);
  } catch (_) {
    return null;
  }
  String? text(XmlElement e, String name) {
    final c = e.findElements(name).firstOrNull ?? e.descendants.whereType<XmlElement>().where((x) => x.name.local == name).firstOrNull;
    return c?.innerText;
  }

  String? mediaUrl(XmlElement e) {
    for (final el in e.descendants.whereType<XmlElement>()) {
      final n = el.name.local;
      if ((n == 'content' || n == 'thumbnail') && el.name.prefix == 'media') {
        final u = el.getAttribute('url');
        if (u != null) return u;
      }
      if (n == 'enclosure' && (el.getAttribute('type') ?? '').startsWith('image')) {
        return el.getAttribute('url');
      }
    }
    return null;
  }

  final rssItems = doc.findAllElements('item').toList();
  if (rssItems.isNotEmpty) {
    return [
      for (final it in rssItems)
        () {
          final desc = text(it, 'description') ?? '';
          final encoded = it.descendants.whereType<XmlElement>().where((x) => x.name.local == 'encoded').firstOrNull?.innerText ?? '';
          return FeedItem(
            source: source,
            title: _stripHtml(text(it, 'title') ?? ''),
            summary: _stripHtml(desc),
            link: (text(it, 'link') ?? '').trim(),
            imageUrl: mediaUrl(it) ?? _firstImg(desc) ?? _firstImg(encoded),
            published: _date(text(it, 'pubDate') ?? text(it, 'date')),
          );
        }(),
    ];
  }
  final entries = doc.findAllElements('entry').toList();
  if (entries.isNotEmpty) {
    return [
      for (final e in entries)
        () {
          final link = e.findElements('link').where((l) => (l.getAttribute('rel') ?? 'alternate') == 'alternate').firstOrNull;
          final summary = text(e, 'summary') ?? text(e, 'content') ?? '';
          return FeedItem(
            source: source,
            title: _stripHtml(text(e, 'title') ?? ''),
            summary: _stripHtml(summary),
            link: link?.getAttribute('href') ?? '',
            imageUrl: mediaUrl(e) ?? _firstImg(summary),
            published: _date(text(e, 'published') ?? text(e, 'updated')),
          );
        }(),
    ];
  }
  return null;
}

/// Hämtar och slår ihop flöden. Den flödesadress som fungerade sparas så att
/// sökningen bara görs en gång per sida.
class FeedService {
  final http.Client _http;
  final _memo = <String, (DateTime, List<FeedItem>)>{};
  FeedService({http.Client? client}) : _http = client ?? http.Client();

  static const _headers = {'User-Agent': 'Mozilla/5.0 (Android) Fotbollstips/1.0'};

  Future<String?> _get(String url) async {
    try {
      final r = await _http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      return utf8.decode(r.bodyBytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  List<String> _candidates(TipSource s) {
    final base = s.url.endsWith('/') ? s.url.substring(0, s.url.length - 1) : s.url;
    final origin = Uri.parse(s.url).origin;
    return {
      ...s.feeds,
      '$base/feed/',
      '$base/rss',
      '$origin/feed/',
      '$origin/rss',
      '$origin/rss.xml',
      '$origin/feed.xml',
    }.toList();
  }

  Future<List<FeedItem>> fetch(TipSource s) async {
    final memo = _memo[s.url];
    if (memo != null && DateTime.now().difference(memo.$1) < const Duration(minutes: 30)) return memo.$2;

    final prefs = await SharedPreferences.getInstance();
    final key = 'feed_url_${s.url}';
    final known = prefs.getString(key);
    final tries = <String>[?known, ..._candidates(s)];

    List<FeedItem>? items;
    for (final url in tries) {
      final body = await _get(url);
      if (body == null) continue;
      items = parseFeed(body, s.name);
      if (items != null && items.isNotEmpty) {
        await prefs.setString(key, url);
        break;
      }
      // Kanske en HTML-sida som pekar ut sitt flöde.
      final link = RegExp(r'''<link[^>]+type=["']application/(?:rss|atom)\+xml["'][^>]*>''').firstMatch(body)?.group(0);
      final href = link == null ? null : RegExp(r'''href=["']([^"']+)["']''').firstMatch(link)?.group(1);
      if (href != null) {
        final feedUrl = Uri.parse(url).resolve(href).toString();
        final fb = await _get(feedUrl);
        items = fb == null ? null : parseFeed(fb, s.name);
        if (items != null && items.isNotEmpty) {
          await prefs.setString(key, feedUrl);
          break;
        }
      }
      items = null;
    }
    var out = items ?? const <FeedItem>[];
    if (s.onlyBetting) {
      final betting = out.where((i) => _bettingWords.hasMatch('${i.title} ${i.summary} ${i.link}')).toList();
      if (betting.isNotEmpty) out = betting;
    }
    out = out.where((i) => i.title.isNotEmpty && i.link.isNotEmpty).take(15).toList();
    _memo[s.url] = (DateTime.now(), out);
    return out;
  }

  /// Hämtar alla källor parallellt. Returnerar artiklar (nyast först) och
  /// vilka källor som saknar flöde.
  Future<(List<FeedItem>, Set<String>)> fetchAll(List<TipSource> sources, {bool force = false}) async {
    if (force) _memo.clear();
    final results = await Future.wait(sources.map(fetch));
    final all = <FeedItem>[];
    final missing = <String>{};
    for (var i = 0; i < sources.length; i++) {
      if (results[i].isEmpty) missing.add(sources[i].name);
      all.addAll(results[i]);
    }
    all.sort((a, b) => (b.published ?? DateTime(2000)).compareTo(a.published ?? DateTime(2000)));
    return (all, missing);
  }
}
