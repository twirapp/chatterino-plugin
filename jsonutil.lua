--- Returns a `parse`/`stringify` JSON api.
--
-- Prefers the JSON module bundled with chatterino (available in 2025+ builds
-- via `require("chatterino.json")`) and falls back to the vendored copy of
-- rxi/json.lua (see `json.lua`) for older builds.

local ok, impl = pcall(require, "chatterino.json")
if not ok or type(impl) ~= "table" then
    impl = require("json")
end

local jsonutil = {}

if type(impl.parse) == "function" then
    jsonutil.parse = impl.parse
    jsonutil.stringify = impl.stringify
else
    function jsonutil.parse(input)
        return impl.decode(input)
    end

    function jsonutil.stringify(value)
        return impl.encode(value)
    end
end

return jsonutil
