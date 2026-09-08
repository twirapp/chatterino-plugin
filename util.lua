--- Small helpers shared across the plugin.

local util = {}

--- Current time in milliseconds since the Unix epoch.
-- The `os` library is not available inside chatterino, so this goes through
-- the plugin API. Returns 0 if the API is unavailable (e.g. old build).
function util.now_ms()
    local ok, ms = pcall(function()
        return c2.DateTime.current_utc():to_unix_milliseconds()
    end)
    if ok and type(ms) == "number" then
        return ms
    end
    return 0
end

--- Logs a message with the plugin tag prefixed.
function util.log(level, ...)
    c2.log(level, "[twir]", ...)
end

--- Case-insensitive prefix check. Command names are ascii, so `string.lower`
-- is enough here.
function util.starts_with(value, prefix)
    return value:sub(1, #prefix):lower() == prefix:lower()
end

return util
