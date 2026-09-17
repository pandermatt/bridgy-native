# Bridgy

A native SwiftUI port of **Bridg-It** — David Gale's connection game, also known
as the Game of Gale — for iOS, iPadOS and macOS.

This is a rewrite of [pandermatt/bridgy](https://github.com/pandermatt/bridgy),
a Java Swing implementation. The rules and the AI ideas carry over; none of the
code or assets do.

## The game

Blue and red each own a lattice of dots, interleaved so that every possible blue
edge crosses exactly one possible red edge. Taking a cell draws your edge and
denies your opponent theirs, so building and blocking are the same act. Blue
moves first and needs a top-to-bottom chain; red needs left-to-right. There are
no draws: when the board fills, exactly one player has crossed it.

## Opponents

| Level | Engine |
| --- | --- |
| Easy | Random |
| Casual | Greedy, aggressive |
| Medium | Greedy, balanced |
| Hard | Pathfinder, balanced |
| Expert | Monte Carlo tree search |
| Perfect | Gross's pairing strategy |

Bridg-It is a *solved* game. Oliver Gross showed the first player can always
win, via a pairing strategy derived from two edge-disjoint spanning trees of the
board graph — a special case of Lehman's 1964 result on the Shannon switching
game. The Perfect engine implements it and cannot be beaten when it moves first.
(Playing second it falls back to search, because second player provably loses.)

## Layout

- `BridgyEngine/` — the rules, board geometry and all AI, as a platform-agnostic
  SwiftPM package with no UI dependencies
- `Bridgy/` — the SwiftUI app
- `Tools/MakeIcon.swift` — draws the app icon; no artwork is checked in by hand

## Building

```sh
xcodegen generate
open Bridgy.xcodeproj
```

## Tournament

Every difficulty plays every other, in both colours, at each board size, and the
results plot while the run is going: Elo ratings converging game by game, win
rate against board size, and the first-player advantage measured per size. Win
rates carry 95% Wilson intervals, because a tournament spends most of its time
at sample sizes where a bare percentage means very little.

Engine tests run without Xcode:

```sh
cd BridgyEngine && swift test
```

Two opt-in diagnostics print strength tables instead of asserting:

```sh
BRIDGY_DIAGNOSTICS=1 swift test --filter Diagnostics   # engine head-to-head matrix
BRIDGY_LADDER=1 swift test --filter LadderDiagnostics  # each level vs the one below
```
