import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../models/library_catalog.dart';
import '../providers/player_state.dart';
import '../providers/app_settings.dart';
import '../services/artwork_palette_service.dart';
import '../services/song_filter.dart';
import '../widgets/song_tile.dart';

class SongsScreen extends StatefulWidget {
  const SongsScreen({super.key});

  @override
  SongsScreenState createState() => SongsScreenState();
}

enum _SongListAction { sortTitle, sortArtist, toggleShortAudio }

class SongsScreenState extends State<SongsScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  String _query = '';
  SortOption _sortOption = SortOption.title;
  int? _paletteSongId;
  Future<SongVisuals>? _paletteFuture;

  static final _defaultScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF52C8E5),
    brightness: Brightness.dark,
  );

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void clearSearch() {
    _controller.clear();
    _focusNode.unfocus();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    if (_query.isNotEmpty) setState(() => _query = '');
  }

  Future<void> _setShortFilter(AppSettings settings, bool value) async {
    try {
      await settings.setHideShortAudio(value);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this setting.')),
      );
    }
  }

  Widget _emptyState({
    required ColorScheme scheme,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? retry,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.10),
                ),
              ),
              child: Icon(icon, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 290),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            if (retry != null) ...[
              const SizedBox(height: 22),
              FilledButton.tonalIcon(
                onPressed: retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Scan again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _results(
    PlayerState player,
    List<Song> results,
    String query,
    ColorScheme scheme,
  ) {
    if (player.isLoadingLibrary) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
      );
    }

    if (player.libraryError != null) {
      return _emptyState(
        scheme: scheme,
        icon: Icons.info_outline_rounded,
        title: 'Could not load your music',
        subtitle: player.libraryError!,
        retry: () => player.loadLibrary(),
      );
    }

    if (player.songs.isEmpty) {
      return _emptyState(
        scheme: scheme,
        icon: Icons.library_music_outlined,
        title: 'No music found',
        subtitle: 'Songs stored on your device will appear here.',
        retry: () => player.loadLibrary(),
      );
    }

    if (results.isEmpty) {
      return _emptyState(
        scheme: scheme,
        icon: Icons.search_off_rounded,
        title: query.isEmpty ? 'No songs to show' : 'No matches',
        subtitle: query.isEmpty
            ? 'Turn off the short-audio filter to see all songs.'
            : 'Try another song title or artist name.',
      );
    }

    return ListView.separated(
      key: const PageStorageKey('songs-list'),
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        8,
        0,
        8,
        player.currentSong == null ? 24 : 120,
      ),
      itemCount: results.length,
      separatorBuilder: (_, index) => const SizedBox(height: 5),
      itemBuilder: (itemContext, index) {
        final song = results[index];

        return SongTile(
          key: ValueKey(song.id),
          song: song,
          accentColor: scheme.primary,
          isCurrent: player.currentSong?.id == song.id,
          isPlaying: player.playPauseShowsPause,
          onTap: () async {
            _focusNode.unfocus();

            try {
              await player.playFromLibrary(song, List<Song>.of(results));
            } catch (error) {
              debugPrint('Songs playback failed: $error');

              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not play this track.')),
              );
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final settings = context.watch<AppSettings>();
    final query = _query.trim();
    final songId = player.currentSong?.id;

    final results = filterAndSortSongs(
      applyShortAudioFilter(player.songs, enabled: settings.hideShortAudio),
      query,
      _sortOption,
    );

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
        final cached = songId == null
            ? null
            : ArtworkPaletteService.shared.peek(songId);

        final scheme = songId == null
            ? _defaultScheme
            : cached?.scheme ?? snapshot.data?.scheme ?? _defaultScheme;

        final reduceMotion = MediaQuery.of(context).disableAnimations;

        return AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 700),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.65],
              colors: [
                Color.lerp(
                  const Color(0xFF101115),
                  scheme.primaryContainer,
                  0.65,
                )!,
                const Color(0xFF101115),
              ],
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              toolbarHeight: 64,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: const Text('All Songs'),
            ),
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              top: false,
              child: GestureDetector(
                onTap: () => _focusNode.unfocus(),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  textInputAction: TextInputAction.search,
                                  cursorColor: scheme.primary,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Songs, artists…',
                                    filled: true,
                                    fillColor: Colors.white.withValues(
                                      alpha: 0.07,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search_rounded,
                                      color: scheme.primary,
                                    ),
                                    suffixIcon: _query.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear search',
                                            icon: const Icon(
                                              Icons.close_rounded,
                                            ),
                                            onPressed: clearSearch,
                                          ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.09,
                                        ),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: BorderSide(
                                        color: scheme.primary.withValues(
                                          alpha: 0.65,
                                        ),
                                      ),
                                    ),
                                  ),
                                  onChanged: (value) =>
                                      setState(() => _query = value),
                                  onSubmitted: (_) => _focusNode.unfocus(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              PopupMenuButton<_SongListAction>(
                                tooltip: 'Sort and filter songs',
                                icon: const Icon(Icons.sort_rounded),
                                onSelected: (action) async {
                                  switch (action) {
                                    case _SongListAction.sortTitle:
                                      setState(
                                        () => _sortOption = SortOption.title,
                                      );
                                    case _SongListAction.sortArtist:
                                      setState(
                                        () => _sortOption = SortOption.artist,
                                      );
                                    case _SongListAction.toggleShortAudio:
                                      await _setShortFilter(
                                        settings,
                                        !settings.hideShortAudio,
                                      );
                                  }
                                },
                                itemBuilder: (_) => [
                                  CheckedPopupMenuItem(
                                    value: _SongListAction.sortTitle,
                                    checked: _sortOption == SortOption.title,
                                    child: const Text('Song title'),
                                  ),
                                  CheckedPopupMenuItem(
                                    value: _SongListAction.sortArtist,
                                    checked: _sortOption == SortOption.artist,
                                    child: const Text('Artist name'),
                                  ),
                                  const PopupMenuDivider(),
                                  CheckedPopupMenuItem(
                                    value: _SongListAction.toggleShortAudio,
                                    checked: settings.hideShortAudio,
                                    child: const Text(
                                      'Hide tracks under 30 seconds',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (settings.hideShortAudio)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: InputChip(
                                label: const Text(
                                  'Tracks under 30 seconds hidden',
                                ),
                                avatar: const Icon(
                                  Icons.filter_alt_rounded,
                                  size: 18,
                                ),
                                onDeleted: () =>
                                    _setShortFilter(settings, false),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${results.length} ${results.length == 1 ? 'song' : 'songs'}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _results(player, results, query, scheme)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
