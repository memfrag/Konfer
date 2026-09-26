# Editing a Transcript

Both halves of the machinery make mistakes. One works out who spoke, the other what was said. So a transcript is a document you can correct, and every change is saved as you make it.

## Speakers

- **Rename.** Click a speaker at the top of the meeting and type their name. Every line of theirs follows.
- **Merge.** When one person came out as two speakers, right-click one of them and choose **Same Person As**. Their lines are joined under one name.
- **Reassign a line.** When a single line went to the wrong person, click the name above it and choose **Reassign to**.

Naming a speaker also teaches Konfer their voice. See [People](konfer-help:people).

## Lines

Right-click a line for the rest:

| Action | What it does |
|---|---|
| Edit Text… | Correct what was said. The line keeps its start and end times. |
| Delete Line | Remove the line. |
| Split at Playhead | Cut the line in two where the speaker actually changed. |
| Merge with Previous, Merge with Next | Join two lines the machine broke apart. The earlier line keeps its speaker. |

The merge buttons also appear in the margin when you hover over a line.

**Splitting.** The easiest way is to pause, click the word the new line should start with, and choose **Split before word**. **Split at Playhead** does the same for the line that is playing. A line whose text you have edited can't be split, because its words no longer have timings.

**Editing text.** Once you edit a line, its words are no longer the ones the model timed. The line then highlights as a whole during playback, and a pencil mark says it was edited by hand.

## Trimming

To hide the small talk before and after a meeting, choose **Trim…** from the **…** menu beside the player, drag the handles, and choose **Trim**. Nothing is deleted: the hidden lines are counted at the top and bottom of the transcript and can be shown again, and **Keep Everything** undoes the trim. Exports and searches cover only what you kept.

## Translations and edits

A translated line is made from the original line's text. Editing a line, or splitting or merging lines, throws away the affected translations, and **Translate the Rest** makes new ones. Renaming, merging and reassigning speakers leave translations alone. See [Translation](konfer-help:translation).
