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

- `BridgyEngine/` — the rules and all AI, as a platform-agnostic SwiftPM package
- `Bridgy/` — the SwiftUI app

## Building

```sh
xcodegen generate
open Bridgy.xcodeproj
```

Engine tests run without Xcode:

```sh
cd BridgyEngine && swift test
```

Set `BRIDGY_DIAGNOSTICS=1` to include the engine strength matrix.
