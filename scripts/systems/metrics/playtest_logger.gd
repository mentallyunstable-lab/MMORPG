extends Node
## PlaytestLogger - Silent observation for internal playtesting
##
## PRIORITY #17
## "No explaining mechanics. No hinting. No saving testers."
## "If they get lost — log it. If they rage — log why. If they laugh — you failed the tone."
##
## This system silently logs player behavior for analysis without
## any player-facing feedback or assistance.

signal playtest_event_logged(event_type: String, data: Dictionary)
signal session_exported(file_path: String)

## Event categories
enum EventType {
	NAVIGATION,      # Movement, getting lost
	EMOTION,         # Detected emotional responses
	PROGRESSION,     # Quest/objective progress
	FAILURE,         # Deaths, failed attempts
	SYSTEM_INTERACTION, # How they interact with game systems
	BETRAYAL_RESPONSE,  # Response to betrayals
	PAUSE_BEHAVIOR,  # Pausing patterns
}

## Session data
var session_id: String
var session_start: float
var events: Array[Dictionary] = []

## Emotion detection (based on behavior)
var detected_emotions: Dictionary = {
	"confusion": 0,    # Getting lost, backtracking
	"frustration": 0,  # Repeated failures, aggressive inputs
	"fear": 0,         # Hesitation, pausing, slow movement
	"amusement": 0,    # Unexpected behavior patterns (BAD for horror)
	"engagement": 0,   # Steady progress, exploration
}

## Lost detection
var movement_history: Array[Vector3] = []
var backtrack_count: int = 0
var time_in_same_area: float = 0.0
var last_position: Vector3 = Vector3.ZERO

## Failure tracking
var deaths: Array[Dictionary] = []
var retry_attempts: Dictionary = {}  # challenge_id -> count


func _ready() -> void:
	session_id = _generate_session_id()
	session_start = Time.get_ticks_msec() / 1000.0


func _generate_session_id() -> String:
	var datetime := Time.get_datetime_dict_from_system()
	return "playtest_%d%02d%02d_%02d%02d%02d" % [
		datetime["year"], datetime["month"], datetime["day"],
		datetime["hour"], datetime["minute"], datetime["second"]
	]


func log_event(event_type: EventType, data: Dictionary = {}) -> void:
	## Core logging function - called by other systems

	var event := {
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"session_time": (Time.get_ticks_msec() / 1000.0) - session_start,
		"type": EventType.keys()[event_type],
		"data": data,
		"haunt_score": HauntScore.haunt_score if HauntScore else 0.0,
	}

	events.append(event)
	playtest_event_logged.emit(EventType.keys()[event_type], data)


func log_player_position(position: Vector3) -> void:
	## Track movement for lost detection

	if last_position != Vector3.ZERO:
		var distance := position.distance_to(last_position)

		# Detect backtracking
		for i in range(max(0, movement_history.size() - 20), movement_history.size()):
			if position.distance_to(movement_history[i]) < 2.0:
				backtrack_count += 1
				_detect_confusion()
				break

	movement_history.append(position)
	last_position = position

	# Trim history
	if movement_history.size() > 100:
		movement_history.pop_front()


func _detect_confusion() -> void:
	## Player seems lost

	detected_emotions["confusion"] += 1

	if backtrack_count > 5:
		log_event(EventType.NAVIGATION, {
			"sub_type": "lost",
			"backtrack_count": backtrack_count,
			"area": _get_current_area(),
		})


func log_death(cause: String, location: Vector3, context: Dictionary = {}) -> void:
	## Player died

	var death_data := {
		"cause": cause,
		"location": location,
		"context": context,
		"session_time": (Time.get_ticks_msec() / 1000.0) - session_start,
	}

	deaths.append(death_data)

	log_event(EventType.FAILURE, {
		"sub_type": "death",
		"cause": cause,
	})


func log_retry(challenge_id: String) -> void:
	## Player retrying a challenge

	if not challenge_id in retry_attempts:
		retry_attempts[challenge_id] = 0

	retry_attempts[challenge_id] += 1

	# Detect frustration from repeated retries
	if retry_attempts[challenge_id] > 3:
		detected_emotions["frustration"] += 1

		log_event(EventType.FAILURE, {
			"sub_type": "repeated_retry",
			"challenge": challenge_id,
			"attempt": retry_attempts[challenge_id],
		})


func log_betrayal_response(betrayal_type: String, response_action: String, delay: float) -> void:
	## How player responded to a betrayal

	log_event(EventType.BETRAYAL_RESPONSE, {
		"betrayal_type": betrayal_type,
		"response": response_action,
		"reaction_delay": delay,
	})

	# Detect emotions based on response
	match response_action:
		"pause":
			detected_emotions["fear"] += 1
		"aggressive_input":
			detected_emotions["frustration"] += 1
		"cautious_approach":
			detected_emotions["engagement"] += 1


func log_laugh_indicator() -> void:
	## Detected behavior suggesting player is amused (BAD for horror)
	## This could be rapid button mashing, erratic movement, etc.

	detected_emotions["amusement"] += 1

	log_event(EventType.EMOTION, {
		"sub_type": "possible_amusement",
		"note": "TONE FAILURE - player may be laughing",
	})


func log_pause_pattern(duration: float, context: String) -> void:
	## Track pausing behavior

	log_event(EventType.PAUSE_BEHAVIOR, {
		"duration": duration,
		"context": context,
	})

	if duration > 30.0:
		detected_emotions["fear"] += 1  # Long pause = processing fear?


func _get_current_area() -> String:
	## Get current area name
	## TODO: Implement actual area detection
	return "unknown_area"


func export_session() -> String:
	## Export session data to file

	var export_data := {
		"session_id": session_id,
		"duration": (Time.get_ticks_msec() / 1000.0) - session_start,
		"events": events,
		"detected_emotions": detected_emotions,
		"deaths": deaths,
		"retry_attempts": retry_attempts,
		"summary": _generate_summary(),
	}

	var file_path := "user://playtest_logs/%s.json" % session_id

	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute("user://playtest_logs")

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(export_data, "\t"))
		file.close()
		session_exported.emit(file_path)
		return file_path

	return ""


func _generate_summary() -> Dictionary:
	## Generate human-readable summary

	var issues: Array[String] = []
	var tone_failures: Array[String] = []

	# Check for problems
	if detected_emotions["confusion"] > 5:
		issues.append("Player got lost frequently (%d confusion events)" % detected_emotions["confusion"])

	if detected_emotions["frustration"] > 3:
		issues.append("Player showed frustration (%d events)" % detected_emotions["frustration"])

	if detected_emotions["amusement"] > 0:
		tone_failures.append("CRITICAL: Player showed amusement (%d events) - TONE FAILURE" % detected_emotions["amusement"])

	if deaths.size() > 10:
		issues.append("High death count (%d) - may indicate difficulty issues" % deaths.size())

	# Identify problem areas
	var problem_areas: Dictionary = {}
	for event in events:
		if event["type"] == "NAVIGATION" and event["data"].get("sub_type") == "lost":
			var area: String = event["data"].get("area", "unknown")
			if not area in problem_areas:
				problem_areas[area] = 0
			problem_areas[area] += 1

	return {
		"total_events": events.size(),
		"duration_minutes": ((Time.get_ticks_msec() / 1000.0) - session_start) / 60.0,
		"issues": issues,
		"tone_failures": tone_failures,
		"problem_areas": problem_areas,
		"emotion_summary": detected_emotions,
		"overall_assessment": _assess_session(),
	}


func _assess_session() -> String:
	if detected_emotions["amusement"] > 0:
		return "FAILED - Tone broken, player was amused"

	if detected_emotions["frustration"] > detected_emotions["engagement"]:
		return "NEEDS WORK - More frustration than engagement"

	if detected_emotions["confusion"] > 10:
		return "NEEDS WORK - Player frequently lost"

	if detected_emotions["fear"] > 5 and detected_emotions["engagement"] > 3:
		return "SUCCESS - Good balance of fear and engagement"

	return "INCONCLUSIVE - Need more data"


func get_realtime_summary() -> Dictionary:
	return {
		"session_time": (Time.get_ticks_msec() / 1000.0) - session_start,
		"events_logged": events.size(),
		"emotions": detected_emotions,
		"deaths": deaths.size(),
		"confusion_level": detected_emotions["confusion"],
		"frustration_level": detected_emotions["frustration"],
		"tone_intact": detected_emotions["amusement"] == 0,
	}
