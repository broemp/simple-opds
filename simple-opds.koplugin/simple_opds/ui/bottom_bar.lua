local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local logger = require("logger")

local Screen = Device.screen

-- One tappable tab cell. Plain InputContainer + GestureRange so we don't
-- depend on Button/ButtonTable/FocusManager dispatch (both swallowed taps in
-- our nested layout — see history).
local Tab = InputContainer:extend{
    label = nil,
    index = nil,
    is_active = false,
    width = 100,
    height = 50,
    on_select = nil,
}

function Tab:init()
    self[1] = FrameContainer:new{
        bordersize = 0,
        margin = 0,
        padding = 0,
        background = self.is_active and Blitbuffer.COLOR_LIGHT_GRAY or nil,
        width = self.width,
        height = self.height,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text = self.label,
                face = Font:getFace("smallinfofont"),
                bold = self.is_active,
                max_width = self.width - 2 * Size.padding.small,
            },
        },
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapTab = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
end

function Tab:onTapTab()
    logger.dbg("simple-opds: TapTab on", self.index, self.label)
    if self.on_select then self.on_select(self.index) end
    return true
end

-- Build the bottom navigation bar.
-- opts.tabs: array of {label, href} (href is consumed by Shell; we only
--   render the label and report the tapped index).
-- opts.active_index: 1-based index of the currently selected tab.
-- opts.on_select(index): callback invoked on tap.
local function build(opts)
    local tabs = opts.tabs or {}
    local total_w = opts.width or Screen:getWidth()
    local bar_h = Screen:scaleBySize(56)
    local count = math.max(#tabs, 1)
    local tab_w = math.floor(total_w / count)

    local group = HorizontalGroup:new{ align = "center" }
    for i, tab in ipairs(tabs) do
        table.insert(group, Tab:new{
            label = tab.label,
            index = i,
            is_active = i == opts.active_index,
            width = tab_w,
            height = bar_h,
            on_select = opts.on_select,
        })
    end

    return FrameContainer:new{
        bordersize = Size.border.thin,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = total_w,
        height = bar_h + 2 * Size.border.thin,
        group,
    }
end

return {
    build = build,
}
