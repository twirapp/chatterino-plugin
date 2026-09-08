--- CompletionRequested callback: completes Twir commands of the channel the
-- user is currently typing in.

local api = require("api")
local config = require("config")
local store = require("store")
local util = require("util")

local completions = {}

--- Fallback when the active channel can't be detected (e.g. older chatterino
-- without the window API): the last channel we saw the user type in.
local last_channel_id

local function new_list()
    return { values = {}, hide_others = false }
end

local function get_active_channel()
    -- c2.windows is only available in newer chatterino builds, hence pcall.
    local ok, channel = pcall(function()
        local window = c2.windows.last_selected_window
        local page = window.notebook.selected_page
        if page == nil then
            return nil
        end
        return page.selected_split.channel
    end)
    if ok then
        return channel
    end
    return nil
end

--- Returns the twitch id and login name of the active twitch channel.
local function active_identity()
    local channel = get_active_channel()
    if channel == nil then
        return nil, nil
    end
    local ok, id, name = pcall(function()
        if not channel:is_valid() or not channel:is_twitch_channel() then
            return nil, nil
        end
        return channel:get_twitch_id(), channel:get_name()
    end)
    if not ok then
        return nil, nil
    end
    if id == nil or id == "" then
        return nil, nil
    end
    return id, name
end

--- Best-effort resolution of the channel the user is typing in.
-- Returns channel id and (maybe nil) login name.
function completions.resolve()
    local id, name = active_identity()
    if id ~= nil then
        last_channel_id = id
        return id, name
    end
    if last_channel_id ~= nil then
        return last_channel_id, nil
    end
    -- Exactly one known channel: almost certainly the one in use.
    local ids = store.ids()
    if #ids == 1 then
        return ids[1], nil
    end
    return nil, nil
end

--- Remembers a channel as the fallback for `resolve`.
function completions.remember(channel_id)
    last_channel_id = channel_id
end

--- Requests a background refresh when the cached commands went stale.
function completions.ensure_fresh(channel_id, channel_name)
    local entry = store.get(channel_id)
    local now = util.now_ms()

    if now == 0 then
        -- Clock unavailable (very old chatterino): only fetch if we have
        -- nothing at all, otherwise leave the cache alone.
        if entry ~= nil then
            return
        end
    else
        local fetched_at = 0
        if entry ~= nil then
            fetched_at = entry.fetched_at
        end
        if now - fetched_at < config.ttl * 1000 then
            return
        end
    end

    if channel_name == nil or channel_name == "" then
        if entry ~= nil then
            channel_name = entry.name
        end
    end
    api.fetch(channel_id, channel_name)
end

--- The tail of `typed` must be the word being completed, otherwise the
-- replacement value wouldn't line up with the input.
local function split_head_and_query(typed, query, is_first_word)
    if is_first_word then
        return ""
    end
    if #query > #typed then
        return nil
    end
    local head = typed:sub(1, #typed - #query)
    if typed:sub(#typed - #query + 1) ~= query then
        return nil
    end
    return head
end

--- Builds the completion list for a CompletionEvent.
function completions.on_completion(ev)
    local list = new_list()

    local prefix = config.prefix
    if type(prefix) ~= "string" or prefix == "" then
        return list
    end
    if type(ev.full_text_content) ~= "string" or not util.starts_with(ev.full_text_content, prefix) then
        return list
    end

    -- Everything typed after the prefix, e.g. "game alias l" for "!game alias l".
    local typed = ev.full_text_content:sub(#prefix + 1):lower()
    local query = tostring(ev.query):lower()
    local head = split_head_and_query(typed, query, ev.is_first_word)
    if head == nil then
        return list
    end

    local channel_id, channel_name = completions.resolve()
    if channel_id == nil then
        return list
    end
    completions.ensure_fresh(channel_id, channel_name)

    local entry = store.get(channel_id)
    if entry == nil then
        return list
    end

    -- The completion value replaces the word being typed, so:
    -- - first word: "!ba" -> "!ban " (includes the prefix)
    -- - later words: "!game alias l" -> "list " (only the missing part)
    local seen = {}
    for _, command in ipairs(entry.commands) do
        local name = command.name:lower()
        if typed == "" or util.starts_with(name, typed) then
            local value
            if ev.is_first_word then
                value = prefix .. command.name
            else
                value = command.name:sub(#head + 1)
            end
            value = value .. " "
            if not seen[value] then
                seen[value] = true
                list.values[#list.values + 1] = value
            end
        end
    end

    table.sort(list.values)
    list.hide_others = #list.values > 0
    return list
end

--- Computes completions for an arbitrary text, used by `/twirc:complete`.
function completions.for_text(text)
    local is_first_word = text:find("%s") == nil
    local query
    if is_first_word then
        query = text
    else
        query = text:match("(%S*)$") or ""
    end
    return completions.on_completion({
        query = query,
        full_text_content = text,
        cursor_position = #text,
        is_first_word = is_first_word,
    })
end

--- Max length of a single compact listing message. chatterino has no hard
-- limit for local messages, this just keeps them readable.
local COMPACT_LINE_MAX = 450

--- Formats the command list of a channel for printing into chat.
-- mode:
--   "compact" (default) - all commands, joined with bullets, chunked into
--                         messages of at most COMPACT_LINE_MAX characters
--   "full"              - one command per message, including its description
-- Returns a list of lines, or nil when nothing is cached for the channel.
function completions.format_commands(channel_id, mode)
    local entry = store.get(channel_id)
    if entry == nil or #entry.commands == 0 then
        return nil
    end

    local prefix = config.prefix
    local lines = {}

    if mode == "full" then
        for _, command in ipairs(entry.commands) do
            local line = prefix .. command.name
            if command.description ~= "" then
                line = line .. " — " .. command.description
            end
            lines[#lines + 1] = line
        end
        return lines
    end

    local line = ""
    for _, command in ipairs(entry.commands) do
        local name = prefix .. command.name
        if line == "" then
            line = name
        elseif #line + 3 + #name <= COMPACT_LINE_MAX then
            line = line .. "  •  " .. name
        else
            lines[#lines + 1] = line
            line = name
        end
    end
    if line ~= "" then
        lines[#lines + 1] = line
    end
    return lines
end

return completions
