-- license:BSD-3-Clause
--
-- APF Cassette AutoLoader
-- Step 3.4: deferred APF activation and one-shot automatic loading.

local exports = {
    name = "apf_autoload",
    version = "0.3.4",
    description = "Automatic cassette loader framework for APF systems",
    license = "BSD-3-Clause",
    author = { name = "Open-source MAME community project" }
}

local logger = require("apf_autoload.logger")
local cassette = require("apf_autoload.cassette")
local keyboard = require("apf_autoload.keyboard")
local Loader = require("apf_autoload.statemachine")
local apf_driver = require("apf_autoload.drivers.apf")

local reset_subscription
local stop_subscription
local frame_subscription
local media_subscriptions = {}
local loader = Loader.new()
local apf_active = false
local autostart_attempted = false
local apf_ready_frames = 0
local AUTOSTART_DELAY_FRAMES = 180

local function is_supported_machine(machine)
    return machine and machine.system and apf_driver.matches(machine.system)
end

local function clear_media_subscriptions()
    media_subscriptions = {}
end

local function current_machine()
    return manager and manager.machine or nil
end

local function first_mounted_cassette(machine)
    for _, entry in ipairs(cassette.discover(machine)) do
        if entry.device.exists == true then
            return entry
        end
    end
    return nil
end


local function media_identity(device)
    if not device or device.exists ~= true then
        return "<none>"
    end

    if device.loaded_through_softlist == true then
        return string.format(
            "%s | list=%s | title=%s",
            tostring(device.filename or "<software item>"),
            tostring(device.software_list_name or "<unknown>"),
            tostring(device.software_longname or "<unknown>")
        )
    end

    return tostring(device.filename or "<mounted media>")
end

local function log_mounted_images(machine)
    for tag, image in pairs(machine.images or {}) do
        if image.exists == true then
            logger.info(string.format(
                "Mounted image %s: %s",
                tostring(tag),
                media_identity(image)
            ))
        end
    end
end

local function inspect_machine()
    clear_media_subscriptions()

    local machine = current_machine()
    if not is_supported_machine(machine) then
        apf_active = false
        return
    end

    apf_active = true
    local system = machine.system
    logger.info(string.format(
        "APF machine started: %s (%s)",
        tostring(system.description),
        tostring(system.name)
    ))
    logger.info("Supported APF-family system detected.")

    keyboard.log_status(machine)
    log_mounted_images(machine)

    local devices = cassette.discover(machine)
    if #devices == 0 then
        logger.warn("No cassette image devices were found.")
        return
    end

    logger.info(string.format("Found %d cassette device%s.",
        #devices, (#devices == 1) and "" or "s"))

    for _, entry in ipairs(devices) do
        cassette.log_status(entry)

        local subscription = entry.device:add_media_change_notifier(function(change)
            logger.info(string.format(
                "Cassette media change on %s: %s",
                entry.tag, tostring(change)
            ))
            cassette.log_status(entry)
            if change == "unloaded" and loader.active then
                loader:abort()
            end
        end)

        table.insert(media_subscriptions, subscription)
    end
end

local function start_loader()
    local machine = current_machine()
    if not is_supported_machine(machine) then
        return
    end

    local entry = first_mounted_cassette(machine)
    if not entry then
        logger.warn("Cannot start loader: no mounted cassette.")
        return
    end

    logger.info("Manual automatic-load test requested for " ..
        tostring(entry.device.filename))

    local ok, err = loader:start(machine, entry)
    if not ok then
        logger.error("Could not start automatic load: " .. tostring(err))
    end
end

function exports.startplugin()
    reset_subscription = emu.add_machine_reset_notifier(function()
        if loader.active then
            loader:abort()
        end

        apf_active = false
        autostart_attempted = false
        apf_ready_frames = 0
        clear_media_subscriptions()

        -- Do not rely on the reset callback for activation. Some command-line
        -- and frontend launches invoke this before manager.machine.system is
        -- fully available. The frame callback below performs deferred detection.
    end)

    stop_subscription = emu.add_machine_stop_notifier(function()
        if apf_active then
            logger.info("APF machine stopped.")
        end
        if loader.active then
            loader:abort()
        end
        apf_active = false
        autostart_attempted = false
        apf_ready_frames = 0
        clear_media_subscriptions()
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        local machine = current_machine()
        local supported = is_supported_machine(machine)

        if not supported then
            -- Stay completely silent for every non-APF system.
            apf_active = false
            autostart_attempted = false
            apf_ready_frames = 0
            return
        end

        -- Deferred one-time activation fixes frontend/command-line launches
        -- where the reset notifier fires before the driver is visible.
        if not apf_active then
            apf_active = true
            logger.info("Plugin active (version " .. exports.version .. ").")
            inspect_machine()
        end

        loader:tick(machine)

        if loader.active or autostart_attempted then
            return
        end

        local entry = first_mounted_cassette(machine)
        if not entry then
            apf_ready_frames = 0
            return
        end

        local key_status = keyboard.status(machine)
        if key_status.can_post ~= true then
            apf_ready_frames = 0
            return
        end

        apf_ready_frames = apf_ready_frames + 1
        if apf_ready_frames >= AUTOSTART_DELAY_FRAMES then
            autostart_attempted = true
            logger.info("Mounted APF cassette detected; starting automatic load.")
            local ok, err = loader:start(machine, entry)
            if not ok then
                logger.error("Automatic start failed: " .. tostring(err))
            end
        end
    end)

    local function menu_populate()
        local machine = current_machine()
        if not is_supported_machine(machine) then
            return {
                { "APF Cassette AutoLoader", "Inactive for this system", "off" }
            }
        end

        local driver_name = "<none>"
        local cassette_name = "<none>"
        local keyboard_state = "unavailable"

        if machine and machine.system then
            driver_name = tostring(machine.system.name)
            local entry = first_mounted_cassette(machine)
            if entry then
                cassette_name = media_identity(entry.device)
            end

            local status = keyboard.status(machine)
            if status.available then
                keyboard_state = status.can_post and "ready" or "cannot post"
            end
        end

        local start_flags = loader.active and "off" or ""
        local abort_flags = loader.active and "" or "off"

        return {
            { "Plugin version", exports.version, "" },
            { "Current driver", driver_name, "" },
            { "Mounted cassette", cassette_name, "" },
            { "Natural keyboard", keyboard_state, "" },
            { "Loader status", loader:summary(), "" },
            { "Start automatic load test", "", start_flags },
            { "Abort automatic load", "", abort_flags },
            { "Rescan and log", "", "" },
            { "Post CLOAD manually", "", "" },
            { "Post RUN manually", "", "" }
        }
    end

    local function menu_callback(index, event)
        if not is_supported_machine(current_machine()) then
            return false
        end
        if event ~= "select" then
            return false
        end

        if index == 6 then
            start_loader()
            return true
        elseif index == 7 then
            local ok, err = loader:abort()
            if not ok then
                logger.warn(tostring(err))
            end
            return true
        elseif index == 8 then
            inspect_machine()
            return true
        elseif index == 9 then
            keyboard.post_coded(current_machine(), "CLOAD{ENTER}")
            return true
        elseif index == 10 then
            keyboard.post_coded(current_machine(), "RUN{ENTER}")
            return true
        end

        return false
    end

    emu.register_menu(menu_callback, menu_populate, "APF Cassette AutoLoader")
end

return exports
