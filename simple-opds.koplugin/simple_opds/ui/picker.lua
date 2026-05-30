local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ServerSettings = require("simple_opds/settings")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Picker = {}

-- Show the "Add server" dialog. Calls `on_added(server)` with a stored server.
function Picker.add_server(on_added)
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Add OPDS server"),
        fields = {
            { description = _("Name"), text = "", hint = _("e.g. Standard Ebooks") },
            { description = _("Catalog URL"), text = "", hint = _("https://…/opds") },
            { description = _("Username (optional)"), text = "", hint = "" },
            { description = _("Password (optional)"), text = "", hint = "", text_type = "password" },
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
                      name = fields[1],
                      url = fields[2],
                      username = (fields[3] ~= "" and fields[3]) or nil,
                      password = (fields[4] ~= "" and fields[4]) or nil,
                  }
                  if on_added then on_added(server) end
              end },
        }},
    }
    UIManager:show(dialog)
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
