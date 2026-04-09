import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/game_theme.dart';
import '../services/wifi_game_service.dart';

/// Reusable WiFi lobby widget for any game.
/// Shows host/join options, waiting room with player list, and start button.
class WifiLobby extends StatefulWidget {
  final String gameName;
  final int maxPlayers;
  final void Function(WifiGameService service) onGameStart;
  final VoidCallback onBack;

  const WifiLobby({
    super.key,
    required this.gameName,
    this.maxPlayers = 2,
    required this.onGameStart,
    required this.onBack,
  });

  @override
  State<WifiLobby> createState() => _WifiLobbyState();
}

class _WifiLobbyState extends State<WifiLobby> {
  final _service = WifiGameService();
  bool _inLobby = false;
  bool _connecting = false;
  String _joinCode = '';

  @override
  void initState() {
    super.initState();
    _service.onPlayerJoined = (count) {
      if (mounted) setState(() {});
    };
    _service.onDisconnected = () {
      if (mounted) {
        setState(() => _inLobby = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disconnected'), backgroundColor: GameTheme.accentAlt));
      }
    };
    _service.onError = (msg) {
      if (mounted) {
        setState(() => _connecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: GameTheme.accentAlt));
      }
    };
    _service.onGameStarted = () {
      widget.onGameStart(_service);
    };
  }

  @override
  void dispose() {
    if (!_service.connected) _service.dispose();
    super.dispose();
  }

  Future<void> _host() async {
    _connecting = true;
    setState(() {});
    final ok = await _service.host('Player 1');
    _connecting = false;
    if (ok) _inLobby = true;
    if (mounted) setState(() {});
  }

  Future<void> _join() async {
    if (_joinCode.isEmpty) return;
    _connecting = true;
    setState(() {});
    final ok = await _service.join(_joinCode, 'Player');
    _connecting = false;
    if (ok) _inLobby = true;
    if (mounted) setState(() {});
  }

  void _start() {
    _service.startGame();
    widget.onGameStart(_service);
  }

  @override
  Widget build(BuildContext context) {
    if (_connecting) {
      return Scaffold(
        backgroundColor: GameTheme.background,
        body: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: GameTheme.accent),
          SizedBox(height: 16),
          Text('Connecting...', style: TextStyle(color: GameTheme.textSecondary)),
        ])),
      );
    }

    if (_inLobby) return _buildWaiting();
    return _buildOptions();
  }

  Widget _buildOptions() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: Text('${widget.gameName} — WiFi'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: widget.onBack),
      ),
      body: Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_rounded, size: 56, color: GameTheme.accent),
          const SizedBox(height: 8),
          const Text('WiFi Multiplayer', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: GameTheme.textPrimary)),
          const SizedBox(height: 8),
          const Text('Both players must be on the same WiFi', style: TextStyle(fontSize: 13, color: GameTheme.textSecondary)),
          const SizedBox(height: 32),

          _btn(Icons.router_rounded, 'Host Game', 'Create a room', _host),
          const SizedBox(height: 12),
          _btn(Icons.login_rounded, 'Join Game', 'Enter room code', () => _showJoinDialog()),
        ]))),
    );
  }

  Widget _buildWaiting() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Waiting Room'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () {
            _service.dispose();
            setState(() => _inLobby = false);
          }),
      ),
      body: Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_service.isHost) ...[
            const Text('Room Code', style: TextStyle(fontSize: 14, color: GameTheme.textSecondary)),
            const SizedBox(height: 8),
            Text(_service.roomCode,
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900,
                color: GameTheme.accent, letterSpacing: 8)),
            const SizedBox(height: 8),
            const Text('Share this code with other players',
              style: TextStyle(fontSize: 13, color: GameTheme.textSecondary)),
            const SizedBox(height: 32),
            Text('${_service.playerCount} player(s)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: GameTheme.textPrimary)),
            const SizedBox(height: 12),
            for (final name in _service.playerNames)
              Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.person_rounded, color: GameTheme.accent, size: 18),
                  const SizedBox(width: 8),
                  Text(name, style: const TextStyle(color: GameTheme.textPrimary)),
                ])),
            const SizedBox(height: 32),
            if (_service.playerCount >= 2)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: GameTheme.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _start,
                child: const Text('Start Game',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
          ] else ...[
            const CircularProgressIndicator(color: GameTheme.accent),
            const SizedBox(height: 16),
            const Text('Connected! Waiting for host to start...',
              style: TextStyle(color: GameTheme.textSecondary)),
          ],
        ]))),
    );
  }

  void _showJoinDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GameTheme.surface,
        title: const Text('Enter Room Code', style: TextStyle(color: GameTheme.textPrimary)),
        content: TextField(
          keyboardType: TextInputType.number,
          style: const TextStyle(color: GameTheme.textPrimary, fontSize: 24, letterSpacing: 4),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: 'Code',
            filled: true,
            fillColor: GameTheme.surfaceLight,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onChanged: (v) => _joinCode = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: GameTheme.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GameTheme.accent),
            onPressed: () { Navigator.pop(ctx); _join(); },
            child: const Text('Join', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, String label, String sub, VoidCallback onTap) {
    return GestureDetector(onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(color: GameTheme.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GameTheme.border)),
        child: Row(children: [Icon(icon, color: GameTheme.accent, size: 26), const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GameTheme.textPrimary)),
            Text(sub, style: const TextStyle(fontSize: 12, color: GameTheme.textSecondary))])),
          const Icon(Icons.arrow_forward_ios_rounded, color: GameTheme.textSecondary, size: 16)])));
  }
}
