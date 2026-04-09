import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/game_theme.dart';
import 'features/home/ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const GameBoxApp());
}

class GameBoxApp extends StatelessWidget {
  const GameBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GameBox',
      debugShowCheckedModeBanner: false,
      theme: GameTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
