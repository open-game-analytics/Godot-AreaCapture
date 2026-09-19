extends RefCounted

## Renders one tile of a 2D area to an Image.
##
## A SubViewport that shares the running scene's World2D is pointed at the tile by a Camera2D:
## zoom = pixels per unit, rotation = the box's rotation (so a rotated box comes out aligned to
## itself), position = the tile centre. Needs the game to be running with a real renderer
## (--headless uses the dummy renderer and produces no image).


## `center` and `rotation` are in Godot world coordinates. `cull_mask` selects the visibility layers
## (CanvasItem.visibility_layer) that are drawn, so e.g. the player can be left out of the map.
## Returns null if there is no viewport to share.
static func render_tile(host: Node, center: Vector2, rotation: float, pixels_per_unit: float, pixel_size: Vector2i, cull_mask: int) -> Image:
	var viewport: Viewport = host.get_viewport()
	if viewport == null:
		push_warning("CaptureRenderer: no viewport available.")
		return null

	var sub_viewport := SubViewport.new()
	sub_viewport.size = pixel_size
	sub_viewport.transparent_bg = true
	sub_viewport.disable_3d = true
	sub_viewport.canvas_cull_mask = cull_mask
	sub_viewport.world_2d = viewport.world_2d
	# Wait until the camera is in place before drawing, to avoid a blank frame.
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(sub_viewport)

	var camera := Camera2D.new()
	camera.ignore_rotation = false # Camera2D ignores its own rotation by default
	camera.rotation = rotation
	camera.zoom = Vector2(pixels_per_unit, pixels_per_unit)
	camera.position = center
	sub_viewport.add_child(camera)
	camera.make_current()

	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await host.get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = sub_viewport.get_texture().get_image()

	host.remove_child(sub_viewport)
	sub_viewport.queue_free()
	return image
