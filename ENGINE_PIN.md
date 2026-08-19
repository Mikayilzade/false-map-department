# Engine pin

- Evaluated: 2026-08-19
- Pinned engine: **Godot 4.7.1-stable**
- Language: **GDScript-first**
- Renderer baseline: **Compatibility**

Reason: the frozen technical specification names 4.7.1-stable and requires any upgrade to be deliberate, recorded, and regression-tested before replacing the pin. A fresh release check on 2026-08-19 found that **Godot 4.7.2-stable was released on 2026-08-18**. The project nevertheless retains 4.7.1-stable for the current Phase-12A baseline because that exact runtime is the frozen bootstrap target and its import/headless/boot baseline has not yet been executed. Changing the engine while the first baseline is still unproven would mix engine migration risk with bootstrap verification.

This is an explicit retention decision, not an assumption that 4.7.1 is the newest stable patch. A later upgrade to 4.7.2 or newer requires a separate recorded evaluation and green regression evidence before replacing `.godot-version`.

Official references:
- https://github.com/godotengine/godot/releases/tag/4.7.1-stable
- https://github.com/godotengine/godot/releases/tag/4.7.2-stable
- https://godotengine.org/download/archive/
- https://docs.godotengine.org/en/latest/about/release_policy.html

Upgrade rule: any engine change must be explicitly evaluated, recorded, and regression-tested before replacing this pin.
