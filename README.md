# ASCII Diagram Validator

A Perl script and Claude Code skill for validating ASCII box-drawing diagrams for alignment issues. Designed to be used standalone or as an automatic validation step whenever Claude creates ASCII diagrams.

## What It Does

`validate_ascii.pl` checks ASCII diagrams for:

1. **Consistent line widths** — all lines must have the same display width
2. **Box corner alignment** — nested boxes must have vertically aligned corners
3. **Vertical line continuity** — `│` characters must align across rows
4. **Horizontal connections** — corners must connect properly to horizontal lines
5. **Wide character detection** — warns about CJK/emoji characters that break alignment
6. **Forbidden characters** — flags long/double arrows (`⟶ ⇒`) that render wider than 1 column

Output includes `PASS`/`FAIL` status and actionable `FIX:` instructions for each issue.

## Requirements

- Perl 5.10+ (standard on macOS and most Linux distros)

## Installation

### 1. Install the validator script

```bash
cp validate_ascii.pl ~/.local/bin/validate_ascii.pl
chmod +x ~/.local/bin/validate_ascii.pl
```

Make sure `~/.local/bin` is in your `PATH`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc   # or ~/.bashrc
source ~/.zshrc
```

### 2. Install the Claude Code skill (optional)

Copy the skill into your Claude Code skills directory so Claude auto-validates diagrams it creates:

```bash
mkdir -p ~/.claude/skills/ascii-validator
cp .claude/skills/ascii-validator/SKILL.md ~/.claude/skills/ascii-validator/SKILL.md
```

## Usage

### Standalone

```bash
validate_ascii.pl diagram.txt
validate_ascii.pl diagrams/*.txt
```

### With a heredoc

```bash
cat > /tmp/diagram.txt << 'EOF'
┌─────────────────────┐
│  My ASCII Diagram   │
└─────────────────────┘
EOF

validate_ascii.pl /tmp/diagram.txt
```

### Example output

```
ASCII Diagram Validator
==============================================================================
Checking 1 file(s)...

File: /tmp/diagram.txt
==============================================================================
Status: FAIL
Lines: 3, Expected Width: 23 characters

Issues Found:
------------------------------------------------------------------------------
    1. Line   2, Col  23: [WIDTH_MISMATCH] Line has width 22, expected 23 (off by -1). FIX: Add 1 space(s) to pad this line to width 23

Summary
==============================================================================
Total files: 1
Passed: 0
Failed: 1
```

## Safe Box-Drawing Characters

```
Single line:  ─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼
Double line:  ═ ║ ╔ ╗ ╚ ╝ ╠ ╣ ╦ ╩ ╬
Heavy line:   ━ ┃ ┏ ┓ ┗ ┛
Rounded:      ╭ ╮ ╰ ╯
Arrows:       → ← ↑ ↓ ↔ ↕
```

## Characters to Avoid

```
NEVER:  ⟶ ⟵ ⟹ ⟸ ⟷ ⟺  (render 3-4x normal width)
AVOID:  ⇒ ⇐ ⇔ ⇑ ⇓        (render 1.5-2x normal width)
```

## Claude Code Skill

The included skill (`SKILL.md`) instructs Claude to automatically validate any ASCII diagram it creates or modifies and iterate until the validator reports `PASS`. It also handles diagrams embedded in mixed-content files (markdown, source code with comment blocks, etc.) by extracting, validating, fixing, and re-inserting diagram regions.

The skill is triggered automatically when Claude produces box-drawing characters — no manual invocation needed.

## Repository Layout

```
ascii-diagram-validator/
├── validate_ascii.pl                        # The validator tool
├── README.md                                # This file
└── .claude/
    └── skills/
        └── ascii-validator/
            └── SKILL.md                     # Claude Code skill definition
```
