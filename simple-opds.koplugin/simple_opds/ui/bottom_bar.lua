local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local _ = require("gettext")

local Screen = Device.screen

local BottomBar = {}

local TABS = {
    { id = "home",   icon = "home",     label = _("Home")   },
    { id = "recent", icon = "appbar.compose", label = _("Recent") },
    { id = "genre",  icon = "appbar.menu",    label = _("Genre")  },
    { id = "search", icon = "appbar.search",  label = _("Search") },
}

-- Build a 1-row ButtonTable. The active tab is rendered with a thicker frame
-- by setting its `enabled` to false (Button visually inverts) — we actually
-- emulate this by toggling icon + label per state.
function BottomBar.build(opts)
    local active = opts.active or "home"
    local row = {}
    for _, tab in ipairs(TABS) do
        local is_active = tab.id == active
        table.insert(row, {
            text = (is_active and "\u{25CF} " or "") .. tab.label,
            callback = function() opts.on_select(tab.id) end,
            -- Active button gets re-emphasized via the bullet prefix instead
            -- of inverting, because ButtonTable doesn't expose an "active" prop.
        })
    end
    return ButtonTable:new{
        width = opts.width or Screen:getWidth(),
        show_parent = opts.show_parent,
        buttons = { row },
    }
end

BottomBar.TABS = TABS

return BottomBar
