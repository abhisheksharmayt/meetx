# MeetX

MeetX is a native macOS desktop app for recording meeting audio and generating meeting artifacts. It detects Zoom and Google Meet calls, shows a small notch-style prompt to start transcribing, records microphone audio, and saves the recording, transcript, summary, notes, and metadata on your Desktop.

MeetX does not record your screen.

## Features

- Native macOS app with a main window and menu-bar controls.
- Notch-style `Start transcribing?` prompt when a meeting is detected.
- Google Meet detection for exact room links such as `https://meet.google.com/orr-crzx-vph`.
- Zoom detection when the Zoom app is active.
- Microphone-only `.m4a` recording.
- OpenAI-powered transcription and summarization.
- In-app meeting library for viewing summaries, notes, transcripts, settings, and folders.
- Auto-stop when the tracked Meet tab closes, the browser closes, the meeting disappears, the Mac sleeps, or the app quits.

## Requirements

- macOS 14 or newer.
- Xcode command line tools / Swift toolchain.
- OpenAI API key.
- macOS permissions:
  - Microphone
  - Notifications
  - Automation for Chrome, Safari, or Edge when using Google Meet detection

## Build

```sh
./Scripts/build-app.sh
```

The app bundle is created at:

```text
build/MeetX.app
```

Launch it with:

```sh
open build/MeetX.app
```

After rebuilding, restart a running copy with:

```sh
killall MeetX
open build/MeetX.app
```

## First Run

1. Open MeetX.
2. Go to the `Settings` tab in the app window.
3. Paste your OpenAI API key and save.
4. Keep the default models or update them:
   - Transcription: `gpt-4o-transcribe`
   - Summary: `gpt-5.5`
5. Allow requested macOS permissions.

The API key is stored in macOS Keychain.

## Using MeetX

For Google Meet, open a real meeting room URL:

```text
https://meet.google.com/orr-crzx-vph
```

MeetX intentionally does not trigger on the generic Meet homepage:

```text
https://meet.google.com/
```

When a meeting is detected, MeetX shows a notch-style prompt at the top of the screen. Choose `Start` to begin recording. While recording, macOS shows the microphone indicator. Use `Stop Transcribing` in the app window or `Stop & Summarize` from the menu-bar item to stop manually.

## Output

MeetX writes meeting folders to:

```text
~/Desktop/MeetX Meetings/
```

Folder naming:

- Meaningful meeting title:
  - `Project-Sync_2026-06-06_13-05-12`
- Generic or manual meeting:
  - `2026-06-06_13-05-12_Google-Meet`
  - `2026-06-06_13-05-12_Manual-Meeting`

Each meeting folder can contain:

- `recording.m4a`
- `transcript.txt`
- `summary.md`
- `notes.md`
- `metadata.json`
- `error.txt` if OpenAI processing fails

MeetX also writes a debug log at:

```text
~/Desktop/MeetX Meetings/meetx.log
```

## App Window

The main app window includes:

- A sidebar listing saved meeting folders.
- Recording status and a `Stop Transcribing` button.
- Tabs for `Summary`, `Notes`, `Transcript`, and `Settings`.
- An `Open Folder` button for the selected meeting.

## Troubleshooting

If a meeting is not detected:

- Confirm the URL is a real Meet room link like `https://meet.google.com/abc-defg-hij`.
- Allow Automation permission for the browser when macOS asks.
- Try restarting MeetX after changing permissions.

If the mic icon stays on:

- Click `Stop Transcribing` in the app window.
- Or use the menu-bar item and choose `Stop & Summarize`.
- If needed, run `killall MeetX`.

If a recording does not appear:

- Check `~/Desktop/MeetX Meetings/meetx.log`.
- Confirm `~/Desktop/MeetX Meetings/` exists and is writable.
- Check whether a folder was created with `error.txt`; audio may still be saved even if transcription failed.

## Project Structure

```text
Package.swift
Info.plist
Scripts/build-app.sh
Sources/MeetX/
voice-svgrepo-com.svg
```

Important source areas:

- `AppDelegate.swift`: app lifecycle, menu-bar controls, notifications.
- `MeetingDetector.swift`: Zoom and Google Meet detection.
- `NotchPromptController.swift`: notch-style start prompt.
- `AudioRecorder.swift`: microphone-only recording.
- `OpenAIClient.swift`: transcription and summarization calls.
- `MainWindowController.swift`: desktop GUI and meeting library.
- `MeetingProcessor.swift`: output folder and artifact writing.
