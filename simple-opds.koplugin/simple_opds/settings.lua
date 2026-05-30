local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/simple-opds.lua"

local ServerSettings = {}

local function open()
    return LuaSettings:open(SETTINGS_FILE)
end

function ServerSettings.list()
    return open():readSetting("servers", {})
end

function ServerSettings.last_used_id()
    return open():readSetting("last_used")
end

function ServerSettings.get(id)
    for _, s in ipairs(ServerSettings.list()) do
        if s.id == id then return s end
    end
end

local function next_id(servers)
    local max = 0
    for _, s in ipairs(servers) do
        if s.id and s.id > max then max = s.id end
    end
    return max + 1
end

function ServerSettings.save(server)
    local settings = open()
    local servers = settings:readSetting("servers", {})
    if not server.id then
        server.id = next_id(servers)
        table.insert(servers, server)
    else
        for i, s in ipairs(servers) do
            if s.id == server.id then servers[i] = server; break end
        end
    end
    settings:saveSetting("servers", servers)
    settings:saveSetting("last_used", server.id)
    settings:flush()
    return server
end

function ServerSettings.remove(id)
    local settings = open()
    local servers = settings:readSetting("servers", {})
    for i, s in ipairs(servers) do
        if s.id == id then table.remove(servers, i); break end
    end
    settings:saveSetting("servers", servers)
    if settings:readSetting("last_used") == id then
        settings:delSetting("last_used")
    end
    settings:flush()
end

function ServerSettings.set_last_used(id)
    local settings = open()
    settings:saveSetting("last_used", id)
    settings:flush()
end

return ServerSettings
