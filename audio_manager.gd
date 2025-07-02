# AudioManager.gd

extends Node

## The duration, in seconds, for music to fade in or out.
@export var fade_duration: float = 1.0

# --- NODE REFERENCES ---
# Assign these in the Godot Editor's Inspector tab.
@export var waiting_bgm: AudioStreamPlayer
@export var playing_bgm: AudioStreamPlayer
@export var start_sfx: AudioStreamPlayer
@export var end_sfx: AudioStreamPlayer

## Fades out a music track using a Tween.
func _fade_out(player: AudioStreamPlayer):
	if not is_instance_valid(player) or not player.playing:
		return
		
	var tween = create_tween().set_parallel()
	tween.tween_property(player, "volume_db", -80.0, fade_duration).from_current()
	
	# After the tween finishes, stop the player.
	await tween.finished
	if is_instance_valid(player):
		player.stop()

## Fades in a music track using a Tween.
func _fade_in(player: AudioStreamPlayer):
	if not is_instance_valid(player) or player.playing:
		return
		
	player.volume_db = -80.0
	player.play()
	
	var tween = create_tween()
	tween.tween_property(player, "volume_db", 0.0, fade_duration)

## Called when a level starts. Fades in waiting music.
func play_waiting_music():
	_fade_out(playing_bgm)
	_fade_in(waiting_bgm)

## Called on first player movement. Transitions to gameplay audio.
func start_gameplay_audio():
	# Fade out the waiting track.
	_fade_out(waiting_bgm)
	
	# Play the start sound effect.
	if is_instance_valid(start_sfx):
		start_sfx.play()
	
	# Fade in the main gameplay music immediately.
	_fade_in(playing_bgm)

## Called when the level is completed.
func play_end_level_audio():
	# Immediately stop all gameplay-related sounds for an instant cut.
	if is_instance_valid(playing_bgm):
		playing_bgm.stop()
	if is_instance_valid(start_sfx):
		start_sfx.stop()

	# Now, play the end sound effect.
	if is_instance_valid(end_sfx):
		end_sfx.play()

## Stops all BGM instantly. Useful when returning to a menu.
func stop_all_music():
	if is_instance_valid(waiting_bgm) and waiting_bgm.playing:
		waiting_bgm.stop()
	if is_instance_valid(playing_bgm) and playing_bgm.playing:
		playing_bgm.stop()
