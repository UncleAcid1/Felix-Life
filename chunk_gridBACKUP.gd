extends Node2D

# Chunk settings
var chunk_size = 64
var grid_width = 12
var grid_height = 30
var sky_rows = 2

# Dictionaries
var dug_chunks = {}
var fungus_grid = {}
var akira_instance = null

# Resources
var fungus_scene = preload("res://scenes/fungi_standard.tscn")
var cloud_texture = preload("res://sprites/cloud.png")

# --- UPDATED: PATH TO YOUR NEW SCENE ---
# MAKE SURE THIS PATH IS CORRECT!
var akira_scene = preload("res://scenes/akira.tscn")

# State Flags
var build_mode_active = false
var remove_mode_active = false
var plant_mode_active = false
var current_tunnel_piece = "straight"
var current_build_type = "tunnel"
var tunnel_rotation = 0
var preview_chunks = []

# ID Counter
var next_structure_id = 0

# Visual Nodes
var darkness_overlay: TextureRect
var cloud_rects = []
var cloud_speed = 10.0

# Colors
var sky_color_day = Color(0.4, 0.7, 1.0, 0.6)
var sky_color_night = Color(0.05, 0.05, 0.2, 0.6)
var current_sky_color = sky_color_day

# Connections
var piece_connections = {
	"straight": ["left", "right"],
	"corner": ["left", "up"],
	"t_junction": ["left", "right", "up"],
	"cross": ["left", "right", "up", "down"],
	"end_cap": ["left"]
}

var game_manager

func _ready():
	game_manager = get_parent().get_node("GameManager")
	game_manager.connect("time_changed", Callable(self, "_on_time_changed"))
	position = Vector2.ZERO
	
	# --- 1. BACKGROUND SOIL ---
	var bg_texture = load("res://enviroment/base_soil.png")
	var total_bg_size = Vector2.ZERO
	var bg_pos = Vector2.ZERO
	var texture_scale = 0.10
	
	if bg_texture:
		var bg = TextureRect.new()
		bg.name = "SoilBackground"
		bg.texture = bg_texture
		bg.stretch_mode = TextureRect.STRETCH_TILE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.z_index = -100
		
		bg.scale = Vector2(texture_scale, texture_scale)
		
		var margin = 2000.0
		bg_pos = Vector2(-margin, -margin)
		bg.position = bg_pos
		
		var map_w = grid_width * chunk_size
		var map_h = grid_height * chunk_size
		var total_cover_w = map_w + (margin * 2)
		var total_cover_h = map_h + (margin * 2)
		
		total_bg_size = Vector2(total_cover_w / texture_scale, total_cover_h / texture_scale)
		bg.size = total_bg_size
		add_child(bg)
		
		# --- 2. DARKNESS OVERLAY ---
		var gradient_tex = GradientTexture2D.new()
		gradient_tex.fill = GradientTexture2D.FILL_LINEAR
		gradient_tex.fill_from = Vector2(0, 0)
		gradient_tex.fill_to = Vector2(0, 1)
		
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(0, 0, 0, 0))
		gradient.add_point(0.4, Color(0, 0, 0, 0.5))
		gradient.add_point(0.8, Color(0, 0, 0, 0.7))
		gradient.add_point(1.0, Color(0, 0, 0, 1))
		
		gradient_tex.gradient = gradient
		
		darkness_overlay = TextureRect.new()
		darkness_overlay.name = "DarknessOverlay"
		darkness_overlay.texture = gradient_tex
		darkness_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		darkness_overlay.z_index = -99
		
		darkness_overlay.position = bg_pos
		darkness_overlay.scale = Vector2(texture_scale, texture_scale)
		darkness_overlay.size = total_bg_size
		
		add_child(darkness_overlay)

	# --- 3. CLOUDS ---
	if cloud_texture:
		for i in range(2):
			var c = TextureRect.new()
			c.texture = cloud_texture
			c.position = Vector2(i * (cloud_texture.get_width() * 0.75), -100)
			c.z_index = -90
			c.modulate.a = 0.8
			c.scale = Vector2(0.75, 0.75)
			
			if randf() > 0.5: c.flip_h = true
			if randf() > 0.5: c.flip_v = true
			
			add_child(c)
			cloud_rects.append(c)

	# --- GENERATION ---
	generate_initial_tunnel()
	
	# NEW: Check if Akira location is set. If not, generate it.
	if game_manager.akira_chunk_pos == Vector2(-1, -1):
		generate_akira_room()
	else:
		# If already known (loaded from save), refresh visuals
		refresh_akira_visuals()
	
	# Init Lighting
	_on_time_changed(game_manager.is_daytime)

func generate_initial_tunnel():
	var surface_y = sky_rows
	var start_row = sky_rows + 2
	var center_x = grid_width / 2
	
	var init_id = get_new_structure_id()
	
	for y in range(surface_y, start_row):
		force_instant_dig(center_x, y, "straight", 90, "tunnel", init_id)
	
	force_instant_dig(center_x - 1, start_row, "straight", 0, "tunnel", init_id)
	force_instant_dig(center_x, start_row, "t_junction", 0, "tunnel", init_id)
	force_instant_dig(center_x + 1, start_row, "straight", 0, "tunnel", init_id)
	
	queue_redraw()

func generate_akira_room():
	# Pick a random spot deep in the map
	# Constraints: Y between 10 and 25, X between 1 and Width-2
	var y = randi_range(10, grid_height - 5)
	var x = randi_range(1, grid_width - 3)
	
	var pos = Vector2(x, y)
	game_manager.akira_chunk_pos = pos
	print("GENERATED: Akira hidden at: ", pos)

func refresh_akira_visuals():
	# Only spawn visuals if she is DISCOVERED
	if game_manager.akira_discovered and game_manager.akira_chunk_pos != Vector2(-1, -1):
		
		# 1. Spawn the Entity
		spawn_akira_entity(game_manager.akira_chunk_pos)
		
		# 2. Dig the room visually
		var pos = game_manager.akira_chunk_pos
		if not dug_chunks.has(pos):
			var s_id = get_new_structure_id()
			# Left side (Entrance)
			force_instant_dig(pos.x, pos.y, "end_cap", 180, "tunnel", s_id)
			# Right side (The Den)
			force_instant_dig(pos.x + 1, pos.y, "end_cap", 0, "tunnel", s_id)
			
			queue_redraw()

func spawn_akira_entity(chunk_pos: Vector2):
	if akira_instance != null: return # Already spawned
	if not akira_scene: return
	
	# Instantiate the SCENE
	akira_instance = akira_scene.instantiate()
	add_child(akira_instance)
	
	# Position: In the right half of the 2x1 room
	# We add Vector2(1,0) because the room starts at `chunk_pos`, she is in the second tile
	var world_pos = chunk_to_world_position(chunk_pos + Vector2(1, 0))
	
	# Center her in that tile
	akira_instance.position = world_pos

func _on_time_changed(is_day):
	if is_day:
		if darkness_overlay: darkness_overlay.modulate = Color(1, 1, 1, 1)
		current_sky_color = sky_color_day
	else:
		if darkness_overlay: darkness_overlay.modulate = Color(0.3, 0.3, 0.5, 1)
		current_sky_color = sky_color_night
	queue_redraw()

func _process(delta):
	if cloud_rects.size() > 0:
		var width = cloud_rects[0].texture.get_width() * cloud_rects[0].scale.x
		for c in cloud_rects:
			c.position.x -= cloud_speed * delta
		if cloud_rects[0].position.x < -width:
			cloud_rects[0].position.x = cloud_rects[1].position.x + width
		if cloud_rects[1].position.x < -width:
			cloud_rects[1].position.x = cloud_rects[0].position.x + width

	if build_mode_active:
		var mouse_chunk = get_chunk_at_mouse()
		preview_chunks.clear()
		
		var def = game_manager.get_room_def(current_build_type)
		var size = def["size"]
		
		if can_place_room(mouse_chunk, current_build_type):
			for dx in range(size.x):
				for dy in range(size.y):
					preview_chunks.append(Vector2(mouse_chunk.x + dx, mouse_chunk.y + dy))
		queue_redraw()
	
	if remove_mode_active:
		queue_redraw()

func _draw():
	# Draw Sky
	var margin = 2000.0
	var map_w = grid_width * chunk_size
	var map_h = grid_height * chunk_size
	var sky_rect = Rect2(-margin, -margin, map_w + margin * 2, margin + (sky_rows * chunk_size))
	draw_rect(sky_rect, current_sky_color)

	# Draw Grid Lines
	if build_mode_active or plant_mode_active or remove_mode_active:
		for x in range(grid_width + 1):
			var x_pos = x * chunk_size
			draw_line(Vector2(x_pos, 0), Vector2(x_pos, grid_height * chunk_size), Color(1, 1, 1, 0.2), 1)
		for y in range(grid_height + 1):
			var y_pos = y * chunk_size
			draw_line(Vector2(0, y_pos), Vector2(grid_width * chunk_size, y_pos), Color(1, 1, 1, 0.2), 1)
	
	# Draw dug chunks
	for chunk_pos in dug_chunks.keys():
		var chunk_data = dug_chunks[chunk_pos]
		var r_type = chunk_data.get("room_type", "tunnel")
		var status = chunk_data.get("status", "ready")
		var is_ghost = (status == "planned")
		draw_tunnel_piece(chunk_pos, chunk_data["type"], chunk_data["piece_rotation"], r_type, is_ghost)
	
	# --- DRAW AKIRA'S MOUSEHOLE (Background) ---
	if game_manager.akira_discovered and game_manager.akira_chunk_pos != Vector2(-1, -1):
		var ak_pos = game_manager.akira_chunk_pos
		var hole_center = chunk_to_world_position(ak_pos + Vector2(1, 0))
		# Draw a dark circle to represent the den entrance
		draw_circle(hole_center, 25, Color(0.1, 0.05, 0.05, 1.0))

	# Draw preview
	if build_mode_active and preview_chunks.size() > 0:
		for chunk_pos in preview_chunks:
			draw_tunnel_piece(chunk_pos, current_tunnel_piece, tunnel_rotation, current_build_type, true)
	
	# Remove Preview
	if remove_mode_active:
		var m_pos = get_chunk_at_mouse()
		if dug_chunks.has(m_pos):
			draw_rect(Rect2(m_pos.x*64, m_pos.y*64, 64, 64), Color(1, 0, 0, 0.4))

func draw_tunnel_piece(chunk_pos: Vector2, piece_type: String, piece_rotation: int, room_type: String, is_preview: bool = false):
	var base_color = game_manager.get_room_color(room_type)
	if is_preview: base_color.a = 0.2
	else: base_color.a = 0.5
	
	var x = chunk_pos.x * chunk_size
	var y = chunk_pos.y * chunk_size
	var center = Vector2(x + chunk_size / 2, y + chunk_size / 2)
	var tunnel_width = 44.0
	var radius = tunnel_width / 2.0
	
	var connections = get_rotated_connections(piece_type, piece_rotation)
	if connections.size() > 0:
		draw_circle(center, radius, base_color)
	
	for direction in connections:
		var rect = Rect2()
		match direction:
			"left": rect = Rect2(x, center.y - radius, chunk_size / 2, tunnel_width)
			"right": rect = Rect2(center.x, center.y - radius, chunk_size / 2, tunnel_width)
			"up": rect = Rect2(center.x - radius, y, tunnel_width, chunk_size / 2)
			"down": rect = Rect2(center.x - radius, center.y, tunnel_width, chunk_size / 2)
		draw_rect(rect, base_color)

# --- DIGGING LOGIC ---
func get_new_structure_id() -> int:
	next_structure_id += 1
	return next_structure_id

func request_dig_area(start_x: int, start_y: int, room_type: String):
	var def = game_manager.get_room_def(room_type)
	var size = def["size"]
	var total_cost = def["cost"]
	
	if not game_manager.spend_money(total_cost): return
	
	var struct_id = get_new_structure_id()
	
	for dx in range(size.x):
		for dy in range(size.y):
			var target_x = start_x + dx
			var target_y = start_y + dy
			var chunk_pos = Vector2(target_x, target_y)
			var p_type = "cross"
			var p_rot = 0
			
			if size == Vector2(1,1):
				p_type = current_tunnel_piece
				p_rot = tunnel_rotation
			
			dug_chunks[chunk_pos] = {
				"type": p_type,
				"piece_rotation": p_rot,
				"room_type": room_type,
				"status": "planned",
				"structure_id": struct_id
			}
			game_manager.add_task("dig", chunk_pos, {
				"room_type": room_type,
				"duration": def["build_time"],
				"structure_id": struct_id
			})
	queue_redraw()

func request_removal(chunk_pos: Vector2):
	if not dug_chunks.has(chunk_pos): return
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

func finalize_dig(chunk_pos: Vector2):
	if dug_chunks.has(chunk_pos):
		dug_chunks[chunk_pos]["status"] = "ready"
		var r_type = dug_chunks[chunk_pos].get("room_type", "tunnel")
		game_manager.register_built_room(r_type, chunk_pos)
		queue_redraw()

func force_instant_dig(x, y, type, rot, r_type, s_id):
	var pos = Vector2(x,y)
	dug_chunks[pos] = { "type": type, "piece_rotation": rot, "room_type": r_type, "status": "ready", "structure_id": s_id }
	game_manager.register_built_room(r_type, pos)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var chunk_pos = get_chunk_at_mouse()
		if remove_mode_active:
			request_removal(chunk_pos)
		elif build_mode_active:
			if can_place_room(chunk_pos, current_build_type):
				request_dig_area(chunk_pos.x, chunk_pos.y, current_build_type)

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
				if is_chunk_dug(n_pos.x, n_pos.y): connected = true
	return connected

func can_plant_fungus(chunk_x: int, chunk_y: int) -> bool:
	var pos = Vector2(chunk_x, chunk_y)
	if not is_chunk_walkable(pos): return false
	if fungus_grid.has(pos): return false
	if chunk_y < sky_rows: return false
	var chunk_data = dug_chunks[pos]
	if chunk_data["type"] != "straight": return false
	return true

func plant_fungus(chunk_x: int, chunk_y: int, type: String = "basic"):
	if not can_plant_fungus(chunk_x, chunk_y): return
	var chunk_pos = Vector2(chunk_x, chunk_y)
	var chunk_data = dug_chunks[chunk_pos]
	var rotation_deg = chunk_data["piece_rotation"]
	var new_fungus = fungus_scene.instantiate()
	add_child(new_fungus)
	var is_vertical = (rotation_deg == 90 or rotation_deg == 270)
	if is_vertical:
		new_fungus.position = Vector2(chunk_x * chunk_size + (chunk_size - 10), chunk_y * chunk_size + (chunk_size / 2))
		new_fungus.rotation_degrees = -90
	else:
		new_fungus.position = Vector2(chunk_x * chunk_size + (chunk_size / 2), chunk_y * chunk_size + (chunk_size - 10))
		new_fungus.rotation_degrees = 0
	if new_fungus.has_method("initialize"):
		new_fungus.initialize(type)
		new_fungus.connect("mature", Callable(self, "_on_fungus_matured"))
	fungus_grid[chunk_pos] = new_fungus

func _on_fungus_matured(fungus_instance): pass

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

func is_chunk_dug(chunk_x: int, chunk_y: int) -> bool:
	return dug_chunks.has(Vector2(chunk_x, chunk_y))

func is_chunk_walkable(chunk_pos: Vector2) -> bool:
	if not dug_chunks.has(chunk_pos): return false
	return dug_chunks[chunk_pos]["status"] == "ready"

func get_nearest_accessible_neighbor(target_chunk: Vector2) -> Vector2:
	var neighbors = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	var spots = []
	for n in neighbors:
		var check_pos = target_chunk + n
		if is_chunk_walkable(check_pos): spots.append(check_pos)
	if spots.size() > 0: return spots[0]
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

func get_rotated_connections(piece_type: String, piece_rotation: int) -> Array:
	var base_connections = piece_connections[piece_type]
	var rotated = []
	var rotation_map = {
		0: {"left": "left", "right": "right", "up": "up", "down": "down"},
		90: {"left": "up", "right": "down", "up": "right", "down": "left"},
		180: {"left": "right", "right": "left", "up": "down", "down": "up"},
		270: {"left": "down", "right": "up", "up": "left", "down": "right"}
	}
	for connection in base_connections:
		rotated.append(rotation_map[piece_rotation][connection])
	return rotated

func chunks_are_connected(chunk_a: Vector2, chunk_b: Vector2) -> bool:
	if not (dug_chunks.has(chunk_a) and dug_chunks.has(chunk_b)): return false
	var data_a = dug_chunks[chunk_a]
	var data_b = dug_chunks[chunk_b]
	var connections_a = get_rotated_connections(data_a["type"], data_a["piece_rotation"])
	var connections_b = get_rotated_connections(data_b["type"], data_b["piece_rotation"])
	var diff = chunk_b - chunk_a
	if diff == Vector2(1, 0): return "right" in connections_a and "left" in connections_b
	elif diff == Vector2(-1, 0): return "left" in connections_a and "right" in connections_b
	elif diff == Vector2(0, 1): return "down" in connections_a and "up" in connections_b
	elif diff == Vector2(0, -1): return "up" in connections_a and "down" in connections_b
	return false

func get_chunk_at_mouse() -> Vector2:
	var mouse_pos = get_global_mouse_position()
	return Vector2(int(mouse_pos.x / chunk_size), int(mouse_pos.y / chunk_size))

func world_to_chunk_position(world_pos: Vector2) -> Vector2:
	return Vector2(int(world_pos.x / chunk_size), int(world_pos.y / chunk_size))

func chunk_to_world_position(chunk: Vector2) -> Vector2:
	return Vector2(chunk.x * chunk_size + (chunk_size / 2), chunk.y * chunk_size + (chunk_size / 2))

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
