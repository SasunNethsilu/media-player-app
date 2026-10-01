import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/library_catalog.dart';
import '../models/song.dart';
import '../providers/player_state.dart';
import '../services/artwork_palette_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_artwork.dart';
import '../widgets/song_tile.dart';

enum LibraryBrowseType { albums, artists }

class LibraryBrowseScreen extends StatefulWidget {
  final LibraryBrowseType type;
  final bool hideShortAudio;

  const LibraryBrowseScreen({
    super.key,
    required this.type,
    required this.hideShortAudio,
  });

  @override
  State<LibraryBrowseScreen> createState() => _LibraryBrowseScreenState();
}

class _LibraryBrowseScreenState extends State<LibraryBrowseScreen> {
  AlbumSortOption _albumSort = AlbumSortOption.title;
  ArtistSortOption _artistSort = ArtistSortOption.name;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final songs = applyShortAudioFilter(
      player.songs,
      enabled: widget.hideShortAudio,
    );
    final albums = groupAlbums(songs, sort: _albumSort);
    final artists = groupArtists(songs, sort: _artistSort);
    final isAlbums = widget.type == LibraryBrowseType.albums;
    final count = isAlbums ? albums.length : artists.length;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(isAlbums ? 'Albums' : 'Artists'),
        actions: [
          if (isAlbums)
            PopupMenuButton<AlbumSortOption>(
              tooltip: 'Sort albums',
              initialValue: _albumSort,
              icon: const Icon(Icons.sort_rounded),
              onSelected: (value) => setState(() => _albumSort = value),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: AlbumSortOption.title,
                  child: Text('Album title'),
                ),
                PopupMenuItem(
                  value: AlbumSortOption.artist,
                  child: Text('Artist name'),
                ),
                PopupMenuItem(
                  value: AlbumSortOption.newest,
                  child: Text('Newest year'),
                ),
              ],
            )
          else
            PopupMenuButton<ArtistSortOption>(
              tooltip: 'Sort artists',
              initialValue: _artistSort,
              icon: const Icon(Icons.sort_rounded),
              onSelected: (value) => setState(() => _artistSort = value),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: ArtistSortOption.name,
                  child: Text('Artist name'),
                ),
                PopupMenuItem(
                  value: ArtistSortOption.albumCount,
                  child: Text('Album count'),
                ),
                PopupMenuItem(
                  value: ArtistSortOption.songCount,
                  child: Text('Song count'),
                ),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: MiniPlayerOverlay(
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                  child: Text(
                    '$count ${isAlbums
                        ? count == 1
                              ? 'album'
                              : 'albums'
                        : count == 1
                        ? 'artist'
                        : 'artists'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ),
              ),
              if (count == 0)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        widget.hideShortAudio
                            ? 'No music matches the short-audio filter.'
                            : 'No music found.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54),
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
                      final columns = width < 280
                          ? 1
                          : width >= 900
                          ? 5
                          : width >= 620
                          ? 4
                          : 2;
                      const spacing = 16.0;
                      final cardWidth =
                          (width - spacing * (columns - 1)) / columns;
                      final textScale = MediaQuery.textScalerOf(context)
                          .scale(14);
                      final cardHeight = cardWidth + 16 + textScale * 3.2;

                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: 20,
                          mainAxisExtent: cardHeight,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          if (isAlbums) {
                            return _AlbumCard(album: albums[index]);
                          }
                          return _ArtistCard(artist: artists[index]);
                        }, childCount: count),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final AlbumCollection album;

  const _AlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) => SongArtwork(
                  songId: album.artworkSong.id,
                  size: constraints.maxWidth,
                  borderRadius: 20,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 3),
            Text(
              [
                album.artist,
                if (album.year != null) '${album.year}',
              ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final ArtistCollection artist;

  const _ArtistCard({required this.artist});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArtistDetailScreen(artist: artist),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) => ClipOval(
                  child: SongArtwork(
                    songId: artist.artworkSong.id,
                    size: constraints.maxWidth,
                    borderRadius: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 3),
            Text(
              '${artist.albums.length} ${artist.albums.length == 1 ? 'album' : 'albums'} • ${artist.songs.length} ${artist.songs.length == 1 ? 'song' : 'songs'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class AlbumDetailScreen extends StatelessWidget {
  final AlbumCollection album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    return _CollectionDetail(
      title: album.title,
      subtitle: [
        album.artist,
        if (album.year != null) '${album.year}',
      ].join(' • '),
      songs: album.songs,
      artworkSong: album.artworkSong,
      artworkShape: BoxShape.rectangle,
      appBarTitle: 'Album',
    );
  }
}

class ArtistDetailScreen extends StatelessWidget {
  final ArtistCollection artist;

  const ArtistDetailScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context) {
    return _CollectionDetail(
      title: artist.name,
      subtitle:
          '${artist.albums.length} ${artist.albums.length == 1 ? 'album' : 'albums'}',
      songs: artist.songs,
      artworkSong: artist.artworkSong,
      artworkShape: BoxShape.circle,
      appBarTitle: 'Artist',
      albums: artist.albums,
    );
  }
}

class _CollectionDetail extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<Song> songs;
  final Song artworkSong;
  final BoxShape artworkShape;
  final String appBarTitle;
  final List<AlbumCollection> albums;

  const _CollectionDetail({
    required this.title,
    required this.subtitle,
    required this.songs,
    required this.artworkSong,
    required this.artworkShape,
    required this.appBarTitle,
    this.albums = const [],
  });

  @override
  State<_CollectionDetail> createState() => _CollectionDetailState();
}

class _CollectionDetailState extends State<_CollectionDetail> {
  bool _sortArtistSongsByAlbum = false;

  String _durationLabel() {
    final milliseconds = widget.songs.fold<int>(
      0,
      (total, song) => total + (song.durationMs > 0 ? song.durationMs : 0),
    );
    final duration = Duration(milliseconds: milliseconds);
    if (duration.inHours > 0) {
      return '${duration.inHours} hr ${duration.inMinutes.remainder(60)} min';
    }
    if (milliseconds > 0 && duration.inMinutes == 0) {
      return 'Less than a minute';
    }
    return '${duration.inMinutes} min';
  }

  Future<void> _play({bool shuffle = false}) async {
    if (widget.songs.isEmpty) return;
    final songs = List<Song>.of(widget.songs);
    try {
      await context.read<PlayerState>().playFromLibrary(
        songs.first,
        songs,
        shuffle: shuffle,
      );
    } catch (error) {
      debugPrint('Collection playback failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play this track.')),
      );
    }
  }

  List<Song> _displaySongs() {
    if (widget.albums.isEmpty || !_sortArtistSongsByAlbum) {
      return List<Song>.of(widget.songs)..sort((a, b) {
        final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return title != 0 ? title : a.id.compareTo(b.id);
      });
    }

    final albums = groupAlbums(widget.songs);
    return [for (final album in albums) ...album.songs];
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final songs = widget.albums.isEmpty ? widget.songs : _displaySongs();
    final currentInCollection = widget.songs.any(
      (song) => song.id == player.currentSong?.id,
    );
    final showPause = currentInCollection && player.playPauseShowsPause;

    return _ArtworkBackdrop(
      songId: widget.artworkSong.id,
      builder: (context, scheme) {
        final stackControls =
            MediaQuery.sizeOf(context).width < 360 ||
            MediaQuery.textScalerOf(context).scale(14) > 21;

        return Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            toolbarHeight: 64,
            backgroundColor: Colors.transparent,
            title: Text(
              widget.appBarTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ),
          body: MiniPlayerOverlay(
            child: SafeArea(
              top: false,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: widget.artworkShape,
                                    borderRadius:
                                        widget.artworkShape ==
                                            BoxShape.rectangle
                                        ? BorderRadius.circular(28)
                                        : null,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x55000000),
                                        blurRadius: 32,
                                        offset: Offset(0, 16),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: SongArtwork(
                                    songId: widget.artworkSong.id,
                                    size: 260,
                                    borderRadius: 0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 32,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${widget.songs.length} ${widget.songs.length == 1 ? 'song' : 'songs'} • ${_durationLabel()}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Flex(
                            direction: stackControls
                                ? Axis.vertical
                                : Axis.horizontal,
                            crossAxisAlignment: stackControls
                                ? CrossAxisAlignment.stretch
                                : CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                fit: stackControls
                                    ? FlexFit.loose
                                    : FlexFit.tight,
                                child: FilledButton.icon(
                                  onPressed: () {
                                    if (showPause) {
                                      player.togglePlayPause();
                                    } else {
                                      _play();
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
                                  ),
                                  label: Text(showPause ? 'Pause' : 'Play'),
                                ),
                              ),
                              const SizedBox(width: 12, height: 12),
                              Flexible(
                                fit: stackControls
                                    ? FlexFit.loose
                                    : FlexFit.tight,
                                child: OutlinedButton.icon(
                                  onPressed: () => _play(shuffle: true),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 52),
                                    side: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    shape: const StadiumBorder(),
                                  ),
                                  icon: const Icon(Icons.shuffle_rounded),
                                  label: const Text('Shuffle'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.albums.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(24, 4, 24, 12),
                        child: Text(
                          'Albums',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height:
                            150 +
                            MediaQuery.textScalerOf(context).scale(15) * 1.35 +
                            MediaQuery.textScalerOf(context).scale(12) * 1.35,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.albums.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(width: 14),
                          itemBuilder: (context, index) {
                            return SizedBox(
                              width: 136,
                              child: _AlbumCard(album: widget.albums[index]),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 12, 8),
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
                          if (widget.albums.isNotEmpty)
                            PopupMenuButton<bool>(
                              tooltip: 'Sort songs',
                              initialValue: _sortArtistSongsByAlbum,
                              icon: const Icon(Icons.sort_rounded),
                              onSelected: (value) {
                                setState(() => _sortArtistSongsByAlbum = value);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: false,
                                  child: Text('Song title'),
                                ),
                                PopupMenuItem(
                                  value: true,
                                  child: Text('Album order'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      0,
                      8,
                      player.currentSong == null ? 32 : 128,
                    ),
                    sliver: SliverList.builder(
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: SongTile(
                            key: ValueKey(song.id),
                            song: song,
                            accentColor: scheme.primary,
                            isCurrent: player.currentSong?.id == song.id,
                            isPlaying: player.playPauseShowsPause,
                            onTap: () => player.playFromLibrary(
                              song,
                              List<Song>.of(songs),
                            ),
                          ),
                        );
                      },
                    ),
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

class _ArtworkBackdrop extends StatefulWidget {
  final int songId;
  final Widget Function(BuildContext context, ColorScheme scheme) builder;

  const _ArtworkBackdrop({required this.songId, required this.builder});

  @override
  State<_ArtworkBackdrop> createState() => _ArtworkBackdropState();
}

class _ArtworkBackdropState extends State<_ArtworkBackdrop> {
  ColorScheme _scheme = ArtworkPaletteService.fallbackScheme;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ArtworkBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) _load();
  }

  void _load() {
    final request = ++_request;
    final cached = ArtworkPaletteService.shared.peek(widget.songId);
    if (cached != null) {
      _scheme = cached.scheme;
      return;
    }
    _resolve(widget.songId, request);
  }

  Future<void> _resolve(int songId, int request) async {
    try {
      final visuals = await ArtworkPaletteService.shared.load(songId);
      if (!mounted || request != _request) return;
      setState(() => _scheme = visuals.scheme);
    } catch (error) {
      debugPrint('Collection palette loading failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 650),
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
