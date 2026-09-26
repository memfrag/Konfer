# Reading and Playback

A meeting opens as a list of turns. Each turn shows who spoke, when, and what they said. The speakers are listed at the top, each in their own colour. In a recording made in Konfer, an icon beside each speaker says whether they were in the room or on the call.

## Playing

- **Space** plays and pauses.
- **Click any word** to move the playhead to it. It's the quickest way to check a doubtful passage against the audio. Clicking a line's timestamp goes to the start of the line.
- **The waveform** is coloured by who is speaking, so you can see who talked most and where the long stretches are. Click or drag anywhere on it to seek.
- The word being spoken is highlighted as it plays, and the transcript scrolls to follow. Lines edited by hand, and translated lines, have no word timings, so they aren't highlighted word by word.

Clicking a word always seeks, so you can't select text by dragging while reading. To copy, right-click a line and choose **Copy Text** or **Copy with Speaker and Time**. The second gives you `[00:12:34] Anna: …`.

## Finding and replacing

- **Edit ▸ Find…** (⌘F) opens the find bar above the transcript.
- **Find Next** (⌘G) and **Find Previous** (⇧⌘G) step through the matches.
- **Replace** and **Replace All** correct a name or term that was misheard throughout. A replacement that spans more than one word marks that line as edited by hand, and the bar warns you first.

To search every meeting at once, use the search field at the top of the sidebar.

## Transcription cuts

With the Whisper models, a long recording is transcribed in a few parts side by side. **View ▸ Show Transcription Cuts** marks where those parts meet, as yellow lines on the waveform. It's useful if something looks odd right at a boundary. Apple Speech doesn't cut recordings this way.

## When the recording has moved

A meeting remembers where its audio file is but doesn't keep a copy. If the file has been moved or deleted, the meeting still opens and can still be edited, but it can't play: it says **Recording not found — playback unavailable**. Choose **Choose Recording…** to point it at the file's new location.
