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

/// Скачивает подписку по ссылке. Приложение представляется как SHTORM.
/// Если панель не разрешает это приложение, она отдаёт заглушку
/// «App not supported», и мы показываем понятную ошибку.
Future<List<ServerEntry>> fetchSubscription(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    throw Exception('Это не похоже на ссылку подписки (нужна ссылка https://...)');
  }
  try {
    final r = await http
        .get(uri, headers: {'User-Agent': 'SHTORM/1.0'})
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw Exception('Ответ сервера: ${r.statusCode}');
    }
    final all = parseSubscriptionBody(r.body);
    final list = all
        .where((s) => !s.name.toLowerCase().contains('not supported'))
        .toList();
    if (list.isEmpty && all.isNotEmpty) {
      throw Exception(
          'Панель не разрешает это приложение (App not supported). '
          'Нужно добавить SHTORM/1.0 в разрешённые клиенты панели.');
    }
    if (list.isEmpty) {
      throw Exception('В подписке не нашлось серверов');
    }
    return list;
  } on Exception catch (e) {
    if (e.toString().startsWith('Exception: ')) rethrow;
    throw Exception('Не удалось загрузить подписку: $e');
  }
}
