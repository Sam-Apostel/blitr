# Setting up blitr in a coding agent's environment

These steps are written for a coding agent (Claude Code, Codex, Cursor and the like) that was asked to set up
blitr for the project it is working in. blitr renders SwiftUI source to PNG without Xcode or a simulator, so the
agent can look at the screens it changes. Do each step, then tell the user what you installed and where.

## 1. Install the command

Check first: `blitr doctor`. If it works, go to step 3.

- **macOS with Homebrew:** `brew install sam-apostel/blitr/blitr`. Needs Xcode or the Command Line Tools
  (`xcode-select --install`).
- **Linux, as root or with sudo** (cloud containers, CI):
  `curl -fsSL https://github.com/Sam-Apostel/blitr/releases/latest/download/install.sh | bash`.
  It installs blitr into `/opt/blitr` and the Swift toolchain it needs into `/opt/swift` (about 1 GB).
- **Anywhere with Node 22 or newer, no root needed:** `npm install -g @apostel/blitr`. Its first run downloads
  the release, and on Linux the Swift toolchain, into `~/.cache/blitr`.

## 2. Make it survive a new session

A cloud environment is usually rebuilt for each session, so the install has to run again every time.

- If the environment has a setup script you can edit (a `Dockerfile`, a devcontainer, a CI setup step), add the
  Linux install line from step 1 there.
- Claude Code on the web: the setup script lives in the environment's settings, which you cannot edit. Give the
  user the install line and ask them to add it there.
- On the user's own Mac nothing is needed: Homebrew and npm installs stay.

## 3. Add the skill

Save the skill into the project, so every session of every agent working on it knows how to use blitr:

```
mkdir -p .claude/skills/blitr
curl -fsSL https://raw.githubusercontent.com/Sam-Apostel/blitr/main/integrations/claude-skill/blitr/SKILL.md \
  -o .claude/skills/blitr/SKILL.md
```

For an agent that reads `AGENTS.md` instead of Claude Code skills, add a short section there with the gist of
the skill: render with `blitr render <file> --all --scheme both --out-dir /tmp/shots`, look at the PNGs, and
read every `warning:` line.

## 4. Check it works

1. `blitr doctor` reports no problem.
2. Find a SwiftUI file with a `#Preview` in the project and render it:
   `blitr render <file> --all --out-dir /tmp/blitr-check`.
3. Open the PNG and look at it. If the compile fails on an API the renderer lacks, that is a limit of blitr, not
   of the project: do not change the project's code; try another file.

## 5. Report

Tell the user: how blitr was installed, whether it will be there next session (and what they need to add if
not), where the skill file is, and the image you rendered. Leave committing the skill file to them.
