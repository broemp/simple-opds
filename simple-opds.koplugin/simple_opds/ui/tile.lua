local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")

local CoverTile = InputContainer:extend{
    item = nil,
    cover_path = nil,    -- absolute path to a cached cover file, or nil
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
            TextBoxWidget:new{
                text = item.title or "",
                face = Font:getFace("smallinfofont"),
                width = width - 2 * Size.padding.large,
                alignment = "center",
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
            scale_factor = 0, -- fit, keep aspect ratio
            file_do_cache = false,
        },
    }
end

function CoverTile:init()
    local cover_h = math.floor(self.height * 0.78)
    local label_h = self.height - cover_h
    local cover
    if self.cover_path and lfs.attributes(self.cover_path, "mode") == "file" then
        cover = build_image(self.width, cover_h, self.cover_path)
    else
        cover = build_placeholder(self.width, cover_h, self.item)
    end

    local label = FrameContainer:new{
        bordersize = 0,
        padding = Size.padding.small,
        width = self.width,
        height = label_h,
        VerticalGroup:new{
            align = "center",
            TextBoxWidget:new{
                text = self.item.title or "",
                face = Font:getFace("x_smallinfofont"),
                width = self.width - 2 * Size.padding.small,
                alignment = "center",
                line_height = 0,
            },
            self.item.author and TextBoxWidget:new{
                text = self.item.author,
                face = Font:getFace("xx_smallinfofont"),
                width = self.width - 2 * Size.padding.small,
                alignment = "center",
                line_height = 0,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            } or VerticalSpan:new{ width = 0 },
        },
    }

    local content = VerticalGroup:new{
        align = "center",
        cover,
        label,
    }

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = Size.padding.small,
        margin = 0,
        width = self.width,
        height = self.height + 2 * Size.padding.small,
        content,
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

function CoverTile:onTapTile()
    if self.on_tap then self.on_tap(self.item) end
    return true
end

return CoverTile
