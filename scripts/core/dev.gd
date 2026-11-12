extends Node
## Development helper (autoload "Dev"). Inactive unless the AH_DEV environment
## variable is set, e.g.
##   AH_DEV="scene=garage;wait=2.0;call=dev_focus:wheel;shot=shots/garage.png"
## Steps run in order; used for automated screenshots and smoke tests.

func _ready() -> void:
	var spec := OS.get_environment("AH_DEV")
	if spec == "":
		return
	Game.no_save = true
	_run.call_deferred(spec)


func _run(spec: String) -> void:
	for step in spec.split(";", false):
		var kv := step.split("=", true, 1)
		var k := kv[0].strip_edges()
		var v := kv[1] if kv.size() > 1 else ""
		match k:
			"scene":
				await get_tree().process_frame
				get_tree().change_scene_to_file(Nav.SCENES[v])
				Nav.current = v
				await get_tree().process_frame
				await get_tree().process_frame
			"goto":
				Nav.goto(v)
				await Nav.scene_ready
			"wait":
				await get_tree().create_timer(float(v)).timeout
			"call":
				var parts := v.split(":")
				var sc := get_tree().current_scene
				var a := []
				for i in range(1, parts.size()):
					a.append(parts[i])
				if sc and sc.has_method(parts[0]):
					sc.callv(parts[0], a)
				else:
					push_error("Dev: no method " + parts[0])
			"shot":
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + v.get_base_dir()))
				img.save_png("res://shots/" + v + ".png")
				print("Dev: saved ", v)
			"check":
				var stack := ["res://scripts"]
				var cnt := 0
				while not stack.is_empty():
					var d: String = stack.pop_back()
					for f in DirAccess.get_files_at(d):
						if f.ends_with(".gd"):
							var sc = load(d + "/" + f)
							cnt += 1
							if sc == null or not sc.can_instantiate():
								print("FAILED: ", d + "/" + f)
					for sub in DirAccess.get_directories_at(d):
						stack.append(d + "/" + sub)
				print("checked ", cnt, " scripts")
			"press":
				Input.action_press(v)
			"release":
				Input.action_release(v)
			"solo":
				# engine/car audio only: no music, no ambience (for audio captures)
				AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)
				Audio.play_ambience("")
				Audio.set_meta("solo", true)
			"ride":
				# ride=muscle,turbo:3,exhaust:2  -> test a car + parts without touching the save
				Game.no_save = true
				var bits := v.split(",")
				Game._ensure_car(bits[0])
				Game.data.current_car = bits[0]
				if not Game.data.owned_cars.has(bits[0]):
					Game.data.owned_cars.append(bits[0])
				for i in range(1, bits.size()):
					var sv := bits[i].split(":")
					Game.data.configs[bits[0]][sv[0]] = int(sv[1])
			"quit":
				get_tree().quit()
	get_tree().quit()
