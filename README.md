# dot-workbench

Live-edit profiles on a running game through a JSON API over `DotProfileRuntime`, and an off-by-default loopback HTTP page. See [docs/design.md](docs/design.md). Status: API, HTTP adapter and page built; the in-game panel is not.

Enable it in `cfg/server.yml` (the token lives in a file, never in the yml, environment or command line):

```yaml
workbench:
  enabled: true
  bind: 127.0.0.1
  port: 8790
  token_file: /etc/dot/workbench.token
```

The host creates `DotWorkbenchHttp.new(api)`, calls `start_from_config(DotWorkbenchHttp.read_config())` and `poll()` from `_process`. Routes: `GET /` the page; `POST /api` the JSON envelope; `GET /api/profiles[/kind[/id]]`, `PUT /api/profiles/kind/id/key` with `{"value": ...}`, `DELETE /api/profiles/kind/id[/key]`, `POST /api/profiles/save/kind/id`, all with `Authorization: Bearer <token>`.
