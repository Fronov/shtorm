/// Собирает конфиг Xray из ссылки vless:// (нужно для Windows).
Map<String, dynamic> buildXrayConfig(
  String link, {
  int socksPort = 10808,
  int httpPort = 10809,
}) {
  final u = Uri.parse(link);
  if (u.scheme != 'vless') {
    throw Exception('На Windows пока поддерживается только VLESS');
  }
  final q = u.queryParameters;
  final net = q['type'] ?? 'tcp';
  final sec = q['security'] ?? 'none';

  final stream = <String, dynamic>{'network': net, 'security': sec};

  if (sec == 'reality') {
    stream['realitySettings'] = {
      'serverName': q['sni'] ?? '',
      'fingerprint': q['fp'] ?? 'chrome',
      'publicKey': q['pbk'] ?? '',
      'shortId': q['sid'] ?? '',
      'spiderX': q['spx'] ?? '',
    };
  } else if (sec == 'tls') {
    stream['tlsSettings'] = {
      'serverName': q['sni'] ?? u.host,
      'fingerprint': q['fp'] ?? 'chrome',
      if ((q['alpn'] ?? '').isNotEmpty) 'alpn': q['alpn']!.split(','),
    };
  }

  switch (net) {
    case 'ws':
      stream['wsSettings'] = {
        'path': q['path'] ?? '/',
        if ((q['host'] ?? '').isNotEmpty) 'headers': {'Host': q['host']},
      };
      break;
    case 'grpc':
      stream['grpcSettings'] = {
        'serviceName': q['serviceName'] ?? '',
        'multiMode': q['mode'] == 'multi',
      };
      break;
    case 'xhttp':
    case 'splithttp':
      stream['xhttpSettings'] = {
        'path': q['path'] ?? '/',
        if ((q['host'] ?? '').isNotEmpty) 'host': q['host'],
        if ((q['mode'] ?? '').isNotEmpty) 'mode': q['mode'],
      };
      break;
  }

  return {
    'log': {'loglevel': 'warning'},
    'inbounds': [
      {
        'tag': 'socks-in',
        'listen': '127.0.0.1',
        'port': socksPort,
        'protocol': 'socks',
        'settings': {'udp': true},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls'],
        },
      },
      {
        'tag': 'http-in',
        'listen': '127.0.0.1',
        'port': httpPort,
        'protocol': 'http',
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls'],
        },
      },
    ],
    'outbounds': [
      {
        'tag': 'proxy',
        'protocol': 'vless',
        'settings': {
          'vnext': [
            {
              'address': u.host,
              'port': u.port,
              'users': [
                {
                  'id': u.userInfo,
                  'encryption': q['encryption'] ?? 'none',
                  if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
                },
              ],
            },
          ],
        },
        'streamSettings': stream,
      },
      {'tag': 'direct', 'protocol': 'freedom'},
      {'tag': 'block', 'protocol': 'blackhole'},
    ],
    'routing': {
      'domainStrategy': 'IPIfNonMatch',
      'rules': [
        {
          'type': 'field',
          'ip': ['geoip:private'],
          'outboundTag': 'direct',
        },
      ],
    },
  };
}
