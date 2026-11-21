import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subscription.dart';
import 'vpn_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShtormApp());
}

class ShtormApp extends StatelessWidget {
  const ShtormApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF22B8F0);
    return MaterialApp(
      title: 'SHTORM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _accent = Color(0xFF22B8F0);

  final _vpn = VpnService();
  final _linkCtrl = TextEditingController();

  List<ServerEntry> _servers = [];
  int _selected = 0;
  bool _loading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vpn.addListener(() => setState(() {}));
    _boot();
  }

  Future<void> _boot() async {
    await _vpn.init();
    final p = await SharedPreferences.getInstance();
    final link = p.getString('sub_url');
    final raw = p.getString('servers');
    if (link != null) _linkCtrl.text = link;
    if (raw != null) {
      try {
        _servers = (jsonDecode(raw) as List)
            .map((e) => ServerEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        _selected = (p.getInt('selected') ?? 0).clamp(0, _servers.length - 1);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vpn.shutdown();
    _linkCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.detached) _vpn.shutdown();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) _linkCtrl.text = d!.text!.trim();
    setState(() {});
  }

  Future<void> _loadSubscription() async {
    final url = _linkCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _message = 'Вставьте ссылку подписки');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final list = await fetchSubscription(url);
      final p = await SharedPreferences.getInstance();
      await p.setString('sub_url', url);
      await p.setString(
          'servers', jsonEncode(list.map((e) => e.toJson()).toList()));
      await p.setInt('selected', 0);
      setState(() {
        _servers = list;
        _selected = 0;
        _message = 'Загружено серверов: ${list.length}';
      });
    } catch (e) {
      setState(() => _message = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    if (_vpn.state == VpnState.connected ||
        _vpn.state == VpnState.connecting) {
      await _vpn.disconnect();
      return;
    }
    if (_servers.isEmpty) {
      setState(() => _message = 'Сначала добавьте подписку');
      return;
    }
    setState(() => _message = null);
    await _vpn.connect(_servers[_selected]);
  }

  String get _statusText {
    switch (_vpn.state) {
      case VpnState.connected:
        return 'Подключено';
      case VpnState.connecting:
        return 'Подключение…';
      case VpnState.error:
        return 'Ошибка';
      case VpnState.disconnected:
        return 'Отключено';
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _vpn.state == VpnState.connected;
    final connecting = _vpn.state == VpnState.connecting;
    final color = connected
        ? const Color(0xFF2ECC71)
        : (connecting ? Colors.amber : _accent);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 8),
                const Text(
                  'SHTORM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: _accent,
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: GestureDetector(
                    onTap: _toggle,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withOpacity(0.12),
                        border: Border.all(color: color, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(connected ? 0.45 : 0.15),
                            blurRadius: 32,
                          ),
                        ],
                      ),
                      child: connecting
                          ? Padding(
                              padding: const EdgeInsets.all(54),
                              child: CircularProgressIndicator(
                                  color: color, strokeWidth: 3),
                            )
                          : Icon(Icons.power_settings_new,
                              size: 72, color: color),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600, color: color),
                ),
                if (_vpn.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _vpn.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                if (Platform.isWindows && connected)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Работает через системный прокси Windows',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 28),
                if (_servers.isNotEmpty) ...[
                  const Text('Сервер',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    value: _selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder()),
                    items: [
                      for (var i = 0; i < _servers.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(_servers[i].name,
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (_vpn.state == VpnState.connected ||
                            connecting)
                        ? null
                        : (v) async {
                            setState(() => _selected = v ?? 0);
                            final p = await SharedPreferences.getInstance();
                            await p.setInt('selected', _selected);
                          },
                  ),
                  const SizedBox(height: 24),
                ],
                const Text('Ссылка подписки',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                TextField(
                  controller: _linkCtrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'https://...',
                    suffixIcon: IconButton(
                      tooltip: 'Вставить',
                      icon: const Icon(Icons.content_paste),
                      onPressed: _paste,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _loadSubscription,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_download),
                  label: Text(_servers.isEmpty
                      ? 'Добавить подписку'
                      : 'Обновить подписку'),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
