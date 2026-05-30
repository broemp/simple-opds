local Blitbuffer = require("ffi/blitbuffer")
local BottomBar = require("simple_opds/ui/bottom_bar")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local CoverCache = require("simple_opds/cache")
local CoverGrid = require("simple_opds/ui/grid")
local ListView = require("simple_opds/ui/list")
local Scrubber = require("simple_opds/ui/scrubber")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local GestureRange = require("ui/gesturerange")
local TextWidget = require("ui/widget/textwidget")
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
local logger = require("logger")
local VerticalSpan = require("ui/widget/verticalspan")
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

local FEED_ERROR_TEXT = {
    [401] = _("Authentication required. Edit the server to add a username and password."),
    [403] = _("Access denied. Check the username and password."),
    [404] = _("Feed not found."),
    [406] = _("Server refused to serve uncompressed content."),
    parse = _("Server response was not a valid OPDS feed."),
}

local Shell = InputContainer:extend{
    server = nil,                   -- table: { id, name, url, ... }
    nav_links = nil,                -- {recent, popular, categories}
    discovered_search_url = nil,    -- OpenSearch URL from the root feed
    discovered_entries = nil,       -- root feed entries [{label, href}, ...]
    download_dir = nil,
    file_downloaded_callback = nil,
    on_switch_server = nil,
    on_edit_server = nil,
    on_close = nil,

    covers_fullscreen = true,
}

function Shell:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_in_flight = {}
    self.nav_links = self.nav_links or {}
    self.tabs = ServerSettings.normalize_tabs(self.server, {
        nav_links = self.nav_links,
        search_url = self.discovered_search_url,
        entries = self.discovered_entries or {},
    })
    self.active_tab = 1
    self:_build_chrome()
    -- Swipe left/right to flip pages; gesture range covers the full shell so
    -- the content area is the primary swipe target.
    self.ges_events = {
        Swipe = {
            GestureRange:new{ ges = "swipe", range = self.dimen },
        },
    }
    self:set_tab(1)
end

function Shell:_build_chrome()
    self.title_bar = TitleBar:new{
        title = self.server.name or _("OPDS"),
        subtitle = self:_subtitle_for_active(),
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:_show_menu() end,
        close_callback = function() self:_close() end,
        show_parent = self,
    }
    self.bottom_bar = self:_build_bottom_bar()
    self._page_indicator_h = Screen:scaleBySize(20)
    self.page_indicator = self:_build_page_indicator("")
    self._content_h = Screen:getHeight() - self.title_bar:getSize().h
                      - self.bottom_bar:getSize().h - self._page_indicator_h

    self.content_frame = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = Screen:getWidth(),
        height = self._content_h,
        VerticalSpan:new{ width = self._content_h },
    }

    self._outer_vg = VerticalGroup:new{
        align = "left",
        self.title_bar,
        self.content_frame,
        self.page_indicator,
        self.bottom_bar,
    }

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        self._outer_vg,
    }
end

function Shell:_invalidate_layout()
    if self._outer_vg and self._outer_vg.resetLayout then
        self._outer_vg:resetLayout()
    end
end

function Shell:_build_page_indicator(text)
    return FrameContainer:new{
        bordersize = 0,
        margin = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = Screen:getWidth(),
        height = self._page_indicator_h,
        CenterContainer:new{
            dimen = Geom:new{ w = Screen:getWidth(), h = self._page_indicator_h },
            TextWidget:new{
                text = text or "",
                face = Font:getFace("xx_smallinfofont"),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        },
    }
end

function Shell:_set_page_indicator(text)
    self.page_indicator = self:_build_page_indicator(text)
    -- [1] title, [2] content, [3] indicator, [4] bottom bar
    self._outer_vg[3] = self.page_indicator
    self:_invalidate_layout()
end

function Shell:_swap_content(widget)
    self.content_frame[1] = widget
    self:_invalidate_layout()
end

function Shell:_build_bottom_bar()
    return BottomBar.build{
        tabs = self.tabs,
        active_index = self.active_tab,
        width = Screen:getWidth(),
        on_select = function(index) self:set_tab(index) end,
    }
end

function Shell:_subtitle_for_active()
    local tab = self.tabs and self.tabs[self.active_tab]
    return tab and tab.label or ""
end

function Shell:set_tab(index)
    self.active_tab = index
    if self.title_bar and self.title_bar.setSubTitle then
        self.title_bar:setSubTitle(self:_subtitle_for_active())
    end
    self.bottom_bar = self:_build_bottom_bar()
    self._outer_vg[4] = self.bottom_bar
    self:_invalidate_layout()
    UIManager:setDirty(self, "ui")

    local tab = self.tabs[index]
    if not tab then return end
    if tab.href == ServerSettings.SEARCH_HREF then
        self:_prompt_search()
    else
        self:_load_feed(tab.href)
    end
end

function Shell:_load_feed(target_url)
    self._last_feed_url = target_url
    self._az_letters = nil
    self._az_selected = nil
    if not target_url then
        self:_set_content_message(_("No feed configured for this tab."))
        return
    end
    local loading = InfoMessage:new{ text = _("Loading…"), timeout = 1 }
    UIManager:show(loading)
    UIManager:nextTick(function()
        local listing, code = FeedClient.list_items(self.server, target_url)
        UIManager:close(loading)
        if not listing then
            local detail = FEED_ERROR_TEXT[code]
                           or (code and ("HTTP " .. tostring(code)))
                           or _("Network unreachable.")
            self:_set_content_message(_("Could not load feed.") .. "\n\n" .. detail)
            return
        end
        self.last_listing = listing

        -- If the feed looks like an A-Z index (Calibre's "By Title", "By
        -- Author", etc.), auto-load the first letter and render the
        -- scrubber on the right so the user can jump between letters.
        local az = FeedClient.detect_az_index(listing)
        if az then
            self._az_letters = az
            self:_load_az_letter(self:_first_az_letter(az))
            return
        end

        self:_set_content_grid(listing.items)
    end)
end

function Shell:_first_az_letter(az)
    for c = string.byte("A"), string.byte("Z") do
        local L = string.char(c)
        if az[L] then return L end
    end
end

function Shell:_load_az_letter(letter)
    if not letter or not self._az_letters or not self._az_letters[letter] then return end
    self._az_selected = letter
    local loading = InfoMessage:new{
        text = _("Loading ") .. letter .. "…", timeout = 1,
    }
    UIManager:show(loading)
    UIManager:nextTick(function()
        local listing, code = FeedClient.list_items(self.server, self._az_letters[letter])
        UIManager:close(loading)
        if not listing then
            self:_set_content_message(_("Could not load section ") .. letter
                .. "\n\n" .. (FEED_ERROR_TEXT[code] or ("HTTP " .. tostring(code or "?"))))
            return
        end
        self.last_listing = listing
        self:_set_content_grid(listing.items)
    end)
end

-- New listing arrived: store the full items, reset to page 1, render.
function Shell:_set_content_grid(items)
    self._all_items = items or {}
    self._page = 1
    self:_render_current_page()
end

function Shell:_render_current_page()
    local tab = self.tabs[self.active_tab]
    local in_az = self._az_letters ~= nil
    local scrubber_w = in_az and Screen:scaleBySize(28) or 0

    local widget_cls = (tab and tab.view == "list") and ListView or CoverGrid
    local content_w = Screen:getWidth() - scrubber_w
    local per_page = math.max(1, widget_cls.items_per_page(content_w, self._content_h))
    local total = #self._all_items
    self._total_pages = math.max(1, math.ceil(total / per_page))
    if self._page > self._total_pages then self._page = self._total_pages end
    if self._page < 1 then self._page = 1 end

    local start = (self._page - 1) * per_page + 1
    local stop = math.min(start + per_page - 1, total)
    local slice = {}
    for i = start, stop do slice[#slice + 1] = self._all_items[i] end

    local view = widget_cls:new{
        items = slice,
        width = content_w,
        height = self._content_h,
        cover_cache = CoverCache,
        show_parent = self,
        fetch_cover = function(item) self:_fetch_cover_async(item) end,
        on_select = function(item) self:_on_item_selected(item) end,
    }
    self._current_view = view

    if in_az then
        local scrubber = Scrubber:new{
            width = scrubber_w,
            height = self._content_h,
            letters_present = self._az_letters,
            selected = self._az_selected,
            on_select = function(L) self:_load_az_letter(L) end,
        }
        self:_swap_content(HorizontalGroup:new{
            align = "top",
            view,
            scrubber,
        })
    else
        self:_swap_content(view)
    end

    if self._total_pages > 1 then
        self:_set_page_indicator(self._page .. " / " .. self._total_pages)
    else
        self:_set_page_indicator("")
    end

    UIManager:setDirty(self, "ui")
end

function Shell:onSwipe(_arg, ges)
    local dir = ges and ges.direction
    if dir == "west" then        -- finger moves left → next page
        self:_change_page(1)
        return true
    elseif dir == "east" then    -- finger moves right → previous page
        self:_change_page(-1)
        return true
    end
end

function Shell:_change_page(delta)
    if not self._total_pages or self._total_pages <= 1 then return end
    local new_page = (self._page or 1) + delta
    if new_page < 1 or new_page > self._total_pages then return end
    self._page = new_page
    self:_render_current_page()
end

function Shell:_set_content_message(text)
    self:_swap_content(CenterContainer:new{
        dimen = Geom:new{ w = Screen:getWidth(), h = self._content_h },
        TextBoxWidget:new{
            text = text,
            face = Font:getFace("infofont"),
            width = math.floor(Screen:getWidth() * 0.8),
            alignment = "center",
        },
    })
    UIManager:setDirty(self, "ui")
end

-- Kick off a cover download in a forked subprocess. The poller below reaps
-- the worker via isSubProcessDone (otherwise it lingers as a zombie and a
-- few hundred swipes exhaust the process table, hanging the next fork()).
function Shell:_fetch_cover_async(item)
    if not item.cover_url then return end
    if self.covers_in_flight[item.cover_url] then return end

    local FFIUtil = require("ffi/util")
    local target = CoverCache.path_for(item.cover_url)
    local server = self.server
    local cover_url = item.cover_url
    local pid = FFIUtil.runInSubProcess(function()
        FeedClient.download_to(target, cover_url, server.username, server.password)
    end)
    if not pid or pid < 0 then
        logger.dbg("simple-opds: fork failed for", cover_url)
        return
    end

    self.covers_in_flight[cover_url] = {
        item = item,
        pid = pid,
        target = target,
    }
    self:_start_cover_poller()
end

function Shell:_start_cover_poller()
    if self._cover_poller_running then return end
    self._cover_poller_running = true
    UIManager:scheduleIn(0.4, function() self:_poll_covers() end)
end

function Shell:_poll_covers()
    if self._closed or not self._cover_poller_running then
        self._cover_poller_running = false
        return
    end
    if not next(self.covers_in_flight) then
        self._cover_poller_running = false
        return
    end

    local FFIUtil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    local succeeded, failed = {}, {}

    for url, entry in pairs(self.covers_in_flight) do
        if FFIUtil.isSubProcessDone(entry.pid, false) then
            -- Worker reaped. Either the rename landed the final file or the
            -- download failed and only .tmp was cleaned up.
            if lfs.attributes(entry.target, "mode") == "file" then
                succeeded[#succeeded + 1] = url
            else
                failed[#failed + 1] = url
            end
        end
    end

    for _, url in ipairs(succeeded) do
        local entry = self.covers_in_flight[url]
        self.covers_in_flight[url] = nil
        CoverCache.record(url, {
            title = entry.item and entry.item.title,
            author = entry.item and entry.item.author,
        })
        if self._current_view and self._current_view.set_cover then
            self._current_view:set_cover(url, entry.target)
        end
    end
    for _, url in ipairs(failed) do
        self.covers_in_flight[url] = nil
    end

    if #succeeded > 0 then
        UIManager:setDirty(self, "ui")
        CoverCache.prune()
    end

    if next(self.covers_in_flight) then
        UIManager:scheduleIn(0.4, function() self:_poll_covers() end)
    else
        self._cover_poller_running = false
    end
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
    local search_url = (self.last_listing and self.last_listing.search_url)
                       or self.discovered_search_url
                       or self.nav_links.search
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
            {{ text = _("Configure tabs"), align = "left",
               callback = function()
                   UIManager:close(dialog)
                   self:_show_tab_picker()
               end }},
            {{ text = _("Edit server credentials"), align = "left",
               callback = function()
                   UIManager:close(dialog)
                   if self.on_edit_server then self.on_edit_server() end
               end }},
            {{ text = _("Switch server"), align = "left",
               callback = function()
                   UIManager:close(dialog)
                   if self.on_switch_server then self.on_switch_server() end
               end }},
        },
    }
    UIManager:show(dialog)
end

-- Gather pickable feed options from the server's root catalog.
-- Cached after the first fetch to keep the picker snappy.
function Shell:_load_options(callback)
    if self._options_cache then callback(self._options_cache); return end
    local loading = InfoMessage:new{ text = _("Loading options…"), timeout = 1 }
    UIManager:show(loading)
    UIManager:nextTick(function()
        local listing = FeedClient.list_items(self.server, self.server.url)
        UIManager:close(loading)
        local options = {}
        if self._last_feed_url and self._last_feed_url ~= self.server.url then
            table.insert(options, {
                label = _("[Current feed]"),
                href = self._last_feed_url,
            })
        end
        table.insert(options, { label = _("Search"), href = ServerSettings.SEARCH_HREF })
        table.insert(options, { label = _("Server root"), href = self.server.url })
        if listing and listing.items then
            for _, item in ipairs(listing.items) do
                local href = item.sub_feed_url
                local label = item.title
                if href and label and label ~= "" then
                    table.insert(options, { label = label, href = href })
                end
            end
        end
        self._options_cache = options
        callback(options)
    end)
end

-- Step 1: each tab is a row with TWO buttons:
--   [Tab N: <label>]   [<Grid/List>]
-- The left button opens the feed-option dropdown; the right one toggles
-- view mode in place. After any change, we rebuild the bar and re-open
-- this dialog so all four tabs can be configured in one session.
function Shell:_show_tab_picker()
    self:_load_options(function(options)
        local buttons = {}
        for i = 1, ServerSettings.TAB_COUNT do
            local tab = self.tabs[i]
            local label = tab and tab.label or ("Tab " .. i)
            local view = (tab and tab.view == "list") and _("List") or _("Grid")
            table.insert(buttons, {
                { text = "Tab " .. i .. ":  " .. label, align = "left",
                  callback = function()
                      UIManager:close(self._tab_picker_dialog)
                      self:_show_option_dialog(i, options)
                  end },
                { text = view, align = "center",
                  callback = function()
                      UIManager:close(self._tab_picker_dialog)
                      self:_toggle_tab_view(i)
                      self:_show_tab_picker()
                  end },
            })
        end
        table.insert(buttons, {{
            text = _("Done"), align = "center",
            callback = function() UIManager:close(self._tab_picker_dialog) end,
        }})
        self._tab_picker_dialog = ButtonDialog:new{ buttons = buttons }
        UIManager:show(self._tab_picker_dialog)
    end)
end

function Shell:_toggle_tab_view(tab_index)
    local tab = self.tabs[tab_index]
    if not tab then return end
    tab.view = (tab.view == "list") and "grid" or "list"
    self.server.tabs = self.tabs
    ServerSettings.save(self.server)
    -- If the user is currently viewing this tab, re-render with the new mode.
    if self.active_tab == tab_index and self.last_listing then
        self:_set_content_grid(self.last_listing.items)
    end
end

-- Step 2: dropdown of discovered options for a specific tab slot.
function Shell:_show_option_dialog(tab_index, options)
    local buttons = {}
    for _, opt in ipairs(options) do
        table.insert(buttons, {{
            text = opt.label,
            align = "left",
            callback = function()
                UIManager:close(self._option_dialog)
                self.tabs[tab_index] = { label = opt.label, href = opt.href }
                self.server.tabs = self.tabs
                ServerSettings.save(self.server)
                -- Rebuild the bottom bar so the new label shows up immediately.
                self.bottom_bar = self:_build_bottom_bar()
                self._outer_vg[4] = self.bottom_bar
                self:_invalidate_layout()
                UIManager:setDirty(self, "ui")
                -- Re-open the tab picker so the user can configure the next one.
                self:_show_tab_picker()
            end,
        }})
    end
    self._option_dialog = ButtonDialog:new{ buttons = buttons }
    UIManager:show(self._option_dialog)
end

function Shell:_close()
    self._closed = true
    self._cover_poller_running = false
    UIManager:close(self)
    if self.on_close then self.on_close() end
end

return Shell
