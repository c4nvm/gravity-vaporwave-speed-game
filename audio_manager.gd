class_name AudioManager
extends Node

## The duration, in seconds, for music to fade in or out.
@export var fade_duration: float = 1.0

## A dedicated container for player-specific sound effects that do not change with the level profile.
@export var player_sfx_container: Node

# Dictionary to hold all audio profile nodes for level-specific sounds (like BGM).
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

## Sets the current soundtrack profile for level-specific audio.
func set_soundtrack_profile(profile_name: String):
	var normalized_name = profile_name.to_lower()
	if normalized_name in _audio_profiles:
		_current_profile = normalized_name
		print("Switched to audio profile: ", profile_name)
	else:
		push_warning("Audio profile '%s' not found. Using default." % profile_name)
		_current_profile = "default"

## Gets an audio stream player. It checks the constant player SFX container first,
## then falls back to the current level-specific audio profile.
func _get_player(type: String) -> AudioStreamPlayer:
	# 1. Prioritize the constant player SFX container.
	if is_instance_valid(player_sfx_container) and player_sfx_container.has_node(type):
		var player = player_sfx_container.get_node(type)
		if player is AudioStreamPlayer:
			return player

	# 2. If not found in the player container, check the current level profile.
	if _current_profile in _audio_profiles:
		var profile: AudioProfile = _audio_profiles[_current_profile]
		if profile.has_node(type):
			var player = profile.get_node(type)
			if player is AudioStreamPlayer:
				return player
				
	# 3. If not found anywhere, return null.
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

## Plays a one-shot sound effect.
func play_sfx(sfx_name: String):
	var sfx_player = _get_player(sfx_name)
	if sfx_player:
		sfx_player.play()
	else:
		push_warning("SFX '%s' not found in player container or current profile." % sfx_name)

## Plays a looping sound effect.
func play_looping_sfx(sfx_name: String):
	var sfx_player = _get_player(sfx_name)
	if sfx_player:
		if not sfx_player.playing: # Don't restart if already playing
			sfx_player.play()
	else:
		push_warning("Looping SFX '%s' not found in player container or current profile." % sfx_name)

## Stops a looping sound effect.
func stop_looping_sfx(sfx_name: String):
	var sfx_player = _get_player(sfx_name)
	if sfx_player:
		if sfx_player.playing:
			sfx_player.stop()
	else:
		push_warning("Looping SFX '%s' not found in player container or current profile." % sfx_name)

func stop_all_looping_sfx():
	if not is_instance_valid(player_sfx_container):
		return

	for sfx_player in player_sfx_container.get_children():
		if sfx_player is AudioStreamPlayer and sfx_player.playing:
			sfx_player.stop()
