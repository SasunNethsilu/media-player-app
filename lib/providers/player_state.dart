import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

import '../models/playback_sequence.dart';
import '../models/song.dart';
import '../services/library_scanner.dart';
import 'library_collections.dart';

export '../models/playback_sequence.dart' show PlaybackRepeatMode;

class PlayerState extends ChangeNotifier {
  final AudioPlayer _player;
  final PlaybackSequence _sequence;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<Song> _songs = [];
  bool _isLoadingLibrary = false;
  String? _libraryError;
  bool _isDisposed = false;
  final LibraryCollections collections;
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

  PlayerState({
    required this.collections,
    AudioPlayer? audioPlayer,
    Random? random,
  }) : _player = audioPlayer ?? AudioPlayer(),
       _sequence = PlaybackSequence(random: random) {
    _subscriptions.add(
      _player.playerStateStream.listen((_) {
        if (!_isLoadingTrack) _notify();
      }),
    );
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
              }
            } else {
              _exhausted = true;
              await _player.pause();
              if (_isCurrent(request)) _notify();
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
    if (!_isDisposed) notifyListeners();
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
      final songs = await LibraryScanner().scanSongs();

      if (_isDisposed) return;

      _songs = songs;
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
    }, newSelection: true);
  }

  Future<void> playNext() => _transport((request) async {
    if (_sequence.next()) {
      await _loadCurrent(request);
    } else if (_isLoadingTrack && _isCurrent(request)) {
      await _finishPendingLoad(request);
    }
  });

  Future<void> _finishPendingLoad(int request) async {
    if (!identical(_loadedEntry, _sequence.currentKey) ||
        _loadedEntry == null) {
      await _loadCurrent(request);
    } else {
      _isLoadingTrack = false;
      _resume(request);
      collections.recordPlayed(currentSong!.id);
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
      _notify();
    });
  }

  void toggleShuffle() {
    if (_isDisposed) return;
    _sequence.setShuffle(!shuffleEnabled);
    _notify();
  }

  void setRepeatMode(PlaybackRepeatMode mode) {
    if (_isDisposed) return;
    _sequence.repeatMode = mode;
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
    _notify();
  }

  void removeFromQueue(Song song) {
    if (_isDisposed) return;
    _sequence.remove(song);
    _notify();
  }

  void clearUpcomingQueue() {
    if (_isDisposed) return;
    _sequence.clearUpcoming();
    _notify();
  }

  void removeQueueEntry(Object key) {
    if (_isDisposed) return;
    _sequence.removeEntry(key);
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
      if (_isCurrent(request)) _notify();
    });
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
      _notify();
    }, request);
  }

  Future<void> enqueueNext(Song song) => _enqueue(song, next: true);
  Future<void> enqueueLast(Song song) => _enqueue(song, next: false);

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _request++;
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
