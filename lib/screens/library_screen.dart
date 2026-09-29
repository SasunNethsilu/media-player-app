import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_state.dart';
import '../services/song_filter.dart';
import '../widgets/song_artwork.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  SortOption _sortOption = SortOption.title;

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      if (mounted) {
        context.read<PlayerState>().loadLibrary();
      }
    });
  }

  Widget _message({
    required IconData icon,
    required String text,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerState = context.watch<PlayerState>();
    final sortedSongs = filterAndSortSongs(
      playerState.songs,
      '',
      _sortOption,
    );

    Widget body;

    if (playerState.isLoadingLibrary) {
      body = const Center(child: CircularProgressIndicator());
    } else if (playerState.libraryError != null) {
      body = _message(
        icon: Icons.info_outline,
        text: playerState.libraryError!,
        buttonLabel: 'Try again',
        onPressed: () {
          playerState.loadLibrary();
        },
      );
    } else if (sortedSongs.isEmpty) {
      body = _message(
        icon: Icons.library_music_outlined,
        text: 'No music found on your device.',
        buttonLabel: 'Scan again',
        onPressed: () {
          playerState.loadLibrary();
        },
      );
    } else {
      body = RefreshIndicator(
        onRefresh: playerState.loadLibrary,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: sortedSongs.length,
          itemBuilder: (context, index) {
            final song = sortedSongs[index];

            return ListTile(
              key: ValueKey(song.id),
              leading: SongArtwork(
                songId: song.id,
                size: 48,
                borderRadius: 4,
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
              onTap: () {
                playerState.playFromLibrary(song, sortedSongs);
              },
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Library'),
        actions: [
          PopupMenuButton<SortOption>(
            icon: const Icon(Icons.sort),
            onSelected: (option) {
              setState(() => _sortOption = option);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: SortOption.title,
                child: Text('Sort by Title'),
              ),
              PopupMenuItem(
                value: SortOption.artist,
                child: Text('Sort by Artist'),
              ),
            ],
          ),
        ],
      ),
      body: body,
    );
  }
}