# SONIQ — Android music player prototype

Functional Flutter source for an offline/local music player. It does **not** provide licensed global music streaming, real AI DJ, synced rooms or online lyrics.

## Build APK without a computer
1. Create a GitHub repository and upload the contents of this folder (not the ZIP itself).
2. Sign in to codemagic.io using GitHub, select the SONIQ repository.
3. Choose `codemagic.yaml` and start the `SONIQ Android APK` workflow.
4. Download the debug APK from build artifacts and install on Android. Allow installation from the source when prompted.

No APK has been compiled or device-tested in this environment. `flutter analyze` in the cloud build is the first automated check.

## Included
- Device audio import and app-private persistent copies
- Playback, pause, seek, skip, shuffle and repeat
- Favorites, playlists, queue, search and history saved locally
- Mood filtering of local tracks and a sleep timer
- Dark blue / mint responsive UI

Permissions and audio behavior vary by Android version. Background playback and lock-screen controls are not implemented in this first prototype.
