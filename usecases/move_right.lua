--[[============================================================================
usecases/move_right.lua
============================================================================]]--

--[[

Use case: Move Right.
Moves the note under the cursor one track to the right.
If a pattern selection exists, moves the whole selection right instead.

]]--

local Move = require('operations/move')

return {
  keybinding = "Global:Tools:io.momo Move Right",
  menu = "Main Menu:Tools:io.momo:Move Right",
  invoke = function()
    local s = renoise.song().selection_in_pattern
    if s ~= nil then return Move.move_selection_right() end
    return Move.move_right()
  end
}
