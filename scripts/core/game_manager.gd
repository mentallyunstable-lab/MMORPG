extends Node
## GameManager - Central orchestration for Ashborn
##
## Coordinates all systems and enforces restraint orchestration.
## "You are not missing systems. You are missing restraint orchestration."

signal game_state_changed(old_state: GameState, new_state: GameState)
signal session_started
signal session_ended

enum GameState {
	INITIALIZING,
	MAIN_MENU,
	PLAYING,
	PAUSED,
	CUTSCENE,
	WITNESS_STILLNESS,  # Forced stillness moments from Witness Mode
}

## Current game state
var current_state: GameState = GameState.INITIALIZING

## Session tracking
var session_start_time: float = 0.0
var total_play_time: float = 0.0

## First 90 minutes lockdown tracking (Priority #16)
var first_90_minutes_events: Dictionary = {
	"lie_delivered": false,
	"silence_delivered": false,
	"refusal_delivered": false,
}

## Debug mode
var debug_mode: bool = false


func _ready() -> void:
	_initialize_systems()


func _initialize_systems() -> void:
	# Systems initialize themselves via autoload
	# This ensures proper load order
	print("[GameManager] Initializing Ashborn systems...")

	# Verify critical systems
	if not _verify_anchor_system():
		push_error("[GameManager] CRITICAL: Anchor system not properly configured!")

	change_state(GameState.MAIN_MENU)


func _verify_anchor_system() -> bool:
	## The anchor system is MANDATORY. Game collapses into noise without it.
	if not AnchorSystem:
		return false
	return AnchorSystem.is_configured()


func change_state(new_state: GameState) -> void:
	var old_state := current_state
	current_state = new_state
	game_state_changed.emit(old_state, new_state)

	match new_state:
		GameState.PLAYING:
			_on_play_started()
		GameState.PAUSED:
			HauntScore.record_pause()


func _on_play_started() -> void:
	if session_start_time == 0.0:
		session_start_time = Time.get_ticks_msec() / 1000.0
		session_started.emit()


func get_session_duration() -> float:
	## Returns session duration in seconds
	if session_start_time == 0.0:
		return 0.0
	return (Time.get_ticks_msec() / 1000.0) - session_start_time


func is_in_first_90_minutes() -> bool:
	## First 90 minutes have special rules (Priority #16)
	return get_session_duration() < 5400.0  # 90 * 60


func mark_first_90_event(event_type: String) -> void:
	## Track scripted minimum events for first 90 minutes
	if event_type in first_90_minutes_events:
		first_90_minutes_events[event_type] = true


func get_first_90_completion() -> Dictionary:
	return first_90_minutes_events.duplicate()


func enable_debug_mode() -> void:
	debug_mode = true
	print("[GameManager] Debug mode enabled - betrayal overlay active")


## Minimum Viable Horror Loop (Priority #13)
## "Every 30-45 minutes, the player experiences X → Y → Z"
## TODO: Define and implement the loop
func get_horror_loop_status() -> Dictionary:
	return {
		"loop_defined": false,
		"current_phase": "undefined",
		"time_in_phase": 0.0,
	}
