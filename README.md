# Noctyrn — Tactical Shooter

A multiplayer tactical shooter built with Bevy (client) and Axum/Tokio (server).

## Roadmap

- [x] Branding + splash/loading screens (logo, icon, animated intro)
- [ ] Add branding to the game, and overhaul UI (in progress)
- [ ] Continue to polish movement system
- [ ] Add more guns, gun handling, gun customization and more
- [ ] Add more maps, as well as detailed maps
- [ ] Revamp gun crate system and add more advanced weapon skins
- [ ] Fix friends and party system
- [ ] Add proper player models and dynamic animations
- [ ] Overhaul recoil system
- [ ] Add mascot
- [ ] Add skybox
- [ ] Add admin console
- [ ] Add Audio and sound effects

## Known issues

- [x] When spamming space next to a wall, the player can jump and climb up the wall.
- [x] Walls colisions work well, but brushing up against a wall will cuase the player to move very slowly.
- [ ] Dolphin diving camera is bugged
- [x] Rotated meshes don't properly generate convex hulls

## Repo layout

This repo contains only a flake and this README. The game, server, shared code,
website and extras are each their own separate git repositories, cloned side by
side:

| Directory        | Repository            | Purpose |
|------------------|-----------------------|---------|
| `noctyrn-game`   | the game client       | Bevy client — rendering, input, networking, UI |
| `noctyrn-server` | the game server       | HTTP auth + profile API (Axum), TCP lobby/party/matchmaking, UDP game sessions |
| `noctyrn-shared` | shared protocol       | `ClientMessage`/`ServerMessage` types, game mode enums, lobby/party data, map data |
| `noctyrn-website`| landing page          | Static marketing site |
| `noctyrn-extras` | assets + tooling      | Brand SVG sources + `bake/` tool that converts them to game PNGs |

## Getting started

### Prerequisites

- [Nix](https://nixos.org/download/) with flakes enabled — the dev shell
  provides the Rust toolchain, Bevy system libraries, and PostgreSQL.
- PostgreSQL (see below) for the server.

### Enter the dev shell

```bash
nix develop
```

This sets `DATABASE_URL`, `JWT_SECRET`, and the HTTP/TCP/UDP port env vars
needed by the server.

### Start PostgreSQL

```bash
nix-shell -p postgresql --run 'pg_ctl -D /tmp/pgdata -l /tmp/pgdata/pg.log start'
```

(Create `/tmp/pgdata` with `initdb` first if it doesn't exist.)

### Run the server

```bash
cargo run --manifest-path noctyrn-server/Cargo.toml
```

Starts HTTP on `:8080`, TCP on `:7878`, UDP on `:7877`.

### Run the client

```bash
cargo run --manifest-path noctyrn-game/Cargo.toml
```

Requires a running server for auth, parties, and multiplayer; offline play is
also supported from the main menu.

### Build / test

```bash
# All crates
cargo build --manifest-path noctyrn-server/Cargo.toml
cargo build --manifest-path noctyrn-game/Cargo.toml

# Client tests (movement/collision)
cargo test --manifest-path noctyrn-game/Cargo.toml --bin noctyrn collision::tests
```

## Asset pipeline

The brand SVGs in `noctyrn-extras/assets/ui/` are the editable source of
truth — Bevy cannot load SVGs, so production assets are baked to PNGs and
committed into `noctyrn-game/assets/ui/`:

| Source SVG       | Baked output             | Used for |
|------------------|--------------------------|----------|
| `logo.svg`       | `logo.png` (1024²)       | project logo |
| `icon.svg`       | `icon.png` (512²)        | game icon (tray/launch, future work) |
| `noctyrn.svg`    | `noctyrn.png` (1024×171) | stylized wordmark — main menu title (final animation frame) |
| `animation.svg`  | `noctyrn_anim_sheet.png` | splash + loading screen animation (6×5 grid of 1024×171 cells = 30 frames) |

resvg ignores SMIL animations, so the bake tool samples the animation timeline
itself. To re-bake after editing an SVG:

```bash
cd noctyrn-extras/bake
cargo run --release                      # writes PNGs into ../noctyrn-game/assets/ui/
cargo run --release -- --dump-frames     # also dumps individual frames to /tmp/noctyrn-frames
```

The sprite sheet layout (cell size, grid) is mirrored in
`noctyrn-game/src/branding.rs` (`SHEET_*` constants) — keep them in sync when
changing the bake output.

## Game screens

- **Splash** — shown at boot: holds the first logo frame 0.5s, plays the
  30-frame animation over 1.0s, holds the final frame 0.5s, then enters the
  main menu. Also pre-loads (and waits for) the lobby scene so the menu
  background appears instantly.
- **Loading** — shown when joining a match (offline play or matchmaking) and
  when leaving one: same animation. Joining waits for the map's GLB assets to
  finish loading before entering gameplay.

## Networking

### HTTP (Auth + Friends)
- Axum REST API on `:8080`.
- Endpoints: `POST /auth/register`, `POST /auth/login`, `GET /profile`, `POST /friends/add`, etc.
- Stateless JWT auth. Token returned on login, sent as `Authorization: Bearer <token>`.

### TCP (Lobby, Party, Matchmaking)
- Raw TCP on `:7878`. Length-prefixed JSON framing (4-byte big-endian length + payload).
- **Auth handshake**: first message must be `Authenticate { token }`. Server responds with `Authenticated { user_id }`.
- After auth, server registers a push channel per user.
- Messages: `PartyInvite`, `PartyAcceptInvite`, `PartyCreateLobby`, `SetReady`, `PartyStartSearch`, `CancelMatchmaking`, etc.
- Push: `PartyInviteReceived`, `PartyUpdate`, `LobbyUpdate`, `MatchmakingStatus`, `MatchFound`.

### UDP (Gameplay)
- Raw UDP on `:7877`. Binary-encoded state snapshots.
- Server sends world state at ~20 Hz. Clients send input at ~60 Hz.
- No ordering guarantees — dead reckoning on client.

### Auth Flow
1. Client sends `POST /auth/login` (HTTP).
2. Server returns JWT + user_id.
3. Client stores token, connects TCP, sends `Authenticate`.
4. Server verifies JWT, registers push channel.
5. Client can now send/receive party/lobby/matchmaking messages.

### Party System
- **Invite**: friend-list "P" button sends `PartyInvite { username }`. Recipient gets `PartyInviteReceived` push → overlay popup with Accept/Decline.
- **Party state**: `PartyManager` (`noctyrn-server/src/lobby/party.rs`) stores `Party { id, leader, members }`. Size limit: 4.
- **Lobby creation**: party leader sends `PartyCreateLobby { game_mode }` → server creates lobby with all party members → pushes `LobbyUpdate` to all.
- **Ready/Unready**: each member sends `SetReady { ready: bool }`. Server tracks per-player ready state.
- **Matchmaking**: leader sends `PartyStartSearch` → queue party → `try_match` pairs groups → creates `GameSession` → pushes `MatchFound`.
- **Party leave**: any member sends `PartyLeave` → server dissolves party or promotes new leader.

### Lobby
- `LobbyManager` holds active lobbies with player list, ready states, game mode.
- `LobbyUpdate` push refreshes all members' UIs.
- Leave button sends `PartyLeave` → back to main menu.

### Matchmaking
- `MatchmakingQueue` collects parties/players.
- `try_match` runs on a timer (currently every 5s). Pairs compatible groups.
- On match: creates `GameSession`, pushes `MatchFound { lobby_id, server_addr, udp_port }`.
- Cancel sends `CancelMatchmaking` → removed from queue.

### Game Sessions
- `GameSession` tracks connected players, their teams, and session state.
- UDP server runs per session, broadcasting state snapshots.
- On disconnect: session ends, players return to menu.

### Data Flow (Full Match)
```
[Login] → HTTP auth → TCP connect → [Lobby] → PartyCreateLobby → LobbyUpdate
→ SetReady → PartyStartSearch → [Matchmaking] → MatchFound → [Loading] → [Playing]
```

## Connecting to the production server

`ssh -i noctyrn_key.pem noctyrn@135.232.179.144` (when it's running).
