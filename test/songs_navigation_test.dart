import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/main.dart';
import 'package:media_player/models/song.dart';
import 'package:media_player/providers/library_collections.dart';
import 'package:media_player/providers/player_state.dart';
import 'package:media_player/providers/app_settings.dart';
import 'package:media_player/services/song_filter.dart';
import 'package:media_player/widgets/song_tile.dart';
import 'package:provider/provider.dart';

import 'playback_controls_test.dart' show LibraryTestPlayer;
import 'support/fake_audio_player.dart';
import 'support/memory_preferences.dart';

void main() {
  late LibraryCollections collections;
  late AppSettings settings;
  late LibraryTestPlayer player;
  final songs = [
    Song(
      id: 1,
      title: 'Zebra',
      artist: 'North',
      album: 'A',
      path: '/music/1.mp3',
      durationMs: 180000,
    ),
    Song(
      id: 2,
      title: 'Aurora',
      artist: 'South',
      album: 'B',
      path: '/music/2.mp3',
      durationMs: 180000,
    ),
    Song(
      id: 3,
      title: 'Blue Sky',
      artist: 'North',
      album: 'C',
      path: '/music/3.mp3',
      durationMs: 180000,
    ),
  ];

  setUp(() {
    collections = LibraryCollections(preferences: MemoryPreferences());
    settings = AppSettings(preferences: MemoryPreferences());
    player = LibraryTestPlayer(
      collections: collections,
      audioPlayer: FakeAudioPlayer(),
      library: songs,
    );
  });

  tearDown(() {
    player.dispose();
    collections.dispose();
    settings.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryCollections>.value(value: collections),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
          ChangeNotifierProvider<PlayerState>.value(value: player),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Songs shows the sorted full library when search is empty', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Songs').last);
    await tester.pumpAndSettle();

    expect(find.text('All Songs'), findsOneWidget);
    expect(find.byType(SongTile), findsNWidgets(3));
    expect(find.text('3 songs'), findsOneWidget);
    final titles = tester
        .widgetList<SongTile>(find.byType(SongTile))
        .map((tile) => tile.song.title);
    expect(titles, orderedEquals(['Aurora', 'Blue Sky', 'Zebra']));
  });

  test('sorted Songs selection uses its displayed sequence and clears playlist source', () async {
    final playlistId = collections.createPlaylist('Mix').id;
    await player.playFromLibrary(songs.first, songs, playlistId: playlistId);
    expect(player.activePlaylistId, playlistId);

    final displayed = filterAndSortSongs(songs, 'north', SortOption.title);
    await player.playFromLibrary(displayed.first, displayed);
    expect(player.currentSong?.id, 3);
    expect(player.queue.map((song) => song.id), orderedEquals([1]));
    expect(player.activePlaylistId, isNull);
  });

  testWidgets(
    'search filters titles and artists, then clearing restores all songs',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Songs').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'north');
      await tester.pumpAndSettle();
      expect(find.byType(SongTile), findsNWidgets(2));
      expect(find.text('Aurora'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.byType(SongTile), findsNWidgets(3));
      expect(find.text('Aurora'), findsOneWidget);
    },
  );

  testWidgets(
    'Library shortcut clears search and switches to the existing Songs tab',
    (tester) async {
      await mount(tester);
      expect(find.text('All Songs'), findsOneWidget);
      expect(find.byType(SongTile), findsNothing);

      await tester.tap(find.text('All Songs'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'north');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Songs').last);
      await tester.pumpAndSettle();
      expect(find.byType(SongTile), findsNWidgets(2));

      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Songs'));
      await tester.pumpAndSettle();
      expect(find.byType(SongTile), findsNWidgets(3));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
    },
  );
}
