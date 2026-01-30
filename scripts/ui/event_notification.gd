## EventNotification — Displays world event notifications as fading banners.
extends Control

@onready var container: VBoxContainer = $NotificationContainer

const MAX_VISIBLE := 3
const DISPLAY_TIME := 5.0
const FADE_TIME := 1.0


func _ready() -> void:
	WorldEventManager.event_notification.connect(_on_event_notification)


func _exit_tree() -> void:
	if WorldEventManager and WorldEventManager.event_notification.is_connected(_on_event_notification):
		WorldEventManager.event_notification.disconnect(_on_event_notification)


func _on_event_notification(title: String, description: String) -> void:
	if title == "" and description == "":
		return

	# Build notification panel
	var panel := PanelContainer.new()
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	stylebox.border_width_left = 3
	stylebox.border_color = _get_border_color(title)
	stylebox.content_margin_left = 16.0
	stylebox.content_margin_right = 16.0
	stylebox.content_margin_top = 10.0
	stylebox.content_margin_bottom = 10.0
	stylebox.corner_radius_top_left = 2
	stylebox.corner_radius_bottom_left = 2
	panel.add_theme_stylebox_override("panel", stylebox)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title_label := Label.new()
	title_label.text = title.to_upper()
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", _get_border_color(title))
	vbox.add_child(title_label)

	if description != "":
		var desc_label := Label.new()
		desc_label.text = description
		desc_label.add_theme_font_size_override("font_size", 11)
		desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size.x = 350.0
		vbox.add_child(desc_label)

	container.add_child(panel)
	panel.modulate.a = 0.0

	# Fade in
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(DISPLAY_TIME)
	tween.tween_property(panel, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(panel.queue_free)

	# Limit visible notifications
	while container.get_child_count() > MAX_VISIBLE:
		var oldest := container.get_child(0)
		oldest.queue_free()


func _get_border_color(title: String) -> Color:
	var t := title.to_lower()
	if "faith" in t or "miracle" in t or "god" in t or "holy" in t:
		return Color(0.6, 0.7, 1.0)
	elif "truth" in t or "veil" in t or "reality" in t or "revolution" in t:
		return Color(1.0, 1.0, 0.6)
	elif "violence" in t or "war" in t or "bleed" in t or "hostile" in t:
		return Color(1.0, 0.4, 0.3)
	elif "ash" in t or "pressure" in t or "corrupt" in t:
		return Color(0.7, 0.5, 0.3)
	else:
		return Color(0.6, 0.6, 0.6)
