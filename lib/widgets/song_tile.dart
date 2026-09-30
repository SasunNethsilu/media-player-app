import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/library_collections.dart';
import '../providers/player_state.dart';
import 'song_artwork.dart';

enum _SongAction { playNext, addToQueue, addToPlaylist, removeFromPlaylist }

class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;
  final bool isCurrent;
  final bool isPlaying;
  final Widget? trailing;
  final Color? accentColor;
  final VoidCallback? onRemoveFromPlaylist;
  final Widget? dragHandle;

  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.isCurrent = false,
    this.isPlaying = false,
    this.trailing,
    this.accentColor,
    this.onRemoveFromPlaylist,
    this.dragHandle,
  });

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  Future<String?> _askPlaylistName(BuildContext context) {
    String name = '';

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
          ),
          onChanged: (value) => name = value,
          onSubmitted: (value) {
            final trimmed = value.trim();

            if (trimmed.isNotEmpty) {
              Navigator.pop(dialogContext, trimmed);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = name.trim();

              if (trimmed.isNotEmpty) {
                Navigator.pop(dialogContext, trimmed);
              }
            },
            child: const Text('Create & add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addToPlaylist(
    BuildContext context,
    Color accent,
  ) async {
    final collections = context.read<LibraryCollections>();

    final playlistId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1B1D24),
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.55,
            child: Consumer<LibraryCollections>(
              builder: (context, collections, child) {
                final playlists = collections.playlists;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Add to playlist',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor:
                                ThemeData.estimateBrightnessForColor(accent) ==
                                        Brightness.light
                                    ? Colors.black
                                    : Colors.white,
                            minimumSize: const Size(0, 48),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Create new playlist'),
                          onPressed: () async {
                            final name = await _askPlaylistName(sheetContext);

                            if (!sheetContext.mounted || name == null) return;

                            final playlist = collections.createPlaylist(name);

                            Navigator.pop(sheetContext, playlist.id);
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: playlists.isEmpty
                          ? Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.library_music_outlined,
                                      size: 48,
                                      color: accent,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No playlists yet',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Create one in Library → Playlists, '
                                      'then add your songs here.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white54,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                0,
                                12,
                                20,
                              ),
                              itemCount: playlists.length,
                              separatorBuilder: (_, index) {
                                return const SizedBox(height: 4);
                              },
                              itemBuilder: (context, index) {
                                final playlist = playlists[index];
                                final alreadyAdded =
                                    playlist.songIds.contains(song.id);

                                return ListTile(
                                  enabled: !alreadyAdded,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  leading: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      Icons.queue_music_rounded,
                                      color: accent,
                                    ),
                                  ),
                                  title: Text(
                                    playlist.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    alreadyAdded
                                        ? 'Already added'
                                        : '${playlist.songIds.length} '
                                            '${playlist.songIds.length == 1 ? 'song' : 'songs'}',
                                  ),
                                  trailing: Icon(
                                    alreadyAdded
                                        ? Icons.check_rounded
                                        : Icons.add_rounded,
                                    color: alreadyAdded
                                        ? Colors.white38
                                        : accent,
                                  ),
                                  onTap: alreadyAdded
                                      ? null
                                      : () => Navigator.pop(
                                            sheetContext,
                                            playlist.id,
                                          ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (!context.mounted || playlistId == null) return;

    final playlist = collections.playlistById(playlistId);

    if (playlist == null) {
      _showMessage(context, 'This playlist no longer exists.');
      return;
    }

    if (playlist.songIds.contains(song.id)) {
      _showMessage(context, 'Already in ${playlist.name}.');
      return;
    }

    collections.setPlaylistSongs(
      playlist.id,
      [...playlist.songIds, song.id],
    );

    _showMessage(context, 'Added to ${playlist.name}');
  }

  Future<void> _handleAction(
    BuildContext context,
    _SongAction action,
    Color accent,
  ) async {
    if (action == _SongAction.removeFromPlaylist) {
      onRemoveFromPlaylist?.call();
      return;
    }
    if (action == _SongAction.addToPlaylist) {
      await _addToPlaylist(context, accent);
      return;
    }

    final player = context.read<PlayerState>();
    final startsPlayback = player.currentSong == null;

    if (action == _SongAction.addToQueue &&
        !startsPlayback &&
        player.queue.any((item) => item.id == song.id)) {
      _showMessage(context, 'Already in the queue');
      return;
    }

    try {
      switch (action) {
        case _SongAction.playNext:
          await player.enqueueNext(song);
          break;
        case _SongAction.addToQueue:
          await player.enqueueLast(song);
          break;
        case _SongAction.addToPlaylist:
        case _SongAction.removeFromPlaylist:
          return;
      }

      if (!context.mounted) return;

      _showMessage(
        context,
        startsPlayback
            ? 'Playing ${song.title}'
            : action == _SongAction.playNext
                ? 'Playing next: ${song.title}'
                : 'Added to queue',
      );
    } catch (error) {
      debugPrint('Song action failed: $error');

      if (!context.mounted) return;

      _showMessage(context, 'Could not complete that action.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        accentColor ?? Theme.of(context).colorScheme.primary;

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
            fontWeight:
                isCurrent ? FontWeight.w700 : FontWeight.w500,
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCurrent)
                  Icon(
                    isPlaying
                        ? Icons.equalizer_rounded
                        : Icons.pause_rounded,
                    color: accent,
                    size: 20,
                    semanticLabel: isPlaying ? 'Playing' : 'Paused',
                  ),
                PopupMenuButton<_SongAction>(
                  tooltip: 'Options for ${song.title}',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white60,
                  ),
                  onSelected: (action) {
                    _handleAction(context, action, accent);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _SongAction.playNext,
                      child: Row(
                        children: [
                          Icon(Icons.playlist_play_rounded, size: 22),
                          SizedBox(width: 12),
                          Text('Play next'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: _SongAction.addToQueue,
                      child: Row(
                        children: [
                          Icon(Icons.queue_music_rounded, size: 22),
                          SizedBox(width: 12),
                          Text('Add to queue'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: _SongAction.addToPlaylist,
                      child: Row(
                        children: [
                          Icon(Icons.playlist_add_rounded, size: 22),
                          SizedBox(width: 12),
                          Text('Add to playlist'),
                        ],
                      ),
                    ),
                    if (onRemoveFromPlaylist != null)
                      const PopupMenuItem(
                        value: _SongAction.removeFromPlaylist,
                        child: Text('Remove from this playlist'),
                      ),
                  ],
                ),
                ?dragHandle,
              ],
            ),
      ),
    );
  }
}