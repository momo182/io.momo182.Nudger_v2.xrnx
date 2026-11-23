--[[============================================================================
renoise/input_tracker.lua

Tracks user input context (cursor vs selection) to determine operation intent.
============================================================================]]--

local Constants = require('core/constants')
local ErrorHandler = require('core/error_handler')
local ConfigManager = require('core/config_manager')

local InputTracker = {}


-- Normalize possible userdata/observable values to plain numbers
local function num(v)
  if type(v) == "number" then
    return v
  elseif type(v) == "userdata" then
    if v.value ~= nil then
      if type(v.value) == "function" then
        return v.value(v)
      else
        return v.value
      end
    end
    if getmetatable(v) and getmetatable(v).__call then
      return v()
    end
  end
  return nil
end


-- ============================================================================
-- State
-- ============================================================================

local state = {
  last_input_type = nil,      -- "CURSOR" or "SELECTION"
  last_input_time = 0,        -- os.clock() timestamp
  cursor_notifiers = {},      -- Observable notifiers
  selection_notifiers = {},   -- Observable notifiers
  initialized = false
}

-- Input types
InputTracker.INPUT_TYPE = {
  CURSOR = "CURSOR",
  SELECTION = "SELECTION",
  UNKNOWN = "UNKNOWN"
}

-- ============================================================================
-- Input Detection
-- ============================================================================

-- Called when cursor position changes
local function on_cursor_changed()
  ErrorHandler.debug("InputTracker: Cursor changed")
  state.last_input_type = InputTracker.INPUT_TYPE.CURSOR
  state.last_input_time = os.clock()
end

-- Called when selection changes
local function on_selection_changed()
  ErrorHandler.debug("InputTracker: Selection changed")
  state.last_input_type = InputTracker.INPUT_TYPE.SELECTION
  state.last_input_time = os.clock()
end

-- ============================================================================
-- Observable Management
-- ============================================================================

local last_line = nil
local last_col  = nil

local function on_cursor_idle()
  local song = renoise.song()
  local line = song.selected_line_index
  local col  = song.selected_note_column_index
  if line ~= last_line or col ~= last_col then
    last_line = line
    last_col  = col
    on_cursor_changed()
  end
end

local function add_cursor_observables(song)
  -- These ARE observable — keep as-is
  if not song.selected_track_index_observable:has_notifier(on_cursor_changed) then
    song.selected_track_index_observable:add_notifier(on_cursor_changed)
    table.insert(state.cursor_notifiers, song.selected_track_index_observable)
  end

  if not song.selected_pattern_index_observable:has_notifier(on_cursor_changed) then
    song.selected_pattern_index_observable:add_notifier(on_cursor_changed)
    table.insert(state.cursor_notifiers, song.selected_pattern_index_observable)
  end

  -- These are NOT observable — poll via idle
  if not renoise.tool().app_idle_observable:has_notifier(on_cursor_idle) then
    renoise.tool().app_idle_observable:add_notifier(on_cursor_idle)
  end
end

local last_sel = nil

local function on_selection_idle()
  local sel = renoise.song().selection_in_pattern
  -- nil means no selection
  if (sel == nil and last_sel ~= nil)
    or (sel ~= nil and last_sel == nil)
    or (sel ~= nil and last_sel ~= nil and (
      sel.start_line   ~= last_sel.start_line
      or sel.start_track ~= last_sel.start_track
      or sel.start_column ~= last_sel.start_column
      or sel.end_line   ~= last_sel.end_line
      or sel.end_track   ~= last_sel.end_track
      or sel.end_column  ~= last_sel.end_column
    ))
  then
    last_sel = sel
    on_selection_changed()
  end
end

local function add_selection_observables(song)
  if not renoise.tool().app_idle_observable:has_notifier(on_selection_idle) then
    renoise.tool().app_idle_observable:add_notifier(on_selection_idle)
  end
end   

-- Remove all observables (for cleanup)
-- Note: observables belong to a specific song document. When the document
-- is destroyed (e.g. on loading a new song), accessing them throws
-- "trying to access a nil object". pcall() safely skips dead observables.
local function remove_all_observables()
  for _, observable in ipairs(state.cursor_notifiers) do
    pcall(function()
      if observable:has_notifier(on_cursor_changed) then
        observable:remove_notifier(on_cursor_changed)
      end
    end)
  end

  for _, observable in ipairs(state.selection_notifiers) do
    pcall(function()
      if observable:has_notifier(on_selection_changed) then
        observable:remove_notifier(on_selection_changed)
      end
    end)
  end

  state.cursor_notifiers = {}
  state.selection_notifiers = {}
end

-- ============================================================================
-- Public API
-- ============================================================================

-- Initialize input tracking
function InputTracker.initialize()
  if state.initialized then
    ErrorHandler.debug("InputTracker already initialized")
    return
  end

  local song = renoise.song()
  if not song then
    ErrorHandler.warn("Cannot initialize InputTracker: No song loaded")
    return false
  end

  ErrorHandler.debug("Initializing InputTracker")

  -- Add observables
  add_cursor_observables(song)
  add_selection_observables(song)

  state.initialized = true
  state.last_input_type = InputTracker.INPUT_TYPE.UNKNOWN
  state.last_input_time = os.clock()

  ErrorHandler.info("InputTracker initialized")
  return true
end

-- Cleanup (remove observables)
function InputTracker.cleanup()
  if not state.initialized then
    return
  end

  ErrorHandler.debug("Cleaning up InputTracker")
  remove_all_observables()
  state.initialized = false
  state.last_input_type = nil
  state.last_input_time = 0
end

-- Get current input type
function InputTracker.get_input_type()
  if not state.initialized then
    return InputTracker.INPUT_TYPE.UNKNOWN
  end

  -- Check if input has timed out
  local timeout = ConfigManager.get("input_timeout_ms", 500) / 1000.0
  local elapsed = os.clock() - state.last_input_time

  if elapsed > timeout then
    ErrorHandler.debug("Input timeout exceeded, returning UNKNOWN")
    return InputTracker.INPUT_TYPE.UNKNOWN
  end

  return state.last_input_type or InputTracker.INPUT_TYPE.UNKNOWN
end

-- Determine if selection should be used for operations
function InputTracker.should_use_selection()
  -- Check config override
  local input_mode = ConfigManager.get("input_mode", "AUTO")

  if input_mode == "CURSOR_ONLY" then
    return false
  end

  if input_mode == "SELECTION_ONLY" then
    local song = renoise.song()
    return song and song.selection_in_pattern ~= nil
  end

  -- AUTO mode: use input tracking
  local song = renoise.song()
  if not song or not song.selection_in_pattern then
    return false
  end

  local input_type = InputTracker.get_input_type()

  -- If last input was selection-related, use selection
  if input_type == InputTracker.INPUT_TYPE.SELECTION then
    ErrorHandler.debug("Using SELECTION (last input was selection)")
    return true
  end

  -- If last input was cursor-related, use cursor even if selection exists
  if input_type == InputTracker.INPUT_TYPE.CURSOR then
    ErrorHandler.debug("Using CURSOR (last input was cursor)")
    return false
  end

  -- Unknown input type: default behavior
  -- If selection exists and we don't know intent, prefer selection
  ErrorHandler.debug("Unknown input type, defaulting to selection")
  return true
end

-- Get debug info
function InputTracker.get_debug_info()
  return {
    initialized = state.initialized,
    last_input_type = state.last_input_type,
    last_input_time = state.last_input_time,
    time_since_input = os.clock() - state.last_input_time,
    cursor_notifiers = #state.cursor_notifiers,
    selection_notifiers = #state.selection_notifiers
  }
end

-- Force input type (for testing/debugging)
function InputTracker.set_input_type(input_type)
  if input_type == InputTracker.INPUT_TYPE.CURSOR or
     input_type == InputTracker.INPUT_TYPE.SELECTION then
    state.last_input_type = input_type
    state.last_input_time = os.clock()
    ErrorHandler.debug("Forced input type to: " .. input_type)
    return true
  end
  return false
end

return InputTracker
