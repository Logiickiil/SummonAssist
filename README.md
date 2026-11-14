# Summon Assistant

Warlock summoning team manager for **World of Warcraft: Forever** (`1.60.1` / `Interface: 16001`). Automates whisper and Battle.net auto-invites, tracks live Soul Shards and Warlock turn rotation across zones, monitors public chat for summon requests, and syncs a community blacklist.

## Features
- **Keyword Auto-Invite & Battle.net Support:** Standalone keyword matching (`123`, `sum`, `inv`, etc.) on standard whispers and Battle.net friend whispers, automatic party-to-raid conversion, and customizable confirmation whispers.
- **Live Soul Shard Tracker & Warlock Rotation:** Tracks Soul Shards (Item ID `6265`) and Ritual of Summoning casts (Spell ID `698`), skips offline or shard-depleted Warlocks, displays servicing areas, and syncs state across zones via group channels and peer-to-peer whisper fallbacks.
- **Public Chat Watcher & Destination Tagging:** Scans Trade, World, LFG, Say, and Yell for summon requests, tags 20+ Classic hubs (UC, Org, SW, IF, Booty Bay, ZG, Felwood, Dire Maul, BRM, AQ, etc.), displays chat excerpts with full-message hover tooltips, and filters by keyword or servicing area.
- **Community Blacklist (`SSBL1`):** Real-time blacklist sync across party, raid, guild, and background channels with import/export strings.
- **Multi-Channel Ad Broadcaster:** Posts formatted recruitment ads across multiple numbered channels, `YELL`, or `SAY` with dynamic token replacement.

## Installation
1. Download the latest `SummonAssistant.zip` from the [Releases](../../releases) page.
2. Extract it into your WoW Forever AddOns directory so the folder structure is:
   `World of Warcraft\_forever_\Interface\AddOns\SummonAssistant\SummonAssistant.toc`
3. Restart the client or type `/reload` in-game.

## Slash Commands
| Command | Description |
| :--- | :--- |
| `/sa` or `/summonassistant` | Toggle the Summon Assistant window (`/ss` also supported) |
| `/sa ad` | Broadcast your ad to all configured channels |
| `/sa testad` | Preview your formatted ad locally without broadcasting |
| `/sa testwhisper` | Preview your auto-invite confirmation whisper locally |
| `/sa sync` | Force a manual shard/rotation sync across your Warlock team |
| `/sa area <location>` | Set and broadcast your current servicing area |
| `/sa debug` | Toggle live `[Comms TX]` / `[Comms RX]` packet logging |

## Dynamic Message Tokens
- **Ad Message Tokens:** `{loc}`, `{price}`, `{kw}`, `{keywords}`, `{shards}`, `{summoner}`
- **Auto-Invite Whisper Tokens:** `{player}`, `{loc}`, `{price}`, `{summoner}`, `{shards}`

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup, WoW Forever (`16001`) API guidelines, and Pull Request instructions.
