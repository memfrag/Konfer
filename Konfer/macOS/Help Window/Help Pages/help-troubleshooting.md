# Troubleshooting

## The other side of the call is silent

When macOS refuses permission to record system audio, it doesn't report an error. It just hands Konfer silence. That is why the recorder warns **Nothing is coming from the other side** after a few seconds.

Open **System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording** and allow Konfer. If you record a single app, make sure it is the app actually playing the call. See [Recording a Meeting](konfer-help:recording).

## People on the call are listed as being in the room

The microphone heard the call through your speakers. Use headphones next time. For this recording, choose **Transcribe Again…** from the **…** menu beside the player, and turn on **The call came out of the speakers**.

## Transcribe is greyed out

The model for the language you chose hasn't been downloaded. The sheet names it and offers to download it. See [Models and Storage](konfer-help:models).

## The transcript is in the wrong language, or makes no sense

Check the language shown in the bar above the transcript. Konfer transcribes in the language you choose, and a Swedish meeting transcribed as English comes out as something else entirely. Choose **Transcribe Again…** with the right language.

## "Speakers weren't identified"

Konfer couldn't tell the voices apart, so every line is attributed to one unknown speaker. The text and timings are complete. Try **Transcribe Again…**, with **I know how many people spoke** turned on if you know the number.

## One person came out as two speakers, or two as one

Merge the two with **Same Person As**. For two people as one, reassign their lines, or transcribe again with **I know how many people spoke** turned on. See [Editing a Transcript](konfer-help:editing).

## Words are missing

Check **Settings ▸ Transcription ▸ Faster, less complete**. It drops speech. Turn it off and choose **Transcribe Again…**.

## The meeting says "Recording not found"

The audio file has moved. Choose **Choose Recording…** and point the meeting at the file's new location. The transcript is unaffected either way.

## A translation isn't offered

macOS can't translate between Polish and either Swedish or Danish. For other pairs, download the language pack when the Translate sheet offers it. See [Translation](konfer-help:translation).

## Video with Subtitles is greyed out

The recording is audio only, or Konfer can no longer find it. Subtitles need a picture to sit on.
