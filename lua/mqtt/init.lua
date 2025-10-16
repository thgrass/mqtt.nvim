---
--- mqtt.nvim
---
--- A simple Neovim plugin for interacting with MQTT brokers using the
--- command‑line Mosquitto clients.  See README.md for details.
---
local M = {}

-- Default configuration.  See README.md for the meaning of each option.
local defaults = {
  -- Default MQTT broker host.  Users can override this via setup() or
  -- :MqttConnect.  By default we connect to the loopback address.
  default_host = "127.0.0.1",
  default_port = 1883,
  default_user = nil,
  default_pass = nil,
  client_opts = {}, -- extra flags for mosquitto_sub/pub, e.g. {"--insecure"}
  -- When true, append all incoming messages to a single global console buffer
  -- in addition to per‑topic scratch buffers.  Use :MqttConsole to open the
  -- console if it is not already visible.
  use_console = true,
  -- Position for the console window when it is created ("bottom" or "right").
  console_position = "bottom",
  command_names = {
    connect = "MqttConnect",
    subscribe = "MqttSubscribe",
    publish = "MqttPublish",
    disconnect = "MqttDisconnect",
    console = "MqttConsole",
  },
}

-- Runtime state: connection parameters and active subscriptions.
local state = {
  host = nil,
  port = nil,
  user = nil,
  pass = nil,
  subs = {}, -- map buf -> job id
  console_bufnr = nil,
  console_win = nil,
  -- map topic -> scratch buffer (if per-topic buffers are used)
  topic_buffers = {},
}

-- Deep merge two tables.  Used to merge user opts with defaults.
local function deep_extend(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      deep_extend(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

-- Get or create the global console buffer and window.  The console is a
-- persistent buffer where all incoming messages are appended.  It will be
-- created if it doesn't already exist.  When created, a new window is
-- opened according to the configured position.
local function open_console()
  -- ensure buffer
  if not state.console_bufnr or not vim.api.nvim_buf_is_valid(state.console_bufnr) then
    local bufnr = vim.api.nvim_create_buf(false, true)
    state.console_bufnr = bufnr
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(bufnr, "filetype", "mqttconsole")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "-- MQTT console --" })
  end
  -- ensure window
  if not state.console_win or not vim.api.nvim_win_is_valid(state.console_win) then
    local pos = M.config.console_position or defaults.console_position
    if pos == "right" then
      vim.api.nvim_command("botright vsplit")
    else
      -- default to bottom
      vim.api.nvim_command("botright split")
    end
    local win = vim.api.nvim_get_current_win()
    state.console_win = win
    vim.api.nvim_win_set_buf(win, state.console_bufnr)
    vim.api.nvim_win_set_option(win, "wrap", false)
  end
  return state.console_bufnr, state.console_win
end

-- Append a message line to the console buffer with topic prefix.
local function append_to_console(topic, line)
  if not M.config.use_console then return end
  local bufnr = state.console_bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    -- lazily create console; this also opens a window
    open_console()
    bufnr = state.console_bufnr
  end
  local prefix = topic and ("[" .. topic .. "] ") or ""
  local msg = prefix .. line
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { msg })
end

--- Build a mosquitto command.
-- client: either "mosquitto_sub" or "mosquitto_pub"
-- args: table of extra arguments (e.g. {"-t", topic, "-m", payload})
local function build_cmd(client, args)
  local cmd = { client }
  local host = state.host or M.config.default_host
  local port = state.port or M.config.default_port
  if host then table.insert(cmd, "-h") table.insert(cmd, host) end
  if port then table.insert(cmd, "-p") table.insert(cmd, tostring(port)) end
  local user = state.user or M.config.default_user
  local pass = state.pass or M.config.default_pass
  if user then table.insert(cmd, "-u") table.insert(cmd, user) end
  if pass then table.insert(cmd, "-P") table.insert(cmd, pass) end
  for _, opt in ipairs(M.config.client_opts or {}) do
    table.insert(cmd, opt)
  end
  for _, a in ipairs(args) do
    table.insert(cmd, a)
  end
  return cmd
end

--- Connect to an MQTT broker.  Stores the connection parameters for later use.
-- You can omit any argument to fall back to defaults.
function M.connect(host, port, user, pass)
  state.host = host and host ~= "" and host or M.config.default_host
  state.port = port and port ~= "" and tonumber(port) or M.config.default_port
  state.user = user and user ~= "" and user or M.config.default_user
  state.pass = pass and pass ~= "" and pass or M.config.default_pass
  vim.notify(string.format("[mqtt.nvim] Connected to %s:%s", state.host, state.port), vim.log.levels.INFO)
end

--- Subscribe to a topic.  Opens a new scratch buffer and spawns a background job.
function M.subscribe(topic)
  if not topic or topic == "" then
    vim.notify("[mqtt.nvim] Topic required for MqttSubscribe", vim.log.levels.ERROR)
    return
  end
  -- ensure connection parameters are set
  if not (state.host and state.port) then
    -- auto‑connect using defaults if not connected yet
    M.connect()
  end

  -- helper to create or reuse a scratch buffer for the topic
  local function get_topic_buffer()
    local buf = state.topic_buffers[topic]
    if buf and vim.api.nvim_buf_is_valid(buf) then
      return buf
    end
    local newbuf = vim.api.nvim_create_buf(false, true)
    state.topic_buffers[topic] = newbuf
    vim.api.nvim_buf_set_option(newbuf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(newbuf, "filetype", "mqttlog")
    vim.api.nvim_buf_set_option(newbuf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(newbuf, "modifiable", true)
    vim.api.nvim_buf_set_lines(newbuf, 0, -1, false, { string.format("-- MQTT subscription: %s --", topic) })
    -- open the buffer in a split
    vim.api.nvim_command("botright new")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, newbuf)
    vim.api.nvim_win_set_option(win, "wrap", false)
    -- ensure closing the buffer stops the job later; autocommand added below
    return newbuf
  end

  local bufnr = get_topic_buffer()
  -- build mosquitto_sub command
  local cmd = build_cmd("mosquitto_sub", { "-t", topic })
  -- spawn job
  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      vim.schedule(function()
        for _, line in ipairs(data) do
          if line and line ~= "" then
            -- append to per-topic buffer
            if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
              vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { line })
            end
            -- append to console
            append_to_console(topic, line)
          end
        end
      end)
    end,
    on_exit = function(_, code, _)
      vim.schedule(function()
        local msg = string.format("[mqtt.nvim] Subscription to %s ended (code %d)", topic, code)
        -- append to buffers
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { msg })
        end
        append_to_console(topic, msg)
      end)
    end,
  })
  if job_id <= 0 then
    vim.notify(string.format("[mqtt.nvim] Failed to start mosquitto_sub for %s", topic), vim.log.levels.ERROR)
    return
  end
  -- store subscription keyed by job id
  state.subs[job_id] = { topic = topic, bufnr = bufnr }
  -- stop job when buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      -- find job associated with this buffer
      for jid, info in pairs(state.subs) do
        if info.bufnr == bufnr then
          vim.fn.jobstop(jid)
          state.subs[jid] = nil
        end
      end
      state.topic_buffers[topic] = nil
    end,
  })
end

--- Publish a payload to a topic.
function M.publish(topic, payload)
  if not topic or topic == "" then
    vim.notify("[mqtt.nvim] Topic required for MqttPublish", vim.log.levels.ERROR)
    return
  end
  if not payload then payload = "" end
  -- ensure connection parameters are set
  if not (state.host and state.port) then
    M.connect()
  end
  local args = { "-t", topic, "-m", payload }
  local cmd = build_cmd("mosquitto_pub", args)
  local job = vim.fn.jobstart(cmd, {
    detach = true,
  })
  if job <= 0 then
    vim.notify(string.format("[mqtt.nvim] Failed to publish to %s", topic), vim.log.levels.ERROR)
    return
  end
  vim.notify(string.format("[mqtt.nvim] Published to %s", topic), vim.log.levels.INFO)
end

--- Open (or reopen) the MQTT console window.  The console shows all
-- messages from all topics.  If the console buffer does not exist, it
-- will be created.  If the buffer exists but no window shows it, a new
-- split is opened in the configured position.
function M.console()
  open_console()
end

--- Disconnect from the broker and stop all subscriptions.
function M.disconnect()
  -- stop all jobs
  for jid, _info in pairs(state.subs) do
    if jid and jid > 0 then
      vim.fn.jobstop(jid)
    end
  end
  state.subs = {}
  -- reset connection parameters
  state.host = nil
  state.port = nil
  state.user = nil
  state.pass = nil
  -- clear topic buffers and console
  for _, buf in pairs(state.topic_buffers) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "-- MQTT buffer cleared --" })
    end
  end
  state.topic_buffers = {}
  if state.console_bufnr and vim.api.nvim_buf_is_valid(state.console_bufnr) then
    vim.api.nvim_buf_set_lines(state.console_bufnr, 0, -1, false, { "-- MQTT console cleared --" })
  end
  vim.notify("[mqtt.nvim] Disconnected and stopped all subscriptions", vim.log.levels.INFO)
end

--- Setup user configuration and create commands.
-- @param opts table user options merged with defaults
function M.setup(opts)
  M.config = deep_extend(vim.deepcopy(defaults), opts or {})
  -- create user commands
  local names = M.config.command_names or {}
  -- Connect command: accepts up to four optional args
  vim.api.nvim_create_user_command(names.connect or defaults.command_names.connect, function(params)
    local f = params.fargs
    M.connect(f[1], f[2], f[3], f[4])
  end, {
    nargs = "*",
    complete = function(_, _)
      return {}
    end,
    desc = "Set MQTT connection parameters: [host] [port] [user] [password]",
  })
  -- Subscribe command: one argument (topic)
  vim.api.nvim_create_user_command(names.subscribe or defaults.command_names.subscribe, function(params)
    M.subscribe(params.args)
  end, {
    nargs = 1,
    desc = "Subscribe to an MQTT topic and show messages in a buffer",
  })
  -- Publish command: at least two arguments: topic and payload
  vim.api.nvim_create_user_command(names.publish or defaults.command_names.publish, function(params)
    local f = params.fargs
    if #f < 2 then
      vim.notify("[mqtt.nvim] Usage: MqttPublish <topic> <payload>", vim.log.levels.ERROR)
      return
    end
    local topic = f[1]
    -- join remaining args as payload to preserve spaces
    local payload = table.concat(vim.list_slice(f, 2), " ")
    M.publish(topic, payload)
  end, {
    nargs = "+",
    desc = "Publish a payload to an MQTT topic",
  })
  -- Disconnect command: no args
  vim.api.nvim_create_user_command(names.disconnect or defaults.command_names.disconnect, function()
    M.disconnect()
  end, {
    nargs = 0,
    desc = "Disconnect and stop all MQTT subscriptions",
  })
  -- Console command: toggle the console open (creates it if needed)
  vim.api.nvim_create_user_command(names.console or defaults.command_names.console, function()
    M.console()
  end, {
    nargs = 0,
    desc = "Open the MQTT console buffer",
  })
end

return M