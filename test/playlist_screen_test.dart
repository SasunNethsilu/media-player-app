import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/models/song.dart';
import 'package:media_player/providers/library_collections.dart';
import 'package:media_player/providers/player_state.dart';
import 'package:media_player/screens/playlist_screen.dart';
import 'package:media_player/widgets/song_tile.dart';
import 'package:provider/provider.dart';

import 'support/memory_preferences.dart';
import 'support/fake_audio_player.dart';

class PlaylistTestPlayer extends PlayerState {
  @override
  final List<Song> songs;
  @override
  final List<Song> queue;
  @override
  final String activePlaylistId;
  @override
  Song get currentSong => songs.first;
  @override
  bool get playing => true;
  @override
  bool get playPauseShowsPause => true;
  @override
  bool get shuffleEnabled => false;

  PlaylistTestPlayer(
    this.songs,
    this.activePlaylistId,
    LibraryCollections collections,
  ) : queue = songs.skip(1).toList(),
      super(collections: collections, audioPlayer: FakeAudioPlayer());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LibraryCollections collections;
  late PlaylistTestPlayer player;
  late String id;

  setUp(() {
    collections = LibraryCollections(preferences: MemoryPreferences());
    id = collections.createPlaylist('Original').id;
    collections.setPlaylistSongs(id, [1, 2, 3]);
    player = PlaylistTestPlayer(
      [
        for (var i = 1; i <= 3; i++)
          Song(
            id: i,
            title: 'Track $i',
            artist: 'Artist',
            album: 'Album',
            path: '/music/$i.mp3',
            durationMs: 180000,
          ),
      ],
      id,
      collections,
    );
  });

  tearDown(() {
    collections.dispose();
    player.dispose();
  });

  Future<void> openPlaylist(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryCollections>.value(value: collections),
          ChangeNotifierProvider<PlayerState>.value(value: player),
        ],
        child: MaterialApp(home: PlaylistScreen(playlistId: id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'rename prefills, rejects blank input, trims and supports cancel',
    (tester) async {
      await openPlaylist(tester);
      await tester.tap(find.byTooltip('Playlist options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename playlist'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
        'Original',
      );
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a playlist name'), findsOneWidget);
      expect(collections.playlistById(id)!.name, 'Original');
      await tester.enterText(find.byType(TextFormField), '  Renamed  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(collections.playlistById(id)!.name, 'Renamed');
      expect(find.text('Renamed'), findsOneWidget);
      await tester.tap(find.byTooltip('Playlist options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Cancelled');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(collections.playlistById(id)!.name, 'Renamed');
      expect(player.queue.map((song) => song.id), [2, 3]);
    },
  );

  testWidgets('playlist removal preserves playback and the library', (
    tester,
  ) async {
    await openPlaylist(tester);
    await tester.tap(find.byTooltip('Options for Track 1'));
    await tester.pumpAndSettle();
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to playlist'), findsOneWidget);
    await tester.tap(find.text('Remove from this playlist'));
    await tester.pumpAndSettle();
    expect(collections.playlistById(id)!.songIds, [2, 3]);
    expect(player.currentSong.id, 1);
    expect(player.playing, isTrue);
    expect(player.activePlaylistId, id);
    expect(player.queue.map((song) => song.id), [2, 3]);
    expect(player.songs.map((song) => song.id), [1, 2, 3]);
  });

  testWidgets(
    'drag handle reorders saved songs without changing active queue',
    (tester) async {
      await openPlaylist(tester);
      final handles = find.byTooltip('Drag to reorder');
      expect(handles, findsNWidgets(3));
      final target = tester.getCenter(handles.last) + const Offset(0, 80);
      final gesture = await tester.startGesture(
        tester.getCenter(handles.first),
      );
      await tester.pump();
      final start = tester.getCenter(handles.first);
      for (var step = 1; step <= 20; step++) {
        await gesture.moveTo(Offset.lerp(start, target, step / 20)!);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(collections.playlistById(id)!.songIds, [2, 3, 1]);
      expect(player.queue.map((song) => song.id), [2, 3]);
      expect(player.currentSong.id, 1);
      expect(find.byTooltip('Options for Track 1'), findsOneWidget);
      final upwardStart = tester.getCenter(handles.last);
      final upwardTarget =
          tester.getCenter(handles.first) - const Offset(0, 30);
      final upwardGesture = await tester.startGesture(upwardStart);
      await tester.pump();
      for (var step = 1; step <= 20; step++) {
        await upwardGesture.moveTo(
          Offset.lerp(upwardStart, upwardTarget, step / 20)!,
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await upwardGesture.up();
      await tester.pumpAndSettle();
      expect(collections.playlistById(id)!.songIds, [1, 2, 3]);
      expect(player.queue.map((song) => song.id), [2, 3]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary song menus exclude removal and custom trailing stays intact',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SongTile(song: player.songs.first)),
        ),
      );
      await tester.tap(find.byTooltip('Options for Track 1'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from this playlist'), findsNothing);
      expect(find.text('Add to playlist'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SongTile(
              song: player.songs.first,
              trailing: const Icon(Icons.drag_handle_rounded),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.drag_handle_rounded), findsOneWidget);
      expect(find.byTooltip('Options for Track 1'), findsNothing);
    },
  );
}
