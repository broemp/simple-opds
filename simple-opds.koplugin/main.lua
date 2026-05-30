local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local FeedClient = require("simple_opds/feed")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Picker = require("simple_opds/ui/picker")
local ServerSettings = require("simple_opds/settings")
local Shell = require("simple_opds/ui/shell")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local SimpleOPDS = WidgetContainer:extend{
    name = "simple_opds",
}

function SimpleOPDS:init()
    self.ui.menu:registerToMainMenu(self)
end

function SimpleOPDS:addToMainMenu(menu_items)
    if self.ui.document then return end -- FileManager only
    menu_items.simple_opds = {
        text = _("Simple OPDS"),
        sorting_hint = "search",
        callback = function() self:open() end,
    }
end

function SimpleOPDS:_download_dir()
    if self.ui.file_chooser and self.ui.file_chooser.path then
        return self.ui.file_chooser.path
    end
    return require("datastorage"):getDataDir()
end

function SimpleOPDS:open()
    local servers = ServerSettings.list()
    if #servers == 0 then
        Picker.add_server(function(server) self:_open_server(server) end)
        return
    end
    if #servers == 1 then
        self:_open_server(servers[1])
        return
    end
    local last_id = ServerSettings.last_used_id()
    local last = last_id and ServerSettings.get(last_id)
    if last then
        self:_open_server(last)
        return
    end
    Picker.pick(function(server) self:_open_server(server) end,
                function(server) self:_open_server(server) end)
end

function SimpleOPDS:_open_server(server)
    NetworkMgr:runWhenConnected(function()
        UIManager:show(InfoMessage:new{ text = _("Connecting…"), timeout = 1 })
        UIManager:nextTick(function()
            local nav_links = FeedClient.discover(server) or {}
            self.shell = Shell:new{
                server = server,
                nav_links = nav_links,
                current_view = "home",
                download_dir = self:_download_dir(),
                file_downloaded_callback = function(path) self:_after_download(path) end,
                on_switch_server = function()
                    UIManager:close(self.shell)
                    self.shell = nil
                    Picker.pick(function(s) self:_open_server(s) end,
                                function(s) self:_open_server(s) end)
                end,
                on_close = function() self.shell = nil end,
            }
            UIManager:show(self.shell)
        end)
    end)
end

function SimpleOPDS:_after_download(path)
    self.last_downloaded_file = path
    local confirm = ConfirmBox:new{
        text = T(_("File saved to:\n%1\nOpen it now?"), BD.filepath(path)),
        ok_text = _("Open"),
        ok_callback = function()
            self.last_downloaded_file = nil
            if self.shell then
                UIManager:close(self.shell)
                self.shell = nil
            end
            if self.ui.document then
                self.ui:switchDocument(path)
            else
                self.ui:openFile(path)
            end
        end,
    }
    UIManager:nextTick(function() UIManager:show(confirm) end)
end

-- Update FileManager listing once a file lands so the user can see it on close.
function SimpleOPDS:onFlushSettings()
    if self.last_downloaded_file and self.ui.file_chooser then
        local pathname = util.splitFilePathName(self.last_downloaded_file)
        self.ui.file_chooser:changeToPath(pathname, self.last_downloaded_file)
        self.last_downloaded_file = nil
    end
end

return SimpleOPDS
