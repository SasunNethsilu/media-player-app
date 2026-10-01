import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/models/playback_sequence.dart';
import 'package:media_player/models/song.dart';
import 'package:media_player/providers/library_collections.dart';
import 'package:media_player/providers/player_state.dart';
import 'package:media_player/services/playback_session_store.dart';

import 'support/fake_audio_player.dart';
import 'support/memory_preferences.dart';

void main() {
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

  test('session state and throttled position updates are persisted', () async {
    final writtenKeys = <String>[];
    final preferences = MemoryPreferences(
      onWrite: (key, _) => writtenKeys.add(key),
    );
    final store = PlaybackSessionStore(preferences: preferences);
    final collections = LibraryCollections(preferences: MemoryPreferences());
    final audio = FakeAudioPlayer();
    final state = PlayerState(
      collections: collections,
      audioPlayer: audio,
      random: Random(7),
      sessionStore: store,
      scanSongs: () async => songs,
      positionPersistenceInterval: const Duration(milliseconds: 20),
      sequencePersistenceDebounce: const Duration(milliseconds: 20),
    );
    addTearDown(state.dispose);
    addTearDown(collections.dispose);

    await state.loadLibrary();
    await state.playFromLibrary(
      songs[1],
      songs,
      playlistId: 'missing-playlist',
    );
    state.toggleShuffle();
    state.setRepeatMode(PlaybackRepeatMode.all);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await store.flush();
    writtenKeys.clear();

    audio.emitPosition(const Duration(seconds: 10));
    audio.emitPosition(const Duration(seconds: 20));
    audio.emitPosition(const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await store.flush();

    expect(writtenKeys, [PlaybackSessionStore.checkpointKey]);
    final saved = await store.load();
    expect(saved, isNotNull);
    expect(saved!.entries, hasLength(4));
    expect(saved.currentIndex, 1);
    expect(saved.positionMs, const Duration(seconds: 30).inMilliseconds);
    expect(saved.shuffleEnabled, isTrue);
    expect(saved.repeatMode, PlaybackRepeatMode.all);
    expect(saved.playlistId, 'missing-playlist');
  });

  test('rapid queue edits produce one debounced sequence write', () async {
    final writtenKeys = <String>[];
    final preferences = MemoryPreferences(
      onWrite: (key, _) => writtenKeys.add(key),
    );
    final store = PlaybackSessionStore(preferences: preferences);
    final collections = LibraryCollections(preferences: MemoryPreferences());
    final state = PlayerState(
      collections: collections,
      audioPlayer: FakeAudioPlayer(),
      sessionStore: store,
      scanSongs: () async => songs,
      sequencePersistenceDebounce: const Duration(milliseconds: 20),
    );
    addTearDown(state.dispose);
    addTearDown(collections.dispose);

    await state.loadLibrary();
    await state.playFromLibrary(songs.first, songs);
    await store.flush();
    writtenKeys.clear();

    state.reorderQueue(0, 2);
    state.reorderQueue(1, 0);
    state.removeFromQueue(songs[3]);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await store.flush();

    expect(
      writtenKeys.where(
        (key) => key.startsWith(PlaybackSessionStore.sequenceKeyPrefix),
      ),
      hasLength(1),
    );
    expect(
      writtenKeys.where((key) => key == PlaybackSessionStore.checkpointKey),
      hasLength(1),
    );
  });

  test(
    'restore reconciles changed IDs and missing files and stays paused',
    () async {
      final preferences = MemoryPreferences();
      final store = PlaybackSessionStore(preferences: preferences);
      final collections = LibraryCollections(preferences: MemoryPreferences());
      final playlist = collections.createPlaylist('Saved source');
      final movedCurrent = Song(
        id: 91,
        title: songs[1].title,
        artist: songs[1].artist,
        album: songs[1].album,
        path: '/moved/2.mp3',
        durationMs: songs[1].durationMs,
      );
      final changedId = Song(
        id: 90,
        title: songs[0].title,
        artist: songs[0].artist,
        album: songs[0].album,
        path: songs[0].path,
        durationMs: songs[0].durationMs,
      );
      final reusedMissingId = Song(
        id: songs[2].id,
        title: 'Different recording',
        artist: 'Someone else',
        album: 'Other album',
        path: '/music/reused.mp3',
        durationMs: songs[2].durationMs,
      );
      final library = [changedId, movedCurrent, reusedMissingId, songs[3]];
      final saved = SavedPlaybackSession.capture(
        sequence: PlaybackSequenceSnapshot(
          songs: songs,
          orders: const [0, 1, 2, 3],
          currentIndex: 1,
          shuffleEnabled: true,
          repeatMode: PlaybackRepeatMode.all,
        ),
        position: const Duration(seconds: 47),
        playlistId: playlist.id,
      );
      await store.save(saved);

      final audio = FakeAudioPlayer();
      final state = PlayerState(
        collections: collections,
        audioPlayer: audio,
        sessionStore: store,
        scanSongs: () async => library,
      );
      addTearDown(state.dispose);
      addTearDown(collections.dispose);

      await state.loadLibrary();

      expect(state.currentSong, same(movedCurrent));
      expect(state.queue, orderedEquals([songs[3]]));
      expect(state.shuffleEnabled, isTrue);
      expect(state.repeatMode, PlaybackRepeatMode.all);
      expect(state.activePlaylistId, playlist.id);
      expect(audio.sourceId, movedCurrent.id);
      expect(audio.position, const Duration(seconds: 47));
      expect(audio.playing, isFalse);
      expect(audio.playCalls, 0);
      expect(state.playing, isFalse);
      expect(state.canSeek, isTrue);
    },
  );

  test('missing current track selects the next survivor at position zero', () {
    final saved = SavedPlaybackSession.capture(
      sequence: PlaybackSequenceSnapshot(
        songs: songs,
        orders: const [0, 1, 2, 3],
        currentIndex: 1,
        shuffleEnabled: false,
        repeatMode: PlaybackRepeatMode.off,
      ),
      position: const Duration(seconds: 80),
      playlistId: null,
    );

    final restored = saved.reconcile([songs[0], songs[2], songs[3]]);

    expect(restored, isNotNull);
    expect(
      restored!.sequence.songs,
      orderedEquals([songs[0], songs[2], songs[3]]),
    );
    expect(restored.sequence.currentIndex, 1);
    expect(restored.sequence.songs[1], same(songs[2]));
    expect(restored.position, Duration.zero);
  });

  test(
    'restored shuffle retains history and can recover original order',
    () async {
      final preferences = MemoryPreferences();
      final store = PlaybackSessionStore(preferences: preferences);
      final saved = SavedPlaybackSession.capture(
        sequence: PlaybackSequenceSnapshot(
          songs: [songs[0], songs[2], songs[3], songs[1]],
          orders: const [0, 2, 3, 1],
          currentIndex: 1,
          shuffleEnabled: true,
          repeatMode: PlaybackRepeatMode.all,
        ),
        position: const Duration(seconds: 15),
        playlistId: null,
      );
      await store.save(saved);
      final collections = LibraryCollections(preferences: MemoryPreferences());
      final audio = FakeAudioPlayer();
      final state = PlayerState(
        collections: collections,
        audioPlayer: audio,
        sessionStore: store,
        scanSongs: () async => songs,
      );
      addTearDown(state.dispose);
      addTearDown(collections.dispose);

      await state.loadLibrary();
      expect(state.currentSong, same(songs[2]));
      expect(state.queue, orderedEquals([songs[3], songs[1]]));

      state.toggleShuffle();
      expect(state.queue, orderedEquals([songs[1], songs[3]]));
      await state.playNext();
      await state.playNext();
      await state.playNext();

      expect(state.currentSong, same(songs[0]));
      expect(state.repeatMode, PlaybackRepeatMode.all);
    },
  );

  test('session and collections persist through one shared backend', () async {
    final preferences = MemoryPreferences();
    final collections = LibraryCollections(preferences: preferences);
    final store = PlaybackSessionStore(preferences: preferences);
    final playlist = collections.createPlaylist('Shared storage');
    await collections.renamePlaylist(playlist.id, 'Shared storage saved');
    final state = PlayerState(
      collections: collections,
      audioPlayer: FakeAudioPlayer(),
      sessionStore: store,
      scanSongs: () async => songs,
    );
    addTearDown(state.dispose);
    addTearDown(collections.dispose);

    await state.loadLibrary();
    await state.playFromLibrary(songs.first, songs, playlistId: playlist.id);
    await store.flush();

    final restoredCollections = LibraryCollections(preferences: preferences);
    await restoredCollections.load();
    final restoredStore = PlaybackSessionStore(preferences: preferences);
    final restoredState = PlayerState(
      collections: restoredCollections,
      audioPlayer: FakeAudioPlayer(),
      sessionStore: restoredStore,
      scanSongs: () async => songs,
    );
    addTearDown(restoredState.dispose);
    addTearDown(restoredCollections.dispose);

    await restoredState.loadLibrary();

    expect(restoredCollections.playlistById(playlist.id), isNotNull);
    expect(restoredState.currentSong, same(songs.first));
    expect(restoredState.activePlaylistId, playlist.id);
    expect(restoredState.playing, isFalse);
  });

  test('legacy session migrates to split versioned records', () async {
    final preferences = MemoryPreferences();
    preferences.values[PlaybackSessionStore.storageKey] = jsonEncode({
      'version': 1,
      'entries': [
        for (var i = 0; i < songs.length; i++)
          {
            'track': SavedTrackReference.fromSong(songs[i]).toJson(),
            'order': i,
          },
      ],
      'currentIndex': 1,
      'positionMs': 42000,
      'shuffleEnabled': false,
      'repeatMode': PlaybackRepeatMode.one.name,
      'playlistId': null,
    });
    final store = PlaybackSessionStore(preferences: preferences);
    final collections = LibraryCollections(preferences: MemoryPreferences());
    final state = PlayerState(
      collections: collections,
      audioPlayer: FakeAudioPlayer(),
      sessionStore: store,
      scanSongs: () async => songs,
    );
    addTearDown(state.dispose);
    addTearDown(collections.dispose);

    await state.loadLibrary();
    await store.flush();

    expect(state.currentSong, same(songs[1]));
    expect(state.repeatMode, PlaybackRepeatMode.one);
    expect(preferences.values[PlaybackSessionStore.storageKey], isNull);
    final checkpoint = Map<String, dynamic>.from(
      jsonDecode(preferences.values[PlaybackSessionStore.checkpointKey]!)
          as Map,
    );
    expect(checkpoint['version'], 2);
    expect(
      preferences.values[PlaybackSessionStore.sequenceKey(
        checkpoint['revision'] as String,
      )],
      isNotNull,
    );
  });

  test(
    'malformed saved data is ignored without an empty startup write',
    () async {
      var writes = 0;
      final preferences = MemoryPreferences(onWrite: (_, _) => writes++);
      preferences.values[PlaybackSessionStore.storageKey] = jsonEncode({
        'version': 1,
        'entries': 'invalid',
      });
      final original = preferences.values[PlaybackSessionStore.storageKey];
      final store = PlaybackSessionStore(preferences: preferences);
      final collections = LibraryCollections(preferences: MemoryPreferences());
      final state = PlayerState(
        collections: collections,
        audioPlayer: FakeAudioPlayer(),
        sessionStore: store,
        scanSongs: () async => songs,
      );
      addTearDown(state.dispose);
      addTearDown(collections.dispose);

      await state.loadLibrary();
      await store.flush();

      expect(state.currentSong, isNull);
      expect(writes, 0);
      expect(preferences.values[PlaybackSessionStore.storageKey], original);
    },
  );
}
