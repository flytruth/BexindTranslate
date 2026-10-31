# BexindTranslate

> Packet-level translation for Paper 1.21+ Players read your server in their own language, and you don't have to think about it.

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)]()
[![Paper 1.21.1](https://img.shields.io/badge/Paper-1.21.1-brightgreen.svg)](https://papermc.io/)
[![Java 21](https://img.shields.io/badge/Java-21-orange.svg)](https://openjdk.org/)
[![ProtocolLib 5.3.0+](https://img.shields.io/badge/ProtocolLib-5.3.0+-red.svg)](https://github.com/dmulloy2/ProtocolLib)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)]()

BexindTranslate sits between your server and the client and translates packets as they go out. No client mods, no commands for players to remember, no lag spikes. Behind it there's a failover chain across four translation backends, a SQLite database in WAL mode, and a two-tier Caffeine cache.

---

## What it actually does

<table>
<tr>
<td width="50%" valign="top">

### Players don't get left out
Chat, titles, boss bars, tab list, inventory names, advancement toasts — all translated before the packet reaches the client.

</td>
<td width="50%" valign="top">

### One provider goes down, another picks up
Google → Gemini → LibreTranslate → Ollama. The chain rotates on its own when a quota runs out or an endpoint stops responding.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### The same string twice costs nothing
Repeated lookups hit the Caffeine cache and come back in under a millisecond. A boss bar that updates every tick doesn't burn API calls.

</td>
<td width="50%" valign="top">

### Outbound requests are capped
A token-bucket limiter keeps you under provider rate limits, so you're not going to get flagged for hammering an API.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### A crash won't eat your data
SQLite runs in WAL mode — safe for concurrent reads and writes, and it survives a hard stop without corrupting the database.

</td>
<td width="50%" valign="top">

### Language menu on join
A GUI players see when they connect. Make it required or optional — either way it's configurable.

</td>
</tr>
</table>

---

## Details

### How translation works
Packets are intercepted server-side before they reach the client, translated, and sent on. Latency is low enough that players won't notice, and there's nothing to install on their end.

### Provider failover
When a provider hits a quota or goes down, the next one in the chain takes over:

| Provider | Type | Notes |
|---|---|---|
| Google Translate | Cloud API | Fast, covers a lot of languages |
| Gemini API | Cloud LLM | Better with context, higher quality |
| LibreTranslate | Self-hostable | Open source, you keep the data |
| Ollama | Local AI | Fully offline, nothing leaves your machine |

### What gets translated

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

### Caching and storage
Two tiers of Caffeine cache in memory for repeated strings, backed by SQLite in WAL mode for persistence. Both run concurrently without locking each other out.

### Filtering
- Token-bucket rate limiter on outbound calls.
- If the source and target language match, translation is skipped entirely.
- Negative cache stops the plugin from re-querying strings it already knows it can't translate — formatting tokens, for example.

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
1. Drop `BexindTranslate-2.0.0.jar` into `plugins/`.
2. Make sure **ProtocolLib** is in the same folder.
3. Start the server. The database and config generate on first boot.

</td>
<td width="50%" valign="top">

### Option 2 — Build from source
Compiles the shaded JAR and sets up the server directory in one step:

```bash
bash BexindTranslate-2.0.0-installer.sh
```

</td>
</tr>
</table>

---

<p align="center"><em>For servers where not everyone speaks English.</em></p>
