# Exporting

Choose **File ▸ Export**, use the **Export** button in the meeting's toolbar, or right-click the meeting in the sidebar and choose **Export**.

| Format | What you get |
|---|---|
| Markdown | A readable transcript, each line as `[00:12:34] Anna: …` |
| JSON | Speakers, timings and text, with the translation if there is one |
| WebVTT Subtitles | A `.vtt` file for web players |
| SubRip Subtitles | An `.srt` file for most video players and editors |
| Video with Subtitles | A copy of the recording with the subtitles inside it, for QuickTime Player |

Every export includes your edits and only the part of the meeting you kept. See [Editing a Transcript](konfer-help:editing).

## Subtitles

Subtitles are cut where the words were spoken, at most two lines and six seconds at a time. The speaker is named at the start of each of their turns.

**Video with Subtitles** copies the recording and adds a subtitle track. Nothing is re-encoded, and the original file is left alone. It needs a recording with a picture, and one Konfer can still find. If the meeting is trimmed, you can trim the video to match.

## In the translation's language

When a meeting has a translation, the Export menu has a submenu named after its language, such as **Export in English**. It offers Markdown, both subtitle formats and the subtitled video in that language. JSON isn't in it, because the ordinary JSON export already carries both languages.

Translated subtitles keep the original's timings. Each translated line is spread across the cues its original was cut into, so every start and end time comes from the recording.
