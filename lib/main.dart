import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/game_theme.dart';
import 'core/services/rewarded_ad_service.dart';
import 'features/home/ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Draw behind the status and navigation bars on every Android version.
  // Android 15+ enforces this anyway; opting in explicitly makes older
  // versions match instead of letting the OS decide.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Only icon brightness here — the bar *color* setters (statusBarColor,
  // systemNavigationBarColor) are deprecated no-ops from API 35 and setting
  // them trips Play Console's deprecated-edge-to-edge-API warning.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Global error handler — prevents crashes from killing the app
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exception}');
  };

  await RewardedAdService.instance.initialize();

  runApp(const QuirkadeApp());
}

class QuirkadeApp extends StatelessWidget {
  const QuirkadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quirkade',
      debugShowCheckedModeBanner: false,
      theme: GameTheme.darkTheme,
      home: const HomeScreen(),
      // Error widget — shows friendly message instead of red screen
      builder: (context, child) {
        ErrorWidget.builder = (details) {
          return Scaffold(
            backgroundColor: const Color(0xFF0A0E14),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_rounded,
                    color: Color(0xFFFFB800),
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Something went wrong',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please go back and try again',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB800),
                    ),
                    child: const Text(
                      'Go Home',
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          );
        };
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
