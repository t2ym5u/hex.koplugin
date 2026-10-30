# Changelog

All notable changes to this project will be documented in this file.

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
