--[[============================================================================
renoise/phrase_accessor.lua
============================================================================]]--

--[[

Phrase editor accessor for Nudger tool (Renoise 3.5+).
Provides validated access to phrase editor elements.

]]--

local Constants = require('core/constants')
local Validator = require('core/validator')
local ErrorHandler = require('core/error_handler')

local PhraseAccessor = {}

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
-- Note Column Access
-- ============================================================================

-- Get note column at specified position in phrase
-- @param context: Context table with phrase, line, note_col
-- @return note_column or nil, error
function PhraseAccessor.get_note_column(context)
  local success, err = Validator.validate_phrase_selected()
  if not success then
    return nil, err
  end

  local phrase = context.phrase

  -- Normalize possible userdata/observable values to plain numbers
  local function num(v)
    if type(v) == "number" then
      return v
    elseif type(v) == "userdata" then
      -- Renoise API observables expose :value()
      if v.value ~= nil then
        if type(v.value) == "function" then
          return v.value(v)
        else
          return v.value
        end
      end
      -- Fallback: try calling it
      if type(v) == "userdata" and getmetatable(v) and getmetatable(v).__call then
        return v()
      end
    end
    return nil
  end

  local number_of_lines = num(phrase.number_of_lines)
  if not number_of_lines then
    return nil, "Could not read phrase.number_of_lines"
  end

  local line_index = num(context.line)
  if not line_index then
    return nil, "Invalid context.line"
  end

  -- Validate line index
  if line_index < 1 or line_index > number_of_lines then
    return nil, string.format("Phrase line %d out of range [1, %d]",
      line_index, number_of_lines)
  end

  local line = phrase.lines[line_index]
  if not line then
    return nil, string.format("Phrase line %d not found", line_index)
  end

  local note_columns = line.note_columns
  local num_note_columns = num(note_columns)

  -- Some APIs return a table of columns; some return an observable with a length
  if not num_note_columns then
    if type(note_columns) == "table" then
      num_note_columns = #note_columns
    elseif type(note_columns) == "userdata" and note_columns.length then
      num_note_columns = num(note_columns.length)
    end
  end

  if not num_note_columns then
    return nil, "Could not determine number of note columns"
  end

  local note_col_index = num(context.note_col)
  if not note_col_index then
    return nil, "Invalid context.note_col"
  end

  -- Validate note column index
  if note_col_index < 1 or note_col_index > num_note_columns then
    return nil, string.format("Note column %d out of range [1, %d]",
      note_col_index, num_note_columns)
  end

  return line:note_column(note_col_index), nil
end

-- Get current note column in phrase
-- @return note_column or nil, error
function PhraseAccessor.get_current_note_column()
  local Context = require('renoise/context')
  local context, err = Context.get_phrase_context()
  if not context then
    return nil, err
  end

  if not context.note_col then
    return nil, "No note column selected in phrase"
  end

  return PhraseAccessor.get_note_column(context)
end

-- ============================================================================
-- Effect Column Access
-- ============================================================================

-- Get effect column at specified position in phrase
-- @param context: Context table with phrase, line, effect_col
-- @return effect_column or nil, error
function PhraseAccessor.get_effect_column(context)
  local success, err = Validator.validate_phrase_selected()
  if not success then
    return nil, err
  end

  local phrase = context.phrase

  -- Validate line index
  local number_of_lines = num(phrase.number_of_lines)
  if not number_of_lines then
    return nil, "Could not read phrase.number_of_lines"
  end
  if context.line < 1 or context.line > number_of_lines then
    return nil, string.format("Phrase line %d out of range [1, %d]",
      context.line, number_of_lines)
  end

  local line = phrase.lines[context.line]

  -- Validate effect column index
  local num_effect_cols = num(line.effect_columns)
  if not num_effect_cols and type(line.effect_columns) == "table" then
    num_effect_cols = #line.effect_columns
  end
  if not num_effect_cols then
    return nil, "Could not determine number of effect columns"
  end
  if context.effect_col < 1 or context.effect_col > num_effect_cols then
    return nil, string.format("Effect column %d out of range [1, %d]",
      context.effect_col, num_effect_cols)
  end

  return line:effect_column(context.effect_col), nil
end

-- Get current effect column in phrase
-- @return effect_column or nil, error
function PhraseAccessor.get_current_effect_column()
  local Context = require('renoise/context')
  local context, err = Context.get_phrase_context()
  if not context then
    return nil, err
  end

  if not context.effect_col then
    return nil, "No effect column selected in phrase"
  end

  return PhraseAccessor.get_effect_column(context)
end

-- ============================================================================
-- Line Access
-- ============================================================================

-- Get line at specified position in phrase
-- @param context: Context table with phrase, line
-- @return line or nil, error
function PhraseAccessor.get_line(context)
  local success, err = Validator.validate_phrase_selected()
  if not success then
    return nil, err
  end

  local phrase = context.phrase

  -- Validate line index
  local number_of_lines = num(phrase.number_of_lines)
  if not number_of_lines then
    return nil, "Could not read phrase.number_of_lines"
  end
  if context.line < 1 or context.line > number_of_lines then
    return nil, string.format("Phrase line %d out of range [1, %d]",
      context.line, number_of_lines)
  end

  return phrase.lines[context.line], nil
end

-- Get current line in phrase
-- @return line or nil, error
function PhraseAccessor.get_current_line()
  local Context = require('renoise/context')
  local context, err = Context.get_phrase_context()
  if not context then
    return nil, err
  end

  return PhraseAccessor.get_line(context)
end

-- ============================================================================
-- Navigation Helpers
-- ============================================================================


-- -- Check if can move up from current line in phrase
-- -- @param context: Context table
-- -- @return boolean
-- function PhraseAccessor.can_move_up(context)
--   return context.line > 1
-- end


-- Check if can move up from current line in phrase
-- @param context: Context table
-- @return boolean
function PhraseAccessor.can_move_up(context)
  local line = num(context.line)
  if not line then
    return false
  end
  return line > 1
end

-- Check if can move down from current line in phrase
-- @param context: Context table
-- @return boolean
function PhraseAccessor.can_move_down(context)
  local success, err = Validator.validate_phrase_selected()
  if not success then
    return false
  end

  local phrase = context.phrase
  local number_of_lines = num(phrase.number_of_lines)
  if not number_of_lines then
    return false
  end
  return context.line < number_of_lines
end

-- Check if can move left from current column in phrase
-- @param context: Context table
-- @return boolean
function PhraseAccessor.can_move_left(context)
  if context.note_col and context.note_col > 1 then
    return true
  end

  return false
end

-- Check if can move right from current column in phrase
-- @param context: Context table
-- @return boolean
function PhraseAccessor.can_move_right(context)
  local success, err = Validator.validate_phrase_selected()
  if not success then
    return false
  end

  local phrase = context.phrase
  local visible_cols = num(phrase.visible_note_columns)
  if not visible_cols then
    return false
  end

  if context.note_col and context.note_col < visible_cols then
    return true
  end

  return false
end

-- ============================================================================
-- Line/Column Retrieval by Direction
-- ============================================================================

-- Get line above current in phrase
-- @param context: Context table
-- @return line or nil, error
function PhraseAccessor.get_line_above(context)
  if not PhraseAccessor.can_move_up(context) then
    return nil, "Already at first line"
  end

  local new_context = {
    phrase = context.phrase,
    line = context.line - 1
  }

  return PhraseAccessor.get_line(new_context)
end

-- Get line below current in phrase
-- @param context: Context table
-- @return line or nil, error
function PhraseAccessor.get_line_below(context)
  if not PhraseAccessor.can_move_down(context) then
    return nil, "Already at last line"
  end

  local new_context = {
    phrase = context.phrase,
    line = context.line + 1
  }

  return PhraseAccessor.get_line(new_context)
end

-- Get note column to the left in phrase
-- @param context: Context table
-- @return note_column or nil, error
function PhraseAccessor.get_note_column_left(context)
  if not context.note_col then
    return nil, "No note column selected"
  end

  if context.note_col <= 1 then
    return nil, "Already at leftmost column"
  end

  local new_context = {
    phrase = context.phrase,
    line = context.line,
    note_col = context.note_col - 1
  }

  return PhraseAccessor.get_note_column(new_context)
end

-- Get note column to the right in phrase
-- @param context: Context table
-- @return note_column or nil, error
function PhraseAccessor.get_note_column_right(context)
  if not context.note_col then
    return nil, "No note column selected"
  end

  local phrase = context.phrase
  local visible_cols = num(phrase.visible_note_columns)
  if not visible_cols then
    return nil, "Could not determine visible note columns"
  end

  if context.note_col >= visible_cols then
    return nil, "Already at rightmost column"
  end

  local new_context = {
    phrase = context.phrase,
    line = context.line,
    note_col = context.note_col + 1
  }

  return PhraseAccessor.get_note_column(new_context)
end

-- ============================================================================
-- Phrase Information
-- ============================================================================

-- Get line count in phrase
-- @param context: Context table
-- @return line_count or 0
function PhraseAccessor.get_line_count(context)
  local success, err = Validator.validate_phrase_selected()
  if not success then
    return 0
  end

  return num(context.phrase.number_of_lines) or 0
end

-- Get note column count (visible) in current phrase
-- @param context: Context table
-- @return column_count or 0
function PhraseAccessor.get_note_column_count(context)
  local success, err = Validator.validate_phrase_selected()
  if not success then
    return 0
  end

  return num(context.phrase.visible_note_columns) or 0
end

return PhraseAccessor
