extends RefCounted

## Planning rules for tiled, multi-LoD captures: how a box and a resolution turn into tile renders.
##
## Pure static functions on plain values (no nodes, no rendering), so they can be unit-tested headless.
## The same rules are implemented by Unity's CapturePlanner and read by the dashboard; see
## "Capture Metadata v2" in the dashboard docs.

## Pixel size of a full tile unless the zone says otherwise.
const DEFAULT_TILE_PIXELS: int = 1024

## More levels than this (each halves the resolution) would be below any useful size.
const MAX_LOD_LEVELS: int = 8

## Default number of LoD levels per box.
const DEFAULT_LOD_LEVELS: int = 4

## Default for the smallest image edge a degraded level may have; smaller levels are dropped.
const DEFAULT_MIN_LEVEL_PIXELS: int = 256

const _GRID_EPSILON: float = 1e-6


## Pixels a box of `size` world units takes at the finest level (at least 1 per axis), rounded up so the
## image covers the whole box.
static func finest_pixels(size: Vector2, max_pixels_per_unit: float) -> Vector2i:
	return Vector2i(
		maxi(1, ceili(size.x * max_pixels_per_unit - _GRID_EPSILON)),
		maxi(1, ceili(size.y * max_pixels_per_unit - _GRID_EPSILON)))


## Pixels of the level `steps_below_finest` halvings below the finest one: the finest size halved and
## rounded up each time. Deriving every level from the finest size (rather than rounding each on its own)
## makes the tile grids nest exactly: a tile of one level is covered by four tiles of the next.
static func level_pixels(finest: Vector2i, steps_below_finest: int) -> Vector2i:
	var divisor: int = 1 << steps_below_finest
	@warning_ignore("integer_division")
	return Vector2i((finest.x + divisor - 1) / divisor, (finest.y + divisor - 1) / divisor)


## Tiles per axis (columns, rows) of `tile_pixels` pixels needed to cover an image of `total_pixels`.
static func grid_for(total_pixels: Vector2i, tile_pixels: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(
		maxi(1, (total_pixels.x + tile_pixels - 1) / tile_pixels),
		maxi(1, (total_pixels.y + tile_pixels - 1) / tile_pixels))


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
static func count_tiles(size: Vector2, max_pixels_per_unit: float, level_count: int, min_level_pixels: int, tile_pixels: int) -> int:
	if max_pixels_per_unit <= 0.0 or tile_pixels < 1:
		return 0
	var level_ppus: Array[float] = level_pixels_per_unit(size, max_pixels_per_unit, level_count, min_level_pixels)
	var finest: Vector2i = finest_pixels(size, max_pixels_per_unit)
	var total: int = 0
	for level in level_ppus.size():
		var grid: Vector2i = grid_for(level_pixels(finest, level_ppus.size() - 1 - level), tile_pixels)
		total += grid.x * grid.y
	return total


## Every tile of every LoD level of a box of `size` world units.
##
## `max_pixels_per_unit` is the finest level's resolution; see level_pixels_per_unit() for the coarser
## ones. Levels are tagged from 0 (coarsest) upward, so a higher tag is always more detail.
## Every tile is `tile_pixels` square and anchored at the box's top-left corner; only the last column/row
## (and a level smaller than one tile) is cropped to the box. Adjacent levels differ by a factor of two and
## their image sizes are derived from the finest one, so a finer level replaces each tile with four:
## children of (col, row) are (2col..2col+1, 2row..2row+1), and every child lies inside its parent.
## Order: level, row, column. Each entry is a Dictionary:
##   level: int, col: int, row: int, cols: int, rows: int, pixels_per_unit: float,
##   tile_pixels: int     nominal pixel size of a full tile at this level
##   tile_size: Vector2   world units covered by this tile
##   offset: Vector2      tile centre relative to the box centre: x along the image's right, y along its up
##   pixel_size: Vector2i PNG size
static func plan_face(size: Vector2, max_pixels_per_unit: float, level_count: int, min_level_pixels: int, tile_pixels: int) -> Array[Dictionary]:
	var tiles: Array[Dictionary] = []
	if max_pixels_per_unit <= 0.0 or tile_pixels < 1 or size.x <= 0.0 or size.y <= 0.0:
		push_error("CapturePlan: pixels per unit, tile size and box size must be positive.")
		return tiles

	var level_ppus: Array[float] = level_pixels_per_unit(size, max_pixels_per_unit, level_count, min_level_pixels)
	var finest: Vector2i = finest_pixels(size, max_pixels_per_unit)
	for level in level_ppus.size():
		var ppu: float = level_ppus[level]
		var total: Vector2i = level_pixels(finest, level_ppus.size() - 1 - level)
		var grid: Vector2i = grid_for(total, tile_pixels)

		for row in grid.y:
			var px_h: int = mini(tile_pixels, total.y - row * tile_pixels)
			var tile_h: float = px_h / ppu
			var origin_y: float = row * tile_pixels / ppu # from the top edge
			for col in grid.x:
				var px_w: int = mini(tile_pixels, total.x - col * tile_pixels)
				var tile_w: float = px_w / ppu
				var origin_x: float = col * tile_pixels / ppu # from the left edge
				tiles.append({
					"level": level,
					"col": col,
					"row": row,
					"cols": grid.x,
					"rows": grid.y,
					"pixels_per_unit": ppu,
					"tile_pixels": tile_pixels,
					"tile_size": Vector2(tile_w, tile_h),
					"offset": Vector2(
						origin_x + tile_w / 2.0 - size.x / 2.0,
						size.y / 2.0 - (origin_y + tile_h / 2.0)),
					"pixel_size": Vector2i(px_w, px_h),
				})
	return tiles
