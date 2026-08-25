# Phase 12G mature-session protocol — E3 / E4 / E5 / E6 / E9 / E10

Purpose: collect genuine representative **human** observations after the participant already knows the game rules. Prepared packets are acquisition tooling only; they are not evidence.

## Eligibility and privacy

- Use pseudonymous tester IDs only.
- Before finalization, explicitly set `rules_known_before_session=true` only when the participant actually understands the taught base rules well enough for mature-gate testing.
- Do not infer human judgments from telemetry, deterministic solution envelopes, test fixtures, authored validation metadata or automated runtime success.
- Missing participants or blank observer fields remain PENDING.

## Prepare a counterbalanced batch

```bash
python3 scripts/phase12g_mature_session_batch.py prepare \
  --count 6 \
  --tester-prefix MATURE-T \
  --build-id <exact-production-build-id>

python3 scripts/phase12g_mature_session_batch.py status \
  --manifest .phase12g-mature-sessions/batch-manifest.json
```

Each packet pins the exact build ID and prepares the frozen representative tasks for E3, E4, E5, E6, E9 and E10. All human outcome fields start as `null`. Preparation does not append anything to `empirical/evidence`.

E3 method order is deterministically counterbalanced across adjacent tester packets and dossier rows. Counterbalancing is scheduling metadata, not an empirical outcome.

## E3 — mature reasoning versus systematic legal-edit search

Use exactly the methods and representative dossiers in `phase12g_session_protocols.json`.

For each row record:
- whether rule knowledge was confirmed for that task;
- whether the dossier was completed;
- factual completion time in seconds.

Do not coach either method toward a known solution. The point is to compare genuine mature causal reasoning with deliberate systematic legal-edit search, not to benchmark automated solvers.

## E4 — campaign repetition

Use both frozen windows:
- D13–D22;
- D29–D36.

After the participant has experienced the full window, record one of the allowed assessments from the protocol (`distinct`, `mixed`, `predominantly_same_trick`) plus meaningful notes. Do not pre-fill the assessment from authored reasoning-transformation tags; those tags are only automated preconditions.

## E5 — linked-authority comprehension

The packet discovers campaign dossiers with at least three map layers from current production content. For an actually tested requirement, record:
- the requirement ID;
- the layer the participant identifies as authoritative;
- correctness from the frozen authority relation;
- whether tutorial recall was used.

Do not reveal the authority source before the participant answers.

## E6 — causal readability

Use the frozen D33–D40 representative set. Ask the participant to explain the cause of an actually selected requirement state using the normal causal ribbon/Inspect presentation.

`used_raw_debug_log` must be explicitly `false`. Raw debug/event dumps are forbidden for E6 because they bypass the player-facing readability question.

## E9 — remix distinctness

The helper prepares all REMIX01–REMIX12 rows and resolves each frozen `source_substrate_id` directly from remix content. After the participant has played the source substrate and remix, record whether they describe it as a changed causal problem and add notes.

Do not infer distinctness from P10-R10 validation alone; that validation is only an implementation precondition.

## E10 — agent distinctness

The helper discovers taught archetype IDs from campaign content and creates a deterministic ring of pair comparisons so every taught archetype participates without forcing all pairwise combinations on each human tester.

For each observed scenario, record the participant's predicted behavioral distinction before the relevant consequence and whether the prediction was correct. The generated scenario ID only identifies the comparison packet; it is not proof of distinctness.

## Finalize locally

After real observations are entered in `observer-packet.json` and `rules_known_before_session=true` is explicitly confirmed:

```bash
python3 scripts/phase12g_mature_session_batch.py finalize \
  --packet-dir .phase12g-mature-sessions/MATURE-T001
```

Finalization rejects any missing required human field and rejects E6 rows unless `used_raw_debug_log=false`. Successful finalization writes `completed-E3.jsonl`, `completed-E4.jsonl`, `completed-E5.jsonl`, `completed-E6.jsonl`, `completed-E9.jsonl` and `completed-E10.jsonl` only inside the local packet directory.

It still does **not** append repository evidence. Validate and append each completed file deliberately with `scripts/phase12g_collect_completed_rows.py`. Qualitative gates remain PENDING until evidence is collected and an explicit evidence-backed disposition is recorded through the existing Phase-12G disposition mechanism.
