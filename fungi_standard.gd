extends Node2D

signal mature(fungus_instance)

# Properties
var type = "basic"
var growth_stage = 0 
var is_ready_to_harvest = false

# References
@onready var sprite = $AnimatedSprite2D
@onready var timer = $GrowthTimer
var game_manager

func _ready():
	if has_node("/root/TestLevel/GameManager"):
		game_manager = get_node("/root/TestLevel/GameManager")

	# VISUAL FIX: Halved the size again
	# Old: 0.064. New: 0.032 (approx 24px wide)
	scale = Vector2(0.032, 0.032)
	
	# Offset fix (Needs to match half of the sprite height at original size)
	# 750px / 2 = 375. Negative to move up.
	sprite.position.y = -375.0 

	if not timer.timeout.is_connected(_on_growth_timer_timeout):
		timer.timeout.connect(_on_growth_timer_timeout)

func initialize(fungus_type: String):
	type = fungus_type
	var total_grow_time = 45.0 # Default 60s
	
	if game_manager and game_manager.fungus_types.has(type):
		total_grow_time = game_manager.fungus_types[type]["grow_time"]
	
	# --- NEW: COLOUR TINTING ---
	match type:
		"basic":
			sprite.modulate = Color(1, 1, 1) # White (Original)
		"common":
			sprite.modulate = Color(0.3, 1.0, 0.3) # Bright Green
		"rare":
			sprite.modulate = Color(0.3, 0.6, 1.0) # Sky Blue
		"legendary":
			sprite.modulate = Color(1.0, 0.65, 0.0) # Golden Orange
		_:
			sprite.modulate = Color(1, 1, 1) # Default fallback

	timer.wait_time = total_grow_time / 2.0
	timer.start()
	update_appearance()

func _on_growth_timer_timeout():
	growth_stage += 1
	if growth_stage >= 2:
		growth_stage = 2
		is_ready_to_harvest = true
		timer.stop()
		emit_signal("mature", self)
	
	update_appearance()

func update_appearance():
	match growth_stage:
		0: sprite.play("start")
		1: sprite.play("middle")
		2: sprite.play("end")
