--[[============================================================================
usecases/nudge_up.lua
============================================================================]]--

--[[

Use case: Nudge Up.
Raises note properties under the cursor by one step.

]]--

local Nudge = require('operations/nudge')

return {
  keybinding = "Global:Tools:io.momo Nudge Up",
  menu = "Main Menu:Tools:io.momo:Nudge Up",
  invoke = function()
    return Nudge.nudge_up()
  end
}
