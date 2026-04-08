#!/usr/bin/env perl
#
# validate_ascii.pl - Validates ASCII diagrams for alignment issues
#
# This script checks:
# 1. Consistent line widths
# 2. Misaligned box-drawing characters
# 3. Vertical line alignment across rows
# 4. Horizontal line connections
# 5. Variable-width Unicode characters (CJK, emoji)
# 6. Forbidden characters (long arrows, double arrows that render wide)
# 7. Nested box alignment (corners and walls must align vertically)
# 8. Vertical line continuity
#

use strict;
use warnings;
use utf8;
use open qw(:std :utf8);

# ANSI color codes for output
my $RED    = "\e[31m";
my $GREEN  = "\e[32m";
my $YELLOW = "\e[33m";
my $CYAN   = "\e[36m";
my $RESET  = "\e[0m";
my $BOLD   = "\e[1m";

# Box drawing characters categorized by type
my %box_chars = (
    # Corners - single line
    top_left     => ['┌', '╭'],
    top_right    => ['┐', '╮'],
    bottom_left  => ['└', '╰'],
    bottom_right => ['┘', '╯'],

    # Corners - double line
    double_top_left     => ['╔'],
    double_top_right    => ['╗'],
    double_bottom_left  => ['╚'],
    double_bottom_right => ['╝'],

    # Corners - heavy line
    heavy_top_left     => ['┏'],
    heavy_top_right    => ['┓'],
    heavy_bottom_left  => ['┗'],
    heavy_bottom_right => ['┛'],

    # T-junctions
    t_down   => ['┬', '╦', '┳'],
    t_up     => ['┴', '╩', '┻'],
    t_right  => ['├', '╠', '┣'],
    t_left   => ['┤', '╣', '┫'],

    # Cross
    cross    => ['┼', '╬', '╋'],

    # Horizontal lines
    horizontal => ['─', '═', '━', '┄', '┈', '╌', '─'],

    # Vertical lines
    vertical => ['│', '║', '┃', '┆', '┊', '╎'],
);

# Characters that expect vertical continuation
my @vertical_chars = ('│', '║', '┃', '┆', '┊', '╎', '├', '┤', '╠', '╣', '┣', '┫', '┼', '╬', '╋', '┬', '╦', '┳', '┴', '╩', '┻');

# Characters that expect horizontal continuation
my @horizontal_chars = ('─', '═', '━', '┄', '┈', '╌', '├', '┤', '╠', '╣', '┣', '┫', '┼', '╬', '╋', '┬', '╦', '┳', '┴', '╩', '┻');

# Forbidden characters - these cause alignment issues in PDF rendering
# Severity: CRITICAL = will definitely break alignment, HIGH = likely to break, MEDIUM = may break
my %forbidden_chars = (
    # CRITICAL: Long arrows (render 3-4x width) - these WILL break alignment
    '⟶' => { severity => 'CRITICAL', width => '3-4x', replacement => '──→', alt => '-->' },
    '⟵' => { severity => 'CRITICAL', width => '3-4x', replacement => '←──', alt => '<--' },
    '⟹' => { severity => 'CRITICAL', width => '3-4x', replacement => '══→', alt => '==>' },
    '⟸' => { severity => 'CRITICAL', width => '3-4x', replacement => '←══', alt => '<==' },
    '⟷' => { severity => 'CRITICAL', width => '4-5x', replacement => '←─→', alt => '<->' },
    '⟺' => { severity => 'CRITICAL', width => '4-5x', replacement => '←═→', alt => '<=>' },

    # HIGH: Double-stroke arrows (render 1.5-2x width) - likely to break alignment
    '⇒' => { severity => 'HIGH', width => '1.5-2x', replacement => '=>', alt => '→' },
    '⇐' => { severity => 'HIGH', width => '1.5-2x', replacement => '<=', alt => '←' },
    '⇔' => { severity => 'HIGH', width => '2x',     replacement => '<=>', alt => '↔' },
    '⇑' => { severity => 'HIGH', width => '1.5x',   replacement => '^', alt => '↑' },
    '⇓' => { severity => 'HIGH', width => '1.5x',   replacement => 'v', alt => '↓' },
    '⇕' => { severity => 'HIGH', width => '1.5x',   replacement => '↕', alt => '^v' },

    # MEDIUM: Triangle/filled arrows (render 1.2-1.5x width) - may break alignment
    '▶' => { severity => 'MEDIUM', width => '1.2-1.5x', replacement => '>', alt => '→' },
    '◀' => { severity => 'MEDIUM', width => '1.2-1.5x', replacement => '<', alt => '←' },
    '▲' => { severity => 'MEDIUM', width => 'variable', replacement => '^', alt => '↑' },
    '▼' => { severity => 'MEDIUM', width => 'variable', replacement => 'v', alt => '↓' },

    # MEDIUM: Other problematic symbols
    '⇆' => { severity => 'MEDIUM', width => '2x', replacement => '<>', alt => '←→' },
    '⇄' => { severity => 'MEDIUM', width => '2x', replacement => '><', alt => '→←' },
);

# Check for forbidden characters in a line
sub find_forbidden_chars {
    my ($line, $line_num) = @_;
    my @issues;
    my $col = 0;

    for my $char (split //, $line) {
        if (exists $forbidden_chars{$char}) {
            my $info = $forbidden_chars{$char};
            my $type = "FORBIDDEN_CHAR_$info->{severity}";
            my $codepoint = sprintf("U+%04X", ord($char));
            push @issues, {
                line => $line_num,
                col  => $col + 1,
                char => $char,
                type => $type,
                msg  => "Forbidden character '$char' ($codepoint) renders at $info->{width} normal width. " .
                        "FIX: Replace with '$info->{replacement}' or '$info->{alt}'"
            };
        }
        $col++;
    }

    return @issues;
}

# Get display width of a character
# Most box drawing and standard ASCII characters are width 1
# Wide characters (CJK, fullwidth, emoji) are width 2
sub get_display_width {
    my ($char) = @_;
    my $ord = ord($char);

    # Control characters and zero-width
    return 0 if $ord < 0x20;
    return 0 if ($ord >= 0x7F && $ord < 0xA0);
    return 0 if ($ord == 0x200B || $ord == 0x200C || $ord == 0x200D || $ord == 0xFEFF);

    # Hangul Jamo
    return 2 if ($ord >= 0x1100 && $ord <= 0x115F);
    return 2 if ($ord >= 0x11A3 && $ord <= 0x11A7);
    return 2 if ($ord >= 0x11FA && $ord <= 0x11FF);

    # CJK Radicals and Ideographs
    return 2 if ($ord >= 0x2E80 && $ord <= 0x2EFF);  # CJK Radicals Supplement
    return 2 if ($ord >= 0x2F00 && $ord <= 0x2FDF);  # Kangxi Radicals
    return 2 if ($ord >= 0x2FF0 && $ord <= 0x2FFF);  # Ideographic Description
    return 2 if ($ord >= 0x3000 && $ord <= 0x303F);  # CJK Symbols and Punctuation
    return 2 if ($ord >= 0x3040 && $ord <= 0x309F);  # Hiragana
    return 2 if ($ord >= 0x30A0 && $ord <= 0x30FF);  # Katakana
    return 2 if ($ord >= 0x3100 && $ord <= 0x312F);  # Bopomofo
    return 2 if ($ord >= 0x3130 && $ord <= 0x318F);  # Hangul Compatibility Jamo
    return 2 if ($ord >= 0x3190 && $ord <= 0x319F);  # Kanbun
    return 2 if ($ord >= 0x31A0 && $ord <= 0x31BF);  # Bopomofo Extended
    return 2 if ($ord >= 0x31C0 && $ord <= 0x31EF);  # CJK Strokes
    return 2 if ($ord >= 0x31F0 && $ord <= 0x31FF);  # Katakana Phonetic Extensions
    return 2 if ($ord >= 0x3200 && $ord <= 0x32FF);  # Enclosed CJK Letters
    return 2 if ($ord >= 0x3300 && $ord <= 0x33FF);  # CJK Compatibility
    return 2 if ($ord >= 0x3400 && $ord <= 0x4DBF);  # CJK Unified Ideographs Extension A
    return 2 if ($ord >= 0x4E00 && $ord <= 0x9FFF);  # CJK Unified Ideographs
    return 2 if ($ord >= 0xA000 && $ord <= 0xA48F);  # Yi Syllables
    return 2 if ($ord >= 0xA490 && $ord <= 0xA4CF);  # Yi Radicals
    return 2 if ($ord >= 0xAC00 && $ord <= 0xD7AF);  # Hangul Syllables
    return 2 if ($ord >= 0xF900 && $ord <= 0xFAFF);  # CJK Compatibility Ideographs
    return 2 if ($ord >= 0xFE10 && $ord <= 0xFE1F);  # Vertical Forms
    return 2 if ($ord >= 0xFE30 && $ord <= 0xFE4F);  # CJK Compatibility Forms
    return 2 if ($ord >= 0xFE50 && $ord <= 0xFE6F);  # Small Form Variants
    return 2 if ($ord >= 0xFF00 && $ord <= 0xFF60);  # Fullwidth Forms
    return 2 if ($ord >= 0xFFE0 && $ord <= 0xFFE6);  # Fullwidth Forms

    # Supplementary CJK
    return 2 if ($ord >= 0x20000 && $ord <= 0x2A6DF);  # CJK Extension B
    return 2 if ($ord >= 0x2A700 && $ord <= 0x2B73F);  # CJK Extension C
    return 2 if ($ord >= 0x2B740 && $ord <= 0x2B81F);  # CJK Extension D
    return 2 if ($ord >= 0x2B820 && $ord <= 0x2CEAF);  # CJK Extension E
    return 2 if ($ord >= 0x2CEB0 && $ord <= 0x2EBEF);  # CJK Extension F
    return 2 if ($ord >= 0x2F800 && $ord <= 0x2FA1F);  # CJK Compatibility Supplement
    return 2 if ($ord >= 0x30000 && $ord <= 0x3134F);  # CJK Extension G

    # Most emoji are wide
    return 2 if ($ord >= 0x1F300 && $ord <= 0x1F9FF);  # Miscellaneous Symbols and Pictographs, Emoticons, etc.
    return 2 if ($ord >= 0x1FA00 && $ord <= 0x1FA6F);  # Chess Symbols
    return 2 if ($ord >= 0x1FA70 && $ord <= 0x1FAFF);  # Symbols and Pictographs Extended-A

    # Default width is 1 for most characters
    return 1;
}

# Calculate display width of a string
sub string_display_width {
    my ($str) = @_;
    my $width = 0;
    for my $char (split //, $str) {
        $width += get_display_width($char);
    }
    return $width;
}

# Check if character is a box drawing character (U+2500 to U+257F)
sub is_box_char {
    my ($char) = @_;
    my $ord = ord($char);
    return ($ord >= 0x2500 && $ord <= 0x257F);
}

# Check if character is a vertical line type
sub is_vertical {
    my ($char) = @_;
    return grep { $_ eq $char } @vertical_chars;
}

# Check if character is a horizontal line type
sub is_horizontal {
    my ($char) = @_;
    return grep { $_ eq $char } @horizontal_chars;
}

# Characters that have a downward connection (sends line down)
sub has_downward_connection {
    my ($char) = @_;
    return $char =~ /[│┃║┬╦┳├┤╠╣┼╬╋┌┐╔╗┏┓]/;
}

# Characters that have an upward connection (receives line from above)
sub has_upward_connection {
    my ($char) = @_;
    return $char =~ /[│┃║┴╩┻├┤╠╣┼╬╋└┘╚╝┗┛]/;
}

# Check if character is a top-left corner
sub is_top_left_corner {
    my ($char) = @_;
    return $char =~ /[┌╭┏╔]/;
}

# Check if character is a top-right corner
sub is_top_right_corner {
    my ($char) = @_;
    return $char =~ /[┐╮┓╗]/;
}

# Check if character is a bottom-left corner
sub is_bottom_left_corner {
    my ($char) = @_;
    return $char =~ /[└╰┗╚]/;
}

# Check if character is a bottom-right corner
sub is_bottom_right_corner {
    my ($char) = @_;
    return $char =~ /[┘╯┛╝]/;
}

# Check if character is a left-side vertical (can appear on left edge of box)
sub is_left_vertical {
    my ($char) = @_;
    return $char =~ /[│║┃┆┊╎├╠┣]/;
}

# Check if character is a right-side vertical (can appear on right edge of box)
sub is_right_vertical {
    my ($char) = @_;
    return $char =~ /[│║┃┆┊╎┤╣┫]/;
}

# Get character at a specific display column in a line
sub get_char_at_display_col {
    my ($line, $target_col) = @_;
    my @chars = split //, $line;
    my $current_col = 0;

    for my $char (@chars) {
        if ($current_col == $target_col) {
            return $char;
        }
        $current_col += get_display_width($char);
        return undef if $current_col > $target_col;
    }
    return undef;
}

# Find all corners and their display columns in a line
sub find_corners_in_line {
    my ($line) = @_;
    my @corners;
    my @chars = split //, $line;
    my $display_col = 0;

    for my $i (0 .. $#chars) {
        my $char = $chars[$i];
        if (is_top_left_corner($char) || is_top_right_corner($char) ||
            is_bottom_left_corner($char) || is_bottom_right_corner($char)) {
            push @corners, {
                char => $char,
                col => $display_col,
                char_idx => $i
            };
        }
        $display_col += get_display_width($char);
    }
    return @corners;
}

# Validate box alignment - checks that nested boxes have properly aligned corners and walls
sub validate_box_alignment {
    my ($lines_ref) = @_;
    my @lines = @$lines_ref;
    my @issues;

    # Build a map of all corners by line and column
    my @all_corners;  # Array of {line, col, char, type}

    for my $line_idx (0 .. $#lines) {
        my @corners = find_corners_in_line($lines[$line_idx]);
        for my $corner (@corners) {
            my $type;
            if (is_top_left_corner($corner->{char})) {
                $type = 'top_left';
            } elsif (is_top_right_corner($corner->{char})) {
                $type = 'top_right';
            } elsif (is_bottom_left_corner($corner->{char})) {
                $type = 'bottom_left';
            } elsif (is_bottom_right_corner($corner->{char})) {
                $type = 'bottom_right';
            }
            push @all_corners, {
                line => $line_idx,
                col => $corner->{col},
                char => $corner->{char},
                type => $type
            };
        }
    }

    # For each top-left corner, try to find its matching box and validate
    for my $tl (@all_corners) {
        next unless $tl->{type} eq 'top_left';

        my $tl_line = $tl->{line};
        my $tl_col = $tl->{col};

        # Find the matching top-right corner on the same line (first one to the right)
        my $tr = undef;
        for my $corner (@all_corners) {
            next unless $corner->{type} eq 'top_right';
            next unless $corner->{line} == $tl_line;
            next unless $corner->{col} > $tl_col;
            if (!defined $tr || $corner->{col} < $tr->{col}) {
                $tr = $corner;
            }
        }
        next unless defined $tr;

        my $tr_col = $tr->{col};

        # Find the matching bottom-left corner (same column as top-left, below it)
        my $bl = undef;
        for my $corner (@all_corners) {
            next unless $corner->{type} eq 'bottom_left';
            next unless $corner->{col} == $tl_col;
            next unless $corner->{line} > $tl_line;
            if (!defined $bl || $corner->{line} < $bl->{line}) {
                $bl = $corner;
            }
        }

        # Find the matching bottom-right corner (same column as top-right, same line as bottom-left)
        my $br = undef;
        if (defined $bl) {
            for my $corner (@all_corners) {
                next unless $corner->{type} eq 'bottom_right';
                next unless $corner->{line} == $bl->{line};
                next unless $corner->{col} == $tr_col;
                $br = $corner;
                last;
            }
        }

        # If we couldn't find bottom-left at exact column, check for misalignment
        if (!defined $bl) {
            # Look for any bottom-left corner below on a nearby column
            for my $corner (@all_corners) {
                next unless $corner->{type} eq 'bottom_left';
                next unless $corner->{line} > $tl_line;
                my $col_diff = $corner->{col} - $tl_col;
                if (abs($col_diff) <= 3 && abs($col_diff) > 0) {
                    my $fix = $col_diff > 0
                        ? "FIX: Move '$corner->{char}' left by $col_diff position(s) to column " . ($tl_col + 1)
                        : "FIX: Move '$corner->{char}' right by " . abs($col_diff) . " position(s) to column " . ($tl_col + 1);
                    push @issues, {
                        line => $corner->{line} + 1,
                        col  => $corner->{col} + 1,
                        type => 'BOX_CORNER_MISALIGNED',
                        msg  => "Bottom-left corner '$corner->{char}' at column " . ($corner->{col} + 1) .
                                " should align with top-left '┌' at line " . ($tl_line + 1) .
                                ", column " . ($tl_col + 1) . ". $fix"
                    };
                }
            }
        }

        # If we found all four corners, validate the walls between them
        if (defined $bl && defined $br) {
            my $bl_line = $bl->{line};

            # Check left wall: vertical chars between top-left and bottom-left
            for my $check_line ($tl_line + 1 .. $bl_line - 1) {
                my $char_at_left = get_char_at_display_col($lines[$check_line], $tl_col);
                if (defined $char_at_left && !is_left_vertical($char_at_left) && $char_at_left ne ' ') {
                    # Not a vertical line character - might be misaligned
                    # Check if there's a vertical nearby (within 2 cols)
                    for my $offset (-2 .. 2) {
                        next if $offset == 0;
                        my $nearby_char = get_char_at_display_col($lines[$check_line], $tl_col + $offset);
                        if (defined $nearby_char && is_left_vertical($nearby_char)) {
                            my $fix = $offset > 0
                                ? "FIX: Move '│' left by $offset position(s) to column " . ($tl_col + 1)
                                : "FIX: Move '│' right by " . abs($offset) . " position(s) to column " . ($tl_col + 1);
                            push @issues, {
                                line => $check_line + 1,
                                col  => $tl_col + $offset + 1,
                                type => 'BOX_WALL_MISALIGNED',
                                msg  => "Left wall '│' at column " . ($tl_col + $offset + 1) .
                                        " should align with box corner at column " . ($tl_col + 1) . ". $fix"
                            };
                        }
                    }
                }
            }

            # Check right wall: vertical chars between top-right and bottom-right
            for my $check_line ($tl_line + 1 .. $bl_line - 1) {
                my $char_at_right = get_char_at_display_col($lines[$check_line], $tr_col);
                if (defined $char_at_right && !is_right_vertical($char_at_right) && $char_at_right ne ' ') {
                    # Check if there's a vertical nearby (within 2 cols)
                    for my $offset (-2 .. 2) {
                        next if $offset == 0;
                        my $nearby_char = get_char_at_display_col($lines[$check_line], $tr_col + $offset);
                        if (defined $nearby_char && is_right_vertical($nearby_char)) {
                            my $fix = $offset > 0
                                ? "FIX: Move '│' left by $offset position(s) to column " . ($tr_col + 1)
                                : "FIX: Move '│' right by " . abs($offset) . " position(s) to column " . ($tr_col + 1);
                            push @issues, {
                                line => $check_line + 1,
                                col  => $tr_col + $offset + 1,
                                type => 'BOX_WALL_MISALIGNED',
                                msg  => "Right wall '│' at column " . ($tr_col + $offset + 1) .
                                        " should align with box corner at column " . ($tr_col + 1) . ". $fix"
                            };
                        }
                    }
                }
            }
        }

        # Check if bottom-right is misaligned with top-right
        if (defined $bl && !defined $br) {
            # Look for bottom-right on the same line as bottom-left but at wrong column
            for my $corner (@all_corners) {
                next unless $corner->{type} eq 'bottom_right';
                next unless $corner->{line} == $bl->{line};
                my $col_diff = $corner->{col} - $tr_col;
                if (abs($col_diff) <= 3 && abs($col_diff) > 0) {
                    my $fix = $col_diff > 0
                        ? "FIX: Move '$corner->{char}' left by $col_diff position(s) to column " . ($tr_col + 1)
                        : "FIX: Move '$corner->{char}' right by " . abs($col_diff) . " position(s) to column " . ($tr_col + 1);
                    push @issues, {
                        line => $corner->{line} + 1,
                        col  => $corner->{col} + 1,
                        type => 'BOX_CORNER_MISALIGNED',
                        msg  => "Bottom-right corner '$corner->{char}' at column " . ($corner->{col} + 1) .
                                " should align with top-right '┐' at line " . ($tl_line + 1) .
                                ", column " . ($tr_col + 1) . ". $fix"
                    };
                }
            }
        }
    }

    return @issues;
}

# Check if character is a pure vertical line (not a junction)
sub is_pure_vertical {
    my ($char) = @_;
    return $char =~ /[│┃║]/;
}

# Validate vertical line continuity - checks that vertical connectors align across lines
# Only checks pure vertical lines (│) to avoid false positives on converging patterns
sub validate_vertical_continuity {
    my ($lines_ref) = @_;
    my @lines = @$lines_ref;
    my @issues;

    # For each line (except the last), check pure vertical characters
    for my $line_idx (0 .. $#lines - 1) {
        my $line = $lines[$line_idx];
        my $next_line = $lines[$line_idx + 1];
        my @chars = split //, $line;

        my $display_col = 0;
        for my $char_idx (0 .. $#chars) {
            my $char = $chars[$char_idx];

            # Only check pure vertical lines, not junctions (to reduce false positives)
            if (is_pure_vertical($char)) {
                my $char_below = get_char_at_display_col($next_line, $display_col);

                # If there's a space below a pure vertical, check for misaligned verticals nearby
                if (defined $char_below && $char_below eq ' ') {
                    my $found_nearby = 0;
                    my $nearby_col = 0;
                    for my $offset (-2 .. 2) {
                        next if $offset == 0;
                        my $nearby = get_char_at_display_col($next_line, $display_col + $offset);
                        # Only flag if the nearby char is also a pure vertical (indicating misalignment)
                        if (defined $nearby && is_pure_vertical($nearby)) {
                            $found_nearby = 1;
                            $nearby_col = $display_col + $offset;
                            last;
                        }
                    }

                    if ($found_nearby) {
                        my $off = $nearby_col - $display_col;
                        my $fix = $off > 0
                            ? "FIX: Move '│' on line " . ($line_idx + 2) . " left by $off position(s) to column " . ($display_col + 1)
                            : "FIX: Move '│' on line " . ($line_idx + 2) . " right by " . abs($off) . " position(s) to column " . ($display_col + 1);
                        push @issues, {
                            line => $line_idx + 2,
                            col  => $nearby_col + 1,
                            type => 'VERTICAL_MISALIGNED',
                            msg  => "Vertical '│' at column " . ($nearby_col + 1) .
                                    " should align with '│' above (line " . ($line_idx + 1) . ", column " . ($display_col + 1) . "). $fix"
                        };
                    }
                }
            }
            # Also check T-down junctions (┬) - vertical must continue at same column
            elsif ($char =~ /[┬╦┳]/) {
                my $char_below = get_char_at_display_col($next_line, $display_col);

                # If there's a horizontal line (─) below but a ┼ nearby, that's misaligned
                if (defined $char_below && $char_below =~ /[─═━]/) {
                    # Horizontal line below - check if there's a ┼ nearby that should be here
                    for my $offset (-2 .. 2) {
                        next if $offset == 0;
                        my $nearby = get_char_at_display_col($next_line, $display_col + $offset);
                        # Flag if there's a cross junction nearby (should be at this column)
                        if (defined $nearby && $nearby =~ /[┼╬╋┴╩┻]/) {
                            my $fix = $offset > 0
                                ? "FIX: Move '$nearby' left by $offset position(s) to column " . ($display_col + 1)
                                : "FIX: Move '$nearby' right by " . abs($offset) . " position(s) to column " . ($display_col + 1);
                            push @issues, {
                                line => $line_idx + 2,
                                col  => $display_col + $offset + 1,
                                type => 'VERTICAL_MISALIGNED',
                                msg  => "Junction '$nearby' at column " . ($display_col + $offset + 1) .
                                        " should align with '┬' above (line " . ($line_idx + 1) . ", column " . ($display_col + 1) . "). $fix"
                            };
                            last;
                        }
                    }
                }
                # Space below ┬ - look for misaligned connector nearby
                elsif (defined $char_below && $char_below eq ' ') {
                    for my $offset (-2 .. 2) {
                        next if $offset == 0;
                        my $nearby = get_char_at_display_col($next_line, $display_col + $offset);
                        if (defined $nearby && has_upward_connection($nearby)) {
                            my $fix = $offset > 0
                                ? "FIX: Move connector left by $offset position(s) to column " . ($display_col + 1)
                                : "FIX: Move connector right by " . abs($offset) . " position(s) to column " . ($display_col + 1);
                            push @issues, {
                                line => $line_idx + 2,
                                col  => $display_col + $offset + 1,
                                type => 'VERTICAL_MISALIGNED',
                                msg  => "Connector '$nearby' at column " . ($display_col + $offset + 1) .
                                        " should align with '┬' above (line " . ($line_idx + 1) . ", column " . ($display_col + 1) . "). $fix"
                            };
                            last;
                        }
                    }
                }
            }

            $display_col += get_display_width($char);
        }
    }

    return @issues;
}

# Find potentially variable-width characters
sub find_variable_width_chars {
    my ($line, $line_num) = @_;
    my @issues;
    my $pos = 0;

    for my $char (split //, $line) {
        my $width = get_display_width($char);
        if ($width == 2) {
            my $codepoint = sprintf("U+%04X", ord($char));
            push @issues, {
                line => $line_num,
                col  => $pos + 1,
                char => $char,
                type => 'WIDE_CHAR',
                msg  => "Wide character '$char' ($codepoint) occupies 2 columns but counts as 1 character. " .
                        "FIX: Replace with ASCII equivalent or account for double-width in alignment"
            };
        }
        $pos++;
    }

    return @issues;
}

# Validate a single file
sub validate_file {
    my ($filename) = @_;
    my @issues;
    my @lines;

    # Read the file
    open(my $fh, '<:utf8', $filename) or do {
        return {
            filename => $filename,
            status   => 'ERROR',
            message  => "Cannot open file: $!",
            issues   => []
        };
    };

    @lines = <$fh>;
    close($fh);

    # Remove trailing newlines but preserve content
    chomp(@lines);

    if (@lines == 0) {
        return {
            filename => $filename,
            status   => 'EMPTY',
            message  => "File is empty",
            issues   => []
        };
    }

    # Check 1: Line width consistency
    my @widths;
    for my $i (0 .. $#lines) {
        my $display_width = string_display_width($lines[$i]);
        push @widths, { line => $i + 1, width => $display_width, raw_len => length($lines[$i]) };
    }

    # Find the most common width (expected width)
    my %width_counts;
    for my $w (@widths) {
        $width_counts{$w->{width}}++;
    }
    my $expected_width = (sort { $width_counts{$b} <=> $width_counts{$a} } keys %width_counts)[0];

    # Report lines with different widths
    for my $w (@widths) {
        if ($w->{width} != $expected_width) {
            my $diff = $w->{width} - $expected_width;
            my $fix;
            if ($diff > 0) {
                $fix = "FIX: Remove $diff character(s) from this line";
            } else {
                $fix = "FIX: Add " . abs($diff) . " space(s) to pad this line to width $expected_width";
            }
            push @issues, {
                line => $w->{line},
                col  => $w->{width} + 1,
                type => 'WIDTH_MISMATCH',
                msg  => "Line has width $w->{width}, expected $expected_width (off by $diff). $fix"
            };
        }
    }

    # Check 2 & 3: Vertical alignment of box drawing characters
    my %vertical_positions;  # Track vertical lines by column position

    for my $line_idx (0 .. $#lines) {
        my $line = $lines[$line_idx];
        my @chars = split //, $line;

        for my $char_idx (0 .. $#chars) {
            my $char = $chars[$char_idx];

            # Calculate actual display column
            my $display_col = 0;
            for my $j (0 .. $char_idx - 1) {
                $display_col += get_display_width($chars[$j]);
            }

            if (is_box_char($char)) {
                # Track vertical lines
                if (is_vertical($char)) {
                    push @{$vertical_positions{$display_col}}, {
                        line => $line_idx + 1,
                        char => $char
                    };
                }
            }
        }
    }

    # Check for vertical line alignment issues
    for my $col (sort { $a <=> $b } keys %vertical_positions) {
        my @occurrences = @{$vertical_positions{$col}};
        next if @occurrences < 2;

        @occurrences = sort { $a->{line} <=> $b->{line} } @occurrences;

        # Look for unexpected gaps in vertical lines
        for my $i (0 .. $#occurrences - 1) {
            my $current_line = $occurrences[$i]->{line};
            my $next_line = $occurrences[$i + 1]->{line};
            my $gap = $next_line - $current_line;

            # If there's a gap, check if it's intentional (lines in between should have compatible chars)
            if ($gap > 1 && $gap <= 5) {
                for my $check_line_num ($current_line .. $next_line - 2) {
                    my $check_line = $lines[$check_line_num];
                    my @check_chars = split //, $check_line;

                    # Find character at the same display column
                    my $current_display_col = 0;
                    my $char_at_col = ' ';
                    for my $c (@check_chars) {
                        if ($current_display_col == $col) {
                            $char_at_col = $c;
                            last;
                        }
                        $current_display_col += get_display_width($c);
                        last if $current_display_col > $col;
                    }

                    # If there's a non-space, non-vertical char, it might be a break
                    if ($char_at_col ne ' ' && !is_vertical($char_at_col) && !is_box_char($char_at_col)) {
                        # This could be intentional (e.g., text crossing a line)
                    }
                }
            }
        }
    }

    # Check 4: Horizontal line connections
    for my $line_idx (0 .. $#lines) {
        my $line = $lines[$line_idx];
        my @chars = split //, $line;

        for my $char_idx (0 .. $#chars) {
            my $char = $chars[$char_idx];

            # Check corners and junctions for proper connections
            if ($char =~ /[┌╭┏╔]/) {  # Top-left corners
                # Should have horizontal to the right
                if ($char_idx < $#chars) {
                    my $next = $chars[$char_idx + 1];
                    my $valid_next = ($next eq '─' || $next eq '═' || $next eq '━' ||
                                      $next eq '┄' || $next eq '┈' || $next eq '╌' ||
                                      is_box_char($next) || $next eq ' ');
                    if (!$valid_next) {
                        push @issues, {
                            line => $line_idx + 1,
                            col  => $char_idx + 1,
                            char => $char,
                            type => 'BROKEN_CONNECTION',
                            msg  => "Top-left corner '$char' has unexpected char '$next' to the right"
                        };
                    }
                }
            }

            if ($char =~ /[┐╮┓╗]/) {  # Top-right corners
                # Should have horizontal to the left
                if ($char_idx > 0) {
                    my $prev = $chars[$char_idx - 1];
                    my $valid_prev = ($prev eq '─' || $prev eq '═' || $prev eq '━' ||
                                      $prev eq '┄' || $prev eq '┈' || $prev eq '╌' ||
                                      is_box_char($prev) || $prev eq ' ');
                    if (!$valid_prev) {
                        push @issues, {
                            line => $line_idx + 1,
                            col  => $char_idx + 1,
                            char => $char,
                            type => 'BROKEN_CONNECTION',
                            msg  => "Top-right corner '$char' has unexpected char '$prev' to the left"
                        };
                    }
                }
            }

            if ($char =~ /[└╰┗╚]/) {  # Bottom-left corners
                if ($char_idx < $#chars) {
                    my $next = $chars[$char_idx + 1];
                    my $valid_next = ($next eq '─' || $next eq '═' || $next eq '━' ||
                                      $next eq '┄' || $next eq '┈' || $next eq '╌' ||
                                      is_box_char($next) || $next eq ' ');
                    if (!$valid_next) {
                        push @issues, {
                            line => $line_idx + 1,
                            col  => $char_idx + 1,
                            char => $char,
                            type => 'BROKEN_CONNECTION',
                            msg  => "Bottom-left corner '$char' has unexpected char '$next' to the right"
                        };
                    }
                }
            }

            if ($char =~ /[┘╯┛╝]/) {  # Bottom-right corners
                if ($char_idx > 0) {
                    my $prev = $chars[$char_idx - 1];
                    my $valid_prev = ($prev eq '─' || $prev eq '═' || $prev eq '━' ||
                                      $prev eq '┄' || $prev eq '┈' || $prev eq '╌' ||
                                      is_box_char($prev) || $prev eq ' ');
                    if (!$valid_prev) {
                        push @issues, {
                            line => $line_idx + 1,
                            col  => $char_idx + 1,
                            char => $char,
                            type => 'BROKEN_CONNECTION',
                            msg  => "Bottom-right corner '$char' has unexpected char '$prev' to the left"
                        };
                    }
                }
            }
        }
    }

    # Check 5: Variable width characters
    for my $line_idx (0 .. $#lines) {
        push @issues, find_variable_width_chars($lines[$line_idx], $line_idx + 1);
    }

    # Check 6: Forbidden characters (long arrows, double arrows, etc.)
    for my $line_idx (0 .. $#lines) {
        push @issues, find_forbidden_chars($lines[$line_idx], $line_idx + 1);
    }

    # Check 7: Box alignment (nested boxes must have aligned corners and walls)
    push @issues, validate_box_alignment(\@lines);

    # Check 8: Vertical line continuity (┬ must have │ or ┼ below it at same column)
    push @issues, validate_vertical_continuity(\@lines);

    # Determine overall status
    my $status = @issues ? 'FAIL' : 'PASS';

    return {
        filename      => $filename,
        status        => $status,
        line_count    => scalar(@lines),
        expected_width => $expected_width,
        issues        => \@issues
    };
}

# Print validation result
sub print_result {
    my ($result) = @_;

    my $status_color = $result->{status} eq 'PASS' ? $GREEN :
                       $result->{status} eq 'FAIL' ? $RED : $YELLOW;

    print "\n";
    print "${BOLD}File: $result->{filename}${RESET}\n";
    print "=" x 78 . "\n";
    print "Status: ${status_color}$result->{status}${RESET}\n";

    if ($result->{status} eq 'PASS') {
        print "${GREEN}All checks passed.${RESET}\n";
        print "Lines: $result->{line_count}, Width: $result->{expected_width} characters\n";
    }
    elsif ($result->{status} eq 'ERROR' || $result->{status} eq 'EMPTY') {
        print "${YELLOW}$result->{message}${RESET}\n";
    }
    else {
        print "Lines: $result->{line_count}, Expected Width: $result->{expected_width} characters\n";
        print "\n${CYAN}Issues Found:${RESET}\n";
        print "-" x 78 . "\n";

        my $issue_num = 0;
        for my $issue (@{$result->{issues}}) {
            $issue_num++;
            print sprintf("  %3d. Line %3d, Col %3d: [%s] %s\n",
                $issue_num,
                $issue->{line},
                $issue->{col},
                $issue->{type},
                $issue->{msg}
            );
        }
    }
    print "\n";
}

# Main execution
sub main {
    my @files = @ARGV;

    if (@files == 0) {
        print "Usage: $0 <file1> [file2] [...]\n";
        print "       $0 diagrams/*.txt\n";
        exit 1;
    }

    print "\n";
    print "${BOLD}ASCII Diagram Validator${RESET}\n";
    print "=" x 78 . "\n";
    print "Checking " . scalar(@files) . " file(s)...\n";

    my $pass_count = 0;
    my $fail_count = 0;
    my @all_results;

    for my $file (@files) {
        my $result = validate_file($file);
        push @all_results, $result;

        if ($result->{status} eq 'PASS') {
            $pass_count++;
        } else {
            $fail_count++;
        }

        print_result($result);
    }

    # Summary
    print "\n";
    print "${BOLD}Summary${RESET}\n";
    print "=" x 78 . "\n";
    print "Total files: " . scalar(@files) . "\n";
    print "${GREEN}Passed: $pass_count${RESET}\n";
    print "${RED}Failed: $fail_count${RESET}\n" if $fail_count > 0;
    print "\n";

    exit($fail_count > 0 ? 1 : 0);
}

main();
