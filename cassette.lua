-- license:BSD-3-Clause

local logger = require("apf_autoload.logger")
local cassette = {}

local function basename(path)
    if not path or path == "" then
        return nil
    end
    return path:match("([^/\\]+)$") or path
end

function cassette.discover(machine)
    local found = {}

    if not machine or not machine.cassettes then
        return found
    end

    for tag, device in pairs(machine.cassettes) do
        table.insert(found, {
            tag = tostring(tag),
            device = device
        })
    end

    table.sort(found, function(a, b)
        return a.tag < b.tag
    end)

    return found
end

function cassette.snapshot(entry)
    local device = entry.device
    local mounted = device.exists == true
    local filename = mounted and device.filename or nil

    return {
        tag = entry.tag,
        mounted = mounted,
        filename = filename,
        basename = basename(filename),
        readonly = mounted and (device.readonly == true) or false,
        length = tonumber(device.length) or 0,
        position = tonumber(device.position) or 0,
        playing = device.is_playing == true,
        stopped = device.is_stopped == true,
        motor = device.motor_state == true
    }
end

function cassette.log_status(entry)
    local status = cassette.snapshot(entry)

    if not status.mounted then
        logger.info(string.format(
            "Cassette %s: no image mounted.",
            status.tag
        ))
        return
    end

    logger.info(string.format(
        "Cassette %s: mounted '%s' | %.2fs / %.2fs | %s | motor %s | %s",
        status.tag,
        status.basename or status.filename or "<unknown>",
        status.position,
        status.length,
        status.playing and "playing" or (status.stopped and "stopped" or "active"),
        status.motor and "on" or "off",
        status.readonly and "read-only" or "writable"
    ))

    logger.debug("Full cassette path: " .. tostring(status.filename))
end

return cassette
