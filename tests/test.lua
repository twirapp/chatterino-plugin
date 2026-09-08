-- Test harness for the twir-completion plugin (run outside chatterino).
-- Stubs the `c2` API and exercises the completion logic.

local fake_now_ms = 1000000000000

local requests = {} -- executed HTTP requests
local messages = {} -- system messages sent through the stubbed channels

local c2 = {}
c2.LogLevel = { Debug = 0, Info = 1, Warning = 2, Critical = 3 }
c2.EventType = { CompletionRequested = "CompletionRequested" }
function c2.log() end
local registered_commands = {}
function c2.register_command(name, fn) registered_commands[name] = fn end
local registered_callback = nil
function c2.register_callback(type, fn) registered_callback = fn end

c2.DateTime = {}
function c2.DateTime.current_utc()
    return {
        to_unix_milliseconds = function()
            return fake_now_ms
        end,
    }
end

c2.HTTPMethod = { Get = "get" }
c2.HTTPRequest = {}
function c2.HTTPRequest.create(method, url)
    local req = {
        url = url,
        method = method,
        headers = {},
        executed = false,
    }
    function req:set_timeout(ms) self.timeout = ms end
    function req:set_header(name, value) self.headers[name] = value end
    function req:on_success(cb) self.on_success_cb = cb end
    function req:on_error(cb) self.on_error_cb = cb end
    function req:finally(cb) self.finally_cb = cb end
    function req:execute()
        self.executed = true
        requests[#requests + 1] = self
    end
    return req
end

-- active twitch channel
local active_id, active_name = "1100730352", "justovich221337"

c2.Channel = {}
function c2.Channel.by_name(name)
    if name == active_name then
        return {
            is_valid = function() return true end,
            is_twitch_channel = function() return true end,
            get_twitch_id = function() return active_id end,
            get_name = function() return active_name end,
        }
    end
    return nil
end
function c2.Channel.by_twitch_id(id)
    if id == active_id then
        return c2.windows.last_selected_window.notebook.selected_page.selected_split.channel
    end
    return nil
end

-- context menu signal capture
local context_menu_callbacks = {}

c2.windows = {
    on_channelview_context_menu_requested = function(self, cb)
        context_menu_callbacks[#context_menu_callbacks + 1] = cb
    end,
    last_selected_window = {
        notebook = {
            selected_page = {
                selected_split = {
                    channel = {
                        is_valid = function() return true end,
                        is_twitch_channel = function() return true end,
                        get_twitch_id = function() return active_id end,
                        get_name = function() return active_name end,
                        add_system_message = function(self, msg) messages[#messages + 1] = msg end,
                    },
                },
            },
        },
    },
}

_G.c2 = c2

local plugin_dir = arg[1]
package.path = plugin_dir .. "/?.lua;" .. package.path

local completed, failed = 0, 0
local function check(name, cond)
    if cond then
        completed = completed + 1
        print("  ok   " .. name)
    else
        failed = failed + 1
        print("  FAIL " .. name)
    end
end

local function ev(text, query, is_first_word)
    return {
        full_text_content = text,
        query = query or "",
        cursor_position = #text,
        is_first_word = is_first_word,
    }
end

-- auto-detect query like chatterino would
local function ev_auto(text)
    local is_first_word = text:find("%s") == nil
    local query
    if is_first_word then
        query = text
    else
        query = text:match("(%S*)$") or ""
    end
    return ev(text, query, is_first_word)
end

print("loading modules")
local config = require("config")
local store = require("store")
local api = require("api")
local completions = require("completions")

check("default prefix", config.prefix == "!")
check("default ttl", config.ttl == 900)

local SEED = {
    { name = "watchtime", description = "" },
    { name = "age", description = "User account age" },
    { name = "ban", description = "" },
    { name = "linaryx", description = "" },
    { name = "game alias list", description = "" },
    { name = "game aliase remove", description = "" },
    { name = "game history", description = "" },
}
store.set(active_id, active_name, SEED)

local entry = store.get(active_id)
check("entry stored", entry ~= nil)
check("commands sorted", entry.commands[1].name == "age")
check("command count", #entry.commands == #SEED)

local function values(ev)
    local list = completions.on_completion(ev)
    return list
end

print("completion tests")

-- "!": everything, with prefix, hide others
local list = values(ev("!", "!", true))
check("bang all count", #list.values == #SEED)
check("bang all first", list.values[1] == "!age ")
check("bang hide_others", list.hide_others == true)

-- "!b" -> ban
list = values(ev("!b", "!b", true))
check("bang b single", #list.values == 1 and list.values[1] == "!ban ")

-- "!g" -> game commands
list = values(ev("!g", "!g", true))
check("bang g count", #list.values == 3)
check("bang g values", list.values[1] == "!game alias list "
    and list.values[2] == "!game aliase remove "
    and list.values[3] == "!game history ")

-- "!game alias l" -> "list "
list = values(ev_auto("!game alias l"))
check("multi word tail", #list.values == 1 and list.values[1] == "list ")

-- "!game a" -> alias list + aliase remove
list = values(ev_auto("!game a"))
check("multi word two", #list.values == 2
    and list.values[1] == "alias list "
    and list.values[2] == "aliase remove ")

-- "!game " -> all sub commands (empty query)
list = values(ev_auto("!game "))
check("after space", #list.values == 3 and list.values[1] == "alias list ")

-- "!game history " -> nothing matches anymore
list = values(ev_auto("!game history "))
check("finished command", #list.values == 0 and list.hide_others == false)

-- "!game h" -> history
list = values(ev_auto("!game h"))
check("sub command", #list.values == 1 and list.values[1] == "history ")

-- non command text -> nothing, don't hide others
list = values(ev_auto("hello guys"))
check("no prefix", #list.values == 0 and list.hide_others == false)

-- completed exact name gets a trailing space
list = values(ev_auto("!ban"))
check("exact name", #list.values == 1 and list.values[1] == "!ban ")

-- case insensitive
list = values(ev_auto("!GAME alias L"))
check("case insensitive", #list.values == 1 and list.values[1] == "list ")

print("refresh tests")

-- fresh entry: no fetch
store.set(active_id, active_name, SEED)
requests = {}
values(ev_auto("!a"))
check("fresh entry no fetch", #requests == 0)

-- stale entry: fetch started
store.set(active_id, active_name, SEED)
store.get(active_id).fetched_at = fake_now_ms - 1000 * 60 * 60
requests = {}
values(ev_auto("!a"))
check("stale entry fetch", #requests == 1)
check("fetch url", requests[1] ~= nil and requests[1].url
    == "https://twir.app/api/v2/public/channels/twitch/1100730352/commands")
check("fetch ua set", requests[1].headers["User-Agent"] ~= nil)

-- no duplicate fetch while pending
values(ev_auto("!a"))
check("pending dedup", #requests == 1)

-- completing still works while stale fetch is in flight
list = values(ev_auto("!age"))
check("stale served", #list.values == 1 and list.values[1] == "!age ")

print("api response handling")

-- success
local req = requests[1]
local body = '[{"name":"zeta","description":""},{"name":"alpha","description":"first"},{"name":"ban","description":"","module":"CUSTOM","group":"","responses":[{"text":"hi"}]}]'
req.on_success_cb({
    data = function() return body end,
    status = function() return 200 end,
    error = function() return "" end,
})
local updated = store.get(active_id)
check("stored fetched", #updated.commands == 3)
check("fetched sorted", updated.commands[1].name == "alpha")
check("fetched_at bumped", updated.fetched_at == fake_now_ms)
check("retry cleared", api.in_backoff(active_id) == false)

-- error -> backoff, no crash
req.on_error_cb({
    data = function() return '{"detail":"channel not found"}' end,
    status = function() return 404 end,
    error = function() return "HTTP 404" end,
})
req.finally_cb()
check("backoff after error", api.in_backoff(active_id) == true)
check("pending cleared", api.is_pending(active_id) == false)

-- while in backoff no new fetches, but stale data is still served
requests = {}
list = values(ev_auto("!al"))
check("backoff blocks fetch", #requests == 0)
check("backoff serves stale", #list.values == 1 and list.values[1] == "!alpha ")

-- parse_commands validation
check("parse garbage", api.parse_commands("not json") == nil)
check("parse object", api.parse_commands('{"error":true}') == nil)
check("parse empty", api.parse_commands("[]") == nil)
local parsed = api.parse_commands(body)
check("parse ok", parsed ~= nil and #parsed == 3)

print("resolve fallbacks")

-- no windows api (old chatterino)
local windows = c2.windows
c2.windows = nil
local id, name = completions.resolve()
check("fallback last channel", id == active_id)
c2.windows = windows

-- unknown single cached channel is used
local id2, _ = completions.resolve()
check("resolve returns id", id2 == active_id)

print("for_text (hotkey command)")

store.set(active_id, active_name, SEED)
list = completions.for_text("!game alias l")
check("for_text tail", #list.values == 1 and list.values[1] == "list ")
list = completions.for_text("hello")
check("for_text no prefix", #list.values == 0)

print("init.lua loads")
package.loaded["store"] = nil
package.loaded["api"] = nil
package.loaded["completions"] = nil
package.loaded["config"] = nil
package.loaded["util"] = nil
package.loaded["jsonutil"] = nil
local ok, err = pcall(dofile, plugin_dir .. "/init.lua")
check("init.lua executes", ok)
if not ok then print(err) end
check("init registered callback", registered_callback ~= nil)

print("commands")

-- init.lua re-required the modules, so pick up the instances it uses
store = require("store")
api = require("api")
completions = require("completions")

-- both the ctx channel and the active-channel stub append to the same
-- top-level `messages` table
local ctx = {
    words = {},
    channel = {
        add_system_message = function(self, msg) messages[#messages + 1] = msg end,
    },
}
ctx.words = { "/twirc:complete", "!game", "alias", "l;" }
registered_commands["/twirc:complete"](ctx)
check("complete cmd output", #messages == 1 and messages[1]:find("list", 1, true) ~= nil)

-- /twirc:reload with arg
ctx.words = { "/twirc:reload", "justovich221337" }
requests = {}
registered_commands["/twirc:reload"](ctx)
check("reload with arg fetches", #requests == 1)
check("reload message", messages[#messages]:find("justovich221337", 1, true) ~= nil)
requests[1].finally_cb() -- simulate request completion

-- /twirc:reload without arg (active channel)
ctx.words = { "/twirc:reload" }
requests = {}
registered_commands["/twirc:reload"](ctx)
check("reload no arg fetches", #requests == 1)
requests[1].finally_cb()

-- /twirc:clear
registered_commands["/twirc:clear"](ctx)
check("clear wipes store", store.get(active_id) == nil)

print("list command")

store.set(active_id, active_name, SEED)

-- /twirc:list (compact)
messages = {}
ctx.words = { "/twirc:list" }
registered_commands["/twirc:list"](ctx)
check("list header", messages[1] ~= nil and messages[1]:find("7 commands in justovich221337", 1, true) ~= nil)
check("list compact single message", #messages == 2)
check("list compact content", messages[2]:find("!age", 1, true) ~= nil
    and messages[2]:find("  •  ", 1, true) ~= nil
    and #messages[2] <= 450)

-- /twirc:list full (one command per message, with descriptions)
messages = {}
ctx.words = { "/twirc:list", "full" }
registered_commands["/twirc:list"](ctx)
check("list full count", #messages == 1 + #SEED)
check("list full description", messages[2] == "!age — User account age")
check("list full no empty dash", messages[3] == "!ban")

-- /twirc:list <channel>
messages = {}
ctx.words = { "/twirc:list", "justovich221337" }
registered_commands["/twirc:list"](ctx)
check("list by name", messages[1]:find("7 commands in justovich221337", 1, true) ~= nil)

-- /twirc:list unknown channel
messages = {}
ctx.words = { "/twirc:list", "notopensplit" }
registered_commands["/twirc:list"](ctx)
check("list unknown channel", messages[1] == "[twir] twitch channel not open in chatterino: notopensplit")

-- /twirc:list with empty cache -> fetches and tells the user
store.clear()
messages = {}
requests = {}
ctx.words = { "/twirc:list" }
registered_commands["/twirc:list"](ctx)
check("list empty cache message", messages[1] == "[twir] commands for this channel are not loaded yet, they are being fetched — try again in a moment")
check("list empty cache fetches", #requests == 1)
requests[1].finally_cb()

print("format_commands")

store.set(active_id, active_name, SEED)

local lines = completions.format_commands(active_id, "compact")
check("format compact one line", #lines == 1 and lines[1]:find("!age", 1, true) ~= nil)

-- many long commands must be chunked
local many = {}
for i = 1, 60 do
    many[i] = { name = string.format("command%02dwithaverylongname", i), description = "" }
end
store.set(active_id, active_name, many)
lines = completions.format_commands(active_id, "compact")
check("format compact chunked", #lines > 1)
local all_ok = true
for _, line in ipairs(lines) do
    if #line > 450 then all_ok = false end
end
check("format compact chunk sizes", all_ok)
check("format compact keeps all", table.concat(lines, " "):find("command59withaverylongname", 1, true) ~= nil)

lines = completions.format_commands(active_id, "full")
check("format full count", #lines == 60)
check("format full no dash", lines[1] == "!command01withaverylongname")

store.set(active_id, active_name, SEED)

print("context menu")

check("menu callback registered", #context_menu_callbacks == 1)

local menu_actions = {}
local fake_menu = {
    add_action = function(self, name, fn) menu_actions[name] = fn end,
}
local active_channel_stub = c2.windows.last_selected_window.notebook.selected_page.selected_split.channel

context_menu_callbacks[1]({
    split = { channel = active_channel_stub },
    menu = fake_menu,
})
check("menu action added", menu_actions["Show Twir commands"] ~= nil)

messages = {}
menu_actions["Show Twir commands"]()
check("menu action prints list", messages[1] ~= nil
    and messages[1]:find("7 commands in justovich221337", 1, true) ~= nil)

-- non-twitch channels get no menu entry
menu_actions = {}
context_menu_callbacks[1]({
    split = { channel = {
        is_valid = function() return true end,
        is_twitch_channel = function() return false end,
        get_twitch_id = function() return "" end,
    } },
    menu = fake_menu,
})
check("menu skipped for non-twitch", next(menu_actions) == nil)

print("init.lua loads check done")

print(string.format("\n%d passed, %d failed", completed, failed))
os.exit(failed == 0 and 0 or 1)
