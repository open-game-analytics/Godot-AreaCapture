extends Area2D
class_name CaptureZone2D

## Provides free-form capture boxes (one per child CollisionShape2D) that export PNG tiles of the
## running scene, at several levels of detail, plus a metadata JSON (schema v2) the OGA dashboard reads.
##
## Boxes can be placed, sized and rotated freely and may overlap. Trigger a capture by starting the
## game with `recapture = true`, or from the command line (nothing is saved into the scene):
##     godot --path <project> -- --capture-areas
## The game must run with a real renderer for the capture to work (SubViewport rendering needs an
## active render loop; --headless has none).
##
## Levels of detail: level i renders at `pixels_per_unit` * 2^i and is split into tiles so that no PNG
## exceeds `max_tile_pixels`. For a hand-placed detail area inside a bigger box, add a second
## CaptureZone2D with a higher `first_level` and `pixels_per_unit`; viewers draw it on top when zoomed in.
## See "Capture Metadata v2" in the dashboard docs.

const CapturePlan := preload("capture_plan.gd")
const CaptureRenderer := preload("capture_renderer.gd")
const MetadataWriter := preload("capture_metadata_writer.gd")

const _CLI_ARG: String = "--capture-areas"

## When true, triggers a capture on the next game start. (Set back to false after capturing: the
## running game cannot save the change into the scene.)
@export var recapture: bool = false

## The directory where the captured images and the metadata file will be saved.
@export_dir var output_directory: String = "res://export/capture/"

## Prefix of box ids and image filenames: <filename>_<shape name>. If empty, the node name is used.
@export var filename: String = "capture_zone_image"

## Name of the metadata JSON written to the output directory. Zones sharing the file merge into it
## (a box replaces an earlier one with the same id), so overview and detail zones end up together.
@export var metadata_filename: String = "capture_metadata.json"

## Scenario name written into the metadata JSON.
@export var scenario: String = ""

@export_group("Levels of detail")

## How many levels of detail to export. Level i is rendered at pixels_per_unit * 2^i.
@export_range(1, 8) var lod_levels: int = 1

## LoD level tag of this zone's first level. Keep 0 for an overview zone; give a detail zone placed
## inside a larger one a higher tag (and a higher pixels_per_unit).
@export_range(0, 16) var first_level: int = 0

## Image pixels per world unit at the first level. The Godot 2D world is measured in pixels, so 1 is
## native resolution.
@export_range(0.1, 64.0, 0.1, "or_greater") var pixels_per_unit: float = 1.0

## Largest edge of any exported PNG. Bigger areas are split into a grid of tiles.
@export_range(64, 16384) var max_tile_pixels: int = 4096

@export_group("Rendering")

## Which visibility layers (CanvasItem.visibility_layer) appear in the capture. Move e.g. the player to
## another layer and untick it here to leave it out of the map.
@export_flags_2d_render var render_layers: int = 0xFFFFF


func _ready() -> void:
	var from_command_line: bool = _CLI_ARG in OS.get_cmdline_user_args()
	if recapture or from_command_line:
		await _run_capture()
		if from_command_line:
			get_tree().quit()


## Captures one child collision shape as a single image at the first level's resolution (no tiling).
## Kept for scripts that only need one Image; the export uses render_tile() per planned tile.
## Returns an Image or null if failed.
func capture_content(child: Node2D = null) -> Image:
	var collision_shape := child as CollisionShape2D
	if collision_shape == null or collision_shape.shape == null:
		push_warning("CaptureZone2D: Provided node is not a supported collision shape.")
		return null

	var box: Dictionary = _box_from_shape(collision_shape)
	var tiles: Array[Dictionary] = CapturePlan.plan_face(box["size"], pixels_per_unit, 1, first_level, 1 << 30)
	if tiles.is_empty():
		push_warning("CaptureZone2D: Capture area is empty or invalid.")
		return null

	var tile: Dictionary = tiles[0]
	return await CaptureRenderer.render_tile(self, box["center"], box["rotation"], tile["pixels_per_unit"], tile["pixel_size"], render_layers)


## Captures every child CollisionShape2D as a box (all levels, all tiles) and writes the images and
## the metadata JSON. Runs when the game starts with recapture=true or --capture-areas.
func _run_capture() -> void:
	recapture = false
	print("[CaptureZone2D] '%s': capture started, output='%s'" % [name, output_directory])

	if not DirAccess.dir_exists_absolute(output_directory):
		DirAccess.make_dir_recursive_absolute(output_directory)

	var max_tile: int = clampi(max_tile_pixels, 64, 16384)
	var prefix: String = filename if filename != "" else name
	var boxes: Array = []
	var used_ids: Dictionary = {}

	for child in get_children():
		var collision_shape := child as CollisionShape2D
		if collision_shape == null or collision_shape.shape == null:
			continue

		var geometry: Dictionary = _box_from_shape(collision_shape)
		var size: Vector2 = geometry["size"]
		var tiles: Array[Dictionary] = CapturePlan.plan_face(size, pixels_per_unit, lod_levels, first_level, max_tile)
		if tiles.is_empty():
			push_warning("CaptureZone2D: '%s' has no area and was skipped." % collision_shape.name)
			continue

		var id: String = _unique_id("%s_%s" % [prefix, collision_shape.name], used_ids)
		var box: Dictionary = MetadataWriter.make_box(id, geometry["center"], geometry["rotation"], size)

		var level_images: Dictionary = {} # level -> Array of image entries, in tile order
		var level_info: Dictionary = {} # level -> {pixels_per_unit, grid}
		var failed: bool = false

		for tile: Dictionary in tiles:
			var tile_name: String = "%s_%s_L%d_%dx%d.png" % [id, MetadataWriter.FACE_2D, tile["level"], tile["col"], tile["row"]]
			var save_path: String = output_directory.path_join(tile_name)

			var pixel_size: Vector2i = tile["pixel_size"]
			var image: Image = await CaptureRenderer.render_tile(
				self,
				_tile_center(geometry, tile),
				geometry["rotation"],
				tile["pixels_per_unit"],
				pixel_size,
				render_layers)
			if image == null:
				push_error("CaptureZone2D: rendering '%s' failed." % tile_name)
				failed = true
				break

			var err: Error = image.save_png(save_path)
			if err != OK:
				push_error("CaptureZone2D: Failed to save '%s' (err=%d)" % [save_path, err])
				failed = true
				break

			var level: int = tile["level"]
			if not level_images.has(level):
				level_images[level] = []
				level_info[level] = {"pixels_per_unit": tile["pixels_per_unit"], "grid": Vector2i(tile["cols"], tile["rows"])}
			(level_images[level] as Array).append(MetadataWriter.image_entry(tile["col"], tile["row"], tile_name, pixel_size))

		if failed:
			continue

		for level: int in level_images:
			var info: Dictionary = level_info[level]
			MetadataWriter.add_lod(box, MetadataWriter.FACE_2D, level, info["pixels_per_unit"], info["grid"], level_images[level])
		boxes.append(box)
		print("[CaptureZone2D] '%s': saved %d tile(s) for box '%s'" % [name, tiles.size(), id])

	if boxes.is_empty():
		push_warning("CaptureZone2D: No valid collision shapes found or all captures failed.")
		return

	_write_metadata(boxes)


## World-space geometry of a child shape as an oriented box: its centre, rotation (radians) and size.
## Uses the shape's own rotation and scale, so free-form boxes come out aligned to themselves.
func _box_from_shape(collision_shape: CollisionShape2D) -> Dictionary:
	var local_rect: Rect2 = collision_shape.shape.get_rect()
	var xform: Transform2D = collision_shape.global_transform
	var scale_abs: Vector2 = xform.get_scale().abs()
	return {
		"center": xform * local_rect.get_center(),
		"rotation": xform.get_rotation(),
		"size": Vector2(local_rect.size.x * scale_abs.x, local_rect.size.y * scale_abs.y),
	}


## Centre of a planned tile in Godot world coordinates. The plan's offset is (right, up) in the box's
## own frame; Godot's y axis points down, so up is -y before rotating by the box's rotation.
func _tile_center(geometry: Dictionary, tile: Dictionary) -> Vector2:
	var offset: Vector2 = tile["offset"]
	var center: Vector2 = geometry["center"]
	return center + Vector2(offset.x, -offset.y).rotated(geometry["rotation"])


## Merge these boxes into the metadata file (zones share it); a legacy or unreadable file is replaced.
func _write_metadata(boxes: Array) -> void:
	var meta_path: String = output_directory.path_join(metadata_filename)
	var doc: Dictionary = MetadataWriter.make_document(scenario)

	if FileAccess.file_exists(meta_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if parsed is Dictionary and (parsed as Dictionary).get("schema_version") == MetadataWriter.SCHEMA_VERSION \
				and (parsed as Dictionary).get("boxes") is Array:
			doc = parsed
			if scenario != "":
				doc["scenario"] = scenario

	MetadataWriter.merge_boxes(doc, boxes)

	var meta_file := FileAccess.open(meta_path, FileAccess.WRITE)
	if meta_file == null:
		push_error("CaptureZone2D: cannot write '%s' (err=%d)" % [meta_path, FileAccess.get_open_error()])
		return
	meta_file.store_string(MetadataWriter.to_json(doc))
	meta_file.close()
	print("[CaptureZone2D] '%s': metadata saved to '%s'" % [name, meta_path])


static func _unique_id(base: String, used: Dictionary) -> String:
	var id: String = base
	var n: int = 2
	while used.has(id):
		id = "%s_%d" % [base, n]
		n += 1
	used[id] = true
	return id
