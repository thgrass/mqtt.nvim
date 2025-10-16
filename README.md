# mqtt.nvim

**mqtt.nvim** is a lightweight Neovim plugin for working with [MQTT](https://mqtt.org/) brokers directly from your editor.  It allows you to subscribe to topics and view messages in a buffer, as well as publish arbitrary payloads.  The plugin is written in pure Lua, has no external runtime dependencies beyond the [Mosquitto](https://mosquitto.org/) command‑line clients, and runs asynchronously to keep the UI responsive.

## Features

- 🔌 Connect to any MQTT broker (host, port, optional username/password).
- 📬 Subscribe to one or more topics and see live messages appended to a scratch buffer.
- 📤 Publish arbitrary payloads to topics from within Neovim.
- ⚡️ Asynchronous: uses Neovim’s job API to run `mosquitto_sub` and `mosquitto_pub` without blocking the UI.
- 🧠 Small footprint: the core plugin is ~100 lines of Lua.

## Requirements

- **Neovim 0.7 or later** (requires the built‑in Lua runtime and job control).
- **Mosquitto clients** (`mosquitto_sub` and `mosquitto_pub`) installed and on your `$PATH`.  On Debian/Ubuntu you can install them with:

```sh
sudo apt install mosquitto-clients
```

On macOS with Homebrew:

```sh
brew install mosquitto
```

## Installation

Add the plugin to your Neovim plugin manager. 

### lazy.nvim 

```lua
{
  "thgrass/mqtt.nvim",
  cmd = { "MqttConnect", "MqttSubscribe", "MqttPublish", "MqttDisconnect" },
  config = function()
    -- optional: set defaults here
    require("mqtt").setup({
      default_host = "localhost",
      default_port = 1883,
      default_user = nil,
      default_pass = nil,
    })
  end,
}
```

### packer.nvim

```lua
use {
  "thgrass/mqtt.nvim",
  config = function()
    require("mqtt").setup({
      default_host = "localhost",
      default_port = 1883,
    })
  end,
  cmd = { "MqttConnect", "MqttSubscribe", "MqttPublish", "MqttDisconnect" },
}
```

### vim‑plug

```vim
Plug 'thgrass/mqtt.nvim'

" after plug#end() in Vim script
lua << EOF
require('mqtt').setup({
  default_host = 'localhost',
  default_port = 1883,
})
EOF
```

## Usage

### Setup

Call `require('mqtt').setup()` once from your config to set defaults.  You can omit this call if you don’t need to override anything. Default as example:

```lua
require('mqtt').setup({
  default_host = "127.0.0.1",
  default_port = 1883,
  default_user = nil,
  default_pass = nil,
})
```

### Commands

The plugin defines four user commands.  You can view help for each command with `:h mqtt.nvim` after installation.

| Command | Description |
|--------|-------------|
| `:MqttConnect [host] [port] [username] [password]` | Set the broker connection used for subsequent operations.  If omitted, values fall back to the defaults specified in `setup()`.  You can reconnect at any time to change broker or credentials. |
| `:MqttSubscribe &lt;topic&gt;` | Open a scratch buffer and start a background subscription to the given topic.  Incoming messages append to the buffer **and**, if the console is enabled, to the global console.  Multiple subscriptions may be active simultaneously (one buffer per topic). |
| `:MqttPublish &lt;topic&gt; &lt;payload&gt;` | Publish `payload` to `topic` using the current connection settings. |
| `:MqttDisconnect` | Stop all active subscriptions and clear stored connection parameters.  This does not close any buffers already opened. |
| `:MqttConsole` | Open (or reopen) the persistent console window.  The console aggregates all incoming messages from all topics into a single buffer. |

### Examples

Connect to a broker and subscribe to a topic:

```vim
:MqttConnect test.mosquitto.org 1883
:MqttSubscribe my/home/sensor/temperature
```

Publish a message:

```vim
:MqttPublish my/home/light "ON"
```

Disconnect:

```vim
:MqttDisconnect
```

## Configuration

`require('mqtt').setup()` accepts the following keys (all optional):

| Key | Default | Description |
|----|---------|-------------|
| `default_host` | `"127.0.0.1"` | Broker host used when `:MqttConnect` omits the `host` argument. |
| `default_port` | `1883` | Broker port used when `:MqttConnect` omits the `port` argument. |
| `default_user` | `nil` | Username passed to `mosquitto_sub/pub` when none is given. |
| `default_pass` | `nil` | Password passed to `mosquitto_sub/pub` when none is given. |
| `client_opts` | `{}` | Extra flags appended to `mosquitto_sub` and `mosquitto_pub`.  See the Mosquitto manual for supported options. |
| `use_console` | `true` | If `true`, all incoming messages are also appended to a persistent console buffer.  Toggle it with `:MqttConsole`. |
| `console_position` | `"bottom"` | Where to open the console window (`"bottom"` for a horizontal split or `"right"` for a vertical split). |

You can also override the names of the commands (e.g. `:MqttSubscribe`) by setting the `command_names` table; see the code for details.

## How it works

Under the hood, the plugin shells out to `mosquitto_sub` for subscriptions and `mosquitto_pub` for publishing.  Neovim’s job control captures the standard output of `mosquitto_sub` and appends each line to a scratch buffer in real time.  The asynchronous job is automatically cleaned up when you call `:MqttDisconnect` or when you close Neovim.

Because this approach relies on external executables, you can easily swap them for any MQTT client by modifying the `build_cmd()` function in `lua/mqtt/init.lua`.

## Limitations / TODOs

* **No TLS support out of the box:** you can pass `--cafile`, `--key`, `--cert`, etc. via `client_opts` to enable TLS, but you must manage certificates yourself.
* **No retain flag:** to publish retained messages, add `-r` to `client_opts` and override the publish command accordingly.
* **Single‑use subscriptions:** each call to `:MqttSubscribe` spawns a new `mosquitto_sub` job.  There’s no central connection or topic multiplexing.

## License

This project is licensed under the MIT License.  See [LICENSE](LICENSE) for details.
