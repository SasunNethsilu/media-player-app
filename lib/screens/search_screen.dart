import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/player_state.dart';
import '../services/artwork_palette_service.dart';
import '../services/song_filter.dart';
import '../widgets/song_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String _query = '';
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
    super.dispose();
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

    if (query.isEmpty) {
      return _emptyState(
        scheme: scheme,
        icon: Icons.manage_search_rounded,
        title: 'Find your next listen',
        subtitle: 'Search by song title or artist.',
      );
    }

    if (results.isEmpty) {
      return _emptyState(
        scheme: scheme,
        icon: Icons.search_off_rounded,
        title: 'No matches',
        subtitle: 'Try another song title or artist name.',
      );
    }

    return ListView.separated(
      key: const PageStorageKey('search-results'),
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
              debugPrint('Search playback failed: $error');

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
    final query = _query.trim();
    final songId = player.currentSong?.id;

    final results = query.isEmpty
        ? <Song>[]
        : filterAndSortSongs(player.songs, query, SortOption.title);

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

        final showResultsHeading =
            query.isNotEmpty &&
            results.isNotEmpty &&
            !player.isLoadingLibrary &&
            player.libraryError == null;

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
              title: const Text('Search'),
            ),
            resizeToAvoidBottomInset: false,
            body: SafeArea(
              top: false,
              child: GestureDetector(
                onTap: () => _focusNode.unfocus(),
                behavior: HitTestBehavior.opaque,
                child: NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              textInputAction: TextInputAction.search,
                              cursorColor: scheme.primary,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Songs, artists…',
                                hintStyle: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 16,
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.07),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 18,
                                ),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  color: scheme.primary,
                                  size: 24,
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 54,
                                  minHeight: 54,
                                ),
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          color: Colors.white60,
                                          size: 21,
                                        ),
                                        onPressed: () {
                                          _controller.clear();
                                          setState(() => _query = '');
                                          _focusNode.requestFocus();
                                        },
                                      ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.09),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide(
                                    color: scheme.primary.withValues(
                                      alpha: 0.65,
                                    ),
                                    width: 1.2,
                                  ),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() => _query = value);
                              },
                              onSubmitted: (_) => _focusNode.unfocus(),
                            ),
                          ),
                          if (showResultsHeading)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Results',
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${results.length} '
                                    '${results.length == 1 ? 'song' : 'songs'}',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  body: _results(player, results, query, scheme),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
