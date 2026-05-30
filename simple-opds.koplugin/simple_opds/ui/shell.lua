local Blitbuffer = require("ffi/blitbuffer")
local BottomBar = require("simple_opds/ui/bottom_bar")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local CoverCache = require("simple_opds/cache")
local CoverGrid = require("simple_opds/ui/grid")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local FeedClient = require("simple_opds/feed")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local ServerSettings = require("simple_opds/settings")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local util = require("util")
local _ = require("gettext")

local Screen = Device.screen

local EXT_BY_TYPE = {
    ["application/epub+zip"] = ".epub",
    ["application/pdf"] = ".pdf",
    ["application/x-mobipocket-ebook"] = ".mobi",
    ["application/x-mobi8-ebook"] = ".azw3",
    ["application/x-fictionbook+xml"] = ".fb2",
    ["application/vnd.amazon.ebook"] = ".azw",
    ["application/x-cbz"] = ".cbz",
}

local Shell = InputContainer:extend{
    server = nil,                   -- table: { id, name, url, ... }
    nav_links = nil,                -- table: { recent, popular, categories, search }
    current_view = "home",
    download_dir = nil,
    file_downloaded_callback = nil, -- function(path)
    on_switch_server = nil,
    on_close = nil,
}

function Shell:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_in_flight = {}
    self.nav_links = self.nav_links or {}
    self:_build_chrome()
    self:set_view(self.current_view)
end

function Shell:_build_chrome()
    self.title_bar = TitleBar:new{
        title = self.server.name or _("OPDS"),
        subtitle = self:_subtitle_for(self.current_view),
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:_show_menu() end,
        close_callback = function() self:_close() end,
        show_parent = self,
    }

    self.content_frame = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = Screen:getWidth(),
        height = self:_content_height(),
        VerticalGroup:new{},
    }

    self.bottom_bar = self:_build_bottom_bar(self.current_view)

    self[1] = VerticalGroup:new{
        align = "left",
        self.title_bar,
        self.content_frame,
        self.bottom_bar,
    }
end

function Shell:_build_bottom_bar(active)
    return BottomBar.build{
        active = active,
        width = Screen:getWidth(),
        show_parent = self,
        on_select = function(tab_id) self:set_view(tab_id) end,
    }
end

function Shell:_subtitle_for(view)
    if view == "home" then return _("Home") end
    if view == "recent" then return _("Recently added") end
    if view == "genre" then return _("Categories") end
    if view == "search" then return _("Search") end
    return ""
end

function Shell:_content_height()
    local title_h = self.title_bar and self.title_bar:getSize().h or Screen:scaleBySize(60)
    local bar_h = self.bottom_bar and self.bottom_bar:getSize().h or Screen:scaleBySize(70)
    return Screen:getHeight() - title_h - bar_h
end

function Shell:set_view(view)
    self.current_view = view
    if self.title_bar and self.title_bar.setSubTitle then
        self.title_bar:setSubTitle(self:_subtitle_for(view))
    end
    self.bottom_bar = self:_build_bottom_bar(view)
    self[1][3] = self.bottom_bar

    if view == "search" then
        self:_prompt_search()
        return
    end

    local target_url = self:_url_for_view(view)
    self:_load_feed(target_url)
end

function Shell:_url_for_view(view)
    if view == "home" then
        return self.server.default_category_href
               or self.nav_links.recent
               or self.nav_links.popular
               or self.server.url
    elseif view == "recent" then
        return self.nav_links.recent or self.nav_links.popular or self.server.url
    elseif view == "genre" then
        return self.nav_links.categories or self.server.url
    end
end

function Shell:_load_feed(target_url)
    self._last_feed_url = target_url
    if not target_url then
        self:_set_content_message(_("No feed available for this tab."))
        return
    end
    local loading = InfoMessage:new{ text = _("Loading…"), timeout = 1 }
    UIManager:show(loading)
    UIManager:nextTick(function()
        local listing = FeedClient.list_items(self.server, target_url)
        UIManager:close(loading)
        if not listing then
            self:_set_content_message(_("Could not load feed."))
            return
        end
        self.last_listing = listing
        self:_set_content_grid(listing.items)
    end)
end

function Shell:_set_content_grid(items)
    local grid = CoverGrid:new{
        items = items,
        width = Screen:getWidth(),
        height = self:_content_height(),
        cover_cache = CoverCache,
        show_parent = self,
        fetch_cover = function(item, cb) self:_fetch_cover_async(item, cb) end,
        on_select = function(item) self:_on_item_selected(item) end,
    }
    self.content_frame[1] = grid
    UIManager:setDirty(self, "ui")
end

function Shell:_set_content_message(text)
    self.content_frame[1] = CenterContainer:new{
        dimen = Geom:new{ w = Screen:getWidth(), h = self:_content_height() },
        TextBoxWidget:new{
            text = text,
            face = Font:getFace("infofont"),
            width = math.floor(Screen:getWidth() * 0.8),
            alignment = "center",
        },
    }
    UIManager:setDirty(self, "ui")
end

function Shell:_fetch_cover_async(item, cb)
    if not item.cover_url then if cb then cb(false) end; return end
    if self.covers_in_flight[item.cover_url] then return end
    self.covers_in_flight[item.cover_url] = true

    UIManager:nextTick(function()
        local target = CoverCache.path_for(item.cover_url)
        local ok = FeedClient.download_to(target, item.cover_url,
                                          self.server.username, self.server.password)
        self.covers_in_flight[item.cover_url] = nil
        if ok then
            CoverCache.record(item.cover_url, { title = item.title, author = item.author })
            CoverCache.prune()
        end
        if cb then cb(ok) end
    end)
end

function Shell:_on_item_selected(item)
    if item.sub_feed_url and #item.acquisitions == 0 then
        self:_load_feed(item.sub_feed_url)
        return
    end
    if #item.acquisitions == 0 then
        UIManager:show(InfoMessage:new{ text = _("Nothing to download for this entry.") })
        return
    end
    local chosen
    for _, acq in ipairs(item.acquisitions) do
        if acq.type and DocumentRegistry:hasProvider(nil, acq.type) then
            chosen = acq
            break
        end
    end
    chosen = chosen or item.acquisitions[1]
    self:_download(item, chosen)
end

function Shell:_download(item, acq)
    if not self.download_dir then
        UIManager:show(InfoMessage:new{ text = _("No download directory configured.") })
        return
    end
    local filename = util.getSafeFilename((item.title or "book") .. (EXT_BY_TYPE[acq.type] or ""),
                                          self.download_dir)
    local local_path = self.download_dir .. "/" .. filename
    UIManager:show(InfoMessage:new{ text = _("Downloading…"), timeout = 1 })
    UIManager:scheduleIn(0.5, function()
        local ok = FeedClient.download_to(local_path, acq.href,
                                          self.server.username, self.server.password)
        if ok and self.file_downloaded_callback then
            self.file_downloaded_callback(local_path)
        elseif not ok then
            UIManager:show(InfoMessage:new{ text = _("Download failed.") })
        end
    end)
end

function Shell:_prompt_search()
    local search_url = (self.last_listing and self.last_listing.search_url) or self.nav_links.search
    if not search_url then
        self:_set_content_message(_("This catalog does not expose a search endpoint."))
        return
    end
    local input
    input = InputDialog:new{
        title = _("Search catalog"),
        input = "",
        buttons = {{
            { text = _("Cancel"), id = "close",
              callback = function() UIManager:close(input) end },
            { text = _("Search"), is_enter_default = true,
              callback = function()
                  local q = input:getInputText()
                  UIManager:close(input)
                  self:_run_search(search_url, q)
              end },
        }},
    }
    UIManager:show(input)
    input:onShowKeyboard()
end

function Shell:_run_search(search_url, query)
    UIManager:show(InfoMessage:new{ text = _("Searching…"), timeout = 1 })
    UIManager:nextTick(function()
        local listing = FeedClient.search(self.server, search_url, query)
        if not listing then
            self:_set_content_message(_("No results."))
            return
        end
        self.last_listing = listing
        self:_set_content_grid(listing.items)
    end)
end

function Shell:_show_menu()
    local dialog
    dialog = ButtonDialog:new{
        buttons = {
            {{ text = _("Switch server"), align = "left",
               callback = function()
                   UIManager:close(dialog)
                   if self.on_switch_server then self.on_switch_server() end
               end }},
            {{ text = _("Use current feed as Home"), align = "left",
               callback = function()
                   UIManager:close(dialog)
                   self:_set_home_to_current()
               end }},
        },
    }
    UIManager:show(dialog)
end

function Shell:_set_home_to_current()
    if not self._last_feed_url then return end
    self.server.default_category_href = self._last_feed_url
    ServerSettings.save(self.server)
    UIManager:show(InfoMessage:new{
        text = _("Home tab now opens the current view."), timeout = 2,
    })
end

function Shell:_close()
    UIManager:close(self)
    if self.on_close then self.on_close() end
end

return Shell
