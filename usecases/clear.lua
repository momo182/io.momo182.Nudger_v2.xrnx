--[[============================================================================
usecases/clear.lua
============================================================================]]--

--[[

Use case: Clear.
Resets note properties under the cursor / selection to blank.

]]--

local Clear = require('operations/clear')

return {
  keybinding = "Global:Tools:io.momo Clear",
  menu = "Main Menu:Tools:io.momo:Clear",
  invoke = function()
    return Clear.clear()
  end
}
