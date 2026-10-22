# dot-workbench

Admin live-edit surface over dot-core's `DotProfileRuntime`: a transport-agnostic JSON API (`DotWorkbenchApi`), and `DotWorkbenchHttp`, the off-by-default loopback HTTP adapter (bearer token, `/api/profiles` routes, `web/index.html`) on dot-core's `DotHttpServer`. Read [docs/design.md](docs/design.md) first; it records what the family already has (no HTTP server) and what is not built.

**The distributable is `addons/dot_workbench/`.** `project.godot` and `examples/` exist to validate it alone. It requires dot-core (`ln -s ../../dot-core/addons/dot_core addons/dot_core`); everything else is duck-typed.

- All profile rules (validation, revisions, audit, save) belong to `DotProfileRuntime`; do not copy them here.
- The HTTP server is dot-core's `DotHttpServer`; `DotWorkbenchHttp` only mounts routes on it. The page is `addons/dot_workbench/web/index.html` (one file, no build); an export needs `*.html` in its include filter. The host calls `DotWorkbenchHttp.poll()` from `_process`.
- Secrets (admin token, TLS key) are read from files only, never env or argv.
- Validate: `heavy -- godot --headless --path . --import`, parse every `.gd` with `--check-only`, then `heavy -- godot --headless --path . res://examples/workbench_selftest.tscn` (7 sections, 57 checks).
