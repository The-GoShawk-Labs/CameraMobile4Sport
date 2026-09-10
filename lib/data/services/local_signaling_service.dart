import 'dart:async';
import 'dart:io';
import 'package:volleylive/data/models/p2p_message.dart';

abstract class ISignalingService {
  Stream<P2PMessage> get incomingMessages;
  Stream<bool> get isConnectedStream;
  bool get isConnected;

  Future<void> startLocalServer({int port = 8080});
  Future<void> stopServer();

  Future<void> connect(String uriOrIp, {int port = 8080});
  Future<void> disconnect();

  void sendMessage(P2PMessage message);
}

/// Serwis sygnalizacji lokalnej (WebSocket Host w LAN/Hotspot oraz Klient P2P)
class LocalSignalingService implements ISignalingService {
  HttpServer? _server;
  final List<WebSocket> _serverClients = [];
  WebSocket? _clientSocket;

  final _messageController = StreamController<P2PMessage>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  bool _isConnected = false;
  String? _currentHostAddress;

  @override
  Stream<P2PMessage> get incomingMessages => _messageController.stream;

  @override
  Stream<bool> get isConnectedStream => _connectionStateController.stream;

  @override
  bool get isConnected => _isConnected;

  String? get currentHostAddress => _currentHostAddress;

  /// Uruchomienie lokalnego serwera WebSocket (np. na telefonie kontrolującym Phone B)
  @override
  Future<void> startLocalServer({int port = 8080}) async {
    await stopServer();

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _currentHostAddress = _server?.address.address;

      _server?.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _serverClients.add(socket);
          _setConnected(true);

          socket.listen(
            (data) {
              _handleRawMessage(data, fromSocket: socket);
              // Rozgłoś do pozostałych klientów w trybie hub
              _broadcastToOtherClients(data, socket);
            },
            onDone: () {
              _serverClients.remove(socket);
              if (_serverClients.isEmpty && _clientSocket == null) {
                _setConnected(false);
              }
            },
            onError: (err) {
              _serverClients.remove(socket);
            },
            cancelOnError: true,
          );
        } else {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..close();
        }
      });
    } catch (e) {
      _setConnected(false);
      rethrow;
    }
  }

  /// Połączenie jako klient (np. z Phone A do Phone B lub do chmury WSS)
  @override
  Future<void> connect(String uriOrIp, {int port = 8080}) async {
    await disconnect();

    final String wsUrl;
    if (uriOrIp.startsWith('ws://') || uriOrIp.startsWith('wss://')) {
      wsUrl = uriOrIp;
    } else {
      wsUrl = 'ws://$uriOrIp:$port';
    }

    try {
      _clientSocket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 5));
      _setConnected(true);

      _clientSocket?.listen(
        (data) {
          _handleRawMessage(data);
        },
        onDone: () {
          _setConnected(false);
        },
        onError: (err) {
          _setConnected(false);
        },
        cancelOnError: true,
      );
    } catch (e) {
      _setConnected(false);
      rethrow;
    }
  }

  @override
  void sendMessage(P2PMessage message) {
    final raw = message.toJson();

    // Wyślij przez klienta, jeśli jesteśmy podłączeni jako klient
    if (_clientSocket != null && _clientSocket?.readyState == WebSocket.open) {
      _clientSocket?.add(raw);
    }

    // Lub wyślij do wszystkich połączonych klientów, jeśli jesteśmy serwerem
    for (final client in _serverClients) {
      if (client.readyState == WebSocket.open) {
        client.add(raw);
      }
    }
  }

  @override
  Future<void> disconnect() async {
    if (_clientSocket != null) {
      await _clientSocket?.close();
      _clientSocket = null;
    }
    _setConnected(false);
  }

  @override
  Future<void> stopServer() async {
    for (final client in List.of(_serverClients)) {
      await client.close();
    }
    _serverClients.clear();
    await _server?.close(force: true);
    _server = null;
    _currentHostAddress = null;
    _setConnected(false);
  }

  void _handleRawMessage(dynamic data, {WebSocket? fromSocket}) {
    try {
      if (data is String) {
        final msg = P2PMessage.fromJson(data);
        _messageController.add(msg);
      }
    } catch (_) {
      // Ignoruj uszkodzone pakiety
    }
  }

  void _broadcastToOtherClients(dynamic data, WebSocket sender) {
    for (final client in _serverClients) {
      if (client != sender && client.readyState == WebSocket.open) {
        client.add(data);
      }
    }
  }

  void _setConnected(bool connected) {
    _isConnected = connected;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(connected);
    }
  }

  void dispose() {
    disconnect();
    stopServer();
    _messageController.close();
    _connectionStateController.close();
  }
}
