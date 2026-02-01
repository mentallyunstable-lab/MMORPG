## EventNotification — Displays world event notifications as fading banners.
## Phase 6: Rate-limited to prevent notification fatigue. Colorblind-safe borders.
extends Control

@onready var container: VBoxContainer = $NotificationContainer

const MAX_VISIBLE := 3
const DISPLAY_TIME := 5.0
const FADE_TIME := 1.0

# --- Phase 6: Notification Rate Limiting ---
# Cap noise: maximum notifications per window to prevent fatigue.
const RATE_LIMIT_WINDOW := 10.0  # Seconds
const RATE_LIMIT_MAX := 4  # Max notifications per window
var _notification_timestamps: Array[float] = []
var _suppressed_count: int = 0


func _ready() -> void:
	WorldEventManager.event_notification.connect(_on_event_notification)


func _exit_tree() -> void:
	if WorldEventManager and WorldEventManager.event_notification.is_connected(_on_event_notification):
		WorldEventManager.event_notification.disconnect(_on_event_notification)


func _on_event_notification(title: String, description: String) -> void:
	if title == "" and description == "":
		return

	# Rate limiting: prevent notification spam
	var now := Time.get_ticks_msec() / 1000.0
	_notification_timestamps.append(now)
	# Prune old timestamps
	while _notification_timestamps.size() > 0 and now - _notification_timestamps[0] > RATE_LIMIT_WINDOW:
		_notification_timestamps.pop_front()
	# Check rate limit
	if _notification_timestamps.size() > RATE_LIMIT_MAX:
		_suppressed_count += 1
		# Show suppressed count periodically
		if _suppressed_count == 3:
			_show_notification("...", "The world has more to say. It will wait.", Color(0.5, 0.5, 0.5))
			_suppressed_count = 0
		return

	_suppressed_count = 0
	var border_color := _get_border_color(title)
	_show_notification(title, description, border_color)


func _show_notification(title: String, description: String, border_color: Color) -> void:
	# Build notification panel
	var panel := PanelContainer.new()
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	stylebox.border_width_left = 3
	stylebox.border_color = border_color
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
	title_label.add_theme_color_override("font_color", border_color)
	vbox.add_child(title_label)

	if description != "":
		var desc_label := Label.new()
		desc_label.text = description
		desc_label.add_theme_font_size_override("font_size", 11)
		# Colorblind safety: use high-contrast text (not relying on color alone)
		desc_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
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


## Colorblind-safe border colors — uses both color AND brightness/saturation
## differences to remain distinguishable under protanopia/deuteranopia/tritanopia.
func _get_border_color(title: String) -> Color:
	var t := title.to_lower()
	if "faith" in t or "miracle" in t or "god" in t or "holy" in t or "ash mother" in t:
		# Faith: bright blue-white (visible to all color blindness types)
		return Color(0.5, 0.65, 1.0)
	elif "truth" in t or "veil" in t or "reality" in t or "revolution" in t or "blind sun" in t:
		# Truth: high-brightness yellow (distinguishable from blue)
		return Color(1.0, 0.95, 0.5)
	elif "violence" in t or "war" in t or "bleed" in t or "hostile" in t or "blood" in t:
		# Violence: desaturated orange-red (avoids pure red for protanopia)
		return Color(0.95, 0.45, 0.25)
	elif "ash" in t or "pressure" in t or "corrupt" in t:
		return Color(0.7, 0.5, 0.3)
	elif "divine" in t or "judgment" in t:
		return Color(0.8, 0.7, 0.9)
	elif t == "" or "???" in t or "..." in t:
		# Mystery/unknown: dim white
		return Color(0.55, 0.55, 0.55)
	elif "witness" in t or "end" in t:
		# Ending: pure white, high contrast
		return Color(0.9, 0.9, 0.9)
	else:
		return Color(0.6, 0.6, 0.6)
