local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")

local CoverTile = InputContainer:extend{
    item = nil,
    cover_path = nil,
    width = 200,
    height = 280,
    on_tap = nil,
    show_parent = nil,
}

local function build_placeholder(width, height, item)
    return FrameContainer:new{
        bordersize = Size.border.thin,
        padding = Size.padding.small,
        margin = 0,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        width = width,
        height = height,
        CenterContainer:new{
            dimen = Geom:new{ w = width - 2 * Size.padding.small, h = height - 2 * Size.padding.small },
            TextWidget:new{
                text = item.title or "",
                face = Font:getFace("smallinfofont"),
                max_width = width - 2 * Size.padding.large,
            },
        },
    }
end

local function build_image(width, height, path)
    return FrameContainer:new{
        bordersize = Size.border.thin,
        padding = 0,
        margin = 0,
        width = width,
        height = height,
        ImageWidget:new{
            file = path,
            width = width - 2 * Size.border.thin,
            height = height - 2 * Size.border.thin,
            scale_factor = 0,
            file_do_cache = false,
        },
    }
end

local function build_cover(width, height, item, path)
    if path and lfs.attributes(path, "mode") == "file" then
        return build_image(width, height, path)
    end
    return build_placeholder(width, height, item)
end

function CoverTile:init()
    self._cover_h = math.floor(self.height * 0.78)
    self._label_h = self.height - self._cover_h
    self._cover_slot = build_cover(self.width, self._cover_h, self.item, self.cover_path)

    -- TextWidget auto-truncates with "…" when max_width is exceeded — way
    -- more reliable than TextBoxWidget's height-based clipping.
    local label_width = self.width - 2 * Size.padding.small
    local title = TextWidget:new{
        text = self.item.title or "",
        face = Font:getFace("x_smallinfofont"),
        max_width = label_width,
    }
    local author
    if self.item.author and self.item.author ~= "" then
        author = TextWidget:new{
            text = self.item.author,
            face = Font:getFace("xx_smallinfofont"),
            max_width = label_width,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
    else
        author = VerticalSpan:new{ width = 0 }
    end

    local label = FrameContainer:new{
        bordersize = 0,
        padding = Size.padding.small,
        width = self.width,
        height = self._label_h,
        VerticalGroup:new{
            align = "center",
            title,
            author,
        },
    }

    self._content = VerticalGroup:new{
        align = "center",
        self._cover_slot,
        label,
    }

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = Size.padding.small,
        margin = 0,
        width = self.width,
        height = self.height + 2 * Size.padding.small,
        self._content,
    }

    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height + 2 * Size.padding.small }

    self.ges_events = {
        TapTile = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
    }
end

function CoverTile:set_cover_path(path)
    if path == self.cover_path then return end
    self.cover_path = path
    local new_cover = build_cover(self.width, self._cover_h, self.item, path)
    self._cover_slot = new_cover
    self._content[1] = new_cover
    if self._content.resetLayout then self._content:resetLayout() end
end

function CoverTile:onTapTile()
    if self.on_tap then self.on_tap(self.item) end
    return true
end

return CoverTile
