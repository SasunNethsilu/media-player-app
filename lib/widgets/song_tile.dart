import 'package:flutter/material.dart';

import '../models/song.dart';
import 'song_artwork.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;
  final bool isCurrent;
  final bool isPlaying;
  final Widget? trailing;
  final Color? accentColor;

  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.isCurrent = false,
    this.isPlaying = false,
    this.trailing,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;

    return Material(
      color: isCurrent
        ? accent.withValues(alpha: 0.14)
        : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 5,
        ),
        horizontalTitleGap: 14,
        leading: SongArtwork(
          songId: song.id,
          size: 52,
          borderRadius: 12,
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ),
        trailing: trailing ??
            (isCurrent
                ? Icon(
                    isPlaying
                        ? Icons.equalizer_rounded
                        : Icons.pause_rounded,
                    color: accent,
                    size: 22,
                    semanticLabel: isPlaying ? 'Playing' : 'Paused',
                  )
                : null),
      ),
    );
  }
}