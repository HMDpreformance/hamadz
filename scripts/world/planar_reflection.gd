class_name PlanarReflection
extends Node
## Renders the scene a second time from a camera mirrored through the road
## surface, into a small viewport. The wet-street shader samples it in screen
## space, so buildings, neon, lamps and cars really reflect in the road.
## Runs at a fraction of the screen size; off on the PERFORMANCE preset.

const LAYER_NO_REFLECT := 1 << 9      # visual layer 10: things the mirror camera skips

var main: Camera3D
var plane_y := 0.02
var _vp: SubViewport
var _cam: Camera3D


func setup(scale := 0.5) -> void:
	_vp = SubViewport.new()
	var sz := get_viewport().get_visible_rect().size
	_vp.size = Vector2i(maxi(int(sz.x * scale), 64), maxi(int(sz.y * scale), 36))
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.positional_shadow_atlas_size = 0
	_vp.scaling_3d_scale = 1.0
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.cull_mask = 0xFFFFF & ~LAYER_NO_REFLECT
	_cam.far = 320.0
	_vp.add_child(_cam)
	_cam.make_current()
	StreetSurface.set_reflection(_vp.get_texture())


func texture() -> Texture2D:
	return _vp.get_texture() if _vp else null


func _process(_dt: float) -> void:
	var c := get_viewport().get_camera_3d()
	if c == null or _cam == null:
		return
	var t := c.global_transform
	var o := t.origin
	o.y = 2.0 * plane_y - o.y
	var bx := t.basis.x
	var by := t.basis.y
	var bz := t.basis.z
	bx.y = -bx.y
	by.y = -by.y
	bz.y = -bz.y
	# negate the mirrored up vector to keep a right-handed camera; the shader
	# flips the image vertically to undo it
	_cam.global_transform = Transform3D(Basis(bx, -by, bz), o)
	_cam.fov = c.fov
	_cam.near = c.near
	_cam.keep_aspect = c.keep_aspect


func _exit_tree() -> void:
	StreetSurface.set_reflection(null)
