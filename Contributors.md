# Contributing to Summon Assistant

## Local Development Setup
1. Fork this repository and clone it directly into your WoW Forever AddOns folder:
   `World of Warcraft\_forever_\Interface\AddOns\SummonAssistant\`
2. Make your edits in `Core.lua`, `Comms.lua`, `InviteEngine.lua`, or `UI.lua`.
3. Type `/reload` in-game to test changes immediately.

## WoW Forever (`16001`) Coding Guidelines
- **Client Target:** Keep `## Interface: 16001` in `SummonAssistant.toc`.
- **Chat Safety:** Sanitize all outgoing chat/whisper text to strip unescaped pipe (`|`) characters and normalize realm names with `Ambiguate(name, "none")`.
- **Combat & Secret Values:** Guard any combat unit values or protected strings with `issecretvalue()` before performing Lua string/math operations.
- **Saved Variables:** Keep user settings backwards-compatible inside `SummonAssistantDB`.

## Submitting Changes
1. Create a feature branch (`git checkout -b fix/my-improvement`).
2. Commit clear, focused changes and push your branch to your fork.
3. Open a Pull Request against `main` describing what changed and how you tested it in-game.
