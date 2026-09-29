import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'dart:typed_data';

class SongArtwork extends StatelessWidget {
  final int songId;
  final double size;
  final double borderRadius;

  const SongArtwork({
    super.key,
    required this.songId,
    this.size = 48,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: OnAudioQuery().queryArtwork(songId, ArtworkType.AUDIO, size: 800, quality: 100),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: bytes != null
              ? Image.memory(bytes, width: size, height: size, fit: BoxFit.cover)
              : Container(
                  width: size,
                  height: size,
                  color: Colors.grey[300],
                  child: Icon(Icons.music_note, size: size * 0.4, color: Colors.grey),
                ),
        );
      },
    );
  }
}