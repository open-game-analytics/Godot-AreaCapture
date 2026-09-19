# Godot-AreaCapture

Godot 4 addon that captures free-form areas of a running 2D scene as PNG maps — at several levels of detail, split into tiles — plus a JSON metadata file the OGA dashboard reads to draw position heatmaps over the map. It is the Godot counterpart of the Unity `Unity-AreaCapture` package and writes the same format ("Capture Metadata v2").

## CaptureZone2D

An `Area2D` whose child `CollisionShape2D`s are the capture boxes. Boxes can be placed, sized (shape size and node scale) and **rotated** freely, and may overlap; each box is captured aligned to itself.

| Property | Meaning |
|---|---|
| `recapture` | Capture when the game starts. Not saved back into the scene, so prefer the command line below. |
| `output_directory` | Where the PNGs and the metadata go (`res://export/capture/`). |
| `filename` | Prefix of box ids and image names: `<filename>_<shape name>`. |
| `metadata_filename` | Metadata file; zones that share it merge into it, so an overview and its detail zones end up together. |
| `scenario` | Scenario name stored in the metadata. |
| `pixels_per_unit` | **Maximum quality**: pixels per world unit of the finest level (Godot 2D units are pixels, so `1` = native). |
| `lod_levels` | Levels of detail to export (default 4). The finest is `pixels_per_unit`; each further level is half the resolution of the previous one. |
| `min_level_pixels` | Degraded levels whose whole image would be shorter than this (longest edge, px) are skipped (default 256); the finest level is always exported. |
| `tile_pixels` | Pixel size of every tile of every level (default 1024). Tiles are anchored at the box's top-left corner; only the last column/row (and a level smaller than one tile) is cropped. |
| `render_layers` | Visibility layers included in the capture; move e.g. the player to another layer and untick it to leave it out. |

### Capturing

The game must run with a real renderer (`--headless` has none). While capturing, the scene tree is paused so all tiles show the same moment of the game (nodes with `process_mode` `Always`/`Disabled` and shader `TIME` are not affected). From the command line, nothing is written into the scene:

```bash
godot --path . -- --capture-areas     # captures all CaptureZone2D nodes, then quits
```

### Levels of detail

- **Max quality first:** `pixels_per_unit` is the resolution you want at best; `lod_levels` adds smaller versions below it (4 levels at 1 ppu are 0.125 / 0.25 / 0.5 / 1). Levels are tagged `L0` (coarsest) upward, and every level is cut into tiles of the same pixel size (`tile_pixels`), so a finer level replaces one tile with four and every tile costs the same to load. Levels that would be smaller than `min_level_pixels` are dropped, so small boxes get fewer levels.
- **Manual detail box:** add a second `CaptureZone2D` with a higher `pixels_per_unit` and a box over the area of interest, using the same `metadata_filename`. Level tags are per box (every box starts at `L0`).

### Output

Images are named `<id>_Front_L<level>_<col>x<row>.png` (row 0 is the top). The metadata is schema v2 — see `Dashboard/docs/Capture Metadata v2.md`. Conventions:

- The file is **Y-up** like Unity's: `y` and the rotation angle are negated on export. The images are not flipped.
- 2D boxes export face `Front`; the dashboard shows it for the "Front view (XY)".
- Events sent for the same scenario must use `(x; -y; 0)` to line up with the map.

`CaptureZone3D` still writes the older flat (v1) metadata; the dashboard accepts both.

## Code layout

| File | Role |
|---|---|
| `capture_plan.gd` | Pure rules: tile grid, LoD levels, tile offsets and pixel sizes. Unit-testable headless. |
| `capture_metadata_writer.gd` | Builds and serialises schema v2 (y-flip, rounding, merging). |
| `capture_renderer.gd` | Renders one tile: a `SubViewport` sharing the world with a rotated, zoomed `Camera2D`. |
| `capture_zone_2d.gd` | The node: box geometry from shapes, the capture loop, writing the metadata. |
| `position_tracker.gd`, `trackable_*.gd` | Position reporting (signal only; no event sender yet). |

`capture_plan.gd` and `capture_metadata_writer.gd` are verified against the dashboard's demo dataset (`Dashboard/oga-dashboard/tests/fixtures/capture-lod-demo/`) by running them under `godot --headless --script`.
