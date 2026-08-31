# FALSE MAP DEPARTMENT — PRODUCT ACCEPTANCE RULES

Status: **ACTIVE IMPLEMENTATION ACCEPTANCE CONTRACT**

This file clarifies what implementation evidence may support product-facing completion claims. It does not alter frozen gameplay, content, simulation, or empirical-gate thresholds.

## Player-facing presentation gate

Terms such as **playable**, **demo complete**, **presentation complete**, **vertical slice**, and **owner-ready build** require an intentional player-facing experience of the frozen game loop.

Debug tables, raw stable IDs, internal node/agent/objective identifiers, raw event names, engineering logs, database-style lists, test harnesses, and developer shells are useful implementation tools, but **cannot satisfy this gate**. They must not appear in the normal player path. If retained, they must be available only through an explicit developer/debug mode.

A qualifying player-facing dossier must, at minimum:

1. visualize the authored map geometry and recognizable world locations;
2. let the player act on the map rather than on internal identifiers;
3. visualize agents and the causal world response to an authoritative edit;
4. express objectives, consequences, and completion in human-readable language;
5. preserve non-color and non-animation equivalents for required facts;
6. pass a built-runtime capture review in addition to functional/runtime tests.

Automated tests can establish correctness, determinism, packaging, and absence of internal identifiers. They cannot by themselves establish visual quality or owner acceptance.
