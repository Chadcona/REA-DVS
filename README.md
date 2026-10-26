# OpenDeck

An independent, clean-room macOS DJ application foundation. It does not include,
link to, or modify Serato DJ Pro code, assets, settings, or file formats.

## Current slice

- SwiftUI two-deck mixer interface
- Local audio-file import on each deck
- Persistent OpenDeck-owned local track library, with load-to-deck controls
- Read-only music-folder scan that detects Serato marker tags without changing source files
- Initial `Serato Markers2` cue and saved-loop import for compatible local files (positions, names, colours, and loop lock state)
- Persisted waveform peak analysis rendered on the deck for imported and directly loaded local audio
- Local onset/autocorrelation BPM estimate, displayed as an estimate and used to seed deck sync
- Persistent named OpenDeck crates with library filtering and add-to-crate controls
- Per-deck audio effects: DJ filter, echo, and reverb wired into AVAudioEngine
- AVAudioEngine-backed play/pause, cue, pitch, and gain controls
- Loop, filter, sync, crossfader, waveform, and library state ready for their audio/data implementations

## Run

```sh
swift run
```

## Next slices

1. Expand Serato import to additional tag containers and crate membership.
2. Add beat-grid-aware waveform navigation and manual BPM correction.
3. Persist controller mappings in OpenDeck-owned storage.
4. Add MIDI controller learning and effect parameter mapping.
