extends RefCounted

## Planning rules for tiled, multi-LoD captures: how a box and a resolution turn into tile renders.
##
## Pure static functions on plain values (no nodes, no rendering), so they can be unit-tested headless.
## The same rules are implemented by Unity's CapturePlanner and read by the dashboard; see
## "Capture Metadata v2" in the dashboard docs.

## Largest PNG edge a tile may have unless the zone says otherwise.
const DEFAULT_MAX_TILE_PIXELS: int = 4096

## More levels than this (each halves the resolution) would be below any useful size.
const MAX_LOD_LEVELS: int = 8

## Default number of LoD levels per box.
const DEFAULT_LOD_LEVELS: int = 4

## Default for the smallest image edge a degraded level may have; smaller levels are dropped.
const DEFAULT_MIN_LEVEL_PIXELS: int = 256

const _GRID_EPSILON: float = 1e-6


## Tiles per axis (columns, rows) needed so that no PNG edge exceeds max_tile_pixels.
static func grid_for(size: Vector2, pixels_per_unit: float, max_tile_pixels: int) -> Vector2i:
	var cols: int = maxi(1, ceili(size.x * pixels_per_unit / max_tile_pixels - _GRID_EPSILON))
	var rows: int = maxi(1, ceili(size.y * pixels_per_unit / max_tile_pixels - _GRID_EPSILON))
	return Vector2i(cols, rows)


## Pixels per unit of every LoD level of a box of `size` world units, coarsest first, so the array
## index is the level tag. The finest level is `max_pixels_per_unit`; each further level halves it.
## A degraded level whose whole image would be shorter than `min_level_pixels` on its longest edge is
## dropped; the finest level is always kept.
static func level_pixels_per_unit(size: Vector2, max_pixels_per_unit: float, level_count: int, min_level_pixels: int) -> Array[float]:
	var ppus: Array[float] = []
	var longest_units: float = maxf(size.x, size.y)
	for i in clampi(level_count, 1, MAX_LOD_LEVELS):
		var ppu: float = max_pixels_per_unit / pow(2.0, i)
		if i > 0 and longest_units * ppu < min_level_pixels:
			break # only gets smaller from here
		ppus.append(ppu)
	ppus.reverse()
	return ppus


## Number of tiles plan_face() would produce, without building them.
static func count_tiles(size: Vector2, max_pixels_per_unit: float, level_count: int, min_level_pixels: int, max_tile_pixels: int) -> int:
	if max_pixels_per_unit <= 0.0 or max_tile_pixels < 1:
		return 0
	var total: int = 0
	for ppu in level_pixels_per_unit(size, max_pixels_per_unit, level_count, min_level_pixels):
		var grid: Vector2i = grid_for(size, ppu, max_tile_pixels)
		total += grid.x * grid.y
	return total


## Every tile of every LoD level of a box of `size` world units.
##
## `max_pixels_per_unit` is the finest level's resolution; see level_pixels_per_unit() for the coarser
## ones. Levels are tagged from 0 (coarsest) upward, so a higher tag is always more detail.
## Order: level, row, column. Each entry is a Dictionary:
##   level: int, col: int, row: int, cols: int, rows: int, pixels_per_unit: float,
##   tile_size: Vector2   world units covered by the tile
##   offset: Vector2      tile centre relative to the box centre: x along the image's right, y along its up
##   pixel_size: Vector2i PNG size
static func plan_face(size: Vector2, max_pixels_per_unit: float, level_count: int, min_level_pixels: int, max_tile_pixels: int) -> Array[Dictionary]:
	var tiles: Array[Dictionary] = []
	if max_pixels_per_unit <= 0.0 or max_tile_pixels < 1 or size.x <= 0.0 or size.y <= 0.0:
		push_error("CapturePlan: pixels per unit, tile size and box size must be positive.")
		return tiles

	var level_ppus: Array[float] = level_pixels_per_unit(size, max_pixels_per_unit, level_count, min_level_pixels)
	for level in level_ppus.size():
		var ppu: float = level_ppus[level]
		var grid: Vector2i = grid_for(size, ppu, max_tile_pixels)
		var tile_size := Vector2(size.x / grid.x, size.y / grid.y)
		var pixel_size := Vector2i(maxi(1, roundi(tile_size.x * ppu)), maxi(1, roundi(tile_size.y * ppu)))

		for row in grid.y:
			for col in grid.x:
				tiles.append({
					"level": level,
					"col": col,
					"row": row,
					"cols": grid.x,
					"rows": grid.y,
					"pixels_per_unit": ppu,
					"tile_size": tile_size,
					"offset": Vector2(
						(col + 0.5) / grid.x * size.x - size.x / 2.0,
						size.y / 2.0 - (row + 0.5) / grid.y * size.y),
					"pixel_size": pixel_size,
				})
	return tiles
