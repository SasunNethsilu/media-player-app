import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/artwork_palette_service.dart';

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

    return _MiniPlayerCard(song: song, playerState: playerState);
  }
}

class MiniPlayerOverlay extends StatelessWidget {
  final Widget child;

  const MiniPlayerOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(top: false, child: MiniPlayer()),
        ),
      ],
    );
  }
}

class _MiniPlayerCard extends StatefulWidget {
  final Song song;
  final PlayerState playerState;

  const _MiniPlayerCard({required this.song, required this.playerState});

  @override
  State<_MiniPlayerCard> createState() => _MiniPlayerCardState();
}

class _MiniPlayerCardState extends State<_MiniPlayerCard> {
  ColorScheme _scheme = ArtworkPaletteService.fallbackScheme;

  int _colourRequest = 0;
  int? _prefetchedNextId;

  bool _openingPlayer = false;
  bool _coloursReady = false;

  @override
  void initState() {
    super.initState();
    _loadColours();
    _preloadNext();
  }

  @override
  void didUpdateWidget(covariant _MiniPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.song.id != widget.song.id) {
      _scheme = ArtworkPaletteService.fallbackScheme;
      _coloursReady = false;
      _loadColours();
    }

    _preloadNext();
  }

  Future<void> _loadColours() async {
    final request = ++_colourRequest;
    final songId = widget.song.id;
    final service = ArtworkPaletteService.shared;

    final cached = service.peek(songId);

    if (cached != null) {
      _scheme = cached.scheme;
      _coloursReady = true;
      _precacheNowPlayingArtwork(cached.artwork);
      return;
    }

    final visuals = await service.load(songId);

    if (!mounted || request != _colourRequest) return;

    _precacheNowPlayingArtwork(visuals.artwork);

    setState(() {
      _scheme = visuals.scheme;
      _coloursReady = true;
    });
  }

  void _precacheNowPlayingArtwork(Uint8List? artwork) {
    if (artwork == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        precacheImage(
          MemoryImage(artwork),
          context,
          onError: (Object error, StackTrace? stackTrace) {},
        ),
      );
    });
  }

  void _preloadNext() {
    final queue = widget.playerState.queue;
    final nextId = queue.isEmpty ? null : queue.first.id;

    if (nextId == _prefetchedNextId) return;

    _prefetchedNextId = nextId;

    if (nextId != null) {
      ArtworkPaletteService.shared.preload(nextId);
    }
  }

  Future<void> _openPlayer() async {
    if (_openingPlayer) return;

    _openingPlayer = true;
    FocusScope.of(context).unfocus();

    final reduceMotion = MediaQuery.of(context).disableAnimations;

    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          transitionDuration: Duration(milliseconds: reduceMotion ? 0 : 380),
          reverseTransitionDuration: Duration(
            milliseconds: reduceMotion ? 0 : 300,
          ),
          pageBuilder: (_, animation, secondaryAnimation) {
            return NowPlayingScreen(
              initialColorScheme: _coloursReady ? _scheme : null,
            );
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final slide = animation.drive(
              Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOutCubic)),
            );

            return SlideTransition(position: slide, child: child);
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
        final totalMs = widget.playerState.canSeek
            ? (durationSnapshot.data ?? Duration.zero).inMilliseconds
            : 0;

        return StreamBuilder<Duration>(
          stream: player.positionStream,
          initialData: player.position,
          builder: (context, positionSnapshot) {
            final positionMs = widget.playerState.canSeek
                ? (positionSnapshot.data ?? Duration.zero).inMilliseconds
                : 0;

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
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                                  state.playbackError != null
                                      ? 'Unable to play · Tap to view'
                                      : widget.song.artist,
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
                            tooltip: state.playPauseShowsPause
                                ? 'Pause'
                                : 'Play',
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
                                state.playPauseShowsPause
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                key: ValueKey(state.playPauseShowsPause),
                                size: 27,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: state.canGoNext ? 'Next' : 'No next song',
                            iconSize: 25,
                            color: Colors.white,
                            disabledColor: Colors.white24,
                            onPressed: !state.canGoNext
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
