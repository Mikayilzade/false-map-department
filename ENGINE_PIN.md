# Engine pin

- Evaluated: 2026-08-19
- Pinned engine: **Godot 4.7.1-stable**
- Language: **GDScript-first**
- Renderer baseline: **Compatibility**

Reason: the frozen technical specification names 4.7.1-stable. On 2026-08-19, the official Godot archive still lists 4.7.1 as stable, while 4.7.2 is only RC1 and 4.8 is a development series. No pre-production upgrade is justified before codebase lock.

Official references:
- https://godotengine.org/download/archive/
- https://godotengine.org/article/maintenance-release-godot-4-7-1/
- https://docs.godotengine.org/en/latest/about/release_policy.html

Upgrade rule: any later engine change must be explicitly evaluated, recorded, and regression-tested before replacing this pin.
