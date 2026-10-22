# dot-workbench

Admin live-edit surface over dot-core's `DotProfileRuntime`: a transport-agnostic JSON API (`DotWorkbenchApi`) now, an off-by-default loopback HTTP page later. Read [docs/design.md](docs/design.md) first; it records what the family already has (no HTTP server) and what is not built.

**The distributable is `addons/dot_workbench/`.** `project.godot` and `examples/` exist to validate it alone. It requires dot-core (`ln -s ../../dot-core/addons/dot_core addons/dot_core`); everything else is duck-typed.

- All profile rules (validation, revisions, audit, save) belong to `DotProfileRuntime`; do not copy them here.
- Do not write an HTTP server in this addon; it goes in dot-core `net/` and is shared.
- Secrets (admin token, TLS key) are read from files only, never env or argv.
- Validate: `heavy -- godot --headless --path . --import`, parse every `.gd` with `--check-only`, then `heavy -- godot --headless --path . res://examples/workbench_selftest.tscn` (6 sections, 33 checks).
