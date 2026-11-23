--[[============================================================================
usecases/clone_down.lua
============================================================================]]--

--[[

Use case: Clone Down.
Duplicates the note under the cursor one line down.

]]--

local Clone = require('operations/clone')

return {
  keybinding = "Global:Tools:io.momo Clone Down",
  menu = "Main Menu:Tools:io.momo:Clone Down",
  invoke = function()
    return Clone.clone_down()
  end
}
