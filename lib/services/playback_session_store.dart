import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playback_sequence.dart';
import '../models/song.dart';

class SavedTrackReference {
  final int id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final int durationMs;

  const SavedTrackReference({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
  });

  factory SavedTrackReference.fromSong(Song song) {
    return SavedTrackReference(
      id: song.id,
      path: song.path,
      title: song.title,
      artist: song.artist,
      album: song.album,
      durationMs: song.durationMs,
    );
  }

  factory SavedTrackReference.fromJson(Map<String, dynamic> json) {
    return SavedTrackReference(
      id: (json['id'] as num).toInt(),
      path: json['path'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String,
      durationMs: (json['durationMs'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': durationMs,
  };
}

class SavedPlaybackEntry {
  final SavedTrackReference track;
  final int order;

  const SavedPlaybackEntry({required this.track, required this.order});

  factory SavedPlaybackEntry.fromJson(Map<String, dynamic> json) {
    return SavedPlaybackEntry(
      track: SavedTrackReference.fromJson(
        Map<String, dynamic>.from(json['track'] as Map),
      ),
      order: (json['order'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {'track': track.toJson(), 'order': order};
}

class SavedPlaybackSequence {
  final String revision;
  final List<SavedPlaybackEntry> entries;

  SavedPlaybackSequence({
    required this.revision,
    required Iterable<SavedPlaybackEntry> entries,
  }) : entries = List.unmodifiable(entries);

  factory SavedPlaybackSequence.capture({
    required String revision,
    required PlaybackSequenceSnapshot sequence,
  }) {
    return SavedPlaybackSequence(
      revision: revision,
      entries: [
        for (var i = 0; i < sequence.songs.length; i++)
          SavedPlaybackEntry(
            track: SavedTrackReference.fromSong(sequence.songs[i]),
            order: sequence.orders[i],
          ),
      ],
    );
  }

  factory SavedPlaybackSequence.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 2) throw const FormatException();
    return SavedPlaybackSequence(
      revision: json['revision'] as String,
      entries: (json['entries'] as List).map(
        (entry) => SavedPlaybackEntry.fromJson(
          Map<String, dynamic>.from(entry as Map),
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'revision': revision,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };
}

class SavedPlaybackCheckpoint {
  final String revision;
  final int currentIndex;
  final int positionMs;
  final bool shuffleEnabled;
  final PlaybackRepeatMode repeatMode;
  final String? playlistId;

  const SavedPlaybackCheckpoint({
    required this.revision,
    required this.currentIndex,
    required this.positionMs,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.playlistId,
  });

  factory SavedPlaybackCheckpoint.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 2) throw const FormatException();
    return SavedPlaybackCheckpoint(
      revision: json['revision'] as String,
      currentIndex: (json['currentIndex'] as num).toInt(),
      positionMs: (json['positionMs'] as num).toInt(),
      shuffleEnabled: json['shuffleEnabled'] as bool,
      repeatMode: PlaybackRepeatMode.values.byName(
        json['repeatMode'] as String,
      ),
      playlistId: json['playlistId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'revision': revision,
    'currentIndex': currentIndex,
    'positionMs': positionMs,
    'shuffleEnabled': shuffleEnabled,
    'repeatMode': repeatMode.name,
    'playlistId': playlistId,
  };
}

class SavedPlaybackSession {
  final List<SavedPlaybackEntry> entries;
  final int currentIndex;
  final int positionMs;
  final bool shuffleEnabled;
  final PlaybackRepeatMode repeatMode;
  final String? playlistId;
  final String? revision;
  final bool isLegacy;

  SavedPlaybackSession({
    required Iterable<SavedPlaybackEntry> entries,
    required this.currentIndex,
    required this.positionMs,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.playlistId,
    this.revision,
    this.isLegacy = false,
  }) : entries = List.unmodifiable(entries);

  factory SavedPlaybackSession.capture({
    required PlaybackSequenceSnapshot sequence,
    required Duration position,
    required String? playlistId,
    String? revision,
  }) {
    return SavedPlaybackSession(
      entries: SavedPlaybackSequence.capture(
        revision: revision ?? '',
        sequence: sequence,
      ).entries,
      currentIndex: sequence.currentIndex,
      positionMs: position.inMilliseconds,
      shuffleEnabled: sequence.shuffleEnabled,
      repeatMode: sequence.repeatMode,
      playlistId: playlistId,
      revision: revision,
    );
  }

  factory SavedPlaybackSession.fromLegacyJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException();
    return SavedPlaybackSession(
      entries: (json['entries'] as List).map(
        (entry) => SavedPlaybackEntry.fromJson(
          Map<String, dynamic>.from(entry as Map),
        ),
      ),
      currentIndex: (json['currentIndex'] as num).toInt(),
      positionMs: (json['positionMs'] as num).toInt(),
      shuffleEnabled: json['shuffleEnabled'] as bool,
      repeatMode: PlaybackRepeatMode.values.byName(
        json['repeatMode'] as String,
      ),
      playlistId: json['playlistId'] as String?,
      isLegacy: true,
    );
  }

  factory SavedPlaybackSession.fromSplit({
    required SavedPlaybackSequence sequence,
    required SavedPlaybackCheckpoint checkpoint,
  }) {
    if (sequence.revision != checkpoint.revision) {
      throw const FormatException();
    }
    return SavedPlaybackSession(
      entries: sequence.entries,
      currentIndex: checkpoint.currentIndex,
      positionMs: checkpoint.positionMs,
      shuffleEnabled: checkpoint.shuffleEnabled,
      repeatMode: checkpoint.repeatMode,
      playlistId: checkpoint.playlistId,
      revision: sequence.revision,
    );
  }

  ReconciledPlaybackSession? reconcile(List<Song> library) {
    if (entries.isEmpty || currentIndex < 0 || currentIndex >= entries.length) {
      return null;
    }
    final resolver = _SongResolver(library);
    final resolved = <({int savedIndex, Song song, int order})>[];
    var identityChanged = false;
    for (var i = 0; i < entries.length; i++) {
      final song = resolver.resolve(entries[i].track);
      if (song != null) {
        identityChanged =
            identityChanged || _identityChanged(entries[i].track, song);
        resolved.add((savedIndex: i, song: song, order: entries[i].order));
      }
    }
    if (resolved.isEmpty) return null;

    var restoredIndex = resolved.indexWhere(
      (entry) => entry.savedIndex == currentIndex,
    );
    final keptCurrent = restoredIndex >= 0;
    if (!keptCurrent) {
      restoredIndex = resolved.indexWhere(
        (entry) => entry.savedIndex > currentIndex,
      );
      if (restoredIndex < 0) restoredIndex = resolved.length - 1;
    }

    final current = resolved[restoredIndex].song;
    var restoredPosition = keptCurrent ? positionMs.clamp(0, 1 << 53) : 0;
    if (current.durationMs > 0 && restoredPosition >= current.durationMs) {
      restoredPosition = 0;
    }

    return ReconciledPlaybackSession(
      sequence: PlaybackSequenceSnapshot(
        songs: resolved.map((entry) => entry.song),
        orders: resolved.map((entry) => entry.order),
        currentIndex: restoredIndex,
        shuffleEnabled: shuffleEnabled,
        repeatMode: repeatMode,
      ),
      position: Duration(milliseconds: restoredPosition),
      playlistId: playlistId,
      revision: revision,
      requiresSequenceRewrite:
          isLegacy || resolved.length != entries.length || identityChanged,
    );
  }

  bool _identityChanged(SavedTrackReference saved, Song song) {
    return saved.id != song.id ||
        saved.path != song.path ||
        saved.title != song.title ||
        saved.artist != song.artist ||
        saved.album != song.album ||
        saved.durationMs != song.durationMs;
  }
}

class _SongResolver {
  final Map<String, Song> _byPath = {};
  final Map<int, List<Song>> _byId = {};
  final Map<String, List<Song>> _byMetadata = {};

  _SongResolver(List<Song> library) {
    for (final song in library) {
      _byPath.putIfAbsent(song.path, () => song);
      _byId.putIfAbsent(song.id, () => []).add(song);
      _byMetadata.putIfAbsent(_metadataKeyForSong(song), () => []).add(song);
    }
  }

  Song? resolve(SavedTrackReference saved) {
    final pathMatch = _byPath[saved.path];
    if (pathMatch != null) return pathMatch;

    final idMatches = _byId[saved.id] ?? const [];
    if (idMatches.length == 1 && _durationMatches(saved, idMatches.single)) {
      final match = idMatches.single;
      if (_metadataKeyForSaved(saved) == _metadataKeyForSong(match)) {
        return match;
      }
    }

    final metadataMatches =
        (_byMetadata[_metadataKeyForSaved(saved)] ?? const [])
            .where((song) => _durationMatches(saved, song))
            .toList();
    return metadataMatches.length == 1 ? metadataMatches.single : null;
  }

  bool _durationMatches(SavedTrackReference saved, Song song) =>
      (saved.durationMs - song.durationMs).abs() <= 2000;

  static String _metadataKeyForSaved(SavedTrackReference saved) =>
      '${_normalise(saved.title)}\u0000${_normalise(saved.artist)}\u0000'
      '${_normalise(saved.album)}';

  static String _metadataKeyForSong(Song song) =>
      '${_normalise(song.title)}\u0000${_normalise(song.artist)}\u0000'
      '${_normalise(song.album)}';

  static String _normalise(String value) => value.trim().toLowerCase();
}

class ReconciledPlaybackSession {
  final PlaybackSequenceSnapshot sequence;
  final Duration position;
  final String? playlistId;
  final String? revision;
  final bool requiresSequenceRewrite;

  const ReconciledPlaybackSession({
    required this.sequence,
    required this.position,
    required this.playlistId,
    required this.revision,
    required this.requiresSequenceRewrite,
  });
}

class PlaybackSessionStore {
  static const storageKey = 'local_playback_session_v1';
  static const checkpointKey = 'local_playback_checkpoint_v2';
  static const sequenceKeyPrefix = 'local_playback_sequence_v2_';

  final SharedPreferencesAsync _preferences;
  final Set<String> _committedRevisions = {};
  Future<void> _pendingWrites = Future<void>.value();
  int _revisionCounter = 0;

  PlaybackSessionStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static String sequenceKey(String revision) => '$sequenceKeyPrefix$revision';

  String createRevision() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_revisionCounter++}';

  Future<SavedPlaybackSession?> load() async {
    final split = await _loadSplit();
    if (split != null) return split;
    return _loadLegacy();
  }

  Future<SavedPlaybackSession?> _loadSplit() async {
    try {
      final checkpointRaw = await _preferences.getString(checkpointKey);
      if (checkpointRaw == null) return null;
      final checkpoint = SavedPlaybackCheckpoint.fromJson(
        Map<String, dynamic>.from(jsonDecode(checkpointRaw) as Map),
      );
      final sequenceRaw = await _preferences.getString(
        sequenceKey(checkpoint.revision),
      );
      if (sequenceRaw == null) return null;
      final sequence = SavedPlaybackSequence.fromJson(
        Map<String, dynamic>.from(jsonDecode(sequenceRaw) as Map),
      );
      final session = SavedPlaybackSession.fromSplit(
        sequence: sequence,
        checkpoint: checkpoint,
      );
      _committedRevisions.add(sequence.revision);
      return session;
    } catch (error) {
      debugPrint('Playback session loading failed: $error');
      return null;
    }
  }

  Future<SavedPlaybackSession?> _loadLegacy() async {
    try {
      final raw = await _preferences.getString(storageKey);
      if (raw == null) return null;
      return SavedPlaybackSession.fromLegacyJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (error) {
      debugPrint('Playback session loading failed: $error');
      return null;
    }
  }

  Future<void> save(SavedPlaybackSession session) {
    final revision = session.revision ?? createRevision();
    return saveSequenceAndCheckpoint(
      sequence: SavedPlaybackSequence(
        revision: revision,
        entries: session.entries,
      ),
      checkpoint: SavedPlaybackCheckpoint(
        revision: revision,
        currentIndex: session.currentIndex,
        positionMs: session.positionMs,
        shuffleEnabled: session.shuffleEnabled,
        repeatMode: session.repeatMode,
        playlistId: session.playlistId,
      ),
      removeLegacy: session.isLegacy,
    );
  }

  Future<void> saveSequenceAndCheckpoint({
    required SavedPlaybackSequence sequence,
    required SavedPlaybackCheckpoint checkpoint,
    String? previousRevision,
    bool removeLegacy = false,
  }) {
    if (sequence.revision != checkpoint.revision) {
      return Future<void>.error(const FormatException());
    }
    final sequenceJson = jsonEncode(sequence.toJson());
    final checkpointJson = jsonEncode(checkpoint.toJson());
    _pendingWrites = _pendingWrites.then((_) async {
      try {
        await _preferences.setString(
          sequenceKey(sequence.revision),
          sequenceJson,
        );
        _committedRevisions.add(sequence.revision);
        await _preferences.setString(checkpointKey, checkpointJson);
        if (previousRevision != null && previousRevision != sequence.revision) {
          await _preferences.remove(sequenceKey(previousRevision));
          _committedRevisions.remove(previousRevision);
        }
        if (removeLegacy) await _preferences.remove(storageKey);
      } catch (error) {
        debugPrint('Playback session saving failed: $error');
      }
    });
    return _pendingWrites;
  }

  Future<void> saveCheckpoint(SavedPlaybackCheckpoint checkpoint) {
    final snapshot = jsonEncode(checkpoint.toJson());
    _pendingWrites = _pendingWrites.then((_) async {
      if (!_committedRevisions.contains(checkpoint.revision)) return;
      try {
        await _preferences.setString(checkpointKey, snapshot);
      } catch (error) {
        debugPrint('Playback checkpoint saving failed: $error');
      }
    });
    return _pendingWrites;
  }

  Future<void> flush() => _pendingWrites;
}
