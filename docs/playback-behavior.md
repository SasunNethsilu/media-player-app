# Playback behavior

`PlayerState` owns one `PlaybackSequence`. Its current entry determines the
selected song, upcoming queue and previous tracks. A loaded-entry identity
records which entry the audio engine actually loaded; it is not another queue.
Seeking and the playing indicator require that identity to match the selection.

## Requests and loading

- Native pause, load and seek operations run serially. An in-flight native
  operation is allowed to settle before another begins.
- A newer song selection supersedes older pending selections and their queued
  transport commands. Rapid Next/Previous commands within the same selection
  retain their sequence steps, while obsolete intermediate loads may be skipped.
- Superseded loads cannot start audio, record Recently Played, or report an error
  against a newer request. Errors from an older source's play future are ignored.
- The old audio is paused before a new source is loaded. While loading, the UI
  keeps the selected track's title and artist visible, clears the previous timeline,
  disables seeking, and uses Pause to cancel automatic startup. Pressing Play
  afterward starts the selected track.
- Now Playing artwork is scoped to the selected song. An uncached new song shows
  a placeholder until its artwork is ready; a late result for an older song
  cannot replace it. Artwork still uses `ArtworkPaletteService.shared`.

## Failed tracks

- Missing files, decoder/load failures and runtime audio failures stop playback
  on the selected track and show an error in Now Playing and the mini player.
- There is no automatic skip or retry after failure, including under Repeat one
  or Repeat all. This prevents loops through one or more unreadable tracks.
- Play retries the selected track once per user action. Next, Previous or
  selecting another song can leave the failed track. A successful load clears
  the error. A failed load is not added to Recently Played.
- Failures do not delete files or edit saved playlists, queue membership,
  shuffle/repeat settings or the active playlist identity. An automatic advance
  may select an unreadable next track, but stops there without consuming the rest
  of the queue.

## Completion and exhausted queues

- Repeat off advances through upcoming songs and then pauses at the end of the
  final track, retaining its metadata and playback sequence.
- Play after exhaustion restarts that final track from zero if nothing is
  upcoming. If songs were added after exhaustion, Play starts the first upcoming
  song instead. Adding songs by itself does not restart stopped playback.
- Repeat one restarts the current song on completion; manual Next still advances.
- Repeat all wraps the full active sequence, including previously played entries.
- Previous restarts after three seconds; otherwise it moves backward and wraps
  only under Repeat all. Seeking a completed track to an earlier position keeps
  it paused until Play is pressed.
- Clear upcoming keeps the current track playing and removes upcoming entries
  from the active sequence. Repeat remains unchanged and can cycle retained
  entries. Removed entries do not reappear on repeat.

## Preserved behavior and lifecycle

Shuffle only rearranges upcoming entries. Disabling it restores the remaining
unshuffled order. Saved playlist edits remain independent of the active sequence.
Queue reordering, swipe removal and intentional duplicate occurrences retain
stable entry identities. Starting another playlist changes `activePlaylistId`;
queue editing and retrying do not.

Disposal invalidates pending requests, cancels all audio subscriptions and
disposes the audio player. Late futures cannot resume audio, record tracks or
notify listeners after disposal. Playback state remains session-only.

Regression tests use a controllable audio test double to delay loads and seeks,
inject missing-file and playback errors, and check source/metadata identity,
completion, queue edits and disposal. They do not replace testing on an Android
device with actual local audio files and media controls.
