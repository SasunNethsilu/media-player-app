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

    if (text == null || text.isEmpty || text.toLowerCase() == '<unknown>') {
      return fallback;
    }

    return text;
  }

  String? _optionalMetadata(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == '<unknown>') {
      return null;
    }
    return text;
  }

  int? _positiveInt(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
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
      final metadata = song.getMap;
      final rawTrack = _positiveInt(song.track);
      final encodedDisc = rawTrack != null && rawTrack >= 1000
          ? rawTrack ~/ 1000
          : null;
      final decodedTrack = encodedDisc == null ? rawTrack : rawTrack! % 1000;

      return Song(
        id: song.id,
        title: _cleanMetadata(song.title, 'Unknown Title'),
        artist: _cleanMetadata(song.artist, 'Unknown Artist'),
        album: _cleanMetadata(song.album, 'Unknown Album'),
        path: song.data,
        durationMs: song.duration ?? 0,
        albumId: _positiveInt(song.albumId),
        artistId: _positiveInt(song.artistId),
        albumArtist: _optionalMetadata(metadata['album_artist']),
        trackNumber: decodedTrack != null && decodedTrack > 0
            ? decodedTrack
            : null,
        discNumber: encodedDisc != null && encodedDisc > 0 ? encodedDisc : null,
        year: _positiveInt(metadata['year']),
      );
    }).toList();
  }
}
