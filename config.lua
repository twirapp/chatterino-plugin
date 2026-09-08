--- Plugin configuration.
--
-- Values are read from `config.json` inside the plugin data directory
-- (chatterino's settings -> Plugins -> open plugin folder). The file is
-- optional: everything missing falls back to the defaults below.

local jsonutil = require("jsonutil")

local DEFAULTS = {
    -- The prefix Twir commands are invoked with in chat.
    prefix = "!",
    -- How long fetched commands are considered fresh, in seconds.
    -- A refresh is requested (in the background) after that.
    ttl = 900,
    -- Base URL of the Twir public API.
    api_base = "https://twir.app/api/v2",
    -- HTTP request timeout in milliseconds.
    http_timeout = 10000,
}

local function load()
    local values = {}
    local ok, f = pcall(io.open, "config.json", "r")
    if ok and f ~= nil then
        local ok_read, body = pcall(function()
            return f:read("a")
        end)
        pcall(f.close, f)
        if ok_read and type(body) == "string" and body ~= "" then
            local ok_parse, parsed = pcall(jsonutil.parse, body)
            if ok_parse and type(parsed) == "table" then
                values = parsed
            end
        end
    end
    for key, value in pairs(DEFAULTS) do
        if values[key] == nil then
            values[key] = value
        end
    end
    return values
end

return load()
