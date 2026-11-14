# dot-workbench

Live-edit profiles on a running game. A JSON API over `DotProfileRuntime`, an in-game window, and an off-by-default loopback web page. Tune values while playing, then export only what you changed.

## Install

1. Get [Godot 4.7](https://godotengine.org/download).
2. Either use [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap), which clones every project and links the addons, or copy `addons/dot_workbench/` and [dot-core](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable dot-workbench in *Project > Project Settings > Plugins*.

## Web page and API

Enable it in `cfg/server.yml`. The token lives in a file, never in the yml, environment or command line.

```yaml
workbench:
  enabled: true
  bind: 127.0.0.1
  port: 8790
  token_file: /etc/dot/workbench.token
```

The host creates `DotWorkbenchHttp.new(api)`, calls `start_from_config(DotWorkbenchHttp.read_config())` and calls `poll()` from `_process`. All routes except the page need `Authorization: Bearer <token>`.

| Route | Does |
| --- | --- |
| `GET /` | The page. |
| `POST /api` | The JSON envelope. |
| `GET /api/profiles[/kind[/id]]` | Read profiles. |
| `PUT /api/profiles/kind/id/key` with `{"value": ...}` | Change a value. |
| `DELETE /api/profiles/kind/id[/key]` | Reset a value or profile. |
| `POST /api/profiles/save/kind/id` | Save. |

An exported host needs `*.html` in the preset's `include_filter`, or the page is missing from the pack ([design](docs/design.md#hosting-it-in-a-game-and-exporting-it)).

## In-game window

The workbench is a window on the `;` key, rebindable as `bind_workbench` in the controls settings, or the console command `workbench`. It is on in the editor, in debug builds and for whoever hosts a listen game, and off in a production build. Pick a profile, change values, press Apply. The change is live at once, and nothing is saved until you ask.

When the game feels right, press **Export changes as defaults**. It writes only the values that differ from the shipped defaults, one small yml per profile in the repository's `cfg/` layout, to `user://workbench-export/<date_time>/`, as a zip beside that folder, and as text on your clipboard. To adopt it, copy the `cfg/` folder over the repository's `cfg/` and commit; `game-cvars.yml`, when present, goes into the `cvars:` block of `game.yml`.

To try somebody else's tuning, press **Import** and paste the text, or give the path of an export folder or zip, then Apply. It goes through the same checks as any edit: out-of-range values and unknown profiles are skipped and listed.

| Class | Role |
| --- | --- |
| `DotWorkbenchExport` | Behind both buttons: `collect()`, `export_changes()`, `import_source(actor, source)`. |
| `DotWorkbenchOverlay` | The window. |
| `DotWorkbenchScope` | Tags a set with owner, side, `requires` and `listed`, so the window only lists what is loaded. |
| `DotWorkbenchSetView` | One heading per member of a grouped set, such as one per weapon pack. |

A game hosts the window with dot-game's `DotGameWorkbench` (see dot-game's `docs/workbench.md`).

## Identity

`DotWorkbenchIdentity` is an admin-only gate for `api.identity`, a thin subclass of dot-core's `DotAdminIdentity`. Nothing is imported: the host gives it a `resolver` Callable(token) returning a `DotAuthIdentity` or a Dictionary with `uid`, and optionally a `fallback_permit` Callable(uid, flag) backed by an admin manager. Access is denied by default: only `admin_uids` and members of `admin_groups` get in. Actors are logged as `id:<uid>`, and tokens are never logged. `gate.attach(api)` installs it, and the admin token keeps working beside it.

## Testing

Import the project once, then run `examples/workbench_selftest.tscn` headless with Godot. Design notes: [docs/design.md](docs/design.md).

## Status and licence

Part of the TMC **dot-\*** family of Godot addons. Written with Claude Code and maintained by `gamemann`. Every addon has headless tests, but little of this has been played by real users yet, so expect rough edges and please [open an issue](https://github.com/modcommunity/dot-workbench/issues) when you hit one.

MIT licence, see [LICENSE](LICENSE). The only closed part of the TMC platform is the web back end; you can use your own instead of TMC's.
