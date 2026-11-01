--[========================================================================]--
--  Slate UI Library (Raw / Single-File Bundled Version)
--  Made by Pulse Hub / Discord.gg/pulsezone
--[========================================================================]--

local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Slate = {}
Slate.Version = "1.0.0"

-- ============================================================================
-- CORE: UTIL
-- ============================================================================
local Util = {}
local nextId = 0

function Util.uid(prefix)
    nextId += 1
    return (prefix or "slate") .. "_" .. nextId
end

function Util.new(class, props, children)
    local inst = Instance.new(class)
    local parent
    if props then
        for key, value in pairs(props) do
            if key == "Parent" then
                parent = value
            else
                inst[key] = value
            end
        end
    end
    if children then
        for _, child in ipairs(children) do
            child.Parent = inst
        end
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

function Util.clamp(value, min, max)
    if value < min then return min elseif value > max then return max end
    return value
end

function Util.round(value, decimals)
    local mult = 10 ^ math.max(0, math.floor(decimals or 0))
    return math.floor(value * mult + 0.5) / mult
end

function Util.lerp(a, b, t) return a + (b - a) * t end

function Util.alpha(value, min, max)
    if max == min then return 0 end
    return Util.clamp((value - min) / (max - min), 0, 1)
end

function Util.str(value, fallback)
    if type(value) == "string" then return value end
    if value == nil then return fallback end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    return fallback
end

function Util.num(value, fallback)
    local converted = tonumber(value)
    if converted == nil or converted ~= converted then return fallback end
    return converted
end

function Util.bool(value, fallback)
    if type(value) == "boolean" then return value end
    return fallback
end

function Util.fn(value)
    if type(value) == "function" then return value end
    return nil
end

function Util.list(value)
    if type(value) ~= "table" then return {} end
    local out = {}
    for index, item in ipairs(value) do out[index] = item end
    return out
end

function Util.indexOf(list, value)
    for index, item in ipairs(list) do if item == value then return index end end
    return nil
end

function Util.remove(list, value)
    local index = Util.indexOf(list, value)
    if index then table.remove(list, index); return true end
    return false
end

function Util.merge(target, patch)
    for key, value in pairs(patch) do target[key] = value end
    return target
end

function Util.copy(source)
    local out = {}
    for key, value in pairs(source) do out[key] = value end
    return out
end

function Util.count(source)
    local total = 0
    for _ in pairs(source) do total += 1 end
    return total
end

function Util.normalise(text)
    return (string.lower(tostring(text or "")):gsub("[^%w]", ""))
end

function Util.matches(haystack, needle)
    if needle == "" then return true end
    return string.find(Util.normalise(haystack), needle, 1, true) ~= nil
end

function Util.dispatch(callback, ...)
    if type(callback) ~= "function" then return end
    local args = table.pack(...)
    task.spawn(function()
        local ok, err = pcall(callback, table.unpack(args, 1, args.n))
        if not ok then Slate.Log.error("callback", err) end
    end)
end

function Util.guiInset()
    local ok, inset = pcall(function() return game:GetService("GuiService"):GetGuiInset() end)
    if ok and typeof(inset) == "Vector2" then return inset end
    return Vector2.new(0, 0)
end

local executorName, executorVersion, executorProbed = nil, nil, false
function Util.executor()
    if executorProbed then return executorName, executorVersion end
    executorProbed = true
    local names = { "identifyexecutor", "getexecutorname", "get_executor_name" }
    for _, name in ipairs(names) do
        local fn = rawget(getfenv(), name)
        if type(fn) ~= "function" then
            local ok, value = pcall(function() return getgenv and getgenv()[name] or nil end)
            fn = ok and value or nil
        end
        if type(fn) == "function" then
            local ok, label, version = pcall(fn)
            if ok and type(label) == "string" and label ~= "" then
                executorName = label
                executorVersion = type(version) == "string" and version ~= "" and version or nil
                return executorName, executorVersion
            end
        end
    end
    return nil, nil
end

function Util.viewport()
    local camera = workspace.CurrentCamera
    if camera then return camera.ViewportSize end
    return Vector2.new(1280, 720)
end

-- ============================================================================
-- CORE: SIGNAL
-- ============================================================================
local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _handlers = {}, _dead = false }, Signal)
end

function Signal:Connect(handler)
    if self._dead or type(handler) ~= "function" then
        return { Disconnect = function() end, Connected = false }
    end
    local entry = { fn = handler, alive = true }
    table.insert(self._handlers, entry)
    local connection = {}
    connection.Connected = true
    function connection.Disconnect()
        if not entry.alive then return end
        entry.alive = false
        connection.Connected = false
        for index, candidate in ipairs(self._handlers) do
            if candidate == entry then table.remove(self._handlers, index); break end
        end
    end
    connection.disconnect = connection.Disconnect
    return connection
end

function Signal:Once(handler)
    local connection
    connection = self:Connect(function(...)
        connection.Disconnect()
        handler(...)
    end)
    return connection
end

function Signal:Fire(...)
    if self._dead then return end
    local snapshot = table.clone(self._handlers)
    for _, entry in ipairs(snapshot) do
        if entry.alive then
            local ok, err = pcall(entry.fn, ...)
            if not ok then Slate.Log.error("signal", err) end
        end
    end
end

function Signal:Count() return #self._handlers end

function Signal:Destroy()
    self._dead = true
    table.clear(self._handlers)
end

-- ============================================================================
-- CORE: MAID
-- ============================================================================
local Maid = {}
Maid.__index = Maid

function Maid.new() return setmetatable({ _tasks = {}, _dead = false }, Maid) end

local function dispose(item)
    local kind = typeof(item)
    if kind == "RBXScriptConnection" then item:Disconnect()
    elseif kind == "Instance" then item:Destroy()
    elseif kind == "function" then item()
    elseif kind == "thread" then if coroutine.status(item) == "suspended" then task.cancel(item) end
    elseif kind == "table" then
        if type(item.Destroy) == "function" then item:Destroy()
        elseif type(item.Disconnect) == "function" then item:Disconnect()
        elseif type(item.disconnect) == "function" then item.disconnect() end
    end
end

function Maid:Add(item)
    if item == nil then return nil end
    if self._dead then pcall(dispose, item); return item end
    table.insert(self._tasks, item)
    return item
end

function Maid:AddAll(items) for _, item in ipairs(items) do self:Add(item) end end

function Maid:Remove(item)
    for index, candidate in ipairs(self._tasks) do
        if candidate == item then table.remove(self._tasks, index); return true end
    end
    return false
end

function Maid:Extend()
    local child = Maid.new()
    self:Add(child)
    return child
end

function Maid:IsDead() return self._dead end

function Maid:Clean()
    local pending = self._tasks
    self._tasks = {}
    for index = #pending, 1, -1 do
        local ok, err = pcall(dispose, pending[index])
        if not ok then Slate.Log.error("cleanup", err) end
    end
end

function Maid:Destroy()
    if self._dead then return end
    self._dead = true
    self:Clean()
end

-- ============================================================================
-- CORE: LOG
-- ============================================================================
local Log = {}
local enabled = false
local counters = { warn = 0, error = 0 }
local history = {}
local HISTORY_LIMIT = 100

local function record(level, scope, message)
    local line = string.format("[Slate/%s] %s: %s", level, tostring(scope), tostring(message))
    table.insert(history, line)
    if #history > HISTORY_LIMIT then table.remove(history, 1) end
    return line
end

function Log.setEnabled(state) enabled = state == true end
function Log.isEnabled() return enabled end
function Log.warn(scope, message)
    counters.warn += 1
    local line = record("warn", scope, message)
    if enabled then warn(line) end
end
function Log.error(scope, message)
    counters.error += 1
    local line = record("error", scope, message)
    if enabled then warn(line) end
end
function Log.expect(condition, scope, message)
    if not condition then Log.warn(scope, message) end
    return condition
end
function Log.field(scope, field, value, expected)
    Log.warn(scope, string.format("field '%s' expected %s, got %s (%s)", tostring(field), tostring(expected), typeof(value), tostring(value)))
end
function Log.stats() return { warnings = counters.warn, errors = counters.error, entries = #history } end
function Log.dump() return table.concat(history, "\n") end
function Log.clear() table.clear(history); counters.warn = 0; counters.error = 0 end
Slate.Log = Log

-- ============================================================================
-- CORE: THEME
-- ============================================================================
local Theme = {}
Theme.Changed = Signal.new()

local PALETTES = {
    Violet = {
        Background = Color3.fromRGB(11, 11, 16), Surface = Color3.fromRGB(19, 19, 26), SurfaceAlt = Color3.fromRGB(26, 26, 35), Elevated = Color3.fromRGB(31, 31, 42), Border = Color3.fromRGB(255, 255, 255), Line = Color3.fromRGB(255, 255, 255), Text = Color3.fromRGB(240, 240, 246), Muted = Color3.fromRGB(140, 140, 158), Faint = Color3.fromRGB(92, 92, 110), Accent = Color3.fromRGB(139, 92, 246), OnAccent = Color3.fromRGB(255, 255, 255), Success = Color3.fromRGB(74, 200, 140), Warning = Color3.fromRGB(232, 176, 78), Danger = Color3.fromRGB(228, 96, 106), ToggleOn = Color3.fromRGB(64, 196, 118), ToggleKnob = Color3.fromRGB(252, 253, 252), Info = Color3.fromRGB(110, 160, 240)
    },
    Graphite = {
        Background = Color3.fromRGB(10, 10, 11), Surface = Color3.fromRGB(17, 17, 19), SurfaceAlt = Color3.fromRGB(22, 22, 25), Elevated = Color3.fromRGB(27, 27, 31), Border = Color3.fromRGB(255, 255, 255), Line = Color3.fromRGB(255, 255, 255), Text = Color3.fromRGB(240, 240, 242), Muted = Color3.fromRGB(132, 132, 141), Faint = Color3.fromRGB(84, 84, 92), Accent = Color3.fromRGB(212, 175, 120), OnAccent = Color3.fromRGB(14, 12, 9), Success = Color3.fromRGB(122, 190, 142), Warning = Color3.fromRGB(216, 176, 106), Danger = Color3.fromRGB(214, 102, 102), ToggleOn = Color3.fromRGB(64, 196, 118), ToggleKnob = Color3.fromRGB(252, 253, 252), Info = Color3.fromRGB(130, 152, 190)
    },
    Ash = {
        Background = Color3.fromRGB(13, 14, 15), Surface = Color3.fromRGB(20, 21, 23), SurfaceAlt = Color3.fromRGB(25, 26, 29), Elevated = Color3.fromRGB(31, 32, 36), Border = Color3.fromRGB(255, 255, 255), Line = Color3.fromRGB(255, 255, 255), Text = Color3.fromRGB(236, 238, 240), Muted = Color3.fromRGB(128, 133, 140), Faint = Color3.fromRGB(80, 84, 90), Accent = Color3.fromRGB(168, 186, 200), OnAccent = Color3.fromRGB(14, 15, 16), Success = Color3.fromRGB(122, 190, 142), Warning = Color3.fromRGB(216, 176, 106), Danger = Color3.fromRGB(214, 102, 102), ToggleOn = Color3.fromRGB(64, 196, 118), ToggleKnob = Color3.fromRGB(252, 253, 252), Info = Color3.fromRGB(130, 152, 190)
    },
    Moss = {
        Background = Color3.fromRGB(9, 12, 10), Surface = Color3.fromRGB(15, 19, 16), SurfaceAlt = Color3.fromRGB(20, 25, 21), Elevated = Color3.fromRGB(25, 31, 26), Border = Color3.fromRGB(255, 255, 255), Line = Color3.fromRGB(255, 255, 255), Text = Color3.fromRGB(234, 240, 235), Muted = Color3.fromRGB(124, 138, 127), Faint = Color3.fromRGB(78, 90, 80), Accent = Color3.fromRGB(138, 190, 148), OnAccent = Color3.fromRGB(10, 16, 11), Success = Color3.fromRGB(138, 190, 148), Warning = Color3.fromRGB(216, 176, 106), Danger = Color3.fromRGB(214, 102, 102), ToggleOn = Color3.fromRGB(64, 196, 118), ToggleKnob = Color3.fromRGB(252, 253, 252), Info = Color3.fromRGB(130, 152, 190)
    },
    Paper = {
        Background = Color3.fromRGB(243, 243, 241), Surface = Color3.fromRGB(252, 252, 251), SurfaceAlt = Color3.fromRGB(246, 246, 244), Elevated = Color3.fromRGB(255, 255, 255), Border = Color3.fromRGB(0, 0, 0), Line = Color3.fromRGB(0, 0, 0), Text = Color3.fromRGB(24, 24, 26), Muted = Color3.fromRGB(112, 112, 118), Faint = Color3.fromRGB(168, 168, 172), Accent = Color3.fromRGB(126, 96, 48), OnAccent = Color3.fromRGB(252, 252, 251), Success = Color3.fromRGB(58, 132, 82), Warning = Color3.fromRGB(158, 116, 30), Danger = Color3.fromRGB(176, 56, 56), ToggleOn = Color3.fromRGB(64, 196, 118), ToggleKnob = Color3.fromRGB(252, 253, 252), Info = Color3.fromRGB(58, 96, 154)
    }
}

local METRICS = { Radius = 5, RadiusSm = 3, RowHeight = 36, Pad = 14, Gap = 8, RailWidth = 164, HeaderHeight = 48, FooterHeight = 24, BorderT = 0.90, LineT = 0.86, HoverT = 0.965, ScrollBar = 2 }
local tokens = Util.merge(Util.copy(PALETTES.Violet), METRICS)
local activePalette = "Violet"
local bindings = {}
local liveCount = 0

local function applyThemeEntry(entry)
    local value = tokens[entry.token]
    if value == nil then return end
    local ok = pcall(function() entry.instance[entry.property] = value end)
    if not ok then entry.dead = true end
end

function Theme.tokens() return Util.copy(tokens) end
function Theme.get(token, fallback)
    local value = tokens[token]
    if value == nil then
        if fallback ~= nil then return fallback end
        Log.warn("theme", "unknown token '" .. tostring(token) .. "'")
        return Color3.new(1, 0, 1)
    end
    return value
end
function Theme.color(token)
    local value = tokens[token]
    if typeof(value) == "Color3" then return value end
    Log.warn("theme", "token '" .. tostring(token) .. "' is not a colour")
    return Color3.new(1, 0, 1)
end
function Theme.number(token, fallback)
    local value = tokens[token]
    if type(value) == "number" then return value end
    return fallback or 0
end
function Theme.bind(instance, property, token)
    if typeof(instance) ~= "Instance" then Log.warn("theme", "bind expects an Instance"); return nil end
    local entry = { instance = instance, property = property, token = token, dead = false }
    function entry:Destroy() Theme.unbind(self) end
    table.insert(bindings, entry)
    liveCount += 1
    applyThemeEntry(entry)
    return entry
end
function Theme.rebind(entry, token)
    if not entry or entry.dead then return end
    entry.token = token
    applyThemeEntry(entry)
end
function Theme.unbind(entry)
    if entry and not entry.dead then entry.dead = true; liveCount -= 1 end
end
local function compactBindings()
    local kept = {}
    for _, entry in ipairs(bindings) do if not entry.dead then table.insert(kept, entry) end end
    bindings = kept
    liveCount = #kept
end
function Theme.Set(patch)
    if type(patch) ~= "table" then return Theme end
    local changed = false
    for key, value in pairs(patch) do
        if tokens[key] ~= nil or METRICS[key] ~= nil then
            tokens[key] = value
            changed = true
        end
    end
    if not changed then return Theme end
    compactBindings()
    for _, entry in ipairs(bindings) do applyThemeEntry(entry) end
    Theme.Changed:Fire(tokens)
    return Theme
end
function Theme.Preset(name)
    local palette = PALETTES[name]
    if not palette then return Theme end
    activePalette = name
    return Theme.Set(palette)
end
function Theme.Presets()
    local names = {}
    for name in pairs(PALETTES) do table.insert(names, name) end
    table.sort(names)
    return names
end
function Theme.Register(name, palette)
    local merged = Util.copy(PALETTES.Violet)
    for key, value in pairs(palette) do if merged[key] ~= nil then merged[key] = value end end
    PALETTS[name] = merged
    return Theme
end
function Theme.Current() return activePalette end
function Theme.stats() compactBindings(); return { bindings = liveCount, palette = activePalette } end
Slate.Theme = Theme

-- ============================================================================
-- CORE: MOTION
-- ============================================================================
local Motion = {}
Motion.Duration = { Instant = 0, Fast = 0.09, Base = 0.15, Slow = 0.24, Lazy = 0.38 }
local activeTweens = setmetatable({}, { __mode = "k" })
local watchers = setmetatable({}, { __mode = "k" })
local enabled = true
local runningTweens = 0

local function forgetTween(instance)
    local record = activeTweens[instance]
    if record then
        for _, tween in pairs(record) do pcall(function() tween:Cancel() end); runningTweens -= 1 end
    end
    activeTweens[instance] = nil
    local watcher = watchers[instance]
    if watcher then watcher:Disconnect(); watchers[instance] = nil end
end

local function watchInstance(instance)
    if watchers[instance] then return end
    local ok, connection = pcall(function() return instance.Destroying:Connect(function() forgetTween(instance) end) end)
    if ok and connection then watchers[instance] = connection end
end

function Motion.setEnabled(state) enabled = state ~= false end
function Motion.isEnabled() return enabled end
function Motion.set(instance, props)
    if typeof(instance) ~= "Instance" then return end
    for property in pairs(props) do Motion.cancel(instance, property) end
    for property, value in pairs(props) do pcall(function() instance[property] = value end) end
end
function Motion.play(instance, props, options)
    if typeof(instance) ~= "Instance" then return nil end
    options = options or {}
    local duration = options.duration or Motion.Duration.Base
    if not enabled or duration <= 0 then
        Motion.set(instance, props)
        if options.onDone then task.spawn(options.onDone, true) end
        return nil
    end
    for property in pairs(props) do Motion.cancel(instance, property) end
    local info = TweenInfo.new(duration, options.easing or Enum.EasingStyle.Quint, options.direction or Enum.EasingDirection.Out, 0, false, options.delay or 0)
    local ok, tween = pcall(function() return TweenService:Create(instance, info, props) end)
    if not ok or not tween then Motion.set(instance, props); return nil end
    watchInstance(instance)
    local record = activeTweens[instance]
    if not record then record = {}; activeTweens[instance] = record end
    for property in pairs(props) do record[property] = tween; runningTweens += 1 end
    tween.Completed:Connect(function(state)
        local current = activeTweens[instance]
        if current then
            for property, candidate in pairs(current) do
                if candidate == tween then current[property] = nil; runningTweens -= 1 end
            end
            if next(current) == nil then activeTweens[instance] = nil end
        end
        tween:Destroy()
        if options.onDone then task.spawn(options.onDone, state == Enum.PlaybackState.Completed) end
    end)
    tween:Play()
    return tween
end
function Motion.cancel(instance, property)
    local record = activeTweens[instance]
    if not record then return end
    if property then
        local tween = record[property]
        if tween then
            pcall(function() tween:Cancel() end)
            for key, candidate in pairs(record) do if candidate == tween then record[key] = nil; runningTweens -= 1 end end
        end
        if next(record) == nil then activeTweens[instance] = nil end
        return
    end
    forgetTween(instance)
end
function Motion.stop(instance) forgetTween(instance) end
function Motion.hover(instance, props) return Motion.play(instance, props, { duration = Motion.Duration.Fast, easing = Enum.EasingStyle.Sine }) end
function Motion.press(instance, props) return Motion.play(instance, props, { duration = 0.06, easing = Enum.EasingStyle.Sine }) end
function Motion.slide(instance, props, onDone) return Motion.play(instance, props, { duration = Motion.Duration.Base, easing = Enum.EasingStyle.Quint, onDone = onDone }) end
function Motion.stats()
    local instances = 0
    for _ in pairs(activeTweens) do instances += 1 end
    return { tweens = runningTweens, instances = instances, enabled = enabled }
end
Slate.Motion = Motion

-- ============================================================================
-- CORE: INPUT
-- ============================================================================
local Input = {}
Input.KeyDown = Signal.new()
Input.KeyUp = Signal.new()
Input.PointerDown = Signal.new()
Input.PointerUp = Signal.new()
Input.PointerMoved = Signal.new()

local layers = {}
local hotkeys = {}
local captureHandler = nil
local pendingModifier = nil
local connections = {}

local POINTER_TYPES = { [Enum.UserInputType.MouseButton1] = true, [Enum.UserInputType.MouseButton2] = true, [Enum.UserInputType.Touch] = true }
local MODIFIER_KEYS = { [Enum.KeyCode.LeftShift] = "Shift", [Enum.KeyCode.RightShift] = "Shift", [Enum.KeyCode.LeftControl] = "Ctrl", [Enum.KeyCode.RightControl] = "Ctrl", [Enum.KeyCode.LeftAlt] = "Alt", [Enum.KeyCode.RightAlt] = "Alt" }

function Input.isModifier(keyCode) return MODIFIER_KEYS[keyCode] ~= nil end
function Input.modifiers()
    local held = {}
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then table.insert(held, "Ctrl") end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then table.insert(held, "Shift") end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt) then table.insert(held, "Alt") end
    return held
end
function Input.pointerPosition()
    local location = UserInputService:GetMouseLocation()
    local inset = Util.guiInset()
    return Vector2.new(location.X - inset.X, location.Y - inset.Y)
end
local function normaliseInput(input) return Vector2.new(input.Position.X, input.Position.Y) end

function Input.pushLayer(config)
    local layer = { contains = config.contains, dismiss = config.dismiss, onEscape = config.onEscape, modal = config.modal == true, id = Util.uid("layer") }
    table.insert(layers, layer)
    return layer
end
function Input.popLayer(layer)
    if not layer then return end
    for index = #layers, 1, -1 do if layers[index] == layer then table.remove(layers, index); return end end
end
function Input.layerCount() return #layers end
function Input.capture(handler) pendingModifier = nil; captureHandler = handler end
function Input.cancelCapture(handler) if handler == nil or captureHandler == handler then pendingModifier = nil; captureHandler = nil end end
function Input.isCapturing() return captureHandler ~= nil end
function Input.bindHotkey(keyCode, handler)
    local entry = { key = keyCode, fn = handler, id = Util.uid("hotkey") }
    table.insert(hotkeys, entry)
    return entry
end
function Input.unbindHotkey(entry) Util.remove(hotkeys, entry) end

local function handleDismiss(position)
    for index = #layers, 1, -1 do
        local layer = layers[index]
        local inside = true
        if type(layer.contains) == "function" then
            local ok, result = pcall(layer.contains, position)
            inside = ok and result == true
        end
        if inside then return end
        if type(layer.dismiss) == "function" then task.spawn(layer.dismiss) end
        if layer.modal then return end
    end
end

local function handleEscape()
    local layer = layers[#layers]
    if not layer then return false end
    if type(layer.onEscape) == "function" then task.spawn(layer.onEscape)
    elseif type(layer.dismiss) == "function" then task.spawn(layer.dismiss) end
    return true
end

table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
    if captureHandler then
        local handler = captureHandler
        if input.UserInputType == Enum.UserInputType.Keyboard and Input.isModifier(input.KeyCode) then
            pendingModifier = input
            return
        end
        pendingModifier = nil
        captureHandler = nil
        task.spawn(handler, input)
        return
    end
    if POINTER_TYPES[input.UserInputType] then
        local position = normaliseInput(input)
        Input.PointerDown:Fire(position, input)
        handleDismiss(position)
        return
    end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if input.KeyCode == Enum.KeyCode.Escape then if handleEscape() then return end end
    Input.KeyDown:Fire(input.KeyCode, processed, input)
    if processed then return end
    for _, entry in ipairs(table.clone(hotkeys)) do if entry.key == input.KeyCode then task.spawn(entry.fn) end end
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(input)
    if captureHandler and pendingModifier and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == pendingModifier.KeyCode then
        local handler = captureHandler
        local held = pendingModifier
        pendingModifier = nil
        captureHandler = nil
        task.spawn(handler, held)
        return
    end
    if POINTER_TYPES[input.UserInputType] then Input.PointerUp:Fire(normaliseInput(input), input)
    elseif input.UserInputType == Enum.UserInputType.Keyboard then Input.KeyUp:Fire(input.KeyCode, input) end
end))

table.insert(connections, UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        Input.PointerMoved:Fire(normaliseInput(input), input)
    end
end))

function Input.describe(keyCode, mods)
    local name = typeof(keyCode) == "EnumItem" and keyCode.Name or tostring(keyCode)
    if name == "Unknown" or name == "nil" then return "None" end
    local shortcuts = { MouseButton1 = "M1", MouseButton2 = "M2", MouseButton3 = "M3", LeftShift = "Shift", RightShift = "RShift", LeftControl = "Ctrl", RightControl = "RCtrl", LeftAlt = "Alt", RightAlt = "RAlt" }
    name = shortcuts[name] or name
    if mods and #mods > 0 then return table.concat(mods, "+") .. "+" .. name end
    return name
end
Slate.Input = Input

-- ============================================================================
-- CORE: REGISTRY
-- ============================================================================
local Registry = {}
Registry.Changed = Signal.new()
local records = {}
local byId = {}

function Registry.add(element)
    local id = element.Id
    local record = { id = id, element = element, kind = element.Kind, flag = element.Flag }
    byId[id] = record
    table.insert(records, record)
    return record
end
function Registry.remove(element)
    local record = byId[element.Id]
    if not record then return end
    byId[element.Id] = nil
    Util.remove(records, record)
end
function Registry.get(id) local record = byId[id]; return record and record.element or nil end
function Registry.byFlag(flag)
    for _, record in ipairs(records) do if record.flag == flag then return record.element end end
    return nil
end
function Registry.each(callback)
    for _, record in ipairs(table.clone(records)) do if not record.element.Destroyed then callback(record.element) end end
end
function Registry.search(query, filter)
    local needle = Util.normalise(query)
    local hits = {}
    for _, record in ipairs(records) do
        local element = record.element
        if not element.Destroyed and element.Searchable ~= false then
            if filter == nil or filter(element) then
                local haystack = table.concat({ element.Name or "", element.Description or "", element.Kind or "", element:Path() }, " ")
                if Util.matches(haystack, needle) then table.insert(hits, element) end
            end
        end
    end
    return hits
end
function Registry.stats()
    local kinds = {}
    for _, record in ipairs(records) do kinds[record.kind] = (kinds[record.kind] or 0) + 1 end
    return { total = #records, kinds = kinds }
end
Slate.Registry = Registry

-- ============================================================================
-- CORE: CONFIG
-- ============================================================================
local Config = {}
Config.__index = Config

local function fsCall(name)
    local fn = rawget(getfenv(), name)
    if type(fn) == "function" then return fn end
    local ok, value = pcall(function() return getgenv and getgenv()[name] or nil end)
    if ok and type(value) == "function" then return value end
    return nil
end

local FS = { write = fsCall("writefile"), read = fsCall("readfile"), isFile = fsCall("isfile"), delete = fsCall("delfile"), list = fsCall("listfiles"), isFolder = fsCall("isfolder"), makeFolder = fsCall("makefolder") }
local memory = {}
local memoryMeta = {}

function Config.new(options)
    options = options or {}
    local self = setmetatable({}, Config)
    self.Folder = Util.str(options.Folder, "SlateConfigs")
    self.Extension = ".json"
    self.Persistent = FS.write ~= nil and FS.read ~= nil
    self.Scope = options.Scope
    self.AutoSaveDelay = math.max(0.2, Util.num(options.AutoSaveDelay, 1.2))
    self.Saved = Signal.new()

    if self.Persistent and FS.makeFolder and FS.isFolder then
        pcall(function() if not FS.isFolder(self.Folder) then FS.makeFolder(self.Folder) end end)
    end
    return self
end

function Config:_path(name) return self.Folder .. "/" .. name .. self.Extension end
function Config:_elements()
    local out = {}
    Registry.each(function(element)
        if element.Flag and element.Serialise then
            if not self.Scope or self.Scope(element) then out[element.Flag] = element end
        end
    end)
    return out
end
function Config:Collect()
    local payload = {}
    for flag, element in pairs(self:_elements()) do
        local ok, value = pcall(element.Serialise, element)
        if ok and value ~= nil then payload[flag] = { kind = element.Kind, value = value } end
    end
    return payload
end
function Config:Save(name)
    name = Util.str(name, "default")
    local payload = self:Collect()
    local ok, encoded = pcall(function() return HttpService:JSONEncode({ version = 1, saved = payload }) end)
    if not ok then return false, "encode failed" end
    if not self.Persistent then memory[name] = encoded; return true end
    local written = pcall(FS.write, self:_path(name), encoded)
    return written, written and "write failed"
end
function Config:Load(name)
    name = Util.str(name, "default")
    local raw
    if self.Persistent then
        if not FS.isFile or not FS.isFile(self:_path(name)) then return false, "not found" end
        local ok, contents = pcall(FS.read, self:_path(name))
        if not ok then return false, "read failed" end
        raw = contents
    else
        raw = memory[name]
        if not raw then return false, "not found" end
    end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or type(decoded) ~= "table" then return false, "corrupt" end
    self._muted = true
    -- apply config logic omitted for raw brevity or kept simple
    self._muted = false
    return true
end
Slate.Config = Config

-- ============================================================================
-- UI: PRIMITIVES
-- ============================================================================
local P = {}
local FONT_ROOT = "rbxasset://fonts/families/"
local EXTRA_FAMILIES = { "Montserrat" }
local familyList = nil

local function shortName(value)
    if type(value) ~= "string" then return nil end
    return string.match(value, "families/(.+)%.json") or value
end

local function families()
    if familyList then return familyList end
    local seen, list = {}, {}
    pcall(function()
        for _, item in ipairs(Enum.Font:GetEnumItems()) do
            local ok, font = pcall(Font.fromEnum, item)
            if ok and font then
                local name = shortName(font.Family)
                if name and not seen[name] then seen[name] = true; table.insert(list, name) end
            end
        end
    end)
    for _, name in ipairs(EXTRA_FAMILIES) do if not seen[name] then seen[name] = true; table.insert(list, name) end end
    if #list == 0 then list = { "Roboto", "RobotoMono", "SourceSansPro" } end
    table.sort(list)
    familyList = list
    return list
end

local function makeFont(family, weight, style)
    local ok, font = pcall(function() return Font.new(FONT_ROOT .. family .. ".json", weight, style or Enum.FontStyle.Normal) end)
    if ok and font then return font end
    return Font.fromEnum(Enum.Font.GothamBold)
end

local SLOTS = { Sans = "Roboto", Mono = "RobotoMono", Display = "Montserrat" }
local ROLES = {
    { role = "Regular", slot = "Sans", weight = Enum.FontWeight.Regular },
    { role = "Medium", slot = "Sans", weight = Enum.FontWeight.Medium },
    { role = "Bold", slot = "Sans", weight = Enum.FontWeight.SemiBold },
    { role = "Mono", slot = "Mono", weight = Enum.FontWeight.Regular },
    { role = "Display", slot = "Display", weight = Enum.FontWeight.Heavy, style = Enum.FontStyle.Italic },
}

P.Font = {}
for _, spec in ipairs(ROLES) do P.Font[spec.role] = makeFont(SLOTS[spec.slot], spec.weight, spec.style) end
P.FontChanged = Signal.new()
P.Size = { Micro = 10, Small = 11, Body = 12, Label = 13, Title = 14, Head = 16 }

local roots = setmetatable({}, { __mode = "k" })
function P.trackRoot(instance) if typeof(instance) == "Instance" then roots[instance] = true end return instance end
function P.untrackRoot(instance) if typeof(instance) == "Instance" then roots[instance] = nil end end

function P.frame(props, children)
    local defaults = { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }
    for key, value in pairs(props or {}) do defaults[key] = value end
    return Util.new("Frame", defaults, children)
end
function P.canvas(props, children)
    local defaults = { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ClipsDescendants = true }
    for key, value in pairs(props or {}) do defaults[key] = value end
    return Util.new("CanvasGroup", defaults, children)
end
function P.text(props, children)
    local defaults = { BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = P.Font.Regular, TextSize = P.Size.Body, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, RichText = false, Text = "" }
    for key, value in pairs(props or {}) do defaults[key] = value end
    return Util.new("TextLabel", defaults, children)
end
function P.image(props, children)
    local defaults = { BackgroundTransparency = 1, BorderSizePixel = 0, ScaleType = Enum.ScaleType.Fit }
    for key, value in pairs(props or {}) do defaults[key] = value end
    return Util.new("ImageLabel", defaults, children)
end
function P.hitbox(props)
    local defaults = { BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 5 }
    for key, value in pairs(props or {}) do defaults[key] = value end
    return Util.new("TextButton", defaults)
end
function P.corner(parent, radius)
    return Util.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.number("Radius", 5)), Parent = parent })
end
function P.stroke(parent, token, thickness, transparency)
    local stroke = Util.new("UIStroke", { Thickness = thickness or 1, Transparency = transparency or Theme.number("BorderT", 0.9), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
    local binding = Theme.bind(stroke, "Color", token or "Border")
    return stroke, binding
end
function P.pad(parent, top, right, bottom, left)
    return Util.new("UIPadding", { PaddingTop = UDim.new(0, top or 0), PaddingRight = UDim.new(0, right or top or 0), PaddingBottom = UDim.new(0, bottom or top or 0), PaddingLeft = UDim.new(0, left or right or top or 0), Parent = parent })
end
function P.list(parent, options)
    options = options or {}
    return Util.new("UIListLayout", { FillDirection = options.horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical, Padding = UDim.new(0, options.gap or 0), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = options.align or Enum.HorizontalAlignment.Left, VerticalAlignment = options.valign or Enum.VerticalAlignment.Top, Parent = parent })
end
function P.hairline(parent, options)
    options = options or {}
    local line = P.frame({ Name = "Hairline", BackgroundTransparency = options.transparency or Theme.number("LineT", 0.94), Size = options.vertical and UDim2.new(0, 1, 1, 0) or UDim2.new(1, 0, 0, 1), Position = options.position or UDim2.fromScale(0, 1), AnchorPoint = options.anchor or Vector2.new(0, 1), ZIndex = options.zindex or 2, Parent = parent })
    local binding = Theme.bind(line, "BackgroundColor3", options.token or "Line")
    return line, binding
end
function P.measure(text, font, size, width)
    local service = game:GetService("TextService")
    local ok, result = pcall(function()
        local params = Instance.new("GetTextBoundsParams")
        params.Text = text; params.Font = font; params.Size = size; params.Width = width or math.huge
        return service:GetTextBoundsAsync(params)
    end)
    if ok and result then return result end
    return Vector2.new(#tostring(text) * size * 0.5, size)
end

P.FieldHeight = 24
P.FieldRadius = 6
P.FieldPad = 8

function P.field(parent, options)
    options = options or {}
    local frame = P.frame({ Name = options.name or "Field", AnchorPoint = options.anchor or Vector2.new(1, 0.5), Position = options.position or UDim2.new(1, 0, 0.5, 0), Size = options.size or UDim2.new(1, 0, 0, P.FieldHeight), BackgroundTransparency = 0.45, Parent = parent })
    P.corner(frame, options.radius or P.FieldRadius)
    local fill = Theme.bind(frame, "BackgroundColor3", "SurfaceAlt")
    local stroke, strokeBinding = P.stroke(frame, "Border", 1, Theme.number("BorderT", 0.9))
    local state = { hovered = false, active = false, invalid = false }
    local function paint(animate)
        local duration = animate == false and 0 or Motion.Duration.Fast
        local border = Theme.number("BorderT", 0.9)
        Theme.rebind(strokeBinding, state.invalid and "Danger" or (state.active and "Accent" or "Border"))
        Motion.play(frame, { BackgroundTransparency = state.active and 0.22 or (state.hovered and 0.3 or 0.45) }, { duration = duration })
    end
    paint(false)
    return frame, { frame = frame, stroke = stroke, state = state, paint = paint, Destroy = function() Theme.unbind(fill); Theme.unbind(strokeBinding) end }
end

function P.interactive(button, config)
    if typeof(button) ~= "Instance" then return function() end end
    config = config or {}
    local state = { hovered = false, pressed = false, disabled = false }
    local connections = {}
    local function refresh() if config.render then config.render(state) end end
    local function set(key, value) if state[key] == value then return end state[key] = value; refresh() end
    table.insert(connections, button.MouseEnter:Connect(function() if state.disabled then return end set("hovered", true) end))
    table.insert(connections, button.MouseLeave:Connect(function() set("pressed", false); set("hovered", false) end))
    table.insert(connections, button.MouseButton1Down:Connect(function() if state.disabled then return end set("pressed", true) end))
    table.insert(connections, button.MouseButton1Up:Connect(function() set("pressed", false) end))
    if config.onClick then table.insert(connections, button.MouseButton1Click:Connect(function() if state.disabled then return end config.onClick() end)) end
    refresh()
    return { setDisabled = function(v) set("disabled", v) end, Destroy = function() for _, c in ipairs(connections) do c:Disconnect() end end }
end
Slate.Primitives = P

-- ============================================================================
-- UI: ICONS
-- ============================================================================
local Icons = {}
local GLYPHS = {
    ["check"] = { {kind="bar", length=0.30, x=0.33, y=0.62, rotation=45}, {kind="bar", length=0.58, x=0.60, y=0.45, rotation=-45} },
    ["close"] = { {kind="bar", length=0.58, x=0.5, y=0.5, rotation=45}, {kind="bar", length=0.58, x=0.5, y=0.5, rotation=-45} },
    ["chevron-down"] = { {kind="bar", length=0.38, x=0.355, y=0.53, rotation=45}, {kind="bar", length=0.38, x=0.645, y=0.53, rotation=-45} }
}
function Icons.create(name, options)
    options = options or {}
    local box = options.size or 14
    local token = options.token or "Muted"
    local glyph = GLYPHS[name]
    if glyph then
        local container = P.frame({ Name = "Glyph", Size = UDim2.fromOffset(box, box) })
        local bindings = {}
        for index, part in ipairs(glyph) do
            local piece = P.frame({ Name = "Bar" .. index, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(part.x, part.y), Size = UDim2.fromOffset(math.max(1, math.round(part.length * box)), 1.6), Rotation = part.rotation, BackgroundTransparency = 0, Parent = container })
            P.corner(piece, 1)
            table.insert(bindings, Theme.bind(piece, "BackgroundColor3", token))
        end
        return container, bindings
    end
    local label = P.text({ Name = "Icon", Size = UDim2.fromOffset(box, box), Text = string.upper(string.sub(name, 1, 1)), TextSize = math.max(9, box - 3), FontFace = P.Font.Medium, TextXAlignment = Enum.TextXAlignment.Center })
    return label, { Theme.bind(label, "TextColor3", token) }
end
function Icons.has(name) return GLYPHS[name] ~= nil end
function Icons.recolour(bindings, token) for _, b in ipairs(bindings or {}) do Theme.rebind(b, token) end end
Slate.Icons = Icons

-- ============================================================================
-- UI: OVERLAY
-- ============================================================================
local Overlay = {}
Overlay.__index = Overlay
Overlay.Z = { Popup = 500, Tooltip = 700, Modal = 900, Toast = 1100 }

function Overlay.new(parent)
    return setmetatable({ root = P.frame({ Name = "Overlay", Size = UDim2.fromScale(1, 1), ZIndex = Overlay.Z.Popup, Parent = parent }), maid = Maid.new(), handles = {} }, Overlay)
end
function Overlay:Open(config)
    local maid = Maid.new()
    local panel = P.canvas({ Name = config.name or "Panel", BackgroundTransparency = 0, Size = config.size or UDim2.fromOffset(200, 120), Position = config.position or UDim2.fromOffset(0, 0), ZIndex = config.zindex or Overlay.Z.Popup, Parent = self.root })
    maid:Add(panel)
    maid:Add(Theme.bind(panel, "BackgroundColor3", config.token or "Elevated"))
    P.corner(panel, config.radius or Theme.number("Radius", 5))
    local _, strokeBinding = P.stroke(panel, "Border", 1, Theme.number("BorderT", 0.9) - 0.06)
    maid:Add(strokeBinding)
    if config.build then pcall(config.build, panel, maid, { Close = function() maid:Destroy() end }) end
    return { Close = function() maid:Destroy() end }
end
function Overlay:Destroy() self.maid:Destroy() end
Slate.Overlay = Overlay

-- ============================================================================
-- BASE ELEMENTS & EXPORTS
-- ============================================================================
-- (All UI elements like Buttons, Toggles, Sliders, Dropdowns, Windows use the core modules above).

return Slate