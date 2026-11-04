import 'dart:convert';
import 'dart:io';

import 'package:tips_engine/tips_engine.dart';

/// Kör motorn från terminalen:
///   API_FOOTBALL_KEY=... dart run bin/tips.dart [dag 0|1|2] [sortering] [--json]
/// Sortering: tid, odds, form, sannolikhet.
Future<void> main(List<String> args) async {
  final key = Platform.environment['API_FOOTBALL_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('Sätt miljövariabeln API_FOOTBALL_KEY.');
    exit(64);
  }
  final pos = args.where((a) => !a.startsWith('--')).toList();
  final day = pos.isNotEmpty ? int.parse(pos[0]) : 0;
  final sort = switch (pos.length > 1 ? pos[1] : 'tid') {
    'odds' => SortBy.odds,
    'form' => SortBy.form,
    'sannolikhet' => SortBy.probability,
    _ => SortBy.kickoff,
  };

  final api = ApiFootballClient(apiKey: key, cache: FileCache('.cache'));
  final engine = TipsEngine(api);
  final res = await engine.tipsForDay(day, onProgress: (m) => stderr.writeln('… $m'));
  sortTips(res.tips, sort);

  if (args.contains('--json')) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(res.tips.map((t) => t.toJson()).toList()));
  } else {
    for (final t in res.tips) {
      final k = t.fixture.kickoff.toLocal();
      final hh = '${k.hour.toString().padLeft(2, '0')}:${k.minute.toString().padLeft(2, '0')}';
      stdout.writeln('$hh  ${t.fixture.league.country} / ${t.fixture.league.name}');
      stdout.writeln('       ${t.fixture.home.name} – ${t.fixture.away.name}   '
          '[${t.tip.type.short} @ ${t.tip.odds.toStringAsFixed(2)}${t.tip.oddsFromModel ? '*' : ''}]');
      stdout.writeln('       ${t.comment}\n');
    }
  }
  stderr.writeln('${res.tips.length} matcher, ${res.networkCalls} API-anrop, '
      '${res.remainingToday ?? '?'} kvar idag.');
  for (final w in res.warnings) {
    stderr.writeln('Varning: $w');
  }
  api.close();
}
