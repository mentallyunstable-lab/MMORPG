# Ashborn — Implementation Details

Complete breakdown of every system, script, and scene in the project.

---

## Phase 1 — Foundation

### Player Controller (`scripts/player/player_controller.gd`)
**Class:** `PlayerController` extends `CharacterBody3D`

- **Movement:** WASD relative to camera facing, configurable speed (6.0 default)
- **Camera:** Third-person via `SpringArm3D`, mouse look with pitch clamping (-80 to +60 degrees)
- **Jump:** Single jump (force 8.0), gravity 20.0
- **Dodge roll:** Directional (input-based) or backward fallback, 0.3s duration at speed 14.0
- **Melee attack:** Area3D sweep hits all enemies in range, 20 damage, 0.4s cooldown, adds +0.5 violence per hit
- **Ranged attack:** Spawns `Projectile` instance (see below), 15 damage, 30 speed, 3s lifetime, adds +0.3 violence on enemy hit
- **Interaction:** RayCast3D checks layers 4 (interactables) and 8 (NPCs), press E to interact or advance dialogue
- **Death/Respawn:** On health <= 0: disable input, squish mesh, wait 2s, teleport to spawn position, restore full HP, add +1.0 violence
- **Null safety:** Guards on camera_pivot, spring_arm, interaction_ray; `is_instance_valid(self)` after all `await` calls

### Projectile (`scripts/player/projectile.gd`)
**Class:** `Projectile` extends `Area3D`

- Flies in set direction at configurable speed
- On body_entered: damages enemies, adds violence, self-destructs
- 3s lifetime auto-cleanup
- Collision: layer 5 (Projectiles), mask 1+4 (World + Enemies)

### Enemy AI (`scripts/enemies/enemy_base.gd`)
**Class:** `EnemyBase` extends `CharacterBody3D`

- **State machine:** IDLE → PATROL → CHASE → ATTACK → DEAD
- **Patrol:** Random offset from home position, walks to target, picks new target on arrival
- **Chase:** Follows player when within detection range (default 12.0)
- **Attack:** Deals damage when within attack range (2.0), 1.0s cooldown, knockback on player
- **Force affinity:** `@export var force_affinity: String` — violence/faith/truth
  - Violence-aligned: detection_range * 1.2 when violence > 70
  - Faith-aligned: attack_damage * 1.1 when faith > 70
  - Truth-aligned: detection_range * 1.2 when truth > 70
  - Buff applies once (flag guarded)
- **Death:** Tween shrink + fade, grants force points based on affinity (+2.0), queue_free after 1s
- **Signal cleanup:** Disconnects `GameState.force_changed` in `_exit_tree()`
- **Persistence:** `save_state()` / `load_state()` for health, position, alive status

### NPC Base (`scripts/npcs/npc_base.gd`)
**Class:** `NPCBase` extends `CharacterBody3D`

- Groups: `interactables`, `npcs`
- Dynamic dialogue based on dominant force and NPC's force_affinity
- Default dialogue offers three-force choice (Faith/Truth/Violence, +2.0 each)
- **Visual reactions:** Emission glow scales with aligned force (0-100 mapped to 0-1.5 energy). Scale pulse tween at force > 70
- Signal cleanup in `_exit_tree()`
- Persistence: `has_spoken` flag

### Interaction System (`scripts/systems/interactable.gd`)
**Class:** `Interactable` extends `StaticBody3D`

- Base class for all world objects (shrines, pickups, triggers)
- `@export var one_time: bool` — single-use or repeatable
- `@export var interaction_text: String` — displayed on HUD
- Virtual `_on_interact(_player)` for subclasses to override
- Persistence: `has_interacted` flag

### Zone Trigger (`scripts/systems/zone_trigger.gd`)
**Class:** `ZoneTrigger` extends `Area3D`

- On body_entered (player): calls `WorldManager.load_zone(target_zone)` with optional spawn point

### Dialogue System (`scripts/autoload/dialogue_manager.gd`)
**Singleton**

- Data-driven dialogue arrays with entries containing `speaker`, `text`, optional `choices`, `id`, `requires_force`
- **Choices** can include: `force` (which force to change), `amount`, `next_id` (jump target), `requires_force`/`requires_min` (gating)
- **Force gating:** Lines and choices filtered by current force levels
- **Recursion guard:** Max 50 skip depth before auto-ending dialogue
- **Player control:** Disables player input on start, restores on end
- **Shared filtering:** `_present_filtered_choices()` used by both `advance()` and `_jump_to_id()`

### Dialogue UI (`scripts/ui/dialogue_ui.gd`)
- Panel at screen bottom with speaker name, rich text, and choice buttons
- Choice buttons color-coded by force: blue (faith), yellow (truth), red (violence)
- Auto-hides when dialogue ends

---

## Phase 2 — Three Forces System

### GameState (`scripts/autoload/game_state.gd`)
**Singleton — loaded first**

- **Three Forces:** `faith`, `truth`, `violence` — each 0.0 to 100.0, independent axes
- Setter properties auto-clamp and emit `force_changed(force_name, old, new)`
- **World Pressure:** `(faith + truth + violence) / 3.0` — combined instability metric
- **Faction Reputation:** Dictionary, -100 to 100 per faction
- **God Stability:** Dictionary, 0.0 (dead) to 100.0 (manifest) per god
- **Region State:** Dictionary per zone with `belief_level`, `corruption`, `visited`, `events_triggered`
- **Player Stats:** health, max_health, alive flag
- Full `save_state()` / `load_state()` serialization

### Force Effects (`scripts/autoload/force_effects.gd`)
**Singleton — ticks every 2 seconds**

- **High Faith (70+):** Restores god stability +0.5/tick, decays violence -0.1/tick
- **Critical Faith (90+):** Emits `miracle_pulse` world effect
- **High Truth (70+):** Erodes god stability -0.8/tick, decays faith -0.15/tick
- **Critical Truth (90+):** Emits `reality_glitch` world effect
- **High Violence (70+):** Corrupts all regions +0.5/tick
- **Critical Violence (90+):** Emits `world_destabilize`, decays all faction rep -0.3/tick
- **Pressure Overload (80+):** Emits `pressure_overload`
- Tracks dominant force and tier (none/low/mid/high/critical)
- `get_force_modifier(force_name)` returns 0.0-1.0 for system scaling

### Faction Manager (`scripts/autoload/faction_manager.gd`)
**Singleton**

Four factions registered at startup:

| Faction | Alignment | Description |
|---------|-----------|-------------|
| The Ash Walkers | Faith | Pilgrims seeking signs of old gods |
| The Shattered Lens | Truth | Scholars who value observable reality |
| The Iron Vow | Violence | Warlords who believe strength is currency |
| The Hollow Church | Faith | Dying religion clinging to unanswered rituals |

- **Effective reputation** = base rep + (aligned force * 0.3) - (opposing force penalty)
- **Attitudes:** hostile (< -50), unfriendly (< -15), neutral, friendly (> 15), allied (> 50)
- Emits `faction_attitude_changed` when force shifts cause attitude transitions

### God Manager (`scripts/autoload/god_manager.gd`)
**Singleton**

Three gods registered at startup:

| God | Domain | Starting Stability |
|-----|--------|--------------------|
| Verath, the Ash Mother | Death & Rebirth | 60 |
| Kael, the Blind Sun | Light & Judgment | 50 |
| The Null Throne | Absence & Void | 30 |

- **State machine:** dead (< 5) → fading (< 25) → weakened (< 45) → dormant → manifest (> 75) → ascended (> 95)
- Faith > 50: boosts all god stability (+0.02 per faith point over 50)
- Truth > 30: erodes all god stability (-0.03 per truth point over 30)
- Violence > 60: accelerates current trajectory (strong gods get stronger, weak get weaker)
- Emits `god_state_changed` and `god_event` (death, ascension, fading)

### Force Environment (`scripts/systems/force_environment.gd`)
**Class:** `ForceEnvironment` extends `Node3D`

Real-time atmosphere modification based on forces:

| Force | Fog | Sky | Ambient Light | Sun |
|-------|-----|-----|---------------|-----|
| Faith | Golden tint, normal density | Deep indigo top, golden horizon | Warm, brighter | Warm gold |
| Truth | Cold blue, thinner | Clear dark blue, steel horizon | Cold, neutral | Cool white |
| Violence | Blood red, thicker | Blood sky, ember horizon | Dark red, dimmer | Angry orange |

- Captures base values at `_ready()`, lerps toward force-weighted targets
- Updates on every `force_changed` signal

---

## Phase 3 — World State

### World Event Manager (`scripts/autoload/world_event_manager.gd`)
**Singleton — checks every 3 seconds**

One-time threshold events:

| Event | Condition | Effect |
|-------|-----------|--------|
| The World Bleeds | Violence >= 80 | All enemies +25% damage, +20% HP |
| Blind Faith Rising | Faith >= 70, Truth < 30 | Tech suppression flag set |
| The Veil Torn | Truth >= 70, Faith < 30 | All gods -10 stability |
| Paradox Zone | Faith >= 60, Truth >= 60 | Ashwalkers and Truthseekers -20 rep |
| Holy War | Faith >= 60, Violence >= 60 | Hollow Church -15, Iron Vow +10 |
| Revolution | Truth >= 60, Violence >= 60 | Truthseekers +10, Iron Vow +5 |
| Ashfall | World Pressure >= 85 | All regions +25 corruption |
| Zone Corrupted | Zone corruption >= 75 | Zone marked fully corrupted |

- Events queued and processed sequentially with 0.5s gaps
- Each event has a notification (title + description) and mechanical effects
- Listens to ForceEffects, GodManager, FactionManager for cascade events
- Persistence: `triggered_events` dictionary

### Force Shrine (`scripts/systems/force_shrine.gd`)
**Class:** `ForceShrine` extends `Interactable`

- Channels +10 of aligned force on interact
- Drains opposing forces (30% for direct opposites, 15% each for violence)
- Shifts faction reputation (+3 aligned, -2 opposing)
- Adjusts god stability (+3 for faith shrines, -5 for truth shrines)
- 30s cooldown between uses
- Fires notification on use

### Enemy Spawner (`scripts/systems/enemy_spawner.gd`)
**Class:** `EnemySpawner` extends `Node3D`

- Configurable interval (default 15s), max enemies (default 5), spawn radius
- **Force-reactive:** When dominant force >= 50, 60% chance to spawn force-aligned enemy
- **Tier scaling:** High tier reduces interval to 80%, Critical to 60% + caps max at base+4 (max 12)
- Cleans dead enemy references every frame
- Signal cleanup in `_exit_tree()`

### Event Notification UI (`scripts/ui/event_notification.gd`)
- Top-right floating notification panels
- Force-colored left border (blue/yellow/red/amber)
- Fade in (0.3s), display (5s), fade out (1s), auto-cleanup
- Max 3 visible notifications

---

## Phase 4 — Content Layer

### Quest Manager (`scripts/autoload/quest_manager.gd`)
**Singleton**

- Data-driven quest definitions with `id`, `title`, `description`, `objectives`, `rewards`
- **Objective types:** kill, interact, talk, collect, reach
- **Lifecycle:** AVAILABLE → ACTIVE → COMPLETED/FAILED
- `notify_event(type, target_id)` — called by world systems when things happen
- Auto-completes quests when all objectives done
- **Rewards:** force points, faction reputation, items
- Force-gating: quests can require minimum force levels to accept

### Item Manager (`scripts/autoload/item_manager.gd`)
**Singleton**

6 items registered at startup:

| Item | Type | Effect |
|------|------|--------|
| Ashen Salve | Consumable | Heals 30 HP |
| Prayer Bead | Consumable | +5 Faith |
| Cracked Lens | Consumable | +5 Truth |
| Iron Splinter | Consumable | +5 Violence |
| Ash Relic | Quest | Verath's artifact for Ash Walker quest |
| Void Fragment | Quest | Null Throne fragment for Scholar quest |

- Stacking with configurable max (10 for potions, 5 for force items)
- `use_item()` applies effect and removes from inventory
- Notification on pickup

### NPC: Ash Walker (`scripts/npcs/npc_ashwalker.gd`)
**Extends:** `NPCBase` (faith affinity)

**Quest: "Ashes of the Forgotten"**
1. Talk to Ash Walker — branching greeting based on dominant force
2. Accept via three-force dialogue choice (pray/negotiate/threaten)
3. Find Ash Relic in ruins (item pickup, auto-notifies quest)
4. Return to Ash Walker — delivers relic, receives rewards
5. Post-quest dialogue changes based on Verath's stability

**Rewards:** +10 Faith, +15 Ashwalkers rep, 1 Health Potion

### NPC: Shattered Scholar (`scripts/npcs/npc_scholar.gd`)
**Extends:** `NPCBase` (truth affinity)

**Quest: "What the Throne Left Behind"**
1. Talk to Scholar — greeting varies by dominant force
2. Accept via three-force dialogue choice (accept/ask/negotiate)
3. Find Void Fragment at eastern edge (item pickup, auto-notifies quest)
4. Return to Scholar — delivers fragment, receives rewards
5. Post-quest dialogue changes based on Null Throne stability

**Rewards:** +10 Truth, +15 Truthseekers rep, 1 Cracked Lens

### God Encounter (`scripts/systems/god_encounter.gd`)
**Class:** `GodEncounter` extends `Interactable`

Interactive altar where the player talks to a god's presence. Dialogue changes entirely based on god state:

- **Dead:** "The presence is gone." Choices: pray/acknowledge/dismiss
- **Fading:** Whispered fragments, choices to stabilize/study/destroy
- **Weakened:** God speaks weakly, choices: blessing/truth/demand
- **Dormant:** Neutral conversation, choices: worship/understand/power
- **Manifest:** "I AM HERE." Full divine presence, choices: protect/reveal/wrath
- **Ascended:** "I HAVE TRANSCENDED." Extreme force costs (+8 each)

Each choice shifts the corresponding force. Violence options are always available.

### Item Pickup (`scripts/systems/item_pickup.gd`)
**Class:** `ItemPickup` extends `Interactable`

- Grants configured item on interact
- Optionally notifies QuestManager of "collect" event
- One-time use, hides after collection

### Death Screen (`scripts/ui/death_screen.gd`)
- Black overlay fades to 85% opacity on player death
- Death message changes by dominant force:
  - Faith: "The gods watch you fall."
  - Truth: "Reality does not mourn."
  - Violence: "The strong survive. You didn't."
- Shows current dominant force value
- Auto-fades out when player respawns

### Pause Menu (`scripts/ui/pause_menu.gd`)
- Esc to toggle, pauses game tree
- Three tabs:
  - **Forces:** Bars for Faith/Truth/Violence, world pressure, dominant force, tier
  - **Factions:** All 4 factions with name, alignment color, attitude, effective reputation
  - **Gods:** All 3 gods with name, state, stability value, state-colored text

### Quest Log (`scripts/ui/quest_log_ui.gd`)
- Tab to toggle
- Lists active quests (unchecked) and completed quests (checked, dimmed)
- Quest entries color-coded by force affinity
- Detail panel shows title, description, and objective checklist
- Auto-refreshes on quest accept/update/complete

### HUD (`scripts/ui/hud.gd`)
- Top-left: Health bar, Force bars (Faith blue, Truth yellow, Violence red)
- Center: "[E] Interact" prompt when near interactable
- Updates every frame for health, on signal for forces

---

## Test Zone Layout

```
        N (-Z)
        |
   God:Verath (-20,-20)    Ruins (10,-16)    God:Kael (20,-20)
        |                  Ash Relic (12,-18)
        |
   Pillar (-18,-8)         Enemies            Pillar (-14,-10)
        |
   NPC:AshWalker (-5,-3)   PLAYER (0,0)      NPC:Scholar (5,5)
        |
   Shrine:Faith (-20,15)   Potion (-3,10)     Pillar (8,12)
        |
   Pillar (-10,18)         Wall (-6,22)       Shrine:Violence (22,0)
        |                                      Wall (24,5)
        |                  Shrine:Truth (0,-22) Void Fragment (25,8)
        S (+Z)
        |
        --- E (+X)
```

Ground: 80x80, ash-colored. Sky: dark indigo + orange horizon. Fog + ambient shift with forces.

---

## File Count

**35 files total** (~5,700 lines of GDScript + scene markup)

- 15 GDScript files
- 11 Scene files (.tscn)
- 1 Project config (project.godot)
- 2 Documentation (README.md, IMPLEMENTATION.md)
- 1 Git ignore (.gitignore)
- Empty asset directories (models, textures, audio, fonts)
