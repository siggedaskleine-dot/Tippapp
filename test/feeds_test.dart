import 'package:flutter_test/flutter_test.dart';
import 'package:fotbollstips/feeds.dart';

void main() {
  test('RSS 2.0 med bild och datum', () {
    const rss = '''<?xml version="1.0"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
<channel><title>X</title>
<item>
  <title>Speltips: Allsvenskan &amp; mer</title>
  <link>https://example.se/a</link>
  <description><![CDATA[<p>Vi tror på <b>hemmaseger</b>.</p><img src="https://example.se/i.jpg">]]></description>
  <pubDate>Wed, 05 Nov 2026 08:30:00 +0100</pubDate>
</item>
<item>
  <title>Annan nyhet</title>
  <link>https://example.se/b</link>
  <media:content url="https://example.se/m.jpg"/>
</item>
</channel></rss>''';
    final items = parseFeed(rss, 'Test')!;
    expect(items, hasLength(2));
    expect(items[0].title, 'Speltips: Allsvenskan & mer');
    expect(items[0].summary, 'Vi tror på hemmaseger .');
    expect(items[0].imageUrl, 'https://example.se/i.jpg');
    expect(items[0].published, DateTime.utc(2026, 11, 5, 7, 30));
    expect(items[1].imageUrl, 'https://example.se/m.jpg');
  });

  test('Atom', () {
    const atom = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>Y</title>
<entry><title>Dagens tips</title><link href="https://y.com/1"/><summary>Över 2.5</summary>
<updated>2026-11-05T09:00:00Z</updated></entry></feed>''';
    final items = parseFeed(atom, 'Y')!;
    expect(items.single.link, 'https://y.com/1');
    expect(items.single.published, DateTime.utc(2026, 11, 5, 9));
  });

  test('HTML är inget flöde', () {
    expect(parseFeed('<html><body>hej</body></html>', 'Z'), isNull);
  });

  test('bara speltips, inte vanliga sportnyheter', () {
    FeedItem f(String t, [String s = '', String l = 'https://x.se/a']) =>
        FeedItem(source: 'X', title: t, summary: s, link: l);
    expect(isBettingTip(f('Speltips: så spelar vi Stryktipset')), isTrue);
    expect(isBettingTip(f('Arsenal vs Chelsea Prediction and Betting Tips')), isTrue);
    expect(isBettingTip(f('Dagens spel', 'Över 2.5 mål i Bundesliga')), isTrue);
    expect(isBettingTip(f('Ny tränare klar för AIK')), isFalse);
    expect(isBettingTip(f('Spelaren skadad inför derbyt', 'Han missar matchen')), isFalse);
    expect(isBettingTip(f('Hammarby vann igen', '', 'https://x.se/sport/fotboll/123')), isFalse);
  });
}
