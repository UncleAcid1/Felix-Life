extends Node

# --- CONFIGURATION ---
var ant_scene_path = "res://scenes/ant.tscn"
var ant_scene_resource = null
const Ant = preload("res://ant.gd") 

# --- REFERENCES ---
@onready var audio_manager = get_node("/root/TestLevel/AudioManager")
@onready var chunk_grid = get_node("/root/TestLevel/ChunkGrid")

# --- ECONOMY & RESOURCES ---
var money: int = 500
var fungus_inventory: int = 0

# GLOBAL INVENTORY (Virtual Storage)
var food_inventory = {
	"basic": 0, "common": 0, "rare": 0, "legendary": 0
}

# DINING HALL STORAGE (Physical Storage)
# Format: { structure_id: { "basic": 0 } } -> NOW BASIC ONLY
var dining_hall_contents = {} 

# --- CONSTRUCTION QUEUE ---
var pending_builds = [] 

# --- BUSINESS LOGIC ---
# Tracks how many seeds are currently needed by farmers
var seed_requests = {
	"basic": 0, "common": 0, "rare": 0, "legendary": 0
}

# --- LEVELING SYSTEM ---
var colony_level: int = 1
var current_xp: int = 0
var xp_to_next_level: int = 100

# --- TIME SYSTEM ---
var time_mode = "real_time"
var is_daytime = true

# --- INVENTORY ---
var seeds_owned = {
	"basic": 0, "common": 0, "rare": 0, "legendary": 0
}

# --- DEFINITIONS ---
var fungus_types = {
	"basic":     {"buy_cost": 10,   "sell_price": 15,   "grow_time": 60.0,  "food_value": 100,  "unlock_level": 1},
	"common":    {"buy_cost": 50,   "sell_price": 75,   "grow_time": 120.0, "food_value": 100,  "unlock_level": 2},
	"rare":      {"buy_cost": 250,  "sell_price": 400,  "grow_time": 300.0, "food_value": 100,  "unlock_level": 4},
	"legendary": {"buy_cost": 1000, "sell_price": 2500, "grow_time": 600.0, "food_value": 100, "unlock_level": 6}
}

# ROOM DEFINITIONS
var room_types = {
	"tunnel": { 
		"cost": 5, "color": Color("21160E"), "display_name": "Dirt Tunnel", 
		"size": Vector2(1, 1), "build_time": 2.0, "unlock_level": 1, "is_room": false 
	},
	"sleeping_quarters": { 
		"cost": 150, "color": Color(0.2, 0.2, 0.4, 0.9), "display_name": "Sleeping Qtrs", 
		"size": Vector2(2, 4), "build_time": 8.0, "unlock_level": 2, "is_room": true 
	},
	"farming_room": { 
		"cost": 300, "color": Color(0.1, 0.3, 0.1, 0.9), "display_name": "Fungal Farm", 
		"size": Vector2(2, 2), "build_time": 5.0, "unlock_level": 3, "is_room": true 
	},
	"dining_hall": { 
		"cost": 500, "color": Color(0.4, 0.2, 0.1, 0.9), "display_name": "Dining Hall", 
		"size": Vector2(3, 4), "build_time": 12.0, "unlock_level": 4, "is_room": true 
	}
}

# --- COLONY STATE ---
var ants = []
var colony_population = 0
var next_ant_cost = 150
var recruit_unlock_level = 2

# --- AKIRA STATE ---
var akira_discovered = false
var akira_chunk_pos = Vector2(-1, -1)

var ant_names_db = [
	"Larry", "Berry", "Hal", "Ripley", "Deckard", "Tron", "Flynn",
	"Moog", "Roland", "Korg", "Oberheim", "Sawtooth", "Square",
	"Neo", "Boyd", "Isaac", "I-Kinnard", "Jack Likes Femboys", "Jerry",
	"Joseph", "Jimmy", "Gabriel", "Borat", "Vlad", "Vladmir",
	"Nandor", "Guillermo"
]

var built_rooms = {} 
var room_instances = {} # { structure_id: { "type": type, "chunks": [], "target_seed": "basic" } }

# --- SIGNALS ---
signal money_changed(new_amount)
signal food_changed(new_amount)
signal seeds_changed(type, new_amount)
signal system_message(text, color)
signal population_changed(new_count)
signal xp_changed(current, max_xp, level)
signal level_up(new_level)
signal time_changed(is_day)
signal akira_state_changed(is_discovered)
signal task_assignment_needed(task_type, target_pos, data) 

func _ready():
	if ResourceLoader.exists(ant_scene_path):
		ant_scene_resource = load(ant_scene_path)
	
	for key in room_types.keys():
		built_rooms[key] = []
		
	call_deferred("emit_signal", "money_changed", money)
	call_deferred("emit_signal", "xp_changed", current_xp, xp_to_next_level, colony_level)
	
	check_time_of_day()

func _process(_delta):
	check_time_of_day()

# --- CONSTRUCTION QUEUE LOGIC ---
func add_to_build_queue(task_data):
	for t in pending_builds:
		if t["target_pos"] == task_data["target_pos"]: return
	
	pending_builds.append(task_data)

func cancel_task_at(pos: Vector2):
	for i in range(pending_builds.size() - 1, -1, -1):
		if pending_builds[i]["target_pos"] == pos:
			pending_builds.remove_at(i)

	for ant in ants:
		if ant.task_data.has("target_pos") and ant.task_data["target_pos"] == pos:
			ant.abort_task()

func get_reachable_build_task() -> Dictionary:
	# Standard check for ANY ant (global queue)
	if pending_builds.size() == 0: return {}
	
	for i in range(pending_builds.size()):
		var task = pending_builds[i]
		var target = task["target_pos"]
		var size = task["size"]
		
		var stand_pos = chunk_grid.get_multitile_access_point(target, size)
		
		if stand_pos != Vector2(-1, -1):
			pending_builds.remove_at(i)
			return task
			
	return {}

# Forced proximity check for wandering builders
func get_nearest_pending_build_task(ant_pos_world: Vector2) -> Dictionary:
	if pending_builds.size() == 0: return {}
	
	var nearest_idx = -1
	var min_dist = 300.0 # Must be somewhat close
	
	for i in range(pending_builds.size()):
		var task = pending_builds[i]
		
		# CRITICAL FIX: Ensure target_pos is Vector2 before using it
		var target_pos = task["target_pos"]
		if target_pos is String:
			target_pos = _parse_vector_string(target_pos)
			task["target_pos"] = target_pos # Update the array so we don't parse again
			
		var target_world = chunk_grid.chunk_to_world_position(target_pos)
		var dist = ant_pos_world.distance_to(target_world)
		
		if dist < min_dist:
			# Accessibility check
			# Also ensure 'size' is a Vector2
			var size = task["size"]
			if size is String: 
				size = _parse_vector_string(size)
				task["size"] = size
				
			var stand_pos = chunk_grid.get_multitile_access_point(target_pos, size)
			if stand_pos != Vector2(-1, -1):
				min_dist = dist
				nearest_idx = i
				
	if nearest_idx != -1:
		var task = pending_builds[nearest_idx]
		pending_builds.remove_at(nearest_idx)
		return task
		
	return {}

func _parse_vector_string(s: String) -> Vector2:
	var clean = s.replace("(", "").replace(")", "")
	var parts = clean.split(",")
	if parts.size() >= 2:
		return Vector2(float(parts[0]), float(parts[1]))
	return Vector2.ZERO

# --- BUSINESS / SEED REQUEST LOGIC ---
func report_seed_need(type: String):
	seed_requests[type] += 1
	if seed_requests[type] > 10: seed_requests[type] = 10

func fulfill_seed_request(type: String):
	if seed_requests[type] > 0:
		seed_requests[type] -= 1

# --- ROOM SETTINGS (FARMING) ---
func set_room_target_seed(structure_id: int, seed_type: String):
	if room_instances.has(structure_id):
		room_instances[structure_id]["target_seed"] = seed_type
		send_message("Farm set to grow: " + seed_type.capitalize(), Color.GREEN)

func get_room_target_seed(structure_id: int) -> String:
	if room_instances.has(structure_id):
		return room_instances[structure_id].get("target_seed", "basic")
	return "basic"

# --- HELPER FOR FARMER ANTS ---
func get_all_farm_chunks() -> Array:
	var farms = []
	if built_rooms.has("farming_room"):
		for pos in built_rooms["farming_room"]:
			if chunk_grid.is_chunk_walkable(pos):
				farms.append(pos)
	return farms

# --- TIME LOGIC ---
func check_time_of_day():
	var new_is_day = is_daytime
	match time_mode:
		"real_time":
			var time = Time.get_time_dict_from_system()
			var hour = time.hour
			if hour >= 6 and hour < 21: new_is_day = true
			else: new_is_day = false
		"always_day": new_is_day = true
		"always_night": new_is_day = false
			
	if new_is_day != is_daytime:
		is_daytime = new_is_day
		emit_signal("time_changed", is_daytime)
		if audio_manager:
			var state = "day" if is_daytime else "night"
			audio_manager.set_time_state(state)

func set_time_mode(mode: String):
	time_mode = mode
	check_time_of_day()

# --- MANUAL TASK SYSTEM ---
func request_task(type: String, target_pos: Vector2, data: Dictionary = {}):
	emit_signal("task_assignment_needed", type, target_pos, data)

func assign_specific_task(ant, type: String, target_pos: Vector2, data: Dictionary):
	if not is_instance_valid(ant): return
	data["is_manual"] = true
	var task = {"type": type, "target_pos": target_pos, "data": data}
	ant.assign_task(task)
	send_message(ant.ant_name + " assigned to " + type + ".", Color.WHITE)

# --- DINING HALL LOGIC ---
func add_food_to_dining_hall(structure_id: int, type: String, amount: int = 1):
	# RESTRICTION: BASIC ONLY
	if type != "basic":
		send_message("Dining Halls only accept Basic food!", Color.RED)
		return

	if not dining_hall_contents.has(structure_id):
		dining_hall_contents[structure_id] = { "basic": 0 }
	
	if food_inventory[type] >= amount:
		food_inventory[type] -= amount
		dining_hall_contents[structure_id]["basic"] += amount
		emit_signal("food_changed", get_total_food())
	else:
		print("Error: Not enough global food to move to dining hall")

func withdraw_food_from_dining_hall(structure_id: int, type: String, amount: int = 1):
	if not dining_hall_contents.has(structure_id): return
	if dining_hall_contents[structure_id].get(type, 0) >= amount:
		dining_hall_contents[structure_id][type] -= amount
		food_inventory[type] += amount
		emit_signal("food_changed", get_total_food())

func consume_from_dining_hall(structure_id: int) -> int:
	if not dining_hall_contents.has(structure_id): return 0
	# ONLY CONSUME BASIC
	if dining_hall_contents[structure_id].get("basic", 0) > 0:
		dining_hall_contents[structure_id]["basic"] -= 1
		return fungus_types["basic"]["food_value"]
	return 0

func get_dining_hall_contents(structure_id: int) -> Dictionary:
	if dining_hall_contents.has(structure_id):
		return dining_hall_contents[structure_id]
	return { "basic": 0 }

# --- SAVE SYSTEM ---
func save_game():
	ants.clear()
	for child in chunk_grid.get_children():
		if child is Ant and not child.is_queued_for_deletion():
			ants.append(child)
	
	var save_data = {
		"timestamp": Time.get_unix_time_from_system(),
		"money": money,
		"food": food_inventory,
		"dining_contents": dining_hall_contents,
		"xp": current_xp,
		"lvl": colony_level,
		"xp_needed": xp_to_next_level,
		"seeds": seeds_owned,
		"time_mode": time_mode,
		"ants": [],
		"chunks": {},
		"fungi": [],
		"akira": { "discovered": akira_discovered, "pos_x": akira_chunk_pos.x, "pos_y": akira_chunk_pos.y },
		"pending_builds": pending_builds,
		"room_instances": room_instances 
	}
	
	for ant in ants:
		if not is_instance_valid(ant): continue
		var ant_data = {
			"name": ant.ant_name,
			"pos_x": ant.position.x, "pos_y": ant.position.y,
			"hunger": ant.hunger, "sleep": ant.sleep,
			"happiness": ant.happiness,
			"job_role": ant.job_role,
			"assigned_room_id": ant.assigned_room_id,
			"business_target_seed": ant.business_target_seed
		}
		save_data["ants"].append(ant_data)
		
	for pos in chunk_grid.dug_chunks.keys():
		var chunk = chunk_grid.dug_chunks[pos]
		var key = str(pos.x) + "_" + str(pos.y)
		save_data["chunks"][key] = chunk

	for pos in chunk_grid.fungus_grid.keys():
		var fungus = chunk_grid.fungus_grid[pos]
		var time_left = 0.0
		if not fungus.is_ready_to_harvest and fungus.timer:
			time_left = fungus.timer.time_left
		var f_data = {
			"x": pos.x, "y": pos.y, "type": fungus.type,
			"stage": fungus.growth_stage, "time_left": time_left
		}
		save_data["fungi"].append(f_data)
		
	var file = FileAccess.open("user://felix_save.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		send_message("Game Saved!", Color.GREEN)

func load_game():
	if not FileAccess.file_exists("user://felix_save.json"):
		send_message("No Save File Found.", Color.RED); return

	var file = FileAccess.open("user://felix_save.json", FileAccess.READ)
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error != OK: return
		
	var data = json.data
	
	# --- CLEANUP ---
	for child in chunk_grid.get_children():
		if child is Ant: child.queue_free()
	reset_game_state()
	if chunk_grid: chunk_grid.clear_akira_visuals()
	
	# --- LOAD BASIC DATA ---
	money = data.get("money", 500)
	current_xp = data.get("xp", 0)
	colony_level = data.get("lvl", 1)
	xp_to_next_level = data.get("xp_needed", 100)
	seeds_owned = data.get("seeds", seeds_owned)
	time_mode = data.get("time_mode", "real_time")
	
	# --- FIX 1: PARSE PENDING BUILDS (STRING -> VECTOR2) ---
	pending_builds = data.get("pending_builds", [])
	for i in range(pending_builds.size()):
		var t = pending_builds[i]
		if t.get("target_pos") is String:
			t["target_pos"] = _parse_vector_string(t["target_pos"])
		if t.get("size") is String:
			t["size"] = _parse_vector_string(t["size"])
	
	# LOAD ROOM SETTINGS
	var saved_rooms = data.get("room_instances", {})
	room_instances = {}
	for k in saved_rooms.keys():
		var r_data = saved_rooms[k]
		
		# Parse Chunk Strings "(x, y)" back to Vector2
		if r_data.has("chunks"):
			var fixed_chunks = []
			for c in r_data["chunks"]:
				if c is String:
					fixed_chunks.append(_parse_vector_string(c))
				else:
					fixed_chunks.append(c)
			r_data["chunks"] = fixed_chunks
			
		room_instances[int(k)] = r_data
	
	var saved_food = data.get("food", {})
	if typeof(saved_food) == TYPE_DICTIONARY: food_inventory = saved_food

	var raw_dining = data.get("dining_contents", {})
	dining_hall_contents = {}
	for key in raw_dining.keys():
		dining_hall_contents[int(key)] = raw_dining[key]
	
	var akira_data = data.get("akira", {})
	akira_discovered = akira_data.get("discovered", false)
	akira_chunk_pos = Vector2(akira_data.get("pos_x", -1), akira_data.get("pos_y", -1))
	
	# --- LOAD CHUNKS ---
	var chunks = data.get("chunks", {})
	for key in chunks.keys():
		var parts = key.split("_")
		var pos = Vector2(int(parts[0]), int(parts[1]))
		chunk_grid.dug_chunks[pos] = chunks[key]
		var r_type = chunks[key].get("room_type", "tunnel")
		if chunks[key].get("status") == "ready":
			register_built_room(r_type, pos, chunks[key].get("structure_id", -1), true)
			
	chunk_grid.queue_redraw()
	
	# --- LOAD FUNGI ---
	var saved_time = data.get("timestamp", Time.get_unix_time_from_system())
	var time_passed = Time.get_unix_time_from_system() - saved_time
	
	var fungi_list = data.get("fungi", [])
	for f_data in fungi_list:
		chunk_grid.plant_fungus(f_data["x"], f_data["y"], f_data["type"])
		var fungus = chunk_grid.get_fungus_at(f_data["x"], f_data["y"])
		if fungus:
			simulate_fungus_growth(fungus, f_data["stage"], f_data["time_left"], time_passed)
	
	# --- LOAD ANTS ---
	var ant_list = data.get("ants", [])
	for ant_data in ant_list:
		spawn_ant_from_save(ant_data)
		
	emit_signal("money_changed", money)
	emit_signal("xp_changed", current_xp, xp_to_next_level, colony_level)
	if chunk_grid: chunk_grid.refresh_akira_visuals()
	send_message("Game Loaded!", Color.GREEN)

func reset_game_state():
	money = 500
	current_xp = 0
	colony_level = 1
	xp_to_next_level = 100
	akira_discovered = false
	food_inventory = { "basic": 0, "common": 0, "rare": 0, "legendary": 0 }
	dining_hall_contents = {}
	pending_builds.clear()
	seed_requests = { "basic": 0, "common": 0, "rare": 0, "legendary": 0 }
	
	for ant in ants:
		if is_instance_valid(ant): ant.queue_free()
	ants.clear()
	
	for key in built_rooms.keys(): built_rooms[key].clear()
	room_instances.clear()
	chunk_grid.dug_chunks.clear()
	chunk_grid.fungus_grid.clear()

func simulate_fungus_growth(fungus, saved_stage, saved_time_left, time_passed):
	if fungus.growth_stage >= 2: return
	var type_info = fungus_types[fungus.type]
	var full_stage_duration = type_info["grow_time"] / 2.0
	
	if time_passed >= saved_time_left:
		fungus.growth_stage = saved_stage + 1
		time_passed -= saved_time_left
		if fungus.growth_stage >= 2:
			fungus.growth_stage = 2
			fungus.is_ready_to_harvest = true
			fungus.timer.stop()
		else:
			if time_passed >= full_stage_duration:
				fungus.growth_stage = 2
				fungus.is_ready_to_harvest = true
				fungus.timer.stop()
			else:
				fungus.timer.start(full_stage_duration - time_passed)
	else:
		fungus.growth_stage = saved_stage
		fungus.timer.start(saved_time_left - time_passed)
	fungus.update_appearance()

func spawn_ant_from_save(data):
	if not ant_scene_resource: return
	var new_ant = ant_scene_resource.instantiate()
	new_ant.ant_name = data["name"]
	new_ant.position = Vector2(data["pos_x"], data["pos_y"])
	new_ant.hunger = data["hunger"]
	new_ant.sleep = data.get("sleep", 100.0)
	new_ant.happiness = data["happiness"]
	
	new_ant.job_role = data.get("job_role", "construction") 
	new_ant.assigned_room_id = data.get("assigned_room_id", -1)
	new_ant.business_target_seed = data.get("business_target_seed", "basic")
	
	new_ant.skip_intro_spawn = true
	chunk_grid.add_child(new_ant)

func gain_xp(amount: int):
	current_xp += amount
	if current_xp >= xp_to_next_level:
		level_up_colony()
	emit_signal("xp_changed", current_xp, xp_to_next_level, colony_level)

func level_up_colony():
	current_xp -= xp_to_next_level
	colony_level += 1
	xp_to_next_level += 150
	if audio_manager: audio_manager.play_sfx("level_up")
	emit_signal("level_up", colony_level)
	send_message("LEVEL UP! Colony reached Level " + str(colony_level), Color.GOLD)
	if chunk_grid: chunk_grid.check_akira_reveal()

func is_unlocked(unlock_level: int) -> bool: return colony_level >= unlock_level
func get_next_ant_cost() -> int: return 150 + (colony_population * 50)

func recruit_new_ant(force_free_spawn: bool = false) -> bool:
	if not force_free_spawn:
		if not is_unlocked(recruit_unlock_level):
			send_message("Locked! Requires Level " + str(recruit_unlock_level), Color.RED); return false
		if not spend_money(get_next_ant_cost()): return false
		
	var new_ant = ant_scene_resource.instantiate()
	new_ant.ant_name = generate_ant_name()
	new_ant.skip_intro_spawn = true
	new_ant.job_role = "construction" 
	
	chunk_grid.add_child(new_ant)
	new_ant.position = chunk_grid.chunk_to_world_position(Vector2(chunk_grid.grid_width/2, chunk_grid.sky_rows))
	gain_xp(25)
	send_message("Recruited " + new_ant.ant_name + "!", Color.GREEN)
	return true

func generate_ant_name() -> String: return ant_names_db.pick_random()

func is_ant_at_chunk(chunk_pos: Vector2) -> bool:
	var world_rect = Rect2(chunk_pos.x * 64, chunk_pos.y * 64, 64, 64)
	for ant in ants:
		if world_rect.has_point(ant.position): return true
	return false

func register_built_room(type: String, chunk_pos: Vector2, s_id: int, skip_create: bool = false):
	if built_rooms.has(type):
		if not chunk_pos in built_rooms[type]:
			built_rooms[type].append(chunk_pos)
			
	if s_id != -1 and room_types[type].get("is_room", false):
		if not room_instances.has(s_id):
			room_instances[s_id] = { "type": type, "chunks": [], "target_seed": "basic" }
		if not chunk_pos in room_instances[s_id]["chunks"]:
			room_instances[s_id]["chunks"].append(chunk_pos)

	if skip_create: return # Used during load
	var reward = 0
	match type:
		"tunnel": reward = 1
		"sleeping_quarters": reward = 50
		"farming_room": reward = 40
		"dining_hall": reward = 60
	if reward > 0: gain_xp(reward)
	
	if not akira_discovered and akira_chunk_pos != Vector2(-1, -1):
		if chunk_pos == akira_chunk_pos or chunk_pos == akira_chunk_pos + Vector2(1, 0):
			discover_akira()

func unregister_room(type: String, chunk_pos: Vector2):
	if built_rooms.has(type): built_rooms[type].erase(chunk_pos)

func get_nearest_room(type: String, from_world_pos: Vector2) -> Vector2:
	if not built_rooms.has(type) or built_rooms[type].size() == 0: return Vector2(-1, -1)
	var nearest = Vector2(-1, -1)
	var min_dist = INF
	var cx = int(from_world_pos.x / 64)
	var cy = int(from_world_pos.y / 64)
	var my_chunk = Vector2(cx, cy)
	for r_pos in built_rooms[type]:
		var dist = my_chunk.distance_to(r_pos)
		if dist < min_dist:
			min_dist = dist
			nearest = r_pos
	return nearest

func get_nearest_room_id(type: String, from_world_pos: Vector2) -> int:
	var chunk = get_nearest_room(type, from_world_pos)
	if chunk != Vector2(-1, -1) and chunk_grid.dug_chunks.has(chunk):
		return chunk_grid.dug_chunks[chunk].get("structure_id", -1)
	return -1

func add_money(amount: int): money += amount; emit_signal("money_changed", money)
func spend_money(amount: int) -> bool:
	if money >= amount: money -= amount; emit_signal("money_changed", money); return true
	else: emit_signal("system_message", "Not enough money!", Color.RED); return false
func send_message(text, color): emit_signal("system_message", text, color)

func get_room_def(type_id: String) -> Dictionary:
	if room_types.has(type_id): return room_types[type_id]
	return room_types["tunnel"]
func get_room_cost(type_id: String) -> int: return get_room_def(type_id)["cost"]
func get_room_color(type_id: String) -> Color: return get_room_def(type_id)["color"]

func buy_seed(type: String) -> bool:
	var cost = fungus_types[type]["buy_cost"]
	if spend_money(cost):
		seeds_owned[type] += 1
		emit_signal("seeds_changed", type, seeds_owned[type])
		fulfill_seed_request(type) # Notify business logic
		return true
	return false

func has_seed(type: String) -> bool: return seeds_owned[type] > 0
func use_seed(type: String):
	if seeds_owned[type] > 0: seeds_owned[type] -= 1; emit_signal("seeds_changed", type, seeds_owned[type])

func request_harvest_task(chunk_pos: Vector2):
	request_task("harvest", chunk_pos, {})

func add_food(amount: int, type: String = "basic"):
	food_inventory[type] += amount
	emit_signal("food_changed", get_total_food())
	gain_xp(5 * amount)

func get_total_food() -> int:
	var total = 0
	for k in food_inventory:
		total += food_inventory[k]
	return total
	
func sell_all_food():
	var total_profit = 0
	for type in food_inventory.keys():
		var count = food_inventory[type]
		if count > 0:
			var price = fungus_types[type]["sell_price"]
			total_profit += count * price
			food_inventory[type] = 0
	if total_profit > 0:
		add_money(total_profit)
		emit_signal("food_changed", 0)
		send_message("Sold harvest for $" + str(total_profit), Color.GREEN)
	else: send_message("No global food to sell!", Color.RED)

func register_ant(ant):
	if not ant in ants: ants.append(ant); colony_population = ants.size(); emit_signal("population_changed", colony_population)
func unregister_ant(ant):
	if ant in ants: ants.erase(ant); colony_population = ants.size(); emit_signal("population_changed", colony_population)

func discover_akira():
	if akira_discovered: return
	akira_discovered = true
	emit_signal("akira_state_changed", true)
	emit_signal("system_message", "You found a mysterious cave!", Color.MAGENTA)
	gain_xp(500)
	if chunk_grid: chunk_grid.refresh_akira_visuals()
