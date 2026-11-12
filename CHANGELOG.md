# Changelog

All notable changes to this project will be documented in this file.

## [1.1.3] - 2026-11-12

### Changed
- Picks up game-common 1.16.0: games for two readers (new Two readers
  category) and the shared Start / Join dialog.

## [1.1.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.1.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.1.0] - 2026-11-04

### Changed
- The computer answers in about 2.5 s at most on an e-reader, instead of up
  to 8 s per move at Hard (4 s at Medium) on 11×11. On a Kobo, Hard now
  thinks for at most 2.3 s, Medium 2 s, Easy 1 s.
- Hard keeps what it worked out between moves (the analysis of the line
  actually played), and its random playouts run ~10% faster, which wins back
  part of the shorter thinking time. On a slow e-reader Hard on 11×11 is
  weaker than before: it won 35 of 80 test games on 11×11 and 14 of 40 on
  9×9 against the old 8-second version (Medium and 7×7 Hard: unchanged). On
  a fast device, where the time cap is never reached, Hard is as strong as
  before or slightly stronger.

## [1.0.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.0.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-10-30

### Added
- Hex on a 7×7, 9×9 or 11×11 rhombus of hexagons. Black joins the top and
  bottom edges (solid black bands), White the left and right edges (hollow
  bands); the winning chain is shaded once the game is won.
- Against the computer (play Black or White) or two players on one device.
- Optional swap (pie) rule: on White's first turn a "Swap" button takes over
  Black's opening stone, mirrored across the long diagonal. The computer
  swaps central openings, and opens on an edge row itself when you may swap.
- Computer opponent: Monte Carlo tree search with RAVE statistics and
  bridge-saving playouts, three levels (easy / medium / hard). It always takes
  a winning cell and always blocks a single losing one.
- Undo (against the computer, takes back its reply and your move together),
  auto-save and restore of the game in progress.
