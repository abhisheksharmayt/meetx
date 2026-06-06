# MeetX

MeetX is a native macOS desktop and menu-bar app that detects Zoom and Google Meet calls, prompts you to record, records meeting audio, and writes a transcript, summary, notes, metadata, and raw audio to your Desktop.

## Build

```sh
./Scripts/build-app.sh
```

The app bundle is created at:

```text
build/MeetX.app
```

Launch it with Finder or:

```sh
open build/MeetX.app
```

## First Run

1. Open `MeetX`; the main window shows your meeting library and settings.
2. Add your OpenAI API key.
3. Keep the default models or edit them:
   - Transcription: `gpt-4o-transcribe`
   - Summary: `gpt-5.5`
4. Grant macOS permissions when prompted:
   - Notifications
   - Microphone
   - Automation for supported browsers

## Output

MeetX writes each processed meeting to:

```text
~/Desktop/MeetX Meetings/YYYY-MM-DD_HH-mm-ss_<meeting-name>/
```

Each folder contains:

- `recording.m4a`
- `transcript.txt`
- `summary.md`
- `notes.md`
- `metadata.json`
- `error.txt` if processing fails after recording

## App Window

The main MeetX window includes:

- A sidebar of saved meeting folders from `~/Desktop/MeetX Meetings`.
- Built-in views for `Summary`, `Notes`, and `Transcript`.
- An `Open Folder` button for the selected meeting.
- A `Settings` tab for the OpenAI API key and model names.

## Notes

- MeetX records microphone audio only. It does not record your screen.
- Google Meet detection uses browser automation to read the active tab URL in Safari, Chrome, and Edge.
