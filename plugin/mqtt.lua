-- Auto‑load mqtt.nvim
-- This file runs when Neovim detects the plugin.  It simply calls
-- require('mqtt').setup() with no arguments so that the commands are defined.
-- Users can override defaults by calling require('mqtt').setup() again in
-- their own config; the setup function is idempotent.

if vim.g.loaded_mqtt_nvim then
  return
end
vim.g.loaded_mqtt_nvim = true

pcall(function()
  require('mqtt').setup()
end)