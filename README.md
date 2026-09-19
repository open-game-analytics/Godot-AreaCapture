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
| `lod_levels` | Levels of detail to export. Level *i* renders at `pixels_per_unit × 2^i`. |
| `first_level` | LoD tag of the first level. `0` for an overview; higher for a detail zone drawn on top when zoomed in. |
| `pixels_per_unit` | Pixels per world unit at the first level (Godot 2D units are pixels, so `1` = native). |
| `max_tile_pixels` | Largest PNG edge. Bigger areas are tiled instead of failing. |
| `render_layers` | Visibility layers included in the capture; move e.g. the player to another layer and untick it to leave it out. |

### Capturing

The game must run with a real renderer (`--headless` has none). From the command line, nothing is written into the scene:

```bash
godot --path . -- --capture-areas     # captures all CaptureZone2D nodes, then quits
```

### Levels of detail

- **Auto-subdivision:** set `lod_levels` > 1 on a zone. Each level doubles the resolution and the tile grid grows with it.
- **Manual detail box:** add a second `CaptureZone2D` with `lod_levels = 1`, a higher `first_level` and `pixels_per_unit`, and a box over the area of interest, using the same `metadata_filename`.

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
