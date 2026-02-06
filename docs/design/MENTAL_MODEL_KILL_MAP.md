# Player Mental Model Kill Map

> For each phase: What the player believes → Which system breaks it → What replaces it

---

## Phase 1: Early Game (0-2 hours)

| # | Player Assumption | Breaking System | Replacement Belief | Rage Quit Risk |
|---|-------------------|-----------------|-------------------|----------------|
| 1 | "Shrines are safe" | `trust_destruction.gd` | "Shrines decay but are still worth using" | LOW |
| 2 | "NPCs tell the truth" | `rumor_system.gd` | "Most NPCs believe what they say" | MEDIUM |
| 3 | "The UI is reliable" | `witness_mode.gd` (stage 4) | "UI reflects my perception, not reality" | HIGH |
| 4 | "Saving is permanent" | `save_interference.gd` | TBD - NEEDS REPLACEMENT | CRITICAL |
| 5 | "Audio cues are real" | `audio_lies.gd` | "Frequent sounds are real, rare ones might not be" | MEDIUM |

---

## Phase 2: Mid Game (2-5 hours)

| # | Player Assumption | Breaking System | Replacement Belief | Rage Quit Risk |
|---|-------------------|-----------------|-------------------|----------------|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

---

## Phase 3: Late Game (5+ hours)

| # | Player Assumption | Breaking System | Replacement Belief | Rage Quit Risk |
|---|-------------------|-----------------|-------------------|----------------|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

---

## Critical Rules

1. **Every broken assumption MUST have a replacement belief**
   - If replacement is "nothing" → rage quit vector
   - If replacement is "everything is a lie" → learned helplessness → uninstall

2. **Replacement beliefs can be false** — that's fine
   - False beliefs create future breaking opportunities
   - Chain: True → False → Deeper True

3. **Maximum 2 assumptions broken per hour**
   - More than this = noise
   - Player needs time to form new mental model

4. **The Anchor is NEVER broken**
   - See: `anchor_system.gd`
   - This is the player's one constant

---

## Validation Checklist

Before any playtest, verify:

- [ ] Every row has a replacement belief
- [ ] No CRITICAL rage quit risks without mitigation plan
- [ ] Anchor system assumption is NOT in this table
- [ ] Breaking systems are implemented and tested
- [ ] Replacement beliefs are achievable through gameplay
