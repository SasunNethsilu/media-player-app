import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/models/song.dart';
import 'package:media_player/providers/app_settings.dart';
import 'package:media_player/providers/library_collections.dart';
import 'package:media_player/providers/player_state.dart';
import 'package:media_player/screens/settings_screen.dart';
import 'package:provider/provider.dart';

import 'playback_controls_test.dart' show LibraryTestPlayer;
import 'support/fake_audio_player.dart';
import 'support/memory_preferences.dart';

class ScanPlayer extends LibraryTestPlayer {
  bool scanning = false;
  String? error;
  Completer<void>? pending;

  ScanPlayer({required super.collections, required super.library})
    : super(audioPlayer: FakeAudioPlayer());

  @override
  bool get isLoadingLibrary => scanning;

  @override
  String? get libraryError => error;

  @override
  Future<void> loadLibrary() async {
    scanning = true;
    notifyListeners();
    pending = Completer<void>();
    await pending!.future;
    scanning = false;
    notifyListeners();
  }
}

void main() {
  testWidgets('rescan shows progress, failure, then success', (tester) async {
    final collections = LibraryCollections(preferences: MemoryPreferences());
    final settings = AppSettings(preferences: MemoryPreferences());
    final player = ScanPlayer(
      collections: collections,
      library: [
        Song(
          id: 1,
          title: 'Track',
          artist: 'Artist',
          album: 'Album',
          path: '/music/1.mp3',
          durationMs: 180000,
        ),
      ],
    );
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    addTearDown(collections.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryCollections>.value(value: collections),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
          ChangeNotifierProvider<PlayerState>.value(value: player),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    await tester.tap(find.text('Rescan local library'));
    await tester.pump();
    expect(find.text('Scanning audio on this device…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    player.error = 'Audio access is needed.';
    player.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Audio access is needed.'), findsOneWidget);

    player.error = null;
    await tester.tap(find.text('Rescan local library'));
    await tester.pump();
    player.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Scan complete · 1 song found'), findsOneWidget);
  });
}
