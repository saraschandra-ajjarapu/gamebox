import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Shared WiFi multiplayer service for all games.
/// Host creates a TCP server, clients connect via room code (port number).
/// Messages are JSON objects with a 'type' field.
class WifiGameService {
  ServerSocket? _server;
  Socket? _clientSocket;
  final List<Socket> _clients = [];
  bool _isHost = false;
  String _roomCode = '';
  int _playerIndex = 0; // 0 = host, 1+ = clients in join order
  final List<String> _playerNames = [];
  bool _connected = false;

  // Callbacks
  void Function(Map<String, dynamic> message)? onMessage;
  void Function(int playerCount)? onPlayerJoined;
  void Function()? onDisconnected;
  void Function(String error)? onError;
  void Function()? onGameStarted;

  bool get isHost => _isHost;
  String get roomCode => _roomCode;
  int get playerIndex => _playerIndex;
  int get playerCount => _playerNames.length;
  List<String> get playerNames => List.unmodifiable(_playerNames);
  bool get connected => _connected;

  /// Host a game — creates a TCP server on a random port
  Future<bool> host(String playerName) async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      if (interfaces.isEmpty) {
        onError?.call('No WiFi connection found');
        return false;
      }

      final ip = interfaces.first.addresses.first;
      _server = await ServerSocket.bind(ip, 0);
      _roomCode = '${_server!.port}';
      _isHost = true;
      _playerIndex = 0;
      _playerNames.clear();
      _playerNames.add(playerName);
      _connected = true;

      _server!.listen((client) {
        final idx = _clients.length + 1;
        _clients.add(client);
        final name = 'Player ${idx + 1}';
        _playerNames.add(name);

        // Send welcome with player index
        _sendTo(client, {
          'type': '_welcome',
          'playerIndex': idx,
          'playerName': name,
        });

        // Notify host
        onPlayerJoined?.call(_playerNames.length);

        // Listen for messages from this client
        _listenToSocket(client, idx);
      });

      return true;
    } catch (e) {
      onError?.call('Could not start host: $e');
      return false;
    }
  }

  /// Join a game — connects to host via room code (port)
  Future<bool> join(String code, String playerName) async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      if (interfaces.isEmpty) {
        onError?.call('No WiFi connection found');
        return false;
      }

      final myIp = interfaces.first.addresses.first;
      final subnet = myIp.address.substring(0, myIp.address.lastIndexOf('.'));
      final port = int.tryParse(code);
      if (port == null) {
        onError?.call('Invalid room code');
        return false;
      }

      // Scan subnet for the host
      Socket? socket;
      final futures = <Future>[];
      for (int i = 1; i <= 255; i++) {
        futures.add(
          Socket.connect('$subnet.$i', port, timeout: const Duration(milliseconds: 150))
              .then((s) { socket ??= s; })
              .catchError((_) {}),
        );
      }
      await Future.wait(futures);

      if (socket == null) {
        onError?.call('Could not find host. Same WiFi?');
        return false;
      }

      _clientSocket = socket;
      _isHost = false;
      _roomCode = code;
      _connected = true;

      _listenToSocket(socket!, -1);
      return true;
    } catch (e) {
      onError?.call('Connection failed: $e');
      return false;
    }
  }

  void _listenToSocket(Socket socket, int fromPlayerIndex) {
    String buffer = '';
    socket.listen(
      (data) {
        buffer += utf8.decode(data);
        // Handle multiple JSON messages in one packet
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 1);
          if (line.isNotEmpty) {
            try {
              final msg = jsonDecode(line) as Map<String, dynamic>;
              _handleMessage(msg, fromPlayerIndex, socket);
            } catch (_) {}
          }
        }
      },
      onDone: () {
        _connected = false;
        onDisconnected?.call();
      },
      onError: (_) {
        _connected = false;
        onDisconnected?.call();
      },
    );
  }

  void _handleMessage(Map<String, dynamic> msg, int fromPlayer, Socket socket) {
    final type = msg['type'] as String? ?? '';

    if (type == '_welcome') {
      // Client received welcome from host
      _playerIndex = msg['playerIndex'] as int;
      return;
    }

    if (type == '_start') {
      onGameStarted?.call();
      return;
    }

    // If host, relay message to all other clients
    if (_isHost && fromPlayer >= 0) {
      msg['from'] = fromPlayer;
      for (int i = 0; i < _clients.length; i++) {
        if (_clients[i] != socket) {
          _sendTo(_clients[i], msg);
        }
      }
    }

    // Deliver to game
    msg['from'] = fromPlayer >= 0 ? fromPlayer : 0; // 0 = host
    onMessage?.call(msg);
  }

  /// Send a game message to all peers
  void send(Map<String, dynamic> message) {
    message['from'] = _playerIndex;
    if (_isHost) {
      // Host sends to all clients
      for (final client in _clients) {
        _sendTo(client, message);
      }
    } else {
      // Client sends to host (host relays)
      if (_clientSocket != null) {
        _sendTo(_clientSocket!, message);
      }
    }
  }

  /// Host starts the game — notifies all clients
  void startGame() {
    if (!_isHost) return;
    for (final client in _clients) {
      _sendTo(client, {'type': '_start'});
    }
    onGameStarted?.call();
  }

  void _sendTo(Socket socket, Map<String, dynamic> msg) {
    try {
      socket.write('${jsonEncode(msg)}\n');
    } catch (_) {}
  }

  /// Clean up
  void dispose() {
    _server?.close();
    _clientSocket?.close();
    for (final c in _clients) {
      c.close();
    }
    _clients.clear();
    _playerNames.clear();
    _connected = false;
  }
}
