import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/library_collections.dart';
import '../providers/player_state.dart';
import '../services/artwork_palette_service.dart';
import '../services/song_filter.dart';
import '../widgets/song_artwork.dart';
import '../widgets/song_tile.dart';

class PlaylistScreen extends StatelessWidget {
  final String playlistId;

  const PlaylistScreen({super.key, required this.playlistId});

  Future<void> _rename(BuildContext context, LocalPlaylist playlist) async {
    final formKey = GlobalKey<FormState>();
    var name = playlist.name;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          if (formKey.currentState!.validate()) {
            Navigator.pop(dialogContext, name.trim());
          }
        }

        return AlertDialog(
          title: const Text('Rename playlist'),
          content: Form(
            key: formKey,
            child: TextFormField(
              initialValue: playlist.name,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Playlist name'),
              onChanged: (value) => name = value,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a playlist name'
                  : null,
              onFieldSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: submit, child: const Text('Save')),
          ],
        );
      },
    );
    if (!context.mounted || result == null) return;
    await context.read<LibraryCollections>().renamePlaylist(playlistId, result);
  }

  Future<void> _editSongs(BuildContext context, LocalPlaylist playlist) async {
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
          'Delete "${playlist.name}"? '
          'Your audio files will stay on your device.',
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

  String _durationLabel(List<Song> songs) {
    final milliseconds = songs.fold<int>(
      0,
      (total, song) =>
          total + (song.durationMs > 0 ? song.durationMs : 0),
    );

    final duration = Duration(milliseconds: milliseconds);

    if (duration.inHours > 0) {
      return '${duration.inHours} hr '
          '${duration.inMinutes.remainder(60)} min';
    }

    if (milliseconds > 0 && duration.inMinutes == 0) {
      return 'Less than a minute';
    }

    return '${duration.inMinutes} min';
  }

  Future<void> _play(
    BuildContext context,
    List<Song> songs, {
    bool? shuffle,
  }) async {
    if (songs.isEmpty) return;

    final player = context.read<PlayerState>();

    final queue = List<Song>.of(songs);

    try {
      await player.playFromLibrary(
        queue.first,
        queue,
        playlistId: playlistId,
        shuffle: shuffle,
      );
    } catch (error) {
      debugPrint('Playlist playback failed: $error');

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not play this track. Please try another.'),
        ),
      );
    }
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

    final songs = collections.songsFor(
      playlist.songIds,
      player.songs,
    );

    final isActivePlaylist = player.activePlaylistId == playlistId;
    final showPause = isActivePlaylist && player.playPauseShowsPause;

    final coverSongs = <Song>[];
    final seenAlbums = <String>{};

    for (final song in songs) {
      final album = song.album.trim().toLowerCase();
      final unknownAlbum = album.isEmpty ||
          album == '<unknown>' ||
          album == 'unknown album';

      final key = unknownAlbum ? 'song:${song.id}' : 'album:$album';

      if (seenAlbums.add(key)) {
        coverSongs.add(song);
      }

      if (coverSongs.length == 4) break;
    }

    return _PlaylistBackdrop(
      songId: songs.isEmpty ? null : songs.first.id,
      builder: (context, scheme) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            toolbarHeight: 64,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: const Text(
              'Playlist',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Choose songs',
                onPressed: () => _editSongs(context, playlist),
                icon: const Icon(Icons.playlist_add_rounded),
              ),
              PopupMenuButton<String>(
                tooltip: 'Playlist options',
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (value) {
                  if (value == 'rename') {
                    _rename(context, playlist);
                  }
                  if (value == 'delete') {
                    _delete(context, playlist);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text('Rename playlist'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete playlist'),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: CustomScrollView(
              key: PageStorageKey('playlist-$playlistId'),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 260,
                            ),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x55000000),
                                      blurRadius: 32,
                                      offset: Offset(0, 16),
                                    ),
                                  ],
                                ),
                                child: _PlaylistCover(
                                  songs: coverSongs,
                                  scheme: scheme,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          playlist.name,
                          style: const TextStyle(
                            fontSize: 32,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${songs.length} '
                          '${songs.length == 1 ? 'song' : 'songs'}'
                          ' • ${_durationLabel(songs)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: songs.isEmpty
                                    ? null
                                    : () {
                                        if (isActivePlaylist) {
                                          player.togglePlayPause();
                                        } else {
                                          _play(context, songs);
                                        }
                                      },
                                style: FilledButton.styleFrom(
                                  backgroundColor: scheme.primary,
                                  foregroundColor: scheme.onPrimary,
                                  minimumSize: const Size(0, 52),
                                  shape: const StadiumBorder(),
                                ),
                                icon: Icon(
                                  showPause
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 27,
                                ),
                                label: Text(
                                  showPause ? 'Pause' : 'Play',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: songs.isEmpty
                                    ? null
                                    : () {
                                        if (isActivePlaylist) {
                                          player.toggleShuffle();
                                        } else {
                                          _play(
                                            context,
                                            songs,
                                            shuffle: true,
                                          );
                                        }
                                      },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isActivePlaylist &&
                                          player.shuffleEnabled
                                      ? scheme.primary
                                      : Colors.white,
                                  minimumSize: const Size(0, 52),
                                  side: const BorderSide(
                                    color: Colors.white24,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                icon: const Icon(
                                  Icons.shuffle_rounded,
                                  size: 21,
                                ),
                                label: const Text(
                                  'Shuffle',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (collections.error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            collections.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (songs.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                      child: Column(
                        children: [
                          const Text(
                            'Make it yours',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add a few favourites to get started.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.tonalIcon(
                            onPressed: () => _editSongs(context, playlist),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Choose songs'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Songs',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _editSongs(context, playlist),
                            icon: const Icon(Icons.add_rounded, size: 19),
                            label: const Text('Add songs'),
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
                    sliver: SliverReorderableList(
                      itemCount: songs.length,
                      onReorderItem: (oldIndex, newIndex) {
                        collections.reorderPlaylistSong(
                          playlistId,
                          songs[oldIndex].id,
                          songs[newIndex].id,
                        );
                      },
                      proxyDecorator: (child, index, animation) => Material(
                        color: const Color(0xFF252832),
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        child: child,
                      ),
                      itemBuilder: (context, index) {
                        final song = songs[index];

                        return Padding(
                          key: ValueKey(song.id),
                          padding: const EdgeInsets.only(bottom: 3),
                          child: SongTile(
                            song: song,
                            onRemoveFromPlaylist: () {
                              collections.removePlaylistSong(
                                playlistId,
                                song.id,
                              );
                            },
                            dragHandle: ReorderableDragStartListener(
                              index: index,
                              child: const Tooltip(
                                message: 'Drag to reorder',
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            ),
                            accentColor: scheme.primary,
                            isCurrent: player.currentSong?.id == song.id,
                            isPlaying: player.playing,
                            onTap: () => player.playFromLibrary(
                              song,
                              List<Song>.of(songs),
                              playlistId: playlistId,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistCover extends StatelessWidget {
  final List<Song> songs;
  final ColorScheme scheme;

  const _PlaylistCover({
    required this.songs,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;

          Widget artwork(int index, double width) {
            return SongArtwork(
              songId: songs[index].id,
              size: width,
              borderRadius: 0,
            );
          }

          if (songs.isEmpty) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primaryContainer,
                    const Color(0xFF20232B),
                  ],
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.library_music_rounded,
                  size: 80,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            );
          }

          if (songs.length == 1) {
            return artwork(0, size);
          }

          return Column(
            children: List.generate(2, (row) {
              return Row(
                children: List.generate(2, (column) {
                  final index = (row * 2 + column) % songs.length;
                  return artwork(index, size / 2);
                }),
              );
            }),
          );
        },
      ),
    );
  }
}

class _PlaylistBackdrop extends StatefulWidget {
  final int? songId;
  final Widget Function(BuildContext context, ColorScheme scheme) builder;

  const _PlaylistBackdrop({
    required this.songId,
    required this.builder,
  });

  @override
  State<_PlaylistBackdrop> createState() => _PlaylistBackdropState();
}

class _PlaylistBackdropState extends State<_PlaylistBackdrop> {
  final _palettes = ArtworkPaletteService.shared;

  static final _neutralScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8AAEAA),
    brightness: Brightness.dark,
  );

  late ColorScheme _scheme;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _scheme = _neutralScheme;
    _loadPalette();
  }

  @override
  void didUpdateWidget(covariant _PlaylistBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.songId != widget.songId) {
      _loadPalette();
    }
  }

  void _loadPalette() {
    final request = ++_request;
    final songId = widget.songId;

    if (songId == null) {
      _scheme = _neutralScheme;
      return;
    }

    final cached = _palettes.peek(songId);

    if (cached != null) {
      _scheme = cached.scheme;
      return;
    }

    _resolvePalette(songId, request);
  }

  Future<void> _resolvePalette(int songId, int request) async {
    try {
      final visuals = await _palettes.load(songId);

      if (!mounted || request != _request) return;

      setState(() {
        _scheme = visuals.scheme;
      });
    } catch (error) {
      debugPrint('Playlist palette loading failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 650),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.45, 0.85],
          colors: [
            Color.lerp(
              const Color(0xFF101115),
              _scheme.primaryContainer,
              0.85,
            )!,
            Color.lerp(
              const Color(0xFF101115),
              _scheme.secondaryContainer,
              0.35,
            )!,
            const Color(0xFF101115),
          ],
        ),
      ),
      child: widget.builder(context, _scheme),
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
