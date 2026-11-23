--[[============================================================================
operations/nudge.lua
============================================================================]]--

--[[

Unified nudge operations for Nudger tool.
Consolidates nudgeUp/nudgeDown into single parameterized implementation.

]]--

local Constants = require('core/constants')
local Validator = require('core/validator')
local ErrorHandler = require('core/error_handler')
local ConfigManager = require('core/config_manager')
local Context = require('renoise/context')
local PatternAccessor = require('renoise/pattern_accessor')
local PhraseAccessor = require('renoise/phrase_accessor')
local SelectionAccessor = require('renoise/selection_accessor')
local InputTracker = require('renoise/input_tracker')

local Nudge = {}

-- ============================================================================
-- Property Definitions
-- ============================================================================

-- Define nudge behavior for each property type
local PROPERTY_SPECS = {
  [renoise.Song.SUB_COLUMN_NOTE] = {
    name = "note_value",
    field = "note_value",
    min = Constants.NOTE.MIN,
    max = Constants.NOTE.MAX,
    blank = Constants.NOTE.BLANK,
    wrap = true,  -- Can be overridden by config
    default = Constants.NOTE.DEFAULT
  },

  [renoise.Song.SUB_COLUMN_INSTRUMENT] = {
    name = "instrument_value",
    field = "instrument_value",
    min = Constants.INSTRUMENT.MIN,
    max = Constants.INSTRUMENT.MAX,
    blank = Constants.INSTRUMENT.BLANK,
    wrap = true,
    default = 0
  },

  [renoise.Song.SUB_COLUMN_VOLUME] = {
    name = "volume_value",
    field = "volume_value",
    min = Constants.VOLUME.MIN,
    max = Constants.VOLUME.MAX,
    blank = Constants.VOLUME.BLANK,
    wrap = false,
    default = 64,
    is_effect_value = true
  },

  [renoise.Song.SUB_COLUMN_PANNING] = {
    name = "panning_value",
    field = "panning_value",
    min = Constants.PANNING.MIN,
    max = Constants.PANNING.MAX,
    blank = Constants.PANNING.BLANK,
    wrap = false,
    default = 64,
    is_effect_value = true
  },

  [renoise.Song.SUB_COLUMN_DELAY] = {
    name = "delay_value",
    field = "delay_value",
    min = Constants.DELAY.MIN,
    max = Constants.DELAY.MAX,
    blank = nil,  -- No blank value for delay
    wrap = true,
    default = 0
  },

  [renoise.Song.SUB_COLUMN_SAMPLE_EFFECT_NUMBER] = {
    name = "effect_number_value",
    field = "effect_number_value",
    is_effect_command = true
  },

  [renoise.Song.SUB_COLUMN_SAMPLE_EFFECT_AMOUNT] = {
    name = "effect_amount_value",
    field = "effect_amount_value",
    min = Constants.EFFECT.AMOUNT_MIN,
    max = Constants.EFFECT.AMOUNT_MAX,
    blank = nil,
    wrap = true,
    default = 0
  },

  -- Track effect columns
  [renoise.Song.SUB_COLUMN_EFFECT_NUMBER] = {
    name = "number_value",
    field = "number_value",
    min = Constants.EFFECT.NUMBER_MIN,
    max = Constants.EFFECT.NUMBER_MAX,
    blank = nil,
    wrap = true,
    default = 0
  },

  [renoise.Song.SUB_COLUMN_EFFECT_AMOUNT] = {
    name = "amount_value",
    field = "amount_value",
    min = Constants.EFFECT.AMOUNT_MIN,
    max = Constants.EFFECT.AMOUNT_MAX,
    blank = nil,
    wrap = true,
    default = 0
  }
}

-- ============================================================================
-- Nudge Calculation
-- ============================================================================

-- Calculate new value after nudge
-- @param current_value: Current property value
-- @param direction: Constants.DIRECTION.UP or DOWN
-- @param spec: Property specification
-- @return new_value
local function calculate_nudged_value(current_value, direction, spec)
  -- Handle effect commands (special case)
  if spec.is_effect_command then
    if direction == Constants.DIRECTION.UP then
      return Constants.get_next_effect_number(current_value)
    else
      return Constants.get_prev_effect_number(current_value)
    end
  end

  -- Handle volume/panning effect commands
  if spec.is_effect_value and current_value >= Constants.VOLUME.EFFECT_START and current_value < spec.blank then
    -- This is an effect command value, nudge differently
    local effect_char = string.char(current_value)
    -- For now, just cycle through effect commands
    -- TODO: Implement proper effect value nudging
    return current_value
  end

  -- Calculate delta
  local delta = (direction == Constants.DIRECTION.UP) and 1 or -1
  local new_value = current_value + delta

  -- Check for blank value
  if spec.blank then
    -- Handle blank transitions
    if current_value == spec.blank then
      -- Nudging from blank
      if ConfigManager.get("nudge_blank_to_default", true) then
        return spec.default or spec.min
      else
        return spec.blank
      end
    end

    -- Check if we would wrap to blank
    if new_value > spec.max then
      local wrap = ConfigManager.wrap_enabled(spec.name)
      return wrap and spec.min or spec.max
    elseif new_value < spec.min then
      local wrap = ConfigManager.wrap_enabled(spec.name)
      return wrap and spec.max or spec.min
    end
  else
    -- No blank value, just wrap/clamp
    if new_value > spec.max then
      local wrap = ConfigManager.wrap_enabled(spec.name)
      return wrap and spec.min or spec.max
    elseif new_value < spec.min then
      local wrap = ConfigManager.wrap_enabled(spec.name)
      return wrap and spec.max or spec.min
    end
  end

  return new_value
end

-- ============================================================================
-- Nudge Operations
-- ============================================================================

-- Nudge a property across all matching cells in the pattern selection
-- The nudged property is determined by the cursor's current sub-column
-- (note, instrument, volume, panning, delay, effect...).
-- @param direction: Constants.DIRECTION.UP or DOWN
-- @return success, error_message
function Nudge.nudge_selection(direction)
  ErrorHandler.trace_enter("Nudge.nudge_selection", { direction = direction })

  local success, err = Validator.validate_direction(direction)
  if not success then
    return false, err
  end

  local context, err = Context.get_current()
  if not context then
    ErrorHandler.warn(err)
    return false, err
  end

  local spec = PROPERTY_SPECS[context.sub_column_type]
  if not spec then
    local msg = string.format("No nudge spec for sub-column type: %s", tostring(context.sub_column_type))
    ErrorHandler.warn(msg)
    return false, msg
  end

  local selection, err = SelectionAccessor.get_bounds()
  if not selection then
    ErrorHandler.warn(err)
    return false, err
  end

  -- Track-effect properties live in effect columns; everything else in note columns
  local is_effect_property = (spec.field == "number_value" or spec.field == "amount_value")

  -- Sample-FX properties only make sense on notes that carry an FX command
  local is_sample_effect_property = (spec.field == "effect_number_value" or spec.field == "effect_amount_value")

  local song = renoise.song()
  local pattern = song.patterns[context.pattern]
  local count = 0

  SelectionAccessor.with_undo_grouping("Nudge Selection " .. tostring(direction), function()
    for track_idx = selection.start_track, selection.end_track do
      local pattern_track = pattern.tracks[track_idx]
      if pattern_track then
        local visible_note_cols = song.tracks[track_idx].visible_note_columns

        for line_idx = selection.start_line, selection.end_line do
          local line = pattern_track.lines[line_idx]
          if line then
            -- Logical selection columns: note columns first, then effect columns
            local first_col = (track_idx == selection.start_track) and selection.start_column or 1
            local last_col = (track_idx == selection.end_track) and selection.end_column
              or (visible_note_cols + #line.effect_columns)
            last_col = math.min(last_col, visible_note_cols + #line.effect_columns)

            for col_idx = first_col, last_col do
              if is_effect_property then
                local effect_idx = col_idx - visible_note_cols
                if effect_idx >= 1 then
                  local effect_col = line:effect_column(effect_idx)
                  -- Skip empty effect cells (no command set)
                  if effect_col.number_value ~= 0 then
                    effect_col[spec.field] = calculate_nudged_value(effect_col[spec.field], direction, spec)
                    count = count + 1
                  end
                end
              else
                if col_idx <= visible_note_cols then
                  local note_col = line:note_column(col_idx)
                  -- Skip empty cells: only nudge columns that actually hold data
                  if note_col.note_value ~= Constants.NOTE.BLANK
                    and (spec.blank == nil or note_col[spec.field] ~= spec.blank)
                    and (not is_sample_effect_property or note_col.effect_number_value ~= 0)
                  then
                    note_col[spec.field] = calculate_nudged_value(note_col[spec.field], direction, spec)
                    count = count + 1
                  end
                end
              end
            end
          end
        end
      end
    end
  end)

  ErrorHandler.debug(string.format("Nudged %d cells in selection (%s)", count, spec.name))
  ErrorHandler.trace_exit("Nudge.nudge_selection", true)
  return true, nil
end

-- Nudge current property in given direction
-- @param direction: Constants.DIRECTION.UP or DOWN
-- @return success, error_message
function Nudge.nudge(direction)
  ErrorHandler.trace_enter("Nudge.nudge", { direction = direction })

  -- Validate direction
  local success, err = Validator.validate_direction(direction)
  if not success then
    ErrorHandler.warn(err)
    return false, err
  end

  -- Get context
  local context, err = Context.get_current()
  if not context then
    ErrorHandler.warn(err)
    return false, err
  end

  -- Get property spec for current sub-column
  local spec = PROPERTY_SPECS[context.sub_column_type]
  if not spec then
    local msg = string.format("No nudge spec for sub-column type: %s", tostring(context.sub_column_type))
    ErrorHandler.warn(msg)
    return false, msg
  end

  -- If a pattern selection is active, nudge the whole selection instead
  -- of just the cell under the cursor
  if context.editor_type == Constants.EDITOR_CONTEXT.PATTERN
    and InputTracker.should_use_selection()
  then
    return Nudge.nudge_selection(direction)
  end

  -- Get current note or effect column
  local column, err
  if context.has_note_column then
    if context.editor_type == Constants.EDITOR_CONTEXT.PHRASE then
      column, err = PhraseAccessor.get_current_note_column()
    else
      column, err = PatternAccessor.get_current_note_column()
    end
  elseif context.has_effect_column then
    if context.editor_type == Constants.EDITOR_CONTEXT.PHRASE then
      column, err = PhraseAccessor.get_current_effect_column()
    else
      column, err = PatternAccessor.get_current_effect_column()
    end
  else
    return false, "No column selected"
  end

  if not column then
    ErrorHandler.warn(err)
    return false, err
  end

  -- Get current value
  local current_value = column[spec.field]

  -- Calculate new value
  local new_value = calculate_nudged_value(current_value, direction, spec)

  -- Apply new value
  column[spec.field] = new_value

  -- Log change
  ErrorHandler.debug(string.format("Nudged %s from %s to %s", spec.name, current_value, new_value))

-- Auto-advance if configured
  if ConfigManager.get("auto_advance_after_nudge", false) then
    -- Move to next line
    local song = renoise.song()
    if context.editor_type == Constants.EDITOR_CONTEXT.PHRASE then
      local current_line = song.selected_phrase_line_index
      local total_lines = context.phrase.number_of_lines
      if current_line < total_lines then
        song.selected_phrase_line_index = current_line + 1
      end
    else
      local current_line = song.selected_line_index
      local line_count = PatternAccessor.get_line_count(context)
      if current_line < line_count then
        song.selected_line_index = current_line + 1
      end
    end
  end

  ErrorHandler.trace_exit("Nudge.nudge", true)
  return true, nil
end

-- Convenience functions for up/down
function Nudge.nudge_up()
  return Nudge.nudge(Constants.DIRECTION.UP)
end

function Nudge.nudge_down()
  return Nudge.nudge(Constants.DIRECTION.DOWN)
end

return Nudge
