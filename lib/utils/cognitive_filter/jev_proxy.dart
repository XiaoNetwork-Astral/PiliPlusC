import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/io.dart';

/// AI 接口使用的代理类型
enum JevProxyType {
  /// 不使用代理
  none,

  /// HTTP 代理，HTTPS 目标由 dart:io 自动走 CONNECT
  http,

  /// SOCKS5 代理，无认证
  socks5,
}

/// 一个解析好的代理地址
class JevProxy {
  const JevProxy({required this.type, required this.host, required this.port});

  final JevProxyType type;
  final String host;
  final int port;

  /// 解析 `host:port`；容忍首尾空白与 `http://` / `socks5://` 前缀，
  /// IPv6 支持 `[::1]:7890` 写法，非法时返回 null
  static JevProxy? parse(JevProxyType type, String address) {
    if (type == JevProxyType.none) {
      return null;
    }
    var text = address.trim();
    if (text.isEmpty) {
      return null;
    }
    final lower = text.toLowerCase();
    for (final prefix in const <String>[
      'socks5h://',
      'socks5://',
      'https://',
      'http://',
    ]) {
      if (lower.startsWith(prefix)) {
        text = text.substring(prefix.length).trim();
        break;
      }
    }
    if (text.isEmpty) {
      return null;
    }

    final String host;
    final String portText;
    final bool bracketed;
    if (text.startsWith('[')) {
      final end = text.indexOf(']');
      if (end < 0) {
        return null;
      }
      host = text.substring(1, end).trim();
      final rest = text.substring(end + 1).trim();
      if (!rest.startsWith(':')) {
        return null;
      }
      portText = rest.substring(1).trim();
      bracketed = true;
    } else {
      final colon = text.lastIndexOf(':');
      if (colon < 0) {
        return null;
      }
      host = text.substring(0, colon).trim();
      portText = text.substring(colon + 1).trim();
      bracketed = false;
    }

    if (host.isEmpty ||
        host.contains(RegExp(r'\s')) ||
        (!bracketed && host.contains(':'))) {
      return null;
    }
    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) {
      return null;
    }
    return JevProxy(type: type, host: host, port: port);
  }

  /// `host:port`，IPv6 自动补方括号，供 `findProxy` 使用
  String get authority => host.contains(':') ? '[$host]:$port' : '$host:$port';

  @override
  String toString() => 'JevProxy(${type.name}, $authority)';
}

/// SOCKS5 客户端问候：VER=5, NMETHODS=1, METHOD=0x00（无认证）
List<int> buildSocks5Greeting() => const <int>[0x05, 0x01, 0x00];

/// 解析问候应答，成功返回 null，失败返回中文说明
String? parseSocks5GreetingReply(List<int> reply) {
  if (reply.length < 2) {
    return 'SOCKS5 代理应答不完整';
  }
  if (reply[0] != 0x05) {
    return 'SOCKS5 代理版本不正确';
  }
  if (reply[1] != 0x00) {
    return 'SOCKS5 代理要求认证，暂不支持';
  }
  return null;
}

/// 构造 SOCKS5 CONNECT 请求，目标地址用域名类型（ATYP=0x03）交给代理解析
List<int> buildSocks5ConnectRequest(String host, int port) {
  final hostBytes = utf8.encode(host);
  if (hostBytes.isEmpty || hostBytes.length > 255) {
    throw ArgumentError.value(host, 'host', '域名长度不合法');
  }
  if (port < 1 || port > 65535) {
    throw ArgumentError.value(port, 'port', '端口超出范围');
  }
  return <int>[
    0x05,
    0x01,
    0x00,
    0x03,
    hostBytes.length,
    ...hostBytes,
    (port >> 8) & 0xff,
    port & 0xff,
  ];
}

/// 解析 CONNECT 应答，成功返回 null，失败返回中文说明
String? parseSocks5ConnectReply(List<int> reply) {
  if (reply.length < 4) {
    return 'SOCKS5 代理应答不完整';
  }
  if (reply[0] != 0x05) {
    return 'SOCKS5 代理版本不正确';
  }
  if (reply[1] != 0x00) {
    return 'SOCKS5 代理拒绝连接（错误码 ${reply[1]}）';
  }
  final addressType = reply[3];
  final tail = switch (addressType) {
    0x01 => 6,
    0x03 => (reply.length > 4 ? reply[4] : 0) + 3,
    0x04 => 18,
    _ => -1,
  };
  if (tail < 0) {
    return 'SOCKS5 代理返回了不支持的地址类型';
  }
  if (reply.length < 4 + tail) {
    return 'SOCKS5 代理应答不完整';
  }
  return null;
}

/// 给 dio 用的适配器工厂：有代理时返回带代理配置的 HttpClient
///
/// HTTP 代理直接交给 `findProxy`，HTTPS 目标由 dart:io 自动走 CONNECT；
/// SOCKS5 自己实现握手。注意 [HttpClient.connectionFactory] 在直连时**不会**
/// 对 https 目标自动升级 TLS（返回的 socket 会被直接使用），所以这里在
/// 握手成功后自己调用 `SecureSocket.secure`。
IOHttpClientAdapter createJevAdapter(
  JevProxy? proxy, {
  Duration timeout = const Duration(seconds: 6),
}) {
  if (proxy == null || proxy.type == JevProxyType.none) {
    return IOHttpClientAdapter();
  }
  return IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      if (proxy.type == JevProxyType.http) {
        client.findProxy = (_) => 'PROXY ${proxy.authority}';
      } else {
        // 让 dart:io 走直连，真正由 connectionFactory 建连
        client.findProxy = (_) => 'DIRECT';
        client.connectionFactory = (uri, proxyHost, proxyPort) =>
            _connectSocks5(proxy, uri, timeout);
      }
      return client;
    },
  );
}

/// 连接 SOCKS5 代理并完成握手，返回可交给 HttpClient 的连接任务
Future<ConnectionTask<Socket>> _connectSocks5(
  JevProxy proxy,
  Uri uri,
  Duration timeout,
) async {
  final Socket socket;
  try {
    socket = await Socket.connect(proxy.host, proxy.port, timeout: timeout);
  } catch (error) {
    if (error is SocketException) {
      rethrow;
    }
    if (error is TimeoutException) {
      throw const SocketException('连接 SOCKS5 代理超时');
    }
    throw SocketException('无法连接 SOCKS5 代理：$error');
  }

  final reader = _SocketReader(socket);
  try {
    await _handshake(socket, reader, uri, timeout);
  } catch (error) {
    socket.destroy();
    if (error is SocketException) {
      rethrow;
    }
    throw SocketException('SOCKS5 代理握手失败：$error');
  }

  if (uri.scheme == 'https') {
    try {
      // 握手成功后自己升级 TLS；旧订阅会被 SecureSocket 接管
      final secure = await SecureSocket.secure(
        socket,
        host: uri.host,
      ).timeout(timeout);
      return ConnectionTask.fromSocket<Socket>(
        Future<Socket>.value(secure),
        secure.destroy,
      );
    } catch (error) {
      socket.destroy();
      if (error is TimeoutException) {
        throw const SocketException('通过 SOCKS5 代理建立 HTTPS 超时');
      }
      rethrow;
    }
  }

  final relayed = _BufferedSocket(reader);
  return ConnectionTask.fromSocket<Socket>(
    Future<Socket>.value(relayed),
    relayed.destroy,
  );
}

/// 执行 SOCKS5 无认证握手
Future<void> _handshake(
  Socket socket,
  _SocketReader reader,
  Uri uri,
  Duration timeout,
) async {
  socket.add(buildSocks5Greeting());
  await socket.flush();
  final greeting = await reader.readExact(2, timeout);
  final greetingError = parseSocks5GreetingReply(greeting);
  if (greetingError != null) {
    throw SocketException(greetingError);
  }

  final port = uri.hasPort
      ? uri.port
      : (uri.scheme == 'https' ? 443 : 80);
  socket.add(buildSocks5ConnectRequest(uri.host, port));
  await socket.flush();

  final head = await reader.readExact(4, timeout);
  final addressType = head[3];
  final List<int> reply;
  if (addressType == 0x01) {
    reply = <int>[...head, ...await reader.readExact(6, timeout)];
  } else if (addressType == 0x03) {
    final length = await reader.readExact(1, timeout);
    final rest = await reader.readExact(length[0] + 2, timeout);
    reply = <int>[...head, ...length, ...rest];
  } else if (addressType == 0x04) {
    reply = <int>[...head, ...await reader.readExact(18, timeout)];
  } else {
    throw const SocketException('SOCKS5 代理返回了不支持的地址类型');
  }
  final replyError = parseSocks5ConnectReply(reply);
  if (replyError != null) {
    throw SocketException(replyError);
  }
}

/// 在握手期间缓冲字节，之后可选择把读取权交给 HttpClient
class _SocketReader {
  _SocketReader(this.socket) {
    socket.listen(_onData, onError: _onError, onDone: _onDone);
  }

  final Socket socket;
  final List<int> _buffer = <int>[];

  // 实际的下游由 [handOver] 创建
  StreamController<Uint8List>? _out;
  Completer<void>? _waiter;
  Object? _error;
  StackTrace? _stackTrace;
  bool _done = false;

  void _onData(Uint8List data) {
    final out = _out;
    if (out != null) {
      if (!out.isClosed) {
        out.add(data);
      }
    } else {
      _buffer.addAll(data);
    }
    _wake();
  }

  void _onError(Object error, StackTrace stackTrace) {
    _error = error;
    _stackTrace = stackTrace;
    final out = _out;
    if (out != null && !out.isClosed) {
      out.addError(error, stackTrace);
    }
    _wake();
  }

  void _onDone() {
    _done = true;
    final out = _out;
    if (out != null && !out.isClosed) {
      out.close();
    }
    _wake();
  }

  void _wake() {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _waiter = null;
      waiter.complete();
    }
  }

  /// 精确读取 [count] 字节，超时或连接关闭时抛 [SocketException]
  Future<List<int>> readExact(int count, Duration timeout) async {
    while (_buffer.length < count) {
      final error = _error;
      if (error != null) {
        throw error is SocketException
            ? error
            : SocketException('SOCKS5 代理连接失败：$error');
      }
      if (_done) {
        throw const SocketException('SOCKS5 代理连接已关闭');
      }
      final waiter = _waiter ??= Completer<void>();
      try {
        await waiter.future.timeout(timeout);
      } on TimeoutException {
        if (identical(_waiter, waiter)) {
          _waiter = null;
        }
        throw const SocketException('SOCKS5 代理握手超时');
      }
    }
    final result = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return result;
  }

  /// 把后续读取交给 [HttpClient]，之前缓冲的字节一并转过去
  StreamController<Uint8List> handOver() {
    final out = _out ??= StreamController<Uint8List>();
    if (_buffer.isNotEmpty) {
      out.add(Uint8List.fromList(_buffer));
      _buffer.clear();
    }
    final error = _error;
    if (error != null) {
      out.addError(error, _stackTrace);
    }
    if (_done) {
      out.close();
    }
    return out;
  }
}

/// 把已握手的 Socket 包装成可被 HttpClient 监听的 Socket
///
/// `_SocketReader` 已经占用了原始 Socket 的读取事件，这里用 StreamController
/// 转出一份单订阅流交给 HttpClient，写入仍然直接走原始 Socket。
class _BufferedSocket extends Stream<Uint8List> implements Socket {
  _BufferedSocket(this._reader) : _controller = _reader.handOver();

  final _SocketReader _reader;
  final StreamController<Uint8List> _controller;

  Socket get _socket => _reader.socket;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future addStream(Stream<List<int>> stream) => _socket.addStream(stream);

  @override
  Future close() => _socket.close();

  @override
  Future get done => _socket.done;

  @override
  Future flush() => _socket.flush();

  @override
  Encoding get encoding => _socket.encoding;

  @override
  set encoding(Encoding encoding) => _socket.encoding = encoding;

  @override
  void write(Object? object) => _socket.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _socket.writeln(object);

  @override
  void destroy() => _socket.destroy();

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);

  @override
  int get port => _socket.port;

  @override
  int get remotePort => _socket.remotePort;

  @override
  InternetAddress get address => _socket.address;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;
}
