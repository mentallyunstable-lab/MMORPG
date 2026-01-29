# Ashborn

Action RPG where the player reshapes reality through **Faith**, **Truth**, or **Violence**.

Built with **Godot 4.3** and **GDScript**.

> Multiplayer is out of scope until core loop is finished.

Single-player only. No new systems beyond what is documented in `IMPLEMENTATION.md`.

## Getting Started

1. Open the project in **Godot 4.3+** (Forward Plus renderer)
2. Hit **Play** — `test_zone.tscn` is the main scene
3. Walk around, fight enemies, talk to NPCs, channel shrines, encounter gods

## Controls

| Key | Action |
|-----|--------|
| WASD | Move |
| Mouse | Camera |
| Left Click | Melee attack |
| Right Click | Ranged attack |
| Space | Jump |
| Shift | Dodge roll |
| E | Interact / Advance dialogue |
| Tab | Quest log |
| Q | Use item |
| Esc | Pause menu (forces/factions/gods) |

## The Three Forces

The world reacts to three independent pressure axes (0-100 each):

- **Faith** — Strengthens gods, restores stability, golden atmosphere
- **Truth** — Erodes gods, clears fog, cold blue atmosphere
- **Violence** — Destabilizes regions, thickens fog, red atmosphere

These are not morality. They are **world pressure**. Every system reads them.

## Project Structure

```
scenes/
  player/         Player character (CharacterBody3D + camera + combat)
  enemies/        Enemy prefab (state-machine AI)
  npcs/           NPC prefab (base) + scripted NPCs
  ui/             HUD, dialogue, death screen, pause menu, quest log, notifications
  world/          Zones, shrines, god encounters, item pickups

scripts/
  autoload/       9 global singletons (see IMPLEMENTATION.md)
  player/         Player controller + projectile
  enemies/        Enemy AI base class
  npcs/           NPC base + Ash Walker + Scholar
  systems/        Interactables, zone triggers, shrines, spawner, environment, god encounters, item pickups
  ui/             All UI scripts
```

## Architecture

All game state flows through **autoload singletons** (loaded in this order):

1. **GameState** — Three Forces, factions, god stability, regions, player stats
2. **ForceEffects** — Passive world effects (ticks every 2s)
3. **FactionManager** — 4 factions with force-aligned reputation
4. **GodManager** — 3 gods with stability state machines
5. **WorldEventManager** — Threshold events (holy war, ashfall, etc.)
6. **QuestManager** — Quest lifecycle with force-reactive rewards
7. **ItemManager** — Inventory with consumables and quest items
8. **WorldManager** — Zone loading with persistent state
9. **DialogueManager** — Branching dialogue with force-gated choices

Systems communicate via **signals**. No system polls another directly.

## Test Zone Contents

- **Player** at origin
- **3 enemies** (violence/faith/truth aligned)
- **2 quest NPCs** — Ash Walker (faith quest), Shattered Scholar (truth quest)
- **3 force shrines** — one per force, scattered at edges
- **2 god encounters** — Verath (SW corner), Kael (SE corner)
- **3 item pickups** — ash relic, void fragment, health potion
- **Ruins** — walls and pillars for spatial interest
- **Enemy spawner** — force-reactive, spawns based on dominant force
- **Atmosphere system** — sky/fog/light shift in real time with forces

## Current Status

See `IMPLEMENTATION.md` for the full breakdown of every system, file, and feature.
