--[[============================================================================
usecases/clone_right.lua
============================================================================]]--

--[[

Use case: Clone Right.
Duplicates the note under the cursor one track to the right.

]]--

local Clone = require('operations/clone')

return {
  keybinding = "Global:Tools:io.momo Clone Right",
  menu = "Main Menu:Tools:io.momo:Clone Right",
  invoke = function()
    return Clone.clone_right()
  end
}
