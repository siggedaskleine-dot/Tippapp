import 'package:path_provider/path_provider.dart';

import 'demo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tips_engine/tips_engine.dart';

/// Håller API-nyckeln och motorn. Nyckeln matas in i appen första gången och
/// sparas bara på telefonen. Den kan också byggas in med
/// --dart-define=API_FOOTBALL_KEY=... om man vill.
class TipsRepository {
  static const _prefKey = 'api_football_key';
  static const _builtInKey = String.fromEnvironment('API_FOOTBALL_KEY');
  static const _demo = bool.fromEnvironment('DEMO');

  TipsEngine? _engine;
  ApiFootballClient? _api;
  String? _key;

  final _cacheByDay = <int, DayResult>{};

  double minOdds = 1.70;
  double maxOdds = 2.10;

  int? get remainingToday => _api?.remainingToday;

  /// Ändrar oddsfönstret. Tipsen räknas om från cachen nästa gång en dag laddas.
  Future<void> setOddsRange(double min, double max) async {
    minOdds = min;
    maxOdds = max;
    _engine?.selector = TipSelector.forRange(min, max);
    _cacheByDay.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('min_odds', min);
    await prefs.setDouble('max_odds', max);
  }
  bool get hasKey => (_key ?? '').isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    minOdds = prefs.getDouble('min_odds') ?? 1.70;
    maxOdds = prefs.getDouble('max_odds') ?? 2.10;
    if (_demo) {
      _key = 'demo';
      _api = ApiFootballClient(apiKey: 'demo', cache: MemoryCache(), httpClient: demoClient());
      _engine = TipsEngine(_api!, selector: TipSelector.forRange(minOdds, maxOdds));
      return;
    }
    _key = prefs.getString(_prefKey);
    if ((_key ?? '').isEmpty && _builtInKey.isNotEmpty) _key = _builtInKey;
    if (hasKey) await _build();
  }

  Future<void> setKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, key.trim());
    _key = key.trim();
    _cacheByDay.clear();
    await _build();
  }

  Future<void> _build() async {
    _api?.close();
    final dir = await getApplicationCacheDirectory();
    _api = ApiFootballClient(apiKey: _key!, cache: FileCache('${dir.path}/api'));
    _engine = TipsEngine(_api!, selector: TipSelector.forRange(minOdds, maxOdds));
  }

  /// Alla matcher ett datum (för att rätta facit).
  Future<List<Fixture>> fixturesOn(DateTime day) {
    final api = _api;
    if (api == null) return Future.value(const []);
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
    return api.fixturesByDate(day, isToday: isToday);
  }

  Future<DayResult> load(int day, {bool force = false, void Function(String)? onProgress}) async {
    if (!force && _cacheByDay.containsKey(day)) return _cacheByDay[day]!;
    final engine = _engine;
    if (engine == null) throw StateError('Ingen API-nyckel');
    final res = await engine.tipsForDay(day, onProgress: onProgress);
    _cacheByDay[day] = res;
    return res;
  }
}
