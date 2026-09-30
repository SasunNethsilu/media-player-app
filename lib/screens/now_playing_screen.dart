import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/artwork_palette_service.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/player_state.dart';
import 'queue_screen.dart';

class NowPlayingScreen extends StatelessWidget {
  final ColorScheme? initialColorScheme;

  const NowPlayingScreen({
    super.key,
    this.initialColorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final playerState = context.watch<PlayerState>();
    final song = playerState.currentSong;

    if (song == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nothing playing')),
      );
    }

    return _TrackPlayer(
      song: song,
      playerState: playerState,
      initialColorScheme: initialColorScheme,
    );
  }
}

class _TrackPlayer extends StatefulWidget {
  final Song song;
  final PlayerState playerState;
  final ColorScheme? initialColorScheme;

  const _TrackPlayer({
    required this.song,
    required this.playerState,
    this.initialColorScheme,
  });

  @override
  State<_TrackPlayer> createState() => _TrackPlayerState();
}

class _TrackPlayerState extends State<_TrackPlayer> {
  ColorScheme _scheme = ArtworkPaletteService.fallbackScheme;

  Uint8List? _artwork;
  double? _dragPosition;
  int? _artworkSongId;
  int _visualRequest = 0;

  @override
  void initState() {
    super.initState();

    final cached = ArtworkPaletteService.shared.peek(widget.song.id);

    _scheme = cached?.scheme ??
        widget.initialColorScheme ??
        ArtworkPaletteService.fallbackScheme;

    _artwork = cached?.artwork;
    _artworkSongId = cached == null ? null : widget.song.id;

    _loadVisuals();
  }

  @override
  void didUpdateWidget(covariant _TrackPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.song.id != widget.song.id) {
      _dragPosition = null;
      _loadVisuals();
    }
  }

  Future<void> _loadVisuals() async {
    final request = ++_visualRequest;
    final songId = widget.song.id;

    final visuals = await ArtworkPaletteService.shared.load(songId);

    if (!mounted || request != _visualRequest) return;

    final bytes = visuals.artwork;
    bool imageFailed = false;

    if (bytes != null) {
      await precacheImage(
        MemoryImage(bytes),
        context,
        onError: (Object error, StackTrace? stackTrace) {
          imageFailed = true;
          debugPrint('Artwork decoding failed for $songId: $error');
        },
      );
    }

    if (!mounted || request != _visualRequest) return;

    setState(() {
      _artwork = imageFailed ? null : bytes;
      _artworkSongId = songId;
      _scheme = visuals.scheme;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  void _openQueue() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const QueueScreen(),
      ),
    );
  }

  Widget _buildArtwork(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 40,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: _artwork == null
              ? _artworkPlaceholder(size)
              : Image.memory(
                  _artwork!,
                  key: ValueKey('art-$_artworkSongId'),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stackTrace) {
                    return _artworkPlaceholder(size);
                  },
                ),
        ),
      ),
    );
  }

  Widget _artworkPlaceholder(double size) {
    return Container(
      key: const ValueKey('artwork-placeholder'),
      width: size,
      height: size,
      color: const Color(0xFF242833),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.28,
        color: Colors.white38,
      ),
    );
  }

  Widget _buildProgress() {
    final player = widget.playerState.player;

    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      initialData: player.duration,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        final totalMs = duration.inMilliseconds.toDouble();

        return StreamBuilder<Duration>(
          stream: player.positionStream,
          initialData: player.position,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;

            final displayedMs = (_dragPosition ??
                    position.inMilliseconds.toDouble())
                .clamp(0.0, totalMs)
                .toDouble();

            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: _scheme.primary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white10,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                  ),
                  child: Slider(
                    value: displayedMs,
                    min: 0,
                    max: totalMs > 0 ? totalMs : 1,
                    onChanged: totalMs <= 0
                        ? null
                        : (value) {
                            setState(() => _dragPosition = value);
                          },
                    onChangeEnd: totalMs <= 0
                        ? null
                        : (value) async {
                            final songId = widget.song.id;

                            try {
                              await player.seek(
                                Duration(milliseconds: value.round()),
                              );
                            } catch (error) {
                              debugPrint('Seek failed: $error');
                            } finally {
                              if (mounted && widget.song.id == songId) {
                                setState(() => _dragPosition = null);
                              }
                            }
                          },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(
                          Duration(milliseconds: displayedMs.round()),
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                      Text(
                        _formatDuration(duration),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControls() {
    final state = widget.playerState;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Previous',
          iconSize: 38,
          color: Colors.white,
          onPressed: () => state.playPrevious(),
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        SizedBox(
          width: 78,
          height: 78,
          child: Material(
            color: _scheme.primary,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: state.togglePlayPause,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    state.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    key: ValueKey(state.playing),
                    size: 44,
                    color: _scheme.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: state.queue.isEmpty ? 'No next song' : 'Next',
          iconSize: 38,
          color: Colors.white,
          disabledColor: Colors.white24,
          onPressed: state.queue.isEmpty
              ? null
              : () => state.playNext(),
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final topColour = Color.lerp(
      _scheme.primaryContainer,
      _scheme.primary,
      0.22,
    )!;

    final middleColour = Color.lerp(
      _scheme.secondaryContainer,
      const Color(0xFF101116),
      0.55,
    )!;

    final bottomColour = Color.lerp(
      _scheme.tertiaryContainer,
      const Color(0xFF08090C),
      0.85,
    )!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: bottomColour,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF08090C),
        body: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    topColour,
                    middleColour,
                    bottomColour,
                  ],
                  stops: const [0, 0.52, 1],
                ),
              ),
            ),

            AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.7, -0.55),
                  radius: 1.1,
                  colors: [
                    _scheme.primary.withValues(alpha: 0.16),
                    _scheme.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Close player',
                          color: Colors.white,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 32,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Expanded(
                          child: Text(
                            'NOW PLAYING',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.2,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Open queue',
                          color: Colors.white,
                          icon: const Icon(Icons.queue_music_rounded),
                          onPressed: _openQueue,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final contentWidth = math.min(
                          constraints.maxWidth,
                          480.0,
                        );

                        final artworkSize = math.min(
                          contentWidth - 56,
                          math.max(180.0, constraints.maxHeight * 0.49),
                        );

                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Center(
                              child: SizedBox(
                                width: contentWidth,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    28,
                                    24,
                                    28,
                                    28,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Center(
                                        child: _buildArtwork(artworkSize),
                                      ),
                                      const SizedBox(height: 36),
                                      Text(
                                        widget.song.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.7,
                                          height: 1.15,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        widget.song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 22),
                                      _buildProgress(),
                                      const SizedBox(height: 26),
                                      _buildControls(),
                                      const SizedBox(height: 28),
                                      Center(
                                        child: TextButton.icon(
                                          onPressed: _openQueue,
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.white70,
                                            backgroundColor: Colors.white10,
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 10,
                                            ),
                                            shape: const StadiumBorder(),
                                          ),
                                          icon: const Icon(
                                            Icons.queue_music_rounded,
                                            size: 19,
                                          ),
                                          label: Text(
                                            widget.playerState.queue.isEmpty
                                                ? 'View queue'
                                                : 'Up next · '
                                                    '${widget.playerState.queue.length}',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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
}