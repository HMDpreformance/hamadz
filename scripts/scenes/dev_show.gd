extends Node3D
## Dev-only showroom for iterating on the procedural cars.
var car: CarVisual
var cam: Camera3D

func _ready() -> void:
	var we := WorldEnvironment.new()
	we.environment = GFX.make_environment(Color(0.5, 0.55, 0.7), 0.22, Color.BLACK, 0.0, EnvKit.studio_sky())
	we.environment.background_color = Color(0.05, 0.05, 0.07)
	add_child(we)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(30, 30)
	fl.mesh = pm; fl.material_override = EnvKit.solid(Color(0.12, 0.12, 0.13), 0.5)
	add_child(fl)
	var l := DirectionalLight3D.new(); l.rotation_degrees = Vector3(-50, 40, 0); l.light_energy = 0.8; add_child(l)
	var l2 := OmniLight3D.new(); l2.position = Vector3(-3, 2, -3); l2.omni_range = 9; l2.light_energy = 2.0; add_child(l2)
	car = CarVisual.new(); add_child(car)
	cam = Camera3D.new(); add_child(cam); cam.fov = 40
	var id := OS.get_environment("AH_CAR")
	if id == "": id = "tuner"
	var cfg := CarDB.default_config(id)
	var extra = JSON.parse_string(OS.get_environment("AH_CFG"))
	if typeof(extra) == TYPE_DICTIONARY:
		for k in extra: cfg[k] = int(extra[k])
	car.setup(id, cfg)
	dev_cam("35", "12", "6.5")

func dev_cam(yaw: String, pitch: String, dist: String) -> void:
	var y := deg_to_rad(float(yaw)); var p := deg_to_rad(float(pitch)); var d := float(dist)
	cam.position = Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p)) * d + Vector3(0, 0.6, 0)
	cam.look_at(Vector3(0, 0.6, 0))
