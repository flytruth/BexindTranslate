# BexindTranslate

A high-performance, packet-level automatic translation plugin built specifically for **Paper 1.21.1**. Powered by ProtocolLib, SQLite WAL persistence, Caffeine caching, token-bucket rate limiting, and multi-provider AI translation models.

---

## Features

- **Packet-Level Translation System**: Intercepts server-side network packets dynamically to provide low-latency, real-time context translations.
- **Provider Failover Chain**: Seamlessly fails over across translation services if an API quota is reached or an endpoint experiences downtime:
  - Google Translate
  - Gemini API
  - LibreTranslate
  - Ollama (Local AI models)
- **Extensive Packet Coverage**:
  - Chat & System Messages (`SYSTEM_CHAT`, Unsigned Player Chat)
  - Action Bars & Titles (`SET_TITLE_TEXT`, `SET_SUBTITLE_TEXT`, `SET_ACTION_BAR_TEXT`)
  - Boss Bars (`BOSS`)
  - Player Tab List (`PLAYER_INFO`)
  - Inventory & Container Titles (`OPEN_WINDOW`)
  - Advancement Notifications & Toasts (`ADVANCEMENTS`)
- **Robust Cache & Database Pipeline**:
  - Dual-tier Caffeine in-memory cache for sub-millisecond repeated string lookup.
  - SQLite back-end configured with **Write-Ahead Logging (WAL)** for crash-resilient local persistence and concurrent safe operation.
- **Smart Rate Limiting & Filter Logic**:
  - Built-in token-bucket rate limiter to eliminate provider API ban risks.
  - Automatic language match skip (skips translation when source language equals target language).
  - Negative cache mechanisms to prevent endless lookup loops on un-translatable strings or syntax formatting elements.
- **Customizable Player Join Menu**: Interactive, forced or optional language selection menu on player join.

---

## GitHub Statistics & Activity

<div align="center">

[![GitHub Stats](https://github-readme-stats.vercel.app/api?username=Daniel&show_icons=true&theme=tokyonight&hide_border=true&count_private=true)](https://github.com/Daniel)

[![Top Languages](https://github-readme-stats.vercel.app/api/top-langs/?username=Daniel&layout=compact&theme=tokyonight&hide_border=true)](https://github.com/Daniel)

[![GitHub Streak](https://github-readme-streak-stats.herokuapp.com/?user=Daniel&theme=tokyonight&hide_border=true)](https://github.com/Daniel)

</div>

---

## Commands & Permissions

| Command | Description | Permission Required |
|---|---|---|
| `/lang` | Opens the language selection GUI menu for the player. | *None (Available to all)* |
| `/btr stats` | Displays real-time translation statistics, cache hit-rates, and provider health. | `bexindtranslate.admin` |
| `/btr debug` | Toggles live debug logging in console for real-time packet inspection. | `bexindtranslate.admin` |
| `/btr reload` | Instantly reloads `config.yml`, translation providers, and regex ignore patterns. | `bexindtranslate.admin` |

---

## Requirements

- **Server Software**: Paper 1.21.1 (or compatible forks)
- **Java**: Java 21+
- **Dependency**: ProtocolLib 5.3.0+

---

## Fast Installation & Build

### Option 1: Direct Plugin Installation
1. Place `BexindTranslate-2.0.0.jar` into your server's `plugins/` directory.
2. Ensure **ProtocolLib** is installed in the same directory.
3. Start or restart your server to initialize the database and configuration file.

### Option 2: Build from Source Script
Run the automated shell script to compile the shaded JAR locally and prepare the server environment:

```bash
bash BexindTranslate-2.0.0-installer.sh
