# J.A.R.V.I.S — Native Android App (built from your phone, no PC)

This is a real **Flutter/Dart** app — a proper Android app, not a website.
Since building an APK needs a full Android/Flutter toolchain, and that's
too heavy to run from a phone directly, this uses **GitHub Actions**: a
free cloud service that builds the APK for you. You only ever use your
phone's browser — GitHub's servers do the actual compiling.

## What's real vs. what needs your phone

| Feature | How it works |
|---|---|
| Voice input | Your phone's real mic (`speech_to_text` — native Android speech engine) |
| Voice output | Your phone's real speaker, male voice preferred, selectable |
| Weather | Real GPS location + live Open-Meteo data |
| Notes & Reminders | Saved on-device |
| **Alarms/Reminders** | **Real native Android notifications** — fire even if the app is in the background (a genuine improvement over the earlier web version) |
| Quick-open apps | Opens the real installed apps (YouTube, Spotify, Chrome, etc.) via Android intents |
| "Play <song>" | Deep-links straight into the Spotify app |
| "Search for X" | Deep-links straight into Chrome |
| Ask anything | Free AI (Gemini if you add a free key in-app, otherwise a free keyless fallback) |

## Step-by-step: build the APK from your phone only

### 1. Create a free GitHub account
Open **github.com** in your phone's browser, sign up (free, no card).

### 2. Create a new repository
Tap **+** → **New repository**. Name it e.g. `jarvis-app`. Keep it Public
(GitHub Actions' free minutes are more generous on public repos). Tap
**Create repository**.

### 3. Add three files (typed paths auto-create the folders)
On the repo page: **Add file → Create new file**.

- In the file name box, type: `pubspec.yaml` — paste the contents of the
  `pubspec.yaml` file from this download — then **Commit changes**.
- Repeat: **Add file → Create new file**, name it `lib/main.dart` (typing
  the `lib/` prefix automatically creates that folder) — paste the contents
  of `lib/main.dart` — **Commit changes**.
- Repeat once more: name it `.github/workflows/build-apk.yml` — paste the
  contents of that file — **Commit changes**.

Committing this last file automatically **triggers the build** — you don't
need to do anything else to start it.

### 4. Watch the build run
Tap the **Actions** tab at the top of your repo. You'll see a run in
progress (a yellow dot). It takes about 5–8 minutes. Wait for it to turn
into a green checkmark ✅.

If it turns red ❌, tap into the run to see which step failed — see
"If the build fails" below.

### 5. Download the APK
Open the finished (green) run, scroll down to **Artifacts**, and tap
**jarvis-apk** to download it. It downloads as a `.zip` — your phone's
Files app can usually extract it directly (tap the zip → Extract), giving
you `app-release.apk`.

### 6. Install it
Tap `app-release.apk` in your Files app. Android will ask permission to
"install unknown apps" from your browser/files app the first time — allow
it, then tap **Install**. J.A.R.V.I.S now sits on your home screen as a
real app, no browser involved.

## If the build fails

Open the failed run and read the red step's log — the two most common
causes:
- **Flutter version drift**: package versions in `pubspec.yaml` sometimes
  need a newer Flutter than the workflow pins. Edit
  `.github/workflows/build-apk.yml` in your repo, bump the
  `flutter-version:` line to a newer version (check
  **docs.flutter.dev/release/archive** for the latest stable), commit, and
  it'll rebuild automatically.
- **A single package needs an update**: the error will name the package.
  In `pubspec.yaml`, bump that package's version number, commit, and it
  rebuilds.

You can always re-trigger a build without changing anything by going to
**Actions → Build JARVIS APK → Run workflow**.

## About the AI

Same as the web version: free keyless AI by default, or add your own free
Gemini key (get one at **aistudio.google.com/apikey**, no card needed) in
the app's **AI ENGINE** section for better answers — it's stored only on
your phone.

## Files in this project

```
pubspec.yaml                          ← dependencies
lib/main.dart                          ← the entire app
.github/workflows/build-apk.yml        ← the cloud build recipe
```

The `android/`, `ios/` platform folders are deliberately **not** included —
the workflow generates a fresh one every build (via `flutter create`),
which avoids the folders going stale as Flutter itself updates.
