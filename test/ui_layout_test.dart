import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/main.dart';
import 'package:media_player/models/song.dart';
import 'package:media_player/models/library_catalog.dart';
import 'package:media_player/providers/library_collections.dart';
import 'package:media_player/providers/player_state.dart';
import 'package:media_player/providers/app_settings.dart';
import 'package:media_player/screens/library_screen.dart';
import 'package:media_player/screens/library_browse_screen.dart';
import 'package:media_player/screens/songs_screen.dart';
import 'package:media_player/screens/playlist_screen.dart';
import 'package:media_player/screens/now_playing_screen.dart';
import 'package:media_player/screens/queue_screen.dart';
import 'package:media_player/widgets/mini_player.dart';
import 'package:provider/provider.dart';

import 'playback_controls_test.dart' show LibraryTestPlayer;
import 'support/fake_audio_player.dart';
import 'support/memory_preferences.dart';

class StatusPlayer extends LibraryTestPlayer {
  final String status;
  StatusPlayer({required super.collections, required this.status})
    : super(audioPlayer: FakeAudioPlayer(), library: []);
  @override
  bool get isLoadingLibrary => status == 'loading';
  @override
  String? get libraryError => status == 'error'
      ? 'Audio access is needed to show your music. Grant permission in settings.'
      : null;
}

void main() {
  late LibraryCollections collections;
  late AppSettings settings;
  late LibraryTestPlayer player;
  late String playlistId;
  final songs = List.generate(
    12,
    (i) => Song(
      id: 900 + i,
      title: 'A very long song title that needs to remain readable number $i',
      artist: 'An exceptionally long artist name for layout checks',
      album: 'Album',
      path: '/music/$i.mp3',
      durationMs: 180000,
    ),
  );

  setUp(() async {
    collections = LibraryCollections(preferences: MemoryPreferences());
    settings = AppSettings(preferences: MemoryPreferences());
    playlistId = collections
        .createPlaylist('A long playlist name with plenty of words')
        .id;
    collections.setPlaylistSongs(playlistId, songs.map((s) => s.id).toList());
    player = LibraryTestPlayer(
      collections: collections,
      audioPlayer: FakeAudioPlayer(),
      library: songs,
    );
    await player.playFromLibrary(songs.first, songs, playlistId: playlistId);
  });
  tearDown(() {
    player.dispose();
    collections.dispose();
    settings.dispose();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget screen,
    Size size, {
    double keyboard = 0,
    bool settle = true,
    bool reduceMotion = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryCollections>.value(value: collections),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
          ChangeNotifierProvider<PlayerState>.value(value: player),
        ],
        child: Builder(
          builder: (context) => MaterialApp(
            theme: (const MyApp().build(context) as MaterialApp).theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                disableAnimations: reduceMotion,
                viewInsets: EdgeInsets.only(bottom: keyboard),
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 20),
              ),
              child: child!,
            ),
            home: screen,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  for (final size in [const Size(320, 640), const Size(800, 360)]) {
    for (final page in [
      'library',
      'playlists',
      'songs',
      'playlist',
      'player',
      'queue',
    ]) {
      testWidgets('$page supports large text and safe areas at $size', (
        tester,
      ) async {
        final screen = switch (page) {
          'library' || 'playlists' => const LibraryScreen(),
          'songs' => const SongsScreen(),
          'playlist' => PlaylistScreen(playlistId: playlistId),
          'player' => const NowPlayingScreen(),
          _ => const QueueScreen(),
        };
        await mount(tester, screen, size);
        if (page == 'playlists') {
          await tester.tap(find.text('Playlists'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        if (page == 'playlist') {
          expect(find.byType(MiniPlayer), findsOneWidget);
          await tester.drag(
            find.byType(CustomScrollView).first,
            const Offset(0, -900),
          );
          await tester.pumpAndSettle();
          expect(find.byTooltip('Pause').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        if (page == 'player') {
          for (final widget in tester.widgetList<AnimatedSwitcher>(
            find.byType(AnimatedSwitcher),
          )) {
            expect(widget.duration, Duration.zero);
          }
        }
      });
    }
  }

  testWidgets('playlist rename remains usable with large text and keyboard', (
    tester,
  ) async {
    await mount(
      tester,
      PlaylistScreen(playlistId: playlistId),
      const Size(320, 640),
      keyboard: 260,
    );
    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename playlist'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextFormField), 'Renamed');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(collections.playlistById(playlistId)!.name, 'Renamed');
  });

  testWidgets('songs remain scrollable with keyboard and large text', (
    tester,
  ) async {
    await mount(tester, const MainShell(), const Size(320, 640), keyboard: 260);
    await tester.tap(find.text('Songs').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'long');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Library and Playlists pills remain visible while each list scrolls',
    (tester) async {
      for (var i = 0; i < 8; i++) {
        collections.createPlaylist('Another playlist $i');
      }
      await mount(tester, const LibraryScreen(), const Size(320, 480));

      final playlistsPill = find.text('Playlists');
      final pillPosition = tester.getTopLeft(playlistsPill);
      await tester.drag(
        find.byKey(const PageStorageKey('library-overview')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(playlistsPill), pillPosition);

      await tester.tap(playlistsPill);
      await tester.pumpAndSettle();
      final libraryPill = find.text('Library');
      final libraryPosition = tester.getTopLeft(libraryPill);
      await tester.drag(
        find.byKey(const PageStorageKey('local-playlists-grid')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(libraryPill), libraryPosition);

      await tester.tap(libraryPill);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey('library-overview')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('artist album subtitle fits within its horizontal list', (
    tester,
  ) async {
    final artist = groupArtists(songs).single;
    await mount(
      tester,
      ArtistDetailScreen(artist: artist),
      const Size(390, 844),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -380));
    await tester.pumpAndSettle();

    final albumList = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    );
    final subtitle = find.descendant(
      of: albumList,
      matching: find.text(artist.name),
    );
    expect(subtitle, findsOneWidget);
    expect(
      tester.getRect(subtitle).bottom,
      lessThanOrEqualTo(tester.getRect(albumList).bottom),
    );
  });
  testWidgets('playlist song picker supports a keyboard in landscape', (
    tester,
  ) async {
    await mount(
      tester,
      PlaylistScreen(playlistId: playlistId),
      const Size(800, 360),
      keyboard: 140,
    );
    await tester.tap(find.byTooltip('Choose songs'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'long');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(collections.playlistById(playlistId)!.songIds, hasLength(12));
  });

  testWidgets('song menu and add sheet support large text in landscape', (
    tester,
  ) async {
    await mount(tester, const QueueScreen(), const Size(800, 360));
    await tester.tap(find.byTooltip('Options for ${songs.first.title}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to playlist'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Create new playlist'));
    await tester.tap(find.text('Create new playlist'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'New mix');
    await tester.ensureVisible(find.text('Create & add'));
    await tester.tap(find.text('Create & add'));
    await tester.pumpAndSettle();
    expect(collections.playlists.last.songIds, contains(songs.first.id));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty queue stays readable with large text', (tester) async {
    player.clearUpcomingQueue();
    await mount(tester, const QueueScreen(), const Size(320, 480));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('You’re all caught up'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final status in ['empty', 'loading', 'error']) {
    for (final songsScreen in [false, true]) {
      testWidgets(
        '${songsScreen ? 'Songs' : 'Library'} $status state fits landscape',
        (tester) async {
          player.dispose();
          player = StatusPlayer(collections: collections, status: status);
          await mount(
            tester,
            songsScreen ? const SongsScreen() : const LibraryScreen(),
            const Size(800, 360),
            settle: status != 'loading',
          );
          if (status == 'loading') {
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
          } else {
            expect(find.text('Scan again'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'rotation lays out square artwork on the first frame without changing playback',
    (tester) async {
      await mount(
        tester,
        const NowPlayingScreen(),
        const Size(390, 844),
        reduceMotion: false,
      );
      final current = player.currentSong;
      final queue = List<Song>.of(player.queue);
      final audio = player.player as FakeAudioPlayer;
      final loads = List<int>.of(audio.loadedIds);
      for (final size in [const Size(844, 390), const Size(390, 844)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final art = tester.getSize(
          find.byKey(const ValueKey('artwork-placeholder')),
        );
        expect(art.width, closeTo(art.height, 0.01));
        final firstFrame = tester.getRect(
          find.byKey(const ValueKey('artwork-placeholder')),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.getRect(find.byKey(const ValueKey('artwork-placeholder'))),
          firstFrame,
        );
        expect(player.currentSong, current);
        expect(player.queue, orderedEquals(queue));
        expect(audio.loadedIds, orderedEquals(loads));
        expect(player.playing, isTrue);
      }
    },
  );
}
