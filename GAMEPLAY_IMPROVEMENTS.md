# Rush The Pile — Core Gameplay Improvements

This document analyzes the current core loop and proposes focused, practical ideas to make play more fun, readable, and replayable, while staying faithful to the classic tapping game. Each idea includes low‑scope implementation notes referencing existing scripts.


## 1) Current Core Loop — Quick Analysis
- Loop: Play a card on your turn → watch for doubles/sandwich → tap race → face‑card challenge may start → winner collects pile → repeat.
- Strengths:
  - Fast, simple input (single tap) works on desktop and mobile.
  - Clear classic rules (doubles, sandwiches, face‑card challenge) with 8 AI profiles.
- Pain points/opportunities:
  - Readability/anticipation: It can be hard to anticipate/notice windows without strong audiovisual cues.
  - Frustration spikes: False taps consume scarce allowances and can feel harsh; AI can feel unfair if it “snipes” too quickly.
  - Flat progression: A match has little sense of momentum or personal improvement beyond winning the pile.
  - Limited variety: Only one rule set; long sessions can feel samey.


## 2) Low‑Scope, High‑Impact Improvements (Recommended First)
1) Stronger Tap Window Telemetry (Readability + Juice)
- What: Make doubles/sandwich windows unmistakable with: brief slow‑time (0.85x for 0.25s), center pile glow, pulse animation, and a crisp audio sting; show a tiny on‑pile pattern indicator (e.g., “7 7” or “10 J 10”).
- Why: Improves fairness and learning, reduces “I didn’t see it” frustration, improves moment‑to‑moment excitement.
- Impl Notes:
  - TapSystem.gd: When opening a window, emit a signal like `tap_window_opened(pattern_info, window_duration)`.
  - Visuals.gd: Subscribe and animate a short timescale tweak (Engine.time_scale) + glow shader/pulse on pile; show small pattern badge.
  - AudioManager.gd: Play a short stinger and quiet duck of background SFX during the slow‑time.

2) Human‑Fair Grace Frames vs. AI Snipes
- What: Add a 70–120 ms grace period after a tap window opens where only the human can tap. AI attempts are queued until grace expires.
- Why: Preserves challenge but prevents “robotic” instant AI wins.
- Impl Notes:
  - TapSystem.gd: On window open, set `human_priority_until = now + grace_ms`; ignore/schedule AI tap attempts until time passes.
  - AIProfile.gd: No changes necessary; this is a runtime gate in TapSystem.

3) Dynamic Difficulty Assist (DDS) for Human Tilt Protection
- What: If the human misses 3+ windows in ~60s or commits 2 false taps quickly, temporarily widen human tap leniency or slightly delay AI reaction.
- Why: Smooths streaky frustration; keeps flow engaging.
- Impl Notes:
  - Game.gd/TapSystem.gd: Track simple rolling counters; when thresholds are hit for the player, set a temporary `tap_leniency_ms += 30–60` and/or `ai_reaction_offset_ms += 20–40` for 30–60s.
  - Visuals.gd: Optional subtle “Focus” HUD icon when assist is active.

4) Immediate Feedback on False Tap Penalties
- What: On false tap: red flash, muted tone, and a quick visual of the two penalty cards sliding out from the player with a label “Penalty”. Also show remaining Tap Challenges with a shrinking pip meter.
- Why: Harsh outcomes feel fairer when clearly communicated.
- Impl Notes:
  - Game.gd/Player.gd: Emit `false_tap_committed(player, remaining_allowances)`.
  - Visuals.gd: Animate penalty cards + HUD pips; AudioManager.gd: short “tunk” sound.

5) Tutorial + Practice (1‑minute)
- What: A guided practice mode that slows time to 0.7x, spawns scripted doubles/sandwiches, and shows on‑screen tips.
- Why: Onboarding that shortens the time to competence and confidence.
- Impl Notes:
  - Menu.gd: Add “Practice” button.
  - Game.gd: Support a `practice_mode` flag that preloads a short scripted deck sequence and slower Engine.time_scale.
  - UIMessage.gd: Display contextual tips (e.g., “This is a Sandwich: 10‑J‑10”).


## 3) Momentum & Risk–Reward Additions (Optional, Toggleable)
1) Combo Streaks for Clean Taps
- What: Consecutive valid taps by the human build a combo (e.g., +1 per valid tap within last 20s, resets on miss/false/face loss). Each tier adds a small perk: +10 ms tap window, bonus VFX, or +1 score.
- Why: Creates momentum, positive feedback loop, and a “chase the streak” tension.
- Impl Notes:
  - TapSystem.gd: Track `human_combo` with timeouts; apply limited leniency per tier (cap to prevent trivializing difficulty).
  - Visuals.gd: Combo banner and escalating effects; AudioManager.gd: rising pitch cue.

2) “Focus Tokens” earned by careful play
- What: Earn a Focus token every X successful plays without false taps (e.g., 10 turns). Spend to: briefly widen tap window (+50 ms) or cancel one false tap penalty.
- Why: Adds light strategy and comeback resilience without changing core rules.
- Impl Notes:
  - Player.gd: Track `focus_tokens` and a counter.
  - UI: Small token icon near player; Menu.gd: toggle feature On/Off.

3) Optional Rule Variants (Mode Toggles)
- What: Add optional patterns to keep variety fresh:
  - “Runs” mode: Tap on ascending or descending rank sequences of length 3 (e.g., 4‑5‑6 or 9‑8‑7).
  - “Suit Snap” mode: Tap when two consecutive cards share suit.
  - “Jokers Wild”: Insert 2 Jokers; Joker → immediate tap window for all.
- Why: Extends replayability while preserving classic as default.
- Impl Notes:
  - TapSystem.gd: Modularize `is_tap_pattern()` to check enabled patterns from Game.gd settings.
  - Menu.gd: Add toggles; persist to ConfigFile.


## 4) AI Experience Improvements
1) Personality Callouts
- What: Light chatter bubbles or emotes when AIs succeed/fail (“Nice!”, “Oops”).
- Why: Adds character; makes wins/losses more readable and fun.
- Impl Notes:
  - Visuals.gd/UIMessage.gd: Timed speech bubbles; strings per profile name.

2) Tuning Guardrails
- What: Minimum reaction floor (e.g., never below 180 ms) and variability in their reaction even when Pro.
- Why: Avoids inhuman feels; keeps victories believable.
- Impl Notes:
  - AIProfile.gd/TapSystem.gd: Clamp effective reaction times and add ± jitter.


## 5) Accessibility & UX Quality
- Larger optional TAP button and customizable placement (left/right/bottom).
- High‑contrast pattern highlights; colorblind‑safe palette for pattern badges.
- Adjustable tap penalty severity (e.g., 1 or 2 cards) and Tap Challenge count (2–5) via settings.
- Optional “Hold to Tap” input for motor accessibility.
- Impl Notes:
  - Menu.gd: Settings UI + ConfigFile persistence.
  - Visuals.gd: Scalable UI and contrast theme.


## 6) Fairness / Tie Resolution
- Implement deterministic tie‑breakers when human and AI tap “simultaneously” in the same frame: human wins if within a 20 ms tie window; otherwise earliest timestamp wins.
- Impl Notes:
  - TapSystem.gd: Compare timestamps; when within tie window, bias for human and show a tiny “Tie‑break” label.


## 7) Short‑Form Modes (Replayability)
1) Sprint Mode (3 Pile Wins)
- First to collect the pile 3 times wins the match. Fast, snackable sessions.
- Impl Notes: Game.gd tracks `pile_wins` and ends early.

2) Best‑of‑3 Rounds
- Smaller decks per round or standard deck split into sub‑rounds. Carry over 1 Focus token (if enabled).
- Impl Notes: Game.gd round manager; Menu.gd mode selector.


## 8) Telemetry for Tuning (Dev Only)
- Log anonymous session stats: average reaction, false tap rate, tap window conversion, AI vs human tap share, rage‑quit rate.
- Use to adjust grace frames, DDS thresholds, and AI profiles.
- Impl Notes:
  - Game.gd/TapSystem.gd: Emit simple log lines with timestamps and counters (guarded by a `debug_telemetry` flag).


## 9) Prioritized Roadmap
- Week 1 (Low Effort / High Impact):
  - Stronger tap window VFX/SFX + pattern badge.
  - Grace frames for human vs AI (70–120 ms, tunable).
  - Clear false tap feedback + HUD pips.
  - Tie‑break rule favoring human within 20 ms.
- Week 2:
  - DDS tilt protection (temporary leniency or AI delay).
  - Tutorial/Practice mode with scripted patterns.
  - Accessibility options (larger TAP, contrast theme, adjustable penalties).
- Week 3+ (Optional Modes):
  - Combo streaks and Focus tokens.
  - Rule variants (Runs / Suit Snap / Jokers) as toggles.
  - Sprint Mode; Basic emotes for AI.


## 10) Concrete Hooks (by File)
- TapSystem.gd
  - Add signals: `tap_window_opened(pattern, duration)`, `tap_window_closed()`, `tap_tie_break(result)`.
  - Support `human_priority_until` timestamp and `tie_break_ms` setting.
  - Expose `tap_leniency_ms` and optional rule checks via settings.
- Game.gd
  - Centralize match settings (grace_ms, tie_break_ms, practice_mode, rule toggles, accessibility/penalty counts).
  - Track human streaks and DDS triggers; emit UI/Audio events.
- Visuals.gd
  - Implement pile glow, pattern badge, combo banner, penalty animations, and optional slow‑time pulses.
- AudioManager.gd
  - Add stingers: tap window open, successful tap, false tap, combo tier up.
- Menu.gd
  - Settings UI for toggles (rule variants, accessibility, practice, sprint mode).
- Player.gd
  - Track `focus_tokens` (optional) and expose HUD data.
- UIMessage.gd
  - Tutorial/practice callouts and AI emote bubbles.


## 11) Success Metrics (What to Measure in Playtests)
- Missed‑window complaints drop vs. baseline.
- False tap frequency stabilizes around target (e.g., 0.1–0.25 per minute in Normal).
- Human tap win share stays competitive (40–60%) in Normal difficulty.
- Average session length: Sprint mode 2–4 minutes; Classic 6–10 minutes.
- Qualitative: Players report “fair,” “readable,” and “addicting” more often.


## 12) Guiding Principles
- Default to classic rules; make all variants optional and clearly labeled.
- Improve clarity first, then difficulty, then variety.
- Always bias tie and grace toward a human‑feeling experience.
- Prefer small, tuneable parameters surfaced in settings over invasive rule changes.
