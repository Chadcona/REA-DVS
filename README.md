# OpenDeck

An independent, clean-room macOS DJ application foundation. It does not include,
link to, or modify Serato DJ Pro code, assets, settings, or file formats.

## Current slice

- SwiftUI two-deck mixer interface
- Local audio-file import on each deck
- Persistent OpenDeck-owned local track library, with load-to-deck controls
- Read-only music-folder scan that detects Serato marker tags without changing source files
- AVAudioEngine-backed play/pause, cue, pitch, and gain controls
- Loop, filter, sync, crossfader, waveform, and library state ready for their audio/data implementations

## Run

```sh
swift run
```

## Next slices

1. Decode Serato marker records into OpenDeck cue points and loops.
2. Analyze BPM and generate cached waveform data for imported audio.
3. Add named crates and persist controller mappings in OpenDeck-owned storage.
4. Add MIDI controller learning and effects.
