-- license:BSD-3-Clause
--
-- APF cassette loader state machine.
-- Implements the APF-specific two-Return cassette handshake.

local logger = require("apf_autoload.logger")
local keyboard = require("apf_autoload.keyboard")

local Loader = {}
Loader.__index = Loader

local DEFAULTS = {
    ui_closed_stable_frames = 15,
    command_delay_frames = 30,
    playback_delay_frames = 60,
    leader_return_delay_frames = 120,
    motor_start_timeout_frames = 60 * 30,
    load_timeout_frames = 60 * 20 * 60,
    run_delay_frames = 60,
    movement_threshold_seconds = 0.05
}

local function merge_options(options)
    local result = {}
    for key, value in pairs(DEFAULTS) do result[key] = value end
    for key, value in pairs(options or {}) do result[key] = value end
    return result
end

function Loader.new(options)
    return setmetatable({
        options = merge_options(options),
        active = false,
        state = "idle",
        state_frames = 0,
        cassette = nil,
        cassette_tag = nil,
        start_position = 0,
        highest_position = 0,
        movement_seen = false,
        ui_closed_frames = 0,
        status = "Idle",
        error = nil
    }, Loader)
end

function Loader:_set_state(state, status)
    self.state = state
    self.state_frames = 0
    self.status = status or state
    logger.info("Loader state: " .. state .. " — " .. self.status)
end

function Loader:_fail(message)
    self.error = tostring(message)
    self.active = false
    self:_set_state("error", self.error)
    logger.error("Automatic load failed: " .. self.error)
end

function Loader:start(machine, cassette_entry)
    if self.active then return false, "The loader is already active." end
    if not machine or not machine.system then return false, "No running machine." end
    if tostring(machine.system.name) ~= "apfimag" then
        return false, "Automatic loading is restricted to apfimag."
    end
    if not cassette_entry or not cassette_entry.device
        or cassette_entry.device.exists ~= true then
        return false, "No cassette image is mounted."
    end
    if keyboard.status(machine).can_post ~= true then
        return false, "Natural keyboard posting is unavailable."
    end

    self.cassette = cassette_entry.device
    self.cassette_tag = cassette_entry.tag
    self.error = nil
    self.active = true
    self.start_position = 0
    self.highest_position = 0
    self.movement_seen = false
    self.ui_closed_frames = 0

    local ok, err = pcall(function()
        self.cassette:stop()
        self.cassette:forward()
        self.cassette:seek(0, "set")
        self.cassette.motor_state = false
    end)
    if not ok then
        self:_fail("Could not rewind cassette: " .. tostring(err))
        return false, tostring(err)
    end

    self.start_position = tonumber(self.cassette.position) or 0
    self.highest_position = self.start_position
    self:_set_state("waiting_for_ui", "Close the MAME menu to begin")
    return true
end

function Loader:abort()
    if not self.active then return false, "The loader is not active." end
    if self.cassette then
        pcall(function()
            self.cassette:stop()
            self.cassette.motor_state = false
        end)
    end
    self.active = false
    self:_set_state("aborted", "Stopped by user")
    return true
end

function Loader:tick(machine)
    if not self.active then return end
    self.state_frames = self.state_frames + 1

    local tape = self.cassette
    if not tape or tape.exists ~= true then
        self:_fail("Cassette media was removed.")
        return
    end

    local position = tonumber(tape.position) or 0
    if position > self.highest_position then self.highest_position = position end
    if (self.highest_position - self.start_position)
        >= self.options.movement_threshold_seconds then
        self.movement_seen = true
    end

    if self.state == "waiting_for_ui" then
        local menu_active = manager and manager.ui
            and manager.ui.menu_active == true
        if menu_active then
            self.ui_closed_frames = 0
        else
            self.ui_closed_frames = self.ui_closed_frames + 1
        end
        if self.ui_closed_frames >= self.options.ui_closed_stable_frames then
            self:_set_state("command_delay", "Menu closed; preparing CLOAD")
        end

    elseif self.state == "command_delay" then
        if self.state_frames >= self.options.command_delay_frames then
            local ok, err = keyboard.post_coded(machine, "CLOAD{ENTER}")
            if not ok then
                self:_fail("Could not post CLOAD: " .. tostring(err))
                return
            end
            self:_set_state("before_playback", "CLOAD sent; waiting to start tape")
        end

    elseif self.state == "before_playback" then
        if self.state_frames >= self.options.playback_delay_frames then
            local ok, err = pcall(function()
                tape.motor_state = true
                tape:play()
            end)
            if not ok then
                self:_fail("Could not start cassette: " .. tostring(err))
                return
            end
            self:_set_state("waiting_for_leader", "Tape started; waiting through leader")
        end

    elseif self.state == "waiting_for_leader" then
        if self.movement_seen
            and self.state_frames >= self.options.leader_return_delay_frames then
            local ok, err = keyboard.post_coded(machine, "{ENTER}")
            if not ok then
                self:_fail("Could not post the leader Return: " .. tostring(err))
                return
            end
            logger.info("APF cassette handshake Return sent after leader.")
            self:_set_state("loading", "Second Return sent; loading program")
        elseif self.state_frames >= self.options.motor_start_timeout_frames then
            self:_fail("Tape did not begin moving.")
        end

    elseif self.state == "loading" then
        local tape_finished = tape.length > 0
            and position >= (tape.length - 0.05)
        local motor_finished = self.movement_seen and tape.motor_state ~= true

        if tape_finished or motor_finished then
            pcall(function()
                tape:stop()
                tape.motor_state = false
            end)
            self:_set_state("settling", "Tape finished; preparing RUN")
        elseif self.state_frames >= self.options.load_timeout_frames then
            self:_fail("Cassette loading exceeded 20 minutes.")
        end

    elseif self.state == "settling" then
        if self.state_frames >= self.options.run_delay_frames then
            local ok, err = keyboard.post_coded(machine, "RUN{ENTER}")
            if not ok then
                self:_fail("Could not post RUN: " .. tostring(err))
                return
            end
            self.active = false
            self:_set_state("complete", "RUN sent")
        end
    end
end

function Loader:summary()
    if self.state == "error" then return "ERROR: " .. tostring(self.error) end
    return self.status
end

return Loader
