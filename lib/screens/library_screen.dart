import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../models/library_catalog.dart';
import '../providers/library_collections.dart';
import '../providers/player_state.dart';
import '../providers/app_settings.dart';
import '../services/artwork_palette_service.dart';
import '../widgets/song_artwork.dart';
import 'playlist_screen.dart';
import 'library_browse_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatefulWidget {
  final VoidCallback? onOpenAllSongs;

  const LibraryScreen({super.key, this.onOpenAllSongs});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _section = 0;

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
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlaylistScreen(playlistId: id)));
  }

  void _openBrowse(LibraryBrowseType type) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LibraryBrowseScreen(
          type: type,
          hideShortAudio: context.read<AppSettings>().hideShortAudio,
        ),
      ),
    );
  }

  Widget _browseCard({
    required String title,
    required String detail,
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme scheme,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createPlaylist() async {
    String name = '';

    final result = await showDialog<String>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('New playlist'),
        content: TextField(
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Playlist name'),
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

    final playlist = context.read<LibraryCollections>().createPlaylist(result);

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
        color: selected ? scheme.primary : Colors.white.withValues(alpha: 0.06),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? scheme.onPrimary : Colors.white70,
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? scheme.onPrimary : Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _status(IconData icon, String message, {VoidCallback? retry}) {
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
              style: const TextStyle(color: Colors.white60, height: 1.5),
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
    final showPause =
        player.currentSong?.id == song.id && player.playPauseShowsPause;

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
                  SongArtwork(songId: song.id, size: 136, borderRadius: 22),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Material(
                        color: scheme.primary,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          tooltip: showPause
                              ? 'Pause ${song.title}'
                              : 'Play ${song.title}',
                          icon: Icon(
                            showPause
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          iconSize: 26,
                          color: scheme.onPrimary,
                          padding: EdgeInsets.zero,
                          onPressed: () async {
                            if (player.currentSong?.id == song.id) {
                              player.togglePlayPause();
                              return;
                            }

                            try {
                              await player.playFromLibrary(
                                song,
                                List<Song>.of(recent),
                              );
                            } catch (error) {
                              debugPrint('Recent song playback failed: $error');

                              if (!mounted) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not play this track.'),
                                ),
                              );
                            }
                          },
                        ),
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
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
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
    final settings = context.watch<AppSettings>();
    if (player.isLoadingLibrary) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
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

    final recent = collections.recentSongs(player.songs);
    final browseSongs = applyShortAudioFilter(
      player.songs,
      enabled: settings.hideShortAudio,
    );
    final albumCount = groupAlbums(browseSongs).length;
    final artistCount = groupArtists(browseSongs).length;
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
                    height:
                        160 +
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
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Browse',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  PopupMenuButton<bool>(
                    tooltip: 'Filter albums and artists',
                    icon: Icon(
                      settings.hideShortAudio
                          ? Icons.filter_alt_rounded
                          : Icons.filter_alt_outlined,
                      color: settings.hideShortAudio
                          ? scheme.primary
                          : Colors.white60,
                    ),
                    onSelected: (_) async {
                      try {
                        await settings.setHideShortAudio(
                          !settings.hideShortAudio,
                        );
                      } catch (_) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not save this setting.'),
                          ),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      CheckedPopupMenuItem(
                        value: true,
                        checked: settings.hideShortAudio,
                        child: const Text('Hide tracks under 30 seconds'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stack =
                      constraints.maxWidth < 430 ||
                      MediaQuery.textScalerOf(context).scale(14) > 20;
                  final albums = _browseCard(
                    title: 'Albums',
                    detail:
                        '$albumCount ${albumCount == 1 ? 'album' : 'albums'}',
                    icon: Icons.album_rounded,
                    onTap: () => _openBrowse(LibraryBrowseType.albums),
                    scheme: scheme,
                  );
                  final artists = _browseCard(
                    title: 'Artists',
                    detail:
                        '$artistCount ${artistCount == 1 ? 'artist' : 'artists'}',
                    icon: Icons.people_alt_rounded,
                    onTap: () => _openBrowse(LibraryBrowseType.artists),
                    scheme: scheme,
                  );

                  if (stack) {
                    return Column(
                      children: [albums, const SizedBox(height: 12), artists],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: albums),
                      const SizedBox(width: 12),
                      Expanded(child: artists),
                    ],
                  );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              child: _browseCard(
                title: 'All Songs',
                detail:
                    '${player.songs.length} ${player.songs.length == 1 ? 'song' : 'songs'}',
                icon: Icons.queue_music_rounded,
                onTap: widget.onOpenAllSongs ?? () {},
                scheme: scheme,
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
    final songsById = {for (final song in player.songs) song.id: song};

    return CustomScrollView(
      key: const PageStorageKey('local-playlists-grid'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Playlists',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      if (playlists.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          '${playlists.length} '
                          '${playlists.length == 1 ? 'playlist' : 'playlists'}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  tooltip: 'Create playlist',
                  onPressed: _createPlaylist,
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    minimumSize: const Size(48, 48),
                  ),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
        ),
        if (playlists.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.library_music_rounded,
                        size: 38,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Your next favourite mix',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Bring your favourite songs together.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _createPlaylist,
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        minimumSize: const Size(0, 48),
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create playlist'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              player.currentSong == null ? 28 : 124,
            ),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.crossAxisExtent;
                final textScaler = MediaQuery.of(context).textScaler;

                // Two columns on phones, more on wider screens.
                // Very narrow layouts get one column.
                final columns = width < 260
                    ? 1
                    : width >= 900
                    ? 4
                    : width >= 600
                    ? 3
                    : 2;

                const spacing = 16.0;
                final cardWidth = (width - spacing * (columns - 1)) / columns;

                // Reserve two title lines and one count line.
                final titleHeight = textScaler.scale(15) * 1.3 * 2;
                final countHeight = textScaler.scale(13) * 1.4;
                final cardHeight =
                    cardWidth + 12 + titleHeight + 4 + countHeight + 14;

                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    mainAxisExtent: cardHeight,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final playlist = playlists[index];
                    final songs = <Song>[
                      for (final id in playlist.songIds)
                        if (songsById.containsKey(id)) songsById[id]!,
                    ];

                    return _playlistCard(playlist, songs, scheme, titleHeight);
                  }, childCount: playlists.length),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _playlistCard(
    LocalPlaylist playlist,
    List<Song> songs,
    ColorScheme scheme,
    double titleHeight,
  ) {
    final player = context.watch<PlayerState>();
    final isActivePlaylist = player.activePlaylistId == playlist.id;
    final showPause = isActivePlaylist && player.playPauseShowsPause;

    return Material(
      key: ValueKey(playlist.id),
      color: Colors.white.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPlaylist(playlist.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _playlistCover(songs, scheme),
                  if (songs.isNotEmpty)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Material(
                        color: scheme.primary,
                        shape: const CircleBorder(),
                        elevation: 3,
                        shadowColor: Colors.black38,
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          tooltip: showPause
                              ? 'Pause ${playlist.name}'
                              : 'Play ${playlist.name}',
                          icon: Icon(
                            showPause
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          iconSize: 28,
                          color: scheme.onPrimary,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          onPressed: () async {
                            if (player.activePlaylistId == playlist.id) {
                              player.togglePlayPause();
                              return;
                            }

                            final queue = List<Song>.of(songs);
                            if (queue.isEmpty) return;

                            try {
                              await player.playFromLibrary(
                                queue.first,
                                queue,
                                playlistId: playlist.id,
                              );
                            } catch (error) {
                              debugPrint('Playlist playback failed: $error');

                              if (!mounted) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not play this track. Please try another.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: titleHeight,
                    child: Text(
                      playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${songs.length} '
                    '${songs.length == 1 ? 'song' : 'songs'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playlistCover(List<Song> songs, ColorScheme scheme) {
    final covers = <Song>[];
    final seenAlbums = <String>{};

    for (final song in songs) {
      final album = song.album.trim().toLowerCase();
      final unknownAlbum =
          album.isEmpty || album == '<unknown>' || album == 'unknown album';

      final key = unknownAlbum ? 'song:${song.id}' : 'album:$album';

      if (seenAlbums.add(key)) {
        covers.add(song);
      }

      if (covers.length == 4) break;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;

        if (covers.isEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primaryContainer, const Color(0xFF20232B)],
              ),
            ),
            child: Center(
              child: Icon(
                Icons.library_music_rounded,
                size: size * 0.32,
                color: scheme.onPrimaryContainer,
              ),
            ),
          );
        }

        if (covers.length == 1) {
          return SongArtwork(
            songId: covers.first.id,
            size: size,
            borderRadius: 0,
          );
        }

        return Column(
          children: List.generate(2, (row) {
            return Row(
              children: List.generate(2, (column) {
                final index = (row * 2 + column) % covers.length;

                return SongArtwork(
                  songId: covers[index].id,
                  size: size / 2,
                  borderRadius: 0,
                );
              }),
            );
          }),
        );
      },
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
              actions: [
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Column(
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
          ),
        );
      },
    );
  }
}
