-- license:BSD-3-Clause
--
-- APF-family identification and future boot-sequence configuration.

local apf = {}

-- Known/anticipated APF-family short names. This list is intentionally easy
-- to expand after the first QA run reports the exact MAME driver in use.
local supported_names = {
    apfimag = true,
    apfm1000 = true,
    apfmp1000 = true
}

function apf.matches(system)
    if not system then
        return false
    end

    local name = tostring(system.name or ""):lower()
    local description = tostring(system.description or ""):lower()
    local source_file = tostring(system.source_file or ""):lower()

    return supported_names[name] == true
        or description:find("apf", 1, true) ~= nil
        or source_file:find("/apf", 1, true) ~= nil
        or source_file:find("\\apf", 1, true) ~= nil
end

function apf.supported_names()
    local result = {}
    for name in pairs(supported_names) do
        table.insert(result, name)
    end
    table.sort(result)
    return result
end

return apf
