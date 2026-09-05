## Shipping

There is no Xcode project, on purpose — Pulse is a plain package, and
[Scripts/bundle.sh](../../Scripts/bundle.sh) is what turns its bare executable into
something macOS treats as an app. That is not tidiness: **without a bundle
there is no `Bundle.main`**, which means no version number to compare against
(so no update check), no `SMAppService` login item (hence the launch-agent
fallback in [LoginItem.swift](../../Sources/Pulse/LoginItem.swift)), and nothing to
hand anyone but a build folder.

- **Pushing a tag is the whole release.**

  ```bash
  # CHANGELOG.md first — see below. Then:
  echo 1.0.1 > VERSION && git commit -am "Pulse 1.0.1"
  git tag v1.0.1 && git push && git push origin v1.0.1
  ```

  **[CHANGELOG.md](../../CHANGELOG.md) needs a `## 1.0.1` section before the tag
  goes up**, and the run stops without one — *before* it builds or publishes,
  so a forgotten entry costs a re-tag rather than a release whose notes went
  out wrong. They are not decoration: the same words are the top of the GitHub
  release *and* the text Sparkle shows in the update window of every installed
  copy, so this is the one part of a release nobody else can write for you. The
  fallback to commit subjects in [Scripts/appcast.py](../../Scripts/appcast.py) is
  for older versions and hand runs, not for this.

  [`.github/workflows/release.yml`](../../.github/workflows/release.yml) builds,
  packages and publishes, then signs the archive and commits the Sparkle feed;
  [`ci.yml`](../../.github/workflows/ci.yml) runs the same build on every push. The
  release needs one secret, `SPARKLE_PRIVATE_KEY`, and fails loudly without it
  rather than publishing a version no installed copy would ever be offered. Both pin **`macos-26`** rather than `macos-latest`,
  because `PanelSurface`'s Liquid Glass needs the macOS 26 SDK to compile at
  all even though it is behind an `#available` check — an older image cannot
  build the package, so both workflows check `xcrun --show-sdk-version` first
  and fail with that sentence instead of a hundred lines of "cannot find
  glassEffect". Warnings fail the build, for the reason at the top of this
  file.   **The tag is checked against `VERSION`** and a mismatch fails the run: ship
  them out of step and every installed copy is told, forever, that an update is
  waiting. A tag with a suffix (`v1.1.0-beta.1`) is published as a pre-release,
  which GitHub's "latest release" excludes — and so, therefore, does the update
  check.
- The version lives in [VERSION](../../VERSION) and nowhere else. Tag the release
  `v$(cat VERSION)`: the update check reads GitHub's latest release tag and
  compares it against `CFBundleShortVersionString`, so the two have to agree.
- The package's resource bundle must land in `Contents/Resources` —
  `Bundle.module` looks there through `Bundle.main.resourceURL`. Leave it out
  and the app runs, silently in English, with no provider marks.
- `LSUIElement` must be **true**. The code also sets `.accessory`, but that runs
  after the Dock has already been told what to show, so without the key a Dock
  icon appears for a moment at every launch.
- Built for both architectures (`--arch arm64 --arch x86_64`), so one download
  runs everywhere, and zipped with `ditto`, not `zip` — a plain zip flattens the
  symlinks in a bundle and the unzipped copy won't launch.
- **The output directory is named `build.noindex/` for a reason.** Spotlight
  indexes an `.app` wherever it finds one, so a build sitting in the project
  folder turns up in Launchpad and search beside the installed copy — two
  identical Pulses with no way to tell them apart. Worse, whichever one is
  *opened* claims the login item and rewrites Claude Code's status line path to
  itself, so deleting the build later breaks both.
  A `.noindex` suffix is the convention Spotlight honours and the one Xcode's
  own DerivedData relies on. A `.metadata_never_index` marker file was tried
  first and did **not** work — the build was indexed anyway — so the marker is
  kept as a second line but the directory name is what does the job. Don't
  rename it back.
- **The disk image is the install guide** ([Scripts/dmg.sh](../../Scripts/dmg.sh)).
  Because Pulse isn't notarised, macOS blocks the first launch and the user has
  to allow it by hand — and on macOS 15 and later the old Control-click → Open
  bypass is gone, so it can only be done in System Settings › Privacy & Security
  › Open Anyway. Instructions that live only in a README are instructions nobody
  downloading an app ever reads, so they are printed on the window itself.
  Finder stores the window's size, backdrop and icon positions in a `.DS_Store`,
  and AppleScript is the only way to *write* one — which needs a logged-in
  desktop and permission to drive Finder, neither of which a CI runner has. So
  the layout is captured once on a real Mac
  ([Scripts/dmg-DS_Store](../../Scripts/dmg-DS_Store)) and copied into the staging
  folder, and the build touches Finder only when that file is missing. Verified
  identical both ways. Re-capture it with `./Scripts/dmg.sh --relayout` after
  changing the backdrop or the icon positions, and commit the result. Note Finder's window `bounds` **include the title bar**,
  so the window is 28pt taller than the 660×420 backdrop or its bottom line is
  cut off. The backdrop is [Scripts/dmg-background.tiff](../../Scripts/dmg-background.tiff),
  carrying a 1x and a 2x representation; replace the file to redesign it.
- The ad-hoc signature is **not** distribution signing. It stops macOS calling
  the bundle damaged when it is moved; it does nothing for Gatekeeper, which
  will still warn on first open until there is a Developer ID and notarisation.

**Running from a bundle moves the `UserDefaults` domain**, and that is the sharp
edge of this whole change. `UserDefaults.standard` writes to a domain named
after the bundle identifier, or — with no bundle — after the process name. So
every loose `swift run` build has been keeping its settings in a domain called
`Pulse`, and `Pulse.app` reads an empty one: panel position, enabled providers,
language, *and the flag that says opening at login was already decided*. It
would look like a fresh install and would switch login-at-start back on for
someone who had turned it off.
[LegacyDefaults.swift](../../Sources/Pulse/LegacyDefaults.swift) copies the old domain
across once, taking only keys the new domain doesn't already have. After that
the two diverge, which is right: an Xcode build and an installed `Pulse.app` are
two copies of the app and shouldn't edit each other's settings.
`LoginItem.adoptBundleIfNeeded` is the same problem in the other direction — a
launch agent left over from a loose build still names the old binary, so at the
next login launchd starts the old build *and* `SMAppService` starts the new one.

**Updates install themselves, through Sparkle**
([AppUpdate.swift](../../Sources/Pulse/AppUpdate.swift)). The thing that makes this
safe without an Apple Developer ID is the **EdDSA key**: Sparkle refuses any
archive not signed by the private half of the key whose public half is in
`Info.plist`, whoever served it. Apple's signing and notarisation are
*recommended* by Sparkle rather than required — that was got wrong here once,
and the mistake cost a whole release cycle of "wait until there's a Developer
ID". The one thing notarisation would fix, Gatekeeper blocking the **first**
launch, is not something any updater can help with.

**The update window's notes are carried in the feed, not fetched from GitHub.** They used to be a `sparkle:releaseNotesLink` pointing at the release page — which is not a link the user clicks: Sparkle loads it into a WebView *inside* the update window, so the whole GitHub page, navigation and all, was rendered in a small panel, and showed nothing at all without a network. The item carries a `<description>` instead, and the link has to be **removed** for it to be used: `releaseNotesLink` takes precedence when both are present.
What goes in it is hand-written, in [CHANGELOG.md](../../CHANGELOG.md), and [Scripts/changelog.py](../../Scripts/changelog.py) converts the one version's entry to HTML for the feed while [`release.yml`](../../.github/workflows/release.yml) puts the same markdown at the top of the GitHub release — one source, so the two cannot drift. Generating it from commit subjects was tried and is wrong: this repository takes direct commits, so the range runs to forty subjects a release and half of them say things like "Update README". That path is kept only as a fallback, so a forgotten entry ships something rather than an empty dialog. The converter knows bullets, `**bold**`, `` `code` `` and links, and nothing else — the file is ours, so its grammar can be small enough to be sure of.
The description carries **spacing only, no colours and no fonts**: Sparkle injects `ReleaseNotesColorStyle.css`, which turns the text white under `prefers-color-scheme: dark` and leaves the background transparent so the window shows through. A feed that brings its own palette fights that and loses in whichever appearance it guessed wrong about — verified by rendering the description in a `WKWebView` with Sparkle's own stylesheet applied, in both appearances.

The private key lives only in the `SPARKLE_PRIVATE_KEY` repository secret;
`Scripts/sparkle-public-key.txt` holds the public half and is meant to be
committed. [Scripts/appcast.py](../../Scripts/appcast.py) signs each release's zip
and appends an entry to [appcast.xml](../../appcast.xml), which the release workflow
commits back to `main` — **after** publishing, since the feed points at the
release's own asset and committing first would advertise a 404. Sparkle updates
from the **zip**, not the disk image; the image is for people, the zip is for
the updater.

Three things about the Swift side. `AppUpdate` starts nothing unless
`SUFeedURL` is present, which is only true in a bundle — Sparkle's framework is
in `Contents/Frameworks` and a `swift run` build has neither, so starting it
there would log complaints about a missing feed forever. Sparkle's delegate is
an `@objc` protocol and so cannot be main-actor-isolated, which is why
`UpdaterRelay` sits between it and the `@Observable` model rather than
`AppUpdate` conforming directly. And `didAbortWithError` fires for benign
reasons too — the user closing Sparkle's window is one — so only a genuine
failure to reach or read the feed is reported as one, on the single row that
exists to tell the truth about that.

**Embedding the framework is the fiddly part of the bundle.** SwiftPM links
against Sparkle but has no app to put it in, so `Scripts/bundle.sh` copies it
into `Contents/Frameworks` and adds `@executable_path/../Frameworks` to the
executable's rpath — SwiftPM only ever pointed that at the build directory, and
without the addition the app launches straight into a dyld failure. Signing then
has to run inside out: Sparkle brings nested bundles of its own (XPC services
and its updater app), and signing a container before its contents invalidates
the container.

Note the settings group that holds the *usage* refresh interval is called
"Refresh", not "Updates". It was "Updates" until the app had updates of its own.
