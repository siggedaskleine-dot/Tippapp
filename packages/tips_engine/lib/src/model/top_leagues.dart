/// Ligor och turneringar med "kända lag" (api-footballs liga-id).
const topLeagueIds = <int>{
  // Europeiska cuper och landslag
  1, 2, 3, 4, 5, 9, 32, 848, 960,
  // England
  39, 40, 45, 48,
  // Spanien
  140, 143,
  // Italien
  135, 137,
  // Tyskland
  78, 81,
  // Frankrike
  61, 66,
  // Nederländerna, Portugal, Belgien, Skottland, Turkiet
  88, 94, 144, 179, 203,
  // Norden
  113, 114, 115, 119, 103,
  // Övriga stora
  71, 128, 253, 307,
};

bool isTopLeague(int leagueId) => topLeagueIds.contains(leagueId);

final _cupPattern = RegExp(
  r'\b(cup|cupen|pokal|coppa|copa|coupe|ta[cç]a|beker|trophy|shield|supercup|super cup|supercopa|supercoppa|'
  r'friendlies|friendly|play-?offs?)\b',
  caseSensitive: false,
);

/// Cupmatcher och träningsmatcher, utifrån turneringens namn
/// (fixtures-svaret saknar ligatyp). Champions League, Europa League och
/// Conference League räknas inte som cup här.
bool isCupCompetition(String leagueName) => _cupPattern.hasMatch(leagueName);
