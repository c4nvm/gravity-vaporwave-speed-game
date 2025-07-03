class_name AudioManager
extends Node

## The duration, in seconds, for music to fade in or out.
@export var fade_duration: float = 1.0

# Dictionary to hold all audio profile nodes
var _audio_profiles: Dictionary = {}
# Current active profile
var _current_profile: String = "default"
# Track if we're in gameplay mode
var _in_gameplay: bool = false

func _ready():
	# Automatically detect and register all audio profile child nodes
	_register_audio_profiles()

## Registers all child AudioProfile nodes
func _register_audio_profiles():
	_audio_profiles.clear()
	for child in get_children():
		if child is AudioProfile:
			_audio_profiles[child.profile_name.to_lower()] = child
			print("Registered audio profile: ", child.profile_name)
	
	# Ensure default profile exists
	if not _audio_profiles.has("default"):
		push_error("No default audio profile found!")

## Sets the current soundtrack profile
func set_soundtrack_profile(profile_name: String):
	var normalized_name = profile_name.to_lower()
	if normalized_name in _audio_profiles:
		_current_profile = normalized_name
		print("Switched to audio profile: ", profile_name)
	else:
		push_warning("Audio profile '%s' not found. Using default." % profile_name)
		_current_profile = "default"

## Gets the current audio stream player for a given type
func _get_player(type: String) -> AudioStreamPlayer:
	if _current_profile in _audio_profiles:
		var profile: AudioProfile = _audio_profiles[_current_profile]
		return profile.get_node(type) if profile.has_node(type) else null
	return null

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
	_in_gameplay = false
	var waiting_bgm = _get_player("WaitingBGM")
	var playing_bgm = _get_player("PlayingBGM")
	
	if playing_bgm and playing_bgm.playing:
		_fade_out(playing_bgm)
	if waiting_bgm and not waiting_bgm.playing:
		_fade_in(waiting_bgm)

## Called on first player movement. Transitions to gameplay audio.
func start_gameplay_audio():
	if _in_gameplay:
		return
		
	_in_gameplay = true
	var waiting_bgm = _get_player("WaitingBGM")
	var playing_bgm = _get_player("PlayingBGM")
	var start_sfx = _get_player("StartSFX")
	
	if waiting_bgm and waiting_bgm.playing:
		_fade_out(waiting_bgm)
	
	if start_sfx:
		start_sfx.play()
	
	if playing_bgm and not playing_bgm.playing:
		_fade_in(playing_bgm)

## Called when the level is completed.
func play_end_level_audio():
	var playing_bgm = _get_player("PlayingBGM")
	var start_sfx = _get_player("StartSFX")
	var end_sfx = _get_player("EndSFX")
	
	if playing_bgm and playing_bgm.playing:
		playing_bgm.stop()
	if start_sfx and start_sfx.playing:
		start_sfx.stop()
	if end_sfx:
		end_sfx.play()

## Stops all BGM instantly. Useful when returning to a menu.
func stop_all_music():
	var waiting_bgm = _get_player("WaitingBGM")
	var playing_bgm = _get_player("PlayingBGM")
	
	if waiting_bgm and waiting_bgm.playing:
		waiting_bgm.stop()
	if playing_bgm and playing_bgm.playing:
		playing_bgm.stop()

## Plays a one-shot sound effect from the current profile
func play_sfx(sfx_name: String):
	var sfx_player = _get_player(sfx_name)
	if sfx_player:
		sfx_player.play()
	else:
		push_warning("SFX '%s' not found in current profile" % sfx_name)
