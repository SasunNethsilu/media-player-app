import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:media_player/models/song.dart';
import 'package:media_player/providers/library_collections.dart';
import 'package:media_player/providers/player_state.dart';

import 'support/fake_audio_player.dart';
import 'support/memory_preferences.dart';

void main() {
  late LibraryCollections collections;
  late FakeAudioPlayer audio;
  late PlayerState state;
  final songs = [
    for (var i = 1; i <= 5; i++)
      Song(
        id: i,
        title: 'Track $i',
        artist: 'Artist',
        album: 'Album',
        path: '/music/$i.mp3',
        durationMs: 180000,
      ),
  ];
  List<int> queue() => state.queue.map((song) => song.id).toList();
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  Future<void> start({int index = 0}) =>
      state.playFromLibrary(songs[index], songs, playlistId: 'playlist');

  setUp(() {
    collections = LibraryCollections(preferences: MemoryPreferences());
    audio = FakeAudioPlayer();
    state = PlayerState(
      collections: collections,
      audioPlayer: audio,
      random: Random(7),
    );
  });

  tearDown(() {
    state.dispose();
    collections.dispose();
  });

  test('shuffle preserves current source, position, playlist and remaining membership', () async {
    await start();
    audio.position = const Duration(seconds: 45);
    final original = queue();
    state.toggleShuffle();
    expect(state.shuffleEnabled, isTrue);
    expect(queue(), unorderedEquals(original));
    expect(queue(), isNot(original));
    expect(audio.loadedIds, [1]);
    expect(audio.position, const Duration(seconds: 45));
    expect(state.currentSong!.id, 1);
    expect(state.activePlaylistId, 'playlist');
    final played = state.queue.first.id;
    await state.playNext();
    state.toggleShuffle();
    expect(queue(), original.where((id) => id != played).toList());
    expect(audio.loadedIds, [1, played]);
    expect(songs.map((song) => song.id), [1, 2, 3, 4, 5]);
    expect(() => state.queue.clear(), throwsUnsupportedError);
  });

  test(
    'previous follows shuffled playback and next returns to the same track',
    () async {
      await start();
      state.toggleShuffle();
      final firstNext = state.queue.first.id;
      await state.playNext();
      await state.playPrevious();
      expect(state.currentSong!.id, 1);
      expect(state.queue.first.id, firstNext);
      await state.playNext();
      expect(state.currentSong!.id, firstNext);
      audio.position = const Duration(seconds: 4);
      final before = queue();
      await state.playPrevious();
      expect(state.currentSong!.id, firstNext);
      expect(queue(), before);
      expect(audio.seeks.last, Duration.zero);
    },
  );

  test('repeat one restarts on completion but manual next advances', () async {
    await start();
    state.setRepeatMode(PlaybackRepeatMode.one);
    audio.complete();
    await settle();
    expect(audio.loadedIds, [1]);
    expect(audio.seeks, [Duration.zero]);
    expect(state.playing, isTrue);
    expect(queue(), [2, 3, 4, 5]);
    await state.playNext();
    expect(state.currentSong!.id, 2);
    expect(state.repeatMode, PlaybackRepeatMode.one);
  });

  test('repeat all wraps the entire sequence over multiple cycles', () async {
    await start(index: 2);
    state.setRepeatMode(PlaybackRepeatMode.all);
    for (var i = 0; i < 8; i++) {
      audio.complete();
      await settle();
    }
    expect(audio.loadedIds, [3, 4, 5, 1, 2, 3, 4, 5, 1]);
    expect(state.activePlaylistId, 'playlist');
    await state.playPrevious();
    expect(state.currentSong!.id, 5);
    expect(state.canGoNext, isTrue);
    await state.playNext();
    expect(state.currentSong!.id, 1);
  });

  test(
    'repeat off stops at completion and play restarts the last track',
    () async {
      await state.playFromLibrary(songs.first, [songs.first]);
      expect(state.canGoNext, isFalse);
      await state.playNext();
      expect(audio.loadedIds, [1]);
      audio.complete();
      await settle();
      expect(state.playing, isFalse);
      expect(audio.pauseCalls, 1);
      await state.togglePlayPause();
      expect(state.playing, isTrue);
      expect(audio.seeks.last, Duration.zero);
      state.setRepeatMode(PlaybackRepeatMode.all);
      expect(state.canGoNext, isTrue);
      audio.complete();
      await settle();
      expect(audio.loadedIds, [1, 1]);
    },
  );

  test(
    'queue reorder, removal and additions survive shuffle and repeat',
    () async {
      await start();
      state.reorderQueue(0, 3);
      expect(queue(), [3, 4, 5, 2]);
      state.toggleShuffle();
      state.removeFromQueue(songs[3]);
      await state.enqueueNext(songs[1]);
      await state.enqueueLast(songs[1]);
      state.toggleShuffle();
      expect(queue(), [2, 3, 5]);
      state.setRepeatMode(PlaybackRepeatMode.all);
      for (var i = 0; i < 4; i++) {
        await state.playNext();
      }
      expect(audio.loadedIds, [1, 2, 3, 5, 1]);
      expect(queue(), [2, 3, 5]);
    },
  );

  test('clear leaves the current song playing and removes upcoming from repeat cycles', () async {
    await start();
    await state.playNext();
    state.setRepeatMode(PlaybackRepeatMode.all);
    audio.position = const Duration(seconds: 30);
    state.clearUpcomingQueue();
    expect(queue(), isEmpty);
    expect(state.currentSong!.id, 2);
    expect(audio.loadedIds, [1, 2]);
    expect(audio.position, const Duration(seconds: 30));
    expect(state.playing, isTrue);
    state.toggleShuffle();
    state.toggleShuffle();
    audio.complete();
    await settle();
    expect(audio.loadedIds, [1, 2, 1]);
    expect(queue(), [2]);
  });

  test(
    'clear with repeat off stops after current without changing its position',
    () async {
      await start();
      state.clearUpcomingQueue();
      expect(state.playing, isTrue);
      expect(audio.loadedIds, [1]);
      audio.complete();
      await settle();
      expect(state.playing, isFalse);
      expect(audio.loadedIds, [1]);
    },
  );

  test(
    'saved playlist edits do not affect the active playback sequence',
    () async {
      final playlist = collections.createPlaylist('Original');
      collections.setPlaylistSongs(playlist.id, songs.map((song) => song.id));
      await state.playFromLibrary(songs.first, songs, playlistId: playlist.id);
      await collections.renamePlaylist(playlist.id, 'Renamed');
      await collections.removePlaylistSong(playlist.id, 2);
      await collections.reorderPlaylistSong(playlist.id, 1, 5);
      state.toggleShuffle();
      state.toggleShuffle();
      expect(queue(), [2, 3, 4, 5]);
      expect(state.activePlaylistId, playlist.id);
      expect(audio.loadedIds, [1]);
      expect(collections.playlistById(playlist.id)!.songIds, [3, 4, 5, 1]);
    },
  );

  test(
    'rapid next commands coalesce loading and ignore stale completion',
    () async {
      await start();
      audio.loading = Completer<void>();
      final first = state.playNext();
      final second = state.playNext();
      await settle();
      expect(audio.loadedIds, [1, 3]);
      audio.complete();
      audio.loading!.complete();
      await Future.wait([first, second]);
      expect(audio.loadedIds, [1, 3]);
      expect(queue(), [4, 5]);
      audio.complete();
      audio.complete();
      await settle();
      expect(audio.loadedIds, [1, 3, 4]);
    },
  );

  test(
    'intentional repeated tracks have distinct queue keys across repeat cycles',
    () async {
      await state.playFromLibrary(songs.first, songs.take(2).toList());
      await state.enqueueLast(songs.first);
      state.setRepeatMode(PlaybackRepeatMode.all);
      await state.playNext();
      await state.playNext();
      await state.playNext();
      expect(queue(), [2, 1]);
      expect(state.queueKeys.toSet().length, state.queue.length);
      state.removeQueueEntry(state.queueKeys[1]);
      expect(queue(), [2]);
    },
  );

  test('rapid Previous first restarts and then moves backward', () async {
    await start(index: 2);
    audio.position = const Duration(seconds: 40);
    final restart = state.playPrevious();
    final previous = state.playPrevious();
    await Future.wait([restart, previous]);
    expect(audio.seeks, [Duration.zero]);
    expect(state.currentSong!.id, 2);
    expect(audio.sourceId, 2);
    expect(queue(), [3, 4, 5]);
  });

  test('repeat mode cycles off, one, all, off', () {
    expect(state.repeatMode, PlaybackRepeatMode.off);
    state.cycleRepeatMode();
    expect(state.repeatMode, PlaybackRepeatMode.one);
    state.cycleRepeatMode();
    expect(state.repeatMode, PlaybackRepeatMode.all);
    state.cycleRepeatMode();
    expect(state.repeatMode, PlaybackRepeatMode.off);
  });

  test('shuffled repeat cycles include every entry exactly once', () async {
    await start();
    state.toggleShuffle();
    state.setRepeatMode(PlaybackRepeatMode.all);
    final cycle = [state.currentSong!.id, ...queue()];
    for (var i = 0; i < 10; i++) {
      audio.complete();
      await settle();
    }
    expect(audio.loadedIds, [...cycle, ...cycle, cycle.first]);
    expect(cycle, unorderedEquals([1, 2, 3, 4, 5]));
  });

  test(
    'duplicate input occurrences survive shuffle and removal by identity',
    () async {
      await state.playFromLibrary(songs.first, [
        songs.first,
        songs[1],
        songs[1],
        songs[2],
      ]);
      state.toggleShuffle();
      state.toggleShuffle();
      expect(queue(), [2, 2, 3]);
      expect(state.queueKeys.toSet().length, 3);
      final removeKey = state.queueKeys[1];
      await state.playNext();
      state.removeQueueEntry(removeKey);
      expect(state.currentSong!.id, 2);
      expect(queue(), [3]);
    },
  );

  test('disabled shuffle restores remaining order after manual shuffled rearrangement', () async {
    await start();
    state.toggleShuffle();
    state.reorderQueue(0, 3);
    state.toggleShuffle();
    expect(queue(), [2, 3, 4, 5]);
    expect(audio.loadedIds, [1]);
    expect(state.activePlaylistId, 'playlist');
  });

  test(
    'new playback source preserves modes and updates playlist identity',
    () async {
      await start();
      state.toggleShuffle();
      state.setRepeatMode(PlaybackRepeatMode.all);
      await state.playFromLibrary(songs[1], songs);
      expect(state.activePlaylistId, isNull);
      expect(state.shuffleEnabled, isTrue);
      expect(state.repeatMode, PlaybackRepeatMode.all);
      expect(state.currentSong!.id, 2);
      expect(queue(), unorderedEquals([3, 4, 5]));
    },
  );

  test('new selections supersede pending loads without stale audio or recent history', () async {
    await start();
    audio.loadGates[2] = Completer<void>();
    final old = state.playFromLibrary(songs[1], songs, playlistId: 'old');
    await settle();
    expect(state.isLoadingTrack, isTrue);
    expect(state.playing, isFalse);
    expect(audio.playing, isFalse);
    expect(state.canSeek, isFalse);
    final middle = state.playFromLibrary(songs[2], songs, playlistId: 'middle');
    final newest = state.playFromLibrary(songs[3], songs, playlistId: 'newest');
    audio.loadGates[2]!.complete();
    await Future.wait([old, middle, newest]);
    expect(audio.loadedIds, [1, 2, 4]);
    expect(audio.audibleIds, [1, 4]);
    expect(audio.mediaItem!.id, '4');
    expect(audio.mediaItem!.title, state.currentSong!.title);
    expect(state.currentSong!.id, 4);
    expect(queue(), [5]);
    expect(state.activePlaylistId, 'newest');
    expect(collections.recentSongs(songs).map((song) => song.id), [4, 1]);
    expect(state.playbackError, isNull);
    expect(state.isLoadingTrack, isFalse);
  });

  test(
    'mixed next and previous taps keep the final source and queue together',
    () async {
      await start();
      audio.loadGates[2] = Completer<void>();
      final first = state.playNext();
      await settle();
      final next = state.playNext();
      final previous = state.playPrevious();
      audio.loadGates[2]!.complete();
      await Future.wait([first, next, previous]);
      expect(state.currentSong!.id, 2);
      expect(audio.sourceId, 2);
      expect(audio.audibleIds, [1, 2]);
      expect(queue(), [3, 4, 5]);
      expect(state.activePlaylistId, 'playlist');
    },
  );

  for (final mode in PlaybackRepeatMode.values) {
    test('failed automatic track stops without looping in $mode', () async {
      await start();
      state.setRepeatMode(mode);
      if (mode == PlaybackRepeatMode.one) {
        audio.events.addError(const FileSystemException('File deleted'));
      } else {
        audio.failures[2] = const FileSystemException('File deleted');
        audio.complete();
      }
      await settle();
      expect(state.playbackError, contains('missing or unreadable'));
      expect(state.playing, isFalse);
      expect(audio.playing, isFalse);
      final attempted = List<int>.of(audio.loadedIds);
      for (var i = 0; i < 4; i++) {
        audio.emit(ProcessingState.ready);
        audio.complete();
        await settle();
      }
      expect(audio.loadedIds, attempted);
      expect(audio.stopCalls, 1);
      expect(state.repeatMode, mode);
      expect(state.activePlaylistId, 'playlist');
      expect(
        queue(),
        mode == PlaybackRepeatMode.one ? [2, 3, 4, 5] : [3, 4, 5],
      );
    });
  }

  test('manual failure retains selection and Play retries once after file recovery', () async {
    audio.failures[1] = const FileSystemException('Missing file');
    await start();
    expect(state.currentSong!.id, 1);
    expect(queue(), [2, 3, 4, 5]);
    expect(state.playbackError, isNotNull);
    expect(collections.recentSongs(songs), isEmpty);
    await state.togglePlayPause();
    expect(audio.loadedIds, [1, 1]);
    expect(audio.audibleIds, isEmpty);
    audio.failures.clear();
    await state.togglePlayPause();
    expect(audio.loadedIds, [1, 1, 1]);
    expect(audio.audibleIds, [1]);
    expect(state.playbackError, isNull);
    expect(state.playing, isTrue);
    expect(state.activePlaylistId, 'playlist');
  });

  test(
    'manual Next can leave a failed track without altering saved collections',
    () async {
      audio.failures[1] = StateError('Decoder failure');
      await start();
      await state.playNext();
      expect(audio.sourceId, 2);
      expect(state.currentSong!.id, 2);
      expect(queue(), [3, 4, 5]);
      expect(state.playbackError, isNull);
      expect(state.playing, isTrue);
    },
  );

  test(
    'an obsolete load failure cannot stop or mark the newest selection failed',
    () async {
      audio.loadGates[1] = Completer<void>();
      audio.failures[1] = StateError('Old failure');
      final old = start();
      await settle();
      final next = state.playFromLibrary(songs[2], songs, playlistId: 'new');
      audio.loadGates[1]!.complete();
      await Future.wait([old, next]);
      expect(audio.audibleIds, [3]);
      expect(audio.stopCalls, 0);
      expect(state.playbackError, isNull);
      expect(state.currentSong!.id, 3);
      expect(state.activePlaylistId, 'new');
    },
  );

  test(
    'late play-future errors from an old source cannot stop the new track',
    () async {
      await start();
      final oldPlay = audio.playRequests.single;
      await state.playNext();
      oldPlay.completeError(StateError('Obsolete native play error'));
      await settle();
      expect(state.currentSong!.id, 2);
      expect(state.playbackError, isNull);
      expect(state.playing, isTrue);
      expect(audio.stopCalls, 0);
      audio.playRequests.last.completeError(
        StateError('Current native play error'),
      );
      await settle();
      expect(state.playing, isFalse);
      expect(state.playbackError, isNotNull);
      expect(audio.stopCalls, 1);
    },
  );

  test('adding to an exhausted queue stays stopped until Play starts the new upcoming track', () async {
    await state.playFromLibrary(songs.first, [
      songs.first,
    ], playlistId: 'playlist');
    audio.complete();
    await settle();
    await state.enqueueLast(songs[2]);
    await state.enqueueNext(songs[1]);
    expect(state.playing, isFalse);
    expect(state.currentSong!.id, 1);
    expect(queue(), [2, 3]);
    expect(audio.audibleIds, [1]);
    await state.togglePlayPause();
    expect(state.currentSong!.id, 2);
    expect(audio.audibleIds, [1, 2]);
    expect(queue(), [3]);
    expect(state.activePlaylistId, 'playlist');
  });

  test('completion is not lost while a queue addition is pending', () async {
    await state.playFromLibrary(songs.first, [songs.first]);
    await settle();
    final addition = state.enqueueLast(songs[1]);
    audio.complete();
    await addition;
    await settle();
    expect(state.currentSong!.id, 2);
    expect(audio.audibleIds, [1, 2]);
    expect(state.playing, isTrue);
  });

  test('pausing a pending load never starts it and Play resumes the selected source', () async {
    await start();
    audio.loadGates[2] = Completer<void>();
    final next = state.playNext();
    await settle();
    final pause = state.togglePlayPause();
    audio.loadGates[2]!.complete();
    await Future.wait([next, pause]);
    expect(state.currentSong!.id, 2);
    expect(audio.audibleIds, [1]);
    expect(state.playing, isFalse);
    expect(state.isLoadingTrack, isFalse);
    await state.togglePlayPause();
    expect(audio.audibleIds, [1, 2]);
    expect(audio.loadedIds, [1, 2]);
  });

  test(
    'obsolete seek cannot restart audio or change a newer selection',
    () async {
      await start();
      audio.seekGate = Completer<void>();
      final seek = state.seek(const Duration(seconds: 70));
      await settle();
      final next = state.playFromLibrary(songs[3], songs);
      audio.seekGate!.complete();
      await Future.wait([seek, next]);
      expect(audio.sourceId, 4);
      expect(audio.position, Duration.zero);
      expect(state.currentSong!.id, 4);
      expect(audio.audibleIds, [1, 4]);
    },
  );

  test('disposal cancels every stream and suppresses delayed playback and notifications', () async {
    await start();
    audio.loadGates[2] = Completer<void>();
    var notifications = 0;
    state.addListener(() => notifications++);
    final next = state.playNext();
    await settle();
    state.dispose();
    final atDispose = notifications;
    audio.loadGates[2]!.complete();
    await next;
    await settle();
    expect(audio.states.hasListener, isFalse);
    expect(audio.processing.hasListener, isFalse);
    expect(audio.events.hasListener, isFalse);
    expect(audio.disposed, isTrue);
    expect(audio.audibleIds, [1]);
    expect(notifications, atDispose);
    final sourceCount = audio.loadedIds.length;
    await state.playNext();
    await state.togglePlayPause();
    await state.enqueueLast(songs.last);
    expect(audio.loadedIds.length, sourceCount);
    expect(notifications, atDispose);
  });
}
