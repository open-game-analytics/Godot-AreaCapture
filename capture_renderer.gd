extends RefCounted

## Renders one tile of a 2D area to an Image.
##
## A SubViewport that shares the scene's World2D draws the tile. The view is set with the viewport's
## canvas_transform (see view_transform()) and not with a Camera2D: in the editor, a Camera2D under a
## SubViewport that belongs to the edited scene is ignored (every tile then shows the world origin),
## while canvas_transform works both in the editor and in a running game. Needs a real renderer
## (--headless uses the dummy renderer and produces no image).


## Maps world coordinates to tile pixels: the tile centre `center` lands in the middle of a
## `pixel_size` image, one world unit becomes `pixels_per_unit` pixels, and the view is turned by
## `rotation` (radians, in Godot world coordinates) so that a rotated box comes out aligned to itself.
## It has the same effect as a Camera2D at `center` with that zoom and rotation.
static func view_transform(center: Vector2, rotation: float, pixels_per_unit: float, pixel_size: Vector2i) -> Transform2D:
	var transform := Transform2D(-rotation, Vector2.ZERO).scaled(Vector2(pixels_per_unit, pixels_per_unit))
	transform.origin = Vector2(pixel_size) / 2.0 - transform.basis_xform(center)
	return transform


## `center` and `rotation` are in Godot world coordinates. `cull_mask` selects the visibility layers
## (CanvasItem.visibility_layer) that are drawn, so e.g. the player can be left out of the map.
## `host` must be in the scene tree. Returns null if there is no viewport to share.
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
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(sub_viewport)
	# Only once the viewport is in the tree does it have a canvas to transform; before that the setting is rejected.
	sub_viewport.canvas_transform = view_transform(center, rotation, pixels_per_unit, pixel_size)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	await host.get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = sub_viewport.get_texture().get_image()

	host.remove_child(sub_viewport)
	sub_viewport.queue_free()
	return image


## True when a rendered tile has nothing to show: every pixel is fully transparent (or there is no image).
## Only meaningful with a transparent background, which render_tile() always uses.
static func is_empty_tile(image: Image) -> bool:
	return image == null or image.is_invisible()
