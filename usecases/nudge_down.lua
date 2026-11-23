--[[============================================================================
usecases/nudge_down.lua
============================================================================]]--

--[[

Use case: Nudge Down.
Lowers note properties under the cursor by one step.

]]--

local Nudge = require('operations/nudge')

return {
  keybinding = "Global:Tools:io.momo Nudge Down",
  menu = "Main Menu:Tools:io.momo:Nudge Down",
  invoke = function()
    return Nudge.nudge_down()
  end
}
