# Godot-AreaCapture

Godot 4 addon that captures free-form areas of a 2D scene, from the editor, as PNG maps — at several levels of detail, split into tiles — plus a JSON metadata file the OGA dashboard reads to draw position heatmaps over the map. It is the Godot counterpart of the Unity `Unity-AreaCapture` package and writes the same format ("Capture Metadata v2").

## CaptureZone2D

An `Area2D` whose child `CollisionShape2D`s are the capture boxes. Boxes can be placed, sized (shape size and node scale) and **rotated** freely, and may overlap; each box is captured aligned to itself.

| Property | Meaning |
|---|---|
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

Select a `CaptureZone2D` in the scene tree and press **Capture areas** in the Inspector. The capture runs in the editor, like Unity's Area Capture: the game does not have to run, nothing is written into the scene, and the editor imports the new PNGs afterwards. It needs a real renderer, so it does not work from `--headless`.

The scene is drawn as the editor holds it, so it stands still and every tile shows the same state. Things that exist only while the game runs (spawned nodes, generated levels, a background that follows the game camera) are not in the map. Nodes that draw themselves only in the editor (collision shapes, markers, cameras, occluders, paths, navigation, joints, bones) are hidden during the capture; a custom `@tool` script that draws a gizmo is not, so give it a visibility layer and untick that layer in `render_layers`.

#### Where it works and where not

Each tile is drawn by a `SubViewport` that shares the scene's 2D world. Tested with Godot 4.7 (GL Compatibility, software GL), with a scene of coloured squares moved to different positions:

| How the view is placed | In the editor | In the running game |
|---|---|---|
| `Camera2D` in the `SubViewport`, the `SubViewport` under a node of the edited scene | **no effect:** every tile shows the origin, whatever the camera position, rotation or zoom | works |
| `Camera2D` in the `SubViewport`, the `SubViewport` under an editor plugin node | works | works |
| `SubViewport.canvas_transform` set directly (used here) | works | works, and pixel-identical to the `Camera2D` |

A zone is a node of the edited scene, so the first row is the case that matters and the reason the renderer sets `canvas_transform` instead of using a camera. `capture_renderer.gd` has `view_transform()` for it.

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
| `capture_renderer.gd` | Renders one tile: a `SubViewport` sharing the world, its `canvas_transform` set from the tile centre, rotation and zoom (not a `Camera2D`, see below); tells whether a tile is empty. |
| `capture_zone_2d.gd` | The node: box geometry from shapes, the capture loop, writing the metadata. |
| `position_tracker.gd`, `trackable_*.gd` | Position reporting (signal only; no event sender yet). |

`capture_plan.gd` and `capture_metadata_writer.gd` are verified against the dashboard's demo dataset (`Dashboard/oga-dashboard/tests/fixtures/capture-lod-demo/`) by running them under `godot --headless --script`.
