--[[============================================================================
usecases/clone_left.lua
============================================================================]]--

--[[

Use case: Clone Left.
Duplicates the note under the cursor one track to the left.

]]--

local Clone = require('operations/clone')

return {
  keybinding = "Global:Tools:io.momo Clone Left",
  menu = "Main Menu:Tools:io.momo:Clone Left",
  invoke = function()
    return Clone.clone_left()
  end
}
