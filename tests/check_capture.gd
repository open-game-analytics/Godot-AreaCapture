extends SceneTree

## Headless checks for the addon's pure logic (plan, metadata writer, box geometry), including that it
## reproduces the dashboard's shared demo dataset. Run from the monorepo root:
##     godot --headless --path godot-2d-platformer --script res://addons/Godot-AreaCapture/tests/check_capture.gd
## Exit code 0 = all checks passed. (Rendering itself needs a real display; see the addon README.)

const Plan := preload("res://addons/Godot-AreaCapture/capture_plan.gd")
const Writer := preload("res://addons/Godot-AreaCapture/capture_metadata_writer.gd")
const ZoneScript := preload("res://addons/Godot-AreaCapture/capture_zone_2d.gd")

var checks: int = 0
var failures: int = 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


func near(a: float, b: float, tol: float = 1e-4) -> bool:
	return absf(a - b) <= tol


func same_ppus(actual: Array[float], expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		if not near(actual[i], expected[i]):
			return false
	return true


func _init() -> void:
	# ── grid / plan ──────────────────────────────────────────────────────
	check(Plan.grid_for(Vector2i(200, 100), 200) == Vector2i(1, 1), "grid 200x100 px in 200 px tiles = 1x1")
	check(Plan.grid_for(Vector2i(400, 200), 200) == Vector2i(2, 1), "grid 400x200 = 2x1")
	check(Plan.grid_for(Vector2i(800, 400), 200) == Vector2i(4, 2), "grid 800x400 = 4x2")
	check(Plan.grid_for(Vector2i(801, 400), 200) == Vector2i(5, 2), "a single extra pixel needs another tile")
	check(Plan.finest_pixels(Vector2(12.5, 4.0), 16.0) == Vector2i(200, 64), "finest size, exact products are not bumped by float noise")
	check(Plan.finest_pixels(Vector2(10.01, 1.0), 10.0) == Vector2i(101, 10), "finest size is rounded up so the image covers the box")
	check(Plan.level_pixels(Vector2i(801, 400), 1) == Vector2i(401, 200), "one level down: halved and rounded up")
	check(Plan.level_pixels(Vector2i(801, 400), 2) == Vector2i(201, 100), "two levels down: still derived from the finest")
	check(Plan.count_tiles(Vector2(100, 50), 8.0, 0.0, 200) == 11, "Overview has 1+2+8 tiles")

	var detail: Array[Dictionary] = Plan.plan_face(Vector2(30, 15), 16.0, 16.0, 200)
	check(detail.size() == 6, "Detail 30x15 @16 = 3x2 tiles")
	check(detail[0]["pixel_size"] == Vector2i(200, 200), "Detail tile 0,0 is a full 200x200 px tile")
	check(detail[2]["pixel_size"] == Vector2i(80, 200) and detail[3]["pixel_size"] == Vector2i(200, 40), "...the last column is cropped to 80 px, the last row to 40 px")
	check(detail[0]["tile_pixels"] == 200, "the nominal tile size is recorded")
	var corner: Dictionary = detail[5] # column 2, row 1: 5 x 2.5 units at the box's bottom-right
	check(near(corner["tile_size"].x, 5.0) and near(corner["tile_size"].y, 2.5), "cropped tile covers 5 x 2.5 units")
	check(near(corner["offset"].x, 12.5) and near(corner["offset"].y, -6.25), "cropped corner tile centre (12.5, -6.25)")
	var small: Array[Dictionary] = Plan.plan_face(Vector2(20, 10), 4.0, 4.0, 1024)  # 80x40 px: smaller than one tile
	check(small.size() == 1 and small[0]["pixel_size"] == Vector2i(80, 40) and small[0]["tile_pixels"] == 1024, "a level smaller than one tile is one cropped tile")
	check(detail[0]["level"] == 0, "a single level is tagged 0 (tags are per box)")

	var quad: Array[Dictionary] = Plan.plan_face(Vector2(20, 10), 10.0, 10.0, 50)  # 200x100 px, max 50 => 4x2
	check(quad.size() == 8, "20x10 @10 max50 = 4x2")
	check(near(quad[0]["offset"].x, -7.5) and near(quad[0]["offset"].y, 2.5), "tile 0,0 is top-left (u=-7.5, v=2.5)")

	check(Plan.plan_face(Vector2(1, 1), 0.0, 0.0, 4096).is_empty(), "ppu 0 => no tiles")
	var tiny_tiles: int = Plan.level_pixels_per_unit(Vector2(20, 10), 100.0, 0.0, 1).size()
	check(tiny_tiles > 1 and tiny_tiles <= Plan.MAX_LOD_LEVELS, "1 px tiles: the ladder still terminates within MAX_LOD_LEVELS")
	var big: Array[Dictionary] = Plan.plan_face(Vector2(1000, 1000), 100.0, 100.0, 4096)
	check(big.size() == 625, "huge box is tiled 25x25 instead of failing")

	# ── LoD ladder: max ppu halves until the whole box fits one tile ──
	# 20x10 units @100 ppu = 2000x1000 px; with 512 px tiles the longest edge is 2000/1000/500 px at 100/50/25 ppu
	var ladder: Array[float] = Plan.level_pixels_per_unit(Vector2(20, 10), 100.0, 0.0, 512)
	check(same_ppus(ladder, [25.0, 50.0, 100.0]), "halves until the whole box fits one tile => 25/50/100 coarsest first (got %s)" % str(ladder))
	check(same_ppus(Plan.level_pixels_per_unit(Vector2(20, 10), 100.0, 0.0, 500), [25.0, 50.0, 100.0]), "a level exactly the tile size fits and is the overview")
	check(same_ppus(Plan.level_pixels_per_unit(Vector2(20, 10), 100.0, 0.0, 499), [12.5, 25.0, 50.0, 100.0]), "one px too big => one more level")
	check(same_ppus(Plan.level_pixels_per_unit(Vector2(0.5, 0.5), 100.0, 0.0, 1024), [100.0]), "a box that fits one tile at max ppu has a single level")
	var ladder_tiles: Array[Dictionary] = Plan.plan_face(Vector2(20, 10), 100.0, 0.0, 512)
	var level_ppu: Dictionary = {}
	var level_count: Dictionary = {}
	var top_ppu: float = 0.0
	for t in ladder_tiles:
		level_ppu[t["level"]] = t["pixels_per_unit"]
		level_count[t["level"]] = level_count.get(t["level"], 0) + 1
		top_ppu = maxf(top_ppu, t["pixels_per_unit"])
	check(level_ppu.size() == 3 and near(level_ppu[0], 25.0) and near(level_ppu[2], 100.0), "tags 0..2, L0 coarsest, top tag = max ppu")
	check(level_count[0] == 1, "the overview is a single tile")
	check(top_ppu <= 100.0, "no level is rendered above the requested ppu")

	# min ppu: the ladder never goes below it, even if the box does not fit one tile yet; the max level is always kept
	check(same_ppus(Plan.level_pixels_per_unit(Vector2(20, 10), 100.0, 50.0, 512), [50.0, 100.0]), "min 50 stops the ladder at 50")
	check(same_ppus(Plan.level_pixels_per_unit(Vector2(20, 10), 100.0, 40.0, 512), [50.0, 100.0]), "min between two levels drops the lower one")
	check(same_ppus(Plan.level_pixels_per_unit(Vector2(20, 10), 100.0, 25.0, 512), [25.0, 50.0, 100.0]), "level exactly at the min is kept")
	check(same_ppus(Plan.level_pixels_per_unit(Vector2(20, 10), 100.0, 100.0, 512), [100.0]), "min = max => only the max level")
	check(same_ppus(Plan.level_pixels_per_unit(Vector2(20, 10), 100.0, 150.0, 512), [100.0]), "min above max still keeps the max level")

	# overview + best only: the coarsest and finest level, with their real tags
	check(str(Plan.level_tags(4, true)) == "[0, 3]", "extremes of 4 levels")
	check(str(Plan.level_tags(3, true)) == "[0, 2]", "extremes of 3 levels")
	check(str(Plan.level_tags(2, true)) == "[0, 1]", "2 levels are already the extremes")
	check(str(Plan.level_tags(1, true)) == "[0]", "1 level stays")
	check(str(Plan.level_tags(4, false)) == "[0, 1, 2, 3]", "all levels")
	var full: Array[Dictionary] = Plan.plan_face(Vector2(20, 10), 100.0, 0.0, 250)  # 4 levels
	var preview: Array[Dictionary] = Plan.plan_face(Vector2(20, 10), 100.0, 0.0, 250, true)
	var preview_levels: Dictionary = {}
	var in_full: bool = true
	var expected_preview: int = 0
	for t in full:
		if t["level"] == 0 or t["level"] == 3:
			expected_preview += 1
	for p in preview:
		preview_levels[p["level"]] = true
		var found: bool = false
		for f in full:
			if f["level"] == p["level"] and f["col"] == p["col"] and f["row"] == p["row"] and f["pixels_per_unit"] == p["pixels_per_unit"] and f["offset"] == p["offset"]:
				found = true
				break
		in_full = in_full and found
	check(preview_levels.keys() == [0, 3], "preview keeps L0 and the finest, tags unchanged (got %s)" % str(preview_levels.keys()))
	check(in_full, "every preview tile is identical to the same tile of the full plan")
	check(preview.size() == expected_preview, "preview = exactly the L0 and finest tiles")

	# Constant tile size: every tile but the last column/row is exactly tile_pixels, and every tile lies inside
	# the tile (col/2, row/2) of the level below it
	var nest_rng := RandomNumberGenerator.new()
	nest_rng.seed = 7
	var not_constant: int = 0
	var not_nested: int = 0
	for n in 300:
		var nsize := Vector2(nest_rng.randf_range(1.0, 150.0), nest_rng.randf_range(1.0, 150.0))
		var nppu: float = nest_rng.randf_range(1.0, 30.0)
		var ntile: int = [64, 200, 512][nest_rng.randi() % 3]
		var ntiles: Array[Dictionary] = Plan.plan_face(nsize, nppu, 0.0, ntile)
		var lookup: Dictionary = {}
		for t: Dictionary in ntiles:
			lookup[Vector3i(t["level"], t["col"], t["row"])] = t
		for t: Dictionary in ntiles:
			var px: Vector2i = t["pixel_size"]
			if (t["col"] < t["cols"] - 1 and px.x != ntile) or (t["row"] < t["rows"] - 1 and px.y != ntile) or px.x > ntile or px.y > ntile:
				not_constant += 1
			if t["level"] == 0:
				continue
			var parent: Variant = lookup.get(Vector3i(t["level"] - 1, t["col"] / 2, t["row"] / 2))
			if parent == null:
				not_nested += 1
				continue
			var c_min: Vector2 = t["offset"] - t["tile_size"] / 2.0
			var c_max: Vector2 = t["offset"] + t["tile_size"] / 2.0
			var p_min: Vector2 = parent["offset"] - parent["tile_size"] / 2.0
			var p_max: Vector2 = parent["offset"] + parent["tile_size"] / 2.0
			var slack: float = 1e-3
			if c_min.x < p_min.x - slack or c_min.y < p_min.y - slack or c_max.x > p_max.x + slack or c_max.y > p_max.y + slack:
				not_nested += 1
	check(not_constant == 0, "every tile but the last column/row is exactly the tile size (300 random boxes, got %d)" % not_constant)
	check(not_nested == 0, "every tile lies inside the tile (col/2, row/2) of the level below (300 random boxes, got %d)" % not_nested)

	# CountTiles must agree with PlanFace
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var mismatches: int = 0
	for n in 1000:
		var size := Vector2(rng.randf_range(0.1, 40.0), rng.randf_range(0.1, 40.0))
		var ppu: float = rng.randf_range(0.5, 20.0)
		var max_tile: int = [200, 512, 4096, 8192][rng.randi() % 4]
		var min_ppu: float = [0.0, ppu / 8.0, ppu / 2.0, ppu, ppu * 2.0][rng.randi() % 5]
		var extremes: bool = rng.randi() % 2 == 0
		if Plan.count_tiles(size, ppu, min_ppu, max_tile, extremes) != Plan.plan_face(size, ppu, min_ppu, max_tile, extremes).size():
			mismatches += 1
	check(mismatches == 0, "count_tiles == plan_face size (mismatches=%d)" % mismatches)

	# ── writer: y flip, rotation, rounding ───────────────────────────────
	# A box centred at Godot (20, -10), rotated 30° counter-clockwise on screen (Godot: -30° = -0.5236 rad)
	var box: Dictionary = Writer.make_box("Detail", Vector2(20, -10), -deg_to_rad(30.0), Vector2(30, 15))
	check(near(box["transform"]["position"]["x"], 20.0) and near(box["transform"]["position"]["y"], 10.0), "y is negated into Y-up")
	check(near(box["transform"]["rotation"]["z"], 0.258819, 1e-6) and near(box["transform"]["rotation"]["w"], 0.965926, 1e-6), "screen-CCW rotation becomes +30° about z")
	var cw: Dictionary = Writer.make_box("cw", Vector2.ZERO, deg_to_rad(30.0), Vector2(1, 1))
	check(cw["transform"]["rotation"]["z"] < 0.0, "screen-CW rotation becomes negative z")
	var still: Dictionary = Writer.make_box("still", Vector2(0, 0), 0.0, Vector2(1, 1))
	check(str(still["transform"]["position"]["y"]) == "0.0" and str(still["transform"]["rotation"]["z"]) == "0.0", "no negative zero")
	check(near(Writer.make_box("r", Vector2(0.123456, 0), 0.0, Vector2(1, 1))["transform"]["position"]["x"], 0.1235), "positions rounded to 4 dp")

	# ── cross-check against the JS demo dataset ──────────────────────────
	var demo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_demo_path()))
	check(demo.get("schema_version") == 2, "demo loads")
	# same inputs generate-demo.mjs used, expressed the Godot way (y down, clockwise rotation)
	var specs: Dictionary = {
		"Overview": {"pos": Vector2(0, 0), "rot": 0.0, "size": Vector2(100, 50), "min_ppu": 0.0, "tag_offset": 0, "max_ppu": 8.0},
		"Detail": {"pos": Vector2(20, -10), "rot": -deg_to_rad(30.0), "size": Vector2(30, 15), "min_ppu": 16.0, "tag_offset": 3, "max_ppu": 16.0},
		"Corner": {"pos": Vector2(-30, 10), "rot": 0.0, "size": Vector2(20, 10), "min_ppu": 8.0, "tag_offset": 2, "max_ppu": 8.0},
	}
	var doc: Dictionary = Writer.make_document("lod-demo")
	for demo_box: Dictionary in demo["boxes"]:
		var id: String = demo_box["id"]
		var s: Dictionary = specs[id]
		var built: Dictionary = Writer.make_box(id, s["pos"], s["rot"], s["size"])
		var tiles: Array[Dictionary] = Plan.plan_face(s["size"], s["max_ppu"], s["min_ppu"], 200)
		# The planner tags levels per box from 0; the fixture gives hand-placed detail boxes a higher global tag,
		# which the exporters no longer write, so it is added here to keep comparing grids and pixel sizes exactly.
		var by_level: Dictionary = {}
		for t: Dictionary in tiles:
			var tag: int = t["level"] + s["tag_offset"]
			if not by_level.has(tag):
				by_level[tag] = {"info": t, "images": []}
			(by_level[tag]["images"] as Array).append(Writer.image_entry(
				t["col"], t["row"], "%s_Front_L%d_%dx%d.png" % [id, tag, t["col"], t["row"]], t["pixel_size"]))
		for level: int in by_level:
			var info: Dictionary = by_level[level]["info"]
			Writer.add_lod(built, "Front", level, info["pixels_per_unit"], Vector2i(info["cols"], info["rows"]), by_level[level]["images"], info["tile_pixels"])
		Writer.merge_boxes(doc, [built])

	var out: Dictionary = JSON.parse_string(Writer.to_json(doc))
	check(out != null, "writer output is valid JSON")
	var diffs: Array[String] = []
	# the Godot writer emits z=0 for 2D size/position, so compare the fields both formats define
	for i in demo["boxes"].size():
		var a: Dictionary = demo["boxes"][i]
		var b: Dictionary = out["boxes"][i]
		if a["id"] != b["id"]: diffs.append("id %s vs %s" % [a["id"], b["id"]])
		for k in ["x", "y"]:
			if not near(a["transform"]["position"][k], b["transform"]["position"][k]): diffs.append("%s position.%s" % [a["id"], k])
			if not near(a["transform"]["size"][k], b["transform"]["size"][k]): diffs.append("%s size.%s" % [a["id"], k])
		for k in ["z", "w"]:
			if not near(a["transform"]["rotation"][k], b["transform"]["rotation"][k], 1e-6): diffs.append("%s rotation.%s" % [a["id"], k])
		if JSON.stringify(a["faces"], "", true) != JSON.stringify(b["faces"], "", true):
			diffs.append("%s faces differ" % a["id"])
	check(diffs.is_empty(), "Godot writer/planner equals the JS demo dataset: %s" % str(diffs))
	check(out["scenario"] == "lod-demo", "scenario written")

	# ── merge semantics ──────────────────────────────────────────────────
	var merged: Dictionary = Writer.make_document()
	Writer.merge_boxes(merged, [{"id": "a", "v": 1}, {"id": "b", "v": 1}])
	Writer.merge_boxes(merged, [{"id": "b", "v": 2}, {"id": "c", "v": 1}])
	check((merged["boxes"] as Array).size() == 3, "merge keeps others and adds new")
	check(merged["boxes"][1]["v"] == 2, "merge replaces a box with the same id in place")
	Writer.remove_boxes(merged, ["a", "zzz"])
	check((merged["boxes"] as Array).size() == 2 and merged["boxes"][0]["id"] == "b", "remove_boxes drops the named boxes and ignores unknown ids")

	# ── empty tiles ──────────────────────────────────────────────────────
	var Renderer := preload("res://addons/Godot-AreaCapture/capture_renderer.gd")
	var blank := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	check(Renderer.is_empty_tile(blank), "a fully transparent tile is empty")
	blank.fill(Color(1, 0, 0, 0))
	check(Renderer.is_empty_tile(blank), "colour with alpha 0 everywhere is still empty")
	blank.set_pixel(7, 7, Color(0, 0, 0, 0.5))
	check(not Renderer.is_empty_tile(blank), "one visible pixel makes the tile non-empty")
	check(Renderer.is_empty_tile(null), "no image counts as empty")

	# ── zone script: geometry and tile centres ───────────────────────────
	var zone: Area2D = ZoneScript.new()
	root.add_child(zone)
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30, 10)
	shape_node.shape = rect
	shape_node.position = Vector2(10, 20)
	shape_node.rotation = 0.5
	shape_node.scale = Vector2(2, 1)
	zone.add_child(shape_node)
	var geometry: Dictionary = zone._box_from_shape(shape_node)
	check(near(geometry["size"].x, 60.0) and near(geometry["size"].y, 10.0), "shape scale applied to box size")
	check(near(geometry["center"].x, 10.0) and near(geometry["center"].y, 20.0), "box centre = shape position")
	check(near(geometry["rotation"], 0.5), "box rotation = shape rotation")

	var rotated: Dictionary = {"center": Vector2(100, 100), "rotation": PI / 2.0}
	var left_tile: Dictionary = {"offset": Vector2(-5, 0)}
	var c: Vector2 = zone._tile_center(rotated, left_tile)
	check(near(c.x, 100.0) and near(c.y, 95.0), "left tile of a box turned 90° clockwise sits above centre (got %s)" % str(c))
	var up_tile: Dictionary = {"offset": Vector2(0, 5)}
	c = zone._tile_center({"center": Vector2(100, 100), "rotation": 0.0}, up_tile)
	check(near(c.x, 100.0) and near(c.y, 95.0), "an 'up' offset is -y in Godot")

	var used: Dictionary = {}
	check(ZoneScript._unique_id("a", used) == "a" and ZoneScript._unique_id("a", used) == "a_2" and ZoneScript._unique_id("a", used) == "a_3", "unique ids")

	print("%d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


## Dashboard demo dataset the planner/writer must reproduce. Pass another path after `--` to override.
func _demo_path() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		return args[0]
	return ProjectSettings.globalize_path("res://").path_join("../Dashboard/oga-dashboard/tests/fixtures/capture-lod-demo/capture_metadata.json")
