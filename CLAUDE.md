# dot-workbench

Admin live-edit surface over dot-core's `DotProfileRuntime`: a transport-agnostic JSON API (`DotWorkbenchApi`), and `DotWorkbenchHttp`, the off-by-default loopback HTTP adapter (bearer token, `/api/profiles` routes, `web/index.html`) on dot-core's `DotHttpServer`. Read [docs/design.md](docs/design.md) first; it records what the family already has (no HTTP server) and what is not built.

**The distributable is `addons/dot_workbench/`.** `project.godot` and `examples/` exist to validate it alone. It requires dot-core (`ln -s ../../dot-core/addons/dot_core addons/dot_core`); everything else is duck-typed.

- All profile rules (validation, revisions, audit, save) belong to `DotProfileRuntime`; do not copy them here.
- The HTTP server is dot-core's `DotHttpServer`; `DotWorkbenchHttp` only mounts routes on it. The page is `addons/dot_workbench/web/index.html` (one file, no build); an export needs `*.html` in its include filter. The host calls `DotWorkbenchHttp.poll()` from `_process`.
- `DotWorkbenchPanel` is the in-game panel: it binds dot-menu's `DotProfileEditorScreen` (duck-typed, so dot-ui and dot-menu stay optional) to the api, so Apply, Reset and `save_to_server()` take the same permission path as HTTP. `tools/panel_shot.gd` needs dot-ui, dot-menu and dot-settings linked into `addons/` (gitignored).
- `DotWorkbenchOverlay` is the in-game window (toolbar over the editor) and `DotWorkbenchExport` the tuning round trip: it writes only values differing from `DotWorkbenchApi.baseline_value` (the value seen before the session's first edit) into `cfg/game/<game>/<kind>/<id>.yml`, a zip and a clipboard bundle, and imports any of the three through `api.handle`. Hosting is dot-game's `DotGameWorkbench`.
- Secrets (admin token, TLS key) are read from files only, never env or argv.
- Validate: `heavy -- godot --headless --path . --import`, parse every `.gd` with `--check-only`, then `heavy -- godot --headless --path . res://examples/workbench_selftest.tscn` (10 sections, 95 checks).
- `DotWorkbenchIdentity` gates `api.identity` by duck-typing (resolver Callable, uid and group allowlists, optional fallback permit); keep it free of dot-auth and dot-console references. CI is the shared dot-ci `@v1` (`.github/workflows`).
