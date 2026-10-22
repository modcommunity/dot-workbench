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

## Identity (dot-auth, dot-console)

`DotWorkbenchIdentity` is the admin-only gate for `api.identity`. Nothing is imported: the host gives it a `resolver` Callable(token) returning a `DotAuthIdentity` (or a Dictionary with `uid`), and optionally a `fallback_permit` Callable(uid, flag) backed by dot-server's admin manager or the console's permissions. Deny by default: only `admin_uids` and members of `admin_groups` get in; guests, expired and uid-less identities never do. Admitted actors are `id:<uid>`, so the runtime's audit line names them; tokens are never logged. `gate.attach(api)` installs it; the admin token keeps working beside it.
