## SaveIntegrity — Phase G2: Save corruption detection, crash recovery,
## auto-repair of partial state, and fallback to last coherent snapshot.
## Handles: mid-god-interruption saves, mid-invasion saves, witness transition saves,
## save-quit-reload spam, save during dialogue signal chains.
extends Node

const SAVE_PATH := "user://ashborn_save.dat"
const BACKUP_PATH := "user://ashborn_save_backup.dat"
const SNAPSHOT_PATH := "user://ashborn_snapshot.dat"
const CRASH_FLAG_PATH := "user://ashborn_crash_flag.dat"

# Required keys for a valid save
const REQUIRED_KEYS := [
	"faith", "truth", "violence", "player_health", "player_alive",
]

# State validation ranges
const VALID_RANGES := {
	"faith": [0.0, 100.0],
	"truth": [0.0, 100.0],
	"violence": [0.0, 100.0],
	"player_health": [0.0, 200.0],
}

signal save_repaired(issues: Array)
signal save_corrupted(reason: String)
signal snapshot_restored(reason: String)

var _save_in_progress: bool = false
var _last_coherent_snapshot: Dictionary = {}
var _snapshot_timer: float = 0.0
const SNAPSHOT_INTERVAL := 60.0  # Take coherent snapshot every 60s


func _ready() -> void:
	# Check for crash recovery on startup
	_check_crash_recovery()


func _process(delta: float) -> void:
	_snapshot_timer += delta
	if _snapshot_timer >= SNAPSHOT_INTERVAL:
		_snapshot_timer = 0.0
		_take_coherent_snapshot()


## Take a coherent world snapshot — only when the world is in a stable state.
## This is the fallback if a save becomes corrupted.
func _take_coherent_snapshot() -> void:
	# Don't snapshot during unstable states
	if _save_in_progress:
		return
	if DialogueManager.is_active:
		return
	if GameState.witness_mode:
		return
	# Don't snapshot during god obsession events
	for god_id in GodManager.god_defs:
		if GodManager.get_god_attention(god_id) >= GodManager.ATTENTION_OBSESSED:
			return

	_last_coherent_snapshot = _build_full_state()
	# Write to disk as backup
	_write_snapshot(_last_coherent_snapshot)


func _build_full_state() -> Dictionary:
	var data := GameState.save_state()
	data["save_closed"] = GameState.save_closed
	data["ending_type"] = GameState.ending_type
	data["ending_message"] = GameState.ending_message
	data["world_memory"] = WorldMemory.save_state()
	data["god_attention"] = GodManager.save_attention()
	data["quests"] = QuestManager.save_state()
	data["timestamp"] = Time.get_unix_time_from_system()
	data["version"] = 1
	return data


## Validate a save dictionary. Returns array of issues found.
func validate_save(data: Dictionary) -> Array:
	var issues: Array = []

	# Check required keys
	for key in REQUIRED_KEYS:
		if not data.has(key):
			issues.append("Missing required key: %s" % key)

	# Check value ranges
	for key in VALID_RANGES:
		if data.has(key):
			var val = data[key]
			if val is float or val is int:
				var range_arr: Array = VALID_RANGES[key]
				if float(val) < range_arr[0] or float(val) > range_arr[1]:
					issues.append("Out of range: %s = %s (expected %s-%s)" % [
						key, str(val), str(range_arr[0]), str(range_arr[1])])

	# Check for impossible states
	if data.get("player_alive", true) == false and data.get("player_health", 0.0) > 0:
		issues.append("Inconsistent: player dead but health > 0")

	if data.get("witness_mode", false) and not data.get("save_closed", false):
		issues.append("Inconsistent: witness mode without save_closed")

	# Check god stability ranges
	var god_stability = data.get("god_stability", {})
	if god_stability is Dictionary:
		for god_id in god_stability:
			var stab = god_stability[god_id]
			if stab is float or stab is int:
				if float(stab) < 0.0 or float(stab) > 100.0:
					issues.append("God stability out of range: %s = %s" % [god_id, str(stab)])

	# Check faction reputation ranges
	var factions = data.get("factions", {})
	if factions is Dictionary:
		for fac_id in factions:
			var rep = factions[fac_id]
			if rep is float or rep is int:
				if float(rep) < -100.0 or float(rep) > 100.0:
					issues.append("Faction rep out of range: %s = %s" % [fac_id, str(rep)])

	return issues


## Attempt to repair a save with known issues.
func repair_save(data: Dictionary, issues: Array) -> Dictionary:
	var repaired := data.duplicate(true)

	for issue in issues:
		var issue_str: String = str(issue)

		# Fix missing keys with defaults
		if issue_str.begins_with("Missing required key:"):
			var key := issue_str.split(": ")[1]
			match key:
				"faith", "truth", "violence":
					repaired[key] = 0.0
				"player_health":
					repaired[key] = 100.0
				"player_alive":
					repaired[key] = true

		# Fix out of range values by clamping
		if issue_str.begins_with("Out of range:"):
			var parts := issue_str.split(" = ")
			if parts.size() >= 1:
				var key := parts[0].split(": ")[1]
				if VALID_RANGES.has(key):
					var range_arr: Array = VALID_RANGES[key]
					repaired[key] = clampf(float(repaired.get(key, 0.0)), range_arr[0], range_arr[1])

		# Fix inconsistent states
		if issue_str == "Inconsistent: player dead but health > 0":
			repaired["player_alive"] = true

		if issue_str == "Inconsistent: witness mode without save_closed":
			repaired["save_closed"] = true

		# Fix god stability
		if issue_str.begins_with("God stability out of range:"):
			var parts := issue_str.split(": ")
			if parts.size() >= 3:
				var god_parts := parts[2].split(" = ")
				if god_parts.size() >= 1:
					var god_id := god_parts[0]
					if repaired.has("god_stability") and repaired["god_stability"] is Dictionary:
						repaired["god_stability"][god_id] = clampf(
							float(repaired["god_stability"].get(god_id, 50.0)), 0.0, 100.0)

		# Fix faction rep
		if issue_str.begins_with("Faction rep out of range:"):
			var parts := issue_str.split(": ")
			if parts.size() >= 3:
				var fac_parts := parts[2].split(" = ")
				if fac_parts.size() >= 1:
					var fac_id := fac_parts[0]
					if repaired.has("factions") and repaired["factions"] is Dictionary:
						repaired["factions"][fac_id] = clampf(
							float(repaired["factions"].get(fac_id, 0.0)), -100.0, 100.0)

	save_repaired.emit(issues)
	return repaired


## Safe save — wraps the save process with integrity checks.
func safe_save() -> bool:
	if _save_in_progress:
		return false
	_save_in_progress = true

	# Set crash flag before writing
	_set_crash_flag(true)

	# Build state
	var data := _build_full_state()

	# Validate before writing
	var issues := validate_save(data)
	if issues.size() > 0:
		data = repair_save(data, issues)

	# Backup current save first
	_backup_current_save()

	# Write save
	var success := _write_save(data)

	# Clear crash flag
	_set_crash_flag(false)

	_save_in_progress = false
	return success


## Safe load — wraps the load process with integrity checks and fallbacks.
func safe_load() -> Dictionary:
	# Try primary save
	var data := _read_save(SAVE_PATH)
	if data.size() > 0:
		var issues := validate_save(data)
		if issues.size() == 0:
			return data
		# Attempt repair
		var repaired := repair_save(data, issues)
		var recheck := validate_save(repaired)
		if recheck.size() == 0:
			WorldMemory.record_ambient("Save was damaged. The world stuttered, then recovered.")
			return repaired

	# Primary save failed — try backup
	data = _read_save(BACKUP_PATH)
	if data.size() > 0:
		var issues := validate_save(data)
		if issues.size() == 0:
			WorldMemory.record_ambient("The world rewound slightly. Something was lost.")
			return data
		var repaired := repair_save(data, issues)
		var recheck := validate_save(repaired)
		if recheck.size() == 0:
			return repaired

	# Backup failed — try snapshot
	data = _read_save(SNAPSHOT_PATH)
	if data.size() > 0:
		var issues := validate_save(data)
		if issues.size() == 0:
			snapshot_restored.emit("Primary and backup saves corrupted")
			WorldMemory.record_ambient("The world collapsed and rebuilt from fragments. Much was lost.")
			return data

	# Everything failed — return empty (fresh start)
	save_corrupted.emit("All saves corrupted — starting fresh")
	return {}


## Check for crash recovery on startup.
func _check_crash_recovery() -> void:
	if not FileAccess.file_exists(CRASH_FLAG_PATH):
		return

	# Crash flag exists — previous save was interrupted
	_set_crash_flag(false)  # Clear it

	# Try to load from backup or snapshot
	var data := _read_save(BACKUP_PATH)
	if data.size() > 0:
		var issues := validate_save(data)
		if issues.size() == 0:
			# Backup is good — overwrite corrupted primary
			_write_save(data)
			WorldMemory.record("crash_recovery_backup")
			return

	# Try snapshot
	data = _read_save(SNAPSHOT_PATH)
	if data.size() > 0:
		_write_save(data)
		WorldMemory.record("crash_recovery_snapshot")


func _set_crash_flag(active: bool) -> void:
	if active:
		var file := FileAccess.open(CRASH_FLAG_PATH, FileAccess.WRITE)
		if file:
			file.store_string("crash")
			file.close()
	else:
		if FileAccess.file_exists(CRASH_FLAG_PATH):
			DirAccess.remove_absolute(CRASH_FLAG_PATH)


func _backup_current_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var content := file.get_as_text()
			file.close()
			var backup := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
			if backup:
				backup.store_string(content)
				backup.close()


func _write_save(data: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		return true
	return false


func _write_snapshot(data: Dictionary) -> void:
	var file := FileAccess.open(SNAPSHOT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}
