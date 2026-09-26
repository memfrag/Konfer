# Getting Started

Konfer turns a recording of a meeting into a transcript. Every line has a timestamp and says who spoke it. It works in ten languages and can translate between them.

Everything happens on your Mac. The recording, the transcript and the translation never leave it. The only thing Konfer fetches from the internet is its speech models, once, and only when you ask for them.

## The first time

The welcome window asks **Which languages do you record in?** Some languages are handled by speech recognition built into macOS, and others need a model Konfer downloads. Tick your languages and choose **Download**, and Konfer fetches whatever they need. **Skip** leaves it for later.

<view tag="open-window" window="model-downloads" label="Open Model Downloads"/>

## Three ways in

- **Record a meeting.** Choose **File ▸ New Recording…** (⇧⌘R). See [Recording a Meeting](konfer-help:recording).
- **Transcribe a file you already have.** Drop an audio or video file, or a voice memo, onto the Konfer window. See [Transcribing a File](konfer-help:transcribing).
- **Import a transcript.** Drop a JSON transcript onto the window: one Konfer exported, or one from the Klang app. Nothing needs to be transcribed, so it arrives at once, without playback until you point it at its recording. See [Exporting](konfer-help:exporting).

## What happens next

A transcription runs in the background, and the bottom of the sidebar shows its progress. Konfer first works out who spoke when, then what they said, and then puts the two together. With Apple's recognition an hour of audio takes a minute or two. With the downloaded models it takes about ten minutes.

When it's done, the meeting appears in the sidebar and opens. From there you can [read and play it back](konfer-help:reading), [fix what the machine got wrong](konfer-help:editing), [translate it](konfer-help:translation) and [export it](konfer-help:exporting).

## Meetings and folders

Each meeting is a file in Konfer's library, `~/Library/Application Support/Konfer/Meetings/`. Folders you make in the sidebar are real folders on disk.

- **+** beside **Meetings** adds a meeting or a **New Folder**.
- Drag meetings onto a folder to file them there, or right-click a meeting and choose **Move To**.
- Right-click a meeting to **Rename** it, show its files in Finder, or **Delete** it. Deleting removes the transcript but not the recording.
- Deleting a folder moves what was in it up a level.
- The search field at the top of the sidebar searches every transcript, including speaker names.

Konfer doesn't copy your recordings into the library. A meeting remembers where its audio file is.
