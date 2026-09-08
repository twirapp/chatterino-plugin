--- Keeps fetched Twir commands in memory and persists them to `cache.json`
-- inside the plugin data directory, so completions survive restarts.

local jsonutil = require("jsonutil")
local util = require("util")

local CACHE_FILE = "cache.json"
local CACHE_VERSION = 1

--- channel id -> { name, fetched_at (unix ms), commands = { {name, description}, ... } }
local entries = {}

local store = {}

local function save()
    local payload = { version = CACHE_VERSION, channels = {} }
    for id, entry in pairs(entries) do
        payload.channels[id] = entry
    end
    local ok, err = pcall(function()
        local f = io.open(CACHE_FILE, "w")
        if f == nil then
            error("io.open returned nil")
        end
        f:write(jsonutil.stringify(payload))
        f:close()
    end)
    if not ok then
        util.log(c2.LogLevel.Warning, "failed to write cache: ", tostring(err))
    end
end

local function normalize_commands(raw_commands)
    local commands = {}
    if type(raw_commands) ~= "table" then
        return commands
    end
    for _, command in ipairs(raw_commands) do
        if type(command) == "table" and type(command.name) == "string" and command.name ~= "" then
            commands[#commands + 1] = {
                name = command.name,
                description = type(command.description) == "string" and command.description or "",
            }
        end
    end
    table.sort(commands, function(a, b)
        return a.name < b.name
    end)
    return commands
end

function store.load()
    local ok, f = pcall(io.open, CACHE_FILE, "r")
    if not ok or f == nil then
        return
    end
    local ok_read, body = pcall(function()
        return f:read("a")
    end)
    pcall(f.close, f)
    if not ok_read or type(body) ~= "string" or body == "" then
        return
    end
    local ok_parse, data = pcall(jsonutil.parse, body)
    if not ok_parse or type(data) ~= "table" or type(data.channels) ~= "table" then
        return
    end
    for id, entry in pairs(data.channels) do
        if
            type(id) == "string"
            and type(entry) == "table"
            and type(entry.fetched_at) == "number"
        then
            entries[id] = {
                name = type(entry.name) == "string" and entry.name or "",
                fetched_at = entry.fetched_at,
                commands = normalize_commands(entry.commands),
            }
        end
    end
end

--- Returns the cached entry for a channel id, or nil.
function store.get(channel_id)
    return entries[channel_id]
end

--- Returns all cached channel ids.
function store.ids()
    local ids = {}
    for id in pairs(entries) do
        ids[#ids + 1] = id
    end
    return ids
end

function store.set(channel_id, channel_name, commands)
    entries[channel_id] = {
        name = channel_name or "",
        fetched_at = util.now_ms(),
        commands = normalize_commands(commands),
    }
    save()
end

function store.remove(channel_id)
    if entries[channel_id] ~= nil then
        entries[channel_id] = nil
        save()
    end
end

function store.clear()
    entries = {}
    save()
end

return store
