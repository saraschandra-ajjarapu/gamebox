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

  /// Usable IPv4 addresses for this device's local networks, best first.
  ///
  /// Drops loopback and 169.254.x.x link-local (a link-local address means no
  /// DHCP lease, so no peer will share that subnet), and sorts RFC1918 private
  /// ranges ahead of everything else because that is what home and office WiFi
  /// hands out. Callers must never assume NetworkInterface.list() ordering —
  /// it is arbitrary and frequently puts cellular or VPN interfaces first.
  static Future<List<InternetAddress>> _lanAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final out = <InternetAddress>[];
    for (final ni in interfaces) {
      for (final addr in ni.addresses) {
        if (addr.isLoopback) continue;
        if (addr.address.startsWith('169.254.')) continue;
        out.add(addr);
      }
    }
    out.sort((a, b) {
      final ra = _isPrivateIPv4(a.address) ? 0 : 1;
      final rb = _isPrivateIPv4(b.address) ? 0 : 1;
      return ra.compareTo(rb);
    });
    return out;
  }

  static bool _isPrivateIPv4(String address) {
    if (address.startsWith('192.168.') || address.startsWith('10.')) {
      return true;
    }
    final match = RegExp(r'^172\.(\d{1,3})\.').firstMatch(address);
    if (match == null) return false;
    final second = int.parse(match.group(1)!);
    return second >= 16 && second <= 31;
  }

  /// Host a game — creates a TCP server on a random port
  Future<bool> host(String playerName) async {
    try {
      if ((await _lanAddresses()).isEmpty) {
        onError?.call('No WiFi connection found');
        return false;
      }

      // Bind every interface, not one picked by list order. NetworkInterface
      // .list() is unordered, so `.first` is regularly cellular (pdp_ip0 /
      // rmnet_data) or a VPN (utun) rather than WiFi — binding there leaves
      // the server unreachable from the LAN even though hosting "succeeded".
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
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
      final localAddresses = await _lanAddresses();
      if (localAddresses.isEmpty) {
        onError?.call('No WiFi connection found');
        return false;
      }

      final port = int.tryParse(code);
      if (port == null) {
        onError?.call('Invalid room code');
        return false;
      }

      // Scan every LAN subnet this device is on, not just the one belonging to
      // whichever interface happened to sort first. A phone routinely has WiFi
      // plus cellular (and sometimes a VPN); scanning the wrong /24 finds
      // nothing and looks exactly like "the host isn't running".
      Socket? socket;
      final scanned = <String>{};
      for (final address in localAddresses) {
        final subnet = address.address.substring(
          0,
          address.address.lastIndexOf('.'),
        );
        if (!scanned.add(subnet)) continue;

        // Chunked so we never hold 255 pending sockets at once — that trips
        // per-process file-descriptor limits, and a refused connect there
        // surfaces as a false "host not found".
        for (var start = 1; start <= 255 && socket == null; start += 32) {
          final end = (start + 31).clamp(1, 255);
          final batch = <Future<void>>[];
          for (var i = start; i <= end; i++) {
            batch.add(
              Socket.connect(
                    '$subnet.$i',
                    port,
                    timeout: const Duration(milliseconds: 600),
                  )
                  .then((s) {
                    if (socket == null) {
                      socket = s;
                    } else {
                      s.destroy();
                    }
                  })
                  .catchError((_) {}),
            );
          }
          await Future.wait(batch);
        }
        if (socket != null) break;
      }

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
