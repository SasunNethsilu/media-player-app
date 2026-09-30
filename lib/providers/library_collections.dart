import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

class LocalPlaylist {
  final String id;
  final String name;
  final List<int> songIds;

  LocalPlaylist({
    required this.id,
    required this.name,
    required Iterable<int> songIds,
  }) : songIds = List.unmodifiable(songIds);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'songs': songIds,
      };

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) {
    return LocalPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      songIds: (json['songs'] as List).cast<int>(),
    );
  }
}

class LibraryCollections extends ChangeNotifier {
  static const _storageKey = 'local_music_collections_v1';

  final SharedPreferencesAsync _prefs;

  LibraryCollections({SharedPreferencesAsync? preferences})
    : _prefs = preferences ?? SharedPreferencesAsync();

  List<int> _recentIds = [];
  final List<LocalPlaylist> _playlists = [];

  Future<void> _pendingWrites = Future<void>.value();

  bool _disposed = false;
  bool _canSave = true;
  int _idCounter = 0;
  String? _error;

  String? get error => _error;

  List<LocalPlaylist> get playlists => List.unmodifiable(_playlists);

  Future<void> load() async {
    try {
      final raw = await _prefs.getString(_storageKey);

      if (raw == null) return;

      final json = jsonDecode(raw) as Map<String, dynamic>;

      final recent = (json['recent'] as List).cast<int>();
      final playlists = (json['playlists'] as List)
          .map(
            (item) => LocalPlaylist.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();

      _recentIds = recent.toSet().take(12).toList();
      _playlists
        ..clear()
        ..addAll(playlists);
    } catch (error) {
      // Don't overwrite existing saved data if it couldn't be read.
      _canSave = false;
      _error = 'Saved collections could not be loaded. '
          'Changes will not be saved this session.';
      debugPrint('Collection loading failed: $error');
    }
  }

  List<Song> songsFor(
    Iterable<int> ids,
    List<Song> library,
  ) {
    final byId = {for (final song in library) song.id: song};

    // Missing/deleted files aren't displayed, but their IDs are retained.
    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  List<Song> recentSongs(List<Song> library) {
    return songsFor(_recentIds, library);
  }

  LocalPlaylist? playlistById(String id) {
    for (final playlist in _playlists) {
      if (playlist.id == id) return playlist;
    }

    return null;
  }

  void recordPlayed(int songId) {
    if (_recentIds.isNotEmpty && _recentIds.first == songId) return;

    _recentIds.remove(songId);
    _recentIds.insert(0, songId);

    if (_recentIds.length > 12) {
      _recentIds.removeRange(12, _recentIds.length);
    }

    _changed();
  }

  LocalPlaylist createPlaylist(String name) {
    final playlist = LocalPlaylist(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
      name: name.trim(),
      songIds: const [],
    );

    _playlists.add(playlist);
    _changed();

    return playlist;
  }

  void setPlaylistSongs(String id, Iterable<int> songIds) {
    final index = _playlists.indexWhere((playlist) => playlist.id == id);

    if (index == -1) return;

    final old = _playlists[index];

    _playlists[index] = LocalPlaylist(
      id: old.id,
      name: old.name,
      songIds: songIds.toSet(),
    );

    _changed();
  }

  void deletePlaylist(String id) {
    _playlists.removeWhere((playlist) => playlist.id == id);
    _changed();
  }

  Future<void> renamePlaylist(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name');
    final index = _playlists.indexWhere((playlist) => playlist.id == id);
    if (index == -1 || _playlists[index].name == trimmed) return;
    final old = _playlists[index];
    _playlists[index] = LocalPlaylist(
      id: old.id,
      name: trimmed,
      songIds: old.songIds,
    );
    _changed();
    await _pendingWrites;
  }

  Future<void> removePlaylistSong(String id, int songId) async {
    final playlist = playlistById(id);
    if (playlist == null || !playlist.songIds.contains(songId)) return;
    setPlaylistSongs(id, playlist.songIds.where((item) => item != songId));
    await _pendingWrites;
  }

  Future<void> reorderPlaylistSong(
    String id,
    int songId,
    int targetSongId,
  ) async {
    final playlist = playlistById(id);
    if (playlist == null || songId == targetSongId) return;
    final ids = playlist.songIds.toList();
    final oldIndex = ids.indexOf(songId);
    final newIndex = ids.indexOf(targetSongId);
    if (oldIndex == -1 || newIndex == -1) return;
    ids.insert(newIndex, ids.removeAt(oldIndex));
    setPlaylistSongs(id, ids);
    await _pendingWrites;
  }

  void _changed() {
    _notify();

    if (!_canSave) return;

    final snapshot = jsonEncode({
      'recent': _recentIds,
      'playlists': _playlists.map((playlist) => playlist.toJson()).toList(),
    });

    // Keep writes in order, even when tracks change quickly.
    _pendingWrites = _pendingWrites.then((_) async {
      try {
        await _prefs.setString(_storageKey, snapshot);
        _error = null;
      } catch (error) {
        _error = 'Could not save the latest collection changes.';
        debugPrint('Collection saving failed: $error');
      }

      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}