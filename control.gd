extends Control

var game_manager
var chunk_grid
var camera
var audio_manager

# Game State
var game_started = false
var input_allowed = false
var intro_ant = null

# State
var is_build_mode = false
var is_remove_mode = false
var is_plant_mode = false
var is_inventory_open = false
var is_settings_open = false

var selected_ant = null
var current_tunnel_piece = "straight"
var tunnel_rotation = 0
var current_seed_type = "basic"

# Animation state variables
var save_tween: Tween

# DEBUG / CHEATS
var cheat_buffer = ""

# --- AUDIO RESOURCES ---
var akira_clips = [
	preload("res://audio/voice/akira1.mp3"),
	preload("res://audio/voice/akira2.mp3"),
	preload("res://audio/voice/akira3.mp3")
]

# UI References
var btn_build = null
var btn_plant = null
var btn_inventory = null
var btn_settings = null

# Panels
var inventory_panel = null
var colony_list_panel = null
var ant_inspector_panel = null
var tunnel_selector_panel = null
var plant_selector_panel = null
var mound_hub_panel = null
var settings_panel = null
var delete_confirm_panel = null
var akira_panel = null
var akira_text_label = null

# NEW PANELS
var task_assignment_panel = null
var dining_hall_panel = null
var farm_management_panel = null 

# Pending Task Data
var pending_task_type = ""
var pending_task_target = Vector2.ZERO
var pending_task_data = {}
var pending_farm_chunk = Vector2(-1, -1) 
var pending_farm_id = -1

# Main Menu References
var main_menu_container = null

var seed_count_label = null
var build_info_label = null
var recruit_cost_label = null
var xp_label = null
var start_label = null
var clock_label = null

# UI Layout Settings
var screen_bottom_y = 1000

# --- COORDINATES ---
var backpack_x = 678
var shovel_x = 633
var plant_x = 570
var gear_x = 20

# --- RESOURCES ---
var main_font = load("res://fonts/PixelOperator.ttf")
var kiwi_font = load("res://fonts/KiwiSoda.ttf")

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	game_manager = get_node("/root/TestLevel/GameManager")
	chunk_grid = get_node("/root/TestLevel/ChunkGrid")
	audio_manager = get_node_or_null("/root/TestLevel/AudioManager")
	camera = get_viewport().get_camera_2d()
	
	# Connect standard signals
	game_manager.connect("money_changed", Callable(self, "_on_money_changed"))
	game_manager.connect("seeds_changed", Callable(self, "_on_seeds_changed"))
	game_manager.connect("system_message", Callable(self, "_on_system_message"))
	game_manager.connect("xp_changed", Callable(self, "_on_xp_changed"))
	game_manager.connect("level_up", Callable(self, "_on_level_up"))
	game_manager.connect("task_assignment_needed", Callable(self, "_on_task_assignment_needed"))
	
	# --- 1. UI BUTTONS SETUP ---
	setup_game_ui()
	
	# --- 2. PANELS SETUP ---
	create_tunnel_selector_panel()
	create_plant_selector_panel()
	create_ant_inspector_panel()
	create_global_inventory_panel()
	create_colony_list_panel()
	create_mound_hub_panel()
	create_settings_panel()
	create_delete_confirm_panel()
	create_akira_panel()
	create_task_assignment_panel()
	create_dining_hall_panel()
	create_farm_management_panel()
	
	_update_button_visuals()
	
	# --- 3. MAIN MENU START ---
	create_main_menu()

# --- WINDOW MANAGEMENT HELPERS ---
func is_any_window_open() -> bool:
	if inventory_panel and inventory_panel.visible: return true
	if colony_list_panel and colony_list_panel.visible: return true
	if mound_hub_panel and mound_hub_panel.visible: return true
	if settings_panel and settings_panel.visible: return true
	if akira_panel and akira_panel.visible: return true
	if task_assignment_panel and task_assignment_panel.visible: return true
	if dining_hall_panel and dining_hall_panel.visible: return true
	if farm_management_panel and farm_management_panel.visible: return true
	if ant_inspector_panel and ant_inspector_panel.visible: return true
	return false

func close_all_windows():
	if inventory_panel: inventory_panel.visible = false
	if colony_list_panel: colony_list_panel.visible = false
	if mound_hub_panel: mound_hub_panel.visible = false
	if settings_panel: settings_panel.visible = false
	if akira_panel: akira_panel.visible = false
	if task_assignment_panel: task_assignment_panel.visible = false
	if dining_hall_panel: dining_hall_panel.visible = false
	if farm_management_panel: farm_management_panel.visible = false
	
	# Special handling for inspector to unfreeze ant
	hide_ant_inspector()
	
	# Reset Toggles
	is_inventory_open = false
	is_settings_open = false
	is_build_mode = false
	is_plant_mode = false
	is_remove_mode = false
	
	_update_states()

func setup_game_ui():
	# BACKPACK
	var bag_texture = load("res://sprites/backpack.png")
	if bag_texture:
		btn_inventory = TextureButton.new()
		btn_inventory.texture_normal = bag_texture
		btn_inventory.ignore_texture_size = true
		btn_inventory.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	else:
		btn_inventory = Button.new(); btn_inventory.text = "BAG"
	btn_inventory.name = "InvToggle"
	btn_inventory.size = Vector2(80, 80)
	btn_inventory.position = Vector2(backpack_x, screen_bottom_y - 80)
	btn_inventory.focus_mode = Control.FOCUS_NONE
	btn_inventory.connect("pressed", Callable(self, "_on_inventory_toggle"))
	apply_font(btn_inventory)
	btn_inventory.visible = false
	add_child(btn_inventory)
	
	# SHOVEL
	var shovel_texture = load("res://sprites/shovel.png")
	if shovel_texture:
		btn_build = TextureButton.new()
		btn_build.texture_normal = shovel_texture
		btn_build.ignore_texture_size = true
		btn_build.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	else:
		btn_build = Button.new(); btn_build.text = "BUILD"
	btn_build.name = "ModeToggle"
	btn_build.size = Vector2(40, 40)
	btn_build.position = Vector2(shovel_x, screen_bottom_y - 40)
	btn_build.focus_mode = Control.FOCUS_NONE
	btn_build.connect("pressed", Callable(self, "_on_mode_toggle"))
	apply_font(btn_build)
	btn_build.visible = false
	add_child(btn_build)
	
	# PLANT
	var fungi_texture = load("res://sprites/plantmode.png")
	if not fungi_texture: fungi_texture = load("res://sprites/fungi/standard/1.png")
	if fungi_texture:
		btn_plant = TextureButton.new()
		btn_plant.texture_normal = fungi_texture
		btn_plant.ignore_texture_size = true
		btn_plant.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	else:
		btn_plant = Button.new(); btn_plant.text = "PLANT"
	btn_plant.name = "PlantToggle"
	btn_plant.size = Vector2(60, 60)
	btn_plant.position = Vector2(plant_x, screen_bottom_y - 60)
	btn_plant.focus_mode = Control.FOCUS_NONE
	btn_plant.connect("pressed", Callable(self, "_on_plant_toggle"))
	apply_font(btn_plant)
	btn_plant.visible = false
	add_child(btn_plant)

	# SETTINGS
	btn_settings = Button.new()
	btn_settings.text = "MENU"
	btn_settings.position = Vector2(gear_x, screen_bottom_y - 40)
	btn_settings.size = Vector2(60, 30)
	btn_settings.focus_mode = Control.FOCUS_NONE
	btn_settings.connect("pressed", Callable(self, "_on_settings_toggle"))
	apply_font(btn_settings)
	btn_settings.visible = false
	add_child(btn_settings)
	
	# MONEY
	var money_lbl = get_node_or_null("MoneyLabel")
	if not money_lbl:
		money_lbl = Label.new()
		money_lbl.name = "MoneyLabel"
		money_lbl.position = Vector2(50, 50)
		money_lbl.add_theme_font_size_override("font_size", 30)
		add_child(money_lbl)
	apply_font(money_lbl)
	money_lbl.visible = false
	
	# XP
	xp_label = Label.new()
	xp_label.name = "XPLabel"
	xp_label.position = Vector2(9, 34)
	xp_label.add_theme_font_size_override("font_size", 16)
	xp_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	xp_label.text = "Lvl 1 - XP: 0/100"
	apply_font(xp_label)
	xp_label.visible = false
	add_child(xp_label)
	
	# CLOCK
	clock_label = Label.new()
	clock_label.name = "ClockLabel"
	clock_label.add_theme_font_override("font", main_font)
	clock_label.add_theme_font_size_override("font_size", 18)
	clock_label.modulate = Color.WHITE
	clock_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock_label.position = Vector2(600, 10)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(clock_label)

# --- MAIN MENU SYSTEM ---
func create_main_menu():
	main_menu_container = Control.new()
	main_menu_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_menu_container.z_index = 4096 
	add_child(main_menu_container)
	
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_menu_container.add_child(bg)
	
	var title = Label.new()
	title.text = "FELIX'S COLONY"
	title.position = Vector2(0, 200)
	title.size = Vector2(768, 100)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if kiwi_font:
		title.add_theme_font_override("font", kiwi_font)
		title.add_theme_font_size_override("font_size", 80)
	main_menu_container.add_child(title)
	
	var btn_continue = Button.new()
	btn_continue.text = "CONTINUE"
	btn_continue.position = Vector2(234, 400)
	btn_continue.size = Vector2(300, 60)
	apply_font(btn_continue)
	
	if FileAccess.file_exists("user://felix_save.json"):
		btn_continue.connect("pressed", Callable(self, "_on_menu_continue"))
	else:
		btn_continue.disabled = true
		btn_continue.text = "NO SAVE FOUND"
	main_menu_container.add_child(btn_continue)
	
	var btn_new = Button.new()
	btn_new.text = "NEW GAME"
	btn_new.position = Vector2(234, 480)
	btn_new.size = Vector2(300, 60)
	btn_new.connect("pressed", Callable(self, "_on_menu_new_game"))
	apply_font(btn_new)
	main_menu_container.add_child(btn_new)

func _on_menu_continue():
	main_menu_container.queue_free()
	print("Loading game...")
	game_manager.load_game()
	create_start_screen()
	input_allowed = true
	_on_money_changed(game_manager.money)
	_on_level_up(game_manager.colony_level)
	
	if game_manager.ants.size() > 0:
		intro_ant = game_manager.ants[0]
		if camera:
			camera.position = intro_ant.position
			camera.start_focus(intro_ant.position)

func _on_menu_new_game():
	main_menu_container.queue_free()
	if FileAccess.file_exists("user://felix_save.json"):
		DirAccess.remove_absolute("user://felix_save.json")
	
	game_manager.reset_game_state()
	chunk_grid.reset_world()
	game_manager.recruit_new_ant(true)
	run_intro_sequence()

func run_intro_sequence():
	input_allowed = false
	var intro_layer = CanvasLayer.new()
	intro_layer.layer = 100
	add_child(intro_layer)
	
	var overlay = ColorRect.new()
	overlay.color = Color.BLACK
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	intro_layer.add_child(overlay)
	
	var load_lbl = Label.new()
	load_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	load_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if kiwi_font:
		load_lbl.add_theme_font_override("font", kiwi_font)
		load_lbl.add_theme_font_size_override("font_size", 128)
	else:
		apply_font(load_lbl)
		load_lbl.add_theme_font_size_override("font_size", 128)
	
	load_lbl.modulate = Color.WHITE
	intro_layer.add_child(load_lbl)
	
	await get_tree().create_timer(0.5).timeout
	load_lbl.text = "."
	await get_tree().create_timer(0.5).timeout
	load_lbl.text = ".."
	await get_tree().create_timer(0.5).timeout
	load_lbl.text = "..."
	await get_tree().create_timer(0.5).timeout
	load_lbl.text = ""
	await get_tree().create_timer(1.0).timeout
	load_lbl.queue_free()
	
	create_start_screen()
	
	if game_manager.ants.size() > 0:
		intro_ant = game_manager.ants[0]
		if camera: camera.start_focus(intro_ant.position)
	
	input_allowed = true
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween = create_tween()
	tween.tween_property(overlay, "modulate:a", 0.0, 1.5)
	await tween.finished
	intro_layer.queue_free()

func create_start_screen():
	if start_label: start_label.queue_free()
	start_label = Label.new()
	start_label.text = "Click to start playing!"
	start_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if kiwi_font:
		start_label.add_theme_font_override("font", kiwi_font)
		start_label.add_theme_font_size_override("font_size", 64)
	start_label.add_theme_color_override("font_outline_color", Color.BLACK)
	start_label.add_theme_constant_override("outline_size", 8)
	add_child(start_label)

func _process(_delta):
	if clock_label:
		var time = Time.get_time_dict_from_system()
		var date = Time.get_date_dict_from_system()
		var minute_str = str(time.minute).pad_zeros(2)
		var time_str = str(time.hour) + ":" + minute_str
		var date_str = str(date.month) + "/" + str(date.day) + "/" + str(date.year)
		clock_label.text = date_str + "\n" + time_str
		clock_label.position = Vector2(get_viewport_rect().size.x - 120, 10)

	if not game_started:
		if start_label:
			var time_secs = Time.get_ticks_msec() / 1000.0
			var alpha = (sin(time_secs * 3.0) + 1.0) / 2.0
			start_label.modulate.a = alpha
		if intro_ant and is_instance_valid(intro_ant) and camera:
			camera.start_focus(intro_ant.position)
		return

	# Handle panel blocking
	if is_build_mode and tunnel_selector_panel and tunnel_selector_panel.visible:
		var mouse_pos = get_global_mouse_position()
		var panel_rect = tunnel_selector_panel.get_global_rect()
		var is_over_ui = panel_rect.has_point(mouse_pos)
		
		if is_over_ui and chunk_grid.build_mode_active:
			chunk_grid.set_build_mode_active(false)
		elif not is_over_ui and not chunk_grid.build_mode_active:
			chunk_grid.set_build_mode_active(true)
			
	if is_plant_mode and plant_selector_panel and plant_selector_panel.visible:
		var mouse_pos = get_global_mouse_position()
		var panel_rect = plant_selector_panel.get_global_rect()
		var is_over_ui = panel_rect.has_point(mouse_pos)
		if is_over_ui and chunk_grid.plant_mode_active: chunk_grid.set_plant_mode_active(false)
		elif not is_over_ui and not chunk_grid.plant_mode_active: chunk_grid.set_plant_mode_active(true)

	if selected_ant and is_instance_valid(selected_ant) and ant_inspector_panel.visible:
		update_ant_inspector()
	if is_inventory_open:
		update_global_inventory()

func apply_font(node):
	if not node: return
	if main_font: node.add_theme_font_override("font", main_font)

# --- ANT INSPECTOR ---
func create_ant_inspector_panel():
	var panel = Panel.new()
	panel.name = "AntInspector"
	panel.position = Vector2(50, 400)
	panel.size = Vector2(260, 360) # Taller for extra controls
	panel.visible = false
	add_child(panel)
	self.ant_inspector_panel = panel
	
	var name_lbl = Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.text = "Felix"
	name_lbl.position = Vector2(10, 10)
	if kiwi_font:
		name_lbl.add_theme_font_override("font", kiwi_font)
		name_lbl.add_theme_font_size_override("font_size", 28)
	else: apply_font(name_lbl)
	panel.add_child(name_lbl)
	
	var status_lbl = Label.new()
	status_lbl.name = "StatusLabel"
	status_lbl.text = "State: Wandering"
	status_lbl.position = Vector2(10, 40)
	apply_font(status_lbl)
	panel.add_child(status_lbl)
	
	var hunger_lbl = Label.new()
	hunger_lbl.text = "Hunger:"
	hunger_lbl.position = Vector2(10, 70)
	apply_font(hunger_lbl)
	panel.add_child(hunger_lbl)
	
	var hunger_bar = ProgressBar.new()
	hunger_bar.name = "HungerBar"
	hunger_bar.position = Vector2(80, 73)
	hunger_bar.size = Vector2(160, 15)
	hunger_bar.show_percentage = false
	panel.add_child(hunger_bar)
	
	var sleep_lbl = Label.new()
	sleep_lbl.text = "Sleep:"
	sleep_lbl.position = Vector2(10, 95)
	apply_font(sleep_lbl)
	panel.add_child(sleep_lbl)
	
	var sleep_bar = ProgressBar.new()
	sleep_bar.name = "SleepBar"
	sleep_bar.position = Vector2(80, 98)
	sleep_bar.size = Vector2(160, 15)
	sleep_bar.show_percentage = false
	var bg = StyleBoxFlat.new(); bg.bg_color = Color(0,0,0,0.5)
	var fg = StyleBoxFlat.new(); fg.bg_color = Color(0.2, 0.2, 0.8, 1.0)
	sleep_bar.add_theme_stylebox_override("background", bg)
	sleep_bar.add_theme_stylebox_override("fill", fg)
	panel.add_child(sleep_bar)
	
	# JOB TOGGLE
	var btn_job = Button.new()
	btn_job.name = "JobButton"
	btn_job.text = "Role: Construction"
	btn_job.position = Vector2(16, 125)
	btn_job.size = Vector2(228, 30)
	btn_job.focus_mode = Control.FOCUS_NONE
	btn_job.connect("pressed", Callable(self, "_on_toggle_role"))
	apply_font(btn_job)
	panel.add_child(btn_job)
	
	# --- MANUAL FEEDING ---
	var feed_lbl = Label.new()
	feed_lbl.text = "Manual Feed:"
	feed_lbl.position = Vector2(16, 165)
	apply_font(feed_lbl)
	panel.add_child(feed_lbl)
	
	var feed_box = HBoxContainer.new()
	feed_box.position = Vector2(16, 185)
	feed_box.size = Vector2(228, 30)
	panel.add_child(feed_box)
	
	var foods = ["basic", "common", "rare", "legendary"]
	var colors = [Color.WHITE, Color.GREEN, Color.CYAN, Color.ORANGE]
	for i in range(foods.size()):
		var b = Button.new()
		b.text = foods[i].substr(0,1).to_upper()
		b.modulate = colors[i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "Feed " + foods[i].capitalize()
		b.connect("pressed", Callable(self, "_on_manual_feed").bind(foods[i]))
		feed_box.add_child(b)
		
	# --- BUSINESS CONTROL ---
	var biz_lbl = Label.new()
	biz_lbl.name = "BizLabel"
	biz_lbl.text = "Target Seed:"
	biz_lbl.position = Vector2(16, 230)
	apply_font(biz_lbl)
	panel.add_child(biz_lbl)
	
	var btn_biz = Button.new()
	btn_biz.name = "BizButton"
	btn_biz.text = "Basic"
	btn_biz.position = Vector2(16, 250)
	btn_biz.size = Vector2(228, 30)
	btn_biz.connect("pressed", Callable(self, "_on_cycle_biz_seed"))
	apply_font(btn_biz)
	panel.add_child(btn_biz)
	
	var btn_close = Button.new()
	btn_close.text = "X"
	btn_close.position = Vector2(235, 5)
	btn_close.size = Vector2(20, 20)
	btn_close.connect("pressed", Callable(self, "hide_ant_inspector"))
	apply_font(btn_close)
	panel.add_child(btn_close)

func _on_manual_feed(type):
	if not selected_ant: return
	if game_manager.food_inventory[type] > 0:
		game_manager.food_inventory[type] -= 1
		game_manager.emit_signal("food_changed", game_manager.get_total_food())
		selected_ant.feed(100)
		selected_ant.show_popup_text("Yum!")
		update_ant_inspector()
	else:
		_on_system_message("No " + type + " food!", Color.RED)

func _on_cycle_biz_seed():
	if not selected_ant: return
	var seeds = ["basic", "common", "rare", "legendary"]
	var cur = selected_ant.business_target_seed
	var idx = seeds.find(cur)
	var next = seeds[(idx + 1) % seeds.size()]
	selected_ant.business_target_seed = next
	update_ant_inspector()

func _on_toggle_role():
	if not selected_ant: return
	if game_manager.colony_level < 5:
		game_manager.send_message("Automation unlocks at Level 5!", Color.RED)
		return

	var roles = ["construction", "farmer", "business"]
	var current_idx = roles.find(selected_ant.job_role)
	var next_idx = (current_idx + 1) % roles.size()
	selected_ant.job_role = roles[next_idx]
	
	if selected_ant.job_role != "farmer":
		selected_ant.assigned_room_id = -1
	
	update_ant_inspector()

func update_ant_inspector():
	if not selected_ant: return
	var name_lbl = ant_inspector_panel.get_node("NameLabel")
	var status_lbl = ant_inspector_panel.get_node("StatusLabel")
	var hunger_bar = ant_inspector_panel.get_node("HungerBar")
	var sleep_bar = ant_inspector_panel.get_node("SleepBar")
	var btn_job = ant_inspector_panel.get_node("JobButton")
	
	var biz_lbl = ant_inspector_panel.get_node("BizLabel")
	var btn_biz = ant_inspector_panel.get_node("BizButton")
	
	name_lbl.text = selected_ant.ant_name
	status_lbl.text = "State: " + selected_ant.current_task.capitalize()
	
	hunger_bar.value = selected_ant.hunger
	if selected_ant.hunger < 35: hunger_bar.modulate = Color(1, 0.3, 0.3)
	elif selected_ant.hunger < 70: hunger_bar.modulate = Color(1, 1, 0.3)
	else: hunger_bar.modulate = Color(0.3, 1, 0.3)
	
	sleep_bar.value = selected_ant.sleep

	btn_job.text = "Role: " + selected_ant.job_role.capitalize()
	if game_manager.colony_level < 5:
		btn_job.text += " (Lvl 5)"
		btn_job.modulate = Color(0.5, 0.5, 0.5)
	else:
		btn_job.modulate = Color(1, 1, 1)

	# Show Business Controls
	if selected_ant.job_role == "business":
		biz_lbl.visible = true
		btn_biz.visible = true
		btn_biz.text = selected_ant.business_target_seed.capitalize()
	else:
		biz_lbl.visible = false
		btn_biz.visible = false

func show_ant_inspector(ant):
	if is_any_window_open(): close_all_windows() # Auto-close others
	
	if selected_ant and is_instance_valid(selected_ant): selected_ant.set_frozen(false)
	if selected_ant != ant:
		if audio_manager: audio_manager.play_sfx("focus")
	selected_ant = ant
	selected_ant.set_frozen(true)
	if camera: camera.start_focus(selected_ant.position)
	ant_inspector_panel.visible = true
	update_ant_inspector()

func hide_ant_inspector():
	if selected_ant and is_instance_valid(selected_ant): selected_ant.set_frozen(false)
	selected_ant = null
	ant_inspector_panel.visible = false
	if camera: camera.stop_focus()

# --- MOUND HUB ---
func create_mound_hub_panel():
	var panel = Panel.new()
	panel.name = "MoundHub"
	panel.position = Vector2(184, 300)
	panel.size = Vector2(400, 400) 
	panel.visible = false
	add_child(panel)
	self.mound_hub_panel = panel
	
	var title = Label.new()
	title.text = "THE MOUND"
	title.position = Vector2(0, 10)
	title.size = Vector2(400, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apply_font(title)
	panel.add_child(title)
	
	# Recruit Section
	var btn_recruit = Button.new()
	btn_recruit.name = "RecruitButton"
	btn_recruit.text = "RECRUIT ANT"
	btn_recruit.position = Vector2(100, 60)
	btn_recruit.size = Vector2(200, 50)
	btn_recruit.connect("pressed", Callable(self, "_on_recruit_click"))
	apply_font(btn_recruit)
	panel.add_child(btn_recruit)
	
	recruit_cost_label = Label.new()
	recruit_cost_label.text = "Cost: $150"
	recruit_cost_label.position = Vector2(0, 115)
	recruit_cost_label.size = Vector2(400, 30)
	recruit_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apply_font(recruit_cost_label)
	panel.add_child(recruit_cost_label)
	
	panel.add_child(HSeparator.new())
	
	# Seed Shop Section
	var shop_lbl = Label.new()
	shop_lbl.text = "BUY BASIC SEEDS ($10)"
	shop_lbl.position = Vector2(0, 160)
	shop_lbl.size = Vector2(400, 30)
	shop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apply_font(shop_lbl)
	panel.add_child(shop_lbl)
	
	var btn_buy_1 = Button.new()
	btn_buy_1.text = "Buy 1"
	btn_buy_1.position = Vector2(50, 200)
	btn_buy_1.size = Vector2(80, 40)
	btn_buy_1.connect("pressed", Callable(self, "_on_buy_basic").bind(1))
	apply_font(btn_buy_1)
	panel.add_child(btn_buy_1)
	
	var btn_buy_10 = Button.new()
	btn_buy_10.text = "Buy 10"
	btn_buy_10.position = Vector2(160, 200)
	btn_buy_10.size = Vector2(80, 40)
	btn_buy_10.connect("pressed", Callable(self, "_on_buy_basic").bind(10))
	apply_font(btn_buy_10)
	panel.add_child(btn_buy_10)
	
	var btn_close = Button.new()
	btn_close.text = "Close"
	btn_close.position = Vector2(150, 350)
	btn_close.size = Vector2(100, 30)
	btn_close.connect("pressed", Callable(self, "_on_mound_close"))
	apply_font(btn_close)
	panel.add_child(btn_close)

func _on_buy_basic(amount):
	var cost = 10 * amount
	if game_manager.money >= cost:
		game_manager.spend_money(cost)
		game_manager.seeds_owned["basic"] += amount
		game_manager.emit_signal("seeds_changed", "basic", game_manager.seeds_owned["basic"])
		_on_system_message("Bought " + str(amount) + " Basic Seeds", Color.GREEN)
	else:
		_on_system_message("Not enough money!", Color.RED)

func update_mound_ui_state():
	if not mound_hub_panel: return
	var btn = mound_hub_panel.get_node("RecruitButton")
	var unlock_level = game_manager.recruit_unlock_level
	var current_level = game_manager.colony_level
	if current_level < unlock_level:
		btn.disabled = true
		btn.text = "LOCKED (Lvl " + str(unlock_level) + ")"
		recruit_cost_label.text = "Requires Level " + str(unlock_level)
	else:
		btn.disabled = false
		btn.text = "RECRUIT ANT"
		recruit_cost_label.text = "Cost: $" + str(game_manager.get_next_ant_cost())

func _on_recruit_click():
	if game_manager.recruit_new_ant(): update_mound_ui_state()
func _on_mound_close(): mound_hub_panel.visible = false

# --- FARM MANAGEMENT PANEL ---
func create_farm_management_panel():
	var panel = Panel.new()
	panel.name = "FarmManager"
	panel.position = Vector2(100, 150)
	panel.size = Vector2(568, 600)
	panel.visible = false
	add_child(panel)
	self.farm_management_panel = panel
	
	var title = Label.new()
	title.text = "FARM STATION"
	title.position = Vector2(0, 10)
	title.size = Vector2(568, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apply_font(title)
	panel.add_child(title)
	
	var seed_lbl = Label.new()
	seed_lbl.text = "Grows: Basic"
	seed_lbl.name = "SeedLabel"
	seed_lbl.position = Vector2(20, 60)
	apply_font(seed_lbl)
	panel.add_child(seed_lbl)
	
	var btn_basic = Button.new()
	btn_basic.text = "Basic"
	btn_basic.position = Vector2(150, 55)
	btn_basic.size = Vector2(80, 30)
	btn_basic.connect("pressed", Callable(self, "_set_farm_seed").bind("basic"))
	panel.add_child(btn_basic)
	
	var btn_comm = Button.new()
	btn_comm.text = "Common"
	btn_comm.position = Vector2(240, 55)
	btn_comm.size = Vector2(80, 30)
	btn_comm.connect("pressed", Callable(self, "_set_farm_seed").bind("common"))
	panel.add_child(btn_comm)
	
	var btn_rare = Button.new()
	btn_rare.text = "Rare"
	btn_rare.position = Vector2(330, 55)
	btn_rare.size = Vector2(80, 30)
	btn_rare.connect("pressed", Callable(self, "_set_farm_seed").bind("rare"))
	panel.add_child(btn_rare)

	var current_lbl = Label.new()
	current_lbl.name = "CurrentFarmerLabel"
	current_lbl.text = "Current Farmer: None"
	current_lbl.position = Vector2(0, 100)
	current_lbl.size = Vector2(568, 30)
	current_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	current_lbl.modulate = Color.YELLOW
	apply_font(current_lbl)
	panel.add_child(current_lbl)
	
	var scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.position = Vector2(20, 140)
	scroll.size = Vector2(528, 400)
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "FarmerList"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	var btn_close = Button.new()
	btn_close.text = "CLOSE"
	btn_close.position = Vector2(234, 550)
	btn_close.size = Vector2(100, 40)
	btn_close.connect("pressed", Callable(self, "_on_close_farm_manager"))
	apply_font(btn_close)
	panel.add_child(btn_close)

func open_farm_management(chunk_pos):
	# Enforce single window policy
	if is_any_window_open(): return

	if not chunk_grid.dug_chunks.has(chunk_pos): return
	var s_id = chunk_grid.dug_chunks[chunk_pos].get("structure_id", -1)
	if s_id == -1: return
	
	pending_farm_chunk = chunk_pos
	pending_farm_id = s_id
	
	close_all_windows() # Safety clear
	farm_management_panel.visible = true
	refresh_farm_manager_ui()

func refresh_farm_manager_ui():
	var s_id = pending_farm_id
	if s_id == -1: return

	var lbl = farm_management_panel.get_node("CurrentFarmerLabel")
	var seed_lbl = farm_management_panel.get_node("SeedLabel")
	var vbox = farm_management_panel.get_node("ScrollContainer/FarmerList")
	for c in vbox.get_children(): c.queue_free()
	
	var current_seed = game_manager.get_room_target_seed(s_id)
	seed_lbl.text = "Grows: " + current_seed.capitalize()
	
	var current_owner = null
	for ant in game_manager.ants:
		if ant.assigned_room_id == s_id:
			current_owner = ant
			break
			
	if current_owner:
		lbl.text = "Current Farmer: " + current_owner.ant_name
		lbl.modulate = Color.GREEN
	else:
		lbl.text = "Current Farmer: None"
		lbl.modulate = Color.YELLOW
		
	for ant in game_manager.ants:
		if ant.job_role == "farmer":
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(0, 50)
			
			var txt = ant.ant_name
			if ant == current_owner:
				txt += " (Assigned Here)"
				btn.disabled = true
				btn.modulate = Color.GREEN
			elif ant.assigned_room_id != -1:
				txt += " (Assigned Elsewhere)"
				btn.modulate = Color.ORANGE
			else:
				txt += " (Available)"
				btn.modulate = Color.WHITE
			
			btn.text = txt
			btn.connect("pressed", Callable(self, "_on_assign_farmer").bind(ant, s_id))
			apply_font(btn)
			vbox.add_child(btn)

func _set_farm_seed(type):
	if pending_farm_id != -1:
		game_manager.set_room_target_seed(pending_farm_id, type)
		refresh_farm_manager_ui()

func _on_assign_farmer(ant, s_id):
	# Unassign previous owner
	for a in game_manager.ants:
		if a.assigned_room_id == s_id:
			a.assigned_room_id = -1
			
	# Assign new
	ant.assigned_room_id = s_id
	game_manager.send_message(ant.ant_name + " assigned to farm.", Color.GREEN)
	
	refresh_farm_manager_ui()

func _on_close_farm_manager():
	farm_management_panel.visible = false

# --- INPUT HANDLING ---
func _input(event):
	if not game_started:
		if input_allowed and event is InputEventMouseButton and event.pressed:
			game_started = true
			if start_label: start_label.queue_free()
			if btn_inventory: btn_inventory.visible = true
			if btn_build: btn_build.visible = true
			if btn_plant: btn_plant.visible = true
			if btn_settings: btn_settings.visible = true
			if xp_label: xp_label.visible = true
			if clock_label: clock_label.visible = true
			var money = get_node_or_null("MoneyLabel")
			if money: money.visible = true
			if audio_manager: audio_manager.start_audio_systems()
			if camera:
				camera.stop_focus()
				var tween = create_tween()
				tween.set_parallel(true)
				tween.set_ease(Tween.EASE_OUT)
				tween.set_trans(Tween.TRANS_CUBIC)
				tween.tween_property(camera, "zoom", Vector2(1.0, 1.0), 2.5)
				tween.tween_property(camera, "position", Vector2(384, 512), 2.5)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var char_str = OS.get_keycode_string(event.keycode)
		if char_str.length() == 1:
			cheat_buffer += char_str.to_upper()
			if cheat_buffer.length() > 10:
				cheat_buffer = cheat_buffer.substr(cheat_buffer.length() - 10)
			
			if cheat_buffer.ends_with("FELIX"):
				cheat_buffer = ""
				var needed = game_manager.xp_to_next_level - game_manager.current_xp
				game_manager.gain_xp(needed)
				return

			if cheat_buffer.ends_with("SDIYBT"):
				cheat_buffer = ""
				game_manager.add_money(500)
				game_manager.send_message("CHEAT: +$500", Color.GOLD)
				return
				
			if cheat_buffer.ends_with("ASHASHASH"):
				cheat_buffer = ""
				chunk_grid.force_spawn_ash()
				game_manager.send_message("MEOW!", Color.MAGENTA)
				return

	if is_build_mode and event is InputEventKey and event.pressed and event.keycode == KEY_R:
		tunnel_rotation = (tunnel_rotation + 90) % 360
		chunk_grid.set_tunnel_rotation(tunnel_rotation)
	
	# Priority Click Handling
	if not is_build_mode and not is_plant_mode and not is_remove_mode and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_inventory_open and event.position.y < 700 and not colony_list_panel.visible: return
		
		# BLOCKER: If a window is open, ignore world clicks
		if is_any_window_open():
			return

		var mouse_pos = get_global_mouse_position()
		var cam = get_viewport().get_camera_2d()
		var world_pos = mouse_pos
		if cam: world_pos = cam.get_global_mouse_position()

		# 1. CHECK ANTS FIRST
		var clicked_ant = get_ant_at_position(event.position)
		if clicked_ant: 
			show_ant_inspector(clicked_ant)
			return

		# 2. Mound Interaction
		if world_pos.distance_to(Vector2(384, 32)) < 80:
			mound_hub_panel.visible = true
			update_mound_ui_state()
			return
			
		# 3. Dining Halls
		var hall_id = game_manager.get_nearest_room_id("dining_hall", world_pos)
		if hall_id != -1:
			var r_pos = game_manager.get_nearest_room("dining_hall", world_pos)
			var r_world = chunk_grid.chunk_to_world_position(r_pos)
			if world_pos.distance_to(r_world) < 64:
				open_dining_hall_menu(hall_id)
				return
		
		# 4. Farms
		var c_pos = chunk_grid.get_chunk_at_mouse()
		if chunk_grid.dug_chunks.has(c_pos):
			var data = chunk_grid.dug_chunks[c_pos]
			if data["room_type"] == "farming_room":
				open_farm_management(c_pos)
				return

		# 5. Akira
		if get_akira_at_position(event.position):
			if chunk_grid.is_connected_to_surface(game_manager.akira_chunk_pos):
				open_akira_shop()
			else:
				_on_system_message("You see movement inside, but no path connects to it.", Color.MAGENTA)
			return
			
	# Build/Plant/Remove Logic
	if is_plant_mode and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.y > 750 and event.position.x > 450: return
		var chunk_pos = chunk_grid.get_chunk_at_mouse()
		var fungus = chunk_grid.get_fungus_at(chunk_pos.x, chunk_pos.y)
		if fungus and fungus.is_ready_to_harvest:
			game_manager.request_harvest_task(chunk_pos)
			return
		if chunk_grid.can_plant_fungus(chunk_pos.x, chunk_pos.y):
			if game_manager.has_seed(current_seed_type):
				chunk_grid.plant_fungus(chunk_pos.x, chunk_pos.y, current_seed_type)
				game_manager.use_seed(current_seed_type)
				update_plant_selector_ui() 
			else:
				_on_system_message("No " + current_seed_type + " seeds!", Color.ORANGE)

# --- DINING HALL UI ---
func create_dining_hall_panel():
	var panel = Panel.new()
	panel.name = "DiningHallPanel"
	panel.position = Vector2(50, 200)
	panel.size = Vector2(668, 400) 
	panel.visible = false
	add_child(panel)
	dining_hall_panel = panel
	
	var title = Label.new()
	title.text = "DINING HALL STORAGE (BASIC ONLY)"
	title.position = Vector2(0, 10)
	title.size = Vector2(668, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apply_font(title)
	panel.add_child(title)
	
	var grid = GridContainer.new()
	grid.name = "FoodGrid"
	grid.position = Vector2(34, 60)
	grid.size = Vector2(600, 200)
	grid.columns = 2
	panel.add_child(grid)
	
	var btn_close = Button.new()
	btn_close.text = "CLOSE"
	btn_close.position = Vector2(284, 320)
	btn_close.size = Vector2(100, 40)
	btn_close.connect("pressed", Callable(self, "_close_dining_hall"))
	apply_font(btn_close)
	panel.add_child(btn_close)

var current_hall_id = -1

func open_dining_hall_menu(structure_id):
	if is_any_window_open(): return # Single Window Policy
	close_all_windows()
	
	current_hall_id = structure_id
	dining_hall_panel.visible = true
	refresh_dining_hall_ui()

func _close_dining_hall():
	dining_hall_panel.visible = false
	current_hall_id = -1

func refresh_dining_hall_ui():
	if current_hall_id == -1: return
	var grid = dining_hall_panel.get_node("FoodGrid")
	for child in grid.get_children(): child.queue_free()
	
	var hall_contents = game_manager.get_dining_hall_contents(current_hall_id)
	var global_contents = game_manager.food_inventory
	
	# ONLY SHOW BASIC
	var type = "basic"
	var info_box = VBoxContainer.new()
	var lbl = Label.new()
	lbl.text = "Basic Food"
	apply_font(lbl)
	info_box.add_child(lbl)
	
	var lbl_global = Label.new()
	lbl_global.text = "Inventory: " + str(global_contents[type])
	lbl_global.modulate = Color(0.7, 0.7, 0.7)
	apply_font(lbl_global)
	info_box.add_child(lbl_global)
	
	var lbl_hall = Label.new()
	lbl_hall.text = "In Hall: " + str(hall_contents[type])
	lbl_hall.modulate = Color.GREEN
	apply_font(lbl_hall)
	info_box.add_child(lbl_hall)
	
	grid.add_child(info_box)
	
	var btn_box = VBoxContainer.new()
	
	var row1 = HBoxContainer.new()
	var btn_add = Button.new()
	btn_add.text = "Deposit 1"
	btn_add.disabled = (global_contents[type] < 1)
	btn_add.connect("pressed", Callable(self, "_on_dining_move").bind(type, 1))
	apply_font(btn_add)
	row1.add_child(btn_add)
	
	var btn_add_10 = Button.new()
	btn_add_10.text = "Deposit 10"
	btn_add_10.disabled = (global_contents[type] < 10)
	btn_add_10.connect("pressed", Callable(self, "_on_dining_move").bind(type, 10))
	apply_font(btn_add_10)
	row1.add_child(btn_add_10)
	btn_box.add_child(row1)
	
	var row2 = HBoxContainer.new()
	var btn_sub = Button.new()
	btn_sub.text = "Withdraw 1"
	btn_sub.modulate = Color(1, 0.5, 0.5)
	btn_sub.connect("pressed", Callable(self, "_on_dining_withdraw").bind(type, 1))
	apply_font(btn_sub)
	row2.add_child(btn_sub)
	
	var btn_sub_10 = Button.new()
	btn_sub_10.text = "Withdraw 10"
	btn_sub_10.modulate = Color(1, 0.5, 0.5)
	btn_sub_10.connect("pressed", Callable(self, "_on_dining_withdraw").bind(type, 10))
	apply_font(btn_sub_10)
	row2.add_child(btn_sub_10)
	btn_box.add_child(row2)
	
	grid.add_child(btn_box)

func _on_dining_move(type, amount):
	if current_hall_id != -1:
		game_manager.add_food_to_dining_hall(current_hall_id, type, amount)
		refresh_dining_hall_ui() 

func _on_dining_withdraw(type, amount):
	if current_hall_id != -1:
		game_manager.withdraw_food_from_dining_hall(current_hall_id, type, amount)
		refresh_dining_hall_ui()

# --- TASK ASSIGNMENT UI ---
func create_task_assignment_panel():
	var panel = Panel.new()
	panel.name = "TaskAssignmentPanel"
	panel.position = Vector2(100, 150)
	panel.size = Vector2(568, 600)
	panel.visible = false
	add_child(panel)
	task_assignment_panel = panel
	
	var title = Label.new()
	title.text = "SELECT ANT FOR JOB"
	title.position = Vector2(0, 10)
	title.size = Vector2(568, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apply_font(title)
	panel.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer" 
	scroll.position = Vector2(20, 60)
	scroll.size = Vector2(528, 480)
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "AntList"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "CANCEL JOB"
	btn_cancel.position = Vector2(200, 550)
	btn_cancel.size = Vector2(168, 40)
	btn_cancel.modulate = Color.RED
	btn_cancel.connect("pressed", Callable(self, "_on_cancel_task_assignment"))
	apply_font(btn_cancel)
	panel.add_child(btn_cancel)

func _on_task_assignment_needed(type, target, data):
	pending_task_type = type
	pending_task_target = target
	pending_task_data = data
	
	chunk_grid.lock_preview = true
	if tunnel_selector_panel: tunnel_selector_panel.visible = false
	
	refresh_task_ant_list()
	task_assignment_panel.visible = true

func refresh_task_ant_list():
	var vbox = task_assignment_panel.get_node("ScrollContainer/AntList")
	for child in vbox.get_children(): child.queue_free()
	
	for ant in game_manager.ants:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 60)
		btn.focus_mode = Control.FOCUS_NONE
		
		var status = ant.current_task.capitalize()
		var is_sleeping = (ant.current_task == "sleeping")
		var txt = ant.ant_name + " [" + ant.job_role.capitalize() + "] | " + status
		btn.text = txt
		
		var can_assign = true
		if is_sleeping:
			btn.text += " (SLEEPING)"
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
			can_assign = false
		elif pending_task_type == "dig" and ant.job_role != "construction":
			btn.text += " (WRONG CLASS)"
			btn.disabled = true
			btn.modulate = Color(0.7, 0.7, 0.7)
			can_assign = false
		
		if can_assign:
			btn.connect("pressed", Callable(self, "_on_ant_selected_for_task").bind(ant))
			btn.modulate = Color(1, 1, 1)
			
		apply_font(btn)
		vbox.add_child(btn)

func _on_ant_selected_for_task(ant):
	task_assignment_panel.visible = false
	chunk_grid.lock_preview = false 
	
	if pending_task_type == "dig":
		pending_task_data["is_manual"] = true
		chunk_grid.confirm_dig_task(pending_task_target.x, pending_task_target.y, pending_task_data, ant)
	
	elif pending_task_type == "harvest":
		game_manager.assign_specific_task(ant, "harvest", pending_task_target, pending_task_data)

func _on_cancel_task_assignment():
	task_assignment_panel.visible = false
	chunk_grid.lock_preview = false
	if is_build_mode and tunnel_selector_panel: tunnel_selector_panel.visible = true

# --- OTHER PANELS ---
func create_settings_panel():
	var panel = Panel.new()
	panel.name = "SettingsPanel"
	panel.position = Vector2(234, 300)
	panel.size = Vector2(300, 390)
	panel.visible = false
	add_child(panel)
	self.settings_panel = panel
	
	var title = Label.new()
	title.text = "SETTINGS"
	title.position = Vector2(0, 10)
	title.size = Vector2(300, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apply_font(title)
	panel.add_child(title)
	
	var vbox = VBoxContainer.new()
	vbox.position = Vector2(25, 60)
	vbox.size = Vector2(250, 300)
	panel.add_child(vbox)
	
	var btn_save = Button.new()
	btn_save.text = "Save Game"
	btn_save.connect("pressed", Callable(self, "_on_save_game"))
	apply_font(btn_save)
	vbox.add_child(btn_save)
	
	vbox.add_child(HSeparator.new())
	
	var btn_music = CheckButton.new()
	btn_music.text = "Music"
	btn_music.button_pressed = true
	btn_music.connect("toggled", Callable(self, "_on_music_toggled"))
	apply_font(btn_music)
	vbox.add_child(btn_music)
	
	vbox.add_child(HSeparator.new())
	
	var lbl_time = Label.new()
	lbl_time.text = "Time Mode:"
	apply_font(lbl_time)
	vbox.add_child(lbl_time)
	
	var btn_real = Button.new()
	btn_real.text = "Real Time (Auto)"
	btn_real.connect("pressed", Callable(self, "_set_time_mode").bind("real_time"))
	apply_font(btn_real)
	vbox.add_child(btn_real)
	
	var btn_day = Button.new()
	btn_day.text = "Always Day"
	btn_day.connect("pressed", Callable(self, "_set_time_mode").bind("always_day"))
	apply_font(btn_day)
	vbox.add_child(btn_day)
	
	var btn_night = Button.new()
	btn_night.text = "Always Night"
	btn_night.connect("pressed", Callable(self, "_set_time_mode").bind("always_night"))
	apply_font(btn_night)
	vbox.add_child(btn_night)
	
	vbox.add_child(HSeparator.new())
	
	var btn_del = Button.new()
	btn_del.text = "RESET SAVE"
	btn_del.modulate = Color(1, 0.4, 0.4)
	btn_del.connect("pressed", Callable(self, "_on_delete_save_request"))
	apply_font(btn_del)
	vbox.add_child(btn_del)
	
	var btn_close = Button.new()
	btn_close.text = "X"
	btn_close.position = Vector2(275, 5)
	btn_close.size = Vector2(20, 20)
	btn_close.connect("pressed", Callable(self, "_on_settings_toggle"))
	apply_font(btn_close)
	panel.add_child(btn_close)

func create_delete_confirm_panel():
	var panel = Panel.new()
	panel.name = "DeleteConfirm"
	panel.position = Vector2(200, 400)
	panel.size = Vector2(368, 150)
	panel.visible = false
	add_child(panel)
	delete_confirm_panel = panel
	
	var lbl = Label.new()
	lbl.text = "Are you sure you want to\nDELETE and RESET everything?"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(0, 20)
	lbl.size = Vector2(368, 50)
	apply_font(lbl)
	panel.add_child(lbl)
	
	var btn_yes = Button.new()
	btn_yes.text = "YES, RESET"
	btn_yes.modulate = Color.RED
	btn_yes.position = Vector2(40, 80)
	btn_yes.size = Vector2(120, 40)
	btn_yes.connect("pressed", Callable(self, "_on_confirm_delete"))
	apply_font(btn_yes)
	panel.add_child(btn_yes)
	
	var btn_no = Button.new()
	btn_no.text = "CANCEL"
	btn_no.position = Vector2(208, 80)
	btn_no.size = Vector2(120, 40)
	btn_no.connect("pressed", Callable(self, "_on_cancel_delete"))
	apply_font(btn_no)
	panel.add_child(btn_no)

func _on_delete_save_request():
	delete_confirm_panel.visible = true
	settings_panel.visible = false

func _on_cancel_delete():
	delete_confirm_panel.visible = false
	settings_panel.visible = true

func _on_confirm_delete():
	var path = "user://felix_save.json"
	if FileAccess.file_exists(path):
		var dir = DirAccess.open("user://")
		if dir:
			dir.remove(path)
			print("Save Deleted.")
	get_tree().reload_current_scene()

func show_saving_screen():
	var save_layer = CanvasLayer.new()
	save_layer.layer = 100
	save_layer.name = "SaveLayer"
	add_child(save_layer)
	
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.BLACK
	bg.modulate.a = 0.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	save_layer.add_child(bg)
	
	var tween_in = create_tween()
	tween_in.tween_property(bg, "modulate:a", 1.0, 1.0)
	
	var lbl = Label.new()
	lbl.text = "SAVING..."
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.position.y = -100
	lbl.modulate.a = 0.0
	if kiwi_font:
		lbl.add_theme_font_override("font", kiwi_font)
		lbl.add_theme_font_size_override("font_size", 48)
	save_layer.add_child(lbl)
	
	var tween_txt = create_tween()
	tween_txt.tween_property(lbl, "modulate:a", 1.0, 1.0)
	
	var display_sprite = null
	if game_manager.ant_scene_resource:
		var dummy_ant = game_manager.ant_scene_resource.instantiate()
		var ant_sprite = dummy_ant.get_node("AnimatedSprite2D")
		display_sprite = AnimatedSprite2D.new()
		display_sprite.sprite_frames = ant_sprite.sprite_frames
		display_sprite.scale = Vector2(0.4, 0.4)
		display_sprite.position = Vector2(get_viewport_rect().size.x / 2, get_viewport_rect().size.y / 2)
		display_sprite.play("happy_forward")
		display_sprite.modulate.a = 0.0
		save_layer.add_child(display_sprite)
		dummy_ant.queue_free()
		
		var tween_spr = create_tween()
		tween_spr.tween_property(display_sprite, "modulate:a", 1.0, 1.0)
		
		save_tween = create_tween()
		save_tween.set_loops()
		save_tween.tween_callback(func(): display_sprite.play("happy_side_left"))
		save_tween.tween_interval(0.2)
		save_tween.tween_callback(func(): display_sprite.play("neutral_side_right"))
		save_tween.tween_interval(0.2)
		save_tween.tween_callback(func(): display_sprite.play("unhappy_side_left"))
		save_tween.tween_interval(0.2)
		save_tween.tween_callback(func(): display_sprite.play("happy_side_right"))
		save_tween.tween_interval(0.2)

	if audio_manager: audio_manager.play_loading_music()
	await get_tree().create_timer(1.0).timeout
	
	if settings_panel: settings_panel.visible = false
	
	if game_manager.ants.size() > 0:
		intro_ant = game_manager.ants.pick_random()
		if camera:
			camera.position = intro_ant.position
			camera.zoom = Vector2(10.0, 10.0)
			camera.start_focus(intro_ant.position)
	
	await get_tree().create_timer(5.0).timeout
	game_manager.save_game()
	if audio_manager: audio_manager.fade_out_music(1.5)
	
	return_to_start_screen()
	var tween_out = create_tween()
	tween_out.set_parallel(true)
	tween_out.tween_property(bg, "modulate:a", 0.0, 1.5)
	tween_out.tween_property(lbl, "modulate:a", 0.0, 1.5)
	if display_sprite:
		tween_out.tween_property(display_sprite, "modulate:a", 0.0, 1.5)
		
	await tween_out.finished
	if save_tween and save_tween.is_valid(): save_tween.kill()
	save_layer.queue_free()
	is_settings_open = false
	settings_panel.visible = false
	_update_states()
	if audio_manager: audio_manager.resume_game_music()

func return_to_start_screen():
	if btn_inventory: btn_inventory.visible = false
	if btn_build: btn_build.visible = false
	if btn_plant: btn_plant.visible = false
	if btn_settings: btn_settings.visible = false
	if xp_label: xp_label.visible = false
	if clock_label: clock_label.visible = false
	var money = get_node_or_null("MoneyLabel")
	if money: money.visible = false
	game_started = false
	create_start_screen()

func _on_save_game(): show_saving_screen()
func _on_load_game():
	game_manager.load_game()
	_on_settings_toggle()

func _on_music_toggled(pressed):
	if audio_manager: audio_manager.toggle_music(pressed)

func _set_time_mode(mode): game_manager.set_time_mode(mode)

func _on_settings_toggle():
	if is_settings_open:
		close_all_windows()
		is_settings_open = false
	else:
		close_all_windows()
		is_settings_open = true
		settings_panel.visible = true
	_update_states()

func create_colony_list_panel():
	var panel = Panel.new()
	panel.name = "ColonyList"
	panel.position = Vector2(50, 100)
	panel.size = Vector2(668, 700)
	panel.visible = false
	add_child(panel)
	self.colony_list_panel = panel
	
	var title = Label.new()
	title.text = "COLONY ROSTER"
	title.position = Vector2(0, 20)
	title.size = Vector2(668, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	apply_font(title)
	panel.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.position = Vector2(34, 80)
	scroll.size = Vector2(600, 520)
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "RosterContainer"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	var btn_close = Button.new()
	btn_close.text = "CLOSE"
	btn_close.position = Vector2(284, 630)
	btn_close.size = Vector2(100, 40)
	btn_close.connect("pressed", Callable(self, "_on_close_colony_list"))
	apply_font(btn_close)
	panel.add_child(btn_close)

func update_colony_list():
	var vbox = colony_list_panel.get_node("ScrollContainer/RosterContainer")
	for child in vbox.get_children(): child.queue_free()
	
	for ant in game_manager.ants:
		var hbox = HBoxContainer.new()
		
		var lbl_name = Label.new()
		lbl_name.text = ant.ant_name
		lbl_name.custom_minimum_size = Vector2(150, 30)
		apply_font(lbl_name)
		hbox.add_child(lbl_name)
		
		var lbl_role = Label.new()
		lbl_role.text = "[" + ant.job_role.capitalize() + "]"
		lbl_role.custom_minimum_size = Vector2(150, 30)
		lbl_role.modulate = Color(0.7, 0.9, 1.0)
		apply_font(lbl_role)
		hbox.add_child(lbl_role)
		
		var pbar = ProgressBar.new()
		pbar.custom_minimum_size = Vector2(100, 20)
		pbar.value = ant.hunger
		pbar.show_percentage = false
		pbar.tooltip_text = "Hunger"
		hbox.add_child(pbar)
		
		var btn_focus = Button.new()
		btn_focus.text = "FOCUS"
		btn_focus.focus_mode = Control.FOCUS_NONE
		btn_focus.connect("pressed", Callable(self, "_on_focus_ant_from_list").bind(ant))
		apply_font(btn_focus)
		hbox.add_child(btn_focus)
		
		vbox.add_child(hbox)

func _on_focus_ant_from_list(ant):
	colony_list_panel.visible = false
	show_ant_inspector(ant)

func _on_close_colony_list():
	colony_list_panel.visible = false

func create_global_inventory_panel():
	var panel = Panel.new()
	panel.name = "GlobalInventory"
	panel.position = Vector2(50, 100)
	panel.size = Vector2(668, 600)
	panel.visible = false
	add_child(panel)
	self.inventory_panel = panel
	
	var title = Label.new()
	title.text = "COLONY INVENTORY"
	title.position = Vector2(0, 20)
	title.size = Vector2(668, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	apply_font(title)
	panel.add_child(title)
	
	var content = Label.new()
	content.name = "ContentLabel"
	content.position = Vector2(50, 100)
	content.size = Vector2(568, 300)
	content.text = "Loading..."
	apply_font(content)
	panel.add_child(content)
	
	var btn_sell = Button.new()
	btn_sell.text = "SELL ALL FOOD"
	btn_sell.position = Vector2(234, 450)
	btn_sell.size = Vector2(200, 50)
	btn_sell.focus_mode = Control.FOCUS_NONE
	btn_sell.connect("pressed", Callable(self, "_on_sell_all_click"))
	apply_font(btn_sell)
	panel.add_child(btn_sell)
	
	var btn_roster = Button.new()
	btn_roster.text = "VIEW COLONY ROSTER"
	btn_roster.position = Vector2(234, 520)
	btn_roster.size = Vector2(200, 50)
	btn_roster.focus_mode = Control.FOCUS_NONE
	btn_roster.connect("pressed", Callable(self, "_on_open_roster_click"))
	apply_font(btn_roster)
	panel.add_child(btn_roster)

func _on_open_roster_click():
	inventory_panel.visible = false
	colony_list_panel.visible = true
	update_colony_list()

func update_global_inventory():
	var lbl = inventory_panel.get_node("ContentLabel")
	var text = "HARVESTED FOOD:\n"
	var total_val = 0
	
	for type in game_manager.food_inventory:
		var count = game_manager.food_inventory[type]
		if count > 0:
			var price = game_manager.fungus_types[type]["sell_price"]
			text += "- " + type.capitalize() + ": " + str(count) + " (Val: $" + str(count * price) + ")\n"
			total_val += count * price
			
	text += "\nTOTAL VALUE: $" + str(total_val) + "\n\n"
	
	text += "SEEDS:\n"
	for type in game_manager.seeds_owned.keys():
		text += "- " + type.capitalize() + ": " + str(game_manager.seeds_owned[type]) + "\n"
	text += "\nPOPULATION: " + str(game_manager.colony_population)
	text += "\nLEVEL: " + str(game_manager.colony_level)
	lbl.text = text

func _on_sell_all_click():
	game_manager.sell_all_food()

func create_plant_selector_panel():
	var panel = Panel.new()
	panel.name = "PlantSelectorPanel"
	panel.position = Vector2(20, screen_bottom_y - 320)
	panel.size = Vector2(300, 240)
	panel.visible = false
	add_child(panel)
	self.plant_selector_panel = panel
	
	var title = Label.new()
	title.text = "SELECT SEED"
	title.position = Vector2(0, 5)
	title.size = Vector2(300, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apply_font(title)
	panel.add_child(title)
	
	var vbox = VBoxContainer.new()
	vbox.name = "SeedContainer"
	vbox.position = Vector2(10, 40)
	vbox.size = Vector2(280, 190)
	panel.add_child(vbox)
	
	update_plant_selector_ui()

func update_plant_selector_ui():
	if not plant_selector_panel: return
	var vbox = plant_selector_panel.get_node("SeedContainer")
	for child in vbox.get_children():
		child.queue_free()
		
	var types = ["basic", "common", "rare", "legendary"]
	var colors = {
		"basic": Color(0.8, 0.8, 0.8),
		"common": Color(0.2, 0.8, 0.2),
		"rare": Color(0.2, 0.5, 1.0),
		"legendary": Color(1.0, 0.6, 0.0)
	}
	
	for type in types:
		var count = game_manager.seeds_owned.get(type, 0)
		var btn = Button.new()
		btn.text = type.capitalize() + " (" + str(count) + ")"
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 40)
		
		if type == current_seed_type:
			btn.modulate = Color(1, 1, 1) 
		else:
			btn.modulate = Color(0.7, 0.7, 0.7) 
			
		var style = StyleBoxFlat.new()
		style.bg_color = colors[type]
		style.border_width_bottom = 2
		style.border_color = Color.WHITE
		if type == current_seed_type:
			style.border_width_left = 4
			style.border_width_right = 4
			
		btn.add_theme_stylebox_override("normal", style)
		
		var info = game_manager.fungus_types.get(type, {})
		var grow = info.get("grow_time", 60)
		var sell = info.get("sell_price", 15)
		btn.tooltip_text = "Grow Time: " + str(grow) + "s\nSell Price: $" + str(sell)
		
		btn.connect("pressed", Callable(self, "_on_seed_type_selected").bind(type))
		apply_font(btn)
		vbox.add_child(btn)

func _on_seed_type_selected(type):
	current_seed_type = type
	update_plant_selector_ui()

func create_tunnel_selector_panel():
	var panel = Panel.new()
	panel.name = "TunnelSelectorPanel"
	panel.position = Vector2(20, screen_bottom_y - 270)
	panel.size = Vector2(350, 220)
	panel.visible = false
	add_child(panel)
	self.tunnel_selector_panel = panel
	
	var piece_types = ["straight", "corner", "t_junction", "cross", "end_cap"]
	var piece_symbols = ["─", "└", "┴", "┼", "╸"]
	
	var shape_label = Label.new()
	shape_label.text = "Shape:"
	shape_label.position = Vector2(10, 5)
	apply_font(shape_label)
	panel.add_child(shape_label)
	
	for i in range(piece_types.size()):
		var btn = Button.new()
		btn.text = piece_symbols[i]
		btn.position = Vector2(10 + (i * 55), 30)
		btn.size = Vector2(50, 50)
		btn.focus_mode = Control.FOCUS_NONE
		btn.connect("pressed", Callable(self, "_on_tunnel_piece_selected").bind(piece_types[i]))
		apply_font(btn)
		panel.add_child(btn)
		
	var btn_trash = Button.new()
	btn_trash.text = "X"
	btn_trash.modulate = Color.RED
	btn_trash.position = Vector2(10 + (5 * 55), 30)
	btn_trash.size = Vector2(50, 50)
	btn_trash.focus_mode = Control.FOCUS_NONE
	btn_trash.tooltip_text = "Remove Mode"
	btn_trash.connect("pressed", Callable(self, "_on_remove_toggle"))
	apply_font(btn_trash)
	panel.add_child(btn_trash)
	
	var room_label = Label.new()
	room_label.text = "Room Type:"
	room_label.position = Vector2(10, 90)
	apply_font(room_label)
	panel.add_child(room_label)
	
	var x_offset = 10
	var room_keys = game_manager.room_types.keys()
	
	for key in room_keys:
		var room_def = game_manager.room_types[key]
		var btn = Button.new()
		btn.text = room_def["display_name"].substr(0, 1)
		var style = StyleBoxFlat.new()
		style.bg_color = room_def["color"]
		style.border_width_bottom = 2
		style.border_color = Color.WHITE
		btn.add_theme_stylebox_override("normal", style)
		btn.position = Vector2(x_offset, 115)
		btn.size = Vector2(50, 50)
		btn.focus_mode = Control.FOCUS_NONE
		var req_level = room_def.get("unlock_level", 1)
		if game_manager.colony_level < req_level:
			btn.disabled = true
			btn.tooltip_text = "LOCKED (Lvl " + str(req_level) + ")"
			btn.text = "Lvl" + str(req_level)
			btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			btn.tooltip_text = room_def["display_name"] + " ($" + str(room_def["cost"]) + ")"
			btn.connect("pressed", Callable(self, "_on_room_type_selected").bind(key))
		apply_font(btn)
		panel.add_child(btn)
		x_offset += 55
	
	build_info_label = Label.new()
	build_info_label.text = "Cost: $5"
	build_info_label.position = Vector2(10, 180)
	apply_font(build_info_label)
	panel.add_child(build_info_label)
	
	var hint = Label.new()
	hint.text = "[R] Rotate"
	hint.position = Vector2(200, 180)
	apply_font(hint)
	panel.add_child(hint)

func _on_xp_changed(cur, max_xp, lvl):
	xp_label.text = "Lvl " + str(lvl) + " - XP: " + str(cur) + "/" + str(max_xp)

func _on_level_up(new_level):
	if tunnel_selector_panel:
		tunnel_selector_panel.name = "TrashPanel"
		tunnel_selector_panel.queue_free()
	create_tunnel_selector_panel()
	if is_build_mode: tunnel_selector_panel.visible = true
	update_mound_ui_state()

func get_ant_at_position(screen_pos: Vector2):
	var camera = get_viewport().get_camera_2d()
	var world_pos = screen_pos
	if camera: world_pos = camera.get_global_mouse_position()
	for ant in game_manager.ants:
		if ant.global_position.distance_to(world_pos) < 32: return ant
	return null

func get_akira_at_position(screen_pos: Vector2):
	if not chunk_grid.akira_instance: return false
	var camera = get_viewport().get_camera_2d()
	var world_pos = screen_pos
	if camera: world_pos = camera.get_global_mouse_position()
	return world_pos.distance_to(chunk_grid.akira_instance.global_position) < 64

func _on_seeds_changed(type, amount):
	if type == current_seed_type and seed_count_label:
		seed_count_label.text = "Owned: " + str(amount)
	update_plant_selector_ui()

func _on_mode_toggle():
	# If opening build mode, check for blockers
	if not is_build_mode:
		if is_any_window_open(): close_all_windows()
		is_build_mode = true
		is_plant_mode = false
		is_remove_mode = false
	else:
		is_build_mode = false
		
	_update_states()

func _on_plant_toggle():
	if not is_plant_mode:
		if is_any_window_open(): close_all_windows()
		is_plant_mode = true
		is_build_mode = false
		is_remove_mode = false
		update_plant_selector_ui() 
	else:
		is_plant_mode = false
		
	_update_states()

func _on_remove_toggle():
	is_remove_mode = true
	is_build_mode = false
	is_plant_mode = false
	chunk_grid.set_remove_mode_active(true)
	_update_button_visuals()

func _on_inventory_toggle():
	if is_inventory_open:
		close_all_windows() # Will close inventory
	else:
		close_all_windows()
		is_inventory_open = true
		inventory_panel.visible = true
	_update_states()

func _update_states():
	chunk_grid.set_build_mode_active(is_build_mode)
	chunk_grid.set_plant_mode_active(is_plant_mode)
	chunk_grid.set_remove_mode_active(is_remove_mode)
	if tunnel_selector_panel: tunnel_selector_panel.visible = is_build_mode
	if plant_selector_panel: plant_selector_panel.visible = is_plant_mode
	# Settings panel visibility is handled by close_all_windows/toggle
	_update_button_visuals()

func _update_button_visuals():
	var active = Color(0.6, 0.6, 0.6); var normal = Color(1, 1, 1)
	var press_offset = Vector2(0, 2)
	var bag_pos = Vector2(backpack_x, screen_bottom_y - 80)
	var shovel_pos = Vector2(shovel_x, screen_bottom_y - 40)
	var plant_pos = Vector2(plant_x, screen_bottom_y - 60)
	if btn_inventory:
		btn_inventory.modulate = active if is_inventory_open else normal
		btn_inventory.position = bag_pos + (press_offset if is_inventory_open else Vector2.ZERO)
	if btn_build:
		btn_build.modulate = active if (is_build_mode or is_remove_mode) else normal
		btn_build.position = shovel_pos + (press_offset if (is_build_mode or is_remove_mode) else Vector2.ZERO)
	if btn_plant:
		btn_plant.modulate = active if is_plant_mode else normal
		btn_plant.position = plant_pos + (press_offset if is_plant_mode else Vector2.ZERO)

func _on_money_changed(new_amount):
	var money_label = get_node_or_null("MoneyLabel")
	if money_label: money_label.text = "Money: $" + str(new_amount)

func _on_system_message(text, color): print("SYSTEM: " + text)

func _on_tunnel_piece_selected(piece_type: String):
	is_remove_mode = false
	is_build_mode = true
	chunk_grid.set_remove_mode_active(false)
	chunk_grid.set_build_mode_active(true)
	current_tunnel_piece = piece_type
	chunk_grid.set_tunnel_piece(piece_type)
	_update_button_visuals()

func _on_room_type_selected(room_key: String):
	is_remove_mode = false
	is_build_mode = true
	chunk_grid.set_remove_mode_active(false)
	chunk_grid.set_build_mode_active(true)
	chunk_grid.set_build_type(room_key)
	var cost = game_manager.get_room_cost(room_key)
	var rname = game_manager.room_types[room_key]["display_name"]
	build_info_label.text = rname + ": $" + str(cost)
	_update_button_visuals()

# --- AKIRA SHOP ---
func create_akira_panel():
	var panel = Panel.new()
	panel.name = "AkiraPanel"
	panel.position = Vector2(100, 200)
	panel.size = Vector2(568, 400)
	panel.visible = false
	add_child(panel)
	self.akira_panel = panel
	
	var title = Label.new()
	title.text = "AKIRA (THE CATERPILLAR)"
	title.position = Vector2(0, 10)
	title.size = Vector2(568, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apply_font(title)
	panel.add_child(title)
	
	akira_text_label = Label.new()
	akira_text_label.text = "Oh... hello little one. You dig deep."
	akira_text_label.position = Vector2(30, 60)
	akira_text_label.size = Vector2(508, 100)
	akira_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	apply_font(akira_text_label)
	panel.add_child(akira_text_label)
	
	var btn_talk = Button.new()
	btn_talk.text = "Ask about the colony"
	btn_talk.position = Vector2(30, 180)
	btn_talk.size = Vector2(240, 40)
	btn_talk.connect("pressed", Callable(self, "_on_akira_talk"))
	apply_font(btn_talk)
	panel.add_child(btn_talk)
	
	var btn_leave = Button.new()
	btn_leave.text = "Goodbye"
	btn_leave.position = Vector2(30, 230)
	btn_leave.size = Vector2(240, 40)
	btn_leave.connect("pressed", Callable(self, "_close_akira_shop"))
	apply_font(btn_leave)
	panel.add_child(btn_leave)
	
	var shop_lbl = Label.new()
	shop_lbl.text = "RARE SEEDS"
	shop_lbl.position = Vector2(300, 150)
	apply_font(shop_lbl)
	panel.add_child(shop_lbl)
	
	var y_off = 180
	for type in ["common", "rare", "legendary"]:
		var data = game_manager.fungus_types[type]
		var btn = Button.new()
		btn.text = "Buy " + type.capitalize() + " ($" + str(data["buy_cost"]) + ")"
		btn.position = Vector2(300, y_off)
		btn.size = Vector2(240, 30)
		
		if game_manager.colony_level < data["unlock_level"]:
			btn.disabled = true
			btn.text = "Lvl " + str(data["unlock_level"]) + " Required"
		
		btn.connect("pressed", Callable(self, "_on_buy_seed").bind(type))
		apply_font(btn)
		panel.add_child(btn)
		y_off += 40

func open_akira_shop():
	if is_any_window_open(): return
	close_all_windows()
	
	if akira_panel: akira_panel.queue_free()
	create_akira_panel()
	
	var greetings = [
		"Oh... unexpected visitors.",
		"The earth vibrates with your work.",
		"Got any leaves? No? Shame.",
            "I have seeds... for a price."
	]
	akira_text_label.text = greetings.pick_random()
	akira_panel.visible = true
	
	play_akira_voice()

func _close_akira_shop(): akira_panel.visible = false

func _on_akira_talk():
	var lines = [
		"I've been here since before the first rain.",
		"Your tunnels are messy. Straight lines are boring.",
		"Be careful deep down. The roots scream sometimes.",
            "I used to be smaller. Or larger? I forget."
	]
	akira_text_label.text = lines.pick_random()
	play_akira_voice()

func _on_buy_seed(type):
	if game_manager.buy_seed(type):
		akira_text_label.text = "A wise choice. Plant it well."
		play_akira_voice()
	else:
		akira_text_label.text = "You lack the funds, little ant."
		play_akira_voice()

func play_akira_voice():
	if audio_manager and akira_clips.size() > 0:
		var clip = akira_clips.pick_random()
		print("Control: Playing Akira Voice")
		audio_manager.play_voice_stream(clip)
	else:
		print("Control: Cannot play voice. AM missing or clips empty.")
