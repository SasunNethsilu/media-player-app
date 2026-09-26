import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import '../models/song.dart';

class LibraryScanner {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<List<Song>> scanSongs() async {
    debugPrint('Library scan: checking plugin permissions.');
    bool permitted = await _audioQuery.permissionsStatus();
    if(!permitted) {
      permitted = await _audioQuery.permissionsRequest();
    }
    if(!permitted) {
      debugPrint(
        'Library scan stopped: audio library permission was not granted.',
      );
      return [];
    }

    debugPrint('Library scan: querying songs.');
    final List<SongModel> rawSongs = await _audioQuery.querySongs();
    debugPrint('Library scan: found ${rawSongs.length} songs.');

    return rawSongs.map((s) => Song(
      id:s.id,
      title: s.title,
      artist: s.artist ?? 'Unknown Artist',
      album: s.album ?? 'Unknown Album',
      path: s.data,
      durationMs: s.duration ?? 0
    )).toList();
  }
}
