local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/simple-opds.lua"

local ServerSettings = {}

ServerSettings.SEARCH_HREF = "@search"
ServerSettings.TAB_COUNT = 4
ServerSettings.VIEW_MODES = { "grid", "list" }

local function valid_view(v)
    return (v == "grid" or v == "list") and v or "grid"
end

function ServerSettings.default_tabs(server, nav_links)
    nav_links = nav_links or {}
    return {
        { label = "Home",   href = server.default_category_href or server.url, view = "grid" },
        { label = "Recent", href = nav_links.recent or nav_links.popular or server.url, view = "grid" },
        { label = "Genre",  href = nav_links.categories or server.url, view = "list" },
        { label = "Search", href = ServerSettings.SEARCH_HREF, view = "grid" },
    }
end

function ServerSettings.normalize_tabs(server, nav_links)
    local tabs = server.tabs
    if type(tabs) ~= "table" or #tabs == 0 then
        return ServerSettings.default_tabs(server, nav_links)
    end
    local out = {}
    for i = 1, ServerSettings.TAB_COUNT do
        local t = tabs[i] or {}
        out[i] = {
            label = (t.label and t.label ~= "") and t.label or ("Tab " .. i),
            href = (t.href and t.href ~= "") and t.href or server.url,
            view = valid_view(t.view),
        }
    end
    return out
end

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
