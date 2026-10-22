# dot-workbench design

dot-workbench is the admin live-edit surface on top of `DotProfileRuntime` (dot-core, `docs/profiles.md`). It owns no profile logic: validation, revisions, replication, audit and the save-to-server-tier all stay in the runtime. The workbench moves dictionaries to it and back, and (later) hosts a page and an HTTP endpoint.

## What already exists (investigated 2026-10-22)

- **No HTTP server exists in the family.** dot-server's `DotRconServer` is Source-style RCON over TCP plus a WebSocket listener (the WebSocket handshake is `WebSocketPeer.accept_stream()`, not a request/response server). dot-server-query's `DotQueryServer` is UDP (DQP/A2S) with a TCP side for DQP. dot-net has transports and replication, no HTTP. dot-core's `DotHttp` is a client. `dot-serve` is a Python tool, not an in-game server.
- So the HTTP adapter cannot be hosted by an existing server and is not written here. Writing a second one-off server inside this addon was refused; the owner is the shared `DotHttpServer` in dot-core's `net/` (built 2026-10-22) (built on `TCPServer`, `TLSOptions` for native TLS), which dot-workbench and anything else would use. That is filed as a follow-up on the board.
- What the runtime exposes: `handle_request(actor, req)` for `set`, `reset_key`, `reset`, `save`, returning a `DotResult` whose value is the changed row; `permit(actor, flag)` with `edit_flag` `cvar` and `save_flag` `root`; `revision(kind, id)`; `profile_changed` signal; INFO audit line per edit. It has no list or get; `DotProfileSet` supplies `list_ids`, `has_id`, `load_profile` and `runtime_paths`, which `DotWorkbenchApi` uses.

## Layers

1. **`DotWorkbenchApi`** (done): transport-agnostic. `handle(actor, req) -> DotResult`, `handle_json(token, text) -> String`, `authenticate(token)`, `to_reply(res)`.
2. **HTTP adapter** (`DotWorkbenchHttp`, done, on dot-core's `DotHttpServer`): also REST routes under `/api/profiles`; maps `POST /api` (JSON body, `Authorization: Bearer <token>`) to `handle_json`, and `GET /` to the static page. Needs the shared `DotHttpServer` above.
3. **Static page** (`web/index.html`, done): one `index.html`, hand-written CSS and plain JavaScript, no build step, no framework, no CDN, shipped inside the addon and served from memory. Modern look: system font stack, light and dark by `prefers-color-scheme`, a kind and profile picker, a table of fields with the effective value, the runtime override highlighted, inline edit with the server's validation error shown beside the field, per-field reset, a Save button that asks for confirmation.
4. **In-game panel** (done): `DotWorkbenchPanel` binds dot-menu's `DotProfileEditorScreen` (a `DotUiForm` inside) to `DotWorkbenchApi` through the screen's save, reset and has-override hooks, so Apply writes the live runtime layer as the given actor and `save_to_server()` writes cfg/server. A multi-key Apply that fails midway restores the earlier keys. Screenshot: `docs/workbench-ingame-dark.png`.

## JSON API

One request object in, one reply out. Request: `{"op", "kind", "id", "key", "value"}`.

| op | needs | value of the reply |
| --- | --- | --- |
| `list` (no `kind`) | `read_flag` (`cvar`) | `{kinds: [...]}` |
| `list` (`kind`) | same | `{kind, ids: [...]}` |
| `get` | same | `{kind, id, rev, values, extra, runtime}`: effective values, extras, and the runtime layer alone |
| `set` | `cvar` | the changed row `{kind, id, rev, paths}`, or `{changed: false}` |
| `reset_key` | `cvar` | the row |
| `reset` | `cvar` | the row |
| `save` | `root` | `{saved: path}` |

Reply: `{"ok": true, "value": ...}` or `{"ok": false, "error": {"code", "message"}}` where `code` is a `DotError.CODE_*` (`forbidden`, `invalid`, ...). Clients branch on `code`. Later ops (map cycle, waves, soak report) are new `op` names on the same envelope.

## Permission and auth

- Edits use the console's own path: `DotProfileRuntime.permit(actor, flag)`, `cvar` to edit and reset, `root` to save. `DotWorkbenchApi.permit` is where the host assigns its `DotAdminManager` check (duck-typed).
- Two ways to get an actor. **Admin token**: a long random string the operator puts in a secrets file (read file-only; never environment or argv, as `DotConfig.sensitive_keys`). It maps to one actor, `TOKEN_ACTOR`, which holds `token_flags` (default `cvar` and `root`). Comparison is constant time. **Identity**: assign `identity` a Callable(token) -> actor, which the host backs with dot-auth; the actor then goes through the normal flag check.
- No configured token and no identity means everything is refused. Refusals log WARN on channel `workbench`.

## Configuration: `cfg/server.yml`

```yaml
workbench:
  enabled: false          # off by default
  bind: 127.0.0.1         # loopback unless the operator changes it
  port: 8790
  tls:
    mode: proxy           # proxy (default): plain HTTP on loopback behind nginx/caddy; native: terminate here
    cert: /etc/dot/workbench.crt   # native only: paths, never contents
    key: /etc/dot/workbench.key
  token_file: /etc/dot/workbench.token   # secrets are file paths, never values in yml
  max_failures: 5         # failed tokens per address inside window_sec before a lockout (0 disables)
  window_sec: 60
  lockout_sec: 300        # 429 with Retry-After for this long
```

Layering is the family's: defaults < file < environment < command line, except that `token_file` contents and the TLS key are only ever read from the file. Binding to a non-loopback address with `mode: proxy` and no TLS logs a WARN at start. TLS is a reverse proxy by default (certificate renewal belongs there); native TLS is the option for a box with no proxy, using Godot's `TLSOptions.server(key, cert)`.

## Dependencies

dot-core only. dot-server (admin flags), dot-auth (identity), dot-ui and dot-menu (the in-game panel) are reached through Callables and `DotRegistry`, never imported.

## Not done

wiring `DotWorkbenchPanel` into a game's admin menu (game-playground has its own panel), a Save-to-server button in the screen. Identity wiring is `DotWorkbenchIdentity`; CI is `.github/workflows`.

## Hosting it in a game and exporting it

- The host builds `DotWorkbenchApi` over its `DotProfileRuntime`, adds its `DotProfileSet`s, wraps it in `DotWorkbenchHttp`, calls `start_from_config(DotWorkbenchHttp.read_config())` once the console's permit is set, `poll()` from `_process`, and `stop()` on unload. game-playground's `game/playground_workbench.gd` is the reference host. Without a `workbench:` block, or with `enabled: false`, nothing is opened.
- **An export must include `*.html`.** The page is `addons/dot_workbench/web/index.html`, a plain file, and Godot's exporter drops files it does not import unless the preset's `include_filter` names them. Without it the server starts and `GET /` answers an empty page, with no error. Add `*.html` to the include filter of every preset that ships a host (a server preset; web builds are clients and never host it). Verified 2026-10-22 with `--export-pack` on this repository: the pack lacks `web/index.html` with an empty filter and holds it with `*.html`.
- Set `page_path` to a file the host ships itself if it wants another page; it is read once at start.
