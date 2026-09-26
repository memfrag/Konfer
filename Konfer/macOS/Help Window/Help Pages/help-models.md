# Models and Storage

Konfer downloads its speech models once, only when you ask. After that it never needs the internet.

| Model | Used for | Size |
|---|---|---|
| Speaker identification | Working out who spoke when, in every language | 22 MB |
| KB-Whisper Large | Swedish | 2.9 GB |
| Røst v3 | Danish | 1.6 GB |
| Whisper Large v3 | Dutch and Polish, and as the alternative for Danish and Apple's six languages | 3.1 GB |

English, German, Spanish, French, Italian and Portuguese use Apple Speech unless you choose otherwise. macOS installs that itself the first time you use a language, so it isn't listed here.

## Downloading

**Window ▸ Models** lists every model with its state. Download them one by one, or choose **Download All**. Downloads run one at a time, and you can stop and retry them.

<view tag="open-window" window="model-downloads" label="Open Model Downloads"/>

You don't need to plan ahead. If you choose a language whose model is missing, the Transcribe sheet says so and offers to download it.

## Settings

**Settings ▸ Models** shows how much space the models take. **Manage Models…** opens the list above, and **Delete Models** removes every downloaded model at once. The next transcription that needs one downloads it again. To remove a single model, use **Delete** in the Models window. Models can't be deleted while a transcription is running.

**Settings ▸ Transcription** shows which model each language uses and roughly how long an hour of audio takes with it. It also has two settings:

- **File new meetings in:** chooses whether the Transcribe sheet's folder starts at **The top level** of the library or at **The folder selected in the sidebar**.
- **Faster, less complete** transcribes in parallel chunks, roughly twice as fast, but it drops speech, and not predictably. Leave it off unless you only need a rough idea of what was said. Transcripts made this way are marked.

<view tag="open-settings" label="Open Settings…"/>
