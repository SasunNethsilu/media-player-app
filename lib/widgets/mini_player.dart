import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_state.dart';
import '../screens/now_playing_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playerState = context.watch<PlayerState>();
    final song = playerState.currentSong;

    if (song == null) return const SizedBox.shrink();

    
    return GestureDetector(
      onTap: () {
        Navigator.push(context,
         MaterialPageRoute(builder: (context) => const NowPlayingScreen())
         );
      },
      child: Container(
        height: 64,
        color: Colors.grey[900],
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title, 
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),),
                  Text(song.artist, 
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              )
              ),
              IconButton(
              icon: Icon(
                playerState.playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,),
              onPressed: () => playerState.togglePlayPause(),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );

  }
}