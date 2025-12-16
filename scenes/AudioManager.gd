extends Node

# --- AUDIO CONFIGURATION ---
var bgm_day_path = "res://audio/music/DayBGM.mp3"
var bgm_night_path = "res://audio/music/NightBGM.mp3"
var bgm_loading_path = "res://audio/music/Loading_Save.mp3"

var amb_day_path = "res://audio/ambience/Day_time.mp3"
var amb_night_path = "res://audio/ambience/Night_time.mp3"

var sfx_level_up_path = "res://audio/sfx/Level_Up.mp3"
var sfx_focus_path = "res://audio/sfx/ant.mp3"

# --- NODES ---
var music_player: AudioStreamPlayer
var ambience_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer # NEW: Dedicated voice player
var music_timer: Timer

# --- STATE ---
var is_music_enabled = true
var current_time_state = "day" 
var game_has_started = false
var default_music_vol = -5.0

func _ready():
	# Setup Players
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	music_player.volume_db = default_music_vol 
	add_child(music_player)
	
	ambience_player = AudioStreamPlayer.new()
	ambience_player.bus = "Master"
	ambience_player.volume_db = -2.0
	# FORCE LOOP
	ambience_player.finished.connect(Callable(self, "_on_ambience_finished"))
	add_child(ambience_player)
	
	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "Master"
	add_child(sfx_player)
	
	# NEW: Setup Voice Player
	voice_player = AudioStreamPlayer.new()
	voice_player.bus = "Master"
	voice_player.volume_db = 8.0 # Boost volume to ensure it's heard
	add_child(voice_player)
	
	# Setup Timer
	music_timer = Timer.new()
	music_timer.one_shot = true
	music_timer.connect("timeout", Callable(self, "_on_music_timer_timeout"))
	add_child(music_timer)

# --- PUBLIC FUNCTIONS ---

func start_audio_systems():
	game_has_started = true
	reset_music_volume()
	update_ambience(current_time_state)
	queue_next_song()

func play_loading_music():
	music_timer.stop()
	music_player.stop()
	reset_music_volume()
	var stream = load(bgm_loading_path)
	if stream:
		music_player.stream = stream
		music_player.play()

func fade_out_music(duration: float):
	var tween = create_tween()
	tween.tween_property(music_player, "volume_db", -80.0, duration)
	await tween.finished
	music_player.stop()

func reset_music_volume():
	music_player.volume_db = default_music_vol

func resume_game_music():
	music_player.stop()
	reset_music_volume()
	queue_next_song()

func set_time_state(state: String):
	if current_time_state != state:
		current_time_state = state
		if game_has_started:
			update_ambience(state)

func toggle_music(enabled: bool):
	is_music_enabled = enabled
	if not is_music_enabled:
		music_player.stop()
		music_timer.stop()
	else:
		if game_has_started and not music_player.playing and music_timer.time_left == 0:
			queue_next_song()

func play_sfx(type: String):
	# --- FIX: Auto-create player if it doesn't exist yet ---
	if not sfx_player:
		sfx_player = AudioStreamPlayer.new()
		sfx_player.bus = "Master"
		add_child(sfx_player)

	var path = ""
	match type:
		"level_up": path = sfx_level_up_path
		"focus": path = sfx_focus_path
	
	if path != "":
		var stream = load(path)
		if stream:
			sfx_player.stream = stream
			sfx_player.play()

# --- NEW: VOICE HANDLING ---
func play_voice_stream(stream):
	if not voice_player:
		voice_player = AudioStreamPlayer.new()
		voice_player.bus = "Master"
		voice_player.volume_db = 8.0
		add_child(voice_player)
	
	# Stop previous voice line if still playing (prevents overlap)
	if voice_player.playing:
		voice_player.stop()
		
	if stream:
		voice_player.stream = stream
		voice_player.pitch_scale = randf_range(0.95, 1.05)
		voice_player.play()
		print("AudioManager: Playing voice clip")

# --- INTERNAL LOGIC ---

func update_ambience(state: String):
	var path = amb_day_path if state == "day" else amb_night_path
	var stream = load(path)
	
	if ambience_player.stream != stream:
		ambience_player.stream = stream
		ambience_player.play()

func _on_ambience_finished():
	ambience_player.play()

func queue_next_song():
	if not is_music_enabled or not game_has_started: return
	
	var wait_time = randf_range(120.0, 300.0) 
	music_timer.start(wait_time)

func _on_music_timer_timeout():
	if not is_music_enabled: return
	
	var path = bgm_day_path if current_time_state == "day" else bgm_night_path
	var stream = load(path)
	
	if stream:
		reset_music_volume()
		music_player.stream = stream
		music_player.play()
		await music_player.finished
		queue_next_song()
