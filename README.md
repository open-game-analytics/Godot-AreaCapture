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
| `min_pixels_per_unit` | Lowest resolution a level of detail may have (default 0 = no floor). Levels start at `pixels_per_unit` and halve until a level's whole image fits in one tile (the overview) or the next level would fall below this; the finest level is always exported. |
| `extremes_only` | Export only the coarsest (overview) and finest level, a fast preview of the worst and best LoD (default off). Levels keep their real numbers. |
| `tile_pixels` | Pixel size of every tile of every level (default 1024). Tiles are anchored at the box's top-left corner; only the last column/row (and a level smaller than one tile) is cropped. |
| `skip_empty_tiles` | Default on. Tiles in which nothing is drawn (fully transparent) are not saved and are left out of the metadata, so empty parts of a box cost no disk space; a level or box with no drawn tile is not exported at all (a box with the same id from an earlier export is removed from the metadata). A PNG an earlier export left under the name of a tile that is empty now is deleted once the metadata is written. The dashboard draws nothing where a tile is missing. |
| `render_layers` | Visibility layers included in the capture; move e.g. the player to another layer and untick it to leave it out. |

### Capturing

The game must run with a real renderer (`--headless` has none). While capturing, the scene tree is paused so all tiles show the same moment of the game (nodes with `process_mode` `Always`/`Disabled` and shader `TIME` are not affected). From the command line, nothing is written into the scene:

```bash
godot --path . -- --capture-areas     # captures all CaptureZone2D nodes, then quits
```

### Levels of detail

- **Max quality first:** `pixels_per_unit` is the resolution you want at best; the smaller versions below it are derived: each level halves the resolution until the whole box fits in one tile (a 2000 x 1000 px box at 1 ppu with 512 px tiles gets 0.25 / 0.5 / 1). Levels are tagged `L0` (coarsest) upward, and every level is cut into tiles of the same pixel size (`tile_pixels`), so a finer level replaces one tile with four and every tile costs the same to load. `min_pixels_per_unit` sets a floor for the ladder, and small boxes get fewer levels.
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
| `capture_metadata_writer.gd` | Builds and serialises schema v2 (y-flip, rounding, merging and removing boxes). |
| `capture_renderer.gd` | Renders one tile: a `SubViewport` sharing the world with a rotated, zoomed `Camera2D`; tells whether a tile is empty. |
| `capture_zone_2d.gd` | The node: box geometry from shapes, the capture loop, writing the metadata. |
| `position_tracker.gd`, `trackable_*.gd` | Position reporting (signal only; no event sender yet). |

`capture_plan.gd` and `capture_metadata_writer.gd` are verified against the dashboard's demo dataset (`Dashboard/oga-dashboard/tests/fixtures/capture-lod-demo/`) by running them under `godot --headless --script`.
