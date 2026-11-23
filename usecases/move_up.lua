--[[============================================================================
usecases/move_up.lua
============================================================================]]--

--[[

Use case: Move Up.
Moves the note under the cursor up one line.
If a pattern selection exists, moves the whole selection up instead.

]]--

local Move = require('operations/move')

return {
  keybinding = "Global:Tools:io.momo Move Up",
  menu = "Main Menu:Tools:io.momo:Move Up",
  invoke = function()
    local s = renoise.song().selection_in_pattern
    if s ~= nil then return Move.move_selection_up() end
    return Move.move_up()
  end
}
