import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/library_collections.dart';
import '../providers/player_state.dart';
import '../services/song_filter.dart';
import '../widgets/song_artwork.dart';
import '../widgets/song_tile.dart';

class PlaylistScreen extends StatelessWidget {
  final String playlistId;

  const PlaylistScreen({
    super.key,
    required this.playlistId,
  });

  Future<void> _editSongs(
    BuildContext context,
    LocalPlaylist playlist,
  ) async {
    final player = context.read<PlayerState>();
    final collections = context.read<LibraryCollections>();

    final selected = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(
        builder: (_) => _PlaylistSongPicker(
          songs: List<Song>.of(player.songs),
          selectedIds: playlist.songIds,
        ),
      ),
    );

    if (!context.mounted || selected == null) return;

    collections.setPlaylistSongs(playlistId, selected);
  }

  Future<void> _delete(
    BuildContext context,
    LocalPlaylist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text(
          'Delete "${playlist.name}"? Your audio files will stay on your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!context.mounted || confirmed != true) return;

    context.read<LibraryCollections>().deletePlaylist(playlistId);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final collections = context.watch<LibraryCollections>();
    final player = context.watch<PlayerState>();
    final playlist = collections.playlistById(playlistId);

    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Playlist not found')),
      );
    }

    final songs = collections.songsFor(playlist.songIds, player.songs);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Delete playlist',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(context, playlist),
          ),
        ],
      ),
      body: Column(
        children: [
          if (collections.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                collections.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${songs.length} tracks',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
                IconButton(
                  tooltip: 'Choose songs',
                  onPressed: () => _editSongs(context, playlist),
                  icon: const Icon(Icons.playlist_add_rounded),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: songs.isEmpty
                      ? null
                      : () => player.playFromLibrary(songs.first, songs),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
              ],
            ),
          ),
          Expanded(
            child: songs.isEmpty
                ? Center(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _editSongs(context, playlist),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Choose songs'),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    itemCount: songs.length,
                    separatorBuilder: (_, index) {
                      return const SizedBox(height: 3);
                    },
                    itemBuilder: (context, index) {
                      final song = songs[index];

                      return SongTile(
                        key: ValueKey(song.id),
                        song: song,
                        isCurrent: player.currentSong?.id == song.id,
                        isPlaying: player.playing,
                        onTap: () => player.playFromLibrary(song, songs),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistSongPicker extends StatefulWidget {
  final List<Song> songs;
  final List<int> selectedIds;

  const _PlaylistSongPicker({
    required this.songs,
    required this.selectedIds,
  });

  @override
  State<_PlaylistSongPicker> createState() => _PlaylistSongPickerState();
}

class _PlaylistSongPickerState extends State<_PlaylistSongPicker> {
  late final Set<int> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedIds.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final songs = filterAndSortSongs(
      widget.songs,
      _query.trim(),
      SortOption.title,
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: const Text('Choose songs'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, _selected.toList());
            },
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search songs or artists',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: songs.isEmpty
                ? const Center(child: Text('No songs found'))
                : ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];

                      return CheckboxListTile(
                        value: _selected.contains(song.id),
                        secondary: SongArtwork(
                          songId: song.id,
                          size: 44,
                          borderRadius: 10,
                        ),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: (selected) {
                          setState(() {
                            if (selected == true) {
                              _selected.add(song.id);
                            } else {
                              _selected.remove(song.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}