import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings.dart';
import '../providers/player_state.dart';
import '../services/artwork_palette_service.dart';
import '../widgets/mini_player.dart';

const appVersion = '1.0.0+1';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _scanning = false;
  String? _scanMessage;
  bool _scanFailed = false;
  int? _paletteSongId;
  Future<SongVisuals>? _paletteFuture;

  Future<void> _rescan() async {
    final player = context.read<PlayerState>();
    if (_scanning || player.isLoadingLibrary) return;
    setState(() {
      _scanning = true;
      _scanMessage = null;
    });
    Object? failure;
    try {
      await player.loadLibrary();
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _scanFailed = failure != null || player.libraryError != null;
      _scanMessage =
          player.libraryError ??
          (failure != null
              ? 'Could not scan your music. Please try again.'
              : 'Scan complete · ${player.songs.length} ${player.songs.length == 1 ? 'song' : 'songs'} found');
    });
  }

  Future<void> _save(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save this setting. Try again.'),
        ),
      );
    }
  }

  Widget _section(String title, Widget child, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
          child: Text(
            title,
            style: TextStyle(
              color: scheme.primary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Material(
          color: Colors.white.withValues(alpha: 0.055),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final settings = context.watch<AppSettings>();
    final songId = player.currentSong?.id;
    final busy = _scanning || player.isLoadingLibrary;

    if (songId != _paletteSongId) {
      _paletteSongId = songId;
      _paletteFuture = songId == null
          ? null
          : ArtworkPaletteService.shared.load(songId);
    }

    return FutureBuilder<SongVisuals>(
      key: ValueKey(songId),
      future: _paletteFuture,
      initialData: songId == null
          ? null
          : ArtworkPaletteService.shared.peek(songId),
      builder: (context, snapshot) {
        final scheme = songId == null
            ? Theme.of(context).colorScheme
            : ArtworkPaletteService.shared.peek(songId)?.scheme ??
                  snapshot.data?.scheme ??
                  ArtworkPaletteService.fallbackScheme;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);

        return Theme(
          data: Theme.of(context).copyWith(colorScheme: scheme),
          child: AnimatedContainer(
            duration: Duration(milliseconds: reduceMotion ? 0 : 700),
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
              extendBody: true,
              appBar: AppBar(
                toolbarHeight: 64,
                backgroundColor: Colors.transparent,
                title: const Text('Settings'),
              ),
              body: MiniPlayerOverlay(
                child: SafeArea(
                  top: false,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      player.currentSong == null ? 32 : 120,
                    ),
                    children: [
                      _section(
                        'Library',
                        Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                16,
                                6,
                                12,
                                6,
                              ),
                              leading: busy
                                  ? SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.primary,
                                      ),
                                    )
                                  : Icon(
                                      Icons.refresh_rounded,
                                      color: scheme.primary,
                                    ),
                              title: const Text('Rescan local library'),
                              subtitle: Text(
                                busy
                                    ? 'Scanning audio on this device…'
                                    : 'Look for added or removed audio files.',
                              ),
                              onTap: busy ? null : _rescan,
                            ),
                            if (_scanMessage != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _scanMessage!,
                                    style: TextStyle(
                                      color: _scanFailed
                                          ? scheme.error
                                          : scheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SwitchListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                12,
                                8,
                              ),
                              title: const Text('Hide short audio'),
                              subtitle: const Text(
                                'Hide tracks under 30 seconds from Songs, Albums and Artists. Files and playlists are unchanged.',
                              ),
                              value: settings.hideShortAudio,
                              onChanged: (value) => _save(
                                () => settings.setHideShortAudio(value),
                              ),
                            ),
                          ],
                        ),
                        scheme,
                      ),
                      const SizedBox(height: 20),
                      _section(
                        'Playback',
                        SwitchListTile(
                          contentPadding: const EdgeInsets.fromLTRB(
                            16,
                            8,
                            12,
                            8,
                          ),
                          title: const Text('Restore playback session'),
                          subtitle: const Text(
                            'After the library loads, reopen the last track, queue and position paused. Never starts playing automatically. Changes to this setting take effect on the next app launch.',
                          ),
                          value: settings.restorePlaybackSession,
                          onChanged: (value) => _save(
                            () => settings.setRestorePlaybackSession(value),
                          ),
                        ),
                        scheme,
                      ),
                      const SizedBox(height: 20),
                      _section(
                        'About',
                        const Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                              title: Text('Music Player'),
                              subtitle: Text(
                                'Plays audio stored on this device.',
                              ),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                              title: Text('App version'),
                              trailing: Text(appVersion),
                            ),
                          ],
                        ),
                        scheme,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
