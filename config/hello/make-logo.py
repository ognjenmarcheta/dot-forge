#!/usr/bin/env python3
"""Draw the ByteForge anvil as text: config/hello/byteforge.logo.

The shapes below are traced from byteforge.software/media/brand/logo-dark.webp
(64×32 units): two wings, two posts, and an X of two bars that end in feet;
the bar from the right post to the left foot is in front, so the other one
stops short of it. Each text cell holds two "pixels" (▀ / ▄ / █).

Output: one line per row; {fN} / {bN} mark the foreground / background colour
of region N (1 wings, 2 front bar, 3 back bar), {r} resets; every line is
padded to the same width. dot-hello swaps the marks for colours, or drops them.
    python3 config/hello/make-logo.py > config/hello/byteforge.logo
"""
import re
import sys

COLS, ROWS = 34, 18          # 18 half-rows = 9 lines of text
W, H = 64.0, 32.0


def left_wing(x, y):
    return 2 <= y <= 12 and x <= 16.2 and x >= (y - 2) * 1.25


def right_wing(x, y):
    return 2 <= y <= 11 and x >= 50 and x <= 63 - (y - 2.5) * 1.35


def bar(x, y, c0, slope, post):
    if 0 <= y < 9:
        return post[0] <= x <= post[1]
    if 9 <= y <= 26:
        c = c0 + slope * (y - 9)
        return abs(x - c) <= 4.8
    return False


def front(x, y):   # right post -> left foot
    return bar(x, y, 42.5, -1.30, (38, 47)) or (26 <= y <= 31 and 14 <= x <= 26)


def back(x, y):    # left post -> right foot
    return bar(x, y, 23.5, 1.30, (19, 28)) or (26 <= y <= 31 and 39 <= x <= 51)


def region(x, y):
    if front(x, y):
        return 2
    if back(x, y):
        # a groove where the back bar passes behind the front one
        near = any(front(x + dx, y + dy) for dx in (-1.7, 0, 1.7) for dy in (-0.9, 0, 0.9))
        return 0 if near else 3
    if left_wing(x, y) or right_wing(x, y):
        return 1
    return 0


def cell(cx, cy):
    """majority region of a cell, sampled 4×4"""
    votes = {}
    for i in range(4):
        for j in range(4):
            x = (cx + (i + 0.5) / 4) * W / COLS
            y = (cy + (j + 0.5) / 4) * H / ROWS
            r = region(x, y)
            votes[r] = votes.get(r, 0) + 1
    r, n = max(votes.items(), key=lambda kv: kv[1])
    return r if n >= 6 or r == 0 else max((k for k in votes if k), key=lambda k: votes[k])


def main():
    grid = [[cell(x, y) for x in range(COLS)] for y in range(ROWS)]
    out = []
    for row in range(0, ROWS, 2):
        line, state = "", None
        for x in range(COLS):
            t, b = grid[row][x], grid[row + 1][x]
            if t == 0 and b == 0:
                ch, want = " ", (None, None)
            elif t == b:
                ch, want = "█", (t, None)
            elif b == 0:
                ch, want = "▀", (t, None)
            elif t == 0:
                ch, want = "▄", (b, None)
            else:
                ch, want = "▀", (t, b)
            if ch != " " and want != state:
                line += "{r}" + "{f%d}" % want[0] + ("{b%d}" % want[1] if want[1] else "")
                state = want
            elif ch == " " and state not in (None, (None, None)):
                line += "{r}"
                state = None
            line += ch
        line = line.rstrip()
        visible = len(re.sub(r"\{[a-z0-9]+\}", "", line))
        out.append(line + "{r}" + " " * (COLS - visible))   # every line COLS wide
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
