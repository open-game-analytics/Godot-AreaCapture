extends RefCounted

## Builds and serialises capture metadata schema v2 (box -> face -> LoD level -> tiles).
## See "Capture Metadata v2" in the dashboard docs.
##
## The file is Y-up like Unity's. Godot 2D is Y-down with clockwise-positive rotation, so make_box()
## negates y and the rotation angle. Images are NOT flipped: Godot's screen-up is already -y.

const SCHEMA_VERSION: int = 2

## Positions and sizes are rounded to 4 decimals, quaternions to 6 (as in the Unity exporter).
const _VECTOR_STEP: float = 0.0001
const _QUATERNION_STEP: float = 0.000001

## 2D games export their single face as "Front" (the plane the dashboard shows when it drops Z).
const FACE_2D: String = "Front"


static func make_document(scenario: String = "") -> Dictionary:
	var doc: Dictionary = {"schema_version": SCHEMA_VERSION}
	if scenario != "":
		doc["scenario"] = scenario
	doc["boxes"] = []
	return doc


## One box, in Godot coordinates. `godot_rotation` is Node2D-style radians (clockwise on screen).
static func make_box(id: String, godot_center: Vector2, godot_rotation: float, size: Vector2) -> Dictionary:
	var angle_y_up: float = -godot_rotation
	return {
		"id": id,
		"transform": {
			"position": _vec3(godot_center.x, -godot_center.y, 0.0),
			"rotation": {
				"x": 0.0,
				"y": 0.0,
				"z": _snap(sin(angle_y_up / 2.0), _QUATERNION_STEP),
				"w": _snap(cos(angle_y_up / 2.0), _QUATERNION_STEP),
			},
			"size": _vec3(size.x, size.y, 0.0),
		},
		"faces": {},
	}


## Append one LoD level (its tiles) to a box's face.
static func add_lod(box: Dictionary, face: String, level: int, pixels_per_unit: float, grid: Vector2i, images: Array) -> void:
	var faces: Dictionary = box["faces"]
	if not faces.has(face):
		faces[face] = {"lods": []}
	var lods: Array = faces[face]["lods"]
	lods.append({
		"level": level,
		"pixels_per_unit": _snap(pixels_per_unit, _VECTOR_STEP),
		"grid": [grid.x, grid.y],
		"images": images,
	})


static func image_entry(col: int, row: int, filename: String, pixel_size: Vector2i) -> Dictionary:
	return {"col": col, "row": row, "filename": filename, "pixel_size": [pixel_size.x, pixel_size.y]}


## Merge boxes into a document: a box replaces an existing one with the same id, others are kept.
static func merge_boxes(doc: Dictionary, boxes: Array) -> void:
	var existing: Array = doc["boxes"]
	for box: Dictionary in boxes:
		var replaced: bool = false
		for i in existing.size():
			if (existing[i] as Dictionary).get("id") == box["id"]:
				existing[i] = box
				replaced = true
				break
		if not replaced:
			existing.append(box)


static func to_json(doc: Dictionary) -> String:
	return JSON.stringify(doc, "\t") + "\n"


static func _vec3(x: float, y: float, z: float) -> Dictionary:
	return {"x": _snap(x, _VECTOR_STEP), "y": _snap(y, _VECTOR_STEP), "z": _snap(z, _VECTOR_STEP)}


## Round to a step and never produce -0.0 (which would serialise as "-0.0").
static func _snap(value: float, step: float) -> float:
	var snapped_value: float = snappedf(value, step)
	return 0.0 if snapped_value == 0.0 else snapped_value
