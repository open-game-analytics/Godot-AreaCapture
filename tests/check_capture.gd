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


func _init() -> void:
	# ── grid / plan ──────────────────────────────────────────────────────
	check(Plan.grid_for(Vector2(100, 50), 2.0, 200) == Vector2i(1, 1), "grid 100x50 @2 max200 = 1x1")
	check(Plan.grid_for(Vector2(100, 50), 4.0, 200) == Vector2i(2, 1), "grid @4 = 2x1")
	check(Plan.grid_for(Vector2(100, 50), 8.0, 200) == Vector2i(4, 2), "grid @8 = 4x2")
	check(Plan.count_tiles(Vector2(100, 50), 2.0, 3, 200) == 11, "Overview has 1+2+8 tiles")

	var detail: Array[Dictionary] = Plan.plan_face(Vector2(30, 15), 16.0, 1, 3, 200)
	check(detail.size() == 6, "Detail 30x15 @16 = 3x2 tiles")
	check(detail[0]["pixel_size"] == Vector2i(160, 120), "Detail tile is 160x120 px")
	check(detail[0]["level"] == 3, "first_level tag applied")

	var quad: Array[Dictionary] = Plan.plan_face(Vector2(20, 10), 10.0, 1, 0, 50)  # 200x100 px, max 50 => 4x2
	check(quad.size() == 8, "20x10 @10 max50 = 4x2")
	check(near(quad[0]["offset"].x, -7.5) and near(quad[0]["offset"].y, 2.5), "tile 0,0 is top-left (u=-7.5, v=2.5)")

	check(Plan.plan_face(Vector2(1, 1), 0.0, 1, 0, 4096).is_empty(), "ppu 0 => no tiles")
	var clamped: Array[Dictionary] = Plan.plan_face(Vector2(1, 1), 100.0, 99, 0, 4096)
	var top_level: int = 0
	for t in clamped:
		top_level = maxi(top_level, t["level"])
	check(top_level == Plan.MAX_LOD_LEVELS - 1, "level count clamped")
	var big: Array[Dictionary] = Plan.plan_face(Vector2(1000, 1000), 100.0, 1, 0, 4096)
	check(big.size() == 625, "huge box is tiled 25x25 instead of failing")

	# CountTiles must agree with PlanFace
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var mismatches: int = 0
	for n in 1000:
		var size := Vector2(rng.randf_range(0.1, 40.0), rng.randf_range(0.1, 40.0))
		var ppu: float = rng.randf_range(0.5, 20.0)
		var levels: int = rng.randi_range(1, 3)
		var max_tile: int = [200, 512, 4096, 8192][rng.randi() % 4]
		if Plan.count_tiles(size, ppu, levels, max_tile) != Plan.plan_face(size, ppu, levels, 0, max_tile).size():
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
		"Overview": {"pos": Vector2(0, 0), "rot": 0.0, "size": Vector2(100, 50), "levels": 3, "first": 0, "ppu": 2.0},
		"Detail": {"pos": Vector2(20, -10), "rot": -deg_to_rad(30.0), "size": Vector2(30, 15), "levels": 1, "first": 3, "ppu": 16.0},
		"Corner": {"pos": Vector2(-30, 10), "rot": 0.0, "size": Vector2(20, 10), "levels": 1, "first": 2, "ppu": 8.0},
	}
	var doc: Dictionary = Writer.make_document("lod-demo")
	for demo_box: Dictionary in demo["boxes"]:
		var id: String = demo_box["id"]
		var s: Dictionary = specs[id]
		var built: Dictionary = Writer.make_box(id, s["pos"], s["rot"], s["size"])
		var tiles: Array[Dictionary] = Plan.plan_face(s["size"], s["ppu"], s["levels"], s["first"], 200)
		var by_level: Dictionary = {}
		for t: Dictionary in tiles:
			if not by_level.has(t["level"]):
				by_level[t["level"]] = {"info": t, "images": []}
			(by_level[t["level"]]["images"] as Array).append(Writer.image_entry(
				t["col"], t["row"], "%s_Front_L%d_%dx%d.png" % [id, t["level"], t["col"], t["row"]], t["pixel_size"]))
		for level: int in by_level:
			var info: Dictionary = by_level[level]["info"]
			Writer.add_lod(built, "Front", level, info["pixels_per_unit"], Vector2i(info["cols"], info["rows"]), by_level[level]["images"])
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
