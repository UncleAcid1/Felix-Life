extends Node2D

# --- PROPERTIES ---
var ant_name = "Felix"
var happiness = 100.0
var hunger = 100.0
var sleep = 100.0
var current_emotion = "happy"
var current_direction = "right"
var is_frozen = false
var skip_intro_spawn = false

# --- JOBS & ROLES ---
var job_role = "construction" # Options: construction, farmer, business
var assigned_room_id = -1
var business_target_seed = "basic"
var business_timer = 0.0
var business_interval = 1.0

# --- SETTINGS ---
var hunger_decay_rate = 0.10
var sleep_decay_rate = 0.15
var food_restore_amount = 100

# --- MOVEMENT ---
var base_speed = 40.0
var current_speed = 40.0
var path = []
var current_path_index = 0
var lane_offset = 12
var using_right_lane = true

# --- WANDERING ---
var wander_timer = 0.0
var wander_interval = 5.0

# --- TASKS ---
var current_task = "wander"
var task_data = {}
var is_performing_manual_task = false

# Work Timer
var work_timer = 0.0
var work_duration = 2.0

# --- VISUALS & REFS ---
var animated_sprite
var progress_bar = null
var game_manager
var chunk_grid

func _ready():
	animated_sprite = $AnimatedSprite2D
	game_manager = get_node("/root/TestLevel/GameManager")
	chunk_grid = get_node("/root/TestLevel/ChunkGrid")
	game_manager.register_ant(self)
	
	create_progress_bar()
	
	await get_tree().process_frame
	
	if not skip_intro_spawn:
		spawn_at_random_valid_tunnel()
	
	update_animation()

func spawn_at_random_valid_tunnel():
	var valid_chunks = []
	var akira_pos = game_manager.akira_chunk_pos
	var akira_room_tiles = [akira_pos, akira_pos + Vector2(1, 0)]
	
	for pos in chunk_grid.dug_chunks.keys():
		if pos in akira_room_tiles: continue
		if chunk_grid.is_chunk_walkable(pos):
			valid_chunks.append(pos)
	
	if valid_chunks.size() > 0:
		var random_chunk = valid_chunks.pick_random()
		position = chunk_grid.chunk_to_world_position(random_chunk)
		path.clear()
		current_path_index = 0
		using_right_lane = randf() > 0.5
	else:
		print("Error: No valid tunnels for Ant spawn!")

func create_progress_bar():
	progress_bar = ProgressBar.new()
	progress_bar.size = Vector2(40, 6)
	progress_bar.position = Vector2(-20, -40)
	progress_bar.show_percentage = false
	
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0,0,0,0.5)
	var fg = StyleBoxFlat.new()
	fg.bg_color = Color(0,1,0,1)
	
	progress_bar.add_theme_stylebox_override("background", bg)
	progress_bar.add_theme_stylebox_override("fill", fg)
	progress_bar.visible = false
	add_child(progress_bar)

func _process(delta):
	if is_frozen:
		var anim_name = current_emotion + "_forward"
		if animated_sprite.animation != anim_name:
			animated_sprite.play(anim_name)
		return
	
	# --- SURVIVAL LOGIC ---
	if current_task != "sleeping":
		hunger -= hunger_decay_rate * delta
		if hunger < 0: hunger = 0
		
		sleep -= sleep_decay_rate * delta
		if sleep < 0: sleep = 0
	
	calculate_state()
	
	# --- PRIORITY SYSTEM ---
	# 1. Critical Survival
	if hunger < 5 and current_task != "moving_to_eat" and current_task != "eating":
		seek_food_source()
		return
		
	# 2. Manual Task
	if is_performing_manual_task:
		pass
	else:
		# 3. Standard Needs
		if hunger < 25 and current_task != "moving_to_eat" and current_task != "sleeping" and current_task != "moving_to_sleep":
			seek_food_source()
		
		var is_exhausted = (sleep < 10)
		var night_sleep = (not game_manager.is_daytime) and (sleep < 80)
		
		if (is_exhausted or night_sleep) and current_task != "sleeping" and current_task != "moving_to_sleep":
			seek_bed()

	# --- JOB AUTOMATION ---
	if current_task == "wander" or current_task == "idle" or current_task == "tending_farm" or current_task == "idling_at_surface":
		if job_role == "farmer":
			process_strict_farmer(delta)
		elif job_role == "business":
			process_strict_business(delta)
		elif job_role == "construction":
			check_construction_work()

	# --- STATE MACHINE ---
	match current_task:
		"moving_to_dig":
			if path.size() > 0: follow_path(delta)
			else: on_reached_destination()
		
		"working_dig":
			process_work_dig(delta)
			
		"harvesting":
			if path.size() > 0: follow_path(delta)
			else: on_reached_destination()
		
		"planting":
			if path.size() > 0: follow_path(delta)
			else: on_reached_destination()
			
		"buy_fungus":
			if path.size() > 0: follow_path(delta)
			else: on_reached_destination()
			
		"returning_from_buy":
			if path.size() > 0: follow_path(delta)
			else: on_reached_destination()
			
		"moving_to_eat":
			if path.size() > 0: follow_path(delta)
			else: on_reached_destination()

		"moving_to_sleep":
			if path.size() > 0: follow_path(delta)
			else: on_reached_destination()
			
		"moving_to_farm_station":
			if path.size() > 0: follow_path(delta)
			else: on_reached_destination()
			
		"moving_to_surface":
			if path.size() > 0: follow_path(delta)
			else: on_reached_destination()
			
		"tending_farm":
			pass
			
		"idling_at_surface":
			pass
			
		"busy_working":
			pass # DO NOTHING, waiting for animation/timer to finish

		"sleeping":
			process_sleeping(delta)

		"wander":
			if path.size() > 0:
				follow_path(delta)
			else:
				wander_timer += delta
				if wander_timer >= wander_interval:
					wander_timer = 0.0
					pick_random_destination()
		
		"idle":
			pass

# --- STRICT FARMER LOGIC ---
func process_strict_farmer(_delta):
	if assigned_room_id == -1:
		if current_task == "tending_farm": current_task = "wander"
		return

	var safe_id = int(assigned_room_id)
	if not game_manager.room_instances.has(safe_id):
		assigned_room_id = -1
		print(ant_name + ": Farm ID " + str(safe_id) + " not found. Resigning.")
		return
		
	var room = game_manager.room_instances[safe_id]
	var chunks = room["chunks"]
	
	# 1. Go to Station
	var station_chunk = chunks[0]
	var station_pos = chunk_grid.chunk_to_world_position(station_chunk)
	
	if position.distance_to(station_pos) > 16.0:
		if current_task != "moving_to_farm_station" and current_task != "busy_working":
			task_data = { "target_chunk": station_chunk }
			var start = chunk_grid.world_to_chunk_position(position)
			path = chunk_grid.find_path(start, station_chunk)
			current_path_index = 0
			if path.size() > 0:
				current_task = "moving_to_farm_station"
		return
	
	if current_task != "busy_working":
		current_task = "tending_farm"
	
	# 2. Get Room Settings
	var target_seed = game_manager.get_room_target_seed(safe_id)
	
	# 3. Scan grid
	if current_task != "busy_working":
		for c in chunks:
			var fungus = chunk_grid.get_fungus_at(c.x, c.y)
			
			if fungus and fungus.is_ready_to_harvest:
				perform_instant_harvest(c)
				return
				
			elif fungus == null:
				if game_manager.has_seed(target_seed):
					perform_instant_plant(c, target_seed)
					return
				else:
					game_manager.report_seed_need(target_seed)

func perform_instant_harvest(target_chunk):
	# FIXED: Use "busy_working" so _process doesn't interrupt
	current_task = "busy_working"
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(self): return
	
	var fungus = chunk_grid.get_fungus_at(target_chunk.x, target_chunk.y)
	if fungus:
		game_manager.add_food(1, fungus.type)
		chunk_grid.remove_fungus(target_chunk.x, target_chunk.y)
		show_popup_text("+1 " + fungus.type.capitalize())
	
	current_task = "tending_farm"

func perform_instant_plant(target_chunk, type):
	# FIXED: Use "busy_working"
	current_task = "busy_working"
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(self): return
	
	if chunk_grid.can_plant_fungus(target_chunk.x, target_chunk.y) and game_manager.has_seed(type):
		chunk_grid.plant_fungus(target_chunk.x, target_chunk.y, type)
		game_manager.use_seed(type)
	
	current_task = "tending_farm"

# --- STRICT BUSINESS LOGIC ---
func process_strict_business(delta):
	business_timer += delta
	if business_timer < business_interval: return
	business_timer = 0.0
	
	var my_target = business_target_seed
	
	if game_manager.seed_requests.has(my_target) and game_manager.seed_requests[my_target] > 0:
		if game_manager.money >= game_manager.fungus_types[my_target]["buy_cost"]:
			assign_task_buy_fungus(my_target)
		return

	# Idle at surface
	var surface_target = Vector2(chunk_grid.grid_width / 2, chunk_grid.sky_rows + 1)
	var surface_world = chunk_grid.chunk_to_world_position(surface_target)
	
	if position.distance_to(surface_world) > 64:
		if current_task != "moving_to_surface" and current_task != "buy_fungus" and current_task != "returning_from_buy":
			var start = chunk_grid.world_to_chunk_position(position)
			path = chunk_grid.find_path(start, surface_target)
			current_path_index = 0
			if path.size() > 0:
				current_task = "moving_to_surface"
	else:
		if current_task != "idling_at_surface":
			current_task = "idling_at_surface"

# --- CONSTRUCTION LOGIC ---
func check_construction_work():
	var task = game_manager.get_nearest_pending_build_task(position)
	if not task.is_empty():
		assign_task(task)

# --- GENERIC TASK HANDLING ---
func assign_task(task_info: Dictionary):
	var type = task_info["type"]
	var target = task_info["target_pos"]
	task_data = task_info
	is_performing_manual_task = task_info.get("is_manual", false)
	
	if type == "dig":
		start_dig_task(task_info)
	elif type == "harvest":
		assign_task_harvest(target)
	elif type == "farm_work":
		task_data["target_chunk"] = target
		var start = chunk_grid.world_to_chunk_position(position)
		path = chunk_grid.find_path(start, target)
		current_path_index = 0
		if path.size() > 0: current_task = "moving_to_farm_target"
		else: on_reached_destination()

func start_dig_task(info):
	work_duration = info.get("build_time", 2.0)
	var target = info["target_pos"]
	var size = info.get("size", Vector2(1,1))
	
	var stand_pos = chunk_grid.get_multitile_access_point(target, size)
	if stand_pos == Vector2(-1, -1):
		print(ant_name, " cannot reach dig site!");
		current_task = "wander"
		return
		
	var start = chunk_grid.world_to_chunk_position(position)
	path = chunk_grid.find_path(start, stand_pos)
	current_path_index = 0
	
	if path.size() > 0:
		current_task = "moving_to_dig"
	else:
		current_task = "working_dig"
		work_timer = 0.0

func process_work_dig(delta):
	work_timer += delta
	
	if progress_bar:
		progress_bar.visible = true
		progress_bar.max_value = work_duration
		progress_bar.value = work_timer
	
	var my_pos = chunk_grid.world_to_chunk_position(position)
	var target = task_data["target_pos"]
	var dir = (target - my_pos)
	update_direction_from_vector(dir)
	
	if work_timer >= work_duration:
		chunk_grid.finalize_dig(task_data["target_pos"])
		print(ant_name, " finished digging at ", task_data["target_pos"])
		if progress_bar: progress_bar.visible = false
		is_performing_manual_task = false
		current_task = "wander"

func assign_task_harvest(target_chunk: Vector2):
	task_data["target_chunk"] = target_chunk
	var start = chunk_grid.world_to_chunk_position(position)
	path = chunk_grid.find_path(start, target_chunk)
	current_path_index = 0
	if path.size() > 0: current_task = "harvesting"
	else: perform_harvest()

func perform_harvest():
	var target = task_data["target_chunk"]
	var fungus = chunk_grid.get_fungus_at(target.x, target.y)
	
	if fungus:
		game_manager.add_food(1, fungus.type)
		chunk_grid.remove_fungus(target.x, target.y)
		show_popup_text("+1 Food")
		
	is_performing_manual_task = false
	current_task = "wander"

# --- BUYING LOGIC ---
func assign_task_buy_fungus(type_to_buy = "basic"):
	task_data["buy_type"] = type_to_buy
	var start = chunk_grid.world_to_chunk_position(position)
	var target = Vector2(chunk_grid.grid_width / 2, chunk_grid.sky_rows)
	path = chunk_grid.find_path(start, target)
	current_path_index = 0
	
	if path.size() > 0:
		current_task = "buy_fungus"
	else:
		buy_fungus_at_mound()

func buy_fungus_at_mound():
	var type = task_data.get("buy_type", "basic")
	if game_manager.buy_seed(type):
		show_popup_text("+1 " + type.capitalize())
		var start = chunk_grid.world_to_chunk_position(position)
		var home = Vector2(chunk_grid.grid_width / 2, chunk_grid.sky_rows + 2)
		path = chunk_grid.find_path(start, home)
		current_path_index = 0
		if path.size() > 0:
			current_task = "returning_from_buy"
		else:
			current_task = "wander"
	else:
		current_task = "wander"

# --- MOVEMENT LOGIC ---
func follow_path(delta):
	if current_path_index >= path.size():
		path.clear()
		current_path_index = 0
		on_reached_destination()
		return
	
	var target_chunk = path[current_path_index]
	var target_world_pos = chunk_to_world_position(target_chunk)
	
	var is_horizontal = false
	if current_path_index > 0:
		is_horizontal = (target_chunk.x != path[current_path_index - 1].x)
	elif current_path_index < path.size() - 1:
		is_horizontal = (target_chunk.x != path[current_path_index + 1].x)
	
	if is_horizontal:
		if using_right_lane: target_world_pos.y += lane_offset
		else: target_world_pos.y -= lane_offset
	else:
		if using_right_lane: target_world_pos.x += lane_offset
		else: target_world_pos.x -= lane_offset
	
	var direction = (target_world_pos - position).normalized()
	if position.distance_to(target_world_pos) < current_speed * delta:
		position = target_world_pos
		current_path_index += 1
	else:
		position += direction * current_speed * delta
		update_direction_from_vector(direction)
		update_animation()

func on_reached_destination():
	if current_task == "moving_to_dig":
		current_task = "working_dig"
		work_timer = 0.0
		
	elif current_task == "harvesting":
		perform_harvest()

	elif current_task == "planting":
		perform_instant_plant(task_data["target_chunk"], task_data.get("seed_type", "basic"))
		is_performing_manual_task = false
		
	elif current_task == "buy_fungus":
		buy_fungus_at_mound()
		
	elif current_task == "returning_from_buy":
		if job_role == "business":
			current_task = "idling_at_surface"
		else:
			current_task = "wander"
		
	elif current_task == "moving_to_eat":
		arrived_at_dining_hall()

	elif current_task == "moving_to_sleep":
		enter_sleep_state()
		
	elif current_task == "moving_to_farm_station":
		current_task = "tending_farm"
		
	elif current_task == "moving_to_surface":
		current_task = "idling_at_surface"
		
	elif current_task == "moving_to_farm_target":
		var chunk = task_data["target_chunk"]
		var fungus = chunk_grid.get_fungus_at(chunk.x, chunk.y)
		if fungus and fungus.is_ready_to_harvest:
			perform_harvest()
		elif chunk_grid.can_plant_fungus(chunk.x, chunk.y):
			perform_instant_plant(chunk, "basic")
			is_performing_manual_task = false
		else:
			current_task = "wander"

# --- EATING/SLEEPING ---
func seek_food_source():
	var best_hall_id = -1
	var target_tile = Vector2(-1, -1)
	
	for s_id in game_manager.room_instances.keys():
		var room = game_manager.room_instances[s_id]
		if room["type"] == "dining_hall":
			var contents = game_manager.get_dining_hall_contents(s_id)
			if contents["basic"] > 0:
				best_hall_id = s_id
				for c in room["chunks"]:
					if chunk_grid.is_chunk_walkable(c):
						target_tile = c
						break
				if target_tile != Vector2(-1, -1): break

	if best_hall_id != -1:
		task_data = { "target_hall_id": best_hall_id }
		var start = chunk_grid.world_to_chunk_position(position)
		path = chunk_grid.find_path(start, target_tile)
		current_path_index = 0
		if progress_bar: progress_bar.visible = false
		
		if path.size() > 0:
			current_task = "moving_to_eat"
		else:
			arrived_at_dining_hall()
	else:
		pass

func arrived_at_dining_hall():
	if not task_data.has("target_hall_id"):
		current_task = "wander"
		return
		
	var hall_id = task_data["target_hall_id"]
	var calories = game_manager.consume_from_dining_hall(hall_id)
	
	if calories > 0:
		feed(calories)
		show_munch_effect()
	
	if current_task == "moving_to_eat":
		if assigned_room_id != -1 and job_role == "farmer":
			current_task = "tending_farm"
		elif job_role == "business":
			current_task = "idling_at_surface"
		else:
			current_task = "wander"

func show_munch_effect():
	show_popup_text("*munch*")

func show_popup_text(txt):
	var l = Label.new()
	l.text = txt
	l.modulate = Color.GREEN
	l.position = Vector2(-20, -50)
	add_child(l)
	var t = create_tween()
	t.tween_property(l, "position:y", -80.0, 1.0)
	t.parallel().tween_property(l, "modulate:a", 0.0, 1.0)
	t.tween_callback(l.queue_free)

func seek_bed():
	var bed_id = game_manager.get_nearest_room_id("sleeping_quarters", position)
	
	if bed_id != -1 and game_manager.room_instances.has(bed_id):
		var room_data = game_manager.room_instances[bed_id]
		if room_data["chunks"].size() > 0:
			var target = room_data["chunks"].pick_random()
			var start = chunk_grid.world_to_chunk_position(position)
			path = chunk_grid.find_path(start, target)
			current_path_index = 0
			if progress_bar: progress_bar.visible = false
			
			if path.size() > 0:
				current_task = "moving_to_sleep"
			else:
				enter_sleep_state()
			return

	enter_sleep_state()

func enter_sleep_state():
	current_task = "sleeping"
	path.clear()
	animated_sprite.stop()
	modulate = Color(0.6, 0.6, 0.7)

func process_sleeping(delta):
	sleep += 5.0 * delta
	if sleep >= 100: sleep = 100
	
	if sleep >= 100:
		if game_manager.is_daytime:
			wake_up()

func wake_up():
	print(ant_name, " woke up!")
	current_task = "wander"
	modulate = Color(1, 1, 1)
	update_animation()

# --- HELPERS ---
func calculate_state():
	if current_task == "sleeping":
		current_emotion = "happy"
		return

	if hunger > 50 and sleep > 50:
		current_emotion = "happy"
		current_speed = base_speed
	elif hunger > 20 and sleep > 20:
		current_emotion = "neutral"
		current_speed = base_speed
	else:
		current_emotion = "unhappy"
		current_speed = base_speed * 0.6

func set_frozen(frozen: bool):
	is_frozen = frozen
	if not is_frozen:
		update_animation()

func feed(amount: int):
	hunger = clamp(hunger + amount, 0, 100)
	calculate_state()

func abort_task():
	print(ant_name, " task aborted.")
	current_task = "wander"
	is_performing_manual_task = false
	path.clear()
	current_path_index = 0
	if progress_bar: progress_bar.visible = false

func update_direction_from_vector(dir: Vector2):
	if abs(dir.x) > abs(dir.y):
		current_direction = "right" if dir.x > 0 else "left"
		animated_sprite.rotation = 0
		animated_sprite.flip_h = false
	else:
		current_direction = "right"
		animated_sprite.rotation = deg_to_rad(90)
		animated_sprite.flip_h = (dir.y <= 0)

func pick_random_destination():
	var dug_list = chunk_grid.dug_chunks.keys()
	if dug_list.size() == 0: return
	
	var valid_targets = []
	for pos in dug_list:
		if chunk_grid.is_chunk_walkable(pos):
			valid_targets.append(pos)
			
	if valid_targets.size() == 0: return

	var start = chunk_grid.world_to_chunk_position(position)
	var target = valid_targets.pick_random()
	
	if target == start: return
	path = chunk_grid.find_path(start, target)
	current_path_index = 0
	using_right_lane = randf() > 0.5

func chunk_to_world_position(chunk: Vector2) -> Vector2:
	return Vector2(chunk.x * 64 + 32, chunk.y * 64 + 32)

func update_animation():
	if is_frozen: return
	
	var emotion = current_emotion.substr(0, 1).to_upper()
	var dir_code = "F"
	if current_direction == "left": dir_code = "SL"
	elif current_direction == "right": dir_code = "SR"
	
	var anim = "happy_"
	if emotion == "N": anim = "neutral_"
	elif emotion == "U": anim = "unhappy_"
	
	if dir_code == "SL": anim += "side_left"
	elif dir_code == "SR": anim += "side_right"
	else: anim += "forward"
	
	if animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.play(anim)

func _exit_tree():
	if game_manager:
		game_manager.unregister_ant(self)
