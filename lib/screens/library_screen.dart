import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/library_collections.dart';
import '../providers/player_state.dart';
import '../services/artwork_palette_service.dart';
import '../services/song_filter.dart';
import '../widgets/song_artwork.dart';
import '../widgets/song_tile.dart';
import 'playlist_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _section = 0;
  SortOption _sortOption = SortOption.title;

  int? _paletteSongId;
  Future<SongVisuals>? _paletteFuture;

  static final _defaultScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF52C8E5),
    brightness: Brightness.dark,
  );

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      if (mounted) {
        context.read<PlayerState>().loadLibrary();
      }
    });
  }

  void _openPlaylist(String id) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistScreen(playlistId: id),
      ),
    );
  }

  Future<void> _createPlaylist() async {
    String name = '';

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
          ),
          onChanged: (value) => name = value,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(dialogContext, value.trim());
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
              if (name.trim().isNotEmpty) {
                Navigator.pop(dialogContext, name.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (!mounted || result == null) return;

    final playlist =
        context.read<LibraryCollections>().createPlaylist(result);

    _openPlaylist(playlist.id);
  }

  Widget _pill({
    required String label,
    required IconData icon,
    required int index,
    required ColorScheme scheme,
  }) {
    final selected = _section == index;

    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? scheme.primary
            : Colors.white.withValues(alpha: 0.06),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _section = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 13,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? scheme.onPrimary : Colors.white70,
                ),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? scheme.onPrimary : Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _status(
    IconData icon,
    String message, {
    VoidCallback? retry,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                height: 1.5,
              ),
            ),
            if (retry != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonal(
                onPressed: retry,
                child: const Text('Scan again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recentCard(
    Song song,
    List<Song> recent,
    PlayerState player,
    ColorScheme scheme,
  ) {
    return SizedBox(
      width: 136,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => player.playFromLibrary(song, List<Song>.of(recent)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SongArtwork(
                    songId: song.id,
                    size: 136,
                    borderRadius: 22,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: scheme.onPrimary,
                        size: 23,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _library(
    PlayerState player,
    LibraryCollections collections,
    ColorScheme scheme,
  ) {
    if (player.isLoadingLibrary) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (player.libraryError != null) {
      return _status(
        Icons.info_outline_rounded,
        player.libraryError!,
        retry: () => player.loadLibrary(),
      );
    }

    if (player.songs.isEmpty) {
      return _status(
        Icons.library_music_outlined,
        'No music found on your device.',
        retry: () => player.loadLibrary(),
      );
    }

    final songs = filterAndSortSongs(player.songs, '', _sortOption);
    final recent = collections.recentSongs(player.songs);
    final textScaler = MediaQuery.of(context).textScaler;

    return RefreshIndicator(
      onRefresh: player.loadLibrary,
      child: CustomScrollView(
        key: const PageStorageKey('library-overview'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Text(
                'Recently Played',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: recent.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Text(
                      'Songs you play will appear here.',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : SizedBox(
                    height: 160 +
                        textScaler.scale(14) * 1.5 +
                        textScaler.scale(12) * 1.5,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: recent.length,
                      separatorBuilder: (_, index) {
                        return const SizedBox(width: 14);
                      },
                      itemBuilder: (context, index) {
                        return _recentCard(
                          recent[index],
                          recent,
                          player,
                          scheme,
                        );
                      },
                    ),
                  ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  const Text(
                    'All Songs',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${songs.length}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<SortOption>(
                    tooltip: 'Sort songs',
                    initialValue: _sortOption,
                    icon: const Icon(
                      Icons.sort_rounded,
                      color: Colors.white60,
                    ),
                    onSelected: (option) {
                      setState(() => _sortOption = option);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: SortOption.title,
                        child: Text('Song title'),
                      ),
                      PopupMenuItem(
                        value: SortOption.artist,
                        child: Text('Artist name'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final song = songs[index];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: SongTile(
                      key: ValueKey(song.id),
                      song: song,
                      isCurrent: player.currentSong?.id == song.id,
                      isPlaying: player.playing,
                      onTap: () => player.playFromLibrary(song, songs),
                    ),
                  );
                },
                childCount: songs.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlists(
    PlayerState player,
    LibraryCollections collections,
    ColorScheme scheme,
  ) {
    final playlists = collections.playlists;

    return ListView(
      key: const PageStorageKey('local-playlists'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your Playlists',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Create playlist',
              onPressed: _createPlaylist,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (playlists.isEmpty)
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  size: 44,
                  color: scheme.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No playlists yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _createPlaylist,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create playlist'),
                ),
              ],
            ),
          ),
        for (final playlist in playlists)
          _playlistCard(playlist, player, collections, scheme),
      ],
    );
  }

  Widget _playlistCard(
    LocalPlaylist playlist,
    PlayerState player,
    LibraryCollections collections,
    ColorScheme scheme,
  ) {
    final songs = collections.songsFor(playlist.songIds, player.songs);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.white10),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openPlaylist(playlist.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (songs.isNotEmpty)
                  SongArtwork(
                    songId: songs.first.id,
                    size: 64,
                    borderRadius: 18,
                  )
                else
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.queue_music_rounded,
                      color: scheme.primary,
                      size: 30,
                    ),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${songs.length} tracks',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final collections = context.watch<LibraryCollections>();
    final songId = player.currentSong?.id;

    if (songId != _paletteSongId) {
      _paletteSongId = songId;
      _paletteFuture = songId == null
          ? null
          : ArtworkPaletteService.shared.load(songId);
    }

    return FutureBuilder<SongVisuals>(
      future: _paletteFuture,
      initialData: songId == null
          ? null
          : ArtworkPaletteService.shared.peek(songId),
      builder: (context, snapshot) {
        final scheme = snapshot.data?.scheme ?? _defaultScheme;
        final reduceMotion = MediaQuery.of(context).disableAnimations;

        return AnimatedContainer(
          duration: Duration(milliseconds: reduceMotion ? 0 : 700),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(
                  const Color(0xFF101115),
                  scheme.primaryContainer,
                  0.65,
                )!,
                const Color(0xFF101115),
              ],
              stops: const [0, 0.65],
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              toolbarHeight: 64,
              backgroundColor: Colors.transparent,
              title: const Text('Your Library'),
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _pill(
                          label: 'Library',
                          icon: Icons.graphic_eq_rounded,
                          index: 0,
                          scheme: scheme,
                        ),
                        _pill(
                          label: 'Playlists',
                          icon: Icons.queue_music_rounded,
                          index: 1,
                          scheme: scheme,
                        ),
                      ],
                    ),
                  ),
                ),
                if (collections.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      collections.error!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                Expanded(
                  child: _section == 0
                      ? _library(player, collections, scheme)
                      : _playlists(player, collections, scheme),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}