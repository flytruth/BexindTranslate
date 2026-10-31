# BexindTranslate

> **Real-time, packet-level translation for Paper 1.21.1 — so every player reads your server in their own language.**

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)]()
[![Paper 1.21.1](https://img.shields.io/badge/Paper-1.21.1-brightgreen.svg)](https://papermc.io/)
[![Java 21](https://img.shields.io/badge/Java-21-orange.svg)](https://openjdk.org/)
[![ProtocolLib 5.3.0+](https://img.shields.io/badge/ProtocolLib-5.3.0+-red.svg)](https://github.com/dmulloy2/ProtocolLib)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)]()

BexindTranslate intercepts chat, UI, and system packets *before* they hit the client and swaps in a translation on the fly. No client mods. No per-message commands. No lag spikes. Just a fully localized server experience backed by a resilient multi-provider failover chain, a WAL-mode SQLite store, and a two-tier Caffeine cache.

---

## Why BexindTranslate?

<table>
<tr>
<td width="50%" valign="top">

### 🌍 Players stop being second-class citizens
Non-English speakers see chat, titles, boss bars, tab lists, inventory names, and advancement toasts in their language — automatically.

</td>
<td width="50%" valign="top">

### 🔁 Your server keeps talking, even when an API doesn't
A live failover chain rotates through Google → Gemini → LibreTranslate → Ollama the moment a quota runs dry or an endpoint drops.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### ⚡ Repeated strings are free
The dual-tier Caffeine cache answers repeat lookups in **sub-millisecond** time, so spamming the same boss-bar text doesn't cost you a single API call.

</td>
<td width="50%" valign="top">

### 🛡️ Quotas are protected
A token-bucket rate limiter caps outbound requests, so you never trip a provider's abuse detection.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### 💾 Nothing gets lost on a crash
SQLite runs in **Write-Ahead Logging (WAL)** mode for concurrent-safe, crash-resilient local persistence.

</td>
<td width="50%" valign="top">

### 🎛️ Customizable join menu
An interactive language-selection GUI on player join — forced or optional, your call.

</td>
</tr>
</table>

---

## Feature Breakdown

### Packet-Level Translation Engine
Intercepts server-side network packets dynamically for low-latency, context-aware translation — no client-side mods required.

### Provider Failover Chain
Seamless rotation across translation backends when a quota is hit or an endpoint goes down:

| Provider | Type | Notes |
|---|---|---|
| Google Translate | Cloud API | Fast, broad language coverage |
| Gemini API | Cloud LLM | Context-aware, high quality |
| LibreTranslate | Self-hostable | Open source, privacy-friendly |
| Ollama | Local AI | Fully offline, no data leaves your machine |

### Extensive Packet Coverage

<table>
<tr>
<td width="50%" valign="top">

| Surface | Packet |
|---|---|
| Chat & system messages | `SYSTEM_CHAT`, unsigned player chat |
| Action bars & titles | `SET_TITLE_TEXT`, `SET_SUBTITLE_TEXT`, `SET_ACTION_BAR_TEXT` |
| Boss bars | `BOSS` |

</td>
<td width="50%" valign="top">

| Surface | Packet |
|---|---|
| Player tab list | `PLAYER_INFO` |
| Inventory & container titles | `OPEN_WINDOW` |
| Advancement notifications | `ADVANCEMENTS` |

</td>
</tr>
</table>

### Robust Cache & Database Pipeline
- **Dual-tier Caffeine in-memory cache** — sub-millisecond repeated lookups.
- **SQLite with WAL mode** — crash-resilient persistence, safe for concurrent reads/writes.

### Smart Rate Limiting & Filter Logic
- **Token-bucket rate limiter** — eliminates provider API ban risk.
- **Language match skip** — skips translation when source == target language.
- **Negative cache** — prevents endless lookup loops on un-translatable strings and formatting tokens.

---

## Commands & Permissions

| Command | Description | Permission |
|---|---|---|
| `/lang` | Opens the language-selection GUI. | *None — available to all players* |
| `/btr stats` | Live translation stats, cache hit-rates, and provider health. | `bexindtranslate.admin` |
| `/btr debug` | Toggles live console debug logging for packet inspection. | `bexindtranslate.admin` |
| `/btr reload` | Hot-reloads `config.yml`, providers, and regex ignore patterns. | `bexindtranslate.admin` |

---

## Installation

<table>
<tr>
<td width="50%" valign="top">

### Option 1 — Drop-in
1. Place `BexindTranslate-2.0.0.jar` into `plugins/`.
2. Ensure **ProtocolLib** is in the same directory.
3. Start or restart the server to generate the database and config.

</td>
<td width="50%" valign="top">

### Option 2 — Build from source
Compile the shaded JAR and prep your server in one shot:

```bash
bash BexindTranslate-2.0.0-installer.sh
```

</td>
</tr>
</table>

---

<p align="center"><em>Built for servers that refuse to leave anyone out of the conversation.</em></p>
