_AUTO_RELOAD_DEBUG = function()
  -- Cleanup on reload
  local InputTracker = require('renoise/input_tracker')
  InputTracker.cleanup()
  print("tools reloaded")
end

-- ============================================================================
-- Initialize Core Modules
-- ============================================================================

local ConfigManager = require('core/config_manager')
local ErrorHandler = require('core/error_handler')

-- Load configuration
ConfigManager.load()

-- Set log level from config
ErrorHandler.set_log_level(ConfigManager.get_log_level_number())

-- Log startup
ErrorHandler.info("Nudger tool initialized")
ErrorHandler.debug("Configuration loaded", {
  log_level = ConfigManager.get_log_level(),
  debug_mode = ConfigManager.is_debug_mode(),
  osc_enabled = ConfigManager.is_osc_enabled()
})

-- ============================================================================
-- Initialize Input Tracking
-- ============================================================================

local InputTracker = require('renoise/input_tracker')

-- Initialize when song is loaded
local function init_input_tracker()
  if renoise.song() then
    InputTracker.initialize()
    ErrorHandler.debug("Input tracking initialized")
  end
end

-- Initialize now if song is loaded
init_input_tracker()

-- Re-initialize when new song is loaded
renoise.tool().app_new_document_observable:add_notifier(function()
  ErrorHandler.debug("New document loaded, re-initializing input tracker")
  InputTracker.cleanup()
  init_input_tracker()
end)

-- ============================================================================
-- Register Keybindings and Menus (see usecases/)
-- ============================================================================

local UseCases = require('usecases')
UseCases.register_all()

-- ============================================================================
-- Optional OSC support (disabled)
-- ============================================================================

require 'osc_client'
require 'osc_server'

-- init_osc_server()
-- init_osc_client()
