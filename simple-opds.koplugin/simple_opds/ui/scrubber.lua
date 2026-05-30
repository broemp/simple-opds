local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")

local Screen = Device.screen

-- iPhone-style alphabet scrubber. Each letter is a thin tappable strip.
-- Letters present in `letters_present` are full-strength; missing ones are
-- rendered light gray; the currently selected letter is bolded.

local Scrubber = InputContainer:extend{
    height = 600,
    width = nil,
    letters = nil,        -- array of strings, defaults to A..Z
    letters_present = nil, -- map { ["A"] = true, ... }
    selected = nil,
    on_select = nil,      -- function(letter)
}

local function default_alphabet()
    local out = {}
    for c = string.byte("A"), string.byte("Z") do
        table.insert(out, string.char(c))
    end
    return out
end

local LetterCell = InputContainer:extend{
    letter = nil,
    is_present = false,
    is_selected = false,
    width = 24,
    height = 22,
    on_tap = nil,
}

function LetterCell:init()
    local color = self.is_present and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY
    self[1] = FrameContainer:new{
        bordersize = 0,
        margin = 0,
        padding = 0,
        background = self.is_selected and Blitbuffer.COLOR_LIGHT_GRAY or nil,
        width = self.width,
        height = self.height,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text = self.letter,
                face = Font:getFace("smallinfofont"),
                bold = self.is_selected,
                fgcolor = color,
            },
        },
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapLetter = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
end

function LetterCell:onTapLetter()
    if self.on_tap then self.on_tap(self.letter) end
    return true
end

function Scrubber:init()
    local letters = self.letters or default_alphabet()
    local cell_w = self.width or Screen:scaleBySize(28)
    local cell_h = math.floor(self.height / #letters)
    self.dimen = Geom:new{ x = 0, y = 0, w = cell_w, h = self.height }

    local stack = VerticalGroup:new{ align = "center" }
    for _, letter in ipairs(letters) do
        local cell = LetterCell:new{
            letter = letter,
            is_present = self.letters_present and self.letters_present[letter] or false,
            is_selected = letter == self.selected,
            width = cell_w,
            height = cell_h,
            on_tap = function(L)
                if self.letters_present and not self.letters_present[L] then return end
                if self.on_select then self.on_select(L) end
            end,
        }
        table.insert(stack, cell)
    end
    self[1] = FrameContainer:new{
        bordersize = 0,
        margin = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = cell_w,
        height = self.height,
        stack,
    }
end

return Scrubber
