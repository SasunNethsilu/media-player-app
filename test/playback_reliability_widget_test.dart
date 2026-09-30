import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/models/song.dart';
import 'package:media_player/providers/library_collections.dart';
import 'package:media_player/providers/player_state.dart';
import 'package:media_player/screens/now_playing_screen.dart';
import 'package:media_player/services/artwork_palette_service.dart';
import 'package:media_player/widgets/mini_player.dart';
import 'package:provider/provider.dart';

import 'support/fake_audio_player.dart';
import 'support/memory_preferences.dart';

void main() {
  final songs = [
    for (var id = 701; id <= 703; id++)
      Song(
        id: id,
        title: 'Track $id',
        artist: 'Artist $id',
        album: 'Album',
        path: '/music/$id.mp3',
        durationMs: 180000,
      ),
  ];

  Future<void> mount(
    WidgetTester tester,
    PlayerState state, {
    bool mini = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerState>.value(
        value: state,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: Scaffold(
            body: const NowPlayingScreen(),
            bottomNavigationBar: mini ? const MiniPlayer() : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('late artwork cannot appear beneath a newer track title', (
    tester,
  ) async {
    final collections = LibraryCollections(preferences: MemoryPreferences());
    final audio = FakeAudioPlayer();
    final state = PlayerState(collections: collections, audioPlayer: audio);
    addTearDown(state.dispose);
    addTearDown(collections.dispose);
    const channel = MethodChannel('com.lucasjosino.on_audio_query');
    final delayed = <int, Completer<Uint8List?>>{
      702: Completer<Uint8List?>(),
      703: Completer<Uint8List?>(),
    };
    final bytes = await tester.runAsync(() async {
      final image = await createTestImage(width: 8, height: 8, cache: false);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method != 'queryArtwork') return null;
      final id = (call.arguments as Map)['id'] as int;
      return delayed[id]?.future ?? Future.value(bytes);
    });
    addTearDown(() {
      for (final gate in delayed.values) {
        if (!gate.isCompleted) gate.complete(null);
      }
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    await tester.runAsync(() async {
      await ArtworkPaletteService.shared.load(701);
      ArtworkPaletteService.shared.preload(702);
      ArtworkPaletteService.shared.preload(703);
    });
    await state.playFromLibrary(songs.first, songs);
    await mount(tester, state);
    expect(find.byKey(const ValueKey('art-701')), findsOneWidget);
    await state.playNext();
    await tester.pumpAndSettle();
    expect(find.text('Track 702'), findsOneWidget);
    expect(find.byKey(const ValueKey('art-701')), findsNothing);
    expect(find.byKey(const ValueKey('artwork-placeholder')), findsOneWidget);
    await state.playNext();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      delayed[702]!.complete(bytes);
      await ArtworkPaletteService.shared.load(702);
    });
    await tester.pumpAndSettle();
    expect(find.text('Track 703'), findsOneWidget);
    expect(find.byKey(const ValueKey('art-702')), findsNothing);
    expect(find.byKey(const ValueKey('artwork-placeholder')), findsOneWidget);
    await tester.runAsync(() async {
      delayed[703]!.complete(bytes);
      await ArtworkPaletteService.shared.load(703);
    });
    await tester.pumpAndSettle();
    for (var attempt = 0;
        attempt < 50 && find.byKey(const ValueKey('art-703')).evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('art-703')), findsOneWidget);
    expect(audio.sourceId, 703);
    expect(audio.mediaItem!.title, 'Track 703');
    expect(state.queue, isEmpty);
  });

  testWidgets(
    'loading and failure clear the old timeline and offer a working retry',
    (tester) async {
      final collections = LibraryCollections(preferences: MemoryPreferences());
      final audio = FakeAudioPlayer();
      final state = PlayerState(collections: collections, audioPlayer: audio);
      addTearDown(state.dispose);
      addTearDown(collections.dispose);
      await state.playFromLibrary(songs.first, songs);
      audio.position = const Duration(seconds: 60);
      await mount(tester, state, mini: true);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 60000);
      audio.loadGates[702] = Completer<void>();
      audio.failures[702] = StateError('Missing file');
      final loading = state.playNext();
      await tester.pumpAndSettle();
      expect(find.text('Loading track…'), findsNothing);
      expect(find.text(songs[1].artist), findsNWidgets(2));
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
      audio.loadGates[702]!.complete();
      await loading;
      await tester.pumpAndSettle();
      expect(find.text(state.playbackError!), findsOneWidget);
      expect(find.text('Unable to play · Tap to view'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(state.currentSong!.id, 702);
      expect(audio.playing, isFalse);
      audio.failures.clear();
      await tester.tap(find.byTooltip('Play'));
      await tester.pumpAndSettle();
      expect(state.playbackError, isNull);
      expect(audio.sourceId, 702);
      expect(state.playing, isTrue);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
      expect(find.text('Unable to play · Tap to view'), findsNothing);
    },
  );
}
