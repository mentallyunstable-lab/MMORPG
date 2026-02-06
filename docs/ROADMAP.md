# Ashborn — Development Roadmap

> "You are not missing creativity. You are not missing systems. You are missing restraint orchestration."

---

## Priority Levels

| Priority | Meaning |
|----------|---------|
| 🔴 TOP | Do these before any content additions |
| 🟠 SYSTEM | Invisible but critical hardening |
| 🟡 EXPERIENCE | Readability and player understanding |
| 🟢 CONTENT | World logic and integration |
| 🔵 RELEASE | Pre and post-release checks |

---

## 🔴 TOP PRIORITY — DO THESE BEFORE ANY CONTENT ADDITIONS

### 1. Player Anchoring System (MANDATORY)

**Status:** `[ ] Not Started`

Pick one. Implement it fully. Nothing else matters until this exists.

**Anchor Type Options:**
- [ ] Single NPC
- [ ] Single audio motif
- [ ] Single UI element

**Rules:**
- Never lies
- Never contradicts itself
- Can disappear, but never deceive

**Implementation Requirements:**
- [ ] Global check: anchor bypasses god interference
- [ ] Immune to `trust_destruction.gd`
- [ ] Logs silence vs presence distinctly
- [ ] Playtest until players notice it subconsciously

> ⚠️ If you skip this, the game collapses into noise. Period.

---

### 2. Player Mental Model Kill Map

**Status:** `[ ] Not Started`

Internal design doc. Not optional.

**For each phase document:**
- What the player believes
- Which system breaks that belief
- What replaces it (false belief is OK)

**Example Structure:**
| Assumption | Breaker | Replacement Belief |
|------------|---------|-------------------|
| "Shrines are safe" | `trust_destruction.gd` | "Shrines decay but are still worth using" |

> ⚠️ If any assumption is broken with no replacement, that's a rage quit vector.

---

### 3. Betrayal Pacing Controller

**Status:** `[ ] Not Started`

Betrayals are discrete but not orchestrated.

**Implementation Requirements:**
- [ ] Global betrayal cooldown
- [ ] Hard rule: only ONE core system betrayal per X minutes
- [ ] Soft rule: audio lies do not overlap save lies
- [ ] Debug overlay showing:
  - Last betrayal timestamp
  - Next allowed betrayal window

> Horror needs rhythm. You don't have one yet.

---

## 🟠 SYSTEM HARDENING & CLARITY (INVISIBLE BUT CRITICAL)

### 4. Force Economy Audit

**Status:** `[ ] Not Started`

- [ ] Visualize hidden fatigue in dev tools
- [ ] Simulate 10-hour playthrough force curves
- [ ] Ensure no force permanently soft-locks progress
- [ ] Add emergency decay floor so fatigue always recovers

> Hidden ≠ unfair. Right now you're close to unfair.

---

### 5. God Interference Collision Rules

**Status:** `[ ] Not Started`

**Arbitration Rules Needed:**
- [ ] Priority when two gods interfere simultaneously
- [ ] What happens when lies cancel truths repeatedly
- [ ] Max number of persistent environmental edits per god
- [ ] Cooldown on god-on-god sabotage

> Without this, gods become spammy, not divine.

---

### 6. Quest System Failure Taxonomy

**Status:** `[ ] Not Started`

**Failure Types:**
| Type | Rumor Flavor | God Commentary | World State Change |
|------|--------------|----------------|-------------------|
| Ignored | | | |
| Misinterpreted | | | |
| Half-completed | | | |
| Actively defied | | | |
| Accidentally completed | | | |

> No two failures should feel identical.

---

## 🟡 EXPERIENCE & READABILITY

### 7. Combat Psychology Recognition Layer

**Status:** `[ ] Not Started`

Six moods is fine — recognition is missing.

**Per-Mood Cues:**
- [ ] Breathing rhythm
- [ ] Camera inertia signature
- [ ] Audio filter fingerprint

> If they can't recognize it, it's just VFX.

---

### 8. Witness Mode Escalation Curve

**Status:** `[ ] Not Started`

Currently linear. Make it staged.

**Stages:**
1. Objects respond once
2. NPCs notice but deny
3. Environmental decay
4. UI erosion
5. Sensory dropout
6. Forced stillness moments

**Requirements:**
- [ ] Hard caps so it never eats the entire UI too early
- [ ] Reset rules that feel like mercy, not rollback

---

### 9. Audio Lies Frequency Pass

**Status:** `[ ] Not Started`

Right now: scary. Later: annoying.

**Implementation:**
- [ ] Probability decay per session
- [ ] Context sensitivity (combat vs traversal)
- [ ] Distance-based believability checks

> Phantom footsteps every 30 seconds = trash horror.

---

## 🟢 CONTENT INTEGRATION & WORLD LOGIC

### 10. Cross-Zone Consequence Matrix

**Status:** `[ ] Not Started`

| Decision in Zone A | Effect in Zone B | Delay | Traceable? |
|-------------------|------------------|-------|------------|
| | | | |

**Balance:**
- Some consequences are traceable
- Some are plausibly deniable
- Not all are immediate

> Everything being delayed = confusion. Everything being instant = obvious.

---

### 11. NPC Rumor Propagation System

**Status:** `[ ] Not Started`

Rumors exist. They need movement.

- [ ] Rumor half-life
- [ ] NPC belief strength
- [ ] Mutation over distance/time
- [ ] Rare contradictions that hint at lies

> NPCs should disagree subtly, not loudly.

---

### 12. Death & Absence Weighting

**Status:** `[ ] Not Started`

States: Alive / Dead / Missing / Witness-only

**Questions to Answer:**
- How often is death mentioned?
- How often is absence felt?
- Which gods react to which state?
- Do zones remember missing NPCs differently?

> Absence should sometimes hurt more than death.

---

## 🔵 RELEASE & POST-RELEASE REALITY CHECKS

### 13. Minimum Viable Horror Loop Definition

**Status:** `[ ] Not Started`

Write this sentence explicitly:

> "Every 30–45 minutes, the player experiences X → Y → Z."

If you can't define it, you don't have a loop.

---

### 14. Haunt Score Validation

**Status:** `[ ] Not Started`

Make the number meaningful.

**Correlate haunt score with:**
- [ ] Player pauses
- [ ] Reload frequency
- [ ] Menu open time

**Requirements:**
- [ ] Define thresholds that unlock/lock behaviors
- [ ] Ensure haunt score never soft-bricks progression

> Metrics without interpretation are decoration.

---

### 15. Failure Recovery Vector

**Status:** `[ ] Not Started`

After betrayal, players need action, not comfort.

- [ ] One reliable "move forward anyway" behavior
- [ ] Even if it worsens things later
- [ ] Even if gods notice

> Hopelessness without agency = uninstall.

---

## 🔥 FINAL PRE-RELEASE CHECKS (DO NOT SKIP)

### 16. First 90 Minutes Lockdown

**Status:** `[ ] Not Started`

**Scripted Minimum:**
- [ ] One lie
- [ ] One silence
- [ ] One refusal

**Rules:**
- [ ] Zero overlapping betrayals
- [ ] No god obsession before player understands gods exist

> First impressions are irreversible.

---

### 17. Internal Playtest Rule

**Status:** `[ ] Not Started`

- No explaining mechanics
- No hinting
- No saving testers

**Logging:**
- If they get lost — log it
- If they rage — log why
- If they laugh — you failed the tone

---

### 18. Cut One Thing

**Status:** `[ ] Not Started`

Pick one system and either:
- [ ] Delay it
- [ ] Simplify it
- [ ] Remove one layer

> Density is your enemy now.

---

## Final Word

You are not missing creativity. You are not missing systems. You are missing **restraint orchestration**.

Do this list, and Ashborn becomes hostile art. Skip it, and it becomes an impressive psychological tech demo that burns players out.
