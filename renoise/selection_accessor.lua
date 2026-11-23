--[[============================================================================
renoise/selection_accessor.lua
============================================================================]]--

--[[

Selection accessor for Nudger tool.
Provides access to multi-note selections and operations.

]]--

local Constants = require('core/constants')
local Validator = require('core/validator')
local ErrorHandler = require('core/error_handler')
local ConfigManager = require('core/config_manager')


-- Clamp selection column bounds to each track's visible_note_columns.
-- Renoise's selection_in_pattern.end_column can exceed visible_note_columns,
-- but selected_note_column_index and per-line note_column() are validated
-- against the visible count. Clamp so downstream loops and assignments
-- stay in range.
local function clamp_selection_columns(selection)
  if not selection then
    return selection
  end

  local song = renoise.song()

  -- Find the smallest visible column count across the tracks in the selection.
  -- For a single-track selection this is just that track's visible count.
  local min_visible = math.huge
  for track_idx = selection.start_track, selection.end_track do
    local song_track = song.tracks[track_idx]
    local vc = song_track and song_track.visible_note_columns or 1
    if vc < min_visible then
      min_visible = vc
    end
  end

  if min_visible == math.huge then
    min_visible = 1
  end

  if selection.end_column > min_visible then
    selection.end_column = min_visible
  end
  if selection.start_column > selection.end_column then
    selection.start_column = selection.end_column
  end
  if selection.start_column < 1 then
    selection.start_column = 1
  end

  return selection
end

local SelectionAccessor = {}

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

function visible_cols_for(track_idx)
  local song = renoise.song()
  local song_track = song.tracks[track_idx]
  return song_track and song_track.visible_note_columns or 1
end

-- ============================================================================
-- Selection Information
-- ============================================================================

-- Get current selection bounds
-- @return selection table or nil, error
function SelectionAccessor.get_bounds()
  local success, err = Validator.validate_selection_in_pattern()
  if not success then
    return nil, err
  end

  local song = renoise.song()
  local selection = song.selection_in_pattern

  local result = {
    start_line = selection.start_line,
    end_line = selection.end_line,
    start_track = selection.start_track,
    end_track = selection.end_track,
    start_column = selection.start_column,
    end_column = selection.end_column
  }
  return result, nil
end

-- Get selection size (number of lines)
-- @return line_count or 0
function SelectionAccessor.get_line_count()
  local selection, err = SelectionAccessor.get_bounds()
  if not selection then
    return 0
  end

  return (selection.end_line - selection.start_line + 1)
end

-- Get selection track count
-- @return track_count or 0
function SelectionAccessor.get_track_count()
  local selection, err = SelectionAccessor.get_bounds()
  if not selection then
    return 0
  end

  return (selection.end_track - selection.start_track + 1)
end

-- Get selection column count (within a track)
-- @return column_count or 0
function SelectionAccessor.get_column_count()
  local selection, err = SelectionAccessor.get_bounds()
  if not selection then
    return 0
  end

  return (selection.end_column - selection.start_column + 1)
end

-- Get total number of notes in selection (approximate)
-- @return note_count
function SelectionAccessor.get_note_count()
  local line_count = SelectionAccessor.get_line_count()
  local track_count = SelectionAccessor.get_track_count()
  local col_count = SelectionAccessor.get_column_count()

  -- Approximate: lines * tracks * columns
  return line_count * track_count * col_count
end

-- ============================================================================
-- Selection Movement
-- ============================================================================

-- Check if selection can move in direction
-- @param direction: "up", "down", "left", "right"
-- @return boolean, error_message
function SelectionAccessor.can_move(direction)
  local selection, err = SelectionAccessor.get_bounds()
  if not selection then
    return false, err
  end

  local Context = require('renoise/context')
  local context, err = Context.get_pattern_context()
  if not context then
    return false, err
  end

  local PatternAccessor = require('renoise/pattern_accessor')
  local line_count = PatternAccessor.get_line_count(context)
  local track_count = PatternAccessor.get_track_count(context)

  if direction == Constants.DIRECTION.UP then
    return selection.start_line > 1, "Already at first line"
  elseif direction == Constants.DIRECTION.DOWN then
    return selection.end_line < line_count, "Already at last line"
  elseif direction == Constants.DIRECTION.LEFT then
    return selection.start_column > 1, "Already at leftmost column"
  elseif direction == Constants.DIRECTION.RIGHT then
    -- Need to check against actual column count
    local song = renoise.song()
    local pattern = song.patterns[context.pattern]
    local track = pattern.tracks[context.track]
    local line = track.lines[context.line]
    local col_count = #line.note_columns
    return selection.end_column < col_count, "Already at rightmost column"
  else
    return false, "Invalid direction"
  end
end

-- Move selection in direction
-- @param direction: "up", "down", "left", "right"
-- @return success, error_message
function SelectionAccessor.move(direction)
  local can_move, err = SelectionAccessor.can_move(direction)
  if not can_move then
    ErrorHandler.info(err)
    return false, err
  end

  local selection, err = SelectionAccessor.get_bounds()
  if not selection then
    return false, err
  end

  -- Calculate new selection bounds
  local new_selection = {
    start_line = selection.start_line,
    end_line = selection.end_line,
    start_track = selection.start_track,
    end_track = selection.end_track,
    start_column = selection.start_column,
    end_column = selection.end_column
  }

  if direction == Constants.DIRECTION.UP then
    new_selection.start_line = selection.start_line - 1
    new_selection.end_line = selection.end_line - 1
  elseif direction == Constants.DIRECTION.DOWN then
    new_selection.start_line = selection.start_line + 1
    new_selection.end_line = selection.end_line + 1
  elseif direction == Constants.DIRECTION.LEFT then
    new_selection.start_column = selection.start_column - 1
    new_selection.end_column = selection.end_column - 1
  elseif direction == Constants.DIRECTION.RIGHT then
    new_selection.start_column = selection.start_column + 1
    new_selection.end_column = selection.end_column + 1
  else
    return false, "Invalid direction"
  end

  -- Apply new selection
  local song = renoise.song()
  song.selection_in_pattern = new_selection

  return true, nil
end

-- ============================================================================
-- Selection Iteration
-- ============================================================================

-- Iterate over all note columns in selection
-- @param callback: function(note_column, line_index, track_index, column_index)
-- @return success, error_message
function SelectionAccessor.iterate_note_columns(callback)
  local success, err = Validator.validate_function(callback, "callback")
  if not success then
    return false, err
  end

  local selection, err = SelectionAccessor.get_bounds()
  if not selection then
    return false, err
  end

  local Context = require('renoise/context')
  local context, err = Context.get_pattern_context()
  if not context then
    return false, err
  end

  local song = renoise.song()
  local pattern = song.patterns[context.pattern]

  -- Iterate over selection bounds
  for track_idx = selection.start_track, selection.end_track do
    local track = pattern.tracks[track_idx]

    for line_idx = selection.start_line, selection.end_line do
      local line = track.lines[line_idx]

      -- Determine column range for this track
      local start_col = (track_idx == selection.start_track) and selection.start_column or 1
      local end_col = (track_idx == selection.end_track) and selection.end_column or #line.note_columns

      for col_idx = start_col, math.min(end_col, #line.note_columns) do
        local note_column = line:note_column(col_idx)
        callback(note_column, line_idx, track_idx, col_idx)
      end
    end
  end

  return true, nil
end

-- Count non-blank notes in selection
-- @return note_count
function SelectionAccessor.count_non_blank_notes()
  local count = 0

  SelectionAccessor.iterate_note_columns(function(note_column)
    if note_column.note_value ~= Constants.NOTE.BLANK then
      count = count + 1
    end
  end)

  return count
end

-- ============================================================================
-- Helper Functions for Note Movement
-- ============================================================================

-- Calculate destination bounds for selection movement
-- @param selection: current selection bounds
-- @param direction: "up", "down", "left", "right"
-- @return new_bounds or nil, error
local function calculate_dest_bounds(selection, direction)
  if not selection then
    return nil, "No selection provided"
  end

  local new_bounds = {
    start_line = selection.start_line,
    end_line = selection.end_line,
    start_track = selection.start_track,
    end_track = selection.end_track,
    start_column = selection.start_column,
    end_column = selection.end_column
  }

  if direction == Constants.DIRECTION.UP then
    new_bounds.start_line = selection.start_line - 1
    new_bounds.end_line = selection.end_line - 1
  elseif direction == Constants.DIRECTION.DOWN then
    new_bounds.start_line = selection.start_line + 1
    new_bounds.end_line = selection.end_line + 1
  elseif direction == Constants.DIRECTION.LEFT then
    new_bounds.start_column = selection.start_column - 1
    new_bounds.end_column = selection.end_column - 1
  elseif direction == Constants.DIRECTION.RIGHT then
    new_bounds.start_column = selection.start_column + 1
    new_bounds.end_column = selection.end_column + 1
  else
    return nil, "Invalid direction: " .. tostring(direction)
  end

  return new_bounds, nil
end

local function is_within_bounds(bounds, context)
  if not bounds or not context then
    return false, "Invalid bounds or context"
  end

  local PatternAccessor = require('renoise/pattern_accessor')
  local line_count = PatternAccessor.get_line_count(context)
  local track_count = PatternAccessor.get_track_count(context)

  print(string.format(
    ">>> is_within_bounds: bounds L[%d-%d] T[%d-%d] C[%d-%d] | pattern lines=%s tracks=%s",
    bounds.start_line, bounds.end_line,
    bounds.start_track, bounds.end_track,
    bounds.start_column, bounds.end_column,
    tostring(line_count), tostring(track_count)))

  if bounds.start_line < 1 then
    return false, "Cannot move selection above first line"
  end
  if bounds.end_line > line_count then
    return false, string.format(
      "Cannot move selection below last line (end_line=%d > line_count=%s)",
      bounds.end_line, tostring(line_count))
  end

  if bounds.start_track < 1 or bounds.end_track > track_count then
    return false, string.format(
      "Selection would move outside pattern bounds (tracks) start_track=%d end_track=%d track_count=%s",
      bounds.start_track, bounds.end_track, tostring(track_count))
  end

  if bounds.start_column < 1 or bounds.end_column < 1 then
    return false, string.format(
      "Selection would move outside column bounds start_col=%d end_col=%d",
      bounds.start_column, bounds.end_column)
  end

  local song = renoise.song()
  local pattern = song.patterns[context.pattern]

  for track_idx = bounds.start_track, bounds.end_track do
    local song_track = song.tracks[track_idx]
    local max_cols = song_track and song_track.visible_note_columns or 1

    local start_col = (track_idx == bounds.start_track) and bounds.start_column or 1
    local end_col = (track_idx == bounds.end_track) and bounds.end_column or max_cols

    print(string.format(
      ">>>   track %d: max_cols=%s start_col=%d end_col=%d",
      track_idx, tostring(max_cols), start_col, end_col))

    if end_col > max_cols then
      return false, string.format(
        "Selection would move outside visible columns (track=%d end_col=%d > max_cols=%s)",
        track_idx, end_col, tostring(max_cols))
    end
  end

  return true, nil
end

-- Copy note column data from source to destination
-- @param src_note: source note column
-- @param dst_note: destination note column
local function copy_note_column(src_note, dst_note)
  dst_note.note_value = src_note.note_value
  dst_note.instrument_value = src_note.instrument_value
  dst_note.volume_value = src_note.volume_value
  dst_note.panning_value = src_note.panning_value
  dst_note.delay_value = src_note.delay_value
  dst_note.effect_number_value = src_note.effect_number_value
  dst_note.effect_amount_value = src_note.effect_amount_value
end

local function clear_note_column(note)
  note:clear()
end

-- ============================================================================
-- Selection Note Movement Operations
-- ============================================================================

-- Move selection notes in direction
-- @param direction: "up", "down", "left", "right"
-- @return success, error_message
function SelectionAccessor.move_notes(direction)
  local r = renoise.app()
        
  ErrorHandler.trace_enter("SelectionAccessor.move_notes", direction)

  -- Get current selection
  local selection, err = SelectionAccessor.get_bounds()
  if not selection then
    ErrorHandler.warn("No selection: " .. tostring(err))
    return false, err
  end

  selection = clamp_selection_columns(selection)

  -- Get context
  local Context = require('renoise/context')
  local context, err = Context.get_pattern_context()
  if not context then
    ErrorHandler.warn("No context: " .. tostring(err))
    return false, err
  end

  -- Calculate destination bounds
  local dest_bounds, err = calculate_dest_bounds(selection, direction)
  if not dest_bounds then
    ErrorHandler.warn("Cannot calculate destination: " .. tostring(err))
    return false, err
  end
    
  -- Validate destination bounds
  local valid, err = is_within_bounds(dest_bounds, context)
  if not valid then
    ErrorHandler.info(err)
    return false, err
  end
  
  local song = renoise.song()
  local pattern = song.patterns[context.pattern]

  -- Collect all note data from source selection
  local note_data = {}
  for track_idx = selection.start_track, selection.end_track do
    note_data[track_idx] = {}
    local track = pattern.tracks[track_idx]

    for line_idx = selection.start_line, selection.end_line do
      note_data[track_idx][line_idx] = {}
      local line = track.lines[line_idx]

      local start_col = (track_idx == selection.start_track) and selection.start_column or 1
      local end_col = (track_idx == selection.end_track) and selection.end_column or visible_cols_for(track_idx)

      for col_idx = start_col, math.min(end_col, visible_cols_for(track_idx)) do
        local note = line:note_column(col_idx)
        note_data[track_idx][line_idx][col_idx] = {
          note_value = note.note_value,
          instrument_value = note.instrument_value,
          volume_value = note.volume_value,
          panning_value = note.panning_value,
          delay_value = note.delay_value,
          effect_number_value = note.effect_number_value,
          effect_amount_value = note.effect_amount_value
        }
      end
    end
  end

  -- Perform the move with undo grouping
  SelectionAccessor.with_undo_grouping("Move Selection " .. direction, function()
    -- Clear source notes
    for track_idx = selection.start_track, selection.end_track do
      local track = pattern.tracks[track_idx]

      for line_idx = selection.start_line, selection.end_line do
        local line = track.lines[line_idx]

        local start_col = (track_idx == selection.start_track) and selection.start_column or 1
        local end_col = (track_idx == selection.end_track) and selection.end_column or visible_cols_for(track_idx)

        for col_idx = start_col, math.min(end_col, visible_cols_for(track_idx)) do
          clear_note_column(line:note_column(col_idx))
        end
      end
    end

    -- Copy to destination
    local line_offset = dest_bounds.start_line - selection.start_line
    local col_offset = dest_bounds.start_column - selection.start_column

    for track_idx = selection.start_track, selection.end_track do
      local track = pattern.tracks[track_idx]

      for line_idx = selection.start_line, selection.end_line do
        local dest_line_idx = line_idx + line_offset
        local dest_line = track.lines[dest_line_idx]

        local start_col = (track_idx == selection.start_track) and selection.start_column or 1
        local max_cols = visible_cols_for(track_idx)
        local end_col = (track_idx == selection.end_track) and selection.end_column or max_cols

        for col_idx = start_col, math.min(end_col, max_cols) do
          if note_data[track_idx] and note_data[track_idx][line_idx] and note_data[track_idx][line_idx][col_idx] then
            local dest_col_idx = col_idx + col_offset
            local src_data = note_data[track_idx][line_idx][col_idx]
            local dest_note = dest_line:note_column(dest_col_idx)

            dest_note.note_value = src_data.note_value
            dest_note.instrument_value = src_data.instrument_value
            dest_note.volume_value = src_data.volume_value
            dest_note.panning_value = src_data.panning_value
            dest_note.delay_value = src_data.delay_value
            dest_note.effect_number_value = src_data.effect_number_value
            dest_note.effect_amount_value = src_data.effect_amount_value
          end
        end
      end
    end

    -- Update selection bounds
    song.selection_in_pattern = dest_bounds
  end)

  ErrorHandler.trace_exit("SelectionAccessor.move_notes", true)
  return true, nil
end

-- Clone selection notes in direction
-- @param direction: "up", "down", "left", "right"
-- @return success, error_message
function SelectionAccessor.clone_notes(direction)
  ErrorHandler.trace_enter("SelectionAccessor.clone_notes", direction)

  -- Get current selection
  local selection, err = SelectionAccessor.get_bounds()
  if not selection then
    ErrorHandler.warn("No selection: " .. tostring(err))
    return false, err
  end

  -- Get context
  local Context = require('renoise/context')
  local context, err = Context.get_pattern_context()
  if not context then
    ErrorHandler.warn("No context: " .. tostring(err))
    return false, err
  end

  -- Calculate destination bounds
  local dest_bounds, err = calculate_dest_bounds(selection, direction)
  if not dest_bounds then
    ErrorHandler.warn("Cannot calculate destination: " .. tostring(err))
    return false, err
  end

  -- Validate destination bounds
  local valid, err = is_within_bounds(dest_bounds, context)
  if not valid then
    ErrorHandler.info(err)
    return false, err
  end

  local song = renoise.song()
  local pattern = song.patterns[context.pattern]

  -- local function visible_cols_for(track_idx)
  --   local song_track = song.tracks[track_idx]
  --   return song_track and song_track.visible_note_columns or 1
  -- end

  -- Collect all note data from source selection (same as move)
  local note_data = {}

  for track_idx = selection.start_track, selection.end_track do
    note_data[track_idx] = {}
    local track = pattern.tracks[track_idx]

    for line_idx = selection.start_line, selection.end_line do
      note_data[track_idx][line_idx] = {}
      local line = track.lines[line_idx]

      local start_col = (track_idx == selection.start_track) and selection.start_column or 1
      local max_cols = visible_cols_for(track_idx)
      local end_col = (track_idx == selection.end_track) and selection.end_column or max_cols

      for col_idx = start_col, math.min(end_col, max_cols) do
        local note = line:note_column(col_idx)
        note_data[track_idx][line_idx][col_idx] = {
          note_value = note.note_value,
          instrument_value = note.instrument_value,
          volume_value = note.volume_value,
          panning_value = note.panning_value,
          delay_value = note.delay_value,
          effect_number_value = note.effect_number_value,
          effect_amount_value = note.effect_amount_value
        }
      end
    end
  end

  -- Perform the clone with undo grouping (NO clearing of source)
  SelectionAccessor.with_undo_grouping("Clone Selection " .. direction, function()
    -- Copy to destination (without clearing source)
    local line_offset = dest_bounds.start_line - selection.start_line
    local col_offset = dest_bounds.start_column - selection.start_column

    for track_idx = selection.start_track, selection.end_track do
      local track = pattern.tracks[track_idx]

      for line_idx = selection.start_line, selection.end_line do
        local dest_line_idx = line_idx + line_offset
        local dest_line = track.lines[dest_line_idx]

        local start_col = (track_idx == selection.start_track) and selection.start_column or 1
        local max_cols = visible_cols_for(track_idx)
        local end_col = (track_idx == selection.end_track) and selection.end_column or max_cols

        for col_idx = start_col, math.min(end_col, max_cols) do
          if note_data[track_idx] and note_data[track_idx][line_idx] and note_data[track_idx][line_idx][col_idx] then
            local dest_col_idx = col_idx + col_offset
            local src_data = note_data[track_idx][line_idx][col_idx]
            local dest_note = dest_line:note_column(dest_col_idx)

            dest_note.note_value = src_data.note_value
            dest_note.instrument_value = src_data.instrument_value
            dest_note.volume_value = src_data.volume_value
            dest_note.panning_value = src_data.panning_value
            dest_note.delay_value = src_data.delay_value
            dest_note.effect_number_value = src_data.effect_number_value
            dest_note.effect_amount_value = src_data.effect_amount_value
          end
        end
      end
    end

    -- Update selection bounds to cloned area
    song.selection_in_pattern = dest_bounds
  end)

  ErrorHandler.trace_exit("SelectionAccessor.clone_notes", true)
  return true, nil
end

-- ============================================================================
-- Selection Operations with Undo Grouping
-- ============================================================================

-- Execute operation on selection with undo grouping (Renoise 3.5+)
-- @param operation_name: Name for undo history
-- @param operation_fn: Function to execute
-- @return success, error_message
function SelectionAccessor.with_undo_grouping(operation_name, operation_fn)
  local success, err = Validator.validate_function(operation_fn, "operation_fn")
  if not success then
    return false, err
  end

  local song = renoise.song()

  -- Check if undo grouping is available and enabled
  if ConfigManager.use_undo_grouping() and song.describe_batch_undo then
    -- Use Renoise 3.5+ undo grouping.
    -- describe_batch_undo only takes (name [, timeout]). It does NOT take a
    -- callback. You must start the batch, run your operations, then let it
    -- finalize (either via timeout or by a subsequent non-batch action).
    song:describe_batch_undo(operation_name)
    operation_fn()
  else
    -- Fall back to direct execution (multiple undo steps)
    operation_fn()
  end

  return true, nil
end

return SelectionAccessor
