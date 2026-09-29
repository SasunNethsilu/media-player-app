import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

class SongArtwork extends StatefulWidget {
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
  State<SongArtwork> createState() => _SongArtworkState();
}

class _SongArtworkState extends State<SongArtwork> {
  static final Map<int, Uint8List?> _cache = {};

  late Future<Uint8List?> _artworkFuture;

  @override
  void initState() {
    super.initState();
    _artworkFuture = _fetchArtwork();
  }

  @override
  void didUpdateWidget(covariant SongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      setState(() {
        _artworkFuture = _fetchArtwork();
      });
    }
  }

  Future<Uint8List?> _fetchArtwork() async {
    if (_cache.containsKey(widget.songId)) {
      return _cache[widget.songId];
    }
    final bytes = await OnAudioQuery().queryArtwork(widget.songId, ArtworkType.AUDIO, size: 800, quality: 100);
    _cache[widget.songId] = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _artworkFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: bytes != null
                ? Image.memory(
                    bytes,
                    key: ValueKey('art_${widget.songId}'), // required, tells AnimatedSwitcher this is a "new" child
                    width: widget.size,
                    height: widget.size,
                    fit: BoxFit.cover,
                  )
                : Container(
                    key: const ValueKey('placeholder'),
                    width: widget.size,
                    height: widget.size,
                    color: Colors.grey[300],
                    child: Icon(Icons.music_note, size: widget.size * 0.4, color: Colors.grey),
                  ),
          ),
        );
      },
    );
  }
}