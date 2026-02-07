## DevToggles — Kill switches for testing sanity.
## Toggle individual systems on/off at runtime without code changes.
## Registered FIRST in autoload order so all other systems can reference it.
##
## --- INTERNAL POSTMORTEM (F2) ---
##
## What the Keeper is NOT:
##   Not a reward. Not a safety net. Not a game mechanic the player "unlocks."
##   The Keeper is the last real thing in a world that has forgotten what real means.
##   If you treat it as a tool, you've already lost what it offers.
##   If you treat it as a crutch, it will let you lean — and say nothing about the fall.
##
## What truth cannot do:
##   It cannot protect you. Knowing the fire is hot does not stop the burn.
##   It cannot undo what you chose. The Keeper told you what was real.
##   What you built from it was yours.
##   It cannot make you right. Being correct and being wise are not the same thing.
##   Truth is a mirror. It shows you the world. It does not show you what to do.
##
## Where the system is intentionally unfair:
##   - Silence fallout timing: The delayed rumor spike can compound with natural
##     trust decay in ways that feel arbitrary. This is by design.
##   - Delayed validation cruelty: The player learns they were right only after
##     they've already paid the price for being ignored. No fanfare. No reward.
##   - False relief cycles: The first visit after a streak feels cheaper.
##     The second one doesn't. The player learns the wrong lesson first.
##   - NPC memory conflicts during silence: Two NPCs remember different versions
##     of what happened. Neither is lying. Both are wrong.
##
## --- ONE UNTOUCHED FLAW (F3) ---
##
## Silence fallout timing is not balanced.
## The delayed rumor spike (5–10 minutes after silence ends) can stack with
## the natural trust decay window in ways that create compound damage the
## player has no way to anticipate or prevent.
##
## This is intentional. This will not be balanced.
##
## Why: The player should feel that silence left marks they didn't consent to.
## If the timing were fair, it would feel mechanical instead of traumatic.
## Silence is not a system. Silence is an absence. Absences leave ragged edges.
## The player's discomfort at the unfairness IS the point.
## If they could predict it, they'd optimize around it, and silence would become
## just another cooldown to manage. It must remain something that happened TO them.
extends Node

# --- System Kill Switches ---
# Set any of these to true to disable the corresponding system.
# Used during testing to isolate system behavior.

## Disables the false anchor system entirely (C3).
var disable_false_anchor: bool = false

## Disables silence fallout effects (A3 extensions + original).
var disable_silence_fallout: bool = false

## Disables anti-save-scum detection and adjustment (D1).
var disable_anti_save_scum: bool = false

## Disables NPC language degradation (E2).
var disable_language_degradation: bool = false

## Disables delayed consequence system in anti-save-scum (D1).
var disable_delayed_consequences: bool = false

## Disables dialogue timing manipulation (E1 micro-delays, pauses, cut-short).
var disable_dialogue_timing: bool = false

## Disables NPC agency doubt lines and reflective questions (A2, E3).
var disable_psychological_hooks: bool = false


func _ready() -> void:
	pass


# --- Debug API ---

func get_debug_info() -> Dictionary:
	return {
		"disable_false_anchor": disable_false_anchor,
		"disable_silence_fallout": disable_silence_fallout,
		"disable_anti_save_scum": disable_anti_save_scum,
		"disable_language_degradation": disable_language_degradation,
		"disable_delayed_consequences": disable_delayed_consequences,
		"disable_dialogue_timing": disable_dialogue_timing,
		"disable_psychological_hooks": disable_psychological_hooks,
	}


## Toggle a specific system. Returns the new state.
func toggle(system_name: String) -> bool:
	match system_name:
		"false_anchor":
			disable_false_anchor = not disable_false_anchor
			return disable_false_anchor
		"silence_fallout":
			disable_silence_fallout = not disable_silence_fallout
			return disable_silence_fallout
		"anti_save_scum":
			disable_anti_save_scum = not disable_anti_save_scum
			return disable_anti_save_scum
		"language_degradation":
			disable_language_degradation = not disable_language_degradation
			return disable_language_degradation
		"delayed_consequences":
			disable_delayed_consequences = not disable_delayed_consequences
			return disable_delayed_consequences
		"dialogue_timing":
			disable_dialogue_timing = not disable_dialogue_timing
			return disable_dialogue_timing
		"psychological_hooks":
			disable_psychological_hooks = not disable_psychological_hooks
			return disable_psychological_hooks
	push_warning("DevToggles: unknown system '%s'" % system_name)
	return false
