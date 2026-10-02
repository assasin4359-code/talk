# CLAUDE.md — Back to the Gates

The top-level design authority is `docs/00_GDD_Handoff.md` (owner's original text, Korean). Read it before changing story content. Never rewrite it; put proposals in the "결정 필요" table in `docs/01_Architecture.md`.

## Non-negotiables from the handoff
- The loop did **not** exist before the player arrived. No NPC says "here we go again" in early cycles (a test enforces this for cycles 1–2).
- Show the normal world first; horror = small diffs against a baseline the player has learned. In data, every world rule must have a baseline.
- No quest UI language (퀘스트 / 0/5 / 호감도 / COMPLETE). The validator warns on it.
- No combat, no big inventory, no mazes for playtime, no early narrator reveal, narrator is not a villain.
- Undecided things (names, king's true nature, exact cycle count, …) stay placeholders. Mark temp lines with `"note": "[임시 대사] ..."` or `"제안: ..."`.

## Layout
- `GameData/` — the real narrative data (JSON). Format: `docs/03_Narrative_Data_Spec.md`.
- `Tools/narrative/btg_narrative/` — engine-agnostic reference implementation. The future engine port must behave identically; `GameData/tests/condition_vectors.json` is the shared conformance suite.
- `Tools/narrative/prototype/` — throwaway text-prototype data (locations, flavor text). Not game data.
- No engine project exists yet (UE5 recommended, owner to confirm). This cloud environment cannot build an engine; engine code must be verified on the owner's machine.

## After any change to GameData or Tools/narrative
```bash
python Tools/narrative/btg.py validate
python -m unittest discover -s Tools/narrative/tests -t Tools/narrative/tests
```
If choice order in a beat changes, update `Tools/narrative/prototype/walkthrough.txt`.

## Conventions
- Python: stdlib only, 3.10+.
- Logic/content lives in text (C++/JSON); Blueprints stay thin presentation. Core emits cue names; presentation never decides story state.
- Small PRs. Analyze → design → implement.
