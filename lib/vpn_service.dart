import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';

import 'subscription.dart';
import 'xray_config.dart';

enum VpnState { disconnected, connecting, connected, error }

/// Подключение: Android — через flutter_v2ray (VPN-режим на весь телефон),
/// Windows — через xray.exe рядом с приложением + системный прокси.
class VpnService extends ChangeNotifier {
  VpnState state = VpnState.disconnected;
  String? error;

  // Android
  FlutterV2ray? _v2ray;

  // Windows
  Process? _xray;
  final List<String> _xrayLog = [];

  static const _httpPort = 10809;
  static const _regKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  bool get isConnected => state == VpnState.connected;

  void _set(VpnState s, [String? err]) {
    state = s;
    error = err;
    notifyListeners();
  }

  Future<void> init() async {
    if (Platform.isAndroid) {
      _v2ray = FlutterV2ray(onStatusChanged: (status) {
        final st = status.state.toUpperCase();
        if (st == 'CONNECTED') {
          _set(VpnState.connected);
        } else if (st == 'CONNECTING') {
          _set(VpnState.connecting);
        } else if (st == 'DISCONNECTED' && state != VpnState.error) {
          _set(VpnState.disconnected);
        }
      });
      await _v2ray!.initializeV2Ray();
    }
  }

  Future<void> connect(ServerEntry server) async {
    _set(VpnState.connecting);
    try {
      if (Platform.isAndroid) {
        await _connectAndroid(server);
      } else if (Platform.isWindows) {
        await _connectWindows(server);
      } else {
        throw Exception('Эта платформа пока не поддерживается');
      }
    } catch (e) {
      _set(VpnState.error, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> disconnect() async {
    try {
      if (Platform.isAndroid) {
        _v2ray?.stopV2Ray();
      } else if (Platform.isWindows) {
        await _disconnectWindows();
      }
    } finally {
      _set(VpnState.disconnected);
    }
  }

  // ---------------- Android ----------------

  Future<void> _connectAndroid(ServerEntry server) async {
    final v2ray = _v2ray;
    if (v2ray == null) throw Exception('Ядро не запущено, перезапустите приложение');
    final parsed = FlutterV2ray.parseFromURL(server.link);
    final ok = await v2ray.requestPermission();
    if (!ok) throw Exception('Нужно разрешить создание VPN-подключения');
    v2ray.startV2Ray(
      remark: 'SHTORM',
      config: parsed.getFullConfiguration(),
      proxyOnly: false,
    );
    // Статус «подключено» придёт через onStatusChanged.
  }

  // ---------------- Windows ----------------

  Future<void> _connectWindows(ServerEntry server) async {
    await _disconnectWindows();

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final xrayPath = '$exeDir\\xray.exe';
    if (!File(xrayPath).existsSync()) {
      throw Exception('Не найден xray.exe рядом с приложением');
    }

    final cfg = buildXrayConfig(server.link, httpPort: _httpPort);
    final cfgFile = File('${Directory.systemTemp.path}\\shtorm_xray.json');
    await cfgFile.writeAsString(jsonEncode(cfg));

    _xrayLog.clear();
    final p = await Process.start(
      xrayPath,
      ['run', '-c', cfgFile.path],
      workingDirectory: exeDir,
    );
    _xray = p;
    void collect(List<int> data) {
      _xrayLog.addAll(utf8.decode(data, allowMalformed: true).split('\n'));
      if (_xrayLog.length > 20) {
        _xrayLog.removeRange(0, _xrayLog.length - 20);
      }
    }

    p.stdout.listen(collect);
    p.stderr.listen(collect);
    unawaited(p.exitCode.then((_) {
      if (_xray == p && state == VpnState.connected) {
        _xray = null;
        _setProxy(false);
        _set(VpnState.error, 'Соединение оборвалось');
      }
    }));

    // Если процесс упал сразу — конфиг или сервер не подошли.
    var died = false;
    await Future.any([
      p.exitCode.then((_) => died = true),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);
    if (died) {
      _xray = null;
      final tail = _xrayLog.where((l) => l.trim().isNotEmpty).join('\n');
      throw Exception('Xray не запустился. $tail');
    }

    await _setProxy(true);
    _set(VpnState.connected);
  }

  Future<void> _disconnectWindows() async {
    final p = _xray;
    _xray = null;
    p?.kill();
    await _setProxy(false);
  }

  Future<void> _setProxy(bool on) async {
    if (!Platform.isWindows) return;
    Future<void> reg(String name, String type, String value) =>
        Process.run('reg', [
          'add', _regKey, '/v', name, '/t', type, '/d', value, '/f',
        ]);
    if (on) {
      await reg('ProxyServer', 'REG_SZ', '127.0.0.1:$_httpPort');
      await reg('ProxyOverride', 'REG_SZ', '<local>');
      await reg('ProxyEnable', 'REG_DWORD', '1');
    } else {
      await reg('ProxyEnable', 'REG_DWORD', '0');
    }
  }

  /// Вызывается при закрытии приложения, чтобы не оставить включённый прокси.
  Future<void> shutdown() async {
    if (Platform.isWindows) await _disconnectWindows();
  }
}
