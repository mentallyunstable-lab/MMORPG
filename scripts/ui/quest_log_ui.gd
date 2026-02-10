## QuestLogUI — Displays active and completed quests. Toggle with Tab.
## 11: Journal Hostility — the UI itself resists.
extends Control

@onready var quest_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer/QuestList
@onready var scroll_container: ScrollContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer
@onready var detail_panel: VBoxContainer = $Panel/MarginContainer/VBoxContainer/DetailPanel
@onready var detail_title: Label = $Panel/MarginContainer/VBoxContainer/DetailPanel/DetailTitle
@onready var detail_desc: Label = $Panel/MarginContainer/VBoxContainer/DetailPanel/DetailDesc
@onready var detail_objectives: VBoxContainer = $Panel/MarginContainer/VBoxContainer/DetailPanel/ObjectiveList

var _selected_quest_id: String = ""

# --- 11: Journal Hostility State ---
# Cursor lag: delays selection response on "important" entries
var _cursor_lag_timer: float = 0.0
var _cursor_lag_pending_action: Callable = Callable()
var _cursor_lag_active: bool = false


func _ready() -> void:
	visible = false
	QuestManager.quest_accepted.connect(_on_quest_changed)
	QuestManager.quest_updated.connect(func(_a, _b): _refresh())
	QuestManager.quest_completed.connect(_on_quest_changed)
	detail_panel.visible = false


func _exit_tree() -> void:
	if QuestManager:
		if QuestManager.quest_accepted.is_connected(_on_quest_changed):
			QuestManager.quest_accepted.disconnect(_on_quest_changed)
		if QuestManager.quest_completed.is_connected(_on_quest_changed):
			QuestManager.quest_completed.disconnect(_on_quest_changed)
		# quest_updated uses a lambda — cannot disconnect by reference; it auto-cleans on free


func _process(delta: float) -> void:
	# 11: Process cursor lag timer — delayed selection on important entries
	if _cursor_lag_active and _cursor_lag_timer > 0.0:
		_cursor_lag_timer -= delta
		if _cursor_lag_timer <= 0.0:
			_cursor_lag_active = false
			if _cursor_lag_pending_action.is_valid():
				_cursor_lag_pending_action.call()
				_cursor_lag_pending_action = Callable()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quest_log"):
		visible = not visible
		if visible:
			# 11: Notify JournalViolence that journal was opened
			if JournalViolence:
				JournalViolence.on_journal_opened()
			_refresh()
			# 11: Scroll reset — sometimes the journal "forgets" where you were
			if JournalViolence and JournalViolence.should_reset_scroll() and scroll_container:
				scroll_container.scroll_vertical = 0
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_tree().call_group("player", "set_input_enabled", false)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_tree().call_group("player", "set_input_enabled", true)


func _on_quest_changed(_quest_id: String) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	# Reset display index for journal hostility tracking
	_entry_display_index = 0

	# Clear old entries
	for child in quest_list.get_children():
		child.queue_free()

	# Active quests
	var active := QuestManager.get_active_quests()
	if active.size() > 0:
		_add_header("ACTIVE QUESTS")
		for q in active:
			_add_quest_entry(q, false)

	# Completed quests
	var completed: Array = []
	for qid in QuestManager.quests:
		if QuestManager.quests[qid]["state"] == QuestManager.QuestState.COMPLETED:
			completed.append(QuestManager.quests[qid])
	if completed.size() > 0:
		_add_header("COMPLETED")
		for q in completed:
			_add_quest_entry(q, true)

	if active.size() == 0 and completed.size() == 0:
		var empty := Label.new()
		empty.text = "No quests yet."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		quest_list.add_child(empty)


func _add_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	quest_list.add_child(label)


## Track the display index of each entry for journal hostility
var _entry_display_index: int = 0


func _add_quest_entry(quest_data: Dictionary, completed: bool) -> void:
	var btn := Button.new()
	var title: String = quest_data.get("title", "???")
	btn.text = ("[X] " if completed else "[ ] ") + title
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true

	# Color by force affinity
	var affinity: String = quest_data.get("force_affinity", "")
	match affinity:
		"faith":
			btn.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
		"truth":
			btn.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
		"violence":
			btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		_:
			btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

	if completed:
		btn.modulate.a = 0.5

	var qid: String = quest_data.get("id", "")
	var entry_idx := _entry_display_index
	_entry_display_index += 1

	# 11: Check if this entry is unselectable (silent — no visual indicator)
	var unselectable := false
	if JournalViolence:
		unselectable = JournalViolence.is_entry_unselectable(entry_idx)

	# 11: Determine cursor lag for this entry
	var cursor_lag := 0.0
	if JournalViolence:
		cursor_lag = JournalViolence.get_entry_cursor_lag(title)

	if unselectable:
		# Entry silently refuses to respond. No error. No visual change.
		# The button exists, looks normal, but does nothing.
		btn.pressed.connect(func(): pass)
	elif cursor_lag > 0.0:
		# Entry responds with a subtle delay — the UI hesitates
		btn.pressed.connect(func(): _select_quest_with_lag(qid, cursor_lag))
	else:
		btn.pressed.connect(func(): _select_quest(qid))
	quest_list.add_child(btn)


## 11: Select quest with cursor lag — the journal hesitates before showing details.
func _select_quest_with_lag(quest_id: String, lag: float) -> void:
	if _cursor_lag_active:
		return  # Already waiting
	_cursor_lag_active = true
	_cursor_lag_timer = lag
	_cursor_lag_pending_action = Callable(self, "_select_quest").bind(quest_id)


func _select_quest(quest_id: String) -> void:
	_selected_quest_id = quest_id
	var q: Dictionary = QuestManager.quests.get(quest_id, {})
	if q.is_empty():
		detail_panel.visible = false
		return

	detail_panel.visible = true
	detail_title.text = q.get("title", "???")
	detail_desc.text = q.get("description", "")

	# Clear old objectives
	for child in detail_objectives.get_children():
		child.queue_free()

	var is_completed: bool = q.get("state", 0) == QuestManager.QuestState.COMPLETED

	var objectives: Array = q.get("objectives", [])
	for obj in objectives:
		var label := Label.new()
		var done: bool = obj.get("completed", false)
		label.text = ("[x] " if done else "[ ] ") + obj.get("description", "")
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.4) if done else Color(0.8, 0.8, 0.8))
		detail_objectives.add_child(label)

	# Show rewards section
	var rewards: Dictionary = q.get("rewards", {})
	if not rewards.is_empty():
		var spacer := Control.new()
		spacer.custom_minimum_size.y = 8
		detail_objectives.add_child(spacer)

		var header := Label.new()
		header.text = "REWARDS" + (" (Collected)" if is_completed else "")
		header.add_theme_font_size_override("font_size", 11)
		header.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5) if is_completed else Color(0.7, 0.6, 0.3))
		detail_objectives.add_child(header)

		if rewards.has("force") and rewards.has("force_amount"):
			var rl := Label.new()
			rl.text = "  +%.0f %s" % [rewards["force_amount"], rewards["force"].capitalize()]
			rl.add_theme_font_size_override("font_size", 12)
			detail_objectives.add_child(rl)
		if rewards.has("faction") and rewards.has("faction_amount"):
			var rl := Label.new()
			rl.text = "  +%.0f %s rep" % [rewards["faction_amount"], rewards["faction"]]
			rl.add_theme_font_size_override("font_size", 12)
			detail_objectives.add_child(rl)
		if rewards.has("items"):
			for item_id in rewards["items"]:
				var rl := Label.new()
				rl.text = "  %s" % ItemManager.get_item_name(item_id)
				rl.add_theme_font_size_override("font_size", 12)
				detail_objectives.add_child(rl)
