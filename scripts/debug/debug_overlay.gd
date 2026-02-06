extends CanvasLayer
## DebugOverlay - Developer tools for system monitoring
##
## Shows real-time data for:
## - Betrayal pacing (Priority #3)
## - Force economy visualization (Priority #4)
## - God activity (Priority #5)
## - Haunt score interpretation (Priority #14)

var is_visible: bool = false

@onready var panel: Panel = $Panel
@onready var content: RichTextLabel = $Panel/Content


func _ready() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):  # F12 or similar
		toggle_visibility()


func toggle_visibility() -> void:
	is_visible = not is_visible
	visible = is_visible


func _process(delta: float) -> void:
	if not is_visible:
		return

	_update_display()


func _update_display() -> void:
	var text := "[b]ASHBORN DEBUG OVERLAY[/b]\n\n"

	# Betrayal Controller (Priority #3)
	text += "[color=red]═══ BETRAYAL PACING ═══[/color]\n"
	if BetrayalController:
		var betrayal_data := BetrayalController.get_debug_overlay_data()
		text += "Last Betrayal: %.1fs ago\n" % betrayal_data["time_since_last"]
		text += "Next Window: %.1fs\n" % betrayal_data["next_allowed_window"]
		text += "Active: %s\n" % str(betrayal_data["active_betrayals"])

		text += "\nCooldowns:\n"
		for category in betrayal_data["cooldowns_by_category"]:
			var cd: Dictionary = betrayal_data["cooldowns_by_category"][category]
			var status := "[color=green]READY[/color]" if cd["ready"] else "[color=yellow]%.1fs[/color]" % cd["remaining"]
			text += "  %s: %s\n" % [category, status]

	# Force Economy (Priority #4)
	text += "\n[color=orange]═══ FORCE ECONOMY ═══[/color]\n"
	if ForceEconomy:
		var force_data := ForceEconomy.get_force_visualization_data()
		var bar := _create_bar(force_data["percentage"])
		text += "Force: %s %.0f/%.0f\n" % [bar, force_data["current_force"], force_data["max_force"]]
		text += "Fatigue: %.1f%%\n" % (force_data["fatigue_level"] / force_data["max_force"] * 100)
		if force_data["emergency_active"]:
			text += "[color=red]⚠ EMERGENCY DECAY ACTIVE[/color]\n"

	# God Interference (Priority #5)
	text += "\n[color=purple]═══ GOD ACTIVITY ═══[/color]\n"
	if GodInterference:
		var interferences := GodInterference.get_all_active_interferences()
		text += "Active Interferences: %d\n" % interferences.size()
		for interference in interferences.slice(0, 5):  # Show first 5
			text += "  %s → %s (%s)\n" % [
				interference["god_name"],
				interference["target"],
				"LIE" if interference["is_lie"] else "truth"
			]

	# Witness Mode (Priority #8)
	text += "\n[color=cyan]═══ WITNESS MODE ═══[/color]\n"
	if WitnessMode:
		var witness_data := WitnessMode.get_witness_state()
		text += "Stage: %s (%d/6)\n" % [witness_data["current_stage"], witness_data["stage_number"]]
		text += "Intensity: %.1f%%\n" % (witness_data["intensity"] * 100)
		text += "UI Erosion: %.1f%% %s\n" % [
			witness_data["ui_erosion"] * 100,
			"[CAPPED]" if witness_data["ui_erosion_capped"] else ""
		]
		if witness_data["is_in_stillness"]:
			text += "[color=white]>>> FORCED STILLNESS <<<[/color]\n"

	# Haunt Score (Priority #14)
	text += "\n[color=magenta]═══ HAUNT SCORE ═══[/color]\n"
	if HauntScore:
		var haunt_data := HauntScore.get_haunt_metrics()
		var interpretation := HauntScore.get_interpretation()
		var bar := _create_bar(haunt_data["haunt_score"] / haunt_data["max_possible"])
		text += "Score: %s %.1f/%.1f\n" % [bar, haunt_data["haunt_score"], haunt_data["max_possible"]]
		text += "Threshold: %s\n" % interpretation["threshold"]
		text += "Pauses: %d (%.1f/min)\n" % [haunt_data["pause_count"], haunt_data["pause_rate"]]
		text += "Reloads: %d\n" % haunt_data["reload_count"]

	# Anchor Status (Priority #1)
	text += "\n[color=green]═══ ANCHOR ═══[/color]\n"
	if AnchorSystem:
		var anchor_info := AnchorSystem.get_anchor_info()
		if anchor_info["configured"]:
			text += "Type: %s\n" % anchor_info["type"]
			text += "Present: %s\n" % ("YES" if anchor_info["is_present"] else "NO")
			text += "Silent: %s\n" % ("YES" if anchor_info["is_silent"] else "NO")
		else:
			text += "[color=red]⚠ NOT CONFIGURED[/color]\n"

	# First 90 Minutes (Priority #16)
	if GameManager and GameManager.is_in_first_90_minutes():
		text += "\n[color=yellow]═══ FIRST 90 MIN ═══[/color]\n"
		var first_90 := GameManager.get_first_90_completion()
		text += "Lie: %s\n" % ("✓" if first_90["lie_delivered"] else "○")
		text += "Silence: %s\n" % ("✓" if first_90["silence_delivered"] else "○")
		text += "Refusal: %s\n" % ("✓" if first_90["refusal_delivered"] else "○")

	if content:
		content.text = text


func _create_bar(percentage: float, width: int = 20) -> String:
	var filled := int(percentage * width)
	var empty := width - filled
	return "[" + "█".repeat(filled) + "░".repeat(empty) + "]"
