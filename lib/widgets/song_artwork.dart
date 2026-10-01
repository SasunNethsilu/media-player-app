import 'package:flutter/material.dart';

import '../services/artwork_palette_service.dart';

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
  late Future<SongVisuals> _visualsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.songId != widget.songId) {
      _load();
    }
  }

  void _load() {
    _visualsFuture = ArtworkPaletteService.shared.load(
      widget.songId,
      priority: false,
    );
  }

  Widget _placeholder() {
    return Container(
      key: const ValueKey('placeholder'),
      width: widget.size,
      height: widget.size,
      color: const Color(0xFF272A32),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: widget.size * 0.4,
        color: Colors.white38,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cached = ArtworkPaletteService.shared.peek(widget.songId);

    final decodeWidth = (widget.size * MediaQuery.of(context).devicePixelRatio)
        .round()
        .clamp(1, 800)
        .toInt();

    return FutureBuilder<SongVisuals>(
      key: ValueKey(widget.songId),
      future: _visualsFuture,
      initialData: cached,
      builder: (context, snapshot) {
        final bytes = snapshot.data?.artwork;

        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            child: bytes == null
                ? _placeholder()
                : Image.memory(
                    bytes,
                    key: ValueKey('art-${widget.songId}'),
                    width: widget.size,
                    height: widget.size,
                    cacheWidth: decodeWidth,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stackTrace) {
                      return _placeholder();
                    },
                  ),
          ),
        );
      },
    );
  }
}
