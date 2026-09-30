# dreamscape-pass — the house FreeRDP

The Mac's RDP client for Mage M's console, which GNOME Desktop Sharing mirrors. It is a fork of
[FreeRDP/FreeRDP](https://github.com/FreeRDP/FreeRDP), named after the Penacony pass that lets
you walk into someone else's dream while your body stays home. The launcher that uses it is
hexenzirkel `scripts/mage-m-desktop.sh` (`m-desktop`, "M Desktop" in Spotlight). That launcher
prefers this build's install prefix and falls back to Homebrew's `sdl-freerdp`.

## Branches

| Branch | What it is | Base |
|---|---|---|
| `main` | what the Mac runs: the release Homebrew ships, plus the house patches and this file | tag `3.32.1` |
| `fix/sdl-macos-display-probe` | the upstream PR, kept rebased on upstream `master` | `upstream/master` |
| `master` | upstream's master, untouched | — |

## Patches carried on `main`

| Patch | Why | Upstream |
|---|---|---|
| `[client,sdl] query macOS display geometry without a probe window` | At start-up the SDL client probed each display with a visible full-screen window. With SDL's default, the Spaces slid away and back (8 active-Space changes in one launch); with `SDL_VIDEO_MAC_FULLSCREEN_SPACES=0`, each display flashed black instead. After the patch: 0 windows and 0 changes, and every monitor field is identical to before. | [FreeRDP#13564](https://github.com/FreeRDP/FreeRDP/pull/13564), opened 2026-09-30 |

When upstream releases a version that contains a patch, that patch leaves `main`. Once `main`
carries nothing, retire the prefix, and `m-desktop` falls back to Homebrew's client on its own.

## Doors

```bash
just build                    # configure + build with Apple clang against Homebrew's libraries (Homebrew's LLVM fails on std::free)
just install                  # into ~/.local/opt/dreamscape-pass, then print the installed version
just probe [--spaces 0]       # the installed client: start-up windows and Space changes against a closed local port
just probe-binary <path>      # the same probe for any client binary (an unpatched one flashes the screen)
just upstream                 # the PR's state and the newest upstream tags
```

- **Remotes:** `origin` is `oceanzhang88/dreamscape-pass`, the GitHub fork the PR comes from. `upstream` is `FreeRDP/FreeRDP`, with push `DISABLED`.
- **Identity:** commits in this repo use the GitHub no-reply identity from the repo-local git config, because they land in public upstream history.
- **New release:** `git fetch upstream --tags`, then `git rebase --onto <new-tag> <old-tag> main`. Then run `just install` and `just probe`, and update the base tag in the table above.
- **Upstream contributions:** a branch cut from `upstream/master`, formatted with `git clang-format --diff upstream/master`, following FreeRDP's `.github/PULL_REQUEST_TEMPLATE.md`. The PR says that an AI assistant helped prepare the change.
- **The probe:** `house/startup-probe.swift` polls the active Space (read-only `CGSGetActiveSpace`) and the client PID's windows (`CGWindowListCopyWindowInfo`). A client that shows any window before connecting fails it. Each run of an unpatched client flashes the screen, so keep those runs few.
