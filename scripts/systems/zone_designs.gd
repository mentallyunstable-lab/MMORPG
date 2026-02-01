## ZoneDesigns — Brutal detail for every zone in Ashborn.
## This is the spatial bible. Every sub-area, every landmark, every lie.
## Zones are not content. They are pressure vessels.
class_name ZoneDesigns
extends RefCounted

## Get the complete design document for all zones.
static func get_all_zone_designs() -> Dictionary:
	return {
		"ashborn_depth": _design_ashborn_depth(),
		"hollowed_seminary": _design_hollowed_seminary(),
	}


# ============================================================================
# ZONE 1: ASHBORN DEPTH (The Starting Zone)
# ============================================================================
# Identity: An open ash wasteland surrounding collapsed ruins.
# Feel: Horizontal. Exposed. Nowhere to hide. The sky is always visible.
# Dominant force at start: None (neutral). The player shapes it.
# God presence: All three gods are accessible. None are dominant.
# Lie: The openness feels safe. It isn't. The ash hides depth.
# ============================================================================

static func _design_ashborn_depth() -> Dictionary:
	return {
		"name": "Ashborn Depth",
		"identity": "Open ash wasteland. Collapsed ruins. The sky watches.",
		"layout": "horizontal",
		"size": "80x80 ground plane with vertical ruins reaching 15m",
		"atmosphere": {
			"sky": "Overcast grey. Shifts with forces: faith=amber, truth=white, violence=red-black.",
			"ground": "Ash. Grey-white. Crunches. Occasionally pulses near force zones.",
			"fog": "Thin at start. Thickens with corruption. Colored by dominant force.",
			"lighting": "Diffuse. No harsh shadows. Everything is equally exposed.",
		},

		"sub_areas": {
			"central_ruins": {
				"description": "Collapsed stone structures. Former settlement. Hub for NPC interactions.",
				"size": "20x20m cluster",
				"features": [
					"Crumbled walls (waist-high, provide partial cover)",
					"Central fire pit (cold, relights with faith > 60)",
					"Three pathways radiating outward (one per force alignment)",
					"Ground inscriptions (visible at truth > 40, gibberish below)",
				],
				"npcs": ["npc_ashwalker", "npc_scholar", "npc_survivor"],
				"enemies": "None at start. Spawner activates after first force gain.",
				"ambient": "Wind through ruins. Occasional stone creak.",
			},

			"faith_quarter": {
				"description": "Southwest. Shrine remnants. Candle clusters. The air is warmer.",
				"position": "(-20, 0, 15)",
				"size": "15x15m",
				"features": [
					"Faith shrine (primary faith gain point)",
					"Ash Walker's prayer site (quest start trigger)",
					"Burned icons on walls (micro-scene: burned_shrine)",
					"Candle ring that relights itself at faith > 60",
					"Verath's altar (god encounter point)",
				],
				"environmental_story": "This was a place of worship. The scorch marks suggest the worship ended violently. Whether the violence was against the faithful or by them is unclear.",
				"traversal_note": "Slightly elevated. Player must climb rubble to enter. Feels like ascending to a sacred space.",
				"audio": "Distant humming. Gets louder with faith. Stops abruptly at violence > 70.",
			},

			"truth_district": {
				"description": "North. Machines. Exposed gears. Documentation etched in stone.",
				"position": "(0, 0, -22)",
				"size": "18x12m",
				"features": [
					"Truth shrine (primary truth gain point)",
					"Scholar's research station (quest start trigger)",
					"Broken machine (micro-scene: broken_machine)",
					"Data wall (text appears/disappears based on truth level)",
					"Kael's observation point (god encounter — no altar, just a space where light is too bright)",
				],
				"environmental_story": "Researchers tried to understand the ash. Their tools are precise. Their conclusions are absent. The machines record but don't interpret.",
				"traversal_note": "Flat, geometric layout. Right angles. Feels organized. The organization is itself unsettling in this chaotic landscape.",
				"audio": "Mechanical clicking. Static pops. Frequency increases with truth.",
			},

			"violence_grounds": {
				"description": "East. Blood-stained earth. Weapons embedded in ground. Arena-like clearing.",
				"position": "(22, 0, 0)",
				"size": "20x20m",
				"features": [
					"Violence shrine (primary violence gain point)",
					"Training ground (enemies spawn faster here)",
					"Embedded weapons (interact: +violence, -faith)",
					"Mass grave (micro-scene: mass_grave)",
					"Null Throne crack (god encounter — a crack in the ground that whispers nothing)",
				],
				"environmental_story": "This was a fighting pit. The stains are layered — years of violence, not one event. The weapons in the ground are memorials or warnings. Both look the same.",
				"traversal_note": "Sunken slightly. Player descends into it. Getting out requires more effort than getting in.",
				"audio": "Subsonic rumble. Metal stress sounds. Heartbeat pulse when violence > 50.",
			},

			"ash_wastes": {
				"description": "Outer ring. Open featureless ash plains. The zone's boundary.",
				"size": "Extends 20m beyond the main areas in all directions",
				"features": [
					"Lying memorial (micro-scene — tells false history of Verath's mercy)",
					"Distant spire (unreachable landmark — visible from everywhere)",
					"Witness door (only responsive in witness mode)",
					"Wandering fog patches (move with violence level)",
					"Occasional footprint trails that lead nowhere",
				],
				"environmental_story": "There is nothing here on purpose. The emptiness is the story. What happened to everything that should be here?",
				"traversal_note": "No obstacles. No cover. Maximum exposure. The player should feel watched.",
				"audio": "Wind only. All other sounds fade as you walk outward. At the edge: silence.",
			},
		},

		"enemy_spawners": [
			{"position": "(-10, 0, 0)", "force_affinity": "faith", "types": ["ash_wraith"], "max_count": 3},
			{"position": "(10, 0, -10)", "force_affinity": "truth", "types": ["blood_echo"], "max_count": 3},
			{"position": "(15, 0, 5)", "force_affinity": "violence", "types": ["fanatic"], "max_count": 4},
			{"position": "(0, 0, 10)", "force_affinity": "neutral", "types": ["enemy_basic"], "max_count": 2},
			{"position": "(-15, 0, -15)", "force_affinity": "null", "types": ["void_seeker"], "max_count": 2},
		],

		"zone_rules": [
			"No tutorial. The player figures out interaction by exploring.",
			"First enemy encounter is NOT combat. An enemy stalks from distance in EARLY phase.",
			"NPC dialogue adapts to dominant force from the first conversation.",
			"The distant spire is always visible. It is never reachable.",
			"The zone changes permanently based on first force choice (shrine/combat/NPC).",
			"Fog color shifts are the primary force indicator. No UI notification for first shift.",
		],

		"cross_zone_effects_sent": [
			"Violence crisis -> Seminary patrols tighten",
			"God death -> Seminary shrine deactivates",
			"Holy war -> Seminary becomes war zone",
			"Quest failure -> Hollow Church reputation drops in Seminary",
		],
	}


# ============================================================================
# ZONE 2: THE HOLLOWED SEMINARY
# ============================================================================
# Identity: A collapsed religious school. Vertical. Claustrophobic. Faith is the enemy.
# Feel: Vertical. Pressing. The ceiling is too close. The walls breathe.
# Dominant force: Faith (but faith is HOSTILE here — it hurts its own followers).
# God presence: Verath is dominant. Kael observes. Null Throne fills the gaps.
# Lie: The Resonance Hall claims to be a dead end. It isn't.
# Unsettling mechanic: Faith bridges crumble under doubt.
# Unreachable landmark: The Inverted Bell Tower.
# ============================================================================

static func _design_hollowed_seminary() -> Dictionary:
	return {
		"name": "The Hollowed Seminary",
		"identity": "Collapsed religious school. Faith turned cancerous. The architecture prays.",
		"layout": "vertical_claustrophobic",
		"size": "40x60m footprint, 25m vertical (3 stacked levels + inverted tower)",
		"atmosphere": {
			"sky": "Barely visible. Most areas have stone ceilings. Where sky shows: faith-amber always.",
			"ground": "Stone. Cracked. Prayer inscriptions in every surface. Some glow faintly.",
			"fog": "Internal fog. Incense-like. Denser near the Undercroft.",
			"lighting": "Candle-only in most areas. Electric-bright in truth-influenced sections. Dark in void zones.",
		},

		"sub_areas": {
			"entrance_cloisters": {
				"description": "Open courtyard leading into the Seminary. Last breath of sky.",
				"size": "15x15m",
				"features": [
					"Stone archway with inscriptions (faith text, changes with truth level)",
					"Dead garden (something grows here when faith > 60 — it shouldn't)",
					"Hollow Church NPC (the Hollow Priest, quest giver)",
					"First view of Inverted Bell Tower through broken ceiling",
					"Warning signs: 'Faith sanctified this place. Faith destroyed it.'",
				],
				"traversal_note": "Transition from Ashborn's open sky to Seminary's closed walls. The ceiling closes in over 10 meters. Gradual claustrophobia.",
				"audio": "Echoing footsteps. Distant chanting (always from deeper inside). Wind stops here.",
			},

			"scripture_halls": {
				"description": "Long corridors. Walls covered in religious text. Some text moves.",
				"size": "30x8m corridor network (3 parallel halls connected by narrow passages)",
				"features": [
					"Moving scripture — text on walls shifts when player isn't looking directly",
					"Iron Deacon NPC (violence-aligned, quest giver for blood_tithe)",
					"Patrol zone for faith enemies (ash wraiths, but hostile to faith players)",
					"Hidden passage to Resonance Hall (visible at truth > 50)",
					"Prayer alcoves (sitting in one triggers god whisper)",
				],
				"environmental_story": "Students copied scripture for decades. The repetition drove some mad. You can see where the handwriting changes — from devotion to compulsion to scrawl.",
				"traversal_note": "Narrow. Two people couldn't walk side by side. The walls are close enough to touch both at once. Enemies appearing here should feel like ambushes.",
				"audio": "Whispered scripture (random fragments, some from wrong gods). Pages turning. Scratching sounds from walls.",
			},

			"resonance_hall": {
				"description": "THE LYING AREA. Appears to be a dead end. Corridor narrows, light dims, NPCs warn you back.",
				"size": "25x6m (narrowing to 3m at apparent dead end)",
				"features": [
					"Progressive narrowing (claustrophobia intensifies)",
					"NPC warning: 'Nothing down there. I checked. Turn back.'",
					"Light source dims to near-dark at the 'end'",
					"The lie: the wall at the end is not solid (truth > 50 reveals it, or persistence)",
					"Behind the wall: passage to the Undercroft",
					"Environmental lie: footprints on the floor stop at the 'wall' — someone walked through",
				],
				"the_lie": "Everything environmental says 'dead end.' The narrowing corridor, the dimming light, the NPC advice. All of it is the Seminary protecting its deepest space. Players who trust the world's signals will turn back. Players who don't will find the Undercroft.",
				"traversal_note": "The narrowing should feel physically uncomfortable. The ceiling also lowers. By the 'dead end,' the player is crouching in near-darkness.",
				"audio": "Sound drops out progressively. By the 'dead end': near silence. Past the wall: a completely different soundscape (Undercroft).",
			},

			"faith_bridges": {
				"description": "Crystallized prayer structures spanning gaps between Seminary levels. Beautiful. Fragile.",
				"size": "3 bridges, each 8-12m long, spanning 15m gaps",
				"features": [
					"Bridges made of translucent crystal (prayer solidified into structure)",
					"Integrity system: truth erodes, violence cracks, faith rebuilds but destabilizes",
					"Visual feedback: cracks glow when bridge is stressed, color shifts with force",
					"If bridge collapses: player falls to lower level (damage but not death)",
					"One bridge leads to Inverted Bell Tower base (requires highest integrity)",
					"Hostile faith: bridges pulse aggressively when faith > 60 (they want you to cross, but the want is hungry)",
				],
				"the_mechanic": "The bridges are the zone's signature. They demand faith but punish blind devotion. Truth weakens them (understanding destroys the miracle). Violence shatters them. The optimal approach: enough faith to walk, enough doubt to not trigger the hostility.",
				"traversal_note": "Walking on them should feel like walking on glass. Creaking. Swaying. The crystal is warm — body temperature. It feels alive.",
				"audio": "Crystal resonance. Harmonic tones when stepped on. Dissonant when stressed. Crack sounds are sudden and sharp.",
			},

			"undercroft": {
				"description": "The Seminary's hidden heart. Below everything. Where the faith experiment went wrong.",
				"size": "20x20m with 8m ceiling (feels vast after the tight corridors above)",
				"features": [
					"Central altar (not to any god — to faith itself, as a concept)",
					"Research notes from the Hollow Church's founding (truth content)",
					"Evidence of the faith experiment (combining devotion with force)",
					"Null Throne presence (the void crept in when faith hollowed out)",
					"Permanent save point (the only safe save in this zone)",
					"Exit to Bell Tower base (conditional on force states)",
				],
				"environmental_story": "The Seminary was an experiment. They tried to manufacture faith — to create devotion through repetition and isolation. It worked. Then it didn't stop. The students couldn't stop praying. The prayers changed. What answered wasn't a god. It was the act of devotion itself, given form.",
				"traversal_note": "After the claustrophobia above, this space should feel like breathing. But the air is wrong. Too warm. Too damp. Like being inside something alive.",
				"audio": "Low drone. Heartbeat-like pulse. The chanting from above is inaudible here — replaced by breathing. Not the player's breathing.",
			},

			"inverted_bell_tower": {
				"description": "THE UNREACHABLE LANDMARK. A bell tower hanging inverted from the Seminary ceiling.",
				"size": "5m diameter, 20m tall (inverted), accessible area: 5x5m base platform",
				"features": [
					"Visible from entrance — a tower pointing down, defying gravity",
					"Bell at the 'top' (bottom) — massive, silent, made of something that isn't metal",
					"Access requires: all forces > 60, no god obsessed, faith bridge intact",
					"Most players will never reach this",
					"Inside: a single room. A chair. A desk. Notes from someone who understood everything. The notes are blank.",
					"If the bell is rung: one clear tone. Every god hears it. Attention resets to zero for all gods. Once.",
				],
				"the_design": "This is the zone's impossible space. You see it immediately. You will probably never reach it. If you do, the reward is: blank pages and a bell that silences gods. Not power. Just quiet. The most valuable thing in this world is a moment of silence — and it costs everything.",
				"traversal_note": "Reaching it requires walking UP the inverted tower's exterior (faith bridges + force balance). Gravity is wrong here. The player walks on walls. Controls should feel slightly off.",
				"audio": "Complete silence. Absolute. No ambient, no footsteps, no breathing. The first true silence in the game. It should be unsettling because the player has gotten used to the whispers.",
			},
		},

		"enemy_spawners": [
			{"area": "scripture_halls", "force_affinity": "faith", "types": ["ash_wraith"], "max_count": 3, "note": "Hostile to faith-heavy players — Seminary curse"},
			{"area": "entrance_cloisters", "force_affinity": "violence", "types": ["fanatic"], "max_count": 2, "note": "Guard the entrance"},
			{"area": "faith_bridges", "force_affinity": "neutral", "types": ["void_seeker"], "max_count": 1, "note": "Appears when bridges are stressed"},
			{"area": "undercroft", "force_affinity": "truth", "types": ["blood_echo"], "max_count": 2, "note": "Protect the research"},
		],

		"zone_rules": [
			"No tutorial energy. This zone assumes the player has been broken by Ashborn Depth.",
			"Faith heals in Ashborn Depth. Faith HURTS in the Seminary. No explanation given.",
			"The Resonance Hall lie is never explicitly revealed. Discovery or failure.",
			"God whispers are louder and more frequent here.",
			"The Inverted Bell Tower is visible from the first room. It haunts every corridor.",
			"Cross-zone persistence: Ashborn Depth decisions change enemy patterns, NPC availability, and faith bridge starting integrity.",
			"The Undercroft is the only safe space. Players should feel the relief and question why it exists.",
			"Audio is the primary storytelling tool here. Scripture halls whisper. Bridges sing. The Undercroft breathes.",
		],

		"cross_zone_effects_received": [
			"Verath killed in Ashborn -> Seminary corruption +20, hostile faith intensifies",
			"Violence crisis in Ashborn -> Seminary patrols tighten, detection ranges expand",
			"Veil Torn in Ashborn -> Resonance Hall partially revealed (truth residue)",
			"Ash Walker killed -> Hollow Church NPCs are hostile from the start",
			"Player ignored all gods -> Verath's attention starts at 15 (she speaks louder here)",
		],

		"cross_zone_effects_sent": [
			"Resonance Hall revealed -> Truthseekers gain influence in Ashborn",
			"Bell Tower accessed -> All zones gain mild corruption (gods heard the bell)",
			"Undercroft research found -> Scholar NPC has new dialogue in Ashborn",
			"Iron Deacon killed -> Iron Vow becomes aggressive in all zones",
		],
	}
