## QuestLogUI — Displays active and completed quests. Toggle with Tab.
extends Control

@onready var quest_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer/QuestList
@onready var detail_panel: VBoxContainer = $Panel/MarginContainer/VBoxContainer/DetailPanel
@onready var detail_title: Label = $Panel/MarginContainer/VBoxContainer/DetailPanel/DetailTitle
@onready var detail_desc: Label = $Panel/MarginContainer/VBoxContainer/DetailPanel/DetailDesc
@onready var detail_objectives: VBoxContainer = $Panel/MarginContainer/VBoxContainer/DetailPanel/ObjectiveList

var _selected_quest_id: String = ""


func _ready() -> void:
	visible = false
	QuestManager.quest_accepted.connect(_on_quest_changed)
	QuestManager.quest_updated.connect(func(_a, _b): _refresh())
	QuestManager.quest_completed.connect(_on_quest_changed)
	detail_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quest_log"):
		visible = not visible
		if visible:
			_refresh()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_tree().call_group("player", "set_input_enabled", false)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_tree().call_group("player", "set_input_enabled", true)


func _on_quest_changed(_quest_id: String) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
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
	btn.pressed.connect(func(): _select_quest(qid))
	quest_list.add_child(btn)


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

	var objectives: Array = q.get("objectives", [])
	for obj in objectives:
		var label := Label.new()
		var done: bool = obj.get("completed", false)
		label.text = ("[x] " if done else "[ ] ") + obj.get("description", "")
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.4) if done else Color(0.8, 0.8, 0.8))
		detail_objectives.add_child(label)
