import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/playback_sequence.dart';
import '../models/song.dart';
import 'artwork_palette_service.dart';

class SystemMediaSnapshot {
  final List<Song> sequence;
  final int currentIndex;
  final bool canGoNext;
  final bool shuffleEnabled;
  final PlaybackRepeatMode repeatMode;
  final bool isLoadingTrack;
  final String? playbackError;

  const SystemMediaSnapshot({
    required this.sequence,
    required this.currentIndex,
    required this.canGoNext,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.isLoadingTrack,
    required this.playbackError,
  });

  Song? get currentSong => currentIndex >= 0 && currentIndex < sequence.length
      ? sequence[currentIndex]
      : null;
}

class SystemMediaHandler extends BaseAudioHandler {
  final Future<Uri?> Function(int songId) _artworkUriLoader;
  final Future<Uri?> Function(int songId) _artworkUriPrefetcher;
  final Uri? Function(int songId) _artworkUriPeek;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  AudioPlayer? _player;
  SystemMediaSnapshot? _snapshot;
  Future<void> Function()? _onPlay;
  Future<void> Function()? _onPause;
  Future<void> Function()? _onNext;
  Future<void> Function()? _onPrevious;
  Future<void> Function(Duration position)? _onSeek;
  void Function(bool enabled)? _onSetShuffle;
  void Function(PlaybackRepeatMode mode)? _onSetRepeat;
  String? _mediaKey;
  List<String> _queueKeys = const [];
  int _artworkRequest = 0;
  bool _notificationStopped = false;

  SystemMediaHandler({
    Future<Uri?> Function(int songId)? artworkUriLoader,
    Future<Uri?> Function(int songId)? artworkUriPrefetcher,
    Uri? Function(int songId)? artworkUriPeek,
  }) : _artworkUriLoader =
           artworkUriLoader ??
           ArtworkPaletteService.shared.loadSystemArtworkUri,
       _artworkUriPrefetcher =
           artworkUriPrefetcher ??
           artworkUriLoader ??
           ArtworkPaletteService.shared.preloadSystemArtworkUri,
       _artworkUriPeek =
           artworkUriPeek ?? ArtworkPaletteService.shared.peekSystemArtworkUri;

  void attach({
    required AudioPlayer player,
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
    required Future<void> Function(Duration position) onSeek,
    required void Function(bool enabled) onSetShuffle,
    required void Function(PlaybackRepeatMode mode) onSetRepeat,
  }) {
    detach();
    _player = player;
    _onPlay = onPlay;
    _onPause = onPause;
    _onNext = onNext;
    _onPrevious = onPrevious;
    _onSeek = onSeek;
    _onSetShuffle = onSetShuffle;
    _onSetRepeat = onSetRepeat;
    _subscriptions.add(player.playerStateStream.listen((_) => _broadcast()));
    _subscriptions.add(player.playbackEventStream.listen((_) => _broadcast()));
    _broadcast();
  }

  void synchronize(SystemMediaSnapshot snapshot) {
    final previousKey = _mediaKey;
    final previousQueueKeys = _queueKeys;
    final previousRepeatMode = _snapshot?.repeatMode;
    _snapshot = snapshot;
    final song = snapshot.currentSong;
    final nextKey = song == null ? null : _songKey(song);
    if (nextKey != previousKey) {
      _notificationStopped = false;
      _mediaKey = nextKey;
      _updateMediaItem(song);
    }
    _updateQueue(snapshot);
    if (nextKey != previousKey ||
        !identical(previousQueueKeys, _queueKeys) ||
        previousRepeatMode != snapshot.repeatMode) {
      _prefetchNearby(snapshot);
    }
    _broadcast();
  }

  void detach() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _player = null;
    _snapshot = null;
    _onPlay = null;
    _onPause = null;
    _onNext = null;
    _onPrevious = null;
    _onSeek = null;
    _onSetShuffle = null;
    _onSetRepeat = null;
    _mediaKey = null;
    _queueKeys = const [];
    _artworkRequest++;
    _notificationStopped = false;
    mediaItem.add(null);
    queue.add(const []);
    playbackState.add(PlaybackState());
  }

  @override
  Future<void> play() async {
    _notificationStopped = false;
    await _onPlay?.call();
  }

  @override
  Future<void> pause() async {
    await _onPause?.call();
  }

  @override
  Future<void> skipToNext() async {
    if (_snapshot?.canGoNext == true) await _onNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_snapshot?.currentSong != null) await _onPrevious?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    await _onSeek?.call(position);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _onSetShuffle?.call(shuffleMode != AudioServiceShuffleMode.none);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _onSetRepeat?.call(switch (repeatMode) {
      AudioServiceRepeatMode.none => PlaybackRepeatMode.off,
      AudioServiceRepeatMode.one => PlaybackRepeatMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => PlaybackRepeatMode.all,
    });
  }

  @override
  Future<void> stop() async {
    await _onPause?.call();
    _notificationStopped = true;
    await super.stop();
  }

  void _updateMediaItem(Song? song) {
    final request = ++_artworkRequest;
    if (song == null) {
      mediaItem.add(null);
      return;
    }
    final cachedArtUri = _artworkUriPeek(song.id);
    final item = _mediaItem(song).copyWith(artUri: cachedArtUri);
    mediaItem.add(item);
    if (cachedArtUri != null) return;
    unawaited(
      _artworkUriLoader(song.id).then<void>((artUri) {
        if (request == _artworkRequest &&
            _mediaKey == _songKey(song) &&
            artUri != null) {
          mediaItem.add(item.copyWith(artUri: artUri));
        }
      }, onError: (_, _) {}),
    );
  }

  void _prefetchNearby(SystemMediaSnapshot snapshot) {
    final songs = snapshot.sequence;
    if (songs.length < 2 || snapshot.currentSong == null) return;
    final indices = <int>[
      snapshot.currentIndex + 1,
      snapshot.currentIndex + 2,
      snapshot.currentIndex - 1,
    ];
    final seen = <int>{snapshot.currentSong!.id};
    for (final rawIndex in indices) {
      var index = rawIndex;
      if (index < 0 || index >= songs.length) {
        if (snapshot.repeatMode != PlaybackRepeatMode.all) continue;
        index = (index + songs.length) % songs.length;
      }
      final songId = songs[index].id;
      if (!seen.add(songId) || _artworkUriPeek(songId) != null) continue;
      unawaited(
        _artworkUriPrefetcher(songId).then<void>((_) {}, onError: (_, _) {}),
      );
    }
  }

  void _updateQueue(SystemMediaSnapshot snapshot) {
    final keys = snapshot.sequence.map(_songKey).toList(growable: false);
    if (_sameKeys(keys, _queueKeys)) return;
    _queueKeys = keys;
    queue.add(snapshot.sequence.map(_mediaItem).toList(growable: false));
  }

  void _broadcast() {
    final player = _player;
    final snapshot = _snapshot;
    final song = snapshot?.currentSong;
    if (player == null || snapshot == null || song == null) {
      if (playbackState.value.processingState != AudioProcessingState.idle) {
        playbackState.add(PlaybackState());
      }
      return;
    }
    if (_notificationStopped) return;
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      if (player.playing || snapshot.isLoadingTrack)
        MediaControl.pause
      else
        MediaControl.play,
      if (snapshot.canGoNext) MediaControl.skipToNext,
    ];
    final hasError = snapshot.playbackError != null;
    playbackState.add(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: List<int>.generate(
          controls.length,
          (index) => index,
        ),
        systemActions: const {MediaAction.seek},
        processingState: hasError
            ? AudioProcessingState.error
            : snapshot.isLoadingTrack
            ? AudioProcessingState.loading
            : _processingState(player.processingState),
        playing:
            !hasError &&
            player.playing &&
            player.processingState != ProcessingState.completed,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        errorCode: hasError ? 1 : null,
        errorMessage: snapshot.playbackError,
        repeatMode: switch (snapshot.repeatMode) {
          PlaybackRepeatMode.off => AudioServiceRepeatMode.none,
          PlaybackRepeatMode.one => AudioServiceRepeatMode.one,
          PlaybackRepeatMode.all => AudioServiceRepeatMode.all,
        },
        shuffleMode: snapshot.shuffleEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        queueIndex: snapshot.currentIndex,
      ),
    );
  }

  MediaItem _mediaItem(Song song) => MediaItem(
    id: _songKey(song),
    title: song.title,
    artist: song.artist,
    album: song.album,
    duration: Duration(milliseconds: song.durationMs),
  );

  String _songKey(Song song) => '${song.id}:${song.path}';

  bool _sameKeys(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  AudioProcessingState _processingState(ProcessingState state) =>
      switch (state) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      };
}
