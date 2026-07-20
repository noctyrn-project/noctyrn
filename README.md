# Noctyrn — Tactical Shooter

A multiplayer tactical shooter built with Bevy (client) and Axum/Tokio (server).

## Getting started

This repo contains only a flake and a readme, but is intended to be the base development path.

To get started, git clone the game, server, shared and website repos to this directory. Each of them are their own seperate git repos.

## Architecture

### Project Structure

| Crate | Purpose |
|---|---|
| `noctyrn-shared` | Protocol types (`ClientMessage`/`ServerMessage`), game mode enums, lobby/party data structures. Used by both client and server. |
| `noctyrn-server` | HTTP auth + profile API (Axum), TCP lobby/party/matchmaking (Tokio raw TCP), UDP game session relay. |
| `noctyrn-game` | Bevy client — rendering, input, networking, UI. |
| `noctyrn-website` | Landing page (static HTML). |

### Networking

#### HTTP (Auth + Friends)
- Axum REST API on `:8080`.
- Endpoints: `POST /auth/register`, `POST /auth/login`, `GET /profile`, `POST /friends/add`, etc.
- Stateless JWT auth. Token returned on login, sent as `Authorization: Bearer <token>`.

#### TCP (Lobby, Party, Matchmaking)
- Raw TCP on `:7878`. Length-prefixed JSON framing (4-byte big-endian length + payload).
- **Auth handshake**: first message must be `Authenticate { token }`. Server responds with `Authenticated { user_id }`.
- After auth, server registers a push channel per user.
- Messages: `PartyInvite`, `PartyAcceptInvite`, `PartyCreateLobby`, `SetReady`, `PartyStartSearch`, `CancelMatchmaking`, etc.
- Push: `PartyInviteReceived`, `PartyUpdate`, `LobbyUpdate`, `MatchmakingStatus`, `MatchFound`.

#### UDP (Gameplay)
- Raw UDP on `:7877`. Binary-encoded state snapshots.
- Server sends world state at ~20 Hz. Clients send input at ~60 Hz.
- No ordering guarantees — dead reckoning on client.

### Systems

#### Auth Flow
1. Client sends `POST /auth/login` (HTTP).
2. Server returns JWT + user_id.
3. Client stores token, connects TCP, sends `Authenticate`.
4. Server verifies JWT, registers push channel.
5. Client can now send/receive party/lobby/matchmaking messages.

#### Party System
- **Invite**: friend-list "P" button sends `PartyInvite { username }`. Recipient gets `PartyInviteReceived` push → overlay popup with Accept/Decline.
- **Party state**: `PartyManager` (`noctyrn-server/src/lobby/party.rs`) stores `Party { id, leader, members }`. Size limit: 4.
- **Lobby creation**: party leader sends `PartyCreateLobby { game_mode }` → server creates lobby with all party members → pushes `LobbyUpdate` to all.
- **Ready/Unready**: each member sends `SetReady { ready: bool }`. Server tracks per-player ready state.
- **Matchmaking**: leader sends `PartyStartSearch` → queue party → `try_match` pairs groups → creates `GameSession` → pushes `MatchFound`.
- **Party leave**: any member sends `PartyLeave` → server dissolves party or promotes new leader.

#### Lobby
- `LobbyManager` holds active lobbies with player list, ready states, game mode.
- `LobbyUpdate` push refreshes all members' UIs.
- Leave button sends `PartyLeave` → back to main menu.

#### Matchmaking
- `MatchmakingQueue` collects parties/players.
- `try_match` runs on a timer (currently every 5s). Pairs compatible groups.
- On match: creates `GameSession`, pushes `MatchFound { lobby_id, server_addr, udp_port }`.
- Cancel sends `CancelMatchmaking` → removed from queue.

#### Game Sessions
- `GameSession` tracks connected players, their teams, and session state.
- UDP server runs per session, broadcasting state snapshots.
- On disconnect: session ends, players return to menu.

### Data Flow (Full Match)
```
[Login] → HTTP auth → TCP connect → [Lobby] → PartyCreateLobby → LobbyUpdate
→ SetReady → PartyStartSearch → [Matchmaking] → MatchFound → [Playing]
```

## Commands

### Start PostgreSQL
```bash
nix-shell -p postgresql --run 'pg_ctl -D /tmp/pgdata -l /tmp/pgdata/pg.log start'
```

### Enter dev shell
```bash
nix develop
```
Sets `DATABASE_URL`, `JWT_SECRET`, and port env vars.

### Build
```bash
# All crates
cargo build --manifest-path noctyrn-server/Cargo.toml
cargo build --manifest-path noctyrn-game/Cargo.toml
```

### Run server
```bash
cargo run --manifest-path noctyrn-server/Cargo.toml
```
Starts HTTP on `:8080`, TCP on `:7878`, UDP on `:7877`.

### Run client
```bash
cargo run --manifest-path noctyrn-game/Cargo.toml
```
Requires a running server for auth, parties, and multiplayer.
