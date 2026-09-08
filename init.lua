--- Twir completion — a chatterino plugin that completes Twir channel commands.
--
-- Commands are fetched from the Twir public API:
--   GET https://twir.app/api/v2/public/channels/twitch/{channelId}/commands
--
-- The channel is detected from the currently selected split, fetched in the
-- background and cached (in memory and on disk). Type "!" to complete a
-- command, or run /twirc:list to print the whole command list into chat.

local api = require("api")
local completions = require("completions")
local store = require("store")
local util = require("util")

local VERSION = "1.0.1"

store.load()

c2.register_callback(c2.EventType.CompletionRequested, function(ev)
    local ok, list = pcall(completions.on_completion, ev)
    if ok and type(list) == "table" then
        return list
    end
    if not ok then
        util.log(c2.LogLevel.Warning, "completion failed: ", tostring(list))
    end
    return { values = {}, hide_others = false }
end)

--- Prints the command list of a channel into `chat_channel`.
local function show_commands(chat_channel, channel_id, channel_name, verbose)
    -- make sure we have something to show, or refresh what we have
    completions.ensure_fresh(channel_id, channel_name)

    local lines = completions.format_commands(channel_id, verbose and "full" or "compact")
    local entry = store.get(channel_id)
    local count = 0
    if entry ~= nil then
        count = #entry.commands
    end

    if lines == nil then
        chat_channel:add_system_message(
            "[twir] commands for this channel are not loaded yet, they are being fetched — try again in a moment")
        return
    end

    local name = channel_name
    if name == nil or name == "" then
        if entry ~= nil and entry.name ~= "" then
            name = entry.name
        else
            name = channel_id
        end
    end

    chat_channel:add_system_message(("[twir] %d commands in %s%s"):format(
        count, name, verbose and "" or "  (use /twirc:list full for descriptions)"))
    for _, line in ipairs(lines) do
        chat_channel:add_system_message(line)
    end
end

--- Resolves a channel name (as known to chatterino) to twitch id + login name.
local function resolve_named_channel(target)
    local ok, id, name = pcall(function()
        local channel = c2.Channel.by_name(target)
        if channel == nil then
            return nil, nil
        end
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

--- `/twirc:list [full] [channel]` — print the command list into chat.
local function cmd_list(ctx)
    local verbose = false
    local target

    for i = 2, 3 do
        local word = ctx.words[i]
        if word == "full" or word == "-v" or word == "verbose" then
            verbose = true
        elseif word ~= nil and word ~= "" then
            target = word
        end
    end

    local channel_id, channel_name
    if target ~= nil then
        channel_id, channel_name = resolve_named_channel(target)
        if channel_id == nil then
            ctx.channel:add_system_message("[twir] twitch channel not open in chatterino: " .. target)
            return
        end
        completions.remember(channel_id)
    else
        channel_id, channel_name = completions.resolve()
    end

    if channel_id == nil or channel_id == "" then
        ctx.channel:add_system_message("[twir] could not detect the active channel, use /twirc:list <channel>")
        return
    end

    show_commands(ctx.channel, channel_id, channel_name, verbose)
end

--- `/twirc:reload [channel]` — force a refresh of the command list.
-- Without an argument the active channel is used.
local function cmd_reload(ctx)
    local target = ctx.words[2]
    local channel_id, channel_name

    if target ~= nil and target ~= "" then
        channel_id, channel_name = resolve_named_channel(target)
        if channel_id == nil then
            ctx.channel:add_system_message("[twir] twitch channel not open in chatterino: " .. target)
            return
        end
        completions.remember(channel_id)
    else
        channel_id, channel_name = completions.resolve()
    end

    if channel_id == nil or channel_id == "" then
        ctx.channel:add_system_message("[twir] could not detect the active channel, use /twirc:reload <channel>")
        return
    end

    if channel_name == nil or channel_name == "" then
        channel_name = channel_id
    end

    api.fetch(channel_id, channel_name, true)
    ctx.channel:add_system_message("[twir] refreshing commands for " .. channel_name)
end

--- `/twirc:complete {input.text};` — prints the completions for the typed
-- text into the chat. Handy as a hotkey action:
--   Action: "Run a command", Arguments: "/twirc:complete {input.text};"
local function cmd_complete(ctx)
    table.remove(ctx.words, 1)
    local text = (table.concat(ctx.words, " "):gsub(";$", ""))
    local list = completions.for_text(text)
    if #list.values == 0 then
        ctx.channel:add_system_message("[twir] no completions")
        return
    end
    ctx.channel:add_system_message("[twir] completions: " .. table.concat(list.values, "  "))
end

--- `/twirc:clear` — drops the cached commands.
local function cmd_clear(ctx)
    store.clear()
    ctx.channel:add_system_message("[twir] cache cleared")
end

c2.register_command("/twirc:list", cmd_list)
c2.register_command("/twirc:reload", cmd_reload)
c2.register_command("/twirc:complete", cmd_complete)
c2.register_command("/twirc:clear", cmd_clear)

--- Adds a "Show Twir commands" entry to the chat context menu (right click on
-- the channel view). Only works on builds that expose the window API, silently
-- skipped otherwise.
local function setup_context_menu()
    pcall(function()
        c2.windows:on_channelview_context_menu_requested(function(args)
            pcall(function()
                local channel = nil
                if args.split ~= nil and args.split.channel ~= nil then
                    channel = args.split.channel
                elseif args.channel ~= nil then
                    channel = args.channel
                end
                if channel == nil or not channel:is_valid() or not channel:is_twitch_channel() then
                    return
                end
                local channel_id = channel:get_twitch_id()
                if channel_id == nil or channel_id == "" then
                    return
                end

                args.menu:add_action("Show Twir commands", function()
                    pcall(function()
                        -- the channel object from the menu event may have
                        -- expired by the time the action is clicked, resolve a
                        -- fresh one by id
                        local target = c2.Channel.by_twitch_id(channel_id)
                        if target == nil or not target:is_valid() then
                            return
                        end
                        show_commands(target, channel_id, nil, false)
                    end)
                end)
            end)
        end)
    end)
end

setup_context_menu()

util.log(c2.LogLevel.Info, "twir completion v" .. VERSION .. " loaded")
