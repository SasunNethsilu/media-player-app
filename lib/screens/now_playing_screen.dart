import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_state.dart';
import 'queue_screen.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(1, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final playerState = context.watch<PlayerState>();
    final song = playerState.currentSong;

    if (song == null) {
      return const Scaffold(body: Center(child: Text('Nothing playing')));
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () {
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => const QueueScreen()));
            },)
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.music_note, size: 80, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Text(song.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(song.artist, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),


            StreamBuilder<Duration>(
              stream: playerState.player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final duration = playerState.player.duration ?? Duration.zero;

                return Column(
                  children: [
                    Slider(
                      value: position.inMilliseconds
                          .clamp(0, duration.inMilliseconds)
                          .toDouble(),
                      max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                      onChanged: (value) {
                        playerState.player.seek(Duration(milliseconds: value.toInt()));
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(position)),
                          Text(_formatDuration(duration)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),
            IconButton(
              iconSize: 56,
              icon: Icon(playerState.playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
              onPressed: () => playerState.togglePlayPause(),
            ),
          ],
        ),
      ),
    );
  }
}