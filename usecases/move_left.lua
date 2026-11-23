--[[============================================================================
usecases/move_left.lua
============================================================================]]--

--[[

Use case: Move Left.
Moves the note under the cursor one track to the left.
If a pattern selection exists, moves the whole selection left instead.

]]--

local Move = require('operations/move')

return {
  keybinding = "Global:Tools:io.momo Move Left",
  menu = "Main Menu:Tools:io.momo:Move Left",
  invoke = function()
    local s = renoise.song().selection_in_pattern
    if s ~= nil then return Move.move_selection_left() end
    return Move.move_left()
  end
}
