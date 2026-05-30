local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")

local Screen = Device.screen

-- ------------------------------------------------------------------ ListRow
-- A row's appearance depends on whether the item is a book or a category:
--   book     → thumbnail + title + author
--   category → bigger title, no thumbnail, ">" indicator on the right
-- Category detection: no acquisitions = navigation entry.

local ListRow = InputContainer:extend{
    item = nil,
    cover_path = nil,
    width = 600,
    height = 56,
    on_tap = nil,
    inset_x = nil,  -- pixels of left margin reserved for the scrubber
}

local function build_thumb(width, height, path)
    if not (path and lfs.attributes(path, "mode") == "file") then return nil end
    return ImageWidget:new{
        file = path,
        width = width,
        height = height,
        scale_factor = 0,
        file_do_cache = false,
    }
end

function ListRow:init()
    local thumb_h = self.height - 2 * Size.padding.small
    local thumb_w = math.floor(thumb_h * 0.7)
    self._thumb_w, self._thumb_h = thumb_w, thumb_h

    local is_category = not self.item.acquisitions or #self.item.acquisitions == 0
    local has_cover = self.item.cover_url ~= nil and self.item.cover_url ~= ""

    local row_content = HorizontalGroup:new{ align = "center" }
    local inset = self.inset_x or 0
    table.insert(row_content, HorizontalSpan:new{ width = Size.padding.large + inset })

    local text_left = Size.padding.large + inset
    if has_cover then
        self._thumb_slot = build_thumb(thumb_w, thumb_h, self.cover_path)
                           or HorizontalSpan:new{ width = thumb_w }
        table.insert(row_content, self._thumb_slot)
        table.insert(row_content, HorizontalSpan:new{ width = Size.padding.large })
        text_left = text_left + thumb_w + Size.padding.large
    end

    local trailing_icon_w = 0
    if is_category then trailing_icon_w = Screen:scaleBySize(28) end
    local text_w = self.width - text_left - trailing_icon_w - Size.padding.large

    local title_face = is_category and Font:getFace("smalltfont") or Font:getFace("infofont")
    local title = TextWidget:new{
        text = self.item.title or "",
        face = title_face,
        max_width = text_w,
        bold = is_category,
    }

    local label_stack
    if is_category then
        label_stack = title
    else
        local author
        if self.item.author and self.item.author ~= "" then
            author = TextWidget:new{
                text = self.item.author,
                face = Font:getFace("smallinfofont"),
                max_width = text_w,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            }
        else
            author = VerticalSpan:new{ width = 0 }
        end
        label_stack = VerticalGroup:new{
            align = "left",
            title,
            author,
        }
    end
    table.insert(row_content, label_stack)

    if is_category then
        -- push the ">" to the right edge by padding the row's right side
        table.insert(row_content, HorizontalSpan:new{
            width = math.max(0, self.width - text_left - title:getSize().w
                                - trailing_icon_w - Size.padding.large),
        })
        table.insert(row_content, IconWidget:new{
            icon = "chevron.right",
            width = trailing_icon_w,
            height = trailing_icon_w,
        })
    end

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = Size.padding.small,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = self.width,
        height = self.height,
        LeftContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            row_content,
        },
    }

    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapRow = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
end

function ListRow:set_cover_path(path)
    if path == self.cover_path then return end
    self.cover_path = path
    local new_thumb = build_thumb(self._thumb_w, self._thumb_h, path)
    if not new_thumb then return end
    self._thumb_slot = new_thumb
    -- self[1] FrameContainer → LeftContainer → HorizontalGroup
    -- After the leading span at [1], the thumb is at [2] when has_cover.
    local hg = self[1][1][1]
    hg[2] = new_thumb
end

function ListRow:onTapRow()
    if self.on_tap then self.on_tap(self.item) end
    return true
end

-- ----------------------------------------------------------------- ListView
-- A vertical stack of rows. Trims to whatever fits in `self.height`.
-- `inset_x` reserves a left margin so a scrubber can live on the right.

local ListView = InputContainer:extend{
    width = nil,
    height = nil,
    items = nil,
    inset_x = 0,
    cover_cache = nil,
    fetch_cover = nil,
    on_select = nil,
    show_parent = nil,
}

local function list_metrics(height)
    local row_h = Screen:scaleBySize(56)
    local outer_padding = Size.padding.default
    local usable_h = height - 2 * outer_padding
    local max_rows = math.max(1, math.floor(usable_h / row_h))
    return { row_h = row_h, outer_padding = outer_padding, max_rows = max_rows }
end

function ListView.items_per_page(_width, height)
    return list_metrics(height).max_rows
end

function ListView:init()
    self.width = self.width or Screen:getWidth()
    self.height = self.height or Screen:getHeight()

    local m = list_metrics(self.height)
    local row_h, outer_padding, max_rows = m.row_h, m.outer_padding, m.max_rows

    local items = self.items or {}
    if #items > max_rows then
        local trimmed = {}
        for i = 1, max_rows do trimmed[i] = items[i] end
        items = trimmed
    end

    self._rows = {}
    self._rows_by_url = {}
    local stack = VerticalGroup:new{ align = "left" }
    table.insert(stack, VerticalSpan:new{ width = outer_padding })
    for idx, item in ipairs(items) do
        local cached = item.cover_url and self.cover_cache
                       and self.cover_cache.has(item.cover_url)
        local cover_path = cached and self.cover_cache.path_for(item.cover_url) or nil
        local row = ListRow:new{
            item = item,
            cover_path = cover_path,
            width = self.width,
            height = row_h,
            inset_x = self.inset_x,
            on_tap = function(it) if self.on_select then self.on_select(it) end end,
        }
        self._rows[idx] = row
        if item.cover_url then self._rows_by_url[item.cover_url] = row end
        table.insert(stack, row)
        if idx < #items then
            table.insert(stack, LineWidget:new{
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                dimen = Geom:new{ w = self.width, h = Size.line.thin },
            })
        end
    end
    table.insert(stack, VerticalSpan:new{ width = outer_padding })

    self[1] = stack
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }

    if self.fetch_cover then
        for _, item in ipairs(items) do
            if item.cover_url and not (self.cover_cache and self.cover_cache.has(item.cover_url)) then
                self.fetch_cover(item)
            end
        end
    end
end

function ListView:set_cover(url, path)
    local row = self._rows_by_url and self._rows_by_url[url]
    if row then row:set_cover_path(path) end
end

return ListView
