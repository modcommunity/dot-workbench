# dot-workbench

Live-edit profiles on a running game through a JSON API over `DotProfileRuntime`, and an off-by-default loopback HTTP page. See [docs/design.md](docs/design.md). Status: API, HTTP adapter and page built; the in-game panel lives in each game (game-playground has one).

Enable it in `cfg/server.yml` (the token lives in a file, never in the yml, environment or command line):

```yaml
workbench:
  enabled: true
  bind: 127.0.0.1
  port: 8790
  token_file: /etc/dot/workbench.token
```

The host creates `DotWorkbenchHttp.new(api)`, calls `start_from_config(DotWorkbenchHttp.read_config())` and `poll()` from `_process`. Routes: `GET /` the page; `POST /api` the JSON envelope; `GET /api/profiles[/kind[/id]]`, `PUT /api/profiles/kind/id/key` with `{"value": ...}`, `DELETE /api/profiles/kind/id[/key]`, `POST /api/profiles/save/kind/id`, all with `Authorization: Bearer <token>`.

An exported host needs `*.html` in the preset's `include_filter`, or the page is missing from the pack ([design](docs/design.md#hosting-it-in-a-game-and-exporting-it)).

## Tuning and sending back defaults

Inside a game the workbench is a window on **F9** (or the console command `workbench`). It is on in the editor, in debug builds and for whoever hosts a listen game, and off in a production build. Pick a profile, change values, press Apply: the change is live at once. Nothing is saved until you ask.

When the game feels right, press **Export changes as defaults**. It writes only the values that differ from the shipped defaults, one small yml per profile in the repository's own `cfg/` layout, to `user://workbench-export/<date_time>/`, as a zip beside that folder, and as one block of text on your clipboard. Send the zip or paste the text back. To adopt it, copy the `cfg/` folder over the repository's `cfg/` and commit; `game-cvars.yml`, when present, goes into the `cvars:` block of `game.yml`.

To try somebody else's tuning, press **Import** and paste the text, or type the path of an export folder or zip, then Apply. It goes through the same checks as any edit: out-of-range values and profiles this game does not have are skipped and listed, never applied.

`DotWorkbenchExport` is the class behind both buttons (`collect()`, `export_changes()`, `import_source(actor, source)`); `DotWorkbenchOverlay` is the window. A game hosts them with dot-game's `DotGameWorkbench` ([dot-game docs/workbench.md](../dot-game/docs/workbench.md)).

## Identity (dot-auth, dot-console)

`DotWorkbenchIdentity` is the admin-only gate for `api.identity`. Nothing is imported: the host gives it a `resolver` Callable(token) returning a `DotAuthIdentity` (or a Dictionary with `uid`), and optionally a `fallback_permit` Callable(uid, flag) backed by dot-server's admin manager or the console's permissions. Deny by default: only `admin_uids` and members of `admin_groups` get in; guests, expired and uid-less identities never do. Admitted actors are `id:<uid>`, so the runtime's audit line names them; tokens are never logged. `gate.attach(api)` installs it; the admin token keeps working beside it.
