import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/models/song.dart';
import 'package:media_player/providers/library_collections.dart';
import 'package:media_player/providers/player_state.dart';
import 'package:media_player/services/system_media_handler.dart';

import 'support/fake_audio_player.dart';
import 'support/memory_preferences.dart';

void main() {
  final songs = [
    for (var id = 1; id <= 3; id++)
      Song(
        id: id,
        title: 'Track $id',
        artist: 'Artist $id',
        album: 'Album',
        path: '/music/$id.mp3',
        durationMs: 180000,
      ),
  ];

  test('system controls use PlayerState queue and publish its modes', () async {
    final collections = LibraryCollections(preferences: MemoryPreferences());
    final audio = FakeAudioPlayer();
    final handler = SystemMediaHandler(artworkUriLoader: (_) async => null);
    final state = PlayerState(
      collections: collections,
      audioPlayer: audio,
      systemMediaHandler: handler,
    );
    addTearDown(() {
      state.dispose();
      collections.dispose();
    });

    await state.playFromLibrary(songs.first, songs, playlistId: 'playlist');

    expect(handler.mediaItem.value?.title, 'Track 1');
    expect(handler.queue.value.map((item) => item.title), [
      'Track 1',
      'Track 2',
      'Track 3',
    ]);
    expect(
      handler.playbackState.value.controls.map((control) => control.action),
      [MediaAction.skipToPrevious, MediaAction.pause, MediaAction.skipToNext],
    );

    await handler.pause();
    expect(state.playing, isFalse);
    expect(handler.playbackState.value.controls[1].action, MediaAction.play);

    await handler.play();
    expect(state.playing, isTrue);
    await handler.skipToNext();
    expect(state.currentSong?.id, 2);
    expect(audio.sourceId, 2);
    expect(state.activePlaylistId, 'playlist');

    await handler.seek(const Duration(seconds: 20));
    expect(audio.position, const Duration(seconds: 20));
    await handler.skipToPrevious();
    expect(state.currentSong?.id, 2);
    expect(audio.position, Duration.zero);
    await handler.skipToPrevious();
    expect(state.currentSong?.id, 1);

    await handler.setShuffleMode(AudioServiceShuffleMode.all);
    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    expect(state.shuffleEnabled, isTrue);
    expect(state.repeatMode, PlaybackRepeatMode.all);
    expect(
      handler.playbackState.value.shuffleMode,
      AudioServiceShuffleMode.all,
    );
    expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.all);
  });

  test('late system artwork cannot replace a newer track', () async {
    final artwork = <int, Completer<Uri?>>{
      1: Completer<Uri?>(),
      2: Completer<Uri?>(),
    };
    final handler = SystemMediaHandler(
      artworkUriLoader: (id) => artwork[id]!.future,
    );
    addTearDown(handler.detach);

    handler.synchronize(
      SystemMediaSnapshot(
        sequence: songs,
        currentIndex: 0,
        canGoNext: true,
        shuffleEnabled: false,
        repeatMode: PlaybackRepeatMode.off,
        isLoadingTrack: false,
        playbackError: null,
      ),
    );
    handler.synchronize(
      SystemMediaSnapshot(
        sequence: songs,
        currentIndex: 1,
        canGoNext: true,
        shuffleEnabled: false,
        repeatMode: PlaybackRepeatMode.off,
        isLoadingTrack: false,
        playbackError: null,
      ),
    );

    artwork[1]!.complete(Uri.file('/tmp/old.img'));
    await Future<void>.delayed(Duration.zero);
    expect(handler.mediaItem.value?.title, 'Track 2');
    expect(handler.mediaItem.value?.artUri, isNull);

    artwork[2]!.complete(Uri.file('/tmp/current.img'));
    await Future<void>.delayed(Duration.zero);
    expect(handler.mediaItem.value?.title, 'Track 2');
    expect(handler.mediaItem.value?.artUri, Uri.file('/tmp/current.img'));
  });
}
