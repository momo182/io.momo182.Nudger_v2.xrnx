--[[============================================================================
usecases/clone_up.lua
============================================================================]]--

--[[

Use case: Clone Up.
Duplicates the note under the cursor one line up.

]]--

local Clone = require('operations/clone')

return {
  keybinding = "Global:Tools:io.momo Clone Up",
  menu = "Main Menu:Tools:io.momo:Clone Up",
  invoke = function()
    return Clone.clone_up()
  end
}
