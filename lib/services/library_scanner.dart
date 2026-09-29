import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../models/song.dart';

class LibraryPermissionDenied implements Exception {
  const LibraryPermissionDenied();
}

class LibraryScanner {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  String _cleanMetadata(String? value, String fallback) {
    final text = value?.trim();

    if (text == null ||
        text.isEmpty ||
        text.toLowerCase() == '<unknown>') {
      return fallback;
    }

    return text;
  }

  Future<List<Song>> scanSongs() async {
    bool permitted = await _audioQuery.permissionsStatus();

    if (!permitted) {
      permitted = await _audioQuery.permissionsRequest();
    }

    if (!permitted) {
      throw const LibraryPermissionDenied();
    }

    final rawSongs = await _audioQuery.querySongs();

    debugPrint('Library scan: found ${rawSongs.length} songs.');

    return rawSongs.map((song) {
      return Song(
        id: song.id,
        title: _cleanMetadata(song.title, 'Unknown Title'),
        artist: _cleanMetadata(song.artist, 'Unknown Artist'),
        album: _cleanMetadata(song.album, 'Unknown Album'),
        path: song.data,
        durationMs: song.duration ?? 0,
      );
    }).toList();
  }
}