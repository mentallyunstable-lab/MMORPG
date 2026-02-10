## JournalViolence — The journal does not record. It interprets. It rewrites. It forgets.
##
## 3.1 Journal Violence:
##   - Journal auto-fills INTERPRETATIONS, not events
##   - Earlier entries get retrofitted tone changes over time
##   - Key sentences replaced with "(you thought this mattered)"
##   - No undo. No history. No comparison mode.
##
## 3.2 Memory Conflicts:
##   - NPC references events with swapped cause/effect
##   - Two NPCs recall same moment with inverted emotions
##   - Keeper never corrects — only asks neutral questions
##
## 11 Journal Hostility:
##   - Cursor briefly lags when hovering over "important" entries
##   - Scroll position subtly resets when player reopens the journal
##   - One entry per chapter becomes unselectable (no error, no highlight)
##   - Keeper-related entries are ALWAYS selectable
##
## This system modifies GameState._journal_entries directly.
## The player never sees the original. There is no original.
extends Node

signal journal_corrupted(entry_index: int, old_text: String, new_text: String)
signal journal_entry_replaced(entry_index: int, replacement: String)
signal memory_conflict_injected(npc_a_version: String, npc_b_version: String)
signal journal_hostility_updated  # 11: Emitted when unselectable entries change

# --- Tone Retrofit ---
# Earlier entries gradually shift tone as trust degrades.
# Hopeful entries become cynical. Neutral entries become suspicious.
const RETROFIT_CHECK_INTERVAL := 60.0  # Check every 60 seconds
var _retrofit_timer: float = 0.0
const RETROFIT_CHANCE_PER_CHECK := 0.08  # 8% chance per check to retrofit an entry

# Tone shift mappings — applied to older entries
const TONE_REPLACEMENTS := {
	"seemed honest": "seemed nervous",
	"was helpful": "was evasive",
	"told me": "claimed",
	"I believe": "I thought",
	"nothing unusual": "something felt off",
	"stable": "too stable",
	"safe": "suspiciously safe",
	"I trust": "I trusted",
	"reliable": "seemingly reliable",
	"friendly": "overly friendly",
	"calm": "unnervingly calm",
	"normal": "superficially normal",
}

# --- Sentence Replacement ---
# Key sentences get replaced with dismissive meta-commentary.
const REPLACEMENT_INTERVAL := 120.0  # Check every 2 minutes
var _replacement_timer: float = 0.0
const REPLACEMENT_CHANCE := 0.05  # 5% chance per check

const REPLACEMENTS := [
	"(you thought this mattered)",
	"(this seemed important at the time)",
	"(you wrote this down as if it would help)",
	"(the details have blurred)",
	"(you were so sure about this)",
	"(this entry no longer makes sense to you)",
]

# --- Memory Conflict Templates ---
# For NPC dialogue injection — cause/effect swaps, emotion inversions
const CAUSE_EFFECT_SWAPS := [
	{
		"original": "The silence came because the gods pressed down.",
		"swapped": "The gods pressed down because of the silence.",
	},
	{
		"original": "Violence rose after the faction turned hostile.",
		"swapped": "The faction turned hostile after violence rose.",
	},
	{
		"original": "Trust fell because too many lies were told.",
		"swapped": "Too many lies were told because trust had fallen.",
	},
	{
		"original": "The Keeper went silent when pressure was high.",
		"swapped": "Pressure rose when the Keeper went silent.",
	},
	{
		"original": "NPCs became distant after the world changed.",
		"swapped": "The world changed after NPCs became distant.",
	},
]

const EMOTION_INVERSIONS := [
	{
		"npc_a": "I remember that moment with dread. Everything was falling apart.",
		"npc_b": "I remember that moment with relief. We were finally getting somewhere.",
	},
	{
		"npc_a": "It was terrifying when the Keeper fell silent.",
		"npc_b": "It was calming when the Keeper fell silent. The pressure lifted.",
	},
	{
		"npc_a": "The shrine gave me hope. I felt the force shift.",
		"npc_b": "The shrine made me sick. The force shifted too fast.",
	},
	{
		"npc_a": "When the god stirred, I felt protected.",
		"npc_b": "When the god stirred, I felt hunted.",
	},
]


# ============================================================
# 11 — JOURNAL HOSTILITY
# ============================================================
# The journal fights back. Not with errors — with friction.
# Cursor lags on "important" entries. Scroll resets on reopen.
# One entry per chapter becomes unselectable. No explanation.
# Keeper-related entries are ALWAYS selectable.

## Indices of entries that are currently unselectable (no error, just... won't select)
var _unselectable_indices: Array[int] = []

## How many "chapters" (groups of entries) we track for unselectability
const ENTRIES_PER_CHAPTER := 5

## Scroll reset: tracks whether the next journal open should reset scroll
var _should_reset_scroll: bool = false
var _journal_open_count: int = 0

## Important entry keywords — hovering these entries feels sluggish
const IMPORTANT_KEYWORDS := [
	"keeper", "truth", "silence", "gods", "trust", "betrayal",
	"lied", "honest", "remember", "forgot", "promise", "never",
]

## How much cursor lag to add on important entries (seconds of input delay)
const CURSOR_LAG_AMOUNT := 0.08  # 80ms — noticeable but not infuriating


func _ready() -> void:
	GameState.journal_entry_added.connect(_on_journal_entry_added)


func _process(delta: float) -> void:
	if DevToggles and (DevToggles.disable_psychological_hooks or DevToggles.disable_journal_violence):
		return

	_retrofit_timer += delta
	if _retrofit_timer >= RETROFIT_CHECK_INTERVAL:
		_retrofit_timer = 0.0
		_maybe_retrofit_entries()

	_replacement_timer += delta
	if _replacement_timer >= REPLACEMENT_INTERVAL:
		_replacement_timer = 0.0
		_maybe_replace_entry()


## When a new journal entry is added, it's already an interpretation (handled by npc_base).
## Here we add additional corruption on top.
func _on_journal_entry_added(_text: String) -> void:
	# After a new entry, check if we should also corrupt an older one
	if randf() < 0.15:
		_maybe_retrofit_entries()


## Scan older journal entries and shift their tone.
func _maybe_retrofit_entries() -> void:
	var entries := GameState.get_journal_entries()
	if entries.size() < 3:
		return  # Need enough entries for it to matter

	var trust := TrustDestruction.trust_level
	if trust > 0.7:
		return  # Don't retrofit at high trust

	# Pick a random older entry (not the latest 2)
	var max_idx := entries.size() - 3
	if max_idx < 0:
		return
	var target_idx := randi() % (max_idx + 1)

	if randf() >= RETROFIT_CHANCE_PER_CHECK:
		return

	var entry: Dictionary = entries[target_idx]
	var old_text: String = entry.get("text", "")
	var new_text := old_text

	# Apply tone shifts
	for original_phrase in TONE_REPLACEMENTS:
		var replacement_phrase: String = TONE_REPLACEMENTS[original_phrase]
		if original_phrase in new_text.to_lower():
			new_text = new_text.replace(original_phrase, replacement_phrase)
			# Also try capitalized version
			new_text = new_text.replace(
				original_phrase.capitalize(),
				replacement_phrase.capitalize()
			)
			break  # One shift per retrofit

	if new_text != old_text:
		entries[target_idx]["text"] = new_text
		journal_corrupted.emit(target_idx, old_text, new_text)


## Replace a random older entry with dismissive meta-commentary.
func _maybe_replace_entry() -> void:
	var entries := GameState.get_journal_entries()
	if entries.size() < 5:
		return

	var trust := TrustDestruction.trust_level
	if trust > 0.5:
		return  # Only at low trust

	if randf() >= REPLACEMENT_CHANCE:
		return

	# Pick a random entry from the middle (not first 2 or last 2)
	var min_idx := 2
	var max_idx := entries.size() - 3
	if max_idx <= min_idx:
		return
	var target_idx := randi_range(min_idx, max_idx)

	var entry: Dictionary = entries[target_idx]
	# Don't replace already-replaced entries
	if entry.get("text", "").begins_with("("):
		return

	var replacement: String = REPLACEMENTS[randi() % REPLACEMENTS.size()]
	var old_text: String = entry.get("text", "")
	entries[target_idx]["text"] = replacement
	journal_entry_replaced.emit(target_idx, replacement)


## Get a cause/effect swap for NPC dialogue injection.
## Returns a dictionary with "original" and "swapped" keys, or empty dict.
func get_cause_effect_swap() -> Dictionary:
	if CAUSE_EFFECT_SWAPS.is_empty():
		return {}
	return CAUSE_EFFECT_SWAPS[randi() % CAUSE_EFFECT_SWAPS.size()]


## Get an emotion inversion pair for two NPCs.
## Returns a dictionary with "npc_a" and "npc_b" keys, or empty dict.
func get_emotion_inversion() -> Dictionary:
	if EMOTION_INVERSIONS.is_empty():
		return {}
	return EMOTION_INVERSIONS[randi() % EMOTION_INVERSIONS.size()]


## Get a swapped memory version for NPC dialogue.
## The NPC states the swapped version as if it's what they remember.
func get_swapped_memory_line() -> String:
	var swap := get_cause_effect_swap()
	if swap.is_empty():
		return ""
	return swap.get("swapped", "")


# ============================================================
# 11 — JOURNAL HOSTILITY: QUERY API
# ============================================================

## Called when journal UI opens. Updates unselectable entries and scroll reset.
func on_journal_opened() -> void:
	if DevToggles and DevToggles.disable_journal_hostility:
		return
	_journal_open_count += 1
	# Scroll reset: every other open, the scroll position should reset
	# Not every time — that would be obvious. Every 2-3 opens.
	if _journal_open_count % randi_range(2, 3) == 0:
		_should_reset_scroll = true
	else:
		_should_reset_scroll = false
	_update_unselectable_entries()


## Should the journal UI reset its scroll position to the top?
## Returns true once, then resets. The UI calls this once on open.
func should_reset_scroll() -> bool:
	if DevToggles and DevToggles.disable_journal_hostility:
		return false
	if _should_reset_scroll:
		_should_reset_scroll = false
		return true
	return false


## Is this entry index currently unselectable?
## Returns true if the entry should silently refuse selection.
## No error message, no highlight change — it just doesn't respond.
func is_entry_unselectable(index: int) -> bool:
	if DevToggles and DevToggles.disable_journal_hostility:
		return false
	return index in _unselectable_indices


## Does this entry text warrant cursor lag?
## Returns the lag amount in seconds, or 0.0 if no lag.
func get_entry_cursor_lag(entry_text: String) -> float:
	if DevToggles and DevToggles.disable_journal_hostility:
		return 0.0
	var text_lower := entry_text.to_lower()
	for keyword in IMPORTANT_KEYWORDS:
		if keyword in text_lower:
			return CURSOR_LAG_AMOUNT
	return 0.0


## Recalculate which entries are unselectable.
## One entry per "chapter" (group of N entries) becomes unselectable.
## Keeper-related entries are ALWAYS selectable — the one thing that works.
func _update_unselectable_entries() -> void:
	_unselectable_indices.clear()
	var entries := GameState.get_journal_entries()
	if entries.size() < ENTRIES_PER_CHAPTER:
		return

	var trust := TrustDestruction.trust_level
	if trust > 0.6:
		return  # Only at lower trust

	# For each chapter (group of ENTRIES_PER_CHAPTER), pick one to make unselectable
	var chapter_count := entries.size() / ENTRIES_PER_CHAPTER
	for chapter in range(chapter_count):
		var start_idx := chapter * ENTRIES_PER_CHAPTER
		var end_idx := mini(start_idx + ENTRIES_PER_CHAPTER, entries.size())

		# Collect candidates (not Keeper-related)
		var candidates: Array[int] = []
		for i in range(start_idx, end_idx):
			var text: String = entries[i].get("text", "").to_lower()
			# Keeper entries are ALWAYS selectable
			if "keeper" in text:
				continue
			# Already-replaced entries are already hostile enough
			if text.begins_with("("):
				continue
			candidates.append(i)

		if candidates.size() > 0:
			# Deterministic pick based on chapter index (consistent between opens)
			var pick := candidates[chapter % candidates.size()]
			_unselectable_indices.append(pick)

	journal_hostility_updated.emit()


# --- Persistence ---
# Unselectable indices recalculated on each journal open — no persistence needed.

func save_state() -> Dictionary:
	return {
		"journal_open_count": _journal_open_count,
	}


func load_state(data: Dictionary) -> void:
	_journal_open_count = data.get("journal_open_count", 0)
