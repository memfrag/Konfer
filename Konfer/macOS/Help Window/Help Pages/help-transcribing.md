# Transcribing a File

Drop an audio or video file, or a voice memo, onto the Konfer window. You can also choose **Transcribe Recording…** from the **+** menu in the sidebar. Dropping a file on a folder in the sidebar files the meeting there. A recording you have just made goes straight to the same sheet.

## The Transcribe sheet

**Language.** Say which language the meeting is in. Konfer never guesses, because a wrong guess doesn't give you a slightly worse transcript. It gives you a different one. The language also decides which model does the work:

| Language | Model |
|---|---|
| English, German, Spanish, French, Italian, Portuguese | Apple Speech, or Whisper Large v3 |
| Swedish | KB-Whisper Large |
| Danish, Dutch, Polish | Whisper Large v3 |

**Model.** This appears only for the languages that have a choice, and Konfer remembers your choice for each language. Apple Speech is about nine times faster and needs no download. Whisper is worth a try when Apple struggles with accents, jargon or poor audio.

If the model isn't downloaded yet, the sheet says how big it is and offers **Download…**. **Transcribe** stays unavailable until the model is there. See [Models and Storage](konfer-help:models).

**Folder.** Where the new meeting is filed.

**I know how many people spoke.** If you know the number of speakers, telling Konfer usually improves the result.

**The call came out of the speakers.** This appears only for recordings made in Konfer. Turn it on if you weren't wearing headphones. See [Recording a Meeting](konfer-help:recording).

**Trimming.** The waveform at the top lets you keep only part of the recording. Drag its handles past the small talk before and after the meeting. The play button lets you listen for where to cut, and **Reset** keeps the whole recording again.

## While it runs

The bottom of the sidebar shows the stage, the progress, and a button to stop. Recordings queue up and run one at a time. Transcription is heavy work, and running two at once wouldn't finish either any sooner.

A transcription can't be paused or resumed. Quitting Konfer while one is running discards it, and Konfer asks first.

If Konfer can't work out who spoke when, you still get the whole transcript, with every line attributed to an unknown speaker. The meeting says **Speakers weren't identified**, and the sidebar marks it with a warning triangle.

## Transcribing again

To run a meeting again, for example with another model, a speaker count or a trim, choose **Transcribe Again…** from the **…** menu beside the player. It replaces the transcript. Your title, folder and trim are kept, but hand edits and any translation are not.

If you drop a recording that has been transcribed before, the sheet offers to open the existing transcript instead.
