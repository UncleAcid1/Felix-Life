extends Node2D

# Chunk settings
var chunk_size = 64
var grid_width = 12
var grid_height = 48
var sky_rows = 2

# Dictionaries
var dug_chunks = {}
var fungus_grid = {}
var akira_instance = null

# Resources
var fungus_scene = preload("res://scenes/fungi_standard.tscn")
var cloud_texture = preload("res://sprites/cloud.png")
var akira_scene = preload("res://scenes/akira.tscn")

# --- SURFACE VISUALS ---
var anthill_texture = preload("res://sprites/anthill.png")
var grass_texture = preload("res://sprites/grass.png")
var surface_objects = []

# --- ASH (THE CAT) ---
var ash_script = preload("res://scenes/Ash.gd")
var ash_instance = null
var ash_spawn_timer = 0.0
var ash_duration_timer = 0.0
var ash_is_present = false
# 20 to 35 minutes in seconds
var ash_min_interval = 1200.0
var ash_max_interval = 2100.0

# --- SCALE VARIABLES ---
var anthill_asset_scale = Vector2(0.15, 0.15)
var grass_asset_scale = Vector2(0.5, 0.5)

# State Flags
var build_mode_active = false
var remove_mode_active = false
var plant_mode_active = false
var lock_preview = false
var current_tunnel_piece = "straight"
var current_build_type = "tunnel"
var tunnel_rotation = 0
var preview_chunks = []

var next_structure_id = 0

# --- Lighting Nodes ---
var darkness_overlay: TextureRect
var sky_background: TextureRect
var sky_overlay: ColorRect

# --- SKY GRADIENT COLORS ---
var sky_day_top = Color("ffffffff")
var sky_day_bottom = Color("7aaecbff")

var sky_night_top = Color(0.02, 0.02, 0.1, 1.0)
var sky_night_bottom = Color(0.05, 0.05, 0.2, 1.0)

var sky_gradient_texture: GradientTexture2D
var current_day_progress: float = 1.0

# --- STAR SYSTEM ---
var star_pool = []
const STAR_COUNT = 100
const STAR_Z_INDEX = -95

var cloud_rects = []
var cloud_speed = 10.0

var piece_connections = {
	"straight": ["left", "right"],
	"corner": ["left", "up"],
	"t_junction": ["left", "right", "up"],
	"cross": ["left", "right", "up", "down"],
	"end_cap": ["left"]
}

var game_manager
var control_node = null # Initialized to null

func _ready():
	game_manager = get_node("/root/TestLevel/GameManager")
	
	# Safe deferred initialization
	call_deferred("_deferred_initialization") 
	
	game_manager.connect("time_changed", Callable(self, "_on_time_changed"))
	position = Vector2.ZERO
	
	setup_environment_visuals()
	setup_surface_sprites()
	setup_stars()
	setup_ash()
	
	if dug_chunks.is_empty():
		generate_initial_tunnel()
	
	if game_manager.akira_chunk_pos == Vector2(-1, -1):
		generate_akira_room()
	else:
		check_akira_reveal()
	
	current_day_progress = 1.0 if game_manager.is_daytime else 0.0
	update_sky_gradient(current_day_progress)
	_on_time_changed(game_manager.is_daytime)
	
	reset_ash_timer()

func _deferred_initialization():
	await get_tree().process_frame # Wait one visual frame
	# ROBUST FIND: Search for "Control" anywhere in the scene tree
	control_node = get_tree().root.find_child("Control", true, false)
	if not control_node:
		print("Warning: Control node not found via search. Ash spawn will check again later.")

func setup_ash():
	# Remove duplicates
	var existing_ash = get_node_or_null("Ash")
	if existing_ash: existing_ash.queue_free()

	if not ash_script: return
	ash_instance = ash_script.new()
	ash_instance.name = "Ash"
	ash_instance.z_index = -92
	ash_instance.visible = false 
	add_child(ash_instance)

func reset_ash_timer():
	ash_spawn_timer = randf_range(ash_min_interval, ash_max_interval)
	print("Ash will arrive in: " + str(int(ash_spawn_timer)) + " seconds.")

func force_spawn_ash():
	ash_spawn_timer = 0.5 
	print("Pspsps! Ash is being summoned...")

func spawn_ash():
	if not ash_instance: return
	
	# Retry finding control node if null
	if not control_node:
		control_node = get_tree().root.find_child("Control", true, false)
	
	# Check if game has started
	if not is_instance_valid(control_node) or not control_node.get("game_started"):
		ash_spawn_timer = 5.0 
		return
		
	ash_is_present = true
	ash_instance.visible = true
	ash_instance.is_active = true
	ash_duration_timer = 60.0 
	
	var ground_y = sky_rows * chunk_size
	var random_x = randf_range(40, 275) 
	ash_instance.position = Vector2(random_x, ground_y + 8)
	
	print("Ash has arrived at surface!")

func despawn_ash():
	if not ash_instance: return
	ash_is_present = false
	ash_instance.visible = false
	ash_instance.is_active = false
	ash_instance.position = Vector2(-2000, -2000)
	reset_ash_timer()
	print("Ash has left.")

func setup_stars():
	var max_y = sky_rows * chunk_size
	var max_x = grid_width * chunk_size
	
	for i in range(STAR_COUNT):
		var star = ColorRect.new()
		star.color = Color(1.0, 0.9, 0.4)
		star.size = Vector2(2, 2)
		star.position.x = randf_range(0, max_x)
		star.position.y = randf_range(0, max_y)
		star.z_index = STAR_Z_INDEX
		star.visible = false
		star.set_meta("flicker_speed", randf_range(2.0, 8.0))
		star.set_meta("flicker_offset", randf_range(0, 10.0))
		add_child(star)
		star_pool.append(star)

func clear_akira_visuals():
	if akira_instance:
		akira_instance.queue_free()
		akira_instance = null

func reset_world():
	dug_chunks.clear()
	fungus_grid.clear()
	preview_chunks.clear()
	clear_akira_visuals()
	despawn_ash()
	reset_ash_timer()
		
	for child in get_children():
		if child.has_method("initialize") or child.name.begins_with("Ant"):
			child.queue_free()
			
	generate_initial_tunnel()
	generate_akira_room()
	queue_redraw()

func is_connected_to_surface(target_chunk: Vector2) -> bool:
	var start = Vector2(grid_width / 2, sky_rows)
	if not is_chunk_dug(target_chunk.x, target_chunk.y): return false
	var path = find_path(start, target_chunk)
	return path.size() > 0

func setup_surface_sprites():
	if anthill_texture:
		var hill = Sprite2D.new()
		hill.texture = anthill_texture
		hill.scale = anthill_asset_scale
		hill.position = Vector2((grid_width * chunk_size) - 700 / 2, sky_rows * chunk_size + 10)
		hill.offset = Vector2(0, -hill.texture.get_height() / 2)
		hill.z_index = -5
		add_child(hill)
		surface_objects.append(hill)

	if grass_texture:
		var total_width = grid_width * chunk_size
		var scaled_grass_w = grass_texture.get_width() * grass_asset_scale.x
		var scaled_grass_h = grass_texture.get_height() * grass_asset_scale.y
		
		var grass_rect = TextureRect.new()
		grass_rect.texture = grass_texture
		grass_rect.stretch_mode = TextureRect.STRETCH_TILE
		grass_rect.scale = grass_asset_scale
		
		var base_y_pos = (sky_rows * chunk_size) - scaled_grass_h + 165
		grass_rect.position = Vector2(-2 * chunk_size, base_y_pos)
		grass_rect.size = Vector2(total_width + (4 * chunk_size), scaled_grass_h)
		grass_rect.z_index = 10
		add_child(grass_rect)
		surface_objects.append(grass_rect)

func setup_environment_visuals():
	var dirt_start_y = sky_rows * chunk_size
	
	sky_gradient_texture = GradientTexture2D.new()
	sky_gradient_texture.fill = GradientTexture2D.FILL_LINEAR
	sky_gradient_texture.fill_from = Vector2(0, 0) # Top
	sky_gradient_texture.fill_to = Vector2(0, 1)   # Bottom
	
	var sky_grad = Gradient.new()
	sky_grad.set_color(0, sky_day_top)    # Index 0 is Top
	sky_grad.set_color(1, sky_day_bottom) # Index 1 is Bottom
	sky_gradient_texture.gradient = sky_grad
	
	sky_background = TextureRect.new()
	sky_background.name = "SkyBackground"
	sky_background.texture = sky_gradient_texture
	sky_background.position = Vector2(-2000, -2000)
	sky_background.size = Vector2(40000, 2000 + dirt_start_y)
	sky_background.z_index = -100
	sky_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky_background)

	var bg_texture = load("res://enviroment/base_soil.png")
	var texture_scale = 0.10
	
	if bg_texture:
		var bg = TextureRect.new()
		bg.name = "SoilBackground"
		bg.texture = bg_texture
		bg.stretch_mode = TextureRect.STRETCH_TILE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.z_index = -100
		bg.scale = Vector2(texture_scale, texture_scale)
		bg.position = Vector2(-2000, dirt_start_y)
		bg.size = Vector2(40000, 60000)
		add_child(bg)
		
		var gradient_tex = GradientTexture2D.new()
		gradient_tex.fill = GradientTexture2D.FILL_LINEAR
		gradient_tex.fill_from = Vector2(0, 0)
		gradient_tex.fill_to = Vector2(0, 1)
		
		var gradient = Gradient.new()
		gradient.set_color(0, Color(0, 0, 0, 0.0)) # Transparent at top
		gradient.set_color(1, Color(0, 0, 0, 0.4)) # Dark at bottom
		gradient_tex.gradient = gradient
		
		darkness_overlay = TextureRect.new()
		darkness_overlay.texture = gradient_tex
		darkness_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		darkness_overlay.z_index = -99
		darkness_overlay.position = bg.position
		darkness_overlay.scale = bg.scale
		darkness_overlay.size = bg.size
		add_child(darkness_overlay)

	sky_overlay = ColorRect.new()
	sky_overlay.name = "SkyOverlay"
	sky_overlay.color = Color(0, 0, 0, 0)
	sky_overlay.position = Vector2(-2000, -2000)
	sky_overlay.size = Vector2(40000, 60000)
	sky_overlay.z_index = -90
	sky_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky_overlay)

	if cloud_texture:
		for i in range(2):
			var c = TextureRect.new()
			c.texture = cloud_texture
			var c_scale = 0.40
			var tex_width = cloud_texture.get_width() * c_scale
			c.scale = Vector2(c_scale, c_scale)
			c.position = Vector2(i * tex_width, -300)
			c.z_index = -90
			c.modulate.a = 0.8
			add_child(c)
			cloud_rects.append(c)
			surface_objects.append(c)

func generate_initial_tunnel():
	var surface_y = sky_rows
	var start_row = sky_rows + 2
	var center_x = grid_width / 2
	var init_id = get_new_structure_id()
	
	for y in range(surface_y, start_row):
		force_instant_dig(center_x, y, "straight", 90, "tunnel", init_id, true)
	
	force_instant_dig(center_x - 1, start_row, "straight", 0, "tunnel", init_id, true)
	force_instant_dig(center_x, start_row, "t_junction", 0, "tunnel", init_id, true)
	force_instant_dig(center_x + 1, start_row, "straight", 0, "tunnel", init_id, true)
	queue_redraw()

func generate_akira_room():
	var x = randi_range(1, grid_width - 3)
	var y = randi_range(grid_height - 28, grid_height - 23)
	var pos = Vector2(x, y)
	game_manager.akira_chunk_pos = pos

func check_akira_reveal():
	if game_manager.akira_discovered:
		refresh_akira_visuals()
		return

	# Condition 1: Level 2 Reached
	if game_manager.colony_level >= 2:
		reveal_akira()
		return

	# Condition 2: Player dug within 1 chunk distance
	if game_manager.akira_chunk_pos != Vector2(-1, -1):
		for pos in dug_chunks.keys():
			if pos.distance_to(game_manager.akira_chunk_pos) <= 2.0:
				reveal_akira()
				return

func reveal_akira():
	if game_manager.akira_discovered: return
	refresh_akira_visuals()

func refresh_akira_visuals():
	if game_manager.akira_chunk_pos == Vector2(-1, -1): return
	if akira_instance != null: return

	spawn_akira_entity(game_manager.akira_chunk_pos)
	
	var pos = game_manager.akira_chunk_pos
	var s_id = get_new_structure_id()
	
	if not dug_chunks.has(pos):
		force_instant_dig(pos.x, pos.y, "straight", 0, "tunnel", s_id, true)
		force_instant_dig(pos.x + 1, pos.y, "straight", 0, "tunnel", s_id, true)
		queue_redraw()

func spawn_akira_entity(chunk_pos: Vector2):
	if akira_instance != null: return
	if not akira_scene: return
	
	akira_instance = akira_scene.instantiate()
	add_child(akira_instance)
	
	var world_pos = chunk_to_world_position(chunk_pos + Vector2(1, 0))
	akira_instance.position = world_pos
	
	if akira_instance.has_signal("akira_clicked"):
		akira_instance.connect("akira_clicked", Callable(self, "_on_akira_clicked"))

func _on_akira_clicked(_akira):
	var control = get_parent().get_node("Control")
	if control:
		control.open_akira_shop()

func update_sky_gradient(ratio: float):
	current_day_progress = ratio
	
	if sky_gradient_texture and sky_gradient_texture.gradient:
		var top = sky_night_top.lerp(sky_day_top, ratio)
		var bot = sky_night_bottom.lerp(sky_day_bottom, ratio)
		sky_gradient_texture.gradient.set_color(0, top)
		sky_gradient_texture.gradient.set_color(1, bot)

func _on_time_changed(is_day):
	var target_progress = 1.0 if is_day else 0.0
	var tween_sky = create_tween()
	tween_sky.tween_method(update_sky_gradient, current_day_progress, target_progress, 2.0)
	
	var ambient_color = Color(0.0, 0.0, 0.0, 0.357)
	if not is_day: ambient_color = Color(0.024, 0.014, 0.006, 0.749)
	if sky_overlay:
		var tween = create_tween()
		tween.tween_property(sky_overlay, "color", ambient_color, 2.0)

	var depth_modulate = Color(1.0, 1.0, 1.0, 1.0)
	if not is_day: depth_modulate = Color(1.0, 1.0, 1.0, 0.3)
	if darkness_overlay:
		var tween = create_tween()
		tween.tween_property(darkness_overlay, "modulate", depth_modulate, 2.0)
	
	var surface_tint = Color(0.878, 0.878, 0.878, 1.0)
	if not is_day: surface_tint = Color(0.271, 0.255, 0.263, 1.0)
	for obj in surface_objects:
		var tween = create_tween()
		tween.tween_property(obj, "modulate", surface_tint, 2.0)
	
	for star in star_pool:
		if is_instance_valid(star): star.visible = not is_day
		
	queue_redraw()

func _process(delta):
	# --- ASH LOGIC ---
	if ash_is_present:
		ash_duration_timer -= delta
		if ash_duration_timer <= 0:
			despawn_ash()
	else:
		ash_spawn_timer -= delta
		if ash_spawn_timer <= 0:
			spawn_ash()

	if not game_manager.is_daytime:
		var time = Time.get_ticks_msec() / 1000.0
		for star in star_pool:
			if is_instance_valid(star) and star.visible:
				var flicker_speed = star.get_meta("flicker_speed")
				var flicker_offset = star.get_meta("flicker_offset")
				var alpha = 0.65 + 0.35 * sin(time * flicker_speed + flicker_offset)
				star.modulate.a = alpha

	if cloud_rects.size() >= 2:
		var c1 = cloud_rects[0]
		var c2 = cloud_rects[1]
		var tex_width = c1.texture.get_width() * c1.scale.x
		c1.position.x -= cloud_speed * delta
		c2.position.x -= cloud_speed * delta
		if c1.position.x < -tex_width: c1.position.x = c2.position.x + tex_width
		if c2.position.x < -tex_width: c2.position.x = c1.position.x + tex_width

	if build_mode_active and not lock_preview:
		var mouse_chunk = get_chunk_at_mouse()
		preview_chunks.clear()
		var def = game_manager.get_room_def(current_build_type)
		var size = def["size"]
		if can_place_room(mouse_chunk, current_build_type):
			for dx in range(size.x):
				for dy in range(size.y):
					preview_chunks.append(Vector2(mouse_chunk.x + dx, mouse_chunk.y + dy))
		queue_redraw()
	if remove_mode_active: queue_redraw()

func _draw():
	if build_mode_active or plant_mode_active or remove_mode_active:
		for x in range(grid_width + 1):
			draw_line(Vector2(x*chunk_size, 0), Vector2(x*chunk_size, grid_height * chunk_size), Color(1, 1, 1, 0.2), 1)
		for y in range(grid_height + 1):
			draw_line(Vector2(0, y*chunk_size), Vector2(grid_width * chunk_size, y*chunk_size), Color(1, 1, 1, 0.2), 1)
	
	for chunk_pos in dug_chunks.keys():
		var d = dug_chunks[chunk_pos]
		var is_ghost = (d.get("status") == "planned")
		draw_chunk_graphic(chunk_pos, d["type"], d["piece_rotation"], d.get("room_type", "tunnel"), is_ghost)
	
	if build_mode_active and preview_chunks.size() > 0:
		for chunk_pos in preview_chunks:
			# Show the selected shape/rotation in the preview
			draw_chunk_graphic(chunk_pos, current_tunnel_piece, tunnel_rotation, current_build_type, true)
	
	if remove_mode_active:
		var m_pos = get_chunk_at_mouse()
		if dug_chunks.has(m_pos):
			draw_rect(Rect2(m_pos.x*64, m_pos.y*64, 64, 64), Color(1, 0, 0, 0.4))

func draw_chunk_graphic(chunk_pos, type, rot, r_type, is_preview):
	var base_color = game_manager.get_room_color(r_type)
	base_color.a = 0.3 if is_preview else 0.9
	
	var x = chunk_pos.x * chunk_size
	var y = chunk_pos.y * chunk_size
	var center = Vector2(x + chunk_size / 2, y + chunk_size / 2)
	
	var is_room = (r_type != "tunnel")
	
	if is_room:
		draw_rect(Rect2(x, y, chunk_size, chunk_size), base_color)
	else:
		base_color.a = 0.2 if is_preview else 0.5
		var radius = 22.0
		var connections = get_rotated_connections(type, int(rot))
		
		if connections.size() > 0: draw_circle(center, radius, base_color)
		for dir in connections:
			var rect = Rect2()
			match dir:
				"left": rect = Rect2(x, center.y - radius, 32, 44)
				"right": rect = Rect2(center.x, center.y - radius, 32, 44)
				"up": rect = Rect2(center.x - radius, y, 44, 32)
				"down": rect = Rect2(center.x - radius, center.y, 44, 32)
			draw_rect(rect, base_color)

func get_new_structure_id() -> int:
	next_structure_id += 1
	return next_structure_id

func force_instant_dig(x, y, type, rot, r_type, s_id, silent = false):
	var pos = Vector2(x,y)
	dug_chunks[pos] = { "type": type, "piece_rotation": rot, "room_type": r_type, "status": "ready", "structure_id": s_id }
	game_manager.register_built_room(r_type, pos, s_id, silent)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var chunk_pos = get_chunk_at_mouse()
		if remove_mode_active: request_removal(chunk_pos)
		elif build_mode_active and can_place_room(chunk_pos, current_build_type) and not lock_preview:
			# Pass correct shape and rotation to the request
			request_dig_area(chunk_pos.x, chunk_pos.y, current_build_type, current_tunnel_piece, tunnel_rotation)

func can_place_room(start_pos: Vector2, room_type: String) -> bool:
	var def = game_manager.get_room_def(room_type)
	var size = def["size"]
	var connected = false
	
	for dx in range(size.x):
		for dy in range(size.y):
			var cx = start_pos.x + dx
			var cy = start_pos.y + dy
			if cx < 0 or cx >= grid_width: return false
			if cy < sky_rows or cy >= grid_height: return false
			if is_chunk_dug(cx, cy): return false
			
			var neighbors = [Vector2(0,1), Vector2(0,-1), Vector2(1,0), Vector2(-1,0)]
			for n in neighbors:
				var n_pos = Vector2(cx, cy) + n
				if is_chunk_dug(n_pos.x, n_pos.y):
					connected = true
	return connected

# UPDATED: DIRECTLY ADDS TO QUEUE (BLUEPRINT MODE)
func request_dig_area(start_x, start_y, room_type, piece_shape = "straight", piece_rot = 0):
	var def = game_manager.get_room_def(room_type)
	var size = def["size"]
	var cost = def["cost"]
	
	# 1. Pay Up Front
	if not game_manager.spend_money(cost):
		return # Not enough money
		
	var s_id = get_new_structure_id()
	
	# 2. Add to GameManager Queue
	var task_data = {
		"room_type": room_type,
		"size": size,
		"cost": cost,
		"build_time": def["build_time"],
		"piece_shape": piece_shape,
		"piece_rot": piece_rot,
		"structure_id": s_id,
		"target_pos": Vector2(start_x, start_y),
		"type": "dig"
	}
	
	# 3. Mark chunks as "planned" immediately (Visual Feedback)
	for dx in range(size.x):
		for dy in range(size.y):
			var pos = Vector2(start_x+dx, start_y+dy)
			dug_chunks[pos] = {
				"type": piece_shape,
				"piece_rotation": piece_rot,
				"room_type": room_type,
				"status": "planned",
				"structure_id": s_id
			}
			# Set target to actual position for multi-tile rooms if needed
			task_data["target_pos"] = Vector2(start_x, start_y)
			
	game_manager.add_to_build_queue(task_data)
	queue_redraw()

func confirm_dig_task(start_x, start_y, task_data, assigned_ant):
	# This function is kept for compatibility if needed,
	# but the primary logic is now in request_dig_area (queue addition)
	# and finalize_dig (completion).
	pass

func request_removal(chunk_pos: Vector2):
	if not dug_chunks.has(chunk_pos): return
	
	if game_manager.akira_chunk_pos != Vector2(-1, -1):
		if chunk_pos == game_manager.akira_chunk_pos or chunk_pos == game_manager.akira_chunk_pos + Vector2(1, 0):
			game_manager.send_message("Ancient roots protect this tunnel...", Color.MAGENTA)
			return

	var data = dug_chunks[chunk_pos]
	var target_id = data.get("structure_id", -1)
	var status = data.get("status", "ready")
	var structure_chunks = []
	
	if target_id != -1:
		for pos in dug_chunks.keys():
			if dug_chunks[pos].get("structure_id") == target_id:
				structure_chunks.append(pos)
	else:
		structure_chunks.append(chunk_pos)

	if status == "planned":
		var refund = 0
		for pos in structure_chunks:
			if dug_chunks.has(pos):
				refund += 5
				dug_chunks.erase(pos)
				# FIX: Calling the function that now exists in GameManager
				game_manager.cancel_task_at(pos)
		game_manager.add_money(refund)
		game_manager.send_message("Blueprint Cancelled.", Color.GREEN)
		
	elif status == "ready":
		for pos in structure_chunks:
			if is_chunk_occupied(pos):
				game_manager.send_message("Ant inside!", Color.RED)
				return
		for pos in structure_chunks:
			if dug_chunks.has(pos):
				if fungus_grid.has(pos): remove_fungus(pos.x, pos.y)
				var r_type = dug_chunks[pos].get("room_type", "tunnel")
				game_manager.unregister_room(r_type, pos)
				dug_chunks.erase(pos)
		game_manager.send_message("Demolished.", Color.ORANGE)
	queue_redraw()

func is_chunk_occupied(chunk_pos: Vector2) -> bool:
	return game_manager.is_ant_at_chunk(chunk_pos)

func finalize_dig(target_pos: Vector2):
	if not dug_chunks.has(target_pos): return
	
	var s_id = dug_chunks[target_pos].get("structure_id", -1)
	if s_id != -1:
		for pos in dug_chunks.keys():
			if dug_chunks[pos].get("structure_id") == s_id:
				dug_chunks[pos]["status"] = "ready"
				var r_type = dug_chunks[pos].get("room_type", "tunnel")
				game_manager.register_built_room(r_type, pos, s_id)
				
	check_akira_reveal()
	queue_redraw()

# --- FIXED: PARSES STRINGS FROM SAVE FILES BACK TO VECTOR2 ---
func chunk_to_world_position(c): 
	var v = c
	if v is String:
		# Save data loads vectors as strings like "(1, 2)".
		# We must clean and parse this back to a usable Vector2.
		var clean = v.replace("(", "").replace(")", "")
		var parts = clean.split(",")
		if parts.size() >= 2:
			v = Vector2(float(parts[0]), float(parts[1]))
		else:
			v = Vector2.ZERO
	
	# Perform math on the safe Vector2 'v'
	return Vector2(v.x*64+32, v.y*64+32)

func get_chunk_at_mouse(): return Vector2(int(get_global_mouse_position().x/64), int(get_global_mouse_position().y/64))

func get_rotated_connections(type, rot):
	var i_rot = int(rot)
	var base = piece_connections[type]
	var map = {0:{"left":"left","right":"right","up":"up","down":"down"}, 90:{"left":"up","right":"down","up":"right","down":"left"}, 180:{"left":"right","right":"left","up":"down","down":"up"}, 270:{"left":"down","right":"up","up":"left","down":"right"}}
	var r = []
	if not map.has(i_rot): return base
	for c in base: r.append(map[i_rot][c])
	return r

func is_chunk_dug(x,y): return dug_chunks.has(Vector2(x,y))

func world_to_chunk_position(world_pos: Vector2) -> Vector2:
	return Vector2(int(world_pos.x / chunk_size), int(world_pos.y / chunk_size))

func is_chunk_walkable(chunk_pos: Vector2) -> bool:
	if not dug_chunks.has(chunk_pos): return false
	# NEW: Planned chunks are NOT walkable yet
	return dug_chunks[chunk_pos]["status"] == "ready"

func chunks_are_connected(chunk_a: Vector2, chunk_b: Vector2) -> bool:
	if not (dug_chunks.has(chunk_a) and dug_chunks.has(chunk_b)): return false
	
	var data_a = dug_chunks[chunk_a]
	var data_b = dug_chunks[chunk_b]
	
	var id_a = data_a.get("structure_id", -1)
	var id_b = data_b.get("structure_id", -1)
	
	if id_a == id_b and id_a != -1: return true

	var cons_a = []
	if data_a["room_type"] != "tunnel": cons_a = ["left", "right", "up", "down"]
	else: cons_a = get_rotated_connections(data_a["type"], int(data_a["piece_rotation"]))
	
	var cons_b = []
	if data_b["room_type"] != "tunnel": cons_b = ["left", "right", "up", "down"]
	else: cons_b = get_rotated_connections(data_b["type"], int(data_b["piece_rotation"]))
	
	var diff = chunk_b - chunk_a
	if diff == Vector2(1, 0): return "right" in cons_a and "left" in cons_b
	elif diff == Vector2(-1, 0): return "left" in cons_a and "right" in cons_b
	elif diff == Vector2(0, 1): return "down" in cons_a and "up" in cons_b
	elif diff == Vector2(0, -1): return "up" in cons_a and "down" in cons_b
	return false

func get_multitile_access_point(top_left: Vector2, size: Vector2) -> Vector2:
	for x in range(size.x):
		for y in range(size.y):
			var tile_pos = top_left + Vector2(x, y)
			var neighbor = get_nearest_accessible_neighbor(tile_pos)
			if neighbor != Vector2(-1, -1):
				return neighbor
	return Vector2(-1, -1)

func get_nearest_accessible_neighbor(target_chunk: Vector2) -> Vector2:
	var neighbors = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	for n in neighbors:
		var check_pos = target_chunk + n
		if is_chunk_walkable(check_pos):
			return check_pos
	return Vector2(-1, -1)

func find_path(start_chunk: Vector2, end_chunk: Vector2) -> Array:
	var open_set = [start_chunk]
	var came_from = {}
	var g_score = {start_chunk: 0}
	var f_score = {start_chunk: heuristic(start_chunk, end_chunk)}
	while open_set.size() > 0:
		var current = open_set[0]
		var lowest_f = f_score.get(current, INF)
		for node in open_set:
			if f_score.get(node, INF) < lowest_f:
				current = node
				lowest_f = f_score[node]
		if current == end_chunk: return reconstruct_path(came_from, current)
		open_set.erase(current)
		var neighbors = [Vector2(current.x-1,current.y), Vector2(current.x+1,current.y), Vector2(current.x,current.y-1), Vector2(current.x,current.y+1)]
		for neighbor in neighbors:
			if not is_chunk_walkable(neighbor): continue
			if not chunks_are_connected(current, neighbor): continue
			var tentative_g = g_score.get(current, INF) + 1
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + heuristic(neighbor, end_chunk)
				if not neighbor in open_set: open_set.append(neighbor)
	return []

func heuristic(a: Vector2, b: Vector2) -> float: return abs(a.x - b.x) + abs(a.y - b.y)
func reconstruct_path(came_from: Dictionary, current: Vector2) -> Array:
	var path = [current]
	while came_from.has(current):
		current = came_from[current]
		path.insert(0, current)
	return path

func can_plant_fungus(chunk_x: int, chunk_y: int) -> bool:
	var pos = Vector2(chunk_x, chunk_y)
	if not is_chunk_walkable(pos): return false
	if fungus_grid.has(pos): return false
	var chunk_data = dug_chunks[pos]
	if chunk_data["room_type"] == "farming_room": return true
	if chunk_data["room_type"] == "tunnel" and chunk_data["type"] == "straight": return true
	return false

func plant_fungus(chunk_x: int, chunk_y: int, type: String = "basic"):
	if not can_plant_fungus(chunk_x, chunk_y): return
	var chunk_pos = Vector2(chunk_x, chunk_y)
	var chunk_data = dug_chunks[chunk_pos]
	
	var new_fungus = fungus_scene.instantiate()
	add_child(new_fungus)
	
	if chunk_data["room_type"] != "tunnel":
		new_fungus.position = Vector2(chunk_x * chunk_size + (chunk_size / 2), chunk_y * chunk_size + (chunk_size - 10))
		new_fungus.rotation_degrees = 0
	else:
		var rotation_deg = int(chunk_data["piece_rotation"])
		var is_vertical = (rotation_deg == 90 or rotation_deg == 270)
		if is_vertical:
			new_fungus.position = Vector2(chunk_x * chunk_size + (chunk_size - 10), chunk_y * chunk_size + (chunk_size / 2))
			new_fungus.rotation_degrees = -90
		else:
			new_fungus.position = Vector2(chunk_x * chunk_size + (chunk_size / 2), chunk_y * chunk_size + (chunk_size - 10))
			new_fungus.rotation_degrees = 0
			
	if new_fungus.has_method("initialize"):
		new_fungus.initialize(type)
	fungus_grid[chunk_pos] = new_fungus

func get_fungus_at(chunk_x: int, chunk_y: int):
	var pos = Vector2(chunk_x, chunk_y)
	if fungus_grid.has(pos): return fungus_grid[pos]
	return null
	
func remove_fungus(chunk_x: int, chunk_y: int):
	var pos = Vector2(chunk_x, chunk_y)
	if fungus_grid.has(pos):
		var fungus = fungus_grid[pos]
		fungus.queue_free()
		fungus_grid.erase(pos)

func set_remove_mode_active(active: bool):
	remove_mode_active = active
	if active: build_mode_active = false; plant_mode_active = false
	queue_redraw()

func set_build_mode_active(active: bool):
	build_mode_active = active
	if active: remove_mode_active = false; plant_mode_active = false
	preview_chunks.clear()
	queue_redraw()

func set_plant_mode_active(active: bool):
	plant_mode_active = active
	if active: build_mode_active = false; remove_mode_active = false
	queue_redraw()

func set_build_type(type_id: String): current_build_type = type_id
func set_tunnel_piece(piece: String): current_tunnel_piece = piece
func set_tunnel_rotation(rot: int): tunnel_rotation = rot
