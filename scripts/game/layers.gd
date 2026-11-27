class_name Layers
## Physics layers with a special meaning.

## Invisible walls (fall guards, the pit barrier). Players and robots bump into them;
## shots, sight lines and grapple lines pass straight through.
const BLOCKER := 1 << 9
## Mask for shots and line-of-sight checks: everything but invisible walls.
const SHOTS := 0xFFFFFFFF & ~BLOCKER
