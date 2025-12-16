extends Node2D

var audio_manager
var sprite : Sprite2D
var is_active = false

func _ready():
	# Setup Audio Connection
	audio_manager = get_node_or_null("/root/TestLevel/AudioManager")
	
	# Setup Sprite
	sprite = Sprite2D.new()
	sprite.texture = load("res://sprites/Ash.png")
	
	# --- USER-DEFINED SCALE ---
	sprite.scale = Vector2(0.13, 0.13)
	
	# centering the sprite so position sets the bottom-center
	var tex_size = sprite.texture.get_size()
	sprite.offset = Vector2(0, -tex_size.y / 2)
	
	add_child(sprite)

func meow():
	if not audio_manager: return
	
	# Play Meow
	var stream = load("res://audio/voice/meow.mp3")
	if stream:
		# Use the voice channel so it doesn't overlap/spam
		audio_manager.play_voice_stream(stream)
		
		# Little jump or wiggle animation when clicked
		var t = create_tween()
		t.tween_property(sprite, "scale", sprite.scale * 1.1, 0.1)
		t.tween_property(sprite, "scale", sprite.scale, 0.1)

func _input(event):
	# Self-contained click detection to save space in Control.gd
	if not is_active or not visible: return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Check if mouse is over sprite
		var mouse_pos = get_global_mouse_position()
		if sprite.get_rect().has_point(to_local(mouse_pos)):
			meow()
			get_viewport().set_input_as_handled()
