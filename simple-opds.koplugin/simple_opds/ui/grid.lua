local CoverTile = require("simple_opds/ui/tile")
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen

local CoverGrid = InputContainer:extend{
    width = nil,
    height = nil,
    items = nil,             -- normalized FeedClient items
    cover_cache = nil,
    fetch_cover = nil,       -- function(url, cb)  — async
    on_select = nil,         -- function(item)
    show_parent = nil,
}

function CoverGrid:init()
    self.width = self.width or Screen:getWidth()
    self.height = self.height or Screen:getHeight()

    local is_landscape = self.width > self.height
    local columns = is_landscape and 4 or 3
    local outer_padding = Size.padding.large
    local gap = Size.padding.default

    local tile_w = math.floor((self.width - 2 * outer_padding - (columns - 1) * gap) / columns)
    local tile_h = math.floor(tile_w * 1.55)

    local rows = {}
    local items = self.items or {}

    -- Track tiles so async cover loaders can refresh them in-place.
    self._tiles = {}

    local row, tiles_in_row = {}, 0
    for idx, item in ipairs(items) do
        local cached = item.cover_url and self.cover_cache and self.cover_cache.has(item.cover_url)
        local cover_path = cached and self.cover_cache.path_for(item.cover_url) or nil

        local tile = CoverTile:new{
            item = item,
            cover_path = cover_path,
            width = tile_w,
            height = tile_h,
            show_parent = self.show_parent,
            on_tap = function(it) if self.on_select then self.on_select(it) end end,
        }
        self._tiles[idx] = tile

        if tiles_in_row > 0 then
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
        table.insert(row, tile)
        tiles_in_row = tiles_in_row + 1

        if tiles_in_row >= columns or idx == #items then
            table.insert(rows, HorizontalGroup:new(row))
            row, tiles_in_row = {}, 0
            if idx ~= #items then
                table.insert(rows, VerticalSpan:new{ height = gap })
            end
        end
    end

    local content = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ height = outer_padding },
    }
    for _, r in ipairs(rows) do
        table.insert(content, HorizontalGroup:new{
            HorizontalSpan:new{ width = outer_padding },
            r,
        })
    end
    table.insert(content, VerticalSpan:new{ height = outer_padding })

    self[1] = content
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }

    -- Kick off async cover fetches for any tiles missing a cached cover.
    if self.fetch_cover then
        for idx, item in ipairs(items) do
            if item.cover_url and not (self.cover_cache and self.cover_cache.has(item.cover_url)) then
                local tile = self._tiles[idx]
                UIManager:nextTick(function()
                    self.fetch_cover(item, function(success)
                        if success and tile and self.show_parent then
                            UIManager:setDirty(self.show_parent, "ui")
                        end
                    end)
                end)
            end
        end
    end
end

return CoverGrid
