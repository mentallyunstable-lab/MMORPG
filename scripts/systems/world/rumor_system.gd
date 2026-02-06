extends Node
## RumorSystem - NPC rumor propagation with decay and mutation
##
## PRIORITY #11
## "NPCs should disagree subtly, not loudly."
##
## Requirements:
## - Rumor half-life
## - NPC belief strength
## - Mutation over distance/time
## - Rare contradictions that hint at lies

signal rumor_created(rumor_id: String)
signal rumor_spread(rumor_id: String, from_npc: String, to_npc: String)
signal rumor_mutated(rumor_id: String, mutation_type: String)
signal rumor_died(rumor_id: String)
signal contradiction_emerged(rumor_a: String, rumor_b: String)

## Rumor data
class Rumor:
	var id: String
	var content: String
	var original_content: String
	var source_type: String  # "event", "npc", "consequence_hint", "god"
	var created_time: float
	var half_life: float  # Seconds until rumor strength halves
	var mutation_count: int = 0
	var spread_count: int = 0

	## NPC beliefs about this rumor
	var npc_beliefs: Dictionary = {}  # npc_id -> belief_strength (0.0 to 1.0)


## Active rumors
var rumors: Dictionary = {}  # rumor_id -> Rumor

## Configuration
@export var base_half_life: float = 600.0  # 10 minutes
@export var mutation_chance_per_spread: float = 0.15
@export var contradiction_chance: float = 0.05
@export var max_mutation_distance: int = 5  # Max mutations from original
@export var belief_decay_rate: float = 0.01  # Per second

## Mutation templates
var mutation_types: Array[String] = [
	"exaggeration",    # Numbers/severity increased
	"minimization",    # Numbers/severity decreased
	"detail_changed",  # Specific details altered
	"source_confused", # Who did it changed
	"location_shifted",# Where it happened changed
	"time_warped",     # When it happened changed
]


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	_decay_beliefs(delta)
	_check_rumor_deaths()


func inject_rumor(rumor_data: Dictionary) -> String:
	## Create a new rumor from external source

	var rumor := Rumor.new()
	rumor.id = _generate_rumor_id()
	rumor.content = rumor_data.get("content", "")
	rumor.original_content = rumor.content
	rumor.source_type = rumor_data.get("source", "event")
	rumor.created_time = Time.get_ticks_msec() / 1000.0
	rumor.half_life = rumor_data.get("half_life", base_half_life)

	rumors[rumor.id] = rumor

	rumor_created.emit(rumor.id)
	return rumor.id


func _generate_rumor_id() -> String:
	return "rmr_%d_%d" % [Time.get_ticks_msec(), randi()]


func spread_rumor(rumor_id: String, from_npc: String, to_npc: String) -> bool:
	## NPC shares rumor with another NPC

	if not rumor_id in rumors:
		return false

	var rumor: Rumor = rumors[rumor_id]

	# Get source NPC's belief strength
	var source_belief: float = rumor.npc_beliefs.get(from_npc, 0.5)

	# Target NPC's belief is influenced by source's conviction
	var target_belief := source_belief * randf_range(0.7, 1.0)

	# Check for mutation
	if randf() < mutation_chance_per_spread and rumor.mutation_count < max_mutation_distance:
		_mutate_rumor(rumor)

	# Check for contradiction emergence
	if randf() < contradiction_chance:
		_create_contradiction(rumor)

	# Update beliefs
	rumor.npc_beliefs[to_npc] = target_belief
	rumor.spread_count += 1

	rumor_spread.emit(rumor_id, from_npc, to_npc)
	return true


func _mutate_rumor(rumor: Rumor) -> void:
	## Apply a mutation to the rumor

	var mutation_type: String = mutation_types[randi() % mutation_types.size()]
	rumor.mutation_count += 1

	# Apply mutation to content
	rumor.content = _apply_mutation(rumor.content, mutation_type)

	rumor_mutated.emit(rumor.id, mutation_type)


func _apply_mutation(content: String, mutation_type: String) -> String:
	## Apply a specific mutation type to rumor content
	## TODO: Implement actual content mutation logic

	match mutation_type:
		"exaggeration":
			return content + " (greatly)"
		"minimization":
			return content + " (barely)"
		"detail_changed":
			return content + " (or so they say)"
		"source_confused":
			return content + " (though who knows who really...)"
		"location_shifted":
			return content + " (somewhere around there)"
		"time_warped":
			return content + " (recently, or was it long ago?)"

	return content


func _create_contradiction(original_rumor: Rumor) -> void:
	## Create a contradicting rumor - hints at lies in the world

	var contradiction := Rumor.new()
	contradiction.id = _generate_rumor_id()
	contradiction.content = _generate_contradiction_content(original_rumor.content)
	contradiction.original_content = contradiction.content
	contradiction.source_type = "contradiction"
	contradiction.created_time = Time.get_ticks_msec() / 1000.0
	contradiction.half_life = original_rumor.half_life * 0.5  # Contradictions die faster

	rumors[contradiction.id] = contradiction

	contradiction_emerged.emit(original_rumor.id, contradiction.id)


func _generate_contradiction_content(original: String) -> String:
	## Generate content that contradicts the original
	## TODO: Implement proper contradiction generation

	return "Some say the opposite: not " + original


func npc_tells_rumor(npc_id: String, listener_is_player: bool = false) -> Dictionary:
	## NPC tells a rumor they believe
	## Returns the rumor data or empty if NPC has nothing to share

	var best_rumor_id := ""
	var best_belief := 0.0

	for rumor_id in rumors:
		var rumor: Rumor = rumors[rumor_id]
		var belief: float = rumor.npc_beliefs.get(npc_id, 0.0)

		if belief > best_belief:
			best_belief = belief
			best_rumor_id = rumor_id

	if best_rumor_id == "" or best_belief < 0.2:
		return {}

	var rumor: Rumor = rumors[best_rumor_id]

	return {
		"rumor_id": best_rumor_id,
		"content": rumor.content,
		"npc_belief_strength": best_belief,
		"mutation_count": rumor.mutation_count,
		"is_heavily_mutated": rumor.mutation_count > 3,
	}


func _decay_beliefs(delta: float) -> void:
	## Beliefs decay over time

	for rumor_id in rumors:
		var rumor: Rumor = rumors[rumor_id]

		for npc_id in rumor.npc_beliefs:
			rumor.npc_beliefs[npc_id] -= belief_decay_rate * delta
			rumor.npc_beliefs[npc_id] = max(0.0, rumor.npc_beliefs[npc_id])


func _check_rumor_deaths() -> void:
	## Remove rumors that have completely faded

	var to_remove: Array[String] = []

	for rumor_id in rumors:
		var rumor: Rumor = rumors[rumor_id]

		# Check if any NPC still believes this
		var max_belief := 0.0
		for npc_id in rumor.npc_beliefs:
			max_belief = max(max_belief, rumor.npc_beliefs[npc_id])

		# Also check age vs half-life
		var age := (Time.get_ticks_msec() / 1000.0) - rumor.created_time
		var decay_factor := pow(0.5, age / rumor.half_life)

		if max_belief < 0.1 and decay_factor < 0.1:
			to_remove.append(rumor_id)

	for rumor_id in to_remove:
		rumors.erase(rumor_id)
		rumor_died.emit(rumor_id)


func get_npc_known_rumors(npc_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for rumor_id in rumors:
		var rumor: Rumor = rumors[rumor_id]
		var belief: float = rumor.npc_beliefs.get(npc_id, 0.0)

		if belief > 0.1:
			result.append({
				"rumor_id": rumor_id,
				"content": rumor.content,
				"belief_strength": belief,
				"mutation_count": rumor.mutation_count,
			})

	# Sort by belief strength
	result.sort_custom(func(a, b): return a["belief_strength"] > b["belief_strength"])
	return result


func get_rumor_stats() -> Dictionary:
	var total := rumors.size()
	var heavily_mutated := 0
	var total_spread := 0

	for rumor_id in rumors:
		var rumor: Rumor = rumors[rumor_id]
		if rumor.mutation_count > 3:
			heavily_mutated += 1
		total_spread += rumor.spread_count

	return {
		"active_rumors": total,
		"heavily_mutated": heavily_mutated,
		"total_spreads": total_spread,
		"average_mutations": float(heavily_mutated) / max(total, 1),
	}


func find_contradictions() -> Array[Dictionary]:
	## Find pairs of contradicting rumors for subtle NPC disagreements
	var contradictions: Array[Dictionary] = []

	for rumor_id in rumors:
		var rumor: Rumor = rumors[rumor_id]
		if rumor.source_type == "contradiction":
			# Find what it contradicts
			for other_id in rumors:
				if other_id != rumor_id:
					var other: Rumor = rumors[other_id]
					if rumor.content.contains(other.original_content) or other.content.contains(rumor.original_content):
						contradictions.append({
							"rumor_a": other_id,
							"rumor_b": rumor_id,
						})

	return contradictions
