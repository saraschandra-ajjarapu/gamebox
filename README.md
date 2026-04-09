# GameBox - Fun Games

A collection of 13 classic games built with Flutter. Available on iOS and Android.

## Screenshots

<p align="center">
  <img src="screenshots/home_top.png" width="250" />
  <img src="screenshots/home_screen.png" width="250" />
</p>

## Games

| Game | Players | Features |
|------|---------|----------|
| 2048 | 1 | 6 visual themes, persistent high score |
| Snake | 1 | Special foods (fake, rock/real, timed), D-pad controls, gradual speed |
| Chess | 1-2 | 3 AI levels (Easy/Medium/Hard), 3 piece styles, 5 board themes, WiFi multiplayer |
| Ludo | 2-4 | Color picker, capture bonus turns, stacked piece indicators |
| Tic Tac Toe | 1-2 | AI opponent, WiFi multiplayer |
| Memory Match | 1 | Card flip animations |
| Connect 4 | 1-2 | Smart AI (minimax depth 5), WiFi multiplayer |
| Sudoku | 1 | Multiple difficulty levels |
| Simon Says | 1 | Persistent best score |
| Dots & Boxes | 1-2 | 7x7 grid, AI opponent, WiFi multiplayer |
| Quiz | 1-4 | 9 categories, 400+ questions, pass-and-play multiplayer |
| Wordle | 1 | 750+ words, stats tracking, win streaks |

## WiFi Multiplayer

Chess, Tic Tac Toe, Connect 4, and Dots & Boxes support WiFi multiplayer — play against friends on the same network with zero cloud cost. One player hosts, others join with a room code.

## Tech Stack

- **Framework:** Flutter (Dart)
- **State:** StatefulWidget + shared_preferences for persistence
- **Networking:** TCP sockets for WiFi multiplayer (no server needed)
- **Platforms:** iOS 13+, Android 5.0+

## Project Structure

```
lib/
├── main.dart                          # App entry point
├── firebase_options.dart              # (unused, can remove)
│
├── core/
│   ├── theme/
│   │   └── game_theme.dart            # Shared dark theme colors & styles
│   ├── utils/
│   │   └── game_help.dart             # How to Play instructions for all games
│   ├── services/
│   │   └── wifi_game_service.dart     # TCP socket service for WiFi multiplayer
│   └── widgets/
│       └── wifi_lobby.dart            # Reusable host/join lobby widget
│
├── features/
│   ├── home/ui/home_screen.dart       # Game grid with cards
│   ├── game_2048/ui/                  # 2048 with themes
│   ├── snake/ui/                      # Snake with special foods
│   ├── chess/ui/                      # Chess with AI levels
│   ├── ludo/ui/                       # Ludo with color picker
│   ├── tictactoe/ui/                  # Tic Tac Toe
│   ├── memory/ui/                     # Memory Match
│   ├── connect4/ui/                   # Connect 4 with minimax AI
│   ├── sudoku/ui/                     # Sudoku
│   ├── simon/ui/                      # Simon Says
│   ├── dots_boxes/ui/                 # Dots & Boxes
│   ├── quiz/
│   │   ├── data/quiz_questions.dart   # 400+ questions across 9 categories
│   │   └── ui/quiz_screen.dart        # Quiz game UI
│   └── wordle/
│       ├── data/word_list.dart        # 750+ five-letter words
│       └── ui/wordle_screen.dart      # Wordle game UI
│
assets/
├── app_icon.png                       # App icon source
├── play_store_icon_512.png            # Google Play icon
├── play_store_feature_graphic.png     # Google Play feature graphic
└── screenshot_*.png                   # Store screenshots
```

## Building

### Prerequisites
- Flutter SDK (3.9+)
- Xcode (for iOS)
- Android Studio (for Android)

### Run locally
```bash
flutter pub get
flutter run
```

### Build for release

**iOS (App Store):**
```bash
flutter build ipa --release
# Upload via Xcode Organizer: open build/ios/archive/Runner.xcarchive
```

**Android (Google Play):**
```bash
flutter build appbundle --release
# AAB at: build/app/outputs/bundle/release/app-release.aab
```

## Distribution

- **iOS:** App Store — "GameBox - Fun Games" by SARASCHANDRA
- **Android:** Google Play — in internal testing (production pending 14-day closed test)
- **Bundle ID:** com.saraschandra.gamebox

## Privacy Policy

https://saraschandra-ajjarapu.github.io/gamebox/privacy-policy.html
