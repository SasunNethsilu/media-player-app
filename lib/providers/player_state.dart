import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

import '../models/playback_sequence.dart';
import '../models/song.dart';
import '../services/library_scanner.dart';
import '../services/playback_session_store.dart';
import '../services/system_media_handler.dart';
import 'library_collections.dart';
import 'app_settings.dart';

export '../models/playback_sequence.dart' show PlaybackRepeatMode;

class PlayerState extends ChangeNotifier {
  final AudioPlayer _player;
  final PlaybackSequence _sequence;
  final SystemMediaHandler? systemMediaHandler;
  PlaybackSessionStore? sessionStore;
  final Future<List<Song>> Function() _scanSongs;
  final Duration positionPersistenceInterval;
  final Duration sequencePersistenceDebounce;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<Song> _songs = [];
  bool _isLoadingLibrary = false;
  String? _libraryError;
  bool _isDisposed = false;
  final LibraryCollections collections;
  final AppSettings? appSettings;
  String? _activePlaylistId;
  Future<void> _pendingPlayback = Future<void>.value();
  int _pendingTransports = 0;
  int _request = 0;
  int _selection = 0;
  int _sourceRevision = 0;
  Object? _loadedEntry;
  bool _isLoadingTrack = false;
  bool _exhausted = false;
  String? _playbackError;
  ProcessingState? _lastProcessingState;
  Timer? _positionPersistenceTimer;
  Timer? _sequencePersistenceTimer;
  String? _sequenceRevision;
  bool _sequenceDirty = false;
  bool _removeLegacyOnNextSequenceSave = false;
  bool _sessionRestoreAttempted = false;
  bool _sessionReady = false;

  PlayerState({
    required this.collections,
    this.appSettings,
    AudioPlayer? audioPlayer,
    Random? random,
    this.sessionStore,
    Future<List<Song>> Function()? scanSongs,
    this.positionPersistenceInterval = const Duration(seconds: 5),
    this.sequencePersistenceDebounce = const Duration(milliseconds: 350),
    this.systemMediaHandler,
  }) : _player = audioPlayer ?? AudioPlayer(),
       _sequence = PlaybackSequence(random: random),
       _scanSongs = scanSongs ?? LibraryScanner().scanSongs {
    _subscriptions.add(
      _player.playerStateStream.listen((_) {
        if (!_isLoadingTrack) _notify();
      }),
    );
    systemMediaHandler?.attach(
      player: _player,
      onPlay: _playFromSystem,
      onPause: _pauseFromSystem,
      onNext: playNext,
      onPrevious: playPrevious,
      onSeek: seek,
      onSetShuffle: setShuffleEnabled,
      onSetRepeat: setRepeatMode,
    );
    _syncSystemMedia();
    _subscriptions.add(_player.positionStream.listen(_positionChanged));
    _subscriptions.add(
      _player.playbackEventStream.listen(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (canSeek) _handleAsyncError(error, _sourceRevision);
        },
      ),
    );
    _subscriptions.add(
      _player.processingStateStream.listen((state) {
        final completed =
            state == ProcessingState.completed &&
            _lastProcessingState != ProcessingState.completed;
        _lastProcessingState = state;
        if (!completed || _pendingTransports > 0 || !canSeek || _exhausted) {
          return;
        }
        final request = _request;
        final source = _sourceRevision;
        unawaited(
          _runPlayback(() async {
            if (!_isCurrent(request) || source != _sourceRevision || !canSeek) {
              return;
            }
            if (_sequence.next(automatic: true)) {
              if (repeatMode == PlaybackRepeatMode.one) {
                await _restart(request);
              } else {
                await _loadCurrent(request);
                _scheduleCheckpointSave();
              }
            } else {
              _exhausted = true;
              await _player.pause();
              if (_isCurrent(request)) {
                _scheduleCheckpointSave();
                _notify();
              }
            }
          }, request),
        );
      }),
    );
  }

  List<Song> get songs => List.unmodifiable(_songs);
  List<Song> get queue => _sequence.queue;
  List<Object> get queueKeys => _sequence.queueKeys;
  Song? get currentSong => _sequence.current;
  AudioPlayer get player => _player;
  bool get isPlaying => playing;
  bool get playPauseShowsPause => playing || isLoadingTrack;
  bool get playing =>
      canSeek &&
      _player.playing &&
      _player.processingState != ProcessingState.completed;
  bool get isLoadingLibrary => _isLoadingLibrary;
  String? get libraryError => _libraryError;
  String? get activePlaylistId => _activePlaylistId;
  bool get shuffleEnabled => _sequence.shuffleEnabled;
  PlaybackRepeatMode get repeatMode => _sequence.repeatMode;
  bool get canGoNext => _sequence.canGoNext;
  bool get isLoadingTrack => _isLoadingTrack;
  String? get playbackError => _playbackError;
  bool get canSeek =>
      !_isDisposed &&
      !_isLoadingTrack &&
      _playbackError == null &&
      _loadedEntry != null &&
      identical(_loadedEntry, _sequence.currentKey);

  bool _isCurrent(int request) => !_isDisposed && request == _request;

  void _notify() {
    if (!_isDisposed) {
      _syncSystemMedia();
      notifyListeners();
    }
  }

  void _syncSystemMedia() {
    final snapshot = _sequence.snapshot;
    systemMediaHandler?.synchronize(
      SystemMediaSnapshot(
        sequence: snapshot?.songs ?? const [],
        currentIndex: snapshot?.currentIndex ?? -1,
        canGoNext: canGoNext,
        shuffleEnabled: shuffleEnabled,
        repeatMode: repeatMode,
        isLoadingTrack: isLoadingTrack,
        playbackError: playbackError,
      ),
    );
  }

  SavedPlaybackSequence? _sequenceSnapshot(String revision) {
    final snapshot = _sequence.snapshot;
    if (snapshot == null) return null;
    return SavedPlaybackSequence.capture(
      revision: revision,
      sequence: snapshot,
    );
  }

  SavedPlaybackCheckpoint? _checkpointSnapshot(String? revision) {
    if (revision == null || currentSong == null) return null;
    return SavedPlaybackCheckpoint(
      revision: revision,
      currentIndex: _sequence.currentIndex,
      positionMs: _player.position.inMilliseconds,
      shuffleEnabled: shuffleEnabled,
      repeatMode: repeatMode,
      playlistId: _activePlaylistId,
    );
  }

  void _positionChanged(Duration position) {
    if (!_sessionReady || _isDisposed || currentSong == null) return;
    _positionPersistenceTimer ??= Timer(positionPersistenceInterval, () {
      _positionPersistenceTimer = null;
      _persistCheckpoint();
    });
  }

  void _persistCheckpoint() {
    if (!_sessionReady || _isDisposed || _sequenceDirty) return;
    final checkpoint = _checkpointSnapshot(_sequenceRevision);
    if (checkpoint != null) {
      unawaited(sessionStore?.saveCheckpoint(checkpoint));
    }
  }

  void _scheduleCheckpointSave() {
    if (!_sessionReady || _isDisposed) return;
    _positionPersistenceTimer?.cancel();
    _positionPersistenceTimer = null;
    _persistCheckpoint();
  }

  void _scheduleSequenceSave({bool immediate = false}) {
    if (!_sessionReady || _isDisposed || currentSong == null) return;
    _sequenceDirty = true;
    _positionPersistenceTimer?.cancel();
    _positionPersistenceTimer = null;
    _sequencePersistenceTimer?.cancel();
    if (immediate) {
      _persistSequence();
    } else {
      _sequencePersistenceTimer = Timer(
        sequencePersistenceDebounce,
        _persistSequence,
      );
    }
  }

  void _persistSequence() {
    if (!_sessionReady || _isDisposed || currentSong == null) return;
    _sequencePersistenceTimer = null;
    final store = sessionStore;
    if (store == null) return;
    final previousRevision = _sequenceRevision;
    final revision = store.createRevision();
    final sequence = _sequenceSnapshot(revision);
    final checkpoint = _checkpointSnapshot(revision);
    if (sequence == null || checkpoint == null) return;
    _sequenceDirty = false;
    _sequenceRevision = revision;
    final removeLegacy = _removeLegacyOnNextSequenceSave;
    _removeLegacyOnNextSequenceSave = false;
    unawaited(
      store.saveSequenceAndCheckpoint(
        sequence: sequence,
        checkpoint: checkpoint,
        previousRevision: previousRevision,
        removeLegacy: removeLegacy,
      ),
    );
  }

  Future<void> _runPlayback(Future<void> Function() action, int request) {
    final operation = _pendingPlayback.then((_) async {
      if (_isDisposed) return;
      try {
        await action();
      } catch (error) {
        await _failPlayback(error, request);
      }
    });
    _pendingPlayback = operation;
    return operation;
  }

  Future<void> _transport(
    Future<void> Function(int) action, {
    bool newSelection = false,
  }) {
    if (_isDisposed) return Future<void>.value();
    if (newSelection) _selection++;
    final selection = _selection;
    final request = ++_request;
    _pendingTransports++;
    return _runPlayback(() async {
      try {
        if (selection == _selection) await action(request);
      } finally {
        _pendingTransports--;
      }
    }, request);
  }

  Future<void> _failPlayback(Object error, int request) async {
    if (!_isCurrent(request)) return;
    debugPrint('Playback failed: $error');
    _playbackError =
        'Could not play this track. It may be missing or unreadable. '
        'Press Play to retry or choose another song.';
    _isLoadingTrack = false;
    _loadedEntry = null;
    _exhausted = false;
    _notify();
    try {
      await _player.stop();
    } catch (stopError) {
      debugPrint('Stopping failed playback: $stopError');
    }
    if (_isCurrent(request)) _notify();
  }

  void _handleAsyncError(Object error, int source) {
    if (_isDisposed || source != _sourceRevision || _playbackError != null) {
      return;
    }
    final request = _request;
    unawaited(
      _runPlayback(() async {
        if (_isCurrent(request) &&
            source == _sourceRevision &&
            _playbackError == null) {
          await _failPlayback(error, request);
        }
      }, request),
    );
  }

  Future<void> loadLibrary() async {
    if (_isLoadingLibrary || _isDisposed) return;

    _isLoadingLibrary = true;
    _libraryError = null;
    notifyListeners();

    try {
      final songs = await _scanSongs();

      if (_isDisposed) return;

      _songs = songs;
      await _restoreSessionAfterLibrary();
    } on LibraryPermissionDenied {
      if (_isDisposed) return;

      _libraryError =
          'Audio access is needed to show your music. '
          'Grant permission when prompted, or enable it in app settings.';
    } catch (error, stackTrace) {
      if (_isDisposed) return;

      _libraryError = 'Could not load your music. Please try again.';
      debugPrint('Library scan failed: $error\n$stackTrace');
    } finally {
      _isLoadingLibrary = false;

      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _restoreSessionAfterLibrary() async {
    if (_sessionRestoreAttempted || _isDisposed) return;
    _sessionRestoreAttempted = true;
    if (appSettings?.restorePlaybackSession == false) {
      _sessionReady = true;
      return;
    }
    final store = sessionStore ??= PlaybackSessionStore();
    final saved = await store.load();
    if (_isDisposed) return;
    final restored = saved?.reconcile(_songs);
    if (restored == null || !_sequence.restore(restored.sequence)) {
      _sessionReady = true;
      return;
    }

    _activePlaylistId =
        restored.playlistId != null &&
            collections.playlistById(restored.playlistId!) != null
        ? restored.playlistId
        : null;
    _sequenceRevision = restored.revision;
    _removeLegacyOnNextSequenceSave = restored.requiresSequenceRewrite;
    _selection++;
    final request = ++_request;
    var loaded = false;
    try {
      await _loadRestoredCurrent(request, restored.position);
      loaded = _isCurrent(request) && canSeek;
    } catch (error) {
      await _failPlayback(error, request);
    } finally {
      if (!_isDisposed) {
        _sessionReady = true;
        if (loaded) {
          if (restored.requiresSequenceRewrite) {
            _scheduleSequenceSave(immediate: true);
          } else {
            _scheduleCheckpointSave();
          }
        }
      }
    }
  }

  Future<void> _loadRestoredCurrent(int request, Duration position) async {
    if (!_isCurrent(request)) return;
    final song = currentSong;
    final entry = _sequence.currentKey;
    if (song == null) return;
    _isLoadingTrack = true;
    _playbackError = null;
    _loadedEntry = null;
    _exhausted = false;
    _sourceRevision++;
    await _player.setAudioSource(
      AudioSource.uri(
        Uri.file(song.path),
        tag: MediaItem(
          id: song.id.toString(),
          title: song.title,
          artist: song.artist,
          album: song.album,
          duration: Duration(milliseconds: song.durationMs),
        ),
      ),
      initialPosition: position,
    );
    if (!_isCurrent(request)) return;
    if (_player.playing) await _player.pause();
    if (!_isCurrent(request)) return;
    _loadedEntry = entry;
    _isLoadingTrack = false;
    _notify();
  }

  void _resume(int request) {
    if (!_isCurrent(request) || !canSeek) return;
    final source = _sourceRevision;
    unawaited(
      _player.play().catchError((Object error, StackTrace stack) {
        _handleAsyncError(error, source);
      }),
    );
  }

  Future<void> _restart(int request, {bool resume = true}) async {
    if (_isDisposed || (!_isCurrent(request) && resume)) return;
    if (!canSeek) {
      await _loadCurrent(request);
      return;
    }
    await _player.seek(Duration.zero);
    if (!_isCurrent(request)) return;
    _exhausted = false;
    if (resume) _resume(request);
    _scheduleCheckpointSave();
    _notify();
  }

  Future<void> _loadCurrent(int request) async {
    if (!_isCurrent(request)) return;
    final song = currentSong;
    final entry = _sequence.currentKey;
    if (song == null) return;
    _isLoadingTrack = true;
    _playbackError = null;
    _loadedEntry = null;
    _exhausted = false;
    _notify();
    if (_player.playing) await _player.pause();
    if (!_isCurrent(request)) return;
    _sourceRevision++;
    await _player.setAudioSource(
      AudioSource.uri(
        Uri.file(song.path),
        tag: MediaItem(
          id: song.id.toString(),
          title: song.title,
          artist: song.artist,
          album: song.album,
          duration: Duration(milliseconds: song.durationMs),
        ),
      ),
    );
    if (_isDisposed) return;
    _loadedEntry = entry;
    if (!_isCurrent(request)) return;
    _isLoadingTrack = false;
    _resume(request);
    collections.recordPlayed(song.id);
    _notify();
  }

  Future<void> play(Song song) => playFromLibrary(song, [song]);

  Future<void> playFromLibrary(
    Song song,
    List<Song> fromList, {
    String? playlistId,
    bool? shuffle,
  }) {
    final snapshot = List<Song>.of(fromList);
    if (!snapshot.any((item) => item.id == song.id)) {
      return Future<void>.value();
    }
    return _transport((request) async {
      if (!_sequence.start(song, snapshot, shuffle: shuffle)) return;
      _activePlaylistId = playlistId;
      await _loadCurrent(request);
      _scheduleSequenceSave(immediate: true);
    }, newSelection: true);
  }

  Future<void> playNext() => _transport((request) async {
    if (_sequence.next()) {
      await _loadCurrent(request);
      _scheduleCheckpointSave();
    } else if (_isLoadingTrack && _isCurrent(request)) {
      await _finishPendingLoad(request);
    }
  });

  Future<void> _finishPendingLoad(int request) async {
    if (!identical(_loadedEntry, _sequence.currentKey) ||
        _loadedEntry == null) {
      await _loadCurrent(request);
      _scheduleCheckpointSave();
    } else {
      _isLoadingTrack = false;
      _resume(request);
      collections.recordPlayed(currentSong!.id);
      _scheduleCheckpointSave();
      _notify();
    }
  }

  Future<void> playPrevious() => _transport((request) async {
    if (currentSong == null) return;
    if ((canSeek && _player.position > const Duration(seconds: 3)) ||
        !_sequence.previous()) {
      await _restart(request, resume: false);
      return;
    }
    await _loadCurrent(request);
    _scheduleCheckpointSave();
  });

  Future<void> seek(Duration position) {
    if (!canSeek) return Future<void>.value();
    final entry = _sequence.currentKey;
    return _transport((request) async {
      if (!_isCurrent(request) ||
          !canSeek ||
          !identical(entry, _sequence.currentKey)) {
        return;
      }
      await _player.seek(position);
      if (!_isCurrent(request)) return;
      _exhausted = false;
      _scheduleCheckpointSave();
      _notify();
    });
  }

  void toggleShuffle() {
    setShuffleEnabled(!shuffleEnabled);
  }

  void setShuffleEnabled(bool enabled) {
    if (_isDisposed || shuffleEnabled == enabled) return;
    _sequence.setShuffle(enabled);
    _scheduleSequenceSave();
    _notify();
  }

  void setRepeatMode(PlaybackRepeatMode mode) {
    if (_isDisposed) return;
    _sequence.repeatMode = mode;
    _scheduleCheckpointSave();
    _notify();
  }

  void cycleRepeatMode() {
    setRepeatMode(
      PlaybackRepeatMode.values[(repeatMode.index + 1) %
          PlaybackRepeatMode.values.length],
    );
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (_isDisposed) return;
    _sequence.reorder(oldIndex, newIndex);
    _scheduleSequenceSave();
    _notify();
  }

  void removeFromQueue(Song song) {
    if (_isDisposed) return;
    _sequence.remove(song);
    _scheduleSequenceSave();
    _notify();
  }

  void clearUpcomingQueue() {
    if (_isDisposed) return;
    _sequence.clearUpcoming();
    _scheduleSequenceSave();
    _notify();
  }

  void removeQueueEntry(Object key) {
    if (_isDisposed) return;
    _sequence.removeEntry(key);
    _scheduleSequenceSave();
    _notify();
  }

  Future<void> togglePlayPause() {
    final pause = playing || isLoadingTrack;
    return _transport((request) async {
      if (!_isCurrent(request) || currentSong == null) return;
      if (pause) {
        await _player.pause();
        if (!_isCurrent(request)) return;
        _isLoadingTrack = false;
      } else if (_playbackError != null || !canSeek) {
        await _loadCurrent(request);
      } else if (_exhausted ||
          _player.processingState == ProcessingState.completed) {
        if (queue.isNotEmpty && _sequence.next()) {
          await _loadCurrent(request);
        } else {
          await _restart(request);
        }
      } else {
        _resume(request);
      }
      if (_isCurrent(request)) {
        _scheduleCheckpointSave();
        _notify();
      }
    });
  }

  Future<void> _playFromSystem() {
    if (_isDisposed || playing || isLoadingTrack) return Future<void>.value();
    return togglePlayPause();
  }

  Future<void> _pauseFromSystem() {
    if (_isDisposed || (!playing && !isLoadingTrack)) {
      return Future<void>.value();
    }
    return togglePlayPause();
  }

  Future<void> _enqueue(Song song, {required bool next}) {
    if (_isDisposed) return Future<void>.value();
    if (currentSong == null && _pendingTransports == 0) {
      return playFromLibrary(song, [song]);
    }
    final selection = _selection;
    final request = _request;
    return _runPlayback(() async {
      if (selection != _selection) return;
      _sequence.enqueue(song, next: next);
      _scheduleSequenceSave();
      _notify();
    }, request);
  }

  Future<void> enqueueNext(Song song) => _enqueue(song, next: true);
  Future<void> enqueueLast(Song song) => _enqueue(song, next: false);

  @override
  void dispose() {
    if (_isDisposed) return;
    _positionPersistenceTimer?.cancel();
    _positionPersistenceTimer = null;
    _sequencePersistenceTimer?.cancel();
    _sequencePersistenceTimer = null;
    if (_sessionReady && currentSong != null) {
      if (_sequenceDirty || _sequenceRevision == null) {
        _persistSequence();
      } else {
        _persistCheckpoint();
      }
    }
    _isDisposed = true;
    _request++;
    systemMediaHandler?.detach();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(
      _player.dispose().catchError((Object error, StackTrace stack) {
        debugPrint('Audio disposal failed: $error');
      }),
    );
    super.dispose();
  }
}
