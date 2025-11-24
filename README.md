# Rush The Pile

Single-player, fast‑paced tapping card game built with Godot 4. Play against 3 AI opponents with distinct personalities and reaction speeds. The objective is to win the entire 52‑card deck by playing to, and tapping, the center pile according to the rules below.

Last updated: 2025-08-24


## Highlights
- True to the classic tap game rules (doubles and sandwiches).
- Face-card challenge flow (J/Q/K/A grant 1/2/3/4 chances to the next player).
- Tap Challenges: each player gets 3 incorrect-tap allowances per match; running out disables tapping until a new game.
- Dynamic Difficulty Assist (optional, time-limited focus assist that slightly delays AI taps when you’re struggling).
- 8 AI profiles spanning Easy to Pro difficulties, with human‑like mistakes (missed taps, false taps) and variable play/tap timing.
- Single input design: tap/click or on-screen TAP button. Simple to play on desktop or mobile.
- Lightweight codebase using typed GDScript 2.0 (Godot 4.x).


## Code Map (Scripts)
- godot/scripts/Game.gd — Match coordinator and state machine. Emits signals for UI/Audio; wires Deck, Players, TapSystem, and ChallengeSystem.
- godot/scripts/TapSystem.gd — Detects doubles/sandwiches, opens tap windows, schedules AI taps, resolves tie-breaks, awards pile.
- godot/scripts/ChallengeSystem.gd — Face-card challenge flow (start/pass/fail/clear) with signals for transitions.
- godot/scripts/Visuals.gd — Overlay HUD and VFX reacting to Game/TapSystem (center highlight, tokens, timer, overlays).
- godot/scripts/AudioManager.gd — Procedural SFX and haptics; persists SFX volume.
- godot/scripts/DdsAssist.gd — Dynamic Difficulty Assist component that temporarily modifies AI tap reaction when thresholds are met.
- godot/scripts/InputRouter.gd — Encapsulates human inputs (center taps, play area, TAP button) decoupled from Game.
- godot/scripts/AIProfile.gd — Tunable AI timing/mistake parameters; helpers to pick delays.
- godot/scripts/Player.gd — Player data model (human/AI): hand, score, tap challenges; play/receive/penalty/shuffle helpers.
- godot/scripts/Deck.gd — 52-card deck reset/shuffle/deal with optional deterministic RNG.
- godot/scripts/Card.gd — Card resource with rank/suit and helpers (value, face flags, label).
- godot/scripts/Menu.gd — Main menu and settings (difficulty select, audio sliders, fullscreen toggle).
- godot/scripts/UIMessage.gd — Minimal status banner bound to Game.status.

## Game Rules (Summary)
- Setup
  - A standard 52‑card deck is shuffled and dealt evenly to 4 players as face‑down piles.
  - You play against 3 AIs. A random player starts.

- Normal play
  - Turns proceed clockwise. On your turn, tap the center to play the top card of your pile face-up onto the center stack.
  - Play Timer: You have 3 seconds to play your next card. If you don’t play in time, you lose your turn and must place your top card into the center as a penalty.
  - If a face card (J, Q, K, A) is played, the next player enters a face-card challenge:
    - J: 1 chance, Q: 2 chances, K: 3 chances, A: 4 chances to reveal another face card.
    - If the next player reveals a face card within their allotted chances, the challenge passes onward to the next player with a new chance count.
    - If they fail, the player who laid the initiating face card collects the entire center pile to the bottom of their hand and becomes the next to play.

- Tap/tap events (anyone can tap first)
  - Double: two consecutive cards with the same rank (e.g., 7–7).
  - Sandwich: a-b-a by rank (e.g., 10–J–10).
  - First to tap during a valid window wins the entire center pile and becomes the next player.
  - False tap (no valid event): consumes 1 Tap Challenge and the tapping player must place their top two cards onto the center pile as a penalty. When a player has 0 Tap Challenges remaining, further taps are ignored for the rest of the match.

- Win condition
  - The game ends when one player has collected all cards.


## Privacy & Offline Play
- 100% offline by default. The game does not collect, transmit, or store any personal data.
- Analytics are opt-in only. If analytics are added in the future, they will be off by default; you may enable them explicitly in Settings. No third-party SDKs are bundled.
- Haptics and audio preferences are local to your device.

## Settings Persistence
Saved to user://settings.cfg on your device:
- Audio: master volume, SFX volume.
- Haptics: enabled/disabled.
- Difficulty: Easy/Medium/Hard selection from the main menu.
- GUI scale: additional UI scale multiplier for accessibility.
- Tutorial: seen/dismissed flag.
- Last seed: last game seed used for deterministic replays/debugging.

## Controls
- Desktop: Left‑click (or press the ui_tap action) on the center area, or use the on‑screen TAP button.
  - On your turn: plays your top card.
  - Any time: attempts a tap. If valid during a tap window, you may win the pile; if invalid, you consume 1 Tap Challenge and take a penalty.
- Mobile: Tap the center area (project uses a mobile‑friendly renderer setting; you can export to mobile).
- Keyboard Shortcuts (Desktop):
  - Esc: Quit (from menu) or Return to Menu (from game).
  - F11: Toggle Fullscreen.


## AI Behavior
There are 8 AI profiles defined (Easy A/B, Normal A/B, Hard A/B, Pro A/B). Each profile varies in:
- Play delay (how long they wait to play a card on their turn).
- Tap reaction window (how quickly they attempt to tap valid events).
- Miss/false tap probabilities (to simulate mistakes).
- Face focus bias (tendency to speed up under face-card pressure).

During a tap window, AIs decide to attempt a tap independent of turn order. Outside tap windows, AIs may occasionally false tap based on their profile.

### State Diagram (Play, Challenges, Tap Windows)
Textual overview of the main states and transitions managed by Game.gd, ChallengeSystem.gd, and TapSystem.gd:
- DEALING → NORMAL_PLAY after shuffle/deal and first player is chosen.
- NORMAL_PLAY: Active player plays one card on their turn.
  - If the new top of the pile forms a tap event (double or sandwich), TapSystem opens TAP_WINDOW.
  - If the played card is a face card (J/Q/K/A), start CHALLENGE with chances = 1/2/3/4 for the next player, then advance turn.
  - Otherwise remain in NORMAL_PLAY and advance turn.
- CHALLENGE: The current player must reveal another face within their remaining chances.
  - If they play a non-face and chances remain, chances decrement and the challenge passes to the next player; stay in CHALLENGE.
  - If chances reach 0 (failure), the initiator of the challenge takes the entire pile; state returns to NORMAL_PLAY and the winner becomes the next to play.
  - If any player reveals a new face during CHALLENGE, a fresh challenge starts with new chances from that face, and turn advances.
- TAP_WINDOW: Any player (including you) may tap.
  - First valid tap awards the entire pile to the tapper; state returns to NORMAL_PLAY and that player becomes the next to play.
  - If another card is played before a tap and it does not create a tap pattern, the tap window closes automatically.

Notes on timing:
- Tap windows only open immediately after a card is added that makes a double or sandwich.
- AI tap attempts are scheduled within their personal reaction windows; they may “miss” a valid window based on miss_tap_probability.
- Outside TAP_WINDOW, AIs can occasionally false tap (small per‑second chance) and take the penalty.

### AI Profiles (Defaults and Tuning)
The game supports AI profiles via Resource (AIProfile). Profiles can be provided as .tres files or fall back to built-in defaults. Parameters per profile:
- name
- min_play_delay, max_play_delay (seconds)
- tap_reaction_min, tap_reaction_max (seconds)
- miss_tap_probability (0..1 chance to miss a valid tap)
- false_tap_probability (0..1 chance per second to false tap during normal play)
- face_focus_bias (speeds up AI play under face‑card pressure; 0.1 ≈ 10% faster)

Default profiles (used if no .tres are provided):

| Name   | Play Delay (s) | Tap Reaction (s) | Miss Tap Prob | False Tap Prob | Face Focus Bias |
|--------|-----------------|------------------|----------------|-----------------|-----------------|
| Easy A | 0.9–1.6        | 0.35–0.60        | 0.40           | 0.10            | 0.00            |
| Easy B | 0.8–1.5        | 0.32–0.55        | 0.30           | 0.08            | 0.00            |
| Normal A | 0.6–1.2      | 0.26–0.50        | 0.15           | 0.04            | 0.00            |
| Normal B | 0.55–1.1     | 0.24–0.48        | 0.12           | 0.03            | 0.05            |
| Hard A | 0.5–1.0        | 0.22–0.40        | 0.06           | 0.02            | 0.10            |
| Hard B | 0.45–0.95      | 0.20–0.38        | 0.05           | 0.02            | 0.12            |
| Pro A  | 0.42–0.90      | 0.18–0.34        | 0.02           | 0.01            | 0.15            |
| Pro B  | 0.40–0.85      | 0.16–0.32        | 0.01           | 0.005           | 0.20            |

Using .tres profiles:
- You can provide profiles via the exported array in Game.gd (ai_profile_resources) or by placing resources at:
  - res://resources/ai/easy_a.tres, res://resources/ai/easy_b.tres,
  - res://resources/ai/normal_a.tres, res://resources/ai/normal_b.tres,
  - res://resources/ai/hard_a.tres, res://resources/ai/hard_b.tres,
  - res://resources/ai/pro_a.tres, res://resources/ai/pro_b.tres
- If all 8 files exist and are valid AIProfile resources, they are loaded; otherwise the built-in defaults above are used.

Tweaking values:
- In the Godot editor, create a new AIProfile resource (Right‑click in FileSystem > New Resource > AIProfile) and set fields in the Inspector.
- Or set the exported ai_profile_resources array on the Game node in Main.tscn to reference your custom .tres files.
- face_focus_bias only affects AI play delay during an active challenge (lower delay when positive). Tap reaction uses the tap_reaction_* range regardless of challenge state.
- Default field values when creating a fresh AIProfile (from AIProfile.gd):
  - name = "AI"
  - min_play_delay = 0.4, max_play_delay = 1.2
  - tap_reaction_min = 0.18, tap_reaction_max = 0.45
  - miss_tap_probability = 0.0
  - false_tap_probability = 0.0
  - face_focus_bias = 0.0


## Requirements
- Godot Engine 4.3+ (4.x recommended). Download: https://godotengine.org
- Desktop OS: Windows, macOS, or Linux. Mobile export optionally supported via Godot export templates.


## Quick Start (Run From Editor)
1. Open Godot 4.x.
2. Import the project:
   - Project > Import > Select the folder: `godot/` (contains `project.godot`).
3. Open the project and press F5 (Play) to run.
   - The game starts at the menu: `res://scenes/Menu.tscn`. Choose Easy/Medium/Hard to begin. Settings panel allows adjusting Master and SFX volume; values persist across sessions.

Tip: The center pile and player areas are visible in the main scene for quick testing. The UI label at the top displays status messages.


## Exporting
- Desktop (Windows/macOS/Linux):
  - Project > Export… > Add relevant presets > Configure output path > Export.
- Mobile (Android/iOS):
  - Install Godot export templates.
  - Configure signing (Android keystore or iOS provisioning), orientation, permissions, and input.
  - Export builds for your target device.

Note: The project uses only tap/click input and does not rely on keyboard. Ensure the ui_tap action maps to a touch or primary button in your export platform.


## Project Structure
- godot/project.godot – Godot 4 project settings (renderer: mobile; version 1.0.0; feature tag 4.3/4.4).
- godot/scenes/Menu.tscn – Main menu with difficulty selection and Settings panel.
- godot/scenes/Main.tscn – In-game scene wiring nodes and UI (on‑screen TAP button and Leave Match button).
- godot/scripts/
  - Menu.gd – Handles menu interactions, settings, and scene switching with chosen difficulty.
  - Game.gd – Core gameplay loop, turn logic, tap windows, challenges, scoring, messaging, and AI timing.
  - TapSystem.gd – Encapsulates tap detection, tap window, AI tap reactions, false taps, and pile awarding.
  - ChallengeSystem.gd – Manages face‑card challenge state and transitions.
  - Visuals.gd – Lightweight visual effects overlay (HUD, highlights, timer, tutorial hooks).
  - AudioManager.gd – Minimal synthesized SFX and persisted SFX volume control.
  - DdsAssist.gd – Dynamic Difficulty Assist component wired to TapSystem and status messaging.
  - InputRouter.gd – Routes human inputs (center taps, play area, TAP button) while decoupling from Game.
  - UIMessage.gd – Binds Game.status to a label.
  - AIProfile.gd – Parameterized AI behavior profiles.
  - Deck.gd – 52‑card deck model with shuffle and deal.
  - Card.gd – Card data and helpers (face detection, label, rank value).
  - Player.gd – Player hand operations, penalties, receiving piles, scoring.


## Development Notes
- Engine: Godot 4.x, GDScript 2.0, typed.
- Rendering: Mobile rendering method enabled in project settings; works on desktop too.
- Input: `ui_tap` action is configured to Left Mouse Button in `project.godot`. `ui_fullscreen` (F11) and `ui_cancel` (Esc) are also defined. You can add touch events if needed.
- Randomness: Uses `randomize()` on ready; results vary per run.


## Troubleshooting
- Project fails to open: Verify you are using Godot 4.3+ (not 3.x).
- Input unresponsive:
  - Ensure you are clicking/tapping within the CenterPileArea in the main scene or use the on‑screen TAP button.
  - Confirm `ui_tap` is bound to your input device in Project Settings > Input Map.
- Cannot tap anymore: You may be out of Tap Challenges (3 per player by default). Start a new match from the Menu.
- AIs never tap: Tap windows open only on valid patterns (double or sandwich). You’ll see messaging in the UI when the pile is taken.
- Performance on mobile: Use release exports and consider lowering resolution or toggling rendering options if needed.


## Roadmap (Ideas)
- Visual card assets and animations for dealing and flipping.
- Settings to choose AI difficulties and number of AIs.
- Sound effects and haptics for taps.
- Online leaderboard for fastest wins.


## Arcade Scoring System (New)
The game now tracks an arcade-style score per player.
- Play a card: Earn points equal to the card value (2–10 count as 2–10; J=11, Q=12, K=13, A=14).
- Win a tap: Flat bonus of +10 points.
- Clear the center pile: Bonus equal to the sum of values of all cards collected in that pile.

Notes:
- Score events float as +N pop-ups near the player who earned them.
- Internally, scores are kept on each Player and exposed via a score_awarded signal for UI/overlays.
- You can tune constants in Game.gd (TAP_WIN_BONUS) or adjust per-card scaling via Card.get_value().

## Making Gameplay More Arcade-like (Notes)
Suggestions you can pick and choose from, ordered roughly by impact vs effort:
1) Feedback & Juice
- Add hit sparks and screen shake on tap wins; quick color flash around the center (already added) and a bigger flash + glow when piles are taken.
- Play short SFX: card flip, tap slap, error buzz for false taps, whoosh for pile transfers.
- Add combo text when multiple scoring events occur within a short window (e.g., Rapid Tap! + Chain Clear!).

2) Momentum & Combo Mechanics
- Streak bonus: consecutive successful taps within X seconds grant incremental +5/+10/+15 bonuses.
- Speed multiplier: temporarily multiply play/tap points if the player keeps actions under a reaction-time threshold.
- Risk-reward: allow a “power tap” input during challenge that doubles clear bonus but increases false-tap penalty.

3) Clarity & Competition
- Always-visible scoreboard HUD with per-player scores and small up/down tick animations when scores change.
- End-of-round summary: taps won, false taps, biggest pile, highest combo, total score.
- Difficulty-based scoring multipliers (e.g., Hard x1.2, Pro x1.4) to reward tougher settings.

4) Tempo & Flow
- Slightly shorten AI play delays for higher tempo on Medium/Hard.
- Add a “Quick Deal” animation and a 3-2-1 countdown at new game start.
- Auto-continue after pile awards with a brisk tween rather than long pauses.

5) Cosmetics
- Themed suits and dynamic backgrounds that pulse subtly with score gains or tap windows.
- Trail lines from cards as they move to the center and from the center to the winner.

Implementation hooks in this codebase:
- Visuals.gd already listens to important signals; extend it with SFX, shake, and HUD updates without touching core logic.
- Game.gd exposes score_awarded for HUD and combo systems.
- TapSystem.gd emits pile_cleared with pile stats; useful for combo/bonus logic.

## Contributing
Contributions are welcome. Suggested steps:
- Fork the repo and create a feature branch.
- Keep changes focused and include brief descriptions.
- Prefer minimal external dependencies.
- Open a pull request with screenshots or short clips if UI/UX changes.


## License
Dual-licensing for development and distribution:
- Source code: MIT License (see LICENSE). You may use, modify, and redistribute the source code under MIT terms.
- Game builds and assets (binaries, artwork, audio, fonts, names, logos, trademarks): Proprietary. Distributed under the End User License Agreement (see EULA.txt). These are not licensed under MIT.

Notes for Steam distribution:
- Ship the game with EULA.txt and reference it on your Steam store page if desired.
- Ensure you own or have rights to all included assets and third-party components.
- Trademarks, logos, and the game title are reserved and may not be used without permission.


## Acknowledgements
- Godot Engine and community.
- Classic tap card games that inspired the ruleset.


## Recommendations for Improvement

Below are concrete, prioritized suggestions tailored to this codebase. They aim to improve code quality, maintainability, UX, performance, and project hygiene while keeping the project lightweight.

1) Code Architecture & Godot Best Practices
- Split Game.gd responsibilities into smaller scripts or modules:
  - Turn/Deal/State coordinator (GameState) responsible for high‑level flow.
  - ChallengeSystem that encapsulates face‑card challenge state and transitions.
  - TapSystem that owns tap detection, windows, and awarding logic (signals like tap_window_opened, pile_awarded).
  This makes each concern testable and reduces coupling.
- Use enums and a simple state machine (e.g., enum { DEALING, NORMAL_PLAY, CHALLENGE, TAP_WINDOW, GAME_OVER }) to clarify transitions and guard inputs.
- Prefer @onready variables for frequently used nodes (e.g., CenterPileArea, CenterLabel, UI/Message) rather than repeated has_node/path lookups.
- Consider moving AI profile data out of Game.gd into .tres resources (AIProfile) and loading them via export Array[AIProfile] or ResourceLoader. This enables tuning without code changes and supports future UI selection.
- Replace difficulty: String with an exported enum or integer (and map to labels) to reduce stringly‑typed errors and to expose in the inspector.
- Replace message signal self‑connection with a dedicated UI script listening to Game signals; alternatively, emit typed signals (pile_changed(top_label), turn_changed(name), status(message)). This decouples Game from UI.

2) Randomness, Determinism, and Replays
- Use a dedicated RandomNumberGenerator instance (rng = RandomNumberGenerator.new()) instead of global randomize/randf(). Seed it at game start and store/display the seed. This allows deterministic replays and reproducible bug reports.
- Thread the rng through deck.shuffle(), AI reaction picks, and false‑tap decisions.

3) Timers and Scheduling
- Avoid creating many transient Timer nodes for AI taps. Use SceneTreeTimer via get_tree().create_timer(delay) and await it; this avoids node churn and bookkeeping.
- Keep a single play_timer as you have (good), but similarly use SceneTreeTimer for AI tap attempts. Also guard against race conditions by checking that the tap window is still open and tap_valid at the await point (you already do, keep it).

4) Input Handling and UX
- Unify human input path: choose either Area2D input_event or _input action, not both, to avoid double‑handling. If keeping both (for mouse/touch), gate with is_action_pressed and event.handled = true after consuming.
- Add multitouch/touchscreen support explicitly (InputEventScreenTouch) and ensure ui_tap maps to touch on mobile exports.
- Provide clear visual affordances: highlight the center pile when a tap window opens; flash border in the color of the player who took the pile; show turn indicator around the active player area.
- Add animations for card plays and pile takes (tween to center, tween to winner), keeping logic decoupled from visual tween completion.
- Add a pause/restart menu; display number of cards per player and last action (helps learning and debugging).

5) Game Rules & Edge Cases
- Fix potential null insertion bug: Player.penalty_two_to_center currently appends play_top() which can return null when the hand is empty. Guard: var c = play_top(); if c: center.append(c).
- Ensure challenge flow handles a player with zero cards cleanly (you decrement chances already; consider messaging like "Player X out of cards, challenge continues").
- When awarding the pile, center_pile = [] is fine, but consider center_pile.clear() to preserve reference if any UI binds directly. If not, keep as is.
- Consider exposing rule toggles (enable/disable sandwiches, doubles only) for custom modes.

6) AI Behavior
- Promote AI profiles to .tres and allow difficulty presets to select specific resources. Consider exposing an in‑game difficulty selector.
- Add variability: slight jitter on tap reaction when under face‑card pressure (you already bias play delay with face_focus_bias; also bias tap reaction based on pressure or pile size).
- Limit false tap probabilities when no cards are in hand to avoid pointless penalties or adjust penalty rules for 0‑card players (house rule).

7) Performance
- Replace per‑frame false‑tap checks with stochastic scheduling: pick a next_false_tap_time per AI using an exponential distribution and attempt only at that time; reduces per‑frame RNG work.
- Avoid allocating arrays in hot paths. For instance, reusing a PackedStringArray of messages or pooling temporary timers (if not using SceneTreeTimer).
- If adding animations, consider running them on a separate visual layer with minimal logic coupling.

8) Testing & CI
- Add automated tests using GdUnit4 or WAT/GUT:
  - Deck: 52 unique cards, even deals, shuffle randomness.
  - Tap detection: doubles and sandwiches across a variety of sequences.
  - Challenge system: face chances, pass/fail chains, awarding logic after exhaustion.
  - Penalties: false tap penalty behavior (and null guard).
- Set up GitHub Actions CI to run headless Godot tests on push/PR (official Godot setup action available). Include linter/static checks (gdformat/gdlint) if desired.

9) Project & Repo Hygiene
- Add a Godot‑specific .gitignore (.import/, .godot/, export/ builds, .cache, platform exports). Remove IDE‑local files from VCS (.idea, .iml) or move to a global gitignore.
- Add .gitattributes for consistent line endings and to mark binary assets.
- Add CONTRIBUTING.md with dev setup, code style, and test instructions; optionally CODE_OF_CONDUCT.md.
- Include screenshots or a short GIF in README to showcase gameplay.
- Consider adding RELEASING.md with steps to export for platforms.

10) Documentation Improvements
- Expand README with a brief state diagram for face‑card challenges and tap windows.
- Document AI profiles in a table (name, play delay range, tap reaction range, miss/false probabilities, bias). If moved to .tres, list default values and how to tweak.
- Add a Troubleshooting entry for "double input" symptoms and how to map ui_tap for mobile.
- Clarify versioning (semver) and add a CHANGELOG.md when features evolve.

11) Quality of Life & Telemetry (Optional)
- Track basic stats in memory (taps attempted, successful taps, false taps, fastest pile win) and show at end of game.
- Optional analytics (opt‑in) for aggregate difficulty usage; keep privacy in mind.

Quick Wins to Tackle First
- Fix null guard in Player.penalty_two_to_center.
- Unify input handling for human player.
- Switch AI tap delay timers to get_tree().create_timer() to reduce node churn.
- Add .gitignore for Godot and remove IDE project files from repo.
- Add a seed via RandomNumberGenerator for deterministic runs (display in UI message at game start).


## Additional Improvements (Aug 2025 Review)

These are further, concrete improvements identified during a fresh review. They do not assume adding heavy dependencies and are scoped to be feasible for a solo project.

1) Accessibility and UX
- Color‑blind friendly palette and high‑contrast mode for player indicators and center highlights. P1
- Scalable UI: respect ProjectSettings display/GUI scale, add in‑game slider and save preference. P2
- Reduce motion toggle to minimize animations for sensitive players. P2
- Larger hit‑target option for mobile center area and Tap button. P1
- Hints/Tutorial: one‑page overlay explaining doubles/sandwich with examples; first‑run only with a “Don’t show again” checkbox. P1

2) Audio & Feedback
- Minimal SFX set: card flip, slap, error buzz, pile whoosh; expose volumes in a Settings menu. P1
- Short background loop with mute toggle; ensure pause when app unfocused. P3
- Audio feedback for “no challenges left” and for challenge pass/fail. P2

3) Game Modes & Progression
- Practice Mode: infinite deck with quick reset and slowed AI for learning; disable scoring. P2
- Time Attack: win the deck as fast as possible; show best time and seed. P2
- Custom Rules: toggles in Settings for doubles/sandwiches, tap bonus value, false‑tap penalty amount. P2

4) AI & Difficulty
- Dynamic scaling: slightly increase AI false‑tap probability when human is far behind to create comeback moments (optional). P3
- Per‑seat seeding: allow selecting which seat starts and lock AI profiles per seat for repeatable comparisons. P2
- Expose AI profile selection in the menu (drop‑down next to difficulty). P2

5) Save/Load & Persistence
- Save settings (volume, fullscreen, GUI scale, rule toggles, difficulty) to a config file using ConfigFile. P1
- Save last seed and last used settings; add “Replay last match” from menu. P2

6) End‑of‑Game & Stats
- Summary screen: taps attempted, taps won, false taps, biggest pile won, longest challenge chain, final score. P1
- Local leaderboard for Time Attack and Highest Score; store with simple JSON. P2

7) Input & Platforms
- Controller support: map ui_tap to A/X, add button glyphs in Help overlay. P2
- Long‑press on mobile as “tap” alternative (tunable threshold). P3
- Haptics on mobile for tap win and false tap (via Godot vibration API on Android). P2

8) Performance & Polish
- Profile with built‑in profiler while spam‑tapping; ensure zero allocations in hot paths (avoid new arrays per frame). P2
- Pool label/token nodes in Visuals.gd to avoid instantiation overhead on low‑end devices. P2
- Cap maximum pile size visual updates to reduce label churn (e.g., update_hud at most 10 Hz). P3

9) Code Quality
- Extract a small HUD script for scoreboard and challenge labels; let Visuals orchestrate only animations. P2
- Introduce a lightweight EventBus autoload for decoupled UI if scenes grow. P3
- Add gdformat/gdlint tooling suggestions and style guide in CONTRIBUTING.md. P2

10) Testing
- Unit tests for TapSystem _is_tap_event with edge sequences (double, sandwich, near‑miss). P1
- ChallengeSystem tests for multi‑face chains and on_player_empty cases. P1
- Player.penalty_two_to_center tests: hands of size 0/1/2+ insert to bottom ordering. P1
- Seed determinism test: same seed → identical first 10 deals. P2

11) Release Hygiene
- Add Godot‑focused .gitignore (e.g., .godot/, .import/, export/). P1
- Add basic GitHub Actions workflow to run tests (if added) and optionally lint. P3
- Add screenshots/GIFs to README and store under a docs/ folder. P2

Notes
- Many items can be implemented without touching core turn logic; prefer extending Visuals.gd and Menu/UI scenes, keeping Game.gd authoritative.
- Priorities: P1 = high impact/low effort; P2 = medium; P3 = nice‑to‑have.


## App Store Success Playbook (Mobile‑Focused)

Goal: Improve first‑session satisfaction, 1‑day/7‑day retention, and monetization while keeping the game fair and lightweight.

1) First‑Time User Experience (FTUE) and Onboarding
- One‑screen tutorial overlay (already noted): visual examples of Double and Sandwich with animated arrows; tap to continue. Persist "seen_tutorial" in ConfigFile.
- Assisted first match: in the first game, slow AI slightly and highlight valid tap windows for 0.5s.
- Clear success/failure feedback: reinforce with SFX (AudioManager.gd has card flip / error buzz / whoosh) and short color flashes (Visuals.gd).
- Add a “Practice” mode in Menu with no penalties, ideal for learning.

2) Session Design and Retention Loops
- Daily Challenge: fixed seed of the day; leaderboard shows best times among local results. Simple and low‑cost but sticky.
- Missions: 3 rotating goals (e.g., "Win 3 tap windows", "Win a sandwich", "Avoid false taps for a round"). Reward soft currency or cosmetics.
- Streaks: consecutive‑day login streak grants a cosmetic border or subtle table skin.
- Fast sessions: ensure average round < 2 minutes; expose Quick Restart.

3) Monetization (Fair and Non‑Intrusive)
- Ads: rewarded ad only, never interstitials mid‑round. Offer “Second Chance” after a big mistake or “Double Daily Reward”.
- IAPs: Remove Ads, Cosmetic Packs (table skins, card backs), Premium Mode (Time Attack + advanced stats). No pay‑to‑win.
- Starter bundle: 3–5 tasteful card backs + Remove Ads at a discount. Limited time banner on day 1–3.

4) Live‑Ops Light
- Weekly rotating card‑back themes and background palettes; align with seasons/holidays.
- “Rule of the Week” optional toggle (e.g., doubles only) to create variety without fragmenting code.
- News panel on Menu with 1–2 short items pulled from a tiny JSON on your site/GitHub.

5) Analytics & A/B Testing (Privacy‑Respecting)
- Local telemetry: track core KPIs in memory and save aggregates in user://: first session length, matches played, taps attempted/won, false taps, FTUE completion, difficulty chosen.
- Optional analytics toggle: if enabled, send anonymous events (FTUE_complete, match_end with duration and difficulty) to a simple endpoint. Make it opt‑in with a clear privacy note.
- Simple A/B via remote JSON: e.g., tutorial hint duration 0.3s vs 0.6s. Persist assigned bucket per device.

6) Mobile Polish
- Haptics: light vibration on tap win, warning buzz on false tap.
- Large touch targets: ensure center area is comfortably sized; add a redundant on‑screen Tap button.
- Pause/Resume safety: auto‑pause when app loses focus; resume with a 3‑2‑1 countdown.
- Performance: cap HUD updates; pool nodes in Visuals.gd; keep GC pressure low on low‑end devices.

7) Store Presence
- ASO: short, keyword‑rich subtitle: “Fast card‑tapping duel • Doubles & Sandwiches!”
- Screenshots: 6–8 showing tap wins, face‑card challenges, Daily Challenge, cosmetics. Add short captions.
- App Preview/Trailer: 15–30s with punchy SFX; show a full tap win and whoosh moment within the first 3s.
- Ratings prompt: after 3rd completed match and a win or high score, ask for rating using native prompts.

8) Compliance & Build Hygiene
- Privacy: clear offline play, no personal data collected by default; opt‑in analytics only.
- Settings persistence: volume, haptics, difficulty, GUI scale, tutorial seen, last seed.
- .gitignore for Godot artefacts; export presets for Android/iOS with icons and adaptive icons.

Implementation Hooks in This Repo
- AudioManager.gd: already persists SFX volume and generates minimal SFX. Add haptics calls alongside play_tap_success()/play_error_buzz() on mobile.
- Menu.gd: ideal place for tutorial toggle, difficulty/mode selection (Daily Challenge, Practice, Time Attack), and ratings prompt triggers.
- Game.gd: emit simple signals for match_start/match_end with stats; wire to a lightweight Telemetry singleton (autoload) if desired.
- Visuals.gd: extend for highlight pulses on TAP_WINDOW and victory animations; pool UI nodes.

Prioritized Backlog for App Stores
- P1 (Week 1): FTUE overlay + Practice mode; haptics; ratings prompt; polished SFX already present; quick restart; settings persistence for tutorial/volume.
- P2 (Week 2): Daily Challenge (seed of day) + local leaderboard; missions framework (simple JSON rotate); cosmetics (1–2 table skins/card backs).
- P3 (Week 3+): Rewarded ads and Remove Ads IAP; Time Attack mode with shareable seed/time; optional telemetry + tiny A/B for tutorial hint timing.
