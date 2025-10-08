Paperdoll overlays - quick guide

Assets
- Place PNGs in `/images/paperdoll` (or `/images/paperdll`) under slot folders:
  - head, body, back, left, right, legs, feet, neck, finger, ammo, purse
- File names: `ITEMID_0.png`, `ITEMID_1.png`, `ITEMID_2.png`, `ITEMID_3.png`
  - 0..3 correspond to N, E, S, W (diagonals are auto-mapped)

Runtime offsets
- Offsets are stored in `/settings/paperdoll_offsets.json` and can be tweaked live via console helpers:
  - `paperdoll_nudge_head(dirKey, dx, dy)`
  - `paperdoll_nudge_body(dirKey, dx, dy)`
  - `paperdoll_nudge_head_current(dx, dy)` and `paperdoll_nudge_body_current(dx, dy)`

Testing helpers (console)
- `paperdoll_scan_current()`
  - Prints which equipped items have overlays and which directions exist
- `paperdoll_refresh_all()`
  - Reapplies overlays for all inventory slots (skips while invisible)
- `paperdoll_simulate_invisibility(true|false)`
  - Simulates invisibility suppression/restoration of overlays for quick checks

Notes
- Overlays are suppressed while invisible and restored automatically on exit.
- Any new item with assets following the pattern above inherits behavior automatically.
