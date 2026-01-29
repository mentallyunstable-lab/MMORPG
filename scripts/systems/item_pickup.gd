## ItemPickup — World object that grants an item when interacted with.
## Optionally notifies QuestManager of a "collect" event.
class_name ItemPickup
extends Interactable

@export var item_id: String = ""
@export var item_count: int = 1
@export var quest_target_id: String = ""  # If set, notifies quest system


func _ready() -> void:
	super._ready()
	one_time = true
	if item_id != "":
		interaction_text = "Pick up %s" % ItemManager.get_item_name(item_id)
	else:
		interaction_text = "Pick up"


func _on_interact(_player: Node) -> void:
	if item_id == "":
		return

	var success := ItemManager.add_item(item_id, item_count)
	if not success:
		return

	if quest_target_id != "":
		QuestManager.notify_event("collect", quest_target_id)

	# Hide the object
	visible = false
	set_process(false)
