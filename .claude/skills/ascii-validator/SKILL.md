---
name: ascii-validator
description: Validate ASCII diagram alignment and iteratively fix issues. Use this skill automatically whenever you create an ASCII diagram to ensure proper alignment of box-drawing characters, corners, and vertical/horizontal lines.
allowed-tools: Bash, Read, Write, Edit
---

# ASCII Diagram Alignment Validator

This skill validates ASCII diagrams for alignment issues using the `validate_ascii.pl` Perl script and iteratively corrects problems until validation passes.

## When to Use

**IMPORTANT**: Use this skill automatically whenever you create or modify an ASCII diagram that uses box-drawing characters (─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ etc.).

## Validation Tool

The validator is located at `~/.local/bin/validate_ascii.pl` and checks:

1. **Consistent line widths** - All lines must be the same display width
2. **Box corner alignment** - Nested boxes must have vertically aligned corners
3. **Vertical line continuity** - │ characters must align across rows
4. **Horizontal connections** - Corners must connect properly to horizontal lines
5. **Wide character detection** - Warns about CJK/emoji characters that break alignment

## Workflow

### Step 1: Create the Diagram

Write the ASCII diagram to a temporary file:

```bash
cat > /tmp/ascii-diagram.txt << 'EOF'
┌─────────────────────────────────────┐
│ Your diagram content here           │
└─────────────────────────────────────┘
EOF
```

### Step 2: Validate

Run the validator:

```bash
~/.local/bin/validate_ascii.pl /tmp/ascii-diagram.txt
```

### Step 3: Fix Issues

The validator provides actionable error messages with explicit FIX instructions:

- **FORBIDDEN_CHAR_CRITICAL/HIGH/MEDIUM**: Forbidden character detected
  - Example: `Forbidden character '⟶' (U+27F6) renders at 3-4x normal width. FIX: Replace with '──→' or '-->'`

- **WIDTH_MISMATCH**: Line width differs from expected
  - Example: `Line has width 54, expected 55 (off by -1). FIX: Add 1 space(s) to pad this line to width 55`

- **VERTICAL_MISALIGNED**: Vertical lines don't align
  - Example: `Vertical '│' at column 55 should align with '│' above (line 7, column 54). FIX: Move '│' on line 8 left by 1 position(s) to column 54`

- **BOX_CORNER_MISALIGNED**: Box corners don't align vertically
  - Example: `Bottom-left corner '└' at column 3 should align with top-left '┌' at line 1, column 4. FIX: Move '└' right by 1 position(s) to column 4`

- **WIDE_CHAR**: Double-width character (CJK, emoji) detected
  - Example: `Wide character '中' (U+4E2D) occupies 2 columns but counts as 1 character. FIX: Replace with ASCII equivalent`

### Step 4: Re-validate

After making corrections, run the validator again. Repeat steps 3-4 until the validator reports `PASS`.

## Example Session

```bash
$ ~/.local/bin/validate_ascii.pl /tmp/diagram.txt
File: /tmp/diagram.txt
Status: FAIL
Issues Found:
  1. Line 6, Col 16: [FORBIDDEN_CHAR_CRITICAL] Forbidden character '⟶' (U+27F6) renders at 3-4x normal width. FIX: Replace with '──→' or '-->'
  2. Line 5, Col 55: [WIDTH_MISMATCH] Line has width 54, expected 55 (off by -1). FIX: Add 1 space(s) to pad this line to width 55

# Fix: Replace ⟶ with ──→ and add padding spaces
# Re-validate until PASS
```

## Safe Box-Drawing Characters

Use these characters for reliable alignment:

```
Single line:  ─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼
Double line:  ═ ║ ╔ ╗ ╚ ╝ ╠ ╣ ╦ ╩ ╬
Heavy line:   ━ ┃ ┏ ┓ ┗ ┛
Rounded:      ╭ ╮ ╰ ╯
Arrows:       → ← ↑ ↓ ↔ ↕
```

## Characters to AVOID

These cause alignment issues in most fonts:

```
NEVER:  ⟶ ⟵ ⟹ ⟸ ⟷ ⟺  (3-4x width)
AVOID:  ⇒ ⇐ ⇔ ⇑ ⇓        (1.5-2x width)
```

## Working with Mixed-Content Files

When the file containing an ASCII diagram is not purely a diagram (e.g., a markdown file with embedded diagrams, a README, or a source file with diagram comments), follow these steps:

### Step 1: Identify Diagram Boundaries

Look for diagram regions bounded by:
- **Code fences:** ` ```  ` blocks (the diagram is the content between fences)
- **Box-drawing characters:** Contiguous lines containing `─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ ═ ║` etc.
- **Comment blocks:** Lines prefixed with `//`, `#`, or `*` that contain box-drawing characters

Note the **start line**, **end line**, and **indentation prefix** (e.g., 4 spaces, or `// `) for each diagram region.

### Step 2: Extract Each Diagram

For each identified diagram region:

1. Extract the diagram lines to a temporary file, stripping any common prefix (indentation, comment markers)
2. Preserve the original line numbers for re-insertion

```bash
# Example: extract lines 138-156 from README.md, stripping no prefix
sed -n '138,156p' README.md > /tmp/ascii-diagram.txt
```

### Step 3: Validate and Fix Iteratively

Run the validator on the extracted diagram:

```bash
~/.local/bin/validate_ascii.pl /tmp/ascii-diagram.txt
```

Fix issues as described in the standard workflow (Steps 3-4 above). Repeat until `PASS`.

### Step 4: Re-insert into Original File

Replace the original diagram region with the fixed version:

1. Re-apply any stripped prefix (indentation, comment markers) to each line
2. Preserve the code fence markers, surrounding text, and overall file structure
3. Use the Edit tool to replace the old diagram block with the fixed one

**Important:** Only modify the diagram content itself. Never alter:
- Code fence markers (` ``` `)
- Surrounding prose or headings
- Indentation of non-diagram lines
- File encoding or line endings

### Multiple Diagrams

If a file contains multiple diagram regions, process each one independently. Extract, validate, fix, and re-insert one at a time to avoid cross-contamination of fixes.

## Tips

1. **Pad all lines**: Every line should have the same display width
2. **Count carefully**: Use a monospace editor to verify alignment visually
3. **Test iteratively**: Validate after each significant change
4. **Check nested boxes**: Inner boxes must align with outer box corners
