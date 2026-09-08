# Twir completion (chatterino plugin)

A [chatterino](https://chatterino.com) plugin that autocompletes [Twir](https://twir.app) channel commands while you type.

Inspired by [supibot-completion-plugin](https://github.com/Mm2PL/supibot-completion-plugin).

## Features

- Completes commands of the channel you are currently typing in, e.g. `!` → `!watchtime`, `!ban`, `!7tv emote`, …
- Understands multi-word command names: `!game ali` → `!game alias list`, `!game alias remove`, …
- Case-insensitive, works with non-ascii command names.
- Commands are fetched from the Twir public API per channel:
  `GET https://twir.app/api/v2/public/channels/twitch/{channelId}/commands`
- Fetched in the background, cached in memory and on disk, refreshed after `ttl` seconds (default 15 min).
- No build step — plain Lua.

## Requirements

- chatterino with plugins support enabled (Settings → Plugins).
- The plugin uses `Network` and `Filesystem` permissions (see `info.json`).
- Automatic detection of the active channel uses `c2.windows` (chatterino builds after April 2026, [#6687](https://github.com/Chatterino/chatterino2/pull/6687)).
  On older builds the plugin falls back to the last known channel — run `/twirc:reload <channel>` once if completions don't show up.

## Install

1. Find your chatterino plugins directory (Settings → Plugins → open the folder).
2. Copy this repository into a new directory there, e.g. `plugins/twir-completion/`, so that `init.lua` and `info.json` sit next to each other.
3. Enable the plugin in Settings → Plugins.
4. Open a Twitch channel with Twir in it and type `!` — commands load in the background and are cached for the next time.

## Usage

| Input | Result |
| --- | --- |
| `!` | list of all channel commands in the completion |
| `!wa` | `!watchtime` |
| `!game ali` | `!game alias add`, `!game alias list`, `!game aliase add`, … |
| `!chat wall ban` | finishes the word: `!chat wall ban ` |

Completion values replace the word being typed, exactly like chatterino's built-in completion.

### Showing the command list on screen

Chatterino's Tab completion is inline-only (it just cycles matches, there is no popup for it —
the popup is reserved for `@` usernames and `:` emotes). If you want to *see* the list of
commands, the plugin can print it into chat:

| Command | Result |
| --- | --- |
| `/twirc:list` | all commands of the channel, compact (`!7tv add • !7tv copy • …`) |
| `/twirc:list full` | one command per message, including descriptions |
| `/twirc:list <channel>` | list for an open channel other than the active one |

There is also a **"Show Twir commands"** entry in the channel context menu
(right click on the chat view) on builds with the window API.

Bind a hotkey for it: Action `Run a command`, Arguments `/twirc:list`.

### Commands

| Command | Description |
| --- | --- |
| `/twirc:list [full] [channel]` | Print the command list into chat (`full` adds descriptions). |
| `/twirc:reload` | Force a refresh of the commands of the active channel. |
| `/twirc:reload <channel>` | Force a refresh for an open channel by name. |
| `/twirc:complete {input.text};` | Print completions for the given text into the chat. |
| `/twirc:clear` | Drop the cached commands. |

### Hotkey for listing completions

Add a hotkey (Settings → Hotkeys) if you want to list completions for the current input:

| Key | Value |
| --- | --- |
| Name | twir complete |
| Category | `Split` |
| Action | `Run a command` |
| Keybinding | any, e.g. `Ctrl+Space` |
| Arguments | `/twirc:complete {input.text};` |

## Configuration

Optional `config.json` inside the plugin **data** directory (Settings → Plugins → open plugin data folder):

```json
{
    "prefix": "!",
    "ttl": 900,
    "api_base": "https://twir.app/api/v2",
    "http_timeout": 10000
}
```

| Key | Default | Description |
| --- | --- | --- |
| `prefix` | `"!"` | The prefix Twir commands are invoked with in chat. |
| `ttl` | `900` | Seconds until the cached command list is refreshed in the background. |
| `api_base` | `"https://twir.app/api/v2"` | Base URL of the Twir public API. |
| `http_timeout` | `10000` | HTTP request timeout in milliseconds. |

`cache.json` (in the same data directory) is managed by the plugin.

## Development

The plugin is plain Lua (5.4), no transpiling. Syntax check and unit tests:

```sh
luac5.4 -p *.lua
lua5.4 tests/test.lua .
```

The test suite stubs the `c2` API and covers the completion logic, caching, HTTP handling and the plugin commands.

## License

MIT, see [LICENSE](LICENSE). Vendored [rxi/json.lua](https://github.com/rxi/json.lua) is used as a JSON fallback for older chatterino builds (newer builds provide `chatterino.json`).
