import 'dart:convert';
import 'package:http/http.dart' as http;

/// Один сервер из подписки.
class ServerEntry {
  final String name;
  final String link;
  const ServerEntry(this.name, this.link);

  String get scheme => link.split('://').first.toLowerCase();

  Map<String, String> toJson() => {'name': name, 'link': link};
  factory ServerEntry.fromJson(Map<String, dynamic> j) =>
      ServerEntry(j['name'] as String, j['link'] as String);
}

const _schemes = ['vless', 'vmess', 'trojan', 'ss'];

/// Разбирает тело подписки: обычный список ссылок или base64.
List<ServerEntry> parseSubscriptionBody(String body) {
  var text = body.trim();
  if (!text.contains('://')) {
    try {
      final cleaned = text
          .replaceAll(RegExp(r'\s'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      text = utf8.decode(base64.decode(base64.normalize(cleaned)));
    } catch (_) {
      return [];
    }
  }
  final result = <ServerEntry>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final scheme = line.split('://').first.toLowerCase();
    if (!_schemes.contains(scheme)) continue;
    var name = scheme.toUpperCase();
    final hash = line.indexOf('#');
    if (hash != -1 && hash < line.length - 1) {
      try {
        name = Uri.decodeComponent(line.substring(hash + 1));
      } catch (_) {
        name = line.substring(hash + 1);
      }
    }
    result.add(ServerEntry(name, line));
  }
  return result;
}

/// Скачивает подписку по ссылке. Панель отдаёт конфиг только известным
/// приложениям (по User-Agent), поэтому пробуем несколько вариантов
/// и пропускаем заглушку «App not supported».
Future<List<ServerEntry>> fetchSubscription(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    throw Exception('Это не похоже на ссылку подписки (нужна ссылка https://...)');
  }
  Object? lastError;
  for (final ua in const [
    'Happ/2.3.0',
    'INCY/1.0',
    'v2rayNG/1.8.29',
    'SHTORM/1.0',
  ]) {
    try {
      final r = await http
          .get(uri, headers: {'User-Agent': ua})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        lastError = 'Ответ сервера: ${r.statusCode}';
        continue;
      }
      final list = parseSubscriptionBody(r.body)
          .where((s) => !s.name.toLowerCase().contains('not supported'))
          .toList();
      if (list.isNotEmpty) return list;
      lastError = 'Панель не отдала серверы (приложение не распознано)';
    } catch (e) {
      lastError = e;
    }
  }
  throw Exception('Не удалось загрузить подписку: $lastError');
}
