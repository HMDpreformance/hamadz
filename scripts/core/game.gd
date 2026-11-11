extends Node
## Player profile + persistence (autoload "Game").
## Everything the player owns or has configured lives in `data` and is written
## to user://save.json after every change.

signal money_changed(amount: int)
signal saved

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const START_MONEY := 60000

var data := {}
var no_save := false     # dev/test runs never touch the real save


func _ready() -> void:
	load_game()
	GFX.set_preset(int(data.settings.preset))


func _fresh() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"money": START_MONEY,
		"current_car": "tuner",
		"owned_cars": ["tuner"],
		"configs": {},
		"owned_parts": {},
		"best_time": 0.0,
		"runs": 0,
		"settings": {"preset": 1, "music": 0.8, "sfx": 0.9, "steer_mode": 0, "show_fps": false},
	}


func load_game() -> void:
	data = _fresh()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY and int(parsed.get("version", 0)) == SAVE_VERSION:
				for k in parsed:
					if k == "settings":
						for sk in parsed[k]:
							data.settings[sk] = parsed[k][sk]
					else:
						data[k] = parsed[k]
	data.money = int(data.money)
	for id in CarDB.CAR_ORDER:
		_ensure_car(id)


func _ensure_car(id: String) -> void:
	var dc := CarDB.default_config(id)
	var cfg: Dictionary = data.configs.get(id, {})
	for k in dc:
		cfg[k] = int(cfg.get(k, dc[k]))
	data.configs[id] = cfg
	var dof := CarDB.default_owned(id)
	var own: Dictionary = data.owned_parts.get(id, {})
	for k in dof:
		var arr := []
		for v in own.get(k, dof[k]):
			arr.append(int(v))
		for v in dof[k]:
			if not arr.has(v):
				arr.append(v)
		own[k] = arr
	data.owned_parts[id] = own


func save_game() -> void:
	if no_save:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		saved.emit()


func reset_progress() -> void:
	var settings = data.settings
	data = _fresh()
	data.settings = settings
	for id in CarDB.CAR_ORDER:
		_ensure_car(id)
	save_game()
	money_changed.emit(data.money)


# ------------------------------------------------------------------ queries
func money() -> int:
	return int(data.money)


func current_car() -> String:
	return data.current_car


func config(car_id: String = "") -> Dictionary:
	if car_id == "":
		car_id = data.current_car
	return data.configs[car_id]


func owns_car(id: String) -> bool:
	return data.owned_cars.has(id)


func owns_part(car_id: String, slot: String, idx: int) -> bool:
	return data.owned_parts[car_id][slot].has(idx)


func setting(key: String, def = null):
	return data.settings.get(key, def)


# ------------------------------------------------------------------ mutations
func set_setting(key: String, value) -> void:
	data.settings[key] = value
	save_game()


func add_money(amount: int) -> void:
	data.money = int(data.money) + amount
	money_changed.emit(data.money)
	save_game()


func buy_car(id: String) -> bool:
	if owns_car(id):
		return true
	var price: int = CarDB.CARS[id].price
	if data.money < price:
		return false
	data.money -= price
	data.owned_cars.append(id)
	money_changed.emit(data.money)
	save_game()
	return true


func select_car(id: String) -> void:
	if owns_car(id):
		data.current_car = id
		save_game()


## Buys (if needed) and installs an option. Returns "ok", "poor" or "locked".
func install_part(car_id: String, slot: String, idx: int) -> String:
	if not owns_car(car_id):
		return "locked"
	if not owns_part(car_id, slot, idx):
		var price: int = CarDB.parts()[slot].options[idx].price
		if data.money < price:
			return "poor"
		data.money -= price
		data.owned_parts[car_id][slot].append(idx)
		money_changed.emit(data.money)
	data.configs[car_id][slot] = idx
	save_game()
	return "ok"


func record_run(time: float) -> bool:
	data.runs = int(data.runs) + 1
	var best := float(data.best_time)
	var is_best := best <= 0.0 or time < best
	if is_best:
		data.best_time = time
	save_game()
	return is_best
