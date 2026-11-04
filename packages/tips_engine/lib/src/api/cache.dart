import 'dart:convert';
import 'dart:io';

/// Enkel nyckel/värde-cache med utgångstid. I Flutter-appen pekas
/// [FileCache] på katalogen från path_provider.
abstract class CacheStore {
  Future<String?> get(String key);
  Future<void> put(String key, String value, Duration ttl);
}

class MemoryCache implements CacheStore {
  final _data = <String, (DateTime, String)>{};
  DateTime Function() now;
  MemoryCache({DateTime Function()? now}) : now = now ?? DateTime.now;

  @override
  Future<String?> get(String key) async {
    final e = _data[key];
    if (e == null) return null;
    if (now().isAfter(e.$1)) {
      _data.remove(key);
      return null;
    }
    return e.$2;
  }

  @override
  Future<void> put(String key, String value, Duration ttl) async {
    _data[key] = (now().add(ttl), value);
  }
}

class FileCache implements CacheStore {
  final Directory dir;
  FileCache(String path) : dir = Directory(path);

  File _file(String key) {
    final safe = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    // Långa nycklar (t.ex. 20 match-id:n) kortas med en hash så att
    // filnamnet håller sig under filsystemets gräns.
    final name = safe.length > 120 ? '${safe.substring(0, 80)}_${key.hashCode.toUnsigned(32)}' : safe;
    return File('${dir.path}/$name.json');
  }

  @override
  Future<String?> get(String key) async {
    final f = _file(key);
    if (!await f.exists()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (j['key'] != key) return null;
      final exp = DateTime.parse(j['expires'] as String);
      if (DateTime.now().isAfter(exp)) {
        await f.delete();
        return null;
      }
      return j['value'] as String;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> put(String key, String value, Duration ttl) async {
    await dir.create(recursive: true);
    final exp = DateTime.now().add(ttl).toIso8601String();
    await _file(key).writeAsString(jsonEncode({'key': key, 'expires': exp, 'value': value}));
  }
}
