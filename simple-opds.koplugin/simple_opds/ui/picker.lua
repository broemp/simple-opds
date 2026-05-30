local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ServerSettings = require("simple_opds/settings")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Picker = {}

-- Show an add-or-edit dialog. Pass `existing` to prefill from a stored server.
-- NOTE: MultiInputDialog's `text_type = "password"` is broken upstream
-- (see multiinputdialog.lua: "semi-broken when text_type is password"), so the
-- password field renders in plain text. Acceptable trade-off vs. losing it.
local function show_form(existing, on_saved)
    local title = existing and _("Edit OPDS server") or _("Add OPDS server")
    local dialog
    dialog = MultiInputDialog:new{
        title = title,
        fields = {
            { description = _("Name"),
              text = existing and existing.name or "",
              hint = _("e.g. My Calibre") },
            { description = _("Catalog URL"),
              text = existing and existing.url or "",
              hint = _("https://…/opds") },
            { description = _("Username (optional)"),
              text = existing and existing.username or "",
              hint = "" },
            { description = _("Password (optional, shown in plain text)"),
              text = existing and existing.password or "",
              hint = "" },
        },
        buttons = {{
            { text = _("Cancel"), id = "close",
              callback = function() UIManager:close(dialog) end },
            { text = _("Save"),
              callback = function()
                  local fields = dialog:getFields()
                  if not fields[1] or fields[1] == "" or not fields[2] or fields[2] == "" then
                      UIManager:show(InfoMessage:new{ text = _("Name and URL are required.") })
                      return
                  end
                  UIManager:close(dialog)
                  local server = ServerSettings.save{
                      id = existing and existing.id or nil,
                      name = fields[1],
                      url = fields[2],
                      username = (fields[3] ~= "" and fields[3]) or nil,
                      password = (fields[4] ~= "" and fields[4]) or nil,
                      default_category_href = existing and existing.default_category_href or nil,
                  }
                  if on_saved then on_saved(server) end
              end },
        }},
    }
    UIManager:show(dialog)
end

function Picker.add_server(on_added)
    show_form(nil, on_added)
end

function Picker.edit_server(server, on_saved)
    show_form(server, on_saved)
end

-- Show a picker for existing servers. `on_pick(server)` opens it; "Add new" triggers add_server.
function Picker.pick(on_pick, on_added)
    local servers = ServerSettings.list()
    local buttons = {}
    for _, server in ipairs(servers) do
        table.insert(buttons, {{
            text = server.name,
            align = "left",
            callback = function()
                UIManager:close(Picker._dialog)
                ServerSettings.set_last_used(server.id)
                if on_pick then on_pick(server) end
            end,
        }})
    end
    table.insert(buttons, {{
        text = _("Add server…"),
        align = "left",
        callback = function()
            UIManager:close(Picker._dialog)
            Picker.add_server(on_added or on_pick)
        end,
    }})
    Picker._dialog = ButtonDialog:new{ buttons = buttons }
    UIManager:show(Picker._dialog)
end

return Picker
