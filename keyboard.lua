-- license:BSD-3-Clause
--
-- Safe natural-keyboard helpers used by the Step 2 manual test menu.

local logger = require("apf_autoload.logger")
local keyboard = {}

local function get_manager(machine)
    if not machine then
        return nil, "No running machine is available."
    end

    local natkeyboard = machine.natkeyboard
    if not natkeyboard then
        return nil, "MAME did not expose a natural keyboard manager."
    end

    return natkeyboard
end

function keyboard.status(machine)
    local natkeyboard, err = get_manager(machine)
    if not natkeyboard then
        return {
            available = false,
            error = err
        }
    end

    return {
        available = true,
        can_post = natkeyboard.can_post == true,
        in_use = natkeyboard.in_use == true,
        empty = natkeyboard.empty == true,
        full = natkeyboard.full == true,
        is_posting = natkeyboard.is_posting == true
    }
end

function keyboard.log_status(machine)
    local status = keyboard.status(machine)

    if not status.available then
        logger.warn(status.error)
        return false
    end

    logger.info(string.format(
        "Natural keyboard: can_post=%s | in_use=%s | empty=%s | full=%s | is_posting=%s",
        tostring(status.can_post),
        tostring(status.in_use),
        tostring(status.empty),
        tostring(status.full),
        tostring(status.is_posting)
    ))

    return status.can_post
end

function keyboard.dump(machine)
    local natkeyboard, err = get_manager(machine)
    if not natkeyboard then
        logger.warn(err)
        return false, err
    end

    local ok, result = pcall(function()
        return natkeyboard:dump()
    end)

    if not ok then
        logger.error("Keyboard dump failed: " .. tostring(result))
        return false, tostring(result)
    end

    logger.info("Keyboard binding dump follows:")
    emu.print_info(tostring(result))
    return true
end

local function prepare(machine)
    local natkeyboard, err = get_manager(machine)
    if not natkeyboard then
        return nil, err
    end

    if natkeyboard.can_post ~= true then
        return nil, "The current machine reports can_post=false."
    end

    if natkeyboard.full == true then
        return nil, "The natural keyboard input buffer is full."
    end

    -- Explicitly enable natural keyboard mode for posted characters.
    natkeyboard.in_use = true
    return natkeyboard
end

function keyboard.post_literal(machine, text)
    if type(text) ~= "string" or text == "" then
        return false, "Literal text must be a non-empty string."
    end

    local natkeyboard, err = prepare(machine)
    if not natkeyboard then
        logger.warn("Literal post rejected: " .. tostring(err))
        return false, err
    end

    local ok, result = pcall(function()
        return natkeyboard:post(text)
    end)

    if not ok then
        logger.error("Literal keyboard post failed: " .. tostring(result))
        return false, tostring(result)
    end

    logger.info("Posted literal text: " .. string.format("%q", text))
    return true
end

function keyboard.post_coded(machine, text)
    if type(text) ~= "string" or text == "" then
        return false, "Coded text must be a non-empty string."
    end

    local natkeyboard, err = prepare(machine)
    if not natkeyboard then
        logger.warn("Coded post rejected: " .. tostring(err))
        return false, err
    end

    local ok, result = pcall(function()
        return natkeyboard:post_coded(text)
    end)

    if not ok then
        logger.error("Coded keyboard post failed: " .. tostring(result))
        return false, tostring(result)
    end

    logger.info("Posted coded text: " .. string.format("%q", text))
    return true
end

return keyboard
