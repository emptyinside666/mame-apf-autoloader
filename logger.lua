-- license:BSD-3-Clause

local logger = {}

local PREFIX = "[APF AutoLoader] "

local function stringify(message)
    if message == nil then
        return "<nil>"
    end
    return tostring(message)
end

function logger.debug(message)
    emu.print_verbose(PREFIX .. stringify(message))
end

function logger.info(message)
    emu.print_info(PREFIX .. stringify(message))
end

function logger.warn(message)
    emu.print_warning(PREFIX .. stringify(message))
end

function logger.error(message)
    emu.print_error(PREFIX .. stringify(message))
end

return logger
