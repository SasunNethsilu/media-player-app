import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/models/song.dart';
import 'package:media_player/providers/library_collections.dart';

import 'support/memory_preferences.dart';

void main() {
  late MemoryPreferences preferences;
  late LibraryCollections collections;
  late String id;

  setUp(() async {
    preferences = MemoryPreferences();
    collections = LibraryCollections(preferences: preferences);
    await collections.load();
    id = collections.createPlaylist('Original').id;
    collections.setPlaylistSongs(id, [1, 2, 3, 4]);
  });

  tearDown(() => collections.dispose());

  test(
    'rapid edits persist in order and leave previous snapshots unchanged',
    () async {
      final original = collections.playlistById(id)!;
      final other = collections.createPlaylist('Other');
      collections.setPlaylistSongs(other.id, [1, 2]);
      collections.recordPlayed(2);

      await Future.wait([
        collections.renamePlaylist(id, '  Road trip  '),
        collections.removePlaylistSong(id, 2),
        collections.reorderPlaylistSong(id, 1, 4),
      ]);

      final restored = LibraryCollections(preferences: preferences);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.playlistById(id)!.name, 'Road trip');
      expect(restored.playlistById(id)!.songIds, [3, 4, 1]);
      expect(restored.playlistById(other.id)!.songIds, [1, 2]);
      expect(original.name, 'Original');
      expect(original.songIds, [1, 2, 3, 4]);
    },
  );

  test('blank rename is rejected and preserves the saved name', () async {
    await collections.renamePlaylist(id, 'Saved');
    await expectLater(
      collections.renamePlaylist(id, ' \n '),
      throwsArgumentError,
    );
    final restored = LibraryCollections(preferences: preferences);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.playlistById(id)!.name, 'Saved');
  });

  test(
    'reorder works in both directions and retains unavailable song IDs',
    () async {
      await collections.reorderPlaylistSong(id, 1, 4);
      expect(collections.playlistById(id)!.songIds, [2, 3, 4, 1]);
      await collections.reorderPlaylistSong(id, 1, 2);
      expect(collections.playlistById(id)!.songIds, [1, 2, 3, 4]);
      await collections.reorderPlaylistSong(id, 1, 3);
      expect(collections.playlistById(id)!.songIds, [2, 3, 1, 4]);
      await collections.reorderPlaylistSong(id, 99, 1);
      expect(collections.playlistById(id)!.songIds, [2, 3, 1, 4]);
    },
  );

  test('removal only changes membership and can empty a playlist', () async {
    final directory = await Directory.systemTemp.createTemp('playlist-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/song.mp3')
        .writeAsString('audio');
    final library = [
      Song(
        id: 1,
        title: 'Local song',
        artist: 'Artist',
        album: 'Album',
        path: file.path,
        durationMs: 1000,
      ),
    ];
    expect(
      collections.songsFor(collections.playlistById(id)!.songIds, library),
      [library.single],
    );
    for (final songId in [1, 2, 3, 4]) {
      await collections.removePlaylistSong(id, songId);
    }
    expect(await file.readAsString(), 'audio');
    expect(library.single.path, file.path);
    expect(
      collections.songsFor(collections.playlistById(id)!.songIds, library),
      isEmpty,
    );
    final restored = LibraryCollections(preferences: preferences);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.playlistById(id)!.songIds, isEmpty);
  });

  test('failed edit writes report an error and later edits recover', () async {
    await collections.renamePlaylist(id, 'Saved');
    preferences.failures.add('write');
    await collections.renamePlaylist(id, 'Unsaved');
    expect(collections.error, isNotNull);
    final restored = LibraryCollections(preferences: preferences);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.playlistById(id)!.name, 'Saved');
    preferences.failures.clear();
    await collections.renamePlaylist(id, 'Recovered');
    expect(collections.error, isNull);
    await restored.load();
    expect(restored.playlistById(id)!.name, 'Recovered');
  });
}
