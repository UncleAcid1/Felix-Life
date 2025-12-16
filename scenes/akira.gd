extends Node2D

@onready var animated_sprite = $AnimatedSprite2D

func _ready():
	# Force her to be visible above background
	z_index = 200 
	
	# Play Animation
	if animated_sprite:
		if animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.play("idle")
		else:
			animated_sprite.play()

# Note: play_voice() is no longer needed here as Control handles it directly.
# Keeping the function as a stub in case other scripts call it blindly.
func play_voice():
	pass
