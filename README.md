# Ashborn

Action RPG where the player reshapes reality through **Faith**, **Truth**, or **Violence**.

Built with **Godot 4.x** and **GDScript**.

## Project Structure

```
scenes/
  player/       - Player character scene
  enemies/      - Enemy scenes
  npcs/         - NPC scenes
  ui/           - HUD and dialogue UI
  world/        - Zone scenes (test_zone is the entry point)

scripts/
  autoload/     - Global singletons (GameState, WorldManager, DialogueManager)
  player/       - Player controller and combat
  enemies/      - Enemy AI
  npcs/         - NPC interaction logic
  systems/      - Interactables, zone triggers
  ui/           - HUD and dialogue UI scripts
```

## Controls

- **WASD** — Move
- **Mouse** — Camera
- **Left Click** — Melee attack
- **Right Click** — Ranged attack
- **Space** — Jump
- **Shift** — Dodge
- **E** — Interact / Advance dialogue
- **Esc** — Toggle mouse capture

## Three Forces

The world reacts to three independent pressure axes:

- **Faith** — Strengthens miracles, weakens technology
- **Truth** — Weakens gods, causes reality glitches
- **Violence** — Destabilizes the world faster

Every choice shifts these forces. Every system reads them.
