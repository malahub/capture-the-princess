# LICENSES

**Heavy Flag is an original work.** Every model, texture-free material, sound,
line of code and the title itself were authored for this project. No assets were
extracted from, converted from, or copied out of any commercial game — including
Fat Princess — and no reference art was traced into the build.

Mechanics are not copyrightable; expression is. The castle-siege princess
formula is reimplemented from the published description of the genre's mechanics,
with original geometry, characters, palette, UI, audio and naming.

## Code

- Game code: original, written for this project.
- Engine: [Godot Engine 4.7.2](https://godotengine.org) — MIT License.

## Art

- All meshes are Godot primitives (`BoxMesh`, `CylinderMesh`, `SphereMesh`,
  `TorusMesh`, `PrismMesh`) assembled at runtime in `scripts/build.gd`.
- No texture files. Materials are flat `StandardMaterial3D` colours.
- `icon.svg` is an original mark drawn for this project.

## Audio

- Every sound is a PCM tone synthesised at runtime in `Core.tone()`
  (square / triangle / sine / noise bursts). No audio files ship with the game.

## Fonts

- Godot's built-in default font (SIL Open Font License, via the engine).
