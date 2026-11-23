--[[============================================================================
usecases.lua
============================================================================]]--

--[[

Use case registry.

Each file in this folder is one user-triggered event: it declares the
keybinding, an optional menu entry, and the invoke() that maps the event
to operation modules (operations/*).

To add a new action:
  1. Create usecases/my_action.lua with the same table shape.
  2. Add it to the list below.
main.lua needs no changes.

NOTE: keep this as a single root-level usecases.lua (not usecases/init.lua) —
Renoise's package.path has no "./?/init.lua" template for tool folders,
so folder-style modules would not resolve.

]]--

local UseCases = {}

-- Order here defines the order of menu entries in Renoise
local definitions = {
  require('usecases/clear'),
  require('usecases/nudge_down'),
  require('usecases/nudge_up'),
  require('usecases/move_up'),
  require('usecases/move_down'),
  require('usecases/move_left'),
  require('usecases/move_right'),
  require('usecases/clone_up'),
  require('usecases/clone_down'),
  require('usecases/clone_left'),
  require('usecases/clone_right'),
}

-- Temporary debug wrapper: prints to Scripting Terminal on every invoke,
-- and shows a popup for hard errors (nil returns / thrown errors).
local DEBUG_KEYS = true

local function wrap_debug(name, invoke)
  if not DEBUG_KEYS then return invoke end
  return function(...)
    print(string.format("[Nudger] key event fired: %s", name))
    local ok, a, b = pcall(invoke, ...)
    if not ok then
      renoise.app():show_error(("Nudger '%s' crashed: %s"):format(name, tostring(a)))
      print(string.format("[Nudger] ERROR in %s: %s", name, tostring(a)))
      return
    end
    print(string.format("[Nudger] %s -> %s %s", name, tostring(a), tostring(b)))
    return a, b
  end
end

-- Register all keybindings and menu entries with Renoise
function UseCases.register_all()
  local tool = renoise.tool()

  for _, usecase in ipairs(definitions) do
    local invoke = wrap_debug(usecase.keybinding, usecase.invoke)

    tool:add_keybinding{
      name = usecase.keybinding,
      invoke = invoke
    }

    if usecase.menu then
      tool:add_menu_entry{
        name = usecase.menu,
        invoke = invoke
      }
    end
  end
end

-- Expose definitions for ad-hoc invocation (console, tests, future OSC routing)
UseCases.all = definitions

return UseCases
