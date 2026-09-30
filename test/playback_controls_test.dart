import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/main.dart';
import 'package:media_player/models/song.dart';
import 'package:media_player/providers/library_collections.dart';
import 'package:media_player/providers/player_state.dart';
import 'package:media_player/screens/now_playing_screen.dart';
import 'package:media_player/screens/playlist_screen.dart';
import 'package:media_player/screens/queue_screen.dart';
import 'package:media_player/widgets/mini_player.dart';
import 'package:provider/provider.dart';

import 'support/fake_audio_player.dart';
import 'support/memory_preferences.dart';

class LibraryTestPlayer extends PlayerState {
  final List<Song> library;

  LibraryTestPlayer({
    required super.collections,
    required super.audioPlayer,
    required this.library,
  }) : super(random: Random(7));

  @override
  List<Song> get songs => library;

  @override
  Future<void> loadLibrary() async {}
}

void main() {
  late LibraryCollections collections;
  late LibraryTestPlayer state;
  late FakeAudioPlayer audio;
  late String playlistId;
  final songs = [
    for (var i = 1; i <= 4; i++)
      Song(
        id: i,
        title: 'Track $i',
        artist: 'Artist',
        album: 'Album',
        path: '/music/$i.mp3',
        durationMs: 180000,
      ),
  ];

  Future<void> initialize() async {
    collections = LibraryCollections(preferences: MemoryPreferences());
    playlistId = collections.createPlaylist('Mix').id;
    collections.setPlaylistSongs(playlistId, [1, 2, 3, 4]);
    audio = FakeAudioPlayer();
    state = LibraryTestPlayer(
      collections: collections,
      audioPlayer: audio,
      library: songs,
    );
    await state.playFromLibrary(songs.first, songs, playlistId: playlistId);
  }

  tearDown(() {
    state.dispose();
    collections.dispose();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget app, {
    Size size = const Size(420, 950),
  }) async {
    await initialize();
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryCollections>.value(value: collections),
          ChangeNotifierProvider<PlayerState>.value(value: state),
        ],
        child: app,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Now Playing toggles modes and mini player reflects playback and repeat-aware Next',
    (tester) async {
      await pump(
        tester,
        const MaterialApp(
          home: Scaffold(
            body: NowPlayingScreen(),
            bottomNavigationBar: MiniPlayer(),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Shuffle off'));
      await tester.pumpAndSettle();
      expect(state.shuffleEnabled, isTrue);
      expect(find.byTooltip('Shuffle on'), findsOneWidget);
      expect(audio.loadedIds, [1]);
      await tester.tap(find.byTooltip('Repeat off'));
      await tester.pumpAndSettle();
      expect(state.repeatMode, PlaybackRepeatMode.one);
      await tester.tap(find.byTooltip('Repeat one'));
      await tester.pumpAndSettle();
      expect(state.repeatMode, PlaybackRepeatMode.all);
      state.clearUpcomingQueue();
      await tester.pumpAndSettle();
      final miniNext = find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.byTooltip('Next'),
      );
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: miniNext, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(miniNext);
      await tester.pumpAndSettle();
      expect(audio.loadedIds, [1, 1]);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(state.playing, isFalse);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNWidgets(2));
      await tester.tap(find.byTooltip('Repeat all'));
      await tester.pumpAndSettle();
      expect(state.repeatMode, PlaybackRepeatMode.off);
      expect(find.byTooltip('No next song'), findsNWidgets(2));
    },
  );

  testWidgets(
    'playlist shuffle and card Play/Pause share the active playback state',
    (tester) async {
      await pump(tester, const MyApp());
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mix'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistScreen), findsOneWidget);
      await tester.tap(find.text('Shuffle'));
      await tester.pumpAndSettle();
      expect(state.shuffleEnabled, isTrue);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Shuffle'),
            )
            .style!
            .foregroundColor!
            .resolve({}),
        isNot(Colors.white),
      );
      expect(audio.loadedIds, [1]);
      expect(collections.playlistById(playlistId)!.songIds, [1, 2, 3, 4]);
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(state.playing, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final cardPlay = find.byTooltip('Play Mix');
      expect(cardPlay, findsOneWidget);
      await tester.tap(cardPlay);
      await tester.pumpAndSettle();
      expect(state.playing, isTrue);
      expect(find.byTooltip('Pause Mix'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.byTooltip('Pause'),
        ),
        findsOneWidget,
      );
      expect(audio.loadedIds, [1]);
      expect(state.activePlaylistId, playlistId);
    },
  );

  testWidgets(
    'queue drag, swipe removal and Clear upcoming preserve current playback',
    (tester) async {
      await pump(tester, const MaterialApp(home: QueueScreen()));
      final handles = find.byType(ReorderableDragStartListener);
      final start = tester.getCenter(handles.first);
      final target = tester.getCenter(handles.last) + const Offset(0, 80);
      final gesture = await tester.startGesture(start);
      await tester.pump();
      for (var step = 1; step <= 20; step++) {
        await gesture.moveTo(Offset.lerp(start, target, step / 20)!);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(state.queue.map((song) => song.id), [3, 4, 2]);
      await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(state.queue.map((song) => song.id), [4, 2]);
      await tester.tap(find.byTooltip('Clear upcoming queue'));
      await tester.pumpAndSettle();
      expect(state.queue, isEmpty);
      expect(state.currentSong!.id, 1);
      expect(state.playing, isTrue);
      expect(audio.loadedIds, [1]);
    },
  );

  for (final size in [
    const Size(320, 800),
    const Size(390, 844),
    const Size(420, 700),
    const Size(800, 600),
    const Size(800, 360),
  ]) {
    testWidgets('Now Playing aligns artwork, timeline and controls at $size', (
      tester,
    ) async {
      await pump(
        tester,
        const MaterialApp(home: NowPlayingScreen()),
        size: size,
      );
      final artwork = tester.getRect(
        find.byKey(const ValueKey('artwork-placeholder')),
      );
      final slider = tester.getRect(find.byType(Slider));
      final controls = tester.getRect(
        find
            .ancestor(
              of: find.byTooltip('Shuffle off'),
              matching: find.byType(Row),
            )
            .first,
      );
      expect(slider.left, closeTo(artwork.left, 0.1));
      expect(slider.right, closeTo(artwork.right, 0.1));
      expect(controls.left, closeTo(artwork.left, 0.1));
      expect(controls.right, closeTo(artwork.right, 0.1));
      expect(
        tester.getCenter(find.byIcon(Icons.pause_rounded)).dx,
        closeTo(artwork.center.dx, 0.1),
      );
      expect(
        tester.getRect(find.text('0:00')).left,
        closeTo(artwork.left + 16, 0.1),
      );
      expect(
        tester.getRect(find.text('3:00')).right,
        closeTo(artwork.right - 16, 0.1),
      );
      await tester.ensureVisible(find.byTooltip('Shuffle off'));
      await tester.tap(find.byTooltip('Shuffle off'));
      await tester.pumpAndSettle();
      expect(state.shuffleEnabled, isTrue);
      await tester.tap(find.byTooltip('Repeat off'));
      await tester.pumpAndSettle();
      expect(state.repeatMode, PlaybackRepeatMode.one);
    });
  }
}
