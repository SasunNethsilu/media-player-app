import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/player_state.dart';
import '../screens/now_playing_screen.dart';
import 'song_artwork.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playerState = context.watch<PlayerState>();
    final song = playerState.currentSong;

    if (song == null) return const SizedBox.shrink();

    return _MiniPlayerCard(
      song: song,
      playerState: playerState,
    );
  }
}

class _MiniPlayerCard extends StatefulWidget {
  final Song song;
  final PlayerState playerState;

  const _MiniPlayerCard({
    required this.song,
    required this.playerState,
  });

  @override
  State<_MiniPlayerCard> createState() => _MiniPlayerCardState();
}

class _MiniPlayerCardState extends State<_MiniPlayerCard> {
  static final ColorScheme _fallbackScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF7189B8),
    brightness: Brightness.dark,
  );

  static final Map<int, ColorScheme> _paletteCache = {};

  ColorScheme _scheme = _fallbackScheme;
  int _colourRequest = 0;
  bool _openingPlayer = false;

  @override
  void initState() {
    super.initState();
    _loadColours();
  }

  @override
  void didUpdateWidget(covariant _MiniPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.song.id != widget.song.id) {
      _loadColours();
    }
  }

  Future<void> _loadColours() async {
    final request = ++_colourRequest;
    final songId = widget.song.id;

    final cached = _paletteCache[songId];

    if (cached != null) {
      _scheme = cached;
      return;
    }

    ColorScheme scheme = _fallbackScheme;

    try {
      final bytes = await OnAudioQuery().queryArtwork(
        songId,
        ArtworkType.AUDIO,
        size: 800,
        quality: 100,
      );

      if (!mounted || request != _colourRequest) return;

      if (bytes != null && bytes.isNotEmpty) {
        scheme = await ColorScheme.fromImageProvider(
          provider: MemoryImage(bytes),
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
        );
      }

      if (!mounted || request != _colourRequest) return;

      if (_paletteCache.length >= 24) {
        _paletteCache.remove(_paletteCache.keys.first);
      }

      _paletteCache[songId] = scheme;
    } catch (error) {
      debugPrint('Mini-player colour extraction failed: $error');
    }

    if (!mounted || request != _colourRequest) return;

    setState(() => _scheme = scheme);
  }

  Future<void> _openPlayer() async {
    if (_openingPlayer) return;

    _openingPlayer = true;
    FocusScope.of(context).unfocus();

    final reduceMotion = MediaQuery.of(context).disableAnimations;

    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          transitionDuration: Duration(
            milliseconds: reduceMotion ? 0 : 380,
          ),
          reverseTransitionDuration: Duration(
            milliseconds: reduceMotion ? 0 : 300,
          ),
          pageBuilder: (_, animation, secondaryAnimation) {
            return NowPlayingScreen(
              initialColorScheme: _scheme,
            );
          },
          transitionsBuilder: (
            context,
            animation,
            secondaryAnimation,
            child,
          ) {
            final slide = animation.drive(
              Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).chain(
                CurveTween(curve: Curves.easeOutCubic),
              ),
            );

            return SlideTransition(
              position: slide,
              child: child,
            );
          },
        ),
      );
    } finally {
      _openingPlayer = false;
    }
  }

  Widget _buildProgress() {
    final player = widget.playerState.player;

    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      initialData: player.duration,
      builder: (context, durationSnapshot) {
        final totalMs =
            (durationSnapshot.data ?? Duration.zero).inMilliseconds;

        return StreamBuilder<Duration>(
          stream: player.positionStream,
          initialData: player.position,
          builder: (context, positionSnapshot) {
            final positionMs =
                (positionSnapshot.data ?? Duration.zero).inMilliseconds;

            final progress = totalMs <= 0
                ? 0.0
                : (positionMs / totalMs).clamp(0.0, 1.0).toDouble();

            return SizedBox(
              height: 2,
              width: double.infinity,
              child: ColoredBox(
                color: Colors.white12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    heightFactor: 1,
                    child: ColoredBox(color: _scheme.primary),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.playerState;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final leftColour = Color.lerp(
      _scheme.primaryContainer,
      const Color(0xFF15171C),
      0.30,
    )!;

    final rightColour = Color.lerp(
      _scheme.secondaryContainer,
      const Color(0xFF15171C),
      0.65,
    )!;

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: AnimatedContainer(
          duration: Duration(milliseconds: reduceMotion ? 0 : 700),
          curve: Curves.easeInOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [leftColour, rightColour],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openPlayer,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                      child: Row(
                        children: [
                          SongArtwork(
                            songId: widget.song.id,
                            size: 46,
                            borderRadius: 10,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Previous',
                            iconSize: 25,
                            color: Colors.white,
                            onPressed: () => state.playPrevious(),
                            icon: const Icon(Icons.skip_previous_rounded),
                          ),
                          IconButton(
                            tooltip: state.playing ? 'Pause' : 'Play',
                            style: IconButton.styleFrom(
                              backgroundColor: _scheme.primary,
                              foregroundColor: _scheme.onPrimary,
                              shape: const CircleBorder(),
                            ),
                            onPressed: state.togglePlayPause,
                            icon: AnimatedSwitcher(
                              duration: Duration(
                                milliseconds: reduceMotion ? 0 : 180,
                              ),
                              child: Icon(
                                state.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                key: ValueKey(state.playing),
                                size: 27,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip:
                                state.queue.isEmpty ? 'No next song' : 'Next',
                            iconSize: 25,
                            color: Colors.white,
                            disabledColor: Colors.white24,
                            onPressed: state.queue.isEmpty
                                ? null
                                : () => state.playNext(),
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                        ],
                      ),
                    ),
                    _buildProgress(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}