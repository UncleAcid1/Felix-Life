extends Camera2D

# Zoom settings
var zoom_speed = 0.1
var min_zoom = 0.75
var max_zoom = 12.0 # Increased max to support extreme zoom

# Panning settings
var pan_speed = 500.0

# Focus Mode
var is_focused = false
var focus_target_pos = Vector2.ZERO
# CHANGED: 10.0 is "Pore-seeing" levels of close-up
var focus_zoom_level = Vector2(10.0, 10.0) 

# World bounds
var world_left = 0
var world_right = 768
var world_top = 0
var world_bottom = 3072 # UPDATED: 48 chunks * 64px = 3072
var screen_width = 768
var screen_height = 1024

func _ready():
	zoom = Vector2(1.0, 1.0)
	position = Vector2(384, 512)

func _process(delta):
	if is_focused:
		# Smooth lerp to target
		position = position.lerp(focus_target_pos, 5.0 * delta)
		zoom = zoom.lerp(focus_zoom_level, 5.0 * delta)
		return 
	
	# Manual Zoom
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		zoom_in()
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		zoom_out()
	
	# Manual Pan
	var movement = Vector2.ZERO
	if Input.is_action_pressed("ui_up"): movement.y -= pan_speed * delta / zoom.x
	if Input.is_action_pressed("ui_down"): movement.y += pan_speed * delta / zoom.x
	if Input.is_action_pressed("ui_left"): movement.x -= pan_speed * delta / zoom.x
	if Input.is_action_pressed("ui_right"): movement.x += pan_speed * delta / zoom.x
	
	position += movement
	constrain_camera()

func start_focus(target_pos: Vector2):
	is_focused = true
	# Offset logic: If the menu is on the LEFT, we might want the camera slightly to the RIGHT
	# But for now, center on face is good.
	focus_target_pos = target_pos

func stop_focus():
	is_focused = false

func constrain_camera():
	var visible_width = screen_width / zoom.x
	var visible_height = screen_height / zoom.y
	var min_x = world_left + visible_width / 2
	var max_x = world_right - visible_width / 2
	var min_y = world_top + visible_height / 2
	var max_y = world_bottom - visible_height / 2
	
	# If zoomed out too far, center instead of clamping
	if visible_width > (world_right - world_left):
		position.x = (world_right + world_left) / 2
	else:
		position.x = clamp(position.x, min_x, max_x)
		
	if visible_height > (world_bottom - world_top):
		position.y = (world_bottom + world_top) / 2
	else:
		position.y = clamp(position.y, min_y, max_y)

func zoom_in():
	var new_zoom = zoom + Vector2(zoom_speed, zoom_speed)
	if new_zoom.x <= max_zoom: zoom = new_zoom

func zoom_out():
	var new_zoom = zoom - Vector2(zoom_speed, zoom_speed)
	var visible_width = screen_width / new_zoom.x
	var visible_height = screen_height / new_zoom.y
	
	# Allow zooming out until we see the whole world bounds
	if visible_width <= (world_right - world_left) * 1.5 and visible_height <= (world_bottom - world_top) * 1.5:
		if new_zoom.x >= min_zoom: zoom = new_zoom
