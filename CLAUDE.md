# dot-workbench

Admin live-edit surface over dot-core's `DotProfileRuntime`: a transport-agnostic JSON API (`DotWorkbenchApi`), and `DotWorkbenchHttp`, the off-by-default loopback HTTP adapter (bearer token, `/api/profiles` routes, `web/index.html`) on dot-core's `DotHttpServer`. Read [docs/design.md](docs/design.md) first; it records what the family already has (no HTTP server) and what is not built.

**The distributable is `addons/dot_workbench/`.** `project.godot` and `examples/` exist to validate it alone. It requires dot-core (`ln -s ../../dot-core/addons/dot_core addons/dot_core`); everything else is duck-typed.

Also requires **dot-profile** (`DotProfileSet`, `DotProfile`, `DotProfileRuntime`, split from dot-core): link `addons/dot_profile` next to `addons/dot_core`.

- All profile rules (validation, revisions, audit, save) belong to `DotProfileRuntime`; do not copy them here.
- The HTTP server is dot-core's `DotHttpServer`; `DotWorkbenchHttp` only mounts routes on it. The page is `addons/dot_workbench/web/index.html` (one file, no build); an export needs `*.html` in its include filter. The host calls `DotWorkbenchHttp.poll()` from `_process`.
- `DotWorkbenchPanel` is the in-game panel: it binds dot-menu's `DotProfileEditorScreen` (duck-typed, so dot-ui and dot-menu stay optional) to the api, so Apply, Reset and `save_to_server()` take the same permission path as HTTP. `tools/panel_shot.gd` needs dot-ui, dot-menu and dot-settings linked into `addons/` (gitignored).
- `DotWorkbenchOverlay` is the in-game window (toolbar over the editor) and `DotWorkbenchExport` the tuning round trip: it writes only values differing from `DotWorkbenchApi.baseline_value` (the value seen before the session's first edit) into `cfg/game/<game>/<kind>/<id>.yml`, a zip and a clipboard bundle, and imports any of the three through `api.handle`. Hosting is dot-game's `DotGameWorkbench`.
- `DotWorkbenchPublish` (and the CLI `tools/publish_avatar_content.gd`) uploads a wearable, action or avatar GLB (the overlay's "Make wearable" form, `DotWorkbenchWearableForm`, does wearables; the token comes from a file) to the site's `/api/avatar/v1/publish` with a creator token; the site validates and moderates, this only pre-checks fields and size. Suite: `examples/publish_selftest.tscn` (6 sections, 36 checks).
- Secrets (admin token, TLS key, creator token) are read from files only, never env or argv.
- Validate: `heavy -- godot --headless --path . --import`, parse every `.gd` with `--check-only`, then `heavy -- godot --headless --path . res://examples/workbench_selftest.tscn` (12 sections, 114 checks).
- `DotWorkbenchApi.forward` (Callable(req)) repeats each applied write elsewhere: a connected client's panel edits its local copy and forwards to the server, where dot-game's `DotGameWorkbenchRemote` checks it again (dot-game `docs/workbench.md`).
- `DotWorkbenchIdentity` gates `api.identity` by duck-typing (resolver Callable, uid and group allowlists, optional fallback permit); keep it free of dot-auth and dot-console references. CI is the shared dot-ci `@v1` (`.github/workflows`).
- `DotWorkbenchTrails` is the trail form's server side (ops `trail_list`, `trail_upload`, `trail_delete`; flag `trail`, which the admin token holds); `DotWorkbenchHttp.mount_trails` adds `/api/trails`. Validation is dot-trail's `DotTrailStore` (duck-typed). Suite: `examples/trails_selftest.tscn` (3 sections, 26 checks; link `addons/dot_trail`).
