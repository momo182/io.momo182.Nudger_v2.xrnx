--[[============================================================================
usecases/move_down.lua
============================================================================]]--

--[[

Use case: Move Down.
Moves the note under the cursor down one line.
If a pattern selection exists, moves the whole selection down instead.

]]--

local Move = require('operations/move')

return {
  keybinding = "Global:Tools:io.momo Move Down",
  menu = "Main Menu:Tools:io.momo:Move Down",
  invoke = function()
    local s = renoise.song().selection_in_pattern
    if s ~= nil then return Move.move_selection_down() end
    return Move.move_down()
  end
}
