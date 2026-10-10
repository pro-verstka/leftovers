# leftovers

Terminal UI for macOS that finds files left behind by uninstalled apps — preferences, caches, containers, launch agents, helpers — and moves the ones you pick to the Trash.

Single Swift file, no dependencies.

## Install

Download the latest release (universal binary, macOS 12+):

```sh
mkdir -p ~/.local/bin
curl -fsSL https://github.com/pro-verstka/leftovers/releases/latest/download/leftovers-macos.tar.gz | tar -xz -C ~/.local/bin
```

The binary is not notarized. If you download it with a browser instead of `curl`, run `xattr -d com.apple.quarantine ~/.local/bin/leftovers`.

Or build from source (requires Xcode or the Command Line Tools):

```sh
make install          # builds and copies to ~/.local/bin
make install PREFIX=/usr/local
```

## Usage

```sh
leftovers             # interactive, scans ~/Library and /Library
sudo leftovers        # also lets you remove items in /Library
leftovers --list      # print path, size, date and exit
leftovers --version   # print version
```

| Key | Action |
| --- | --- |
| `↑` `↓` / `j` `k` | move |
| `PgUp` `PgDn` `g` `G` | page / top / bottom |
| `space` | select |
| `a` | select all / none |
| `o` | reveal in Finder |
| `d` / `Enter` | move selected to Trash (asks `y/N`) |
| `q` | quit |

## How it works

It builds an index of what is installed: app bundles (Spotlight plus `/Applications`, `~/Applications`, `/opt`), their bundle IDs, nested helpers, app groups and team IDs from code signatures, executables on `PATH`, and system daemons. Then it scans `~/Library` and `/Library` (Application Support, Caches, Containers, Group Containers, Preferences, Logs, LaunchAgents/Daemons, PrivilegedHelperTools, …) and lists entries that match nothing installed. A launchd plist is listed when its program no longer exists.

Matching is heuristic. Check the list before deleting anything. Nothing is deleted outright: items are moved to `~/.Trash`, so you can drag them back.

Containers and Group Containers are protected by macOS. Their size shows as `?`, and moving them may need Full Disk Access for your terminal.

## Test

```sh
make test
```

## Release

Push a tag. GitHub Actions builds the universal binary and publishes it to Releases.

```sh
git tag v0.1.0
git push origin v0.1.0
```

`make dist` builds the same archive locally into `dist/`.
