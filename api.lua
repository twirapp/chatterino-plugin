--- Client for the Twir public API
-- (GET {api_base}/public/channels/twitch/{channelId}/commands).

local config = require("config")
local jsonutil = require("jsonutil")
local store = require("store")
local util = require("util")

local USER_AGENT = "twir-completion-plugin/1.0.1 (+https://twir.app)"

--- Don't retry a failed fetch more often than this.
local FAILURE_BACKOFF_MS = 60 * 1000

local api = {}

--- channel id -> true while a request is in flight
local pending = {}
--- channel id -> unix ms until which no new requests should be made
local retry_at = {}

function api.is_pending(channel_id)
    return pending[channel_id] == true
end

function api.in_backoff(channel_id)
    local at = retry_at[channel_id]
    return at ~= nil and util.now_ms() < at
end

--- Parses and validates the response of the commands endpoint.
-- Returns a list of `{name, description}` tables, or nil if the payload is
-- not what we expect.
function api.parse_commands(body)
    local ok, data = pcall(jsonutil.parse, body)
    if not ok or type(data) ~= "table" or data[1] == nil then
        return nil
    end
    local commands = {}
    for _, raw in ipairs(data) do
        if type(raw) == "table" and type(raw.name) == "string" and raw.name ~= "" then
            commands[#commands + 1] = {
                name = raw.name,
                description = type(raw.description) == "string" and raw.description or "",
            }
        end
    end
    table.sort(commands, function(a, b)
        return a.name < b.name
    end)
    return commands
end

--- Starts an asynchronous fetch of the command list for a Twitch channel id.
-- `force` skips the failure backoff (used by the manual reload command).
-- Returns true if a request was started.
function api.fetch(channel_id, channel_name, force)
    if api.is_pending(channel_id) then
        return false
    end
    if force then
        retry_at[channel_id] = nil
    elseif api.in_backoff(channel_id) then
        return false
    end

    local url = string.format(
        "%s/public/channels/twitch/%s/commands",
        config.api_base,
        channel_id
    )
    local ok, request = pcall(c2.HTTPRequest.create, c2.HTTPMethod.Get, url)
    if not ok then
        retry_at[channel_id] = util.now_ms() + FAILURE_BACKOFF_MS
        util.log(c2.LogLevel.Warning, "failed to create HTTP request: ", tostring(request))
        return false
    end

    pending[channel_id] = true

    request:set_timeout(config.http_timeout)
    request:set_header("Accept", "application/json")
    request:set_header("User-Agent", USER_AGENT)

    local function fail()
        retry_at[channel_id] = util.now_ms() + FAILURE_BACKOFF_MS
        util.log(c2.LogLevel.Warning, "fetching commands for channel ", channel_id, " failed")
    end

    request:on_success(function(response)
        local commands = api.parse_commands(response:data())
        if commands == nil then
            retry_at[channel_id] = util.now_ms() + FAILURE_BACKOFF_MS
            util.log(c2.LogLevel.Warning,
                "unexpected response for channel ", channel_id,
                " (status ", tostring(response:status()), ")")
            return
        end
        retry_at[channel_id] = nil
        store.set(channel_id, channel_name, commands)
        util.log(c2.LogLevel.Info,
            "fetched ", tostring(#commands), " commands for channel ", channel_id)
    end)

    request:on_error(function(response)
        fail()
        util.log(c2.LogLevel.Debug,
            "request error: ", tostring(response:error()))
    end)

    request:finally(function()
        pending[channel_id] = nil
    end)

    request:execute()
    return true
end

return api
