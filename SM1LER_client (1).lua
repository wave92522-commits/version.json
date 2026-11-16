--[[
    SM1LER  |  client-side LocalScript (fully local UI)

    Pages: Home, Editor (syntax highlight, tabs, undo/redo), Scripts
    (Local / ScriptBlox hub with filters + pagination / URL loader),
    Console, Settings (2-column grid, language + FPS popups, quick tour),
    Account.

    Run:  Studio -> StarterPlayerScripts (LocalScript)  |  or paste into your runner.
    Toggle window: RightShift or the round "S" button.

    Icons are vector shapes drawn from Frames, so there are no external files or assets:
    everything lives in this one LocalScript.
]]

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UIS                = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local Stats              = game:GetService("Stats")
local HttpService        = game:GetService("HttpService")

local LP = Players.LocalPlayer
local CFG = {
    Name = "SM1LER",
    ToggleKey = Enum.KeyCode.RightShift,
    File = "sm1ler_data.json",
    HubApi = "https://scriptblox.com/api/script/",
    MaxLoad = 3.5,               -- loading screen never lasts longer than this (seconds)
    Version = "1.9.2",           -- bump this on every release (and in version.json on your host)
    Update = {
        ManifestUrl = "https://raw.githubusercontent.com/wave92522-commits/version.json/main/version.json",        -- e.g. https://raw.githubusercontent.com/<you>/<repo>/main/version.json  (empty = updater off)
        ScriptUrl = "",          -- optional fallback if version.json has no "url"
        Folder = "SM1LER",       -- workspace folder where the downloaded build is stored
    },
    Key = {
        Hours = 12,              -- default / legacy key length
        WaitSeconds = 100,       -- LinkVault: first waiting time
        -- three "services"; each one issues keys of its own length (Hours)
        M1 = { Name = "FlashKey",  Hours = 1,  Ads = 2, AdSeconds = 30, ScanSeconds = 15 },
        M2 = { Name = "LinkVault", Hours = 5,  AdsMin = 1, AdsMax = 5, AdSeconds = 15, AfterAdWait = 70 },
        M3 = { Name = "GoldPass",  Hours = 12, AdsMin = 5, AdsMax = 9, Stages = 4, AdSeconds = 20, AfterAdWait = 0 },
        WarnSeconds = 600,       -- warn this long before the key expires (10 minutes)
        BindToUser = false,      -- true = keys only work on the account that created them
        Prefix = "SM1",
        -- CHANGE THIS to your own random text before sharing the script.
        -- Keys are signed with it; a different salt = old keys stop working.
        Salt = "sm1ler-change-this-salt-7Hq2",
    },
    -- Status: shown on Home and sent to Discord. "status" = the injector itself; "detect" = ban/detection risk.
    -- Edit these two lines by hand for a quick manual update, or host the same two fields in version.json
    -- ("status" / "detectStatus") so you can change them without editing or re-publishing the script.
    Status = {
        Status = "ok",         -- "ok" | "updating" | "down"
        Detect = "ok",         -- "ok" | "updating" | "down"
        -- edit these three lines to change what each state shows - anywhere in the UI and in Discord
        Icons = { ok = "🟢", updating = "🟡", down = "🔴" },
        Labels = { ok = { "Work", "Работает" }, updating = { "Updating", "Обновляется" }, down = { "DOWN", "Не работает" } },
    },
    -- AI tab: needs the person's own, free API key (Google AI Studio -> "Get API key", or Groq console).
    -- Leave ApiKey empty here and let people paste their own key in Settings > AI instead (saved per person, DB.ai.key).
    AI = {
        Provider = "gemini",   -- "gemini" | "groq"
        ApiKey = "",
        Model = "gemini-2.5-flash",
        GroqModel = "llama-3.3-70b-versatile",
        Endpoint = "https://generativelanguage.googleapis.com/v1beta/models/",
        GroqEndpoint = "https://api.groq.com/openai/v1/chat/completions",
        System = "You are a helpful assistant inside a Roblox script hub. Keep answers short and plain.",
    },
    -- Discord: posts an embed to a webhook on inject / failure. Leave WebhookUrl empty to turn this off.
    Discord = {
        WebhookUrl = "",             -- https://discord.com/api/webhooks/.../...
        SendOnInject = true,
        SendOnFail = true,
        AvatarUrl = "",
    },
}

local function netGet(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" and #body > 0 then return body end
    local req = request or http_request or (syn and syn.request)
    if req then
        local ok2, r = pcall(req, { Url = url, Method = "GET" })
        if ok2 and type(r) == "table" and r.StatusCode == 200 and type(r.Body) == "string" and #r.Body > 0 then return r.Body end
    end
    return nil
end
local function netPost(url, jsonBody)
    local req = request or http_request or (syn and syn.request)
    if req then
        local ok, r = pcall(req, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = jsonBody })
        if ok and type(r) == "table" and (r.StatusCode or 0) < 300 then return true end
    end
    local ok2 = pcall(function()
        return game:HttpPost(url, jsonBody, Enum.HttpContentType.ApplicationJson)
    end)
    return ok2
end

local UPD, STAT, DISC, BD, hudBar   -- forward-declared: assigned further down, used by code defined earlier (doInject, Home, Settings)
local genv = (getgenv and getgenv()) or _G
if genv.__SM1LER then pcall(genv.__SM1LER) end
local conns, alive = {}, true
local function bind(sig, fn)
    local c = sig:Connect(fn)
    conns[#conns + 1] = c
    return c
end

----------------------------------------------------------------------
-- Persistence
----------------------------------------------------------------------
local function loadDB()
    local ok, data = pcall(function()
        if isfile and readfile and isfile(CFG.File) then
            return HttpService:JSONDecode(readfile(CFG.File))
        end
    end)
    if ok and type(data) == "table" then return data end
    return {}
end
local DB = loadDB()
DB.settings = DB.settings or {}
DB.fav = DB.fav or {}
DB.recent = DB.recent or {}
local DEFAULTS = {
    uiSize = 100, font = 13, lang = "en", pos = "Center", blur = true, anim = true,
    notif = true, streamer = false, topbtn = true, drag = false, afk = false, fps = "60", tour = false,
    snow = false, neon = true, lastPage = "Home",
    autoInject = false, autoExec = false, autoDelay = 1, outMode = "Auto", spamInterval = 0.5, spamCount = 50, spamBurst = 1, spamStopOnError = true,
    hud = true, hudSnow = false, hud24h = true, guiStyle = "sm1ler",
    backdoorScan = false,
}
local S = DB.settings
for k, v in pairs(DEFAULTS) do if S[k] == nil then S[k] = v end end
if not S.winStyleMig then S.guiStyle, S.winStyleMig = "win", true end   -- Volt-style window buttons
if not S.noSnowMig then S.snow, S.hudSnow, S.noSnowMig = false, false, true end   -- snow is off by default now


if not DB.scripts then
local TESTER_SRC = [==[
local env = getfenv()
local names = {"loadstring","getgenv","getrenv","getfenv","setfenv","setclipboard","getclipboard",
 "writefile","readfile","isfile","isfolder","listfiles","makefolder","delfile","appendfile",
 "setfpscap","gethui","request","http_request","Drawing","WebSocket","cloneref","identifyexecutor",
 "getcustomasset","queue_on_teleport","fireclickdetector","firetouchinterest","fireproximityprompt",
 "getconnections","getinstances","getnilinstances","checkcaller","newcclosure","iscclosure",
 "islclosure","getscripts","getloadedmodules","getrawmetatable","setreadonly","isreadonly",
 "hookfunction","hookmetamethod","getnamecallmethod","base64_encode","base64_decode","lz4compress",
 "crypt","debug.getinfo","debug.getupvalue","debug.setupvalue","setthreadidentity","getthreadidentity"}
local pass, fail = 0, 0
for _, n in ipairs(names) do
    local v = env
    for part in string.gmatch(n, "[^%.]+") do v = type(v) == "table" and v[part] or (v == env and env[part] or nil) end
    if v ~= nil then pass = pass + 1; print("✅ " .. n) else fail = fail + 1; print("⛔ " .. n) end
end
print("UNC Summary")
print(("✅ Tested with a %d%% success rate (%d out of %d)"):format(math.floor(pass / #names * 100), pass, #names))
print("⛔ " .. fail .. " tests failed")
]==]
    DB.scripts = {
        { name = "Hello world",     desc = "Send your first message to the console.", src = 'print("Hello, world!")' },
        { name = "Executor Tester", desc = "Check the available runtime functions.",  src = TESTER_SRC },
        { name = "Infinite yield",  desc = "Open Infinite Yield.",
          src = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()' },
    }
end
local SPY_SRC = [==[
-- Simple Spy loader: tries several mirrors (raw.githubusercontent works where github.com/raw redirects do not)
local urls = {
    "https://raw.githubusercontent.com/exxtremestuffs/SimpleSpySource/master/SimpleSpy.lua",
    "https://raw.githubusercontent.com/78n/SimpleSpy/main/SimpleSpyBeta.lua",
}
local lastErr = "no response from server"
for _, u in ipairs(urls) do
    local got, src = pcall(function() return game:HttpGet(u) end)
    if got and type(src) == "string" and #src > 500 then
        local fn, cerr = loadstring(src)
        if fn then
            local ok, rerr = pcall(fn)
            if ok then return end
            lastErr = tostring(rerr)
        else
            lastErr = tostring(cerr)
        end
    else
        lastErr = tostring(src)
    end
end
warn("[Simple Spy] failed to start: " .. lastErr)
]==]
if not DB.seedSpyDex then
    DB.seedSpyDex = true
    DB.scripts = type(DB.scripts) == "table" and DB.scripts or {}
    local function has(n) for _, sc in ipairs(DB.scripts) do if sc.name == n then return true end end return false end
    if not has("Simple Spy") then
        DB.scripts[#DB.scripts + 1] = { name = "Simple Spy", desc = "Remote spy: logs RemoteEvent / RemoteFunction calls.",
            src = SPY_SRC }
    end
    if not has("Dex Explorer") then
        DB.scripts[#DB.scripts + 1] = { name = "Dex Explorer", desc = "Explorer + properties: browse and inspect every instance.",
            src = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/infyiff/backup/main/dex.lua"))()' }
    end
end
if not DB.seedSpyFix2 then
    DB.seedSpyFix2 = true
    for _, sc in ipairs(type(DB.scripts) == "table" and DB.scripts or {}) do
        if sc.name == "Simple Spy" then sc.src = SPY_SRC end
    end
end
local function saveDB()
    pcall(function() if writefile then writefile(CFG.File, HttpService:JSONEncode(DB)) end end)
end

----------------------------------------------------------------------
-- Theme / helpers
----------------------------------------------------------------------
local C = {
    bg = Color3.fromRGB(8, 8, 10), panel = Color3.fromRGB(18, 18, 21), item = Color3.fromRGB(30, 30, 34),
    hover = Color3.fromRGB(52, 52, 58), line = Color3.fromRGB(40, 40, 46), text = Color3.fromRGB(236, 236, 242),
    sub = Color3.fromRGB(135, 135, 148), white = Color3.fromRGB(246, 246, 249), black = Color3.new(0, 0, 0),
    ok = Color3.fromRGB(110, 210, 140), warn = Color3.fromRGB(240, 190, 90), err = Color3.fromRGB(240, 100, 100),
    info = Color3.fromRGB(120, 170, 240),
}
local function new(class, props, children)
    local o, parent = Instance.new(class), nil
    for k, v in pairs(props or {}) do if k == "Parent" then parent = v else o[k] = v end end
    for _, c in ipairs(children or {}) do c.Parent = o end
    if parent then o.Parent = parent end
    return o
end
local function round(r)  return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function stroke(c, t) return new("UIStroke", { Color = c or C.line, Thickness = t or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function pad(p) return new("UIPadding", { PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p), PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p) }) end
local function hlist(p, ha)
    return new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, p or 6),
        SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = ha or Enum.HorizontalAlignment.Left })
end
local function vlist(p)
    return new("UIListLayout", { Padding = UDim.new(0, p or 6), SortOrder = Enum.SortOrder.LayoutOrder })
end
local function tween(o, t, props)
    if S.anim then TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
    else for k, v in pairs(props) do o[k] = v end end
end
local function hex(c)
    local function b(v) return math.floor(v * 255 + 0.5) end
    return string.format("#%02x%02x%02x", b(c.R), b(c.G), b(c.B))
end

----------------------------------------------------------------------
-- Neon borders, snow, time and key crypto
----------------------------------------------------------------------
local FX = { neon = {}, snow = {} }
local function G(en, ru) return S.lang == "ru" and ru or en end

----------------------------------------------------------------------
UPD = {}
local ok_blk1, err_blk1 = pcall(function()
    local U = CFG.Update
    local function vparts(v)
        local t = {}
        for n in string.gmatch(tostring(v or "0"), "%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    function UPD.newer(a, b)
        local x, y = vparts(a), vparts(b)
        for i = 1, math.max(#x, #y) do
            local p, q = x[i] or 0, y[i] or 0
            if p ~= q then return p > q end
        end
        return false
    end
    local function path(n) return U.Folder .. "/" .. n end
    local function filesOk() return (writefile and readfile and isfile) and true or false end
    local httpGet = netGet
    function UPD.enabled() return type(U.ManifestUrl) == "string" and U.ManifestUrl ~= "" end
    -- raw manifest table (adds status / changelog on top of version / url)
    function UPD.manifest()
        if not UPD.enabled() then return nil end
        local sep = string.find(U.ManifestUrl, "?", 1, true) and "&" or "?"
        local body = httpGet(U.ManifestUrl .. sep .. "t=" .. os.time())
        if not body then return nil end
        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        return (ok and type(data) == "table") and data or nil
    end

    -- saved build: returns version, source
    function UPD.cached()
        if not filesOk() then return nil end
        local ok, v, src = pcall(function()
            if isfile(path("version.txt")) and isfile(path("client.lua")) then
                return (string.gsub(readfile(path("version.txt")), "%s+", "")), readfile(path("client.lua"))
            end
        end)
        if ok and type(v) == "string" and v ~= "" and type(src) == "string" and #src > 1000 then return v, src end
        return nil
    end

    function UPD.remote()
        local data = UPD.manifest()
        if data and data.version and ((data.url and data.url ~= "") or U.ScriptUrl ~= "") then
            return { version = tostring(data.version), url = (data.url and data.url ~= "") and data.url or U.ScriptUrl }
        end
        return nil
    end

    -- downloads a build and saves it; returns ok, source
    function UPD.install(m, cb)
        cb = cb or function() end
        cb(0.1)
        local src = httpGet(m.url)
        cb(0.8)
        if not src or #src < 1000 then return false end
        local okc, fn = pcall(function() return loadstring(src) end)
        if not okc or type(fn) ~= "function" then return false end   -- corrupt / 404 page: never save it
        if filesOk() then
            pcall(function()
                if makefolder and isfolder and not isfolder(U.Folder) then makefolder(U.Folder) end
                writefile(path("client.lua"), src)
                writefile(path("version.txt"), m.version)
            end)
        end
        cb(1)
        return true, src
    end

    -- makes sure the injector data exists locally (downloads only when missing)
    function UPD.ensure(progress)
        progress = progress or function() end
        progress(0.05, G("Checking components", "Проверка компонентов"))
        if not UPD.enabled() or not filesOk() then
            progress(1, G("Components ready", "Компоненты готовы"))
            return true
        end
        if UPD.cached() then
            progress(1, G("Components ready", "Компоненты готовы"))
            return true
        end
        progress(0.2, G("Contacting server", "Подключение к серверу"))
        local m = UPD.remote()
        if not m then
            progress(1, G("Server unreachable, will retry later", "Сервер недоступен, повторю позже"))
            return false
        end
        local ok = UPD.install(m, function(p) progress(0.2 + 0.75 * p, G("Downloading injector data", "Загрузка данных инжектора")) end)
        progress(1, ok and G("Components ready", "Компоненты готовы") or G("Download failed, will retry later", "Загрузка не удалась, повторю позже"))
        return ok and true or false
    end

    function UPD.launch(src, ver)
        local okc, fn = pcall(function() return loadstring(src) end)
        if not okc or type(fn) ~= "function" then return false end
        genv.__SM1LER_launched = ver
        task.spawn(fn)   -- the new build tears this one down at its very top
        return true
    end

    -- called at boot: returns true when a newer build was started (this instance must stop)
    function UPD.boot(cb)
        genv.__SM1LER_upd_n = genv.__SM1LER_upd_n or 0
        if genv.__SM1LER_upd_n >= 3 then return false end   -- loop guard
        cb(G("Checking for updates", "Проверка обновлений"), 0.2)
        local cv, csrc = UPD.cached()
        local newestLocal = (cv and UPD.newer(cv, CFG.Version)) and cv or CFG.Version
        local m = UPD.enabled() and UPD.remote() or nil
        if m and UPD.newer(m.version, newestLocal) then
            genv.__SM1LER_upd_n = genv.__SM1LER_upd_n + 1
            cb(G("Downloading update ", "Загрузка обновления ") .. m.version, 0.4)
            local ok, src = UPD.install(m, function(p) cb(G("Downloading update ", "Загрузка обновления ") .. m.version, 0.4 + 0.5 * p) end)
            if ok then
                cb(G("Starting version ", "Запуск версии ") .. m.version, 1)
                if UPD.launch(src, m.version) then return true end
            end
        elseif cv and UPD.newer(cv, CFG.Version) then
            genv.__SM1LER_upd_n = genv.__SM1LER_upd_n + 1
            cb(G("Starting version ", "Запуск версии ") .. cv, 1)
            if UPD.launch(csrc, cv) then return true end
        end
        return false
    end
end) if not ok_blk1 then warn("[blk1] " .. tostring(err_blk1)) end


----------------------------------------------------------------------
-- STATUS: injector / detection status (own CFG values, or overridden by version.json),
-- changelog, and a Discord webhook that posts both whenever the injector connects.
----------------------------------------------------------------------
STAT = { status = CFG.Status.Status, detect = CFG.Status.Detect, changelog = {}, listeners = {} }
function STAT.icon(key) return CFG.Status.Icons[key] or CFG.Status.Icons.ok end
function STAT.label(key) local l = CFG.Status.Labels[key] return l and G(l[1], l[2]) or key end
function STAT.refresh()
    local m = UPD.manifest()
    if type(m) == "table" then
        if type(m.status) == "string" and CFG.Status.Icons[m.status] then STAT.status = m.status end
        if type(m.detectStatus) == "string" and CFG.Status.Icons[m.detectStatus] then STAT.detect = m.detectStatus end
        if type(m.changelog) == "table" then STAT.changelog = m.changelog end
    end
    for _, f in ipairs(STAT.listeners) do pcall(f) end
end

----------------------------------------------------------------------
-- DISCORD: posts an embed with the injector's name, status, detect status and version
-- to a webhook (Settings > Advanced, or CFG.Discord.WebhookUrl). No personal data is sent.
----------------------------------------------------------------------
DISC = {}
function DISC.enabled() return type(CFG.Discord.WebhookUrl) == "string" and string.find(CFG.Discord.WebhookUrl, "^https?://") ~= nil end
function DISC.post(event)
    if not DISC.enabled() then return end
    task.spawn(function()
        local color = STAT.status == "ok" and 0x2ECC71 or (STAT.status == "updating" and 0xF1C40F or 0xE74C3C)
        local desc = STAT.icon(STAT.status) .. " " .. G("Status: ", "Статус: ") .. STAT.label(STAT.status) .. "\n"
            .. STAT.icon(STAT.detect) .. " " .. G("Detection: ", "Детект: ") .. STAT.label(STAT.detect)
        local embed = {
            title = CFG.Name .. " · v" .. CFG.Version,
            description = desc,
            color = color,
            fields = { { name = G("Event", "Событие"), value = tostring(event), inline = true }, { name = "Executor", value = "unknown", inline = true } },
            footer = { text = os.date("%Y-%m-%d %H:%M:%S") },
        }
        pcall(function()
            local ex = "unknown"
            if identifyexecutor then local ok, n = pcall(identifyexecutor) if ok then ex = tostring(n) end end
            embed.fields[2].value = ex
        end)
        local payload = { username = CFG.Name, avatar_url = (CFG.Discord.AvatarUrl ~= "" and CFG.Discord.AvatarUrl) or nil, embeds = { embed } }
        local ok, json = pcall(function() return HttpService:JSONEncode(payload) end)
        if ok then netPost(CFG.Discord.WebhookUrl, json) end
    end)
end

----------------------------------------------------------------------
-- BACKDOOR MODE: a heuristic, metadata-only scan of the live game for suspicious
-- instance names / exposed webhook-looking strings. This is NOT a real antivirus:
-- it cannot read the source of scripts it did not inject, only names and values
-- it can already see. Treat a hit as "worth a manual look", not proof of a backdoor.
----------------------------------------------------------------------
BD = {}
local ok_blk2, err_blk2 = pcall(function()
    local SUS_NAMES = { "backdoor", "rce", "exploit", "grab", "hwid", "crash", "kill_all", "killall", "infect", "payload", "dupe", "ban_", "banall" }
    local WEBHOOK_PAT = "discordapp%.com/api/webhooks"
    local WEBHOOK_PAT2 = "discord%.com/api/webhooks"
    local function suspicious(name)
        local low = string.lower(name)
        for _, w in ipairs(SUS_NAMES) do if string.find(low, w, 1, true) then return "name:" .. w end end
        return nil
    end
    function BD.scan(progress)
        progress = progress or function() end
        local hits, scanned, roots = {}, 0, { workspace, game:GetService("ReplicatedStorage"), game:GetService("Lighting"), game:GetService("StarterGui"), game:GetService("StarterPack") }
        for ri, root in ipairs(roots) do
            progress((ri - 1) / #roots)
            local ok, desc = pcall(function() return root:GetDescendants() end)
            if ok then
                for _, d in ipairs(desc) do
                    scanned = scanned + 1
                    if scanned % 400 == 0 then task.wait() end
                    local why = suspicious(d.Name)
                    if why then hits[#hits + 1] = { path = d:GetFullName(), why = why } end
                    if d:IsA("StringValue") or d:IsA("ModuleScript") then
                        local ok2, v = pcall(function() return d:IsA("StringValue") and d.Value or nil end)
                        if ok2 and type(v) == "string" and (string.find(v, WEBHOOK_PAT) or string.find(v, WEBHOOK_PAT2)) then
                            hits[#hits + 1] = { path = d:GetFullName(), why = "webhook string" }
                        end
                    end
                    if #hits > 60 then break end
                end
            end
            if #hits > 60 then break end
        end
        progress(1)
        return hits, scanned
    end
end) if not ok_blk2 then warn("[blk2] " .. tostring(err_blk2)) end

local function hexToColor(h)
    h = string.gsub(tostring(h or ""), "#", "")
    if #h ~= 6 then return nil end
    local r, g, b = tonumber(string.sub(h, 1, 2), 16), tonumber(string.sub(h, 3, 4), 16), tonumber(string.sub(h, 5, 6), 16)
    if not (r and g and b) then return nil end
    return Color3.fromRGB(r, g, b)
end
local TD = {   -- theme defaults
    mode = "none", color = "#0a0a0c", g1 = "#000000", g2 = "#10102a", g3 = "", angle = 90,
    image = "", imgScale = "Crop", imgAlpha = 0.25, dim = 0.35, panelAlpha = 0,
    neonA = "#ffffff", neonB = "#ffffff", neonSpeed = 30, neonThick = 1.5, rainbow = false,
    radius = 1, borderScale = 1, font = "Gotham", textScale = 1,   -- interface style
    -- layout (a theme is a full interface configuration)
    winW = 880, winH = 450,
    sbPos = "left", sbW = 196, sbLabels = true, sbSplit = false, sbGap = 10, sbFooter = true, sbCollapse = true,
    titleBar = true, titleH = 38, ctrlLoc = "title",
    edTree = true, edCrumb = true, edStatus = true, tabStyle = "flat",
    home = { account = true, plan = true, license = true, version = true, exec = true, news = true },
    navOff = {},
    brandName = "", brandLogo = "",   -- "" = keep the current name / logo
    watermark = false, panelDepth = 0, uiGrid = false, colorfulIcons = false,
    showTitleVersion = false, logoIcon = true, logoText = true,
    navLabelMode = "both", treeSide = "left", toolbarPos = "top",
}
local function cpv(v)
    if type(v) == "table" then
        local t = {}
        for a, b in pairs(v) do t[a] = cpv(b) end
        return t
    end
    return v
end
S.theme = type(S.theme) == "table" and S.theme or {}
for k, v in pairs(TD) do if S.theme[k] == nil then S.theme[k] = cpv(v) end end
local TH = S.theme
local neonTrans, neonSeq
local ok_blk3, err_blk3 = pcall(function()
local RAINBOW_SEQ = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)), ColorSequenceKeypoint.new(1 / 6, Color3.fromHSV(1 / 6, 1, 1)),
    ColorSequenceKeypoint.new(2 / 6, Color3.fromHSV(2 / 6, 1, 1)), ColorSequenceKeypoint.new(3 / 6, Color3.fromHSV(3 / 6, 1, 1)),
    ColorSequenceKeypoint.new(4 / 6, Color3.fromHSV(4 / 6, 1, 1)), ColorSequenceKeypoint.new(5 / 6, Color3.fromHSV(5 / 6, 1, 1)),
    ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1)) })
local COMET_SEQ = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0.82),
    NumberSequenceKeypoint.new(0.55, 0.82), NumberSequenceKeypoint.new(1, 0) })
local FULL_SEQ = NumberSequence.new(0)
function neonTrans() return TH.rainbow and FULL_SEQ or COMET_SEQ end
function neonSeq()
    if TH.rainbow then return RAINBOW_SEQ end
    local a = hexToColor(TH.neonA) or Color3.new(1, 1, 1)
    local b = hexToColor(TH.neonB) or a
    return ColorSequence.new(a, b)
end
end) if not ok_blk3 then warn("[blk3] " .. tostring(err_blk3)) end
-- Streamer mode state (names are random, beautiful and only change what is shown on YOUR screen)
local Stream = { display = nil, handle = nil, active = false, hooked = setmetatable({}, { __mode = "k" }), conns = {}, watch = {}, humOrig = nil }
local applyStreamer
local function rerollNames()
    local adj = { "Velvet", "Neon", "Silent", "Crimson", "Lunar", "Frost", "Amber", "Cosmic", "Mystic", "Golden", "Shadow", "Solar", "Violet", "Echo",
        "Nova", "Pixel", "Misty", "Azure", "Ivory", "Scarlet", "Electric", "Gentle" }
    local noun = { "Fox", "Raven", "Comet", "Wolf", "Phoenix", "Lynx", "Falcon", "Orchid", "Tiger", "Aurora", "Panda", "Cipher", "Ember", "Willow", "Drift",
        "Zephyr", "Sparrow", "Nebula", "Otter", "Meteor", "Lotus", "Hawk" }
    local a, b = adj[math.random(#adj)], noun[math.random(#noun)]
    Stream.display = a .. b
    Stream.handle = a .. b .. tostring(math.random(10, 99))
end
rerollNames()
local function dispName() return (S.streamer and Stream.display) or LP.DisplayName end
local function userName() return (S.streamer and Stream.handle) or LP.Name end
local function userIdText() return S.streamer and "••••••••" or tostring(LP.UserId) end
local function tw2(o, t, props, style, dir)
    TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end
local function neonStroke(thick, speed, main)
    local g = new("UIGradient", {
        Color = neonSeq(),
        Transparency = neonTrans(),
    })
    local st = new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = thick or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, { g })
    FX.neon[#FX.neon + 1] = { g = g, speed = speed or 40, st = st, main = main }
    return st
end
local function makeSnow(parent, count, maxSize, watch)
    local holder = new("Frame", { Parent = parent, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, BorderSizePixel = 0, Active = false })
    local flakes = {}
    for i = 1, count do
        local sz = math.random(2, maxSize or 5)
        local f = new("Frame", {
            Parent = holder, Size = UDim2.fromOffset(sz, sz), BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.2 + math.random() * 0.5, BorderSizePixel = 0,
        }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
        flakes[i] = { f = f, x = math.random(), y = math.random(), sp = 0.035 + (sz / 5) * 0.06 + math.random() * 0.03,
            sw = math.random() * 6.28, sa = 0.008 + math.random() * 0.02 }
    end
    local obj = { holder = holder, flakes = flakes, watch = watch, always = false }
    FX.snow[#FX.snow + 1] = obj
    return obj
end
local ok_blk4, err_blk4 = pcall(function()
    local skip, snowT = 0, 0
    bind(RunService.Heartbeat, function(dt)
        for i = #FX.neon, 1, -1 do
            local n = FX.neon[i]
            if n.g:IsDescendantOf(game) then n.g.Rotation = (n.g.Rotation + dt * n.speed) % 360
            else table.remove(FX.neon, i) end
        end
        skip = skip + 1
        if skip % 2 == 0 then
            snowT = snowT + dt * 2
            for i = #FX.snow, 1, -1 do
                local sn = FX.snow[i]
                if not sn.holder:IsDescendantOf(game) then
                    table.remove(FX.snow, i)
                elseif sn.holder.Visible and (sn.always or S.snow ~= false) and (not sn.watch or sn.watch.Visible) then
                    for _, f in ipairs(sn.flakes) do
                        f.y = f.y + f.sp * dt * 2
                        if f.y > 1.05 then f.y = -0.05 f.x = math.random() end
                        f.f.Position = UDim2.fromScale(f.x + math.sin(snowT * 0.5 + f.sw) * f.sa, f.y)
                    end
                end
            end
        end
    end)
end) if not ok_blk4 then warn("[blk4] " .. tostring(err_blk4)) end

local unlocked = false
local KEY = { value = nil, expires = 0 }
local function nowT()
    local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
    if ok and type(t) == "number" and t > 1e9 then return t end
    return os.time()
end
local function fmtDur(sec)
    sec = math.max(0, math.floor(sec))
    local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%02d:%02d", m, sec % 60)
end
local function keyLeftText()
    if not KEY.value then return "-" end
    return fmtDur(KEY.expires - nowT())
end

local makeKey, validateKey
local ok_blk5, err_blk5 = pcall(function()
    local KC = CFG.Key
    local B32 = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local function mul32(a, b)
        local ah, al = math.floor(a / 65536), a % 65536
        return (al * b + ((ah * b) % 65536) * 65536) % 4294967296
    end
    local function h32(str, seed)
        local h = seed
        for i = 1, #str do h = mul32(bit32.bxor(h, string.byte(str, i)), 16777619) end
        h = bit32.bxor(h, bit32.rshift(h, 15))
        h = mul32(h, 2246822519)
        h = bit32.bxor(h, bit32.rshift(h, 13))
        h = mul32(h, 3266489917)
        return bit32.bxor(h, bit32.rshift(h, 16))
    end
    local function enc32(n, len)
        local t = {}
        for i = len, 1, -1 do
            local d = n % 32
            t[i] = string.sub(B32, d + 1, d + 1)
            n = (n - d) / 32
        end
        return table.concat(t)
    end
    local function dec32(str)
        local n = 0
        for i = 1, #str do
            local p = string.find(B32, string.sub(str, i, i), 1, true)
            if not p then return nil end
            n = n * 32 + (p - 1)
        end
        return n
    end
    local TIERS = { [0] = KC.Hours, [1] = KC.M1.Hours, [2] = KC.M2.Hours, [3] = KC.M3.Hours }   -- tier lives in the top bits of the nonce
    local function sign(issuedMin, nonce)
        local base = KC.Salt .. ":" .. issuedMin .. ":" .. nonce .. (KC.BindToUser and (":" .. LP.UserId) or "")
        local a = h32(base, 2166136261)
        local b = h32(base .. KC.Salt, 3735928559)
        return enc32((a % 33554432) * 1024 + (b % 1024), 7)
    end
    local function fmt(raw) return string.sub(raw, 1, 3) .. "-" .. string.sub(raw, 4, 8) .. "-" .. string.sub(raw, 9, 13) .. "-" .. string.sub(raw, 14, 20) end
    function makeKey(tier)
        tier = (TIERS[tier] and tier) or 0
        local issuedMin = math.floor(nowT() / 60)
        local nonce = tier * 8388608 + Random.new():NextInteger(0, 8388607)
        local raw = KC.Prefix .. enc32(issuedMin, 5) .. enc32(nonce, 5) .. sign(issuedMin, nonce)
        return fmt(raw), issuedMin * 60 + TIERS[tier] * 3600
    end
    function validateKey(str)
        if type(str) ~= "string" then return false, "format" end
        local s2 = string.upper((string.gsub(str, "[^%w]", "")))
        if #s2 ~= 20 or string.sub(s2, 1, 3) ~= KC.Prefix then return false, "format" end
        local issued, nonce = dec32(string.sub(s2, 4, 8)), dec32(string.sub(s2, 9, 13))
        if not issued or not nonce then return false, "format" end
        if sign(issued, nonce) ~= string.sub(s2, 14, 20) then return false, "sig" end
        local hrs = TIERS[math.floor(nonce / 8388608)] or KC.Hours
        local t, exp = nowT(), issued * 60 + hrs * 3600
        if issued * 60 > t + 300 then return false, "clock" end
        if t >= exp then return false, "expired" end
        return true, exp, fmt(s2), math.floor(nonce / 8388608)
    end
end) if not ok_blk5 then warn("[blk5] " .. tostring(err_blk5)) end

----------------------------------------------------------------------
-- Icons (vector, drawn from Frames - no external assets)
----------------------------------------------------------------------
local icon
local ok_blk6, err_blk6 = pcall(function()
local ICONS = {
home={{"l",36,132,128,48,20},{"l",128,48,220,132,20},{"l",66,116,66,212,20},{"l",66,212,190,212,20},{"l",190,212,190,116,20},{"l",112,212,112,156,20},{"l",112,156,144,156,20},{"l",144,156,144,212,20}},
pencil={{"l",180,58,204,82,20},{"l",204,82,100,186,20},{"l",100,186,60,196,20},{"l",60,196,70,156,20},{"l",70,156,180,58,20},{"l",150,88,174,112,20}},
code={{"l",92,76,40,128,20},{"l",40,128,92,180,20},{"l",164,76,216,128,20},{"l",216,128,164,180,20},{"l",146,60,110,196,20}},
terminal={{"r",30,46,226,210,30,20},{"l",70,96,108,128,20},{"l",108,128,70,160,20},{"l",128,164,180,164,20}},
gear={{"l",194,128,226,128,34},{"l",175,175,197,197,34},{"l",128,194,128,226,34},{"l",81,175,59,197,34},{"l",62,128,30,128,34},{"l",81,81,59,59,34},{"l",128,62,128,30,34},{"l",175,81,197,59,34},{"c",128,128,72,22,0},{"c",128,128,26,18,0}},
user={{"c",128,86,42,20,0},{"l",44,234,45,219,20},{"l",45,219,49,205,20},{"l",49,205,55,192,20},{"l",55,192,64,180,20},{"l",64,180,74,170,20},{"l",74,170,86,161,20},{"l",86,161,99,155,20},{"l",99,155,113,151,20},{"l",113,151,128,150,20},{"l",128,150,143,151,20},{"l",143,151,157,155,20},{"l",157,155,170,161,20},{"l",170,161,182,170,20},{"l",182,170,192,180,20},{"l",192,180,201,192,20},{"l",201,192,207,205,20},{"l",207,205,211,219,20},{"l",211,219,212,234,20}},
play={{"f",84,52,91,62},{"f",84,60,104,70},{"f",84,68,118,78},{"f",84,76,131,86},{"f",84,84,145,94},{"f",84,92,158,102},{"f",84,100,172,110},{"f",84,108,185,118},{"f",84,116,199,126},{"f",84,124,212,134},{"f",84,132,199,142},{"f",84,140,185,150},{"f",84,148,172,158},{"f",84,156,158,166},{"f",84,164,145,174},{"f",84,172,131,182},{"f",84,180,118,190},{"f",84,188,104,198},{"f",84,196,91,206},{"l",84,52,84,204,16},{"l",84,204,212,128,16},{"l",212,128,84,52,16}},
star={{"l",128,28,154,96,16},{"l",154,96,227,100,16},{"l",227,100,170,146,16},{"l",170,146,189,216,16},{"l",189,216,128,176,16},{"l",128,176,67,216,16},{"l",67,216,86,146,16},{"l",86,146,29,100,16},{"l",29,100,102,96,16},{"l",102,96,128,28,16}},
stard={{"f",126,28,130,38},{"f",123,36,133,46},{"f",120,44,136,54},{"f",117,52,139,62},{"f",114,60,142,70},{"f",111,68,145,78},{"f",108,76,148,86},{"f",105,84,151,94},{"f",102,92,154,102},{"f",34,100,222,110},{"f",44,108,212,118},{"f",54,116,202,126},{"f",64,124,192,134},{"f",74,132,182,142},{"f",84,140,172,150},{"f",84,148,172,158},{"f",82,156,174,166},{"f",80,164,176,174},{"f",78,172,128,182},{"f",128,172,178,182},{"f",76,180,116,190},{"f",140,180,180,190},{"f",73,188,104,198},{"f",152,188,183,198},{"f",71,196,91,206},{"f",165,196,185,206},{"f",69,204,79,214},{"f",177,204,187,214},{"f",67,212,67,222},{"f",189,212,189,222},{"l",128,28,154,96,16},{"l",154,96,227,100,16},{"l",227,100,170,146,16},{"l",170,146,189,216,16},{"l",189,216,128,176,16},{"l",128,176,67,216,16},{"l",67,216,86,146,16},{"l",86,146,29,100,16},{"l",29,100,102,96,16},{"l",102,96,128,28,16}},
trash={{"l",46,74,210,74,20},{"l",104,74,104,44,20},{"l",104,44,152,44,20},{"l",152,44,152,74,20},{"l",66,74,78,212,20},{"l",78,212,178,212,20},{"l",178,212,190,74,20},{"l",112,108,112,180,16},{"l",144,108,144,180,16}},
undo={{"l",214,128,44,128,20},{"l",100,72,44,128,20},{"l",44,128,100,184,20}},
redo={{"l",42,128,212,128,20},{"l",156,72,212,128,20},{"l",212,128,156,184,20}},
copy={{"l",92,88,92,40,20},{"l",92,40,210,40,20},{"l",210,40,210,168,20},{"l",210,168,168,168,20},{"r",46,88,168,216,22,20}},
plus={{"l",128,48,128,208,20},{"l",48,128,208,128,20}},
x={{"l",64,64,192,192,20},{"l",192,64,64,192,20}},
save={{"l",48,48,182,48,20},{"l",182,48,208,74,20},{"l",208,74,208,208,20},{"l",208,208,48,208,20},{"l",48,208,48,48,20},{"l",84,48,84,98,20},{"l",84,98,162,98,20},{"l",162,98,162,48,20},{"l",84,208,84,150,20},{"l",84,150,172,150,20},{"l",172,150,172,208,20}},
paste={{"r",48,64,208,224,22,20},{"r",92,34,164,86,14,20},{"l",88,134,168,134,16},{"l",88,176,150,176,16}},
search={{"c",112,112,64,20,0},{"l",160,160,212,212,24}},
down={{"l",58,96,128,166,20},{"l",128,166,198,96,20}},
left={{"l",162,54,90,128,20},{"l",90,128,162,202,20}},
right={{"l",94,54,166,128,20},{"l",166,128,94,202,20}},
filter={{"l",44,70,212,70,14},{"c",92,70,22,14,1},{"l",44,128,212,128,14},{"c",164,128,22,14,1},{"l",44,186,212,186,14},{"c",112,186,22,14,1}},
phone={{"r",76,28,180,228,26,20},{"l",112,198,144,198,16}},
globe={{"c",128,128,92,20,0},{"l",36,128,220,128,16},{"l",180,128,178,152,16},{"l",178,152,173,174,16},{"l",173,174,165,193,16},{"l",165,193,154,208,16},{"l",154,208,141,217,16},{"l",141,217,128,220,16},{"l",128,220,115,217,16},{"l",115,217,102,208,16},{"l",102,208,91,193,16},{"l",91,193,83,174,16},{"l",83,174,78,152,16},{"l",78,152,76,128,16},{"l",76,128,78,104,16},{"l",78,104,83,82,16},{"l",83,82,91,63,16},{"l",91,63,102,48,16},{"l",102,48,115,39,16},{"l",115,39,128,36,16},{"l",128,36,141,39,16},{"l",141,39,154,48,16},{"l",154,48,165,63,16},{"l",165,63,173,82,16},{"l",173,82,178,104,16},{"l",178,104,180,128,16}},
refresh={{"l",201,170,186,189,20},{"l",186,189,167,202,20},{"l",167,202,145,210,20},{"l",145,210,121,212,20},{"l",121,212,99,207,20},{"l",99,207,78,195,20},{"l",78,195,61,179,20},{"l",61,179,50,158,20},{"l",50,158,44,135,20},{"l",44,135,46,112,20},{"l",46,112,53,90,20},{"l",53,90,67,70,20},{"l",67,70,85,56,20},{"l",85,56,107,47,20},{"l",107,47,130,44,20},{"l",130,44,154,48,20},{"l",154,48,175,58,20},{"l",175,58,192,74,20},{"l",212,44,212,100,20},{"l",212,100,156,100,20}},
info={{"c",128,128,92,20,0},{"c",128,84,9,4,1},{"l",128,122,128,184,20}},
server={{"r",36,46,220,112,20,20},{"r",36,144,220,210,20,20},{"c",76,79,8,2,1},{"c",76,177,8,2,1}},
check={{"l",48,136,104,190,20},{"l",104,190,210,74,20}},
list={{"c",52,70,9,2,1},{"l",90,70,212,70,16},{"c",52,128,9,2,1},{"l",90,128,212,128,16},{"c",52,186,9,2,1},{"l",90,186,212,186,16}},
bolt={{"l",152,30,70,142,16},{"l",70,142,126,142,16},{"l",126,142,104,226,16},{"l",104,226,190,106,16},{"l",190,106,134,106,16},{"l",134,106,152,30,16}},
boltfill={{"f",154.7,18,155.8,22},{"f",152.1,22,155.5,26},{"f",149.4,26,155.2,30},{"f",146.8,30,154.9,34},{"f",144.2,34,154.6,38},{"f",141.6,38,154.3,42},{"f",138.9,42,154,46},{"f",136.3,46,153.7,50},{"f",133.7,50,153.4,54},{"f",131.1,54,153.1,58},{"f",128.4,58,152.8,62},{"f",125.8,62,152.5,66},{"f",123.2,66,152.2,70},{"f",120.6,70,151.8,74},{"f",117.9,74,151.5,78},{"f",115.3,78,151.2,82},{"f",112.7,82,150.9,86},{"f",110.1,86,150.6,90},{"f",107.4,90,150.3,94},{"f",104.8,94,208,98},{"f",102.2,98,205,102},{"f",99.6,102,201.9,106},{"f",96.9,106,198.9,110},{"f",94.3,110,195.8,114},{"f",91.7,114,192.8,118},{"f",89.1,118,189.7,122},{"f",86.4,122,186.7,126},{"f",83.8,126,183.7,130},{"f",81.2,130,180.6,134},{"f",78.6,134,177.6,138},{"f",75.9,138,174.5,142},{"f",73.3,142,171.5,146},{"f",123.5,146,168.5,150},{"f",122.4,150,165.4,154},{"f",121.4,154,162.4,158},{"f",120.3,158,159.3,162},{"f",119.3,162,156.3,166},{"f",118.3,166,153.2,170},{"f",117.2,170,150.2,174},{"f",116.2,174,147.2,178},{"f",115.1,178,144.1,182},{"f",114.1,182,141.1,186},{"f",113,186,138,190},{"f",112,190,135,194},{"f",111,194,131.9,198},{"f",109.9,198,128.9,202},{"f",108.9,202,125.9,206},{"f",107.8,206,122.8,210},{"f",106.8,210,119.8,214},{"f",105.7,214,116.7,218},{"f",104.7,218,113.7,222},{"f",103.7,222,110.6,226},{"f",102.6,226,107.6,230},{"f",101.6,230,104.6,234},{"f",100.5,234,101.5,238}},
move={{"l",128,40,128,216,20},{"l",40,128,216,128,20},{"l",102,66,128,40,16},{"l",128,40,154,66,16},{"l",102,190,128,216,16},{"l",128,216,154,190,16},{"l",66,102,40,128,16},{"l",40,128,66,154,16},{"l",190,102,216,128,16},{"l",216,128,190,154,16}},
book={{"r",40,48,216,208,18,20},{"l",128,48,128,208,16},{"l",70,100,104,100,14},{"l",152,100,186,100,14}}
}

local function drawIcon(parent, prims, k, color)
    for _, p in ipairs(prims) do
        local t = p[1]
        if t == "l" then
            local x1, y1, x2, y2 = p[2] * k, p[3] * k, p[4] * k, p[5] * k
            local w = math.max(1.5, p[6] * k * 1.1)
            local dx, dy = x2 - x1, y2 - y1
            new("Frame", {
                Parent = parent, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
                Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + w, w), Rotation = math.deg(math.atan2(dy, dx)),
                BackgroundColor3 = color, BorderSizePixel = 0,
            }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
        elseif t == "f" then
            new("Frame", {
                Parent = parent, Position = UDim2.fromOffset(p[2] * k, p[3] * k),
                Size = UDim2.fromOffset(math.max(1, (p[4] - p[2]) * k), math.max(1, (p[5] - p[3]) * k)),
                BackgroundColor3 = color, BorderSizePixel = 0,
            })
        elseif t == "c" then
            local r, w = p[4] * k, math.max(1.5, p[5] * k * 1.1)
            if p[6] == 1 then
                new("Frame", {
                    Parent = parent, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p[2] * k, p[3] * k),
                    Size = UDim2.fromOffset(r * 2, r * 2), BackgroundColor3 = color, BorderSizePixel = 0,
                }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
            else
                local d = math.max(1, r * 2 - w)
                new("Frame", {
                    Parent = parent, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p[2] * k, p[3] * k),
                    Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1, BorderSizePixel = 0,
                }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), new("UIStroke", { Color = color, Thickness = w }) })
            end
        elseif t == "r" then
            local w = math.max(1.5, p[7] * k * 1.1)
            new("Frame", {
                Parent = parent, AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromOffset((p[2] + p[4]) / 2 * k, (p[3] + p[5]) / 2 * k),
                Size = UDim2.fromOffset(math.max(1, (p[4] - p[2]) * k - w), math.max(1, (p[5] - p[3]) * k - w)),
                BackgroundTransparency = 1, BorderSizePixel = 0,
            }, { new("UICorner", { CornerRadius = UDim.new(0, math.max(1, p[6] * k)) }), new("UIStroke", { Color = color, Thickness = w }) })
        end
    end
end
function icon(parent, name, px, color)
    local box = new("Frame", { Parent = parent, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(px, px) })
    drawIcon(box, ICONS[name] or ICONS.info, px / 256, color or C.text)
    return box
end
end) if not ok_blk6 then warn("[blk6] " .. tostring(err_blk6)) end
local function tint(o, c)
    for _, d in ipairs(o:GetDescendants()) do
        if d:IsA("UIStroke") then d.Color = c
        elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then d.BackgroundColor3 = c end
    end
end
local function centered(o)
    o.AnchorPoint = Vector2.new(0.5, 0.5)
    o.Position = UDim2.fromScale(0.5, 0.5)
    return o
end

----------------------------------------------------------------------
-- i18n
----------------------------------------------------------------------
local I18N
local ok_blk7, err_blk7 = pcall(function()
local KEYS = { "Home", "Editor", "Scripts", "Console", "Settings", "Account", "Run", "Save", "Clear", "Search", "Language" }
local function pack(t) local r = {} for i, k in ipairs(KEYS) do r[k] = t[i] end return r end
I18N = {
    ru = pack({ "Главная", "Редактор", "Скрипты", "Консоль", "Настройки", "Аккаунт", "Запуск", "Сохранить", "Очистить", "Поиск", "Язык" }),
    es = pack({ "Inicio", "Editor", "Scripts", "Consola", "Ajustes", "Cuenta", "Ejecutar", "Guardar", "Limpiar", "Buscar", "Idioma" }),
    de = pack({ "Start", "Editor", "Skripte", "Konsole", "Einstellungen", "Konto", "Ausführen", "Speichern", "Leeren", "Suche", "Sprache" }),
    fr = pack({ "Accueil", "Éditeur", "Scripts", "Console", "Réglages", "Compte", "Exécuter", "Enregistrer", "Effacer", "Recherche", "Langue" }),
    pt = pack({ "Início", "Editor", "Scripts", "Console", "Configurações", "Conta", "Executar", "Salvar", "Limpar", "Buscar", "Idioma" }),
    pl = pack({ "Start", "Edytor", "Skrypty", "Konsola", "Ustawienia", "Konto", "Uruchom", "Zapisz", "Wyczyść", "Szukaj", "Język" }),
    vi = pack({ "Trang chủ", "Trình soạn thảo", "Tập lệnh", "Bảng điều khiển", "Cài đặt", "Tài khoản", "Chạy", "Lưu", "Xóa", "Tìm kiếm", "Ngôn ngữ" }),
}
end) if not ok_blk7 then warn("[blk7] " .. tostring(err_blk7)) end
for k, v in pairs({
    Paste = "Вставить", Edit = "Правка", Saved = "Сохранённые", Favorites = "Избранное", Recent = "Недавние",
    All = "Все", Errors = "Ошибки", Warnings = "Предупреждения", Output = "Вывод", Filters = "Фильтры",
    ["Quick tour"] = "Быстрый тур", ["Welcome back"] = "С возвращением", Expires = "Истекает", Never = "Никогда",
    ["Quick scripts"] = "Быстрые скрипты", Player = "Игрок", Game = "Игра", Players = "Игроки",
    ["UI Size"] = "Размер UI", ["Editor font"] = "Шрифт редактора", ["Window position"] = "Позиция окна",
    ["Background blur"] = "Размытие фона", Animations = "Анимации", Notifications = "Уведомления",
    ["Streamer mode"] = "Режим стримера", ["Top bar button"] = "Кнопка сверху", ["Draggable window"] = "Перетаскивание",
    ["Anti-AFK"] = "Анти-AFK", ["FPS cap"] = "Лимит FPS", Server = "Сервер", Rejoin = "Перезайти",
    ["Server hop"] = "Смена сервера", ["Small server"] = "Малый сервер", Center = "Центр", Top = "Сверху",
    Bottom = "Снизу", ["Follow on"] = "Следить: вкл", ["Follow off"] = "Следить: выкл", ["Save all"] = "Сохранить всё",
    Apply = "Применить", Reset = "Сброс", Sort = "Сортировка", ["Only show"] = "Показывать только",
    Latest = "Новые", Updated = "Обновлённые", ["Top views"] = "Популярные", ["No key"] = "Без ключа",
    Universal = "Универсальные", Unpatched = "Рабочие", Verified = "Проверенные", Next = "Далее", Skip = "Пропустить",
}) do I18N.ru[k] = v end

for k, v in pairs({
    ["Snow effect"] = "Снег", ["Neon borders"] = "Неоновые рамки", Start = "Старт", Copy = "Копировать",
    Activate = "Активировать", Verify = "Проверить", Continue = "Продолжить", ["Renew key"] = "Обновить ключ",
    ["Forget key"] = "Забыть ключ",
    ["Press INJECT first"] = "Сначала нажми INJECT", Injected = "Инжект выполнен", ["Editor is empty"] = "Редактор пуст",
    ["Inject failed: loadstring unavailable"] = "Ошибка: loadstring недоступен", ["Auto INJECT"] = "Авто-INJECT",
    ["Stop spam on error"] = "Стоп спама при ошибке", ["Spam interval"] = "Интервал спама", ["Spam count"] = "Кол-во повторов",
    ["Spam burst"] = "Пачка за раз", Injector = "Инжектор", Theme = "Тема", Background = "Фон", None = "Нет", Color = "Цвет",
    Gradient = "Градиент", Image = "Картинка", Presets = "Пресеты", Crop = "Заполнить", Fit = "Вписать", Stretch = "Растянуть",
    Tile = "Плитка", ["Image opacity"] = "Прозрачность картинки", ["Darkness"] = "Затемнение", ["Panel transparency"] = "Прозрачность панелей",
    ["Neon border"] = "Неоновая рамка", ["Neon color A"] = "Цвет неона A", ["Neon color B"] = "Цвет неона B", ["Neon speed"] = "Скорость неона",
    ["Neon thickness"] = "Толщина неона", ["Color 1"] = "Цвет 1", ["Color 2"] = "Цвет 2", ["Color 3 (optional)"] = "Цвет 3 (необяз.)",
    ["Roblox console"] = "Консоль Roblox", ["Test F9 output"] = "Проверка вывода F9", ["This game"] = "Эта игра", Test = "Тест",
    Info = "Инфо", ["Rainbow neon"] = "Радужный неон", ["Auto exec"] = "Автозапуск скриптов", ["Auto exec delay"] = "Задержка автозапуска",
    ["HUD bar"] = "Панель HUD", ["HUD snow"] = "Снег на панели", ["24h clock"] = "24-часовой формат", ["GUI style"] = "Стиль окна",
    ["Reroll name"] = "Новый ник", Reroll = "Сменить", Performance = "Производительность", Environment = "Окружение", Session = "Сессия",
    Angle = "Угол", Load = "Загрузить", Apply = "Применить", ["Pick color"] = "Выбор цвета", Reset = "Сброс",
}) do I18N.ru[k] = v end

local function T(key)
    local d = I18N[S.lang]
    return (d and d[key]) or key
end
local trList = {}
local function reg(obj, key, prefix)
    obj.Text = (prefix or "") .. T(key)
    trList[#trList + 1] = { obj, key, prefix }
end
local function applyLang()
    for _, p in ipairs(trList) do
        if p[1] and p[1].Parent then p[1].Text = (p[3] or "") .. T(p[2]) end
    end
end

----------------------------------------------------------------------
-- Root
----------------------------------------------------------------------
local gui = new("ScreenGui", {
    Name = "SM1LER", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui"),
})
local blur = new("BlurEffect", { Size = 0, Parent = game:GetService("Lighting") })

----------------------------------------------------------------------
-- BRANDING: custom name + logo (letter / emoji / image)
----------------------------------------------------------------------
local BR = { logos = {}, defaultName = "SM1LER" }
local ok_blk8, err_blk8 = pcall(function()
    DB.brand = type(DB.brand) == "table" and DB.brand or {}
    local function trim(t) return (string.gsub(tostring(t or ""), "^%s*(.-)%s*$", "%1")) end
    local function replaceWord(text, old, new)
        local out, i = {}, 1
        while true do
            local a, b = string.find(text, old, i, true)
            if not a then out[#out + 1] = string.sub(text, i) break end
            local before, after = string.sub(text, a - 1, a - 1), string.sub(text, b + 1, b + 1)
            local isWord = not string.find(before, "[%w_]") and not string.find(after, "[%w_]")
            out[#out + 1] = string.sub(text, i, a - 1) .. (isWord and new or old)
            i = b + 1
        end
        return table.concat(out)
    end
    function BR.resolve(spec)
        if type(spec) ~= "string" or spec == "" then return nil end
        if string.find(spec, "^rbxassetid://") or string.find(spec, "^rbxasset://") then return spec end
        if string.find(spec, "^%d%d%d+$") then return "rbxassetid://" .. spec end
        if getcustomasset and isfile then
            local ok, has = pcall(isfile, spec)
            if ok and has then
                local ok2, url = pcall(getcustomasset, spec)
                if ok2 and url then return url end
            end
        end
        return nil
    end
    if type(DB.brand.name) == "string" and DB.brand.name ~= "" then CFG.Name = DB.brand.name end
    BR.image = BR.resolve(DB.brand.imgSpec)
    local function paintOne(e)
        if DB.brand.vectorLogo then
            e.l.Text, e.img.Visible = "", false
            e.vec.Visible = true
            local sz = math.floor(math.min(e.l.AbsoluteSize.X, e.l.AbsoluteSize.Y) * 0.6 + 0.5)
            if sz < 4 then sz = 18 end
            for _, c in ipairs(e.vec:GetChildren()) do c:Destroy() end
            centered(icon(e.vec, "boltfill", sz, Color3.new(0, 0, 0))).Parent = e.vec
        elseif BR.image then
            e.l.Text, e.vec.Visible = "", false
            e.img.Image, e.img.Visible = BR.image, true
        else
            e.l.Text, e.img.Visible, e.vec.Visible = DB.brand.logo or "S", false, false
        end
    end
    function BR.paint()
        local keep = {}
        for _, e in ipairs(BR.logos) do
            if e.l and e.l.Parent then keep[#keep + 1] = e paintOne(e) end
        end
        BR.logos = keep
    end
    -- registers a rounded TextLabel/TextButton as a logo (text mode) and adds an image layer for image mode
    function BR.addLogo(label)
        local img = new("ImageLabel", { Parent = label, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop,
            Visible = false, ZIndex = label.ZIndex + 1, BorderSizePixel = 0 })
        local vec = new("Frame", { Parent = label, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = label.ZIndex + 1, BorderSizePixel = 0 })
        local cr = label:FindFirstChildOfClass("UICorner")
        if cr then new("UICorner", { Parent = img, CornerRadius = cr.CornerRadius }) end
        local e = { l = label, img = img, vec = vec }
        BR.logos[#BR.logos + 1] = e
        if #BR.logos > 60 then
            local keep = {}
            for _, x in ipairs(BR.logos) do if x.l.Parent then keep[#keep + 1] = x end end
            BR.logos = keep
        end
        paintOne(e)
        return label
    end
    function BR.setName(name)
        name = trim(name)
        if name == "" then name = BR.defaultName end
        if (utf8.len(name) or #name) > 14 then name = string.sub(name, 1, (utf8.offset(name, 15) or 15) - 1) end
        if (utf8.len(name) or #name) < 3 then return CFG.Name, false end
        local old = CFG.Name
        if old == name then return name, true end
        CFG.Name = name
        DB.brand.name = (name ~= BR.defaultName) and name or nil
        saveDB()
        for _, d in ipairs(gui:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Font ~= Enum.Font.Code and d.Text ~= "" and string.find(d.Text, old, 1, true) then
                d.Text = replaceWord(d.Text, old, name)
            end
        end
        return name, true
    end
    -- spec: "" (reset) | "bolt" (generated vector mark) | 1-2 characters | asset id / rbxassetid://... | file in the workspace folder
    function BR.setLogo(spec)
        spec = trim(spec)
        if spec == "" then
            DB.brand.logo, DB.brand.imgSpec, DB.brand.vectorLogo, BR.image = nil, nil, nil, nil
        elseif spec == "bolt" then
            DB.brand.vectorLogo, DB.brand.logo, DB.brand.imgSpec, BR.image = true, nil, nil, nil
        elseif (utf8.len(spec) or #spec) <= 2 and not string.find(spec, "^%d%d%d+$") then
            DB.brand.vectorLogo = nil
            DB.brand.logo, DB.brand.imgSpec, BR.image = spec, nil, nil
        else
            DB.brand.vectorLogo = nil
            local url = BR.resolve(spec)
            if not url then return false, G("Image not found. Use an asset id or a file in the workspace folder.", "Картинка не найдена. Используй id ассета или файл из папки workspace.") end
            DB.brand.imgSpec, DB.brand.logo, BR.image = spec, nil, url
        end
        saveDB()
        BR.paint()
        return true
    end
end) if not ok_blk8 then warn("[blk8] " .. tostring(err_blk8)) end

local function makeBrand(z)
    local B = {}
    local root = new("Frame", { Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = z, Active = true })
    local grp = new("CanvasGroup", { Parent = root, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0 })
    makeSnow(grp, 70, 5)
    local center = new("Frame", { Parent = grp, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromOffset(320, 210), BackgroundTransparency = 1 })
    local ring = new("Frame", { Parent = center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(88, 88), BackgroundTransparency = 1 },
        { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), neonStroke(2.5, 140), new("UIScale") })
    local logoScale = ring:FindFirstChildOfClass("UIScale")
    BR.addLogo(new("TextLabel", { Parent = ring, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(62, 62),
        BackgroundColor3 = Color3.new(1, 1, 1), Text = "S", Font = Enum.Font.GothamBlack, TextSize = 36, TextColor3 = Color3.new(0, 0, 0) },
        { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) }))
    local row = new("Frame", { Parent = center, Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 },
        { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }) })
    local letters = {}
    for i = 1, #CFG.Name do
        letters[i] = new("TextLabel", { Parent = row, LayoutOrder = i, Size = UDim2.fromOffset(26, 40), BackgroundTransparency = 1,
            Text = string.sub(CFG.Name, i, i), Font = Enum.Font.GothamBlack, TextSize = 32, TextColor3 = Color3.new(1, 1, 1) })
    end
    local status = new("TextLabel", { Parent = center, Position = UDim2.fromOffset(0, 152), Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
        Text = "", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Color3.fromRGB(135, 135, 148) })
    local track = new("Frame", { Parent = center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 178), Size = UDim2.fromOffset(220, 3),
        BackgroundColor3 = Color3.fromRGB(34, 34, 38), BorderSizePixel = 0 }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
    local fill = new("Frame", { Parent = track, Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 },
        { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
    local greet = new("TextLabel", { Parent = center, Position = UDim2.fromOffset(0, 150), Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
        Text = "", Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = Color3.fromRGB(200, 200, 208), TextTransparency = 1 })

    function B.status(t) status.Text = t end
    function B.progress(p) tw2(fill, 0.25, { Size = UDim2.fromScale(p, 1) }) end
    local function burst(delay)
        task.delay(delay, function()
            if not root.Parent then return end
            local f = new("Frame", { Parent = center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(88, 88), BackgroundTransparency = 1 },
                { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }) })
            local st = f:FindFirstChildOfClass("UIStroke")
            tw2(f, 0.7, { Size = UDim2.fromOffset(460, 460) })
            tw2(st, 0.7, { Transparency = 1 })
            task.delay(0.8, function() f:Destroy() end)
        end)
    end
    function B.play(who)
        tw2(status, 0.15, { TextTransparency = 1 })
        tw2(track, 0.15, { BackgroundTransparency = 1 })
        tw2(fill, 0.15, { BackgroundTransparency = 1 })
        for _, l in ipairs(letters) do l.TextTransparency = 1 end
        logoScale.Scale = 0.55
        tw2(logoScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
        burst(0.05) burst(0.32)
        for i, l in ipairs(letters) do
            task.delay(0.22 + i * 0.07, function() tw2(l, 0.25, { TextTransparency = 0 }) end)
        end
        greet.Text = who or ""
        task.delay(0.85, function() tw2(greet, 0.3, { TextTransparency = 0 }) end)
        task.wait(1.45)
    end
    function B.close()
        tw2(grp, 0.4, { GroupTransparency = 1 })
        tw2(root, 0.4, { BackgroundTransparency = 1 })
        task.delay(0.5, function() root:Destroy() end)
    end
    return B
end
local splash = makeBrand(500)
splash.status("Starting...")

local function notify(text)
    if not S.notif then return end
    local t = new("Frame", {
        Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -50),
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), BackgroundColor3 = C.bg, ZIndex = 100,
    }, { round(16), stroke(C.line), hlist(8), new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 14) }) })
    local dot = BR.addLogo(new("TextLabel", {
        Parent = t, LayoutOrder = 1, Size = UDim2.fromOffset(22, 22), BackgroundColor3 = C.item, Text = "S",
        Font = Enum.Font.GothamBlack, TextSize = 12, TextColor3 = C.white, ZIndex = 101,
    }, { round(11) }))
    new("TextLabel", {
        Parent = t, LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text, Text = text, ZIndex = 101,
    })
    tween(t, 0.25, { Position = UDim2.new(0.5, 0, 0, 56) })
    task.delay(2.2, function()
        if t.Parent then tween(t, 0.25, { Position = UDim2.new(0.5, 0, 0, -50) }) task.wait(0.3) t:Destroy() end
    end)
end

-- Components -----------------------------------------------------------
local function pill(parent, key, iconName, size, cb, primary)
    local P = {}
    P.fgOn, P.fgOff = C.black, C.text
    local fg = primary and C.black or C.text
    P.b = new("TextButton", {
        Parent = parent, Size = size, AutoButtonColor = false, Text = "", BackgroundColor3 = primary and C.white or C.item,
    }, { round(10), hlist(7, Enum.HorizontalAlignment.Center) })
    if iconName then P.i = icon(P.b, iconName, 15, fg) P.i.LayoutOrder = 1 end
    if key then
        P.t = new("TextLabel", {
            Parent = P.b, LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
            BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = fg,
        })
        reg(P.t, key)
    end
    P.base = P.b.BackgroundColor3
    P.active = primary or false
    function P.set(on)
        P.active = on
        P.base = on and C.white or C.item
        tween(P.b, 0.12, { BackgroundColor3 = P.base })
        local f = on and C.black or C.text
        if P.t then P.t.TextColor3 = f end
        if P.i then tint(P.i, f) end
    end
    bind(P.b.MouseEnter, function() tween(P.b, 0.1, { BackgroundColor3 = P.active and Color3.fromRGB(214, 214, 220) or C.hover }) end)
    bind(P.b.MouseLeave, function() tween(P.b, 0.1, { BackgroundColor3 = P.base }) end)
    if cb then bind(P.b.MouseButton1Click, cb) end
    return P
end

local function iconBtn(parent, name, size, cb, color)
    local b = new("TextButton", {
        Parent = parent, Size = UDim2.fromOffset(size, size), AutoButtonColor = false, Text = "", BackgroundColor3 = C.item,
    }, { round(10) })
    local ic = centered(icon(b, name, math.floor(size * 0.5), color or C.text))
    ic.Parent = b
    bind(b.MouseEnter, function() tween(b, 0.1, { BackgroundColor3 = C.hover }) end)
    bind(b.MouseLeave, function() tween(b, 0.1, { BackgroundColor3 = C.item }) end)
    if cb then bind(b.MouseButton1Click, cb) end
    return b, ic
end

local function txt(parent, text, size, color, font, align)
    return new("TextLabel", {
        Parent = parent, BackgroundTransparency = 1, Text = text, TextSize = size, TextColor3 = color or C.text,
        Font = font or Enum.Font.Gotham, TextXAlignment = align or Enum.TextXAlignment.Left,
    })
end

----------------------------------------------------------------------
-- Logging
----------------------------------------------------------------------
local logs, consoleAppend = {}, nil
local logHooks = {}
local recentOut = {}
DB.banned = type(DB.banned) == "table" and DB.banned or {}
-- signature of an error: lowercase, trimmed, digits collapsed (so the same error with changing numbers is one error)
local function errSig(m)
    m = string.lower(tostring(m))
    m = string.gsub(m, "^%s+", "")
    m = string.gsub(m, "%s+$", "")
    return (string.gsub(m, "%d+", "#"))
end
local function addLog(kind, text)
    if (kind == "ERROR" or kind == "WARN") and DB.banned[errSig(text)] then return end
    local e = { t = os.date("%H:%M:%S"), k = kind, m = tostring(text) }
    logs[#logs + 1] = e
    if #logs > 500 then table.remove(logs, 1) end
    if consoleAppend then consoleAppend(e) end
    for _, f in ipairs(logHooks) do pcall(f, e) end
end
bind(game:GetService("LogService").MessageOut, function(msg, mt)
    local seen = recentOut[msg]
    if seen and os.clock() - seen < 0.6 then recentOut[msg] = nil return end
    local k = "PRINT"
    if mt == Enum.MessageType.MessageWarning then k = "WARN"
    elseif mt == Enum.MessageType.MessageError then k = "ERROR"
    elseif mt == Enum.MessageType.MessageInfo then k = "INFO" end
    addLog(k, msg)
end)

----------------------------------------------------------------------
-- Window / pages
----------------------------------------------------------------------
local WIN_W, WIN_H = TH.winW, TH.winH
local win = new("Frame", {
    Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(WIN_W, WIN_H), BackgroundTransparency = 1, Visible = false,
})
local uiScale = new("UIScale", { Parent = win })
local function targetScale()
    local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    return math.min(1, (vp.X - 16) / (WIN_W + 8), (vp.Y - 16) / (WIN_H + 8)) * (S.uiSize / 100)
end

-- LAYOUT: every region of the window is described by the theme (TH.*), LY.apply() lays everything out
local SB = { collapsed = S.sbCollapsed == true }
local LY = { hooks = {} }
function LY.rects()
    local c = TH
    local W, H = c.winW, c.winH
    local tb = c.titleBar and c.titleH or 0
    local split = c.sbSplit
    local gap = split and (c.sbGap or 10) or 0
    local sbw = SB.collapsed and 56 or c.sbW
    local sbh = 46
    local top, right = c.sbPos == "top", c.sbPos == "right"
    local R = { tb = tb, sbw = sbw, sbh = sbh }
    if top then
        if split then R.sb, R.ct = { 0, 0, W, sbh }, { 0, sbh + gap, W, H - sbh - gap }
        else R.sb, R.ct = { 0, tb, W, sbh }, { 0, 0, W, H } end
    elseif right then
        if split then R.sb, R.ct = { W - sbw, 0, sbw, H }, { 0, 0, W - sbw - gap, H }
        else R.sb, R.ct = { W - sbw, tb, sbw, H - tb }, { 0, 0, W, H } end
    else
        if split then R.sb, R.ct = { 0, 0, sbw, H }, { sbw + gap, 0, W - sbw - gap, H }
        else R.sb, R.ct = { 0, tb, sbw, H - tb }, { 0, 0, W, H } end
    end
    local cw, ch = R.ct[3], R.ct[4]
    local px, py, pw, ph = 0, 0, cw, ch
    if tb > 0 then py, ph = tb + 1, ch - tb - 1 end
    if not split then
        if top then py, ph = py + sbh + 1, ph - sbh - 1
        elseif right then pw = cw - sbw - 1
        else px, pw = sbw + 1, cw - sbw - 1 end
    end
    R.pg = { px, py, pw, ph }
    return R
end
local R0 = LY.rects()

-- window frame (background layers + neon border)
local content = new("Frame", {
    Parent = win, Position = UDim2.fromOffset(R0.ct[1], R0.ct[2]), Size = UDim2.fromOffset(R0.ct[3], R0.ct[4]), BackgroundColor3 = C.bg,
}, { round(14), neonStroke(TH.neonThick, TH.neonSpeed, true) })
local bgC = new("Frame", { Parent = content, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0 },
    { round(14), new("UIGradient", { Enabled = false }) })
local bgI = new("ImageLabel", { Parent = content, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", Visible = false, ScaleType = Enum.ScaleType.Crop, BorderSizePixel = 0 },
    { round(14) })
local bgD = new("Frame", { Parent = content, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0 },
    { round(14) })
local mainSnow = makeSnow(content, 24, 4, win)
mainSnow.holder.Visible = S.snow ~= false
local lineT = new("Frame", { Parent = content, Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.line, BorderSizePixel = 0 })

-- sidebar: transparent over the window (flat) or its own rounded card (split)
local sidebar = new("Frame", { Parent = win, Position = UDim2.fromOffset(R0.sb[1], R0.sb[2]), Size = UDim2.fromOffset(R0.sb[3], R0.sb[4]), BackgroundColor3 = C.bg,
    BackgroundTransparency = TH.sbSplit and 0 or 1, BorderSizePixel = 0 },
    { round(14), neonStroke(TH.neonThick, TH.neonSpeed, true) })
local sbStroke = sidebar:FindFirstChildOfClass("UIStroke")
sbStroke.Enabled = false
local sbBg = new("Frame", { Parent = sidebar, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false },
    { round(14), new("UIGradient", { Enabled = false }) })
local lineV = new("Frame", { Parent = win, Size = UDim2.fromOffset(1, 100), BackgroundColor3 = C.line, BorderSizePixel = 0 })
local lineH = new("Frame", { Parent = win, Size = UDim2.fromOffset(100, 1), BackgroundColor3 = C.line, BorderSizePixel = 0 })

local NAV_COLORS = { Color3.fromRGB(240, 120, 120), Color3.fromRGB(240, 190, 100), Color3.fromRGB(130, 220, 140), Color3.fromRGB(110, 180, 240), Color3.fromRGB(190, 140, 240) }
local pages, navBtns, navOrder = {}, {}, {}
local currentPage
local function showPage(name)
    currentPage = name
    S.lastPage = name
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, o in pairs(navBtns) do
        local on = n == name
        tint(o.ic, on and C.white or (TH.colorfulIcons and o.navColor or C.sub))
        o.lb.TextColor3 = on and C.text or C.sub
        tween(o.b, 0.12, { BackgroundTransparency = on and 0 or 1 })
    end
end

local function addPage(name, iconName)
    local idx = 0
    for _ in pairs(navOrder) do idx = idx + 1 end
    idx = idx + 1
    navOrder[name] = idx
    local b = new("TextButton", {
        Parent = sidebar, Position = UDim2.fromOffset(8, 10 + (idx - 1) * 36), Size = UDim2.new(1, -16, 0, 32),
        BackgroundColor3 = C.item, BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
    }, { round(8) })
    local ic = icon(b, iconName, 16, C.sub)
    ic.Position = UDim2.fromOffset(10, 8)
    local lb = txt(b, "", 13, C.sub, Enum.Font.GothamMedium)
    lb.Position, lb.Size = UDim2.fromOffset(36, 0), UDim2.new(1, -44, 1, 0)
    reg(lb, name)
    navBtns[name] = { b = b, ic = ic, lb = lb, navColor = NAV_COLORS[(navOrder[name] - 1) % #NAV_COLORS + 1] }
    bind(b.MouseButton1Click, function() showPage(name) end)
    bind(b.MouseEnter, function() if currentPage ~= name then tween(b, 0.1, { BackgroundTransparency = 0.6 }) end end)
    bind(b.MouseLeave, function() if currentPage ~= name then tween(b, 0.1, { BackgroundTransparency = 1 }) end end)
    local R = LY.rects()
    local page = new("Frame", {
        Parent = content, Position = UDim2.fromOffset(R.pg[1], R.pg[2]), Size = UDim2.fromOffset(R.pg[3], R.pg[4]), BackgroundTransparency = 1, Visible = false,
    }, { pad(16) })
    pages[name] = page
    return page
end

local open, topBtn = false, nil
local function setOpen(v)
    if v and not unlocked then return end
    open = v
    if v then
        uiScale.Scale = targetScale() * (S.anim and 0.93 or 1)
        win.Visible = true
        tween(uiScale, 0.18, { Scale = targetScale() })
    else
        win.Visible = false
    end
    blur.Size = (v and S.blur) and 16 or 0
end
local function applyPosition()
    win.Position = UDim2.fromScale(0.5, ({ Center = 0.5, Top = 0.3, Bottom = 0.7 })[S.pos] or 0.5)
end

local HEADER_BUILDERS, TITLE_RIGHT, HEADER_RIGHT, HEADER_CTRL = {}, {}, {}, {}
local CTRL_W = { win = 126, sm1ler = 32, mac = 104, linux = 100 }
local function ctrlW() return CTRL_W[S.guiStyle or "win"] or 32 end
local HEADER_OFF, TITLE_OFF = 0, 0
-- places an element at the right edge of a page header (left of the window buttons when they live in the header)
local function placeRight(o, y, gap)
    HEADER_RIGHT[#HEADER_RIGHT + 1] = { o = o, y = y or 0, gap = gap or 8 }
    o.Position = UDim2.new(1, -(HEADER_OFF + (gap or 8)), 0, y or 0)
end
-- places an element in the title bar, just left of the window buttons
local function placeTitle(o, gap)
    TITLE_RIGHT[#TITLE_RIGHT + 1] = { o = o, gap = gap or 12 }
    o.Position = UDim2.new(1, -(TITLE_OFF + 6 + (gap or 12)), 0.5, 0)
end
local function applyGuiStyle()
    for _, f in ipairs(HEADER_BUILDERS) do pcall(f) end
    if LY.apply then LY.apply(false) end
end

local function winControls(parent)
    local box = new("Frame", { Parent = parent, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(126, 32), BackgroundTransparency = 1 })
    local function build()
        for _, ch in ipairs(box:GetChildren()) do ch:Destroy() end
        local style = S.guiStyle or "sm1ler"
        if style == "win" then
            box.Size = UDim2.fromOffset(126, 32)
            new("UIListLayout", { Parent = box, Padding = UDim.new(0, 0), FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
                VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Right })
            local function wb(order, hoverColor, cb, draw)
                local b = new("TextButton", { Parent = box, LayoutOrder = order, Size = UDim2.fromOffset(42, 32), BackgroundColor3 = hoverColor, BackgroundTransparency = 1,
                    AutoButtonColor = false, Text = "" }, { round(6) })
                draw(b)
                bind(b.MouseEnter, function() tween(b, 0.1, { BackgroundTransparency = 0 }) end)
                bind(b.MouseLeave, function() tween(b, 0.1, { BackgroundTransparency = 1 }) end)
                bind(b.MouseButton1Click, cb)
            end
            wb(1, C.item, function() setOpen(false) end, function(b)
                new("Frame", { Parent = b, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(11, 1), BackgroundColor3 = C.text, BorderSizePixel = 0 })
            end)
            wb(2, C.item, function() end, function(b)
                new("Frame", { Parent = b, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1 },
                    { new("UIStroke", { Color = C.text, Thickness = 1 }) })
            end)
            wb(3, C.err, function() setOpen(false) end, function(b)
                centered(icon(b, "x", 13, C.text)).Parent = b
            end)
        elseif style == "mac" then
            box.Size = UDim2.fromOffset(104, 32)
            new("UIListLayout", { Parent = box, Padding = UDim.new(0, 10), FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Right })
            local function dot(color, glyphColor, order, cb)
                local b = new("TextButton", { Parent = box, LayoutOrder = order, Size = UDim2.fromOffset(20, 20), BackgroundColor3 = color, AutoButtonColor = false, Text = "" }, { round(10), stroke(Color3.new(0, 0, 0)) })
                local st = b:FindFirstChildOfClass("UIStroke") st.Transparency = 0.75
                local gl = centered(icon(b, "x", 10, glyphColor)) gl.Parent = b gl.Visible = false
                bind(b.MouseEnter, function() gl.Visible = true tween(b, 0.1, { BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.12) }) end)
                bind(b.MouseLeave, function() gl.Visible = false tween(b, 0.1, { BackgroundColor3 = color }) end)
                bind(b.MouseButton1Click, cb)
                return b
            end
            dot(Color3.fromRGB(100, 200, 90), Color3.fromRGB(10, 70, 10), 1, function() end)
            dot(Color3.fromRGB(240, 190, 70), Color3.fromRGB(90, 60, 5), 2, function() setOpen(false) end)
            dot(Color3.fromRGB(235, 90, 85), Color3.fromRGB(90, 10, 10), 3, function() setOpen(false) end)
        elseif style == "linux" then
            box.Size = UDim2.fromOffset(100, 32)
            new("UIListLayout", { Parent = box, Padding = UDim.new(0, 5), FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Right })
            local function rnd(glyph, order, hoverC, cb)
                local b = new("TextButton", { Parent = box, LayoutOrder = order, Size = UDim2.fromOffset(30, 30), BackgroundColor3 = C.item, AutoButtonColor = false, Text = "" }, { round(15) })
                centered(icon(b, glyph, 11, C.text)).Parent = b
                bind(b.MouseEnter, function() tween(b, 0.1, { BackgroundColor3 = hoverC }) end)
                bind(b.MouseLeave, function() tween(b, 0.1, { BackgroundColor3 = C.item }) end)
                bind(b.MouseButton1Click, cb)
                return b
            end
            rnd("down", 1, C.hover, function() setOpen(false) end)
            rnd("move", 2, C.hover, function() end)
            rnd("x", 3, C.err, function() setOpen(false) end)
        else
            box.Size = UDim2.fromOffset(32, 32)
            local x = new("TextButton", { Parent = box, Size = UDim2.fromOffset(32, 32), BackgroundColor3 = C.item, AutoButtonColor = false, Text = "" }, { round(10) })
            centered(icon(x, "x", 14, C.text)).Parent = x
            bind(x.MouseButton1Click, function() setOpen(false) end)
            bind(x.MouseEnter, function() tween(x, 0.1, { BackgroundColor3 = C.hover }) end)
            bind(x.MouseLeave, function() tween(x, 0.1, { BackgroundColor3 = C.item }) end)
        end
    end
    build()
    HEADER_BUILDERS[#HEADER_BUILDERS + 1] = build
    return box
end

local function header(page, titleKey)
    local h = new("Frame", { Parent = page, Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1 })
    local title = txt(h, "", 20, C.text, Enum.Font.GothamBold)
    title.Size = UDim2.new(0, 160, 1, 0)
    reg(title, titleKey)
    local hc = winControls(h)
    hc.Visible = false   -- LY.apply decides where the window buttons live
    HEADER_CTRL[#HEADER_CTRL + 1] = hc
    return h, title
end

-- title bar: logo, name, injector status, window buttons
local TBAR = {}
local ok_blk9, err_blk9 = pcall(function()
    local titleBar = new("Frame", { Parent = content, Size = UDim2.new(1, 0, 0, TH.titleH), BackgroundTransparency = 1, Visible = TH.titleBar })
    TBAR.frame = titleBar
    local tLogo = BR.addLogo(new("TextLabel", { Parent = titleBar, Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = C.white, Text = "S", Font = Enum.Font.GothamBlack,
        TextSize = 13, TextColor3 = C.black }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) }))
    for _, e in ipairs(BR.logos) do if e.l == tLogo then e.titleSlot = true end end
    local tt = txt(titleBar, CFG.Name, 13, C.text, Enum.Font.GothamBold)
    tt.Position, tt.Size = UDim2.fromOffset(44, 0), UDim2.new(0, 160, 1, 0)
    TBAR.tt = tt
    TBAR.verLbl = txt(titleBar, "v" .. CFG.Version, 11, C.sub, Enum.Font.Code)
    TBAR.verLbl.Position, TBAR.verLbl.Size, TBAR.verLbl.Visible = UDim2.fromOffset(200, 0), UDim2.new(0, 60, 1, 0), TH.showTitleVersion
    TBAR.controls = winControls(titleBar)
    TBAR.pill = new("Frame", { Parent = titleBar, AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(124, 24), BackgroundColor3 = C.panel }, { round(12), stroke() })
    TBAR.dot = new("Frame", { Parent = TBAR.pill, Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = C.err, BorderSizePixel = 0 }, { round(4) })
    TBAR.lbl = txt(TBAR.pill, G("Not injected", "Не подключён"), 12, C.text, Enum.Font.GothamMedium)
    TBAR.lbl.Position, TBAR.lbl.Size = UDim2.fromOffset(26, 0), UDim2.new(1, -30, 1, 0)
    placeTitle(TBAR.pill, 12)
end) if not ok_blk9 then warn("[blk9] " .. tostring(err_blk9)) end

-- sidebar footer: who is signed in
local SBU = {}
local ok_blk10, err_blk10 = pcall(function()
    local card = new("Frame", { Parent = sidebar, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -10), Size = UDim2.new(1, -16, 0, 50), BackgroundColor3 = C.panel }, { round(10), stroke() })
    local av = new("ImageLabel", { Parent = card, Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = C.item, Image = "", BorderSizePixel = 0 },
        { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
    SBU.name = txt(card, dispName(), 12, C.text, Enum.Font.GothamBold)
    SBU.name.Position, SBU.name.Size, SBU.name.TextTruncate = UDim2.fromOffset(50, 8), UDim2.new(1, -58, 0, 16), Enum.TextTruncate.AtEnd
    SBU.sub = txt(card, G("Signed in", "Вошёл"), 11, C.sub)
    SBU.sub.Position, SBU.sub.Size = UDim2.fromOffset(50, 26), UDim2.new(1, -58, 0, 14)
    SBU.card, SBU.av = card, av
    task.spawn(function()
        local ok, url = pcall(function() return Players:GetUserThumbnailAsync(LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48) end)
        if ok and url and av.Parent then av.Image = url end
    end)
end) if not ok_blk10 then warn("[blk10] " .. tostring(err_blk10)) end

-- watermark (name + version, bottom-right of the window)
local WMK = new("TextLabel", { Parent = win, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -6), Size = UDim2.fromOffset(200, 16),
    BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11, TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.5,
    TextXAlignment = Enum.TextXAlignment.Right, Text = "", ZIndex = 50, Visible = false })
task.spawn(function()
    while alive do
        WMK.Text = CFG.Name .. " · v" .. CFG.Version
        task.wait(1)
    end
end)

-- faint grid overlay inside the content area (decorative)
local GRID = new("Frame", { Parent = content, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, Visible = false, ZIndex = 1, BorderSizePixel = 0 })
local function buildGrid()
    for _, c in ipairs(GRID:GetChildren()) do c:Destroy() end
    local step = 24
    for x = 0, WIN_W, step do
        new("Frame", { Parent = GRID, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(1, WIN_H), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.95, BorderSizePixel = 0 })
    end
    for y = 0, WIN_H, step do
        new("Frame", { Parent = GRID, Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(WIN_W, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.95, BorderSizePixel = 0 })
    end
end
buildGrid()
LY.hooks[#LY.hooks + 1] = buildGrid

-- panel depth: adds a soft 1px shadow line under every C.panel-colored surface
local PDEPTH = {}
local ok_blk11, err_blk11 = pcall(function()
    local tagged, lastDepth = {}, -1
    function PDEPTH.apply(depth)
        if depth == lastDepth then return end
        lastDepth = depth
        for _, d in ipairs(content:GetDescendants()) do
            if d:IsA("Frame") and d.BackgroundColor3 == C.panel and d.BackgroundTransparency < 1 then
                local sh = d:FindFirstChild("_depthShadow")
                if depth <= 0 then
                    if sh then sh:Destroy() end
                else
                    if not sh then
                        sh = new("Frame", { Name = "_depthShadow", Parent = d, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
                            Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = d.ZIndex })
                    end
                    sh.BackgroundTransparency = 1 - math.clamp(depth / 3, 0, 1) * 0.35
                end
            end
        end
    end
end) if not ok_blk11 then warn("[blk11] " .. tostring(err_blk11)) end

-- collapse / expand button (vertical sidebar)
local ok_blk12, err_blk12 = pcall(function()
    local cb = new("TextButton", { Parent = sidebar, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -68), Size = UDim2.new(1, -16, 0, 30),
        BackgroundColor3 = C.item, BackgroundTransparency = 1, AutoButtonColor = false, Text = "" }, { round(8) })
    local cic = icon(cb, "left", 14, C.sub)
    cic.Position = UDim2.fromOffset(11, 8)
    local clb = txt(cb, G("Collapse", "Свернуть"), 12, C.sub, Enum.Font.GothamMedium)
    clb.Position, clb.Size = UDim2.fromOffset(36, 0), UDim2.new(1, -44, 1, 0)
    SB.btn, SB.icon, SB.label = cb, cic, clb
    bind(cb.MouseButton1Click, function()
        SB.collapsed = not SB.collapsed
        S.sbCollapsed = SB.collapsed
        saveDB()
        LY.apply(true)
    end)
    bind(cb.MouseEnter, function() tween(cb, 0.1, { BackgroundTransparency = 0.6 }) end)
    bind(cb.MouseLeave, function() tween(cb, 0.1, { BackgroundTransparency = 1 }) end)
end) if not ok_blk12 then warn("[blk12] " .. tostring(err_blk12)) end

-- the layout engine: reads the theme and places every region
function LY.apply(animate)
    local c = TH
    local R = LY.rects()
    local d = animate and 0.15 or 0
    local function put(o, props)
        if d > 0 then tween(o, d, props) else for k, v in pairs(props) do o[k] = v end end
    end
    local resized = (WIN_W ~= c.winW or WIN_H ~= c.winH)
    WIN_W, WIN_H = c.winW, c.winH
    win.Size = UDim2.fromOffset(WIN_W, WIN_H)
    if resized and win.Visible then uiScale.Scale = targetScale() end
    local split, top, right = c.sbSplit, c.sbPos == "top", c.sbPos == "right"
    local vertical = not top
    put(content, { Position = UDim2.fromOffset(R.ct[1], R.ct[2]), Size = UDim2.fromOffset(R.ct[3], R.ct[4]) })
    put(sidebar, { Position = UDim2.fromOffset(R.sb[1], R.sb[2]), Size = UDim2.fromOffset(R.sb[3], R.sb[4]) })
    sbBg.Visible, sbStroke.Enabled = split, split
    sidebar.BackgroundTransparency = split and 0 or 1
    -- title bar and dividers
    TBAR.frame.Visible = c.titleBar
    TBAR.frame.Size = UDim2.new(1, 0, 0, c.titleH)
    lineT.Visible = c.titleBar
    lineT.Position = UDim2.fromOffset(0, c.titleH)
    lineV.Visible = (not split) and vertical
    lineV.Position = UDim2.fromOffset(right and (WIN_W - R.sbw - 1) or R.sbw, R.tb)
    lineV.Size = UDim2.fromOffset(1, WIN_H - R.tb)
    lineH.Visible = (not split) and top
    lineH.Position = UDim2.fromOffset(0, R.tb + R.sbh)
    lineH.Size = UDim2.fromOffset(WIN_W, 1)
    -- navigation
    local labMode = c.navLabelMode or (c.sbLabels == false and "icon" or "both")
    local labels = labMode ~= "icon" and not SB.collapsed
    local iconsOn = labMode ~= "text"
    local NAVCOLORS = { Color3.fromRGB(240, 120, 120), Color3.fromRGB(240, 190, 100), Color3.fromRGB(130, 220, 140), Color3.fromRGB(110, 180, 240), Color3.fromRGB(190, 140, 240) }
    local names = {}
    for name, idx in pairs(navOrder) do names[#names + 1] = { name, idx } end
    table.sort(names, function(a, b) return a[2] < b[2] end)
    local pos = 0
    for _, e in ipairs(names) do
        local name = e[1]
        local o = navBtns[name]
        local hidden = type(c.navOff) == "table" and c.navOff[name] == true and name ~= "Settings" and name ~= "Theme"
        o.b.Visible = not hidden
        if not hidden then
            if vertical then
                o.b.Position, o.b.Size = UDim2.fromOffset(8, 10 + pos * 36), UDim2.new(1, -16, 0, 32)
                o.lb.Position, o.lb.Size = UDim2.fromOffset(36, 0), UDim2.new(1, -44, 1, 0)
            else
                local w = labels and 112 or 40
                o.b.Position, o.b.Size = UDim2.fromOffset(8 + pos * (w + 4), 7), UDim2.fromOffset(w, 32)
                o.lb.Position, o.lb.Size = UDim2.fromOffset(32, 0), UDim2.new(1, -38, 1, 0)
            end
            o.ic.Position = labels and UDim2.fromOffset(10, 8) or UDim2.new(0.5, -8, 0, 8)
            o.ic.Visible = iconsOn
            o.lb.Visible = labels
            pos = pos + 1
        end
    end
    -- footer + collapse button
    SBU.card.Visible = c.sbFooter and vertical
    SB.btn.Visible = c.sbCollapse and vertical
    SB.btn.Position = UDim2.new(0, 8, 1, c.sbFooter and -68 or -10)
    SB.icon.Rotation = SB.collapsed and 180 or 0
    SB.label.Visible = not SB.collapsed
    SBU.name.Visible, SBU.sub.Visible = not SB.collapsed, not SB.collapsed
    SBU.av.Position = UDim2.fromOffset(SB.collapsed and 3 or 8, 8)
    -- pages
    for _, pg in pairs(pages) do put(pg, { Position = UDim2.fromOffset(R.pg[1], R.pg[2]), Size = UDim2.fromOffset(R.pg[3], R.pg[4]) }) end
    -- logo / name / version visibility
    for _, e in ipairs(BR.logos) do
        if e.titleSlot then e.l.Visible = c.logoIcon end
    end
    if TBAR.tt then TBAR.tt.Visible = c.logoText end
    if TBAR.verLbl then TBAR.verLbl.Visible = c.showTitleVersion end
    if WMK then WMK.Visible = c.watermark end
    -- colourful nav icons
    for _, nm in ipairs(names) do
        local o = navBtns[nm[1]]
        if o and iconsOn then tint(o.ic, (currentPage == nm[1]) and C.white or (c.colorfulIcons and o.navColor or C.sub)) end
    end
    -- faint UI grid overlay
    if GRID then GRID.Visible = c.uiGrid end
    -- panel depth (adds/removes a soft bottom shadow line on every panel-colored surface)
    if PDEPTH then PDEPTH.apply(c.panelDepth or 0) end
    -- window buttons: title bar or page headers
    local useTitle = c.titleBar and c.ctrlLoc == "title"
    TBAR.controls.Visible = useTitle
    for _, hc in ipairs(HEADER_CTRL) do hc.Visible = not useTitle end
    HEADER_OFF = useTitle and 0 or ctrlW()
    TITLE_OFF = useTitle and ctrlW() or 0
    for _, r in ipairs(HEADER_RIGHT) do r.o.Position = UDim2.new(1, -(HEADER_OFF + r.gap), 0, r.y) end
    for _, r in ipairs(TITLE_RIGHT) do r.o.Position = UDim2.new(1, -(TITLE_OFF + 6 + r.gap), 0.5, 0) end
    for _, f in ipairs(LY.hooks) do pcall(f) end
end

-- modal ----------------------------------------------------------------
local function modal(titleKey, w, h)
    local dim = new("TextButton", {
        Parent = content, Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.black, BackgroundTransparency = 0.45,
        Text = "", AutoButtonColor = false, ZIndex = 20,
    }, { round(18) })
    local card = new("Frame", {
        Parent = dim, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = C.bg, ZIndex = 21,
    }, { round(16), stroke(C.stroke or C.line), pad(16) })
    if titleKey then
        local t = txt(card, "", 18, C.text, Enum.Font.GothamBold)
        t.Size = UDim2.new(1, 0, 0, 24)
        t.ZIndex = 22
        reg(t, titleKey)
    end
    local function close() dim:Destroy() end
    bind(dim.MouseButton1Click, close)
    return card, close
end

local runSource, openInEditor

----------------------------------------------------------------------
-- HOME
----------------------------------------------------------------------
local refreshHome
local ok_blk13, err_blk13 = pcall(function()
    local homePage = addPage("Home", "home")
    local homeScroll = new("ScrollingFrame", { Parent = homePage, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y })
    local h, homeTitle = header(homeScroll, "Overview")
    local hLogo = BR.addLogo(new("TextLabel", { Parent = h, Size = UDim2.fromOffset(34, 34), BackgroundColor3 = C.white, Text = "S", Font = Enum.Font.GothamBlack,
        TextSize = 20, TextColor3 = C.black }, { round(17) }))
    local hName = txt(h, CFG.Name, 20, C.text, Enum.Font.GothamBold)
    hName.Position, hName.Size = UDim2.fromOffset(44, 0), UDim2.new(0, 220, 0, 34)
    local sub = txt(h, "", 12, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Right)
    sub.AnchorPoint = Vector2.new(1, 0)
    sub.Size = UDim2.fromOffset(300, 36)
    placeRight(sub, 0, 4)
    -- Overview cards (Volt style)
    local PLAN = { [1] = "FlashKey", [2] = "LinkVault", [3] = "GoldPass" }
    STAT.listeners[#STAT.listeners + 1] = function() if refreshHome then pcall(refreshHome) end end
    local function card(x, y, w, hgt)
        return new("Frame", { Parent = homeScroll, Position = UDim2.new(x, x > 0 and 4 or 0, 0, y), Size = UDim2.new(w, w < 1 and -4 or 0, 0, hgt), BackgroundColor3 = C.panel }, { round(12), stroke() })
    end
    local function tx(parent, size, color, font, y, right, part)
        local o = txt(parent, "", size, color, font, right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left)
        if part == "r" then o.Position, o.Size = UDim2.new(0.5, 0, 0, y), UDim2.new(0.5, -14, 0, size + 8)
        elseif part == "l" then o.Position, o.Size = UDim2.fromOffset(14, y), UDim2.new(0.5, -14, 0, size + 8)
        else o.Position, o.Size = UDim2.fromOffset(14, y), UDim2.new(1, -28, 0, size + 8) end
        o.TextTruncate = Enum.TextTruncate.AtEnd
        return o
    end
    local cA, cP = card(0, 52, 0.5, 56), card(0.5, 52, 0.5, 56)
    tx(cA, 11, C.sub, Enum.Font.Gotham, 9).Text = G("Account", "Аккаунт")
    local aV = tx(cA, 15, C.text, Enum.Font.GothamBold, 26)
    tx(cP, 11, C.sub, Enum.Font.Gotham, 9, true).Text = G("Plan", "Тариф")
    local pV = tx(cP, 15, C.text, Enum.Font.GothamBold, 26, true)
    local cL = card(0, 116, 1, 72)
    tx(cL, 11, C.sub, Enum.Font.Gotham, 9, false, "l").Text = G("License", "Лицензия")
    local lV = tx(cL, 17, C.text, Enum.Font.GothamBold, 26, false, "l")
    local lS = tx(cL, 11, C.sub, Enum.Font.Gotham, 50, false, "l")
    tx(cL, 11, C.sub, Enum.Font.Gotham, 9, true, "r").Text = G("Time remaining", "Осталось времени")
    local tV = tx(cL, 17, C.text, Enum.Font.GothamBold, 26, true, "r")
    local cS = card(0, 196, 1, 56)
    tx(cS, 11, C.sub, Enum.Font.Gotham, 8, false, "l").Text = G("Status", "Статус")
    local stDot1 = new("Frame", { Parent = cS, Position = UDim2.fromOffset(14, 28), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = C.ok, BorderSizePixel = 0 }, { round(4) })
    local stTxt1 = txt(cS, "", 12, C.text, Enum.Font.GothamMedium)
    stTxt1.Position, stTxt1.Size = UDim2.fromOffset(28, 20), UDim2.fromOffset(180, 16)
    tx(cS, 11, C.sub, Enum.Font.Gotham, 8, true, "r").Text = G("Detection", "Детект")
    local stDot2 = new("Frame", { Parent = cS, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -170, 0, 28), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = C.ok, BorderSizePixel = 0 }, { round(4) })
    local stTxt2 = txt(cS, "", 12, C.text, Enum.Font.GothamMedium, Enum.TextXAlignment.Right)
    stTxt2.Position, stTxt2.Size = UDim2.new(1, -176, 0, 20), UDim2.fromOffset(160, 16)
    local cV, cE = card(0, 260, 0.5, 64), card(0.5, 260, 0.5, 64)
    tx(cV, 11, C.sub, Enum.Font.Gotham, 9).Text = G("SM1LER version", "Версия SM1LER")
    tx(cV, 15, C.text, Enum.Font.GothamBold, 26).Text = "v" .. CFG.Version
    tx(cV, 11, C.sub, Enum.Font.Gotham, 46).Text = CFG.Update.ManifestUrl ~= "" and G("Auto-update: on", "Автообновление: вкл") or G("Auto-update: off", "Автообновление: выкл")
    tx(cE, 11, C.sub, Enum.Font.Gotham, 9, true).Text = G("Executor", "Экзекьютор")
    local exeName, robloxV = "unknown", "?"
    pcall(function()
        if identifyexecutor then
            local n, v = identifyexecutor()
            exeName = tostring(n) .. (v and (" " .. tostring(v)) or "")
        end
    end)
    pcall(function() robloxV = version() end)
    tx(cE, 15, C.text, Enum.Font.GothamBold, 26, true).Text = exeName
    tx(cE, 11, C.sub, Enum.Font.Gotham, 46, true).Text = "Roblox " .. robloxV

    local cW = card(0, 332, 1, 58)
    tx(cW, 11, C.sub, Enum.Font.Gotham, 8).Text = G("What's new", "Что нового")
    tx(cW, 12, C.text, Enum.Font.GothamMedium, 24).Text = G("v1.5.0 · Volt-style window: sidebar, title bar, injector status", "v1.5.0 · окно в стиле Volt: боковая панель, строка заголовка, статус инжектора")
    tx(cW, 11, C.sub, Enum.Font.Gotham, 42).Text = G("v1.4.0 · .theme files are found automatically · snow is off by default", "v1.4.0 · файлы .theme находятся автоматически · снег выключен по умолчанию")

    -- cards flow into rows; the theme decides which cards exist
    local CARDS = { { "account", cA, 1, 56 }, { "plan", cP, 1, 56 }, { "license", cL, 2, 72 }, { "status", cS, 2, 56 }, { "version", cV, 1, 64 }, { "exec", cE, 1, 64 }, { "news", cW, 2, 58 } }
    local function layoutHome()
        local y, pend = 52, nil
        local cfg = type(TH.home) == "table" and TH.home or {}
        local function place(card, x, w, off, hgt)
            card.Position = UDim2.new(x, off, 0, y)
            card.Size = UDim2.new(w, w < 1 and -4 or 0, 0, hgt)
        end
        for _, c in ipairs(CARDS) do c[2].Visible = false end
        for _, c in ipairs(CARDS) do
            if cfg[c[1]] ~= false then
                if c[3] == 2 then
                    if pend then place(pend[2], 0, 1, 0, pend[4]) pend[2].Visible = true y = y + pend[4] + 8 pend = nil end
                    place(c[2], 0, 1, 0, c[4]) c[2].Visible = true y = y + c[4] + 8
                elseif pend then
                    local hgt = math.max(pend[4], c[4])
                    place(pend[2], 0, 0.5, 0, hgt) place(c[2], 0.5, 0.5, 4, hgt)
                    pend[2].Visible, c[2].Visible = true, true
                    y = y + hgt + 8
                    pend = nil
                else
                    pend = c
                end
            end
        end
        if pend then place(pend[2], 0, 1, 0, pend[4]) pend[2].Visible = true end
        local tbOn = TH.titleBar
        hLogo.Visible, hName.Visible, homeTitle.Visible = not tbOn, not tbOn, tbOn
    end
    LY.hooks[#LY.hooks + 1] = layoutHome
    layoutHome()

    function refreshHome()
        SBU.name.Text = dispName()
        SBU.sub.Text = PLAN[DB.planTier] or G("Signed in", "Вошёл")
        sub.Text = T("Welcome back") .. ", " .. dispName()
        aV.Text = "@" .. userName()
        pV.Text = PLAN[DB.planTier] or G("Standard", "Стандарт")
        lV.Text = KEY.value and G("Active key", "Активный ключ") or G("No key", "Нет ключа")
        lS.Text = KEY.value and (G("Valid until ", "Действует до ") .. os.date("%b %d, %H:%M", KEY.expires)) or ""
        tV.Text = keyLeftText()
        local dotColor = { ok = C.ok, updating = C.warn, down = C.err }
        stDot1.BackgroundColor3 = dotColor[STAT.status] or C.ok
        stTxt1.Text = STAT.icon(STAT.status) .. " " .. STAT.label(STAT.status)
        stDot2.BackgroundColor3 = dotColor[STAT.detect] or C.ok
        stTxt2.Text = STAT.icon(STAT.detect) .. " " .. STAT.label(STAT.detect)
        if #STAT.changelog > 0 then
            for _, c in ipairs(cW:GetChildren()) do if c.Name == "_log" then c:Destroy() end end
            local y = 24
            for i = 1, math.min(3, #STAT.changelog) do
                local l = txt(cW, "• " .. tostring(STAT.changelog[i]), 11, i == 1 and C.text or C.sub, i == 1 and Enum.Font.GothamMedium or Enum.Font.Gotham)
                l.Name, l.Position, l.Size, l.TextTruncate = "_log", UDim2.fromOffset(14, y), UDim2.new(1, -28, 0, 16), Enum.TextTruncate.AtEnd
                y = y + 16
            end
        end
    end
    refreshHome()
    task.spawn(function()
        while alive do
            pcall(refreshHome)
            task.wait(1)
        end
    end)
end) if not ok_blk13 then warn("[blk13] " .. tostring(err_blk13)) end

----------------------------------------------------------------------
-- Lua syntax highlighter
----------------------------------------------------------------------
local esc, highlight, setSyntax, resetSyntax, getSyntax
local ok_blk14, err_blk14 = pcall(function()
local KW, BI = {}, {}
for w in string.gmatch("and break do else elseif end false for function if in local nil not or repeat return then true until while continue", "%a+") do KW[w] = true end
for w in string.gmatch("print warn error game workspace script task wait spawn delay pairs ipairs next type typeof tostring tonumber require pcall xpcall loadstring getfenv setmetatable getmetatable Instance Vector2 Vector3 CFrame Color3 UDim2 Enum string table math os", "%a+") do BI[w] = true end
local HC = { comment = Color3.fromRGB(106, 163, 92), str = Color3.fromRGB(214, 157, 133), num = Color3.fromRGB(181, 206, 168),
    kw = Color3.fromRGB(197, 134, 192), bi = Color3.fromRGB(120, 190, 240) }
local HC0 = {}
for k, v in pairs(HC) do HC0[k] = v end
function setSyntax(t) for k, v in pairs(t or {}) do local c = typeof(v) == "Color3" and v or hexToColor(v) if c and HC[k] then HC[k] = c end end end
function resetSyntax() for k, v in pairs(HC0) do HC[k] = v end end
function getSyntax() local o = {} for k, v in pairs(HC) do o[k] = hex(v) end return o end
function esc(s)
    s = string.gsub(s, "&", "&amp;")
    s = string.gsub(s, "<", "&lt;")
    return (string.gsub(s, ">", "&gt;"))
end
local function paint(c, s) return '<font color="' .. hex(c) .. '">' .. esc(s) .. "</font>" end
function highlight(src)
    if #src > 30000 then return esc(src) end
    local out, i, n = {}, 1, #src
    while i <= n do
        local c = string.sub(src, i, i)
        if string.sub(src, i, i + 1) == "--" then
            local lvl = string.match(src, "^%-%-%[(=*)%[", i)
            local j
            if lvl then
                local _, e = string.find(src, "]" .. lvl .. "]", i, true)
                j = e or n
            else
                j = (string.find(src, "\n", i, true) or (n + 1)) - 1
            end
            out[#out + 1] = paint(HC.comment, string.sub(src, i, j))
            i = j + 1
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local d = string.sub(src, j, j)
                if d == "\\" then j = j + 2
                elseif d == c then break
                elseif d == "\n" then j = j - 1 break
                else j = j + 1 end
            end
            j = math.min(j, n)
            out[#out + 1] = paint(HC.str, string.sub(src, i, j))
            i = j + 1
        elseif string.match(c, "%d") then
            local s = string.match(src, "^%d[%w%.]*", i)
            out[#out + 1] = paint(HC.num, s)
            i = i + #s
        elseif string.match(c, "[%a_]") then
            local w = string.match(src, "^[%w_]+", i)
            if KW[w] then out[#out + 1] = paint(HC.kw, w)
            elseif BI[w] then out[#out + 1] = paint(HC.bi, w)
            else out[#out + 1] = esc(w) end
            i = i + #w
        else
            local run = string.match(src, "^[^%w_\"'%-]+", i) or c
            out[#out + 1] = esc(run)
            i = i + #run
        end
    end
    return table.concat(out)
end

end) if not ok_blk14 then warn("[blk14] " .. tostring(err_blk14)) end
if type(DB.activeSyn) == "table" then setSyntax(DB.activeSyn) end

----------------------------------------------------------------------
-- INJECTOR (INJECT / SPAM)
----------------------------------------------------------------------
local injected, injecting, injectPct = false, false, 0
local injectError
local INJ = { ui = {}, gated = {}, hooks = {} }
local spam = { on = false, n = 0, token = 0, ui = {} }
local doInject, toggleSpam, stopSpam, runAutoExec

local function refreshInjectUI()
    for _, P in ipairs(INJ.ui) do
        if P.b.Parent then
            if injecting then
                P.t.Text = "INJECTING " .. injectPct .. "%"
                P.set(true)
            elseif injected then
                P.t.Text = "INJECTED"
                P.set(false)
                P.t.TextColor3 = C.ok
                if P.i then tint(P.i, C.ok) end
            else
                P.t.Text = injectError and "RETRY" or "INJECT"
                P.set(true)
            end
        end
    end
    for _, P in ipairs(INJ.gated) do
        if P.b.Parent then P.b.BackgroundTransparency = injected and 0 or 0.55 end
    end
    for _, fn in ipairs(INJ.hooks) do pcall(fn) end
end


-- print / warn into the REAL Roblox console (F9). Executors often redirect the global
-- print to their own console, so several output paths are offered (Settings > Roblox console).
local function realOut(kind, msg)
    local mode = S.outMode or "Auto"
    pcall(function()
        local function viaRoblox()
            local okR, renv = pcall(function() return getrenv and getrenv() end)
            local f = okR and renv and ((kind == "warn") and renv.warn or renv.print)
            if f then f(msg) return true end
            return false
        end
        local function viaExecutor() ((kind == "warn") and warn or print)(msg) end
        local function viaTest()
            local ts = game:GetService("TestService")
            if kind == "warn" then ts:Warn(false, msg) else ts:Message(msg) end
        end
        if mode == "Executor" then viaExecutor()
        elseif mode == "TestService" then viaTest()
        elseif mode == "Error" then task.defer(error, msg, 0)
        else
            if not viaRoblox() then viaExecutor() end
        end
    end)
end

-- make print/warn of executed code also show up in our Console
local function mirrorPrints(fn)
    pcall(function()
        local base = getfenv(fn)
        local function pack(...)
            local t = {}
            for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
            return table.concat(t, "\t")
        end
        local env = setmetatable({
            print = function(...)
                local m = pack(...)
                recentOut[m] = os.clock()
                addLog("PRINT", m)
                realOut("print", m)
                return
            end,
            warn = function(...)
                local m = pack(...)
                recentOut[m] = os.clock()
                addLog("WARN", m)
                realOut("warn", m)
                return
            end,
        }, { __index = base, __newindex = base })
        setfenv(fn, env)
    end)
end

local function pulseInject()
    for _, P in ipairs(INJ.ui) do
        if P.b.Parent and P.b.Visible then
            task.spawn(function()
                for _, r in ipairs({ 5, -5, 4, -4, 0 }) do P.b.Rotation = r task.wait(0.04) end
            end)
        end
    end
end

local function makeInjectButton(parent, size)
    local P = pill(parent, nil, "bolt", size, function() doInject() end, true)
    P.t = new("TextLabel", { Parent = P.b, LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = C.black, Text = "INJECT" })
    INJ.ui[#INJ.ui + 1] = P
    refreshInjectUI()
    return P
end

function doInject(auto)
    if injecting then return end
    if injected then if not auto then notify(T("Injected")) end return end
    injecting, injectError = true, nil
    local function prog(p, msg)
        injectPct = p
        refreshInjectUI()
        if msg then addLog("INFO", "Injector: " .. msg) end
    end
    task.spawn(function()
        prog(5, "attaching to client...")
        task.wait(0.2)
        prog(35, "checking runtime (loadstring)...")
        local okLs, fn = pcall(loadstring, "return 1")
        local runOk, val = false, nil
        if okLs and type(fn) == "function" then runOk, val = pcall(fn) end
        local loadOk = okLs and runOk and val == 1
        task.wait(0.2)
        prog(65, "reading environment...")
        local ex = "unknown"
        pcall(function() if identifyexecutor then ex = tostring((identifyexecutor())) end end)
        local okH, vH = pcall(function() return game.HttpGet end)
        local caps = {}
        if request or http_request or (syn and syn.request) then caps[#caps + 1] = "request" end
        if okH and vH ~= nil then caps[#caps + 1] = "HttpGet" end
        if writefile and readfile then caps[#caps + 1] = "files" end
        if setclipboard then caps[#caps + 1] = "clipboard" end
        if setfpscap then caps[#caps + 1] = "fpscap" end
        if getgenv then caps[#caps + 1] = "getgenv" end
        addLog("INFO", "Env report: loadstring=" .. tostring(loadOk) .. "  executor=" .. ex .. "  caps=" .. (#caps > 0 and table.concat(caps, ",") or "none"))
        task.wait(0.2)
        if not loadOk then
            injecting, injected, injectPct = false, false, 0
            injectError = "loadstring is not available - this environment cannot execute code (use an executor, not Studio)"
            refreshInjectUI()
            addLog("ERROR", "Injector: " .. injectError)
            notify(T("Inject failed: loadstring unavailable"))
            if CFG.Discord.SendOnFail then DISC.post("inject_failed") end
            return
        end
        if S.backdoorScan then
            prog(78, "scanning the game for backdoors (Backdoor Mode)...")
            local hits, scanned = BD.scan(function(f) prog(78 + f * 15) end)
            BD.lastHits = hits
            if #hits > 0 then
                addLog("WARN", "Backdoor Mode: " .. #hits .. " suspicious item(s) found out of " .. scanned .. " scanned (heuristic, check manually)")
                notify(G("Backdoor Mode: ", "Backdoor Mode: ") .. #hits .. G(" suspicious item(s) found - see Console", " подозрительных объектов - смотри Console"))
            else
                addLog("INFO", "Backdoor Mode: no suspicious names or webhook strings found (" .. scanned .. " instances, heuristic only)")
            end
        end
        prog(100, "ready (" .. ex .. ")")
        task.wait(0.1)
        injected, injecting, injectError = true, false, nil
        refreshInjectUI()
        addLog("INFO", "Injector: injected - Run, Spam and the script catalog are now enabled")
        if CFG.Discord.SendOnInject then DISC.post("injected") end
        if S.autoExec and runAutoExec then
            task.delay(math.max(0, S.autoDelay or 1), function() runAutoExec() end)
        end
        if not auto then notify(T("Injected")) end
    end)
end

local function paintSpam()
    for _, P in ipairs(spam.ui) do
        if P.b.Parent then
            if spam.on then
                P.t.Text = "STOP " .. spam.n .. (S.spamCount > 0 and ("/" .. S.spamCount) or "")
                P.t.TextColor3 = C.err
                if P.i then tint(P.i, C.err) end
            else
                P.t.Text = "SPAM"
                P.t.TextColor3 = C.text
                if P.i then tint(P.i, C.text) end
            end
        end
    end
end

function stopSpam(reason)
    if not spam.on then return end
    spam.on = false
    addLog("INFO", "Spam " .. (reason or "stopped") .. " after " .. spam.n .. " runs")
    paintSpam()
end

function toggleSpam(name, src)
    if spam.on then stopSpam("stopped") return end
    if not injected then notify(T("Press INJECT first")) pulseInject() return end
    if not string.find(src or "", "%S") then notify(T("Editor is empty")) return end
    local ok, fn, err = pcall(loadstring, src)
    if not ok or not fn then
        addLog("ERROR", "Spam: " .. tostring(ok and err or fn))
        notify("Syntax error (see Console)")
        return
    end
    mirrorPrints(fn)
    notify("Spam started: " .. name)
    spam.on, spam.n = true, 0
    spam.token = spam.token + 1
    local my, errs = spam.token, 0
    addLog("INFO", ("Spam started: %s  every %.2fs  x%d per tick%s"):format(name, S.spamInterval, S.spamBurst,
        S.spamCount > 0 and ("  (limit " .. S.spamCount .. ")") or "  (until stopped)"))
    paintSpam()
    task.spawn(function()
        while spam.on and my == spam.token and alive do
            for _ = 1, math.clamp(S.spamBurst, 1, 10) do
                if not spam.on or my ~= spam.token then break end
                local ok2, e = pcall(fn)
                spam.n = spam.n + 1
                if not ok2 then
                    errs = errs + 1
                    if errs <= 5 then
                        addLog("ERROR", "Spam: " .. tostring(e))
                        realOut("warn", "[SM1LER] spam: " .. tostring(e))
                    end
                    if S.spamStopOnError then stopSpam("stopped on error") return end
                end
                if S.spamCount > 0 and spam.n >= S.spamCount then stopSpam("finished") return end
            end
            paintSpam()
            task.wait(math.max(0, S.spamInterval))
        end
    end)
end

local function makeSpamButton(parent, size, getSrc, getName)
    local P = pill(parent, nil, "bolt", size, function() toggleSpam(getName(), getSrc()) end)
    P.t = new("TextLabel", { Parent = P.b, LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text, Text = "SPAM" })
    spam.ui[#spam.ui + 1] = P
    INJ.gated[#INJ.gated + 1] = P
    paintSpam()
    return P
end

----------------------------------------------------------------------
-- EDITOR
----------------------------------------------------------------------
local tabs, activeTab, tabCounter = {}, 1, 0
local editorBox, lineLabel, hlLabel, tabBar, suppress, rebuildTabs

local function newTab(src, name)
    tabCounter = tabCounter + 1
    tabs[#tabs + 1] = { name = name or ("Script " .. tabCounter), src = src or "", hist = { src or "" }, hi = 1 }
    activeTab = #tabs
end
local function refreshCode()
    local text = editorBox.Text
    local n = 1
    for _ in string.gmatch(text, "\n") do n = n + 1 end
    local nums = {}
    for i = 1, n do nums[i] = tostring(i) end
    lineLabel.Text = table.concat(nums, "\n")
    hlLabel.Text = highlight(text)
end
local function loadTab()
    suppress = true
    editorBox.Text = tabs[activeTab].src
    suppress = false
    refreshCode()
    rebuildTabs()
end

local ok_blk15, err_blk15 = pcall(function()
    local editorPage = addPage("Editor", "pencil")
    newTab('-- ' .. string.lower(CFG.Name) .. '\nprint("hello from ' .. CFG.Name .. '")')
    local h = new("Frame", { Parent = editorPage, Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1 })
    tabBar = new("ScrollingFrame", {
        Parent = h, Size = UDim2.new(1, -212, 1, 0), BackgroundTransparency = 1, ScrollBarThickness = 0, BorderSizePixel = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.X,
    }, { hlist(6) })
    local actions = new("Frame", { Parent = h, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 204, 1, 0), BackgroundTransparency = 1 },
        { hlist(4, Enum.HorizontalAlignment.Right) })

    local function pushHist()
        local tb = tabs[activeTab]
        if not tb or tb.src == tb.hist[tb.hi] then return end
        for i = #tb.hist, tb.hi + 1, -1 do table.remove(tb.hist, i) end
        tb.hist[#tb.hist + 1] = tb.src
        if #tb.hist > 60 then table.remove(tb.hist, 1) end
        tb.hi = #tb.hist
    end
    local function stepHist(d)
        pushHist()
        local tb = tabs[activeTab]
        local ni = tb.hi + d
        if ni < 1 then notify("Nothing to undo") return end
        if ni > #tb.hist then notify("Nothing to redo") return end
        tb.hi, tb.src = ni, tb.hist[ni]
        loadTab()
        notify(d < 0 and "Undone" or "Redone")
    end
    local function ab(name, order, cb) local b = iconBtn(actions, name, 32, cb) b.LayoutOrder = order return b end
    ab("undo", 1, function() stepHist(-1) end)
    ab("redo", 2, function() stepHist(1) end)
    ab("copy", 3, function()
        if setclipboard then setclipboard(editorBox.Text) notify("Script copied") else notify("Clipboard not supported") end
    end)
    ab("plus", 4, function() newTab("") loadTab() end)

    local box = new("ScrollingFrame", {
        Parent = editorPage, Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 1, -142), BackgroundColor3 = C.panel,
        BorderSizePixel = 0, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.XY, CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.XY,
    }, { round(12), stroke() })
    local crumbRow = new("Frame", { Parent = editorPage, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 })
    local crumb = txt(crumbRow, "", 12, C.text, Enum.Font.GothamMedium)
    crumb.Position, crumb.Size = UDim2.fromOffset(4, 0), UDim2.new(1, -130, 1, 0)
    local injB = makeInjectButton(crumbRow, UDim2.fromOffset(108, 26))
    injB.b.AnchorPoint, injB.b.Position = Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0)
    task.spawn(function()
        while alive do
            local tb = tabs[activeTab]
            crumb.Text = tb and tb.name or ""
            task.wait(0.3)
        end
    end)
    local statusLbl = new("TextLabel", { Parent = editorPage, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -6, 1, -46), Size = UDim2.fromOffset(320, 16),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Right,
        Text = "Ln 1, Col 1    Spaces: 4    UTF-8    Luau" })
    lineLabel = new("TextLabel", {
        Parent = box, Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(26, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Top,
        Font = Enum.Font.Code, TextSize = S.font, TextColor3 = C.sub, Text = "1",
    })
    hlLabel = new("TextLabel", {
        Parent = box, Position = UDim2.fromOffset(44, 8), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1, RichText = true, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Code, TextSize = S.font, TextColor3 = C.text, Text = "",
    })
    editorBox = new("TextBox", {
        Parent = box, Position = UDim2.fromOffset(44, 8), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1, MultiLine = true, ClearTextOnFocus = false, TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Code,
        TextSize = S.font, TextColor3 = C.text, TextTransparency = 1, Text = "", ZIndex = 2,
    }, { new("UISizeConstraint", { MinSize = Vector2.new(420, 150) }) })
    hlLabel:GetPropertyChangedSignal("AbsoluteSize")
    local tok = 0
    bind(editorBox:GetPropertyChangedSignal("Text"), function()
        if string.find(editorBox.Text, "\t", 1, true) then
            local cp = editorBox.CursorPosition
            editorBox.Text = (string.gsub(editorBox.Text, "\t", "    "))
            editorBox.CursorPosition = cp + 3
            return
        end
        tabs[activeTab].src = editorBox.Text
        refreshCode()
        if suppress then return end
        tok = tok + 1
        local my = tok
        task.delay(0.6, function() if my == tok then pushHist() end end)
    end)

    -- visible blinking caret + current-line highlight + selection (the real TextBox text is transparent)
    do
        local TextService = game:GetService("TextService")
        local caret = new("Frame", { Parent = box, Size = UDim2.fromOffset(2, 14), BackgroundColor3 = C.white, BorderSizePixel = 0, Visible = false, ZIndex = 5 }, { round(1) })
        local lineHL = new("Frame", { Parent = box, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.93, BorderSizePixel = 0, Visible = false, ZIndex = 0 })
        local selHolder = new("Frame", { Parent = box, Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, ZIndex = 0 })
        local selPool, blinkT = {}, 0
        local function metrics()
            local big = Vector2.new(100000, 100000)
            local sz, f = editorBox.TextSize, editorBox.Font
            local a = TextService:GetTextSize("0000000000", sz, f, big)
            local b = TextService:GetTextSize("0000000000\n0000000000", sz, f, big)
            return a.X / 10, math.max(1, b.Y - a.Y)
        end
        local function lineCol(text, p)
            local before = string.sub(text, 1, p - 1)
            local _, nl = string.gsub(before, "\n", "")
            local last = string.match(before, ".*()\n")
            local seg = last and string.sub(before, last + 1) or before
            return nl, utf8.len(seg) or #seg
        end
        local function hideSel() for _, f in ipairs(selPool) do f.Visible = false end end
        local function showSel(text, cw, lh, a, b)
            if a > b then a, b = b, a end
            local l1, c1 = lineCol(text, a)
            local l2, c2 = lineCol(text, b)
            local lines = string.split(text, "\n")
            local n = 0
            for L = l1, math.min(l2, l1 + 300) do
                n = n + 1
                local f = selPool[n]
                if not f then
                    f = new("Frame", { Parent = selHolder, BackgroundColor3 = Color3.fromRGB(70, 110, 200), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 0 })
                    selPool[n] = f
                end
                local ln = lines[L + 1] or ""
                local lineLen = utf8.len(ln) or #ln
                local sc = (L == l1) and c1 or 0
                local ec = (L == l2) and c2 or (lineLen + 1)
                f.Position = UDim2.fromOffset(44 + sc * cw, 8 + L * lh)
                f.Size = UDim2.fromOffset(math.max(2, (ec - sc) * cw), lh)
                f.Visible = true
            end
            for i = n + 1, #selPool do selPool[i].Visible = false end
        end
        local function ensureVisible(x, y, lh)
            local cp, vs = box.CanvasPosition, box.AbsoluteWindowSize
            local nx, ny = cp.X, cp.Y
            if y < cp.Y then ny = y - 6
            elseif y + lh > cp.Y + vs.Y - 8 then ny = y + lh - vs.Y + 12 end
            if x < cp.X + 48 then nx = x - 70
            elseif x > cp.X + vs.X - 24 then nx = x - vs.X + 48 end
            nx, ny = math.max(0, nx), math.max(0, ny)
            if nx ~= cp.X or ny ~= cp.Y then box.CanvasPosition = Vector2.new(nx, ny) end
        end
        local function updateCaret(scrollTo)
            if not (editorBox and editorBox.Parent) then return end
            if not editorBox:IsFocused() then
                caret.Visible, lineHL.Visible = false, false
                hideSel()
                return
            end
            local p = editorBox.CursorPosition
            if p < 1 then return end
            local text = editorBox.Text
            local cw, lh = metrics()
            local ln, col = lineCol(text, p)
            local x, y = 44 + col * cw, 8 + ln * lh
            statusLbl.Text = ("Ln %d, Col %d    Spaces: 4    UTF-8    Luau"):format(ln + 1, col + 1)
            blinkT = 0
            caret.BackgroundTransparency = 0
            caret.Size = UDim2.fromOffset(2, lh)
            caret.Position = UDim2.fromOffset(math.floor(x - 1), y)
            caret.Visible = true
            local ss = editorBox.SelectionStart
            if ss and ss ~= -1 and ss ~= p then
                lineHL.Visible = false
                showSel(text, cw, lh, ss, p)
            else
                hideSel()
                lineHL.Position = UDim2.fromOffset(38, y)
                lineHL.Size = UDim2.new(1, -42, 0, lh)
                lineHL.Visible = true
            end
            if scrollTo then task.defer(ensureVisible, x, y, lh) end
        end
        bind(editorBox:GetPropertyChangedSignal("CursorPosition"), function() updateCaret(true) end)
        bind(editorBox:GetPropertyChangedSignal("SelectionStart"), function() updateCaret(false) end)
        bind(editorBox:GetPropertyChangedSignal("Text"), function() task.defer(updateCaret, true) end)
        bind(editorBox:GetPropertyChangedSignal("TextSize"), function() task.defer(updateCaret, false) end)
        bind(editorBox.Focused, function() task.defer(updateCaret, true) end)
        bind(editorBox.FocusLost, function() updateCaret(false) end)
        bind(RunService.Heartbeat, function(dt)
            if not caret.Visible then return end
            blinkT = blinkT + dt
            caret.BackgroundTransparency = (blinkT % 1.1) < 0.6 and 0 or 1
        end)
    end

    local bar = new("Frame", { Parent = editorPage, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 },
        { hlist(8, Enum.HorizontalAlignment.Right) })
    local function eb(key, ic, order, cb, primary)
        local P = pill(bar, key, ic, UDim2.fromOffset(primary and 92 or 84, 36), cb, primary)
        P.b.LayoutOrder = order
        return P
    end
    local function saveCurrent()
        local tb = tabs[activeTab]
        for _, s in ipairs(DB.scripts) do
            if s.name == tb.name then s.src = tb.src saveDB() notify("Updated " .. tb.name) return end
        end
        DB.scripts[#DB.scripts + 1] = { name = tb.name, desc = "Saved from editor.", src = tb.src }
        saveDB()
        if genv.__SM1LER_refresh then genv.__SM1LER_refresh() end
        notify("Saved " .. tb.name)
    end
    genv.__SM1LER_saveCurrent = saveCurrent
    eb("Save", "save", 1, saveCurrent)
    eb("Paste", "paste", 2, function()
        if getclipboard then
            local ok, t = pcall(getclipboard)
            if ok and t then editorBox.Text = t notify("Pasted") return end
        end
        editorBox:CaptureFocus()
        notify("Use Ctrl+V to paste")
    end)
    eb("Clear", "trash", 3, function() editorBox.Text = "" end)
    local runP = eb("Run", "play", 5, function() runSource(tabs[activeTab].name, editorBox.Text) end, true)
    INJ.gated[#INJ.gated + 1] = runP
    local injP = makeInjectButton(bar, UDim2.fromOffset(112, 36))
    injP.b.LayoutOrder = 0
    local spP = makeSpamButton(bar, UDim2.fromOffset(94, 36), function() return editorBox.Text end, function() return tabs[activeTab].name end)
    spP.b.LayoutOrder = 4
    refreshInjectUI()

    -- ===== Volt-style file tree (left) + terminal (bottom) =====
    local TREEW = 168
    local edMain = new("Frame", { Parent = editorPage, Position = UDim2.fromOffset(TREEW + 8, 0), Size = UDim2.new(1, -(TREEW + 8), 1, 0), BackgroundTransparency = 1 })
    for _, o in ipairs({ h, crumbRow, box, statusLbl, bar }) do o.Parent = edMain end
    local tree = new("Frame", { Parent = editorPage, Size = UDim2.new(0, TREEW, 1, 0), BackgroundColor3 = C.panel }, { round(12), stroke() })
    local srch = new("TextBox", { Parent = tree, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 28), BackgroundColor3 = C.item, TextColor3 = C.text,
        PlaceholderColor3 = C.sub, PlaceholderText = G("Search files...", "Поиск файлов..."), Font = Enum.Font.Gotham, TextSize = 12, Text = "", ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left }, { round(8), new("UIPadding", { PaddingLeft = UDim.new(0, 8) }) })
    local tl = new("ScrollingFrame", { Parent = tree, Position = UDim2.fromOffset(4, 44), Size = UDim2.new(1, -8, 1, -50), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, { vlist(2) })
    local secOpen = { Scripts = true, ["Auto-Execute"] = true, Workspace = false }
    local lastSig = ""
    local function wsFiles()
        local out = {}
        if not listfiles then return out end
        local items
        for _, q in ipairs({ "", "." }) do
            local ok, r = pcall(listfiles, q)
            if ok and type(r) == "table" and #r > 0 then items = r break end
        end
        for _, f in ipairs(items or {}) do
            if type(f) == "string" then
                local path = (string.gsub(f, "\\", "/"))
                local low = string.lower(path)
                local okF, isF = pcall(isfolder or function() return false end, path)
                if not (okF and isF) and (string.sub(low, -4) == ".lua" or string.sub(low, -5) == ".luau" or string.sub(low, -4) == ".txt") then
                    out[#out + 1] = path
                end
            end
        end
        table.sort(out)
        return out
    end
    local function treeRender()
        for _, c in ipairs(tl:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
        local q = string.lower(srch.Text)
        local order = 0
        local function row(depth, text, iconName, cb, bold)
            order = order + 1
            local b = new("TextButton", { Parent = tl, LayoutOrder = order, Size = UDim2.new(1, -4, 0, 26), BackgroundColor3 = C.item, BackgroundTransparency = 1,
                AutoButtonColor = false, Text = "" }, { round(6) })
            local ic = icon(b, iconName, 12, C.sub)
            ic.Position = UDim2.fromOffset(6 + depth * 12, 7)
            local t = txt(b, text, 12, bold and C.text or C.sub, bold and Enum.Font.GothamMedium or Enum.Font.Gotham)
            t.Position, t.Size, t.TextTruncate = UDim2.fromOffset(24 + depth * 12, 0), UDim2.new(1, -28 - depth * 12, 1, 0), Enum.TextTruncate.AtEnd
            b.MouseEnter:Connect(function() tween(b, 0.1, { BackgroundTransparency = 0.6 }) end)
            b.MouseLeave:Connect(function() tween(b, 0.1, { BackgroundTransparency = 1 }) end)
            b.MouseButton1Click:Connect(cb)
            return b
        end
        local function section(key, label, items)
            local shown = {}
            for _, it in ipairs(items) do
                if q == "" or string.find(string.lower(it.name), q, 1, true) then shown[#shown + 1] = it end
            end
            if q ~= "" and #shown == 0 then return end
            local isOpen = secOpen[key] or q ~= ""
            row(0, label .. "  " .. #shown, isOpen and "down" or "right", function()
                secOpen[key] = not secOpen[key]
                treeRender()
            end, true)
            if isOpen then
                for _, it in ipairs(shown) do row(1, it.name, "code", it.cb) end
                if #shown == 0 then
                    local e = row(1, G("(empty)", "(пусто)"), "code", function() end)
                end
            end
        end
        local scripts, auto = {}, {}
        for _, sc in ipairs(DB.scripts or {}) do
            scripts[#scripts + 1] = { name = sc.name, cb = function() openInEditor(sc.name, sc.src) end }
        end
        for _, nm in ipairs(type(DB.autoList) == "table" and DB.autoList or {}) do
            for _, sc in ipairs(DB.scripts or {}) do
                if sc.name == nm then auto[#auto + 1] = { name = nm, cb = function() openInEditor(sc.name, sc.src) end } break end
            end
        end
        section("Scripts", G("Scripts", "Скрипты"), scripts)
        section("Auto-Execute", G("Auto-Execute", "Автозапуск"), auto)
        local ws = {}
        if secOpen.Workspace or q ~= "" then
            for _, f in ipairs(wsFiles()) do
                ws[#ws + 1] = { name = string.match(f, "[^/]+$") or f, cb = function()
                    local ok, body = pcall(readfile, f)
                    if ok and type(body) == "string" then openInEditor(string.match(f, "[^/]+$") or f, body) else notify(G("Cannot read the file", "Не удалось прочитать файл")) end
                end }
            end
        end
        section("Workspace", G("Workspace", "Workspace"), ws)
    end
    bind(srch:GetPropertyChangedSignal("Text"), treeRender)
    treeRender()
    task.spawn(function()
        while alive do
            task.wait(1.5)
            if currentPage == "Editor" and tree.Visible then
                local names = {}
                for _, sc in ipairs(DB.scripts or {}) do names[#names + 1] = sc.name end
                local sig = table.concat(names, "|") .. "#" .. #(type(DB.autoList) == "table" and DB.autoList or {})
                if sig ~= lastSig then lastSig = sig treeRender() end
            end
        end
    end)
    local edLayout
    local listBtn = ab("list", 0, function()
        S.treeOpen = not (S.treeOpen ~= false)
        saveDB()
        edLayout()
    end)

    -- terminal under the editor
    local TERM_H = 104
    local term = new("Frame", { Parent = edMain, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -70), Size = UDim2.new(1, 0, 0, TERM_H),
        BackgroundColor3 = C.panel, Visible = false }, { round(12), stroke() })
    local th = txt(term, G("Terminal", "Терминал"), 12, C.text, Enum.Font.GothamBold)
    th.Position, th.Size = UDim2.fromOffset(12, 0), UDim2.fromOffset(120, 24)
    local clr = new("TextButton", { Parent = term, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 2), Size = UDim2.fromOffset(60, 20), BackgroundTransparency = 1,
        Text = G("Clear", "Очистить"), Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = C.sub, AutoButtonColor = false })
    local tlist = new("ScrollingFrame", { Parent = term, Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 1, -32), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, { vlist(1) })
    local rows = 0
    local KC = { ERROR = C.err, WARN = C.warn, INFO = C.info }
    local function addTermRow(e)
        rows = rows + 1
        local l = new("TextLabel", { Parent = tlist, LayoutOrder = rows, Size = UDim2.new(1, -4, 0, 14), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11,
            TextColor3 = KC[e.k] or C.text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "[" .. e.t .. "] " .. string.gsub(e.m, "[\r\n]+", " ") })
        local kids = tlist:GetChildren()
        if #kids > 140 then
            for _, c in ipairs(kids) do if c:IsA("TextLabel") then c:Destroy() break end end
        end
        tlist.CanvasPosition = Vector2.new(0, 1e6)
    end
    for i = math.max(1, #logs - 30), #logs do addTermRow(logs[i]) end
    logHooks[#logHooks + 1] = addTermRow
    bind(clr.MouseButton1Click, function()
        for _, c in ipairs(tlist:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
    end)
    local termBtn = new("TextButton", { Parent = edMain, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 2, 1, -46), Size = UDim2.fromOffset(120, 16), BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false, Text = "" })
    local termOn = S.termOpen == true
    local lastTabStyle = TH.tabStyle
    function edLayout()
        local c = TH
        local treeOn = c.edTree and S.treeOpen ~= false
        local right = c.treeSide == "right"
        tree.Visible = treeOn
        tree.Position = right and UDim2.new(1, -TREEW, 0, 0) or UDim2.fromOffset(0, 0)
        listBtn.Visible = c.edTree
        edMain.Position = (treeOn and not right) and UDim2.fromOffset(TREEW + 8, 0) or UDim2.fromOffset(0, 0)
        edMain.Size = UDim2.new(1, treeOn and -(TREEW + 8) or 0, 1, 0)
        local topBarOn = c.toolbarPos ~= "bottom"
        crumbRow.Visible = c.edCrumb
        if topBarOn then
            crumbRow.AnchorPoint, crumbRow.Position = Vector2.new(0, 0), UDim2.fromOffset(0, 40)
        else
            crumbRow.AnchorPoint, crumbRow.Position = Vector2.new(0, 1), UDim2.new(0, 0, 1, -40)
        end
        statusLbl.Visible = c.edStatus
        term.Visible = termOn
        termBtn.Text = (termOn and "▾ " or "▸ ") .. G("Terminal", "Терминал")
        local top = topBarOn and (40 + (c.edCrumb and 32 or 0)) or 40
        box.Position = UDim2.fromOffset(0, top)
        box.Size = UDim2.new(1, 0, 1, -(top + 70 + (termOn and (TERM_H + 6) or 0) + ((c.edCrumb and not topBarOn) and 32 or 0)))
        if lastTabStyle ~= c.tabStyle then
            lastTabStyle = c.tabStyle
            if rebuildTabs then pcall(rebuildTabs) end
        end
    end
    bind(termBtn.MouseButton1Click, function()
        termOn = not termOn
        S.termOpen = termOn
        saveDB()
        edLayout()
    end)
    LY.hooks[#LY.hooks + 1] = edLayout
    edLayout()

    function rebuildTabs()
        for _, c in ipairs(tabBar:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
        for i, tb in ipairs(tabs) do
            local on = i == activeTab
            local flat = TH.tabStyle == "flat"
            local f = new("TextButton", {
                Parent = tabBar, LayoutOrder = i, Size = UDim2.fromOffset(flat and 132 or 118, 34), AutoButtonColor = false, Text = "",
                BackgroundColor3 = on and C.item or C.panel, BackgroundTransparency = (flat and not on) and 1 or 0,
            }, { round(flat and 6 or 10) })
            if flat and on then
                new("Frame", { Parent = f, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.white, BorderSizePixel = 0 })
            end
            local l = txt(f, tb.name, 12, on and C.text or C.sub, Enum.Font.GothamMedium)
            l.Position = UDim2.fromOffset(12, 0)
            l.Size = UDim2.new(1, -38, 1, 0)
            l.TextTruncate = Enum.TextTruncate.AtEnd
            local cx = new("TextButton", {
                Parent = f, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(22, 22),
                BackgroundTransparency = 1, Text = "",
            })
            centered(icon(cx, "x", 11, C.sub)).Parent = cx
            bind(f.MouseButton1Click, function() activeTab = i loadTab() end)
            bind(cx.MouseButton1Click, function()
                if #tabs == 1 then tabs[1].src, tabs[1].hist, tabs[1].hi = "", { "" }, 1 loadTab() return end
                table.remove(tabs, i)
                if activeTab > i or activeTab > #tabs then activeTab = math.max(1, activeTab - 1) end
                loadTab()
            end)
        end
    end
    loadTab()
end) if not ok_blk15 then warn("[blk15] " .. tostring(err_blk15)) end
function openInEditor(name, src)
    newTab(src, name)
    loadTab()
    showPage("Editor")
end

----------------------------------------------------------------------
-- RUN
----------------------------------------------------------------------
local saveSoon
local ok_blk16, err_blk16 = pcall(function()
    local tok = 0
    saveSoon = function()
        tok = tok + 1
        local my = tok
        task.delay(1.5, function() if my == tok then saveDB() end end)
    end
end) if not ok_blk16 then warn("[blk16] " .. tostring(err_blk16)) end
local function touchRecent(name)
    for i = #DB.recent, 1, -1 do if DB.recent[i] == name then table.remove(DB.recent, i) end end
    table.insert(DB.recent, 1, name)
    while #DB.recent > 20 do table.remove(DB.recent) end
    saveSoon()
end
function runSource(name, src)
    if not injected then
        notify(T("Press INJECT first"))
        pulseInject()
        return
    end
    local t0 = os.clock()
    local ok, fn, err = pcall(loadstring, src)
    if not ok then addLog("ERROR", "loadstring is not available here: " .. tostring(fn)) notify("loadstring unavailable") return end
    if not fn then addLog("ERROR", tostring(err)) notify("Syntax error (see Console)") return end
    local tCompile = os.clock()
    mirrorPrints(fn)
    -- the script starts RIGHT NOW (task.spawn runs it immediately); UI work happens afterwards
    task.spawn(function()
        local good, e = xpcall(fn, function(m) return debug.traceback(tostring(m), 2) end)
        if good then
            addLog("INFO", "Executed " .. name)
            notify("Executed: " .. name)
        else
            addLog("ERROR", e)
            realOut("warn", "[SM1LER] " .. tostring(e))
            notify("Runtime error (see Console)")
        end
    end)
    local tStart = os.clock()
    task.defer(function()
        addLog("INFO", ("Running %s  (compile %.1f ms, started %.1f ms after click)"):format(name, (tCompile - t0) * 1000, (tStart - t0) * 1000))
        touchRecent(name)
        if currentPage == "Scripts" and genv.__SM1LER_refresh then genv.__SM1LER_refresh() end
    end)
end

local function isAuto(name)
    for _, n in ipairs(DB.autoList or {}) do if n == name then return true end end
    return false
end
local function toggleAuto(name)
    DB.autoList = DB.autoList or {}
    for i, n in ipairs(DB.autoList) do
        if n == name then table.remove(DB.autoList, i) saveDB() return false end
    end
    DB.autoList[#DB.autoList + 1] = name
    saveDB()
    return true
end
function runAutoExec()
    local list = DB.autoList
    if type(list) ~= "table" or #list == 0 then return end
    addLog("INFO", "Auto exec: running " .. #list .. " script(s)")
    for _, nm in ipairs(list) do
        for _, sc in ipairs(DB.scripts) do
            if sc.name == nm then runSource(sc.name, sc.src) task.wait(0.3) break end
        end
    end
end

local function http(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and body then return body end
    local req = request or http_request or (syn and syn.request)
    if req then
        local ok2, r = pcall(req, { Url = url, Method = "GET" })
        if ok2 and r and r.Body then return r.Body end
    end
    return nil, tostring(body)
end

----------------------------------------------------------------------
-- SCRIPTS (Local / Hub / URL)
----------------------------------------------------------------------
local ok_blk17, err_blk17 = pcall(function()
    local scriptsPage = addPage("Scripts", "code")
    local h = header(scriptsPage, "Scripts")
    local mode = "Local"
    local srcBar = new("Frame", { Parent = h, AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0, 330, 1, 0), BackgroundTransparency = 1 },
        { hlist(6, Enum.HorizontalAlignment.Right) })
    placeRight(srcBar, 0)
    local panels, srcPills = {}, {}
    local function setMode(m)
        mode = m
        for k, p in pairs(panels) do p.Visible = (k == m) end
        for k, P in pairs(srcPills) do P.set(k == m) end
    end
    for i, d in ipairs({ { "Local", "phone", 88 }, { "ScriptBlox", "bolt", 112 }, { "URL", "globe", 74 } }) do
        local P = pill(srcBar, d[1], d[2], UDim2.fromOffset(d[3], 32), function() setMode(d[1]) end)
        P.b.LayoutOrder = i
        srcPills[d[1]] = P
    end
    for _, k in ipairs({ "Local", "ScriptBlox", "URL" }) do
        panels[k] = new("Frame", { Parent = scriptsPage, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), BackgroundTransparency = 1, Visible = false })
    end

    local function rowItem(list, order, title, subtitle, btns)
        local row = new("Frame", { Parent = list, LayoutOrder = order, Size = UDim2.new(1, -6, 0, 56), BackgroundColor3 = C.panel }, { round(12) })
        local t = txt(row, title, 13, C.text, Enum.Font.GothamMedium)
        t.Position = UDim2.fromOffset(14, 9)
        t.Size = UDim2.new(1, -330, 0, 18)
        t.TextTruncate = Enum.TextTruncate.AtEnd
        local s = txt(row, subtitle or "", 11, C.sub)
        s.Position = UDim2.fromOffset(14, 29)
        s.Size = UDim2.new(1, -330, 0, 16)
        s.TextTruncate = Enum.TextTruncate.AtEnd
        local act = new("Frame", { Parent = row, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(306, 34), BackgroundTransparency = 1 },
            { hlist(6, Enum.HorizontalAlignment.Right) })
        for i, b in ipairs(btns) do
            local P
            if b.only then
                P = { b = iconBtn(act, b.icon, 32, b.cb, b.color) }
                P.b.Size = UDim2.fromOffset(32, 32)
            else
                P = pill(act, b.key, b.icon, UDim2.fromOffset(b.w or 72, 32), b.cb)
            end
            P.b.LayoutOrder = i
        end
        return row
    end
    local function newList(parent, y, hgt)
        return new("ScrollingFrame", {
            Parent = parent, Position = UDim2.fromOffset(0, y), Size = hgt, BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
        }, { vlist(6) })
    end
    local function searchBox(parent, placeholder, size, pos)
        local b = new("TextBox", {
            Parent = parent, Position = pos or UDim2.new(), Size = size, BackgroundColor3 = C.panel, TextColor3 = C.text,
            PlaceholderColor3 = C.sub, Font = Enum.Font.Gotham, TextSize = 13, Text = "", PlaceholderText = placeholder,
            ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
        }, { round(10), stroke(), new("UIPadding", { PaddingLeft = UDim.new(0, 38) }) })
        local ic = icon(b, "search", 15, C.sub)
        ic.Position = UDim2.new(0, -26, 0.5, -7)
        return b
    end

    ---------------- LOCAL
    do
        local p = panels.Local
        local lmode = "Saved"
        local search = searchBox(p, "Search saved scripts", UDim2.new(1, -112, 0, 34))
        local saveP = pill(p, "Save", "save", UDim2.fromOffset(104, 34), function() genv.__SM1LER_saveCurrent() end)
        saveP.b.AnchorPoint = Vector2.new(1, 0)
        saveP.b.Position = UDim2.new(1, 0, 0, 0)
        local tabRow = new("Frame", { Parent = p, Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, { hlist(6) })
        local list = newList(p, 80, UDim2.new(1, 0, 1, -80))
        local tp = {}
        local refresh
        function refresh()
            for _, c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
            for k, P in pairs(tp) do P.set(k == lmode) end
            local q = string.lower(search.Text)
            local items = {}
            if lmode == "Recent" then
                for _, nm in ipairs(DB.recent) do for _, s in ipairs(DB.scripts) do if s.name == nm then items[#items + 1] = s end end end
            else
                for _, s in ipairs(DB.scripts) do if lmode ~= "Favorites" or DB.fav[s.name] then items[#items + 1] = s end end
            end
            local o = 0
            for _, s in ipairs(items) do
                if q == "" or string.find(string.lower(s.name), q, 1, true) then
                    o = o + 1
                    rowItem(list, o, s.name, s.desc, {
                        { only = true, icon = "bolt", color = isAuto(s.name) and C.ok or C.sub, cb = function()
                            local on = toggleAuto(s.name)
                            refresh()
                            notify(on and "Auto exec: ON for this script" or "Auto exec: OFF for this script")
                        end },
                        { only = true, icon = DB.fav[s.name] and "stard" or "star", color = DB.fav[s.name] and C.warn or C.sub, cb = function()
                            DB.fav[s.name] = (not DB.fav[s.name]) or nil
                            saveDB() refresh()
                            notify(DB.fav[s.name] and "Added to favorites" or "Removed from favorites")
                        end },
                        { only = true, icon = "x", color = C.err, cb = function()
                            for i, v in ipairs(DB.scripts) do if v == s then table.remove(DB.scripts, i) break end end
                            DB.fav[s.name] = nil
                            saveDB() refresh()
                            notify("Deleted " .. s.name)
                        end },
                        { key = "Edit", icon = "pencil", w = 76, cb = function() openInEditor(s.name, s.src) end },
                        { key = "Run", icon = "play", w = 72, cb = function() runSource(s.name, s.src) end },
                    })
                end
            end
        end
        genv.__SM1LER_refresh = refresh
        for i, n in ipairs({ "Saved", "Favorites", "Recent" }) do
            local P = pill(tabRow, n, nil, UDim2.fromOffset(104, 30), function() lmode = n refresh() end)
            P.b.LayoutOrder = i
            tp[n] = P
        end
        bind(search:GetPropertyChangedSignal("Text"), refresh)
        refresh()
    end

    ---------------- HUB (ScriptBlox)
    do
        local p = panels.ScriptBlox
        local F = { sort = "Latest", nokey = false, universal = false, unpatched = true, verified = false }
        local query, page, total, busy = "", 1, 1, false
        local thisGame, gameName = false, nil
        local search = searchBox(p, "Search ScriptBlox", UDim2.new(1, -352, 0, 34))
        local filtersP = pill(p, "Filters", "filter", UDim2.fromOffset(108, 34), nil)
        filtersP.b.AnchorPoint = Vector2.new(1, 0)
        filtersP.b.Position = UDim2.new(1, -112, 0, 0)
        local goP = pill(p, "Search", "search", UDim2.fromOffset(104, 34), nil)
        goP.b.AnchorPoint = Vector2.new(1, 0)
        goP.b.Position = UDim2.new(1, 0, 0, 0)
        local thisP = pill(p, "This game", "globe", UDim2.fromOffset(116, 34), nil, true)
        thisP.b.AnchorPoint = Vector2.new(1, 0)
        thisP.b.Position = UDim2.new(1, -228, 0, 0)
        local list = newList(p, 42, UDim2.new(1, 0, 1, -76))
        local foot = new("Frame", { Parent = p, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 })
        local credit = txt(foot, "Scripts from scriptblox.com", 11, C.sub)
        credit.Size = UDim2.new(0.6, 0, 1, 0)
        local pager = new("Frame", { Parent = foot, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 150, 1, 0), BackgroundTransparency = 1 },
            { hlist(8, Enum.HorizontalAlignment.Right) })
        local prev = iconBtn(pager, "left", 26) prev.LayoutOrder = 1
        local pl = txt(pager, "1/1", 12, C.sub, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
        pl.Size = UDim2.fromOffset(54, 26) pl.LayoutOrder = 2
        local nxt = iconBtn(pager, "right", 26) nxt.LayoutOrder = 3

        local function message(text, color)
            for _, c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
            local l = txt(list, text, 12, color or C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)
            l.Size = UDim2.new(1, 0, 0, 60)
            l.TextWrapped = true
        end
        local srcCache = {}
        local function fetchSource(it)
            if type(it.script) == "string" and #it.script > 0 then return it.script end
            if it.slug then
                local body = http(CFG.HubApi .. it.slug)
                if body then
                    local ok, d = pcall(function() return HttpService:JSONDecode(body) end)
                    if ok and d then
                        local r = d.result or d
                        local sc = r.script
                        if type(sc) == "table" then sc = sc.script end
                        if type(sc) == "string" then return sc end
                    end
                end
            end
            return nil
        end
        local function getSource(it)
            local k = it.slug or it._id or it.title
            if k and srcCache[k] then return srcCache[k] end
            if not (type(it.script) == "string" and #it.script > 0) then notify("Fetching script...") end
            local sc = fetchSource(it)
            if sc and k then srcCache[k] = sc end
            return sc
        end
        local function load()
            if busy then return end
            busy = true
            message("Loading...")
            credit.Text = thisGame and ("Scripts for this game: " .. tostring(gameName)) or "Scripts from scriptblox.com"
            task.spawn(function()
                local url
                local sortBy = ({ Latest = "createdAt", Updated = "updatedAt", ["Top views"] = "views" })[F.sort]
                if query ~= "" then
                    url = CFG.HubApi .. "search?q=" .. HttpService:UrlEncode(query) .. "&page=" .. page .. "&max=20&sortBy=" .. sortBy .. "&order=desc"
                else
                    url = CFG.HubApi .. "fetch?page=" .. page .. "&max=20"
                end
                local body, err = http(url)
                busy = false
                if not body then message("Could not reach the hub (needs HTTP access: " .. tostring(err) .. ")", C.err) addLog("WARN", "Hub request failed: " .. tostring(err)) return end
                local ok, d = pcall(function() return HttpService:JSONDecode(body) end)
                local res = ok and d and (d.result or d)
                local scripts = res and res.scripts
                if type(scripts) ~= "table" then message("Unexpected response from the hub.", C.err) return end
                total = tonumber(res.totalPages) or 1
                pl.Text = page .. "/" .. total
                local items = {}
                for _, it in ipairs(scripts) do
                    local keep = true
                    if F.nokey and it.key then keep = false end
                    if F.universal and not it.isUniversal then keep = false end
                    if F.unpatched and it.isPatched then keep = false end
                    if F.verified and not it.verified then keep = false end
                    if keep then items[#items + 1] = it end
                end
                if thisGame then
                    local mine, rest = {}, {}
                    for _, it in ipairs(items) do
                        local g = type(it.game) == "table" and it.game or nil
                        local match = g and (tostring(g.gameId) == tostring(game.PlaceId)
                            or (gameName and string.lower(tostring(g.name or "")) == string.lower(gameName)))
                        it._mine = match and true or false
                        if match then mine[#mine + 1] = it else rest[#rest + 1] = it end
                    end
                    table.sort(mine, function(a, b) return (a.views or 0) > (b.views or 0) end)
                    items = {}
                    for _, it in ipairs(mine) do items[#items + 1] = it end
                    for _, it in ipairs(rest) do items[#items + 1] = it end
                end
                if query == "" then
                    table.sort(items, function(a, b)
                        if F.sort == "Top views" then return (a.views or 0) > (b.views or 0) end
                        local k = F.sort == "Updated" and "updatedAt" or "createdAt"
                        return tostring(a[k] or "") > tostring(b[k] or "")
                    end)
                end
                for _, c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
                if #items == 0 then message("No scripts match these filters.") return end
                for i, it in ipairs(items) do
                    local gname = (type(it.game) == "table" and it.game.name) or (it.isUniversal and "Universal") or "Unknown game"
                    local sub = gname .. " · " .. tostring(it.views or 0) .. " views" .. (it.key and " · key" or "") .. (it._mine and " · THIS GAME" or "")
                    rowItem(list, i, it.title or "Untitled", sub, {
                        { only = true, icon = "star", color = C.sub, cb = function()
                            local s = getSource(it)
                            if not s then notify("Could not fetch source") return end
                            DB.scripts[#DB.scripts + 1] = { name = it.title or "Hub script", desc = gname, src = s }
                            DB.fav[it.title or "Hub script"] = true
                            saveDB()
                            if genv.__SM1LER_refresh then genv.__SM1LER_refresh() end
                            notify("Added to favorites")
                        end },
                        { key = "Edit", icon = "pencil", w = 76, cb = function()
                            local s = getSource(it)
                            if s then openInEditor(it.title or "Hub script", s) else notify("Could not fetch source") end
                        end },
                        { key = "Run", icon = "play", w = 72, cb = function()
                            local s = getSource(it)
                            if s then runSource(it.title or "Hub script", s) else notify("Could not fetch source") end
                        end },
                    })
                end
            end)
        end
        local function doSearch() thisGame = false query = search.Text page = 1 load() end
        bind(thisP.b.MouseButton1Click, function()
            task.spawn(function()
                if not gameName then
                    local ok, inf = pcall(function() return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId) end)
                    gameName = (ok and inf and inf.Name) or game.Name
                end
                local q = gameName
                q = string.gsub(q, "%b[]", "")
                q = string.gsub(q, "%b()", "")
                q = string.gsub(q, "[^%w%s]", " ")
                q = string.gsub(q, "%s+", " ")
                q = string.gsub(q, "^%s+", "")
                q = string.gsub(q, "%s+$", "")
                if q == "" then q = gameName end
                thisGame = true
                search.Text = q
                query, page = q, 1
                load()
            end)
        end)
        bind(goP.b.MouseButton1Click, doSearch)
        bind(search.FocusLost, function(enter) if enter then doSearch() end end)
        bind(prev.MouseButton1Click, function() if page > 1 then page = page - 1 load() end end)
        bind(nxt.MouseButton1Click, function() if page < total then page = page + 1 load() end end)

        bind(filtersP.b.MouseButton1Click, function()
            local card, close = modal("Filters", 340, 262)
            local function chips(y, title, defs)
                local t = txt(card, "", 12, C.sub, Enum.Font.GothamMedium)
                t.Position = UDim2.fromOffset(0, y)
                t.Size = UDim2.new(1, 0, 0, 16)
                t.ZIndex = 22
                reg(t, title)
                local g = new("Frame", { Parent = card, Position = UDim2.fromOffset(0, y + 20), Size = UDim2.new(1, 0, 0, 36 * math.ceil(#defs / 2) + 6 * (math.ceil(#defs / 2) - 1)), BackgroundTransparency = 1, ZIndex = 22 },
                    { new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 34), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
                for i, d in ipairs(defs) do
                    local P = pill(g, d.key, nil, UDim2.new(), function() d.click(d.P) end)
                    P.b.LayoutOrder = i
                    P.b.ZIndex = 22
                    if P.t then P.t.ZIndex = 23 end
                    d.P = P
                    P.set(d.get())
                end
                return defs
            end
            local sortDefs = {}
            for _, n in ipairs({ "Latest", "Updated", "Top views" }) do
                sortDefs[#sortDefs + 1] = { key = n, get = function() return F.sort == n end, click = function()
                    F.sort = n
                    for _, d in ipairs(sortDefs) do d.P.set(d.key == n) end
                end }
            end
            chips(32, "Sort", sortDefs)
            local function flag(key, field) return { key = key, get = function() return F[field] end, click = function(P) F[field] = not F[field] P.set(F[field]) end } end
            local onlyDefs = { flag("No key", "nokey"), flag("Universal", "universal"), flag("Unpatched", "unpatched"), flag("Verified", "verified") }
            chips(102, "Only show", onlyDefs)
            local reset = pill(card, "Reset", "refresh", UDim2.fromOffset(110, 36), function()
                F.sort, F.nokey, F.universal, F.unpatched, F.verified = "Latest", false, false, true, false
                for _, d in ipairs(sortDefs) do d.P.set(d.key == "Latest") end
                for _, d in ipairs(onlyDefs) do d.P.set(d.get()) end
            end)
            reset.b.AnchorPoint = Vector2.new(0, 1) reset.b.Position = UDim2.fromScale(0, 1) reset.b.ZIndex = 22
            local apply = pill(card, "Apply", "right", UDim2.fromOffset(120, 36), function() close() page = 1 load() end, true)
            apply.b.AnchorPoint = Vector2.new(1, 1) apply.b.Position = UDim2.fromScale(1, 1) apply.b.ZIndex = 22
        end)
        genv.__SM1LER_hubLoad = load
        local first = true
        bind(p:GetPropertyChangedSignal("Visible"), function()
            if p.Visible and first then first = false load() end
        end)
    end

    ---------------- URL
    do
        local p = panels.URL
        local box = new("TextBox", {
            Parent = p, Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = C.panel, TextColor3 = C.text, PlaceholderColor3 = C.sub,
            Font = Enum.Font.Gotham, TextSize = 13, Text = "", ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
            PlaceholderText = "https://raw.githubusercontent.com/.../script.lua",
        }, { round(10), stroke(), new("UIPadding", { PaddingLeft = UDim.new(0, 12) }) })
        local acts = new("Frame", { Parent = p, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1 }, { hlist(8) })
        local function fetch(cb)
            local url = string.gsub(box.Text, "^%s*(.-)%s*$", "%1")
            if not string.match(url, "^https?://") then notify("Enter a valid http(s) URL") return end
            task.spawn(function()
                local body, err = http(url)
                if body then cb(url, body) else notify("Request failed") addLog("WARN", "URL request failed: " .. tostring(err)) end
            end)
        end
        pill(p, "Run", "play", UDim2.fromOffset(100, 36), nil, true).b.Parent = acts
        pill(acts, "Edit", "pencil", UDim2.fromOffset(100, 36), nil)
        local kids = acts:GetChildren()
        for _, c in ipairs(kids) do
            if c:IsA("TextButton") then
                local isRun = false
                for _, d in ipairs(c:GetDescendants()) do if d:IsA("TextLabel") and d.Text == T("Run") then isRun = true end end
                bind(c.MouseButton1Click, function()
                    fetch(function(url, body)
                        if isRun then runSource(url, body) else openInEditor("Remote script", body) end
                    end)
                end)
            end
        end
        local note = txt(p, "Loads a script from a raw URL (GitHub raw, Pastebin raw, etc.) and runs it or opens it in the editor. Only run code you trust.", 12, C.sub)
        note.Position = UDim2.fromOffset(0, 94)
        note.Size = UDim2.new(1, 0, 0, 50)
        note.TextWrapped = true
        note.TextYAlignment = Enum.TextYAlignment.Top
    end

    setMode("Local")
end) if not ok_blk17 then warn("[blk17] " .. tostring(err_blk17)) end

----------------------------------------------------------------------
-- CONSOLE
----------------------------------------------------------------------
local ok_blk18, err_blk18 = pcall(function()
    local consolePage = addPage("Console", "terminal")
    local h = header(consolePage, "Console")
    local follow, filter = true, "All"
    local count = txt(h, "", 11, C.sub)
    count.Position = UDim2.fromOffset(110, 2)
    count.Size = UDim2.fromOffset(110, 32)
    local ctl = new("Frame", { Parent = h, AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0, 280, 1, 0), BackgroundTransparency = 1 },
        { hlist(6, Enum.HorizontalAlignment.Right) })
    placeRight(ctl, 0)
    local list = new("ScrollingFrame", {
        Parent = consolePage, Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 1, -84), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
    }, { new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }) })
    local KC = { PRINT = C.sub, INFO = C.info, WARN = C.warn, ERROR = C.err }
    local function matches(e)
        if filter == "All" then return true end
        if filter == "Errors" then return e.k == "ERROR" end
        if filter == "Warnings" then return e.k == "WARN" end
        return e.k == "PRINT" or e.k == "INFO"
    end
    local rid, rowObjs = 0, {}
    local rebuild, updateBanCount
    local function addRow(e)
        rid = rid + 1
        local row = new("TextLabel", {
            Parent = list, LayoutOrder = rid, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
            RichText = true, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            Font = Enum.Font.Code, TextSize = 12, TextColor3 = C.text,
            Text = string.format('<font color="#7a7a86">%s</font>  <b><font color="%s">%s</font></b>  %s', e.t, hex(KC[e.k] or C.sub), e.k, esc(e.m)),
        })
        local copyBtn = new("TextButton", {
            Parent = row, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(22, 22),
            BackgroundColor3 = C.item, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 5,
        }, { round(7), stroke() })
        centered(icon(copyBtn, "copy", 11, C.sub)).Parent = copyBtn
        bind(row.MouseEnter, function() copyBtn.Visible = true end)
        bind(row.MouseLeave, function() copyBtn.Visible = false end)
        bind(copyBtn.MouseEnter, function() tween(copyBtn, 0.1, { BackgroundColor3 = C.hover }) end)
        bind(copyBtn.MouseLeave, function() tween(copyBtn, 0.1, { BackgroundColor3 = C.item }) end)
        bind(copyBtn.MouseButton1Click, function()
            local line = ("%s [%s] %s"):format(e.t, e.k, e.m)
            if setclipboard then setclipboard(line) notify("Line copied") else notify("Clipboard not supported") end
        end)
        if e.k == "ERROR" or e.k == "WARN" then
            local banBtn = new("TextButton", {
                Parent = row, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -26, 0, 0), Size = UDim2.fromOffset(50, 22),
                BackgroundColor3 = C.item, AutoButtonColor = false, Text = G("Ban", "Бан"), Font = Enum.Font.GothamBold, TextSize = 11,
                TextColor3 = C.err, Visible = false, ZIndex = 5,
            }, { round(7), stroke() })
            bind(row.MouseEnter, function() banBtn.Visible = true end)
            bind(row.MouseLeave, function() banBtn.Visible = false end)
            bind(banBtn.MouseEnter, function() tween(banBtn, 0.1, { BackgroundColor3 = C.hover }) end)
            bind(banBtn.MouseLeave, function() tween(banBtn, 0.1, { BackgroundColor3 = C.item }) end)
            bind(banBtn.MouseButton1Click, function()
                local sig = errSig(e.m)
                DB.banned[sig] = string.sub((string.gsub(e.m, "%s+", " ")), 1, 140)
                for i = #logs, 1, -1 do
                    local l = logs[i]
                    if (l.k == "ERROR" or l.k == "WARN") and errSig(l.m) == sig then table.remove(logs, i) end
                end
                saveDB()
                notify(G("Error banned. It won't show up again.", "Ошибка забанена, больше не появится."))
                updateBanCount()
                rebuild()
            end)
        end
        rowObjs[#rowObjs + 1] = row
        if #rowObjs > 120 then table.remove(rowObjs, 1):Destroy() end
    end
    function rebuild()
        for _, o in ipairs(rowObjs) do o:Destroy() end
        rowObjs = {}
        for i = math.max(1, #logs - 119), #logs do if matches(logs[i]) then addRow(logs[i]) end end
        count.Text = #logs .. " messages"
    end
    local pending = {}
    function consoleAppend(e)
        if matches(e) then pending[#pending + 1] = e end
    end
    task.spawn(function()
        while alive do
            task.wait(0.12)
            if #pending > 0 then
                local batch = pending
                pending = {}
                local first = math.max(1, #batch - 24)
                if first > 1 then
                    addRow({ t = os.date("%H:%M:%S"), k = "INFO", m = "... " .. (first - 1) .. " messages skipped (too many at once)" })
                end
                for i = first, #batch do addRow(batch[i]) end
                count.Text = #logs .. " messages"
                if follow then task.defer(function() list.CanvasPosition = Vector2.new(0, math.max(0, list.AbsoluteCanvasSize.Y)) end) end
            end
        end
    end)
    local followP = pill(ctl, "Follow on", "terminal", UDim2.fromOffset(122, 32), nil)
    followP.b.LayoutOrder = 1
    bind(followP.b.MouseButton1Click, function()
        follow = not follow
        for _, p in ipairs(trList) do if p[1] == followP.t then p[2] = follow and "Follow on" or "Follow off" end end
        followP.t.Text = T(follow and "Follow on" or "Follow off")
    end)
    local clr = pill(ctl, "Clear", "trash", UDim2.fromOffset(100, 32), function() logs = {} pending = {} rebuild() end)
    clr.b.LayoutOrder = 2

    local row = new("Frame", { Parent = consolePage, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, { hlist(6) })
    local fp = {}
    for i, n in ipairs({ "All", "Errors", "Warnings", "Output" }) do
        local P = pill(row, n, nil, UDim2.fromOffset(88, 30), function()
            filter = n
            for k, p in pairs(fp) do p.set(k == n) end
            rebuild()
        end)
        P.b.LayoutOrder = i
        fp[n] = P
    end
    fp.All.set(true)
    local sa = pill(row, "Save all", "save", UDim2.fromOffset(104, 30), function()
        local lines = {}
        for _, e in ipairs(logs) do lines[#lines + 1] = ("%s [%s] %s"):format(e.t, e.k, e.m) end
        local t = table.concat(lines, "\n")
        local ok = pcall(function() writefile("sm1ler_console_" .. os.time() .. ".txt", t) end)
        if ok then notify("Console saved to file")
        elseif setclipboard then setclipboard(t) notify("Console copied")
        else notify("Saving not supported") end
    end)
    sa.b.LayoutOrder = 10

    -- banned errors: list + unban
    local bn
    function updateBanCount()
        local n = 0
        for _ in pairs(DB.banned) do n = n + 1 end
        if bn then bn.t.Text = G("Banned", "Баны") .. " (" .. n .. ")" end
    end
    local function bannedModal()
        local card, close = modal(G("Banned errors", "Забаненные ошибки"), 480, 300)
        local lst = new("ScrollingFrame", { Parent = card, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -82), BackgroundTransparency = 1,
            BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, { vlist(6) })
        local function render()
            for _, c in ipairs(lst:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
            local n = 0
            for sig, sample in pairs(DB.banned) do
                n = n + 1
                local r = new("Frame", { Parent = lst, LayoutOrder = n, Size = UDim2.new(1, -6, 0, 38), BackgroundColor3 = C.panel }, { round(10) })
                local t = txt(r, tostring(sample), 11, C.sub, Enum.Font.Code)
                t.Position, t.Size, t.TextTruncate = UDim2.fromOffset(10, 0), UDim2.new(1, -96, 1, 0), Enum.TextTruncate.AtEnd
                local ub = pill(r, G("Unban", "Вернуть"), nil, UDim2.fromOffset(78, 26), function()
                    DB.banned[sig] = nil
                    saveDB() render() updateBanCount()
                end)
                ub.b.AnchorPoint, ub.b.Position = Vector2.new(1, 0.5), UDim2.new(1, -6, 0.5, 0)
            end
            if n == 0 then
                local t = txt(lst, G("No banned errors.", "Забаненных ошибок нет."), 12, C.sub)
                t.Size = UDim2.new(1, 0, 0, 30)
            end
        end
        render()
        local all = pill(card, G("Unban all", "Вернуть все"), "trash", UDim2.fromOffset(130, 32), function()
            DB.banned = {}
            saveDB() render() updateBanCount()
        end)
        all.b.AnchorPoint, all.b.Position, all.b.ZIndex = Vector2.new(0, 1), UDim2.fromScale(0, 1), 22
    end
    bn = pill(row, G("Banned", "Баны"), "x", UDim2.fromOffset(104, 30), bannedModal)
    bn.b.LayoutOrder = 11
    updateBanCount()
    rebuild()
end) if not ok_blk18 then warn("[blk18] " .. tostring(err_blk18)) end

----------------------------------------------------------------------
-- AI: a small chat tab backed by the person's own free API key (Gemini or Groq).
-- No key ships with the script - CFG.AI.ApiKey stays empty; people paste their own
-- in Settings > AI (saved to DB.ai.key, never sent anywhere but the provider).
----------------------------------------------------------------------
local AI = {}
local ok_AImod, err_AImod = pcall(function()
    local function key() return (type(DB.ai) == "table" and DB.ai.key ~= "" and DB.ai.key) or CFG.AI.ApiKey end
    local function provider() return (type(DB.ai) == "table" and DB.ai.provider) or CFG.AI.Provider end
    local function model() return (type(DB.ai) == "table" and DB.ai.model ~= "" and DB.ai.model) or (provider() == "groq" and CFG.AI.GroqModel or CFG.AI.Model) end
    function AI.ready() return type(key()) == "string" and key() ~= "" end
    function AI.providerName() return provider() == "groq" and "Groq" or "Gemini" end

    -- history: array of { role = "user"|"model", text = "..." } (role "model" = assistant, matches Gemini's naming)
    function AI.ask(history, cb)
        if not AI.ready() then cb(false, G("No API key set. Add one in Settings > AI.", "Нет API-ключа. Добавь его в Settings > AI.")) return end
        task.spawn(function()
            local ok, result = pcall(function()
                if provider() == "groq" then
                    local msgs = { { role = "system", content = CFG.AI.System } }
                    for _, m in ipairs(history) do
                        msgs[#msgs + 1] = { role = (m.role == "model") and "assistant" or "user", content = m.text }
                    end
                    local body = HttpService:JSONEncode({ model = model(), messages = msgs, temperature = 0.7 })
                    local req = request or http_request or (syn and syn.request)
                    if not req then error("no HTTP request function available in this executor") end
                    local r = req({ Url = CFG.AI.GroqEndpoint, Method = "POST",
                        Headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. key() }, Body = body })
                    local data = HttpService:JSONDecode(r.Body)
                    if r.StatusCode >= 300 then error((data.error and data.error.message) or ("HTTP " .. tostring(r.StatusCode))) end
                    return data.choices[1].message.content
                else
                    local contents = {}
                    for _, m in ipairs(history) do
                        contents[#contents + 1] = { role = m.role, parts = { { text = m.text } } }
                    end
                    local body = HttpService:JSONEncode({ contents = contents, systemInstruction = { parts = { { text = CFG.AI.System } } } })
                    local url = CFG.AI.Endpoint .. model() .. ":generateContent?key=" .. key()
                    local okPost, respBody = true, nil
                    local req = request or http_request or (syn and syn.request)
                    if req then
                        local r = req({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
                        if r.StatusCode >= 300 then error((HttpService:JSONDecode(r.Body).error or {}).message or ("HTTP " .. tostring(r.StatusCode))) end
                        respBody = r.Body
                    else
                        local okG, body2 = pcall(function() return game:HttpPost(url, body, Enum.HttpContentType.ApplicationJson) end)
                        if not okG then error("no HTTP request function available in this executor") end
                        respBody = body2
                    end
                    local data = HttpService:JSONDecode(respBody)
                    if not data.candidates or not data.candidates[1] then
                        error((data.promptFeedback and data.promptFeedback.blockReason and ("blocked: " .. data.promptFeedback.blockReason)) or "empty response")
                    end
                    local parts = data.candidates[1].content.parts
                    local text = ""
                    for _, pt in ipairs(parts) do text = text .. (pt.text or "") end
                    return text
                end
            end)
            if ok then cb(true, result) else cb(false, tostring(result)) end
        end)
    end
end)
if not ok_AImod then warn("[AI module] " .. tostring(err_AImod)) end

----------------------------------------------------------------------
-- AI chat page
----------------------------------------------------------------------
local ok_AIpage, err_AIpage = pcall(function()
    local pg = addPage("AI", "bolt")
    local h, title = header(pg, "AI")
    local status = txt(h, "", 12, C.sub)
    status.AnchorPoint = Vector2.new(1, 0)
    status.Size = UDim2.fromOffset(240, 36)
    placeRight(status, 0, 4)

    local history = {}
    local list = new("ScrollingFrame", { Parent = pg, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -98), BackgroundColor3 = C.panel,
        BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, { round(14), stroke(), vlist(8), pad(12) })

    local function refreshStatus()
        status.Text = AI.ready() and (G("Provider: ", "Провайдер: ") .. AI.providerName()) or G("No key - open Settings > AI", "Нет ключа - открой Settings > AI")
        status.TextColor3 = AI.ready() and C.ok or C.warn
    end
    refreshStatus()

    local function bubble(role, text)
        local isUser = role == "user"
        local row = new("Frame", { Parent = list, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 })
        local b = new("Frame", {
            Parent = row, AnchorPoint = isUser and Vector2.new(1, 0) or Vector2.new(0, 0),
            Position = isUser and UDim2.new(1, 0, 0, 0) or UDim2.fromOffset(0, 0),
            Size = UDim2.new(0.82, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = isUser and C.white or C.item,
        }, { round(12), pad(10) })
        local t = new("TextLabel", {
            Parent = b, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
            Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = isUser and C.black or C.text, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = text,
        })
        return row
    end

    local function scrollDown() task.defer(function() list.CanvasPosition = Vector2.new(0, 1e6) end) end
    bubble("model", G("Hi! Ask me anything. I run on your own API key, set in Settings > AI.", "Привет! Спрашивай что угодно. Работаю на твоём собственном ключе из Settings > AI."))

    local inputBar = new("Frame", { Parent = pg, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 })
    local box = new("TextBox", {
        Parent = inputBar, Size = UDim2.new(1, -100, 1, 0), BackgroundColor3 = C.item, TextColor3 = C.text, PlaceholderColor3 = C.sub,
        PlaceholderText = G("Message...", "Сообщение..."), Font = Enum.Font.Gotham, TextSize = 13, Text = "", ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, MultiLine = false,
    }, { round(10), new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }) })
    local sendP = pill(inputBar, G("Send", "Отпр."), "right", UDim2.fromOffset(88, 36), nil, true)
    sendP.b.AnchorPoint, sendP.b.Position = Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0)

    local busy = false
    local function send()
        if busy then return end
        local text = (box.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then return end
        if not AI.ready() then
            notify(G("Add an API key first: Settings > AI", "Сначала добавь ключ: Settings > AI"))
            return
        end
        box.Text = ""
        bubble("user", text)
        history[#history + 1] = { role = "user", text = text }
        if #history > 20 then table.remove(history, 1) end
        scrollDown()
        busy = true
        local thinking = bubble("model", G("Thinking...", "Думаю..."))
        local thinkLbl = thinking:FindFirstChildOfClass("Frame"):FindFirstChildOfClass("TextLabel")
        AI.ask(history, function(ok, result)
            busy = false
            if ok then
                thinkLbl.Text = result
                history[#history + 1] = { role = "model", text = result }
            else
                thinkLbl.Text = "⚠ " .. result
                thinkLbl.TextColor3 = C.err
            end
            scrollDown()
        end)
    end
    bind(sendP.b.MouseButton1Click, send)
    bind(box.FocusLost, function(enter) if enter then send() end end)
    task.spawn(function()
        while alive do
            pcall(refreshStatus)
            task.wait(2)
        end
    end)
end)
if not ok_AIpage then warn("[AI page] " .. tostring(err_AIpage)) end


----------------------------------------------------------------------
----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------
local startTour
local CT = {}   -- custom themes manager (functions are defined next to the Theme page)
local ok_blk19, err_blk19 = pcall(function()
    local settingsPage = addPage("Settings", "gear")
    local h = header(settingsPage, "Settings")
    local qt = pill(h, "Quick tour", "book", UDim2.fromOffset(128, 32), function() startTour() end)
    qt.b.AnchorPoint = Vector2.new(1, 0)
    placeRight(qt.b, 2)

    local scroll = new("ScrollingFrame", {
        Parent = settingsPage, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
    }, { vlist(8) })
    local oc = 0
    local function grid()
        oc = oc + 1
        return new("Frame", { Parent = scroll, LayoutOrder = oc, Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 },
            { new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 42), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
    end
    local function section(key)
        oc = oc + 1
        local l = txt(scroll, "", 12, C.sub, Enum.Font.GothamBold)
        l.LayoutOrder = oc
        l.Size = UDim2.new(1, 0, 0, 18)
        reg(l, key)
    end
    local order = 0
    local function cell(g, key)
        order = order + 1
        local r = new("Frame", { Parent = g, LayoutOrder = order, BackgroundColor3 = C.panel }, { round(12) })
        local l = txt(r, "", 13, C.text, Enum.Font.GothamMedium)
        l.Position = UDim2.fromOffset(14, 0)
        l.Size = UDim2.new(0.5, 0, 1, 0)
        reg(l, key)
        return r
    end
    local function stepper(r, get, set, mn, mx, st, fmt)
        local box = new("Frame", { Parent = r, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(124, 30), BackgroundTransparency = 1 })
        local v = txt(box, "", 13, C.text, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
        v.Position = UDim2.fromOffset(32, 0)
        v.Size = UDim2.new(1, -64, 1, 0)
        local function show() v.Text = fmt and fmt(get()) or tostring(get()) end
        local m = iconBtn(box, "left", 30) m.Position = UDim2.fromOffset(0, 0)
        local p = iconBtn(box, "plus", 30) p.AnchorPoint = Vector2.new(1, 0) p.Position = UDim2.fromScale(1, 0)
        bind(m.MouseButton1Click, function() set(math.clamp(get() - st, mn, mx)) show() saveDB() end)
        bind(p.MouseButton1Click, function() set(math.clamp(get() + st, mn, mx)) show() saveDB() end)
        show()
    end
    local function toggle(r, key, onChange)
        local track = new("TextButton", {
            Parent = r, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(46, 26),
            AutoButtonColor = false, Text = "", BackgroundColor3 = C.item,
        }, { round(13) })
        local knob = new("Frame", { Parent = track, AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = C.sub }, { round(10) })
        local function paint()
            local on = S[key]
            tween(track, 0.12, { BackgroundColor3 = on and C.white or C.item })
            tween(knob, 0.12, { Position = on and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = on and C.black or C.sub })
        end
        paint()
        bind(track.MouseButton1Click, function()
            S[key] = not S[key]
            paint() saveDB()
            if onChange then onChange(S[key]) end
        end)
    end
    local function valueBtn(r, getText, onClick, w)
        local b = new("TextButton", {
            Parent = r, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(w or 124, 30),
            BackgroundColor3 = C.item, AutoButtonColor = false, Text = "", ZIndex = 1,
        }, { round(9), hlist(6, Enum.HorizontalAlignment.Center) })
        local t = new("TextLabel", { Parent = b, LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text, Text = getText() })
        local ic = icon(b, "down", 12, C.sub) ic.LayoutOrder = 2
        bind(b.MouseButton1Click, onClick)
        bind(b.MouseEnter, function() tween(b, 0.1, { BackgroundColor3 = C.hover }) end)
        bind(b.MouseLeave, function() tween(b, 0.1, { BackgroundColor3 = C.item }) end)
        return function() t.Text = getText() end
    end

    local g1 = grid()
    stepper(cell(g1, "UI Size"), function() return S.uiSize end, function(v) S.uiSize = v uiScale.Scale = targetScale() end, 60, 150, 10, function(v) return v .. "%" end)
    local LANGS = {
        { "en", "English" }, { "vi", "Vietnamese (Tiếng Việt)" }, { "pt", "Portuguese (Português)" },
        { "es", "Spanish (Español)" }, { "fr", "French (Français)" }, { "ru", "Russian (Русский)" },
        { "pl", "Polish (Polski)" }, { "de", "German (Deutsch)" },
    }
    local langRefresh
    local function langName() for _, l in ipairs(LANGS) do if l[1] == S.lang then return (string.gsub(l[2], " %(.*$", "")) end end return "English" end
    langRefresh = valueBtn(cell(g1, "Language"), langName, function()
        local card, close = modal("Language", 380, 252)
        local g = new("Frame", { Parent = card, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34), BackgroundTransparency = 1, ZIndex = 22 },
            { new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 38), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, FillDirectionMaxCells = 2 }) })
        local chips = {}
        for i, l in ipairs(LANGS) do
            local P = pill(g, nil, nil, UDim2.new(), function()
                S.lang = l[1] saveDB() applyLang() refreshHome() langRefresh()
                if genv.__SM1LER_refresh then genv.__SM1LER_refresh() end
                for c, p in pairs(chips) do p.set(c == l[1]) end
                close()
            end)
            P.b.LayoutOrder = i
            P.b.ZIndex = 22
            P.t = new("TextLabel", { Parent = P.b, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text, Text = l[2], ZIndex = 23 })
            P.set(l[1] == S.lang)
            chips[l[1]] = P
        end
    end)
    stepper(cell(g1, "Editor font"), function() return S.font end, function(v) S.font = v editorBox.TextSize = v hlLabel.TextSize = v lineLabel.TextSize = v end, 8, 24, 1)
    local posRefresh
    posRefresh = valueBtn(cell(g1, "Window position"), function() return T(S.pos) end, function()
        local order2 = { "Center", "Top", "Bottom" }
        local idx = 1
        for i, o in ipairs(order2) do if o == S.pos then idx = i end end
        S.pos = order2[idx % 3 + 1]
        saveDB() applyPosition() posRefresh()
    end)
    local styleNames = { win = "Windows", sm1ler = "SM1LER", mac = "macOS", linux = "Linux" }
    local styleRefresh
    styleRefresh = valueBtn(cell(g1, "GUI style"), function() return styleNames[S.guiStyle] or "SM1LER" end, function()
        local order3 = { "win", "sm1ler", "mac", "linux" }
        local idx = 1
        for i, o in ipairs(order3) do if o == S.guiStyle then idx = i end end
        S.guiStyle = order3[idx % #order3 + 1]
        saveDB() styleRefresh()
        applyGuiStyle()
        notify(G("Window buttons style: ", "Стиль кнопок окна: ") .. styleNames[S.guiStyle])
    end)
    toggle(cell(g1, "Background blur"), "blur", function() blur.Size = (open and S.blur) and 16 or 0 end)
    toggle(cell(g1, "Animations"), "anim")
    toggle(cell(g1, "Notifications"), "notif", function(v) if v then notify("Notifications on") end end)
    toggle(cell(g1, "Streamer mode"), "streamer", function(v)
        if v then rerollNames() end
        applyStreamer(v)
    end)
    local rrCell = cell(g1, "Reroll name")
    local rrP = pill(rrCell, "Reroll", "refresh", UDim2.fromOffset(100, 30), function()
        local was = S.streamer
        if was then applyStreamer(false) end
        rerollNames()
        if was then applyStreamer(true) end
        notify("Name: " .. Stream.display)
    end)
    rrP.b.AnchorPoint, rrP.b.Position = Vector2.new(1, 0.5), UDim2.new(1, -8, 0.5, 0)
    toggle(cell(g1, "Top bar button"), "topbtn", function(v) if topBtn then topBtn.Visible = v end end)
    toggle(cell(g1, "Draggable window"), "drag", function(v)
        notify(v and ("Drag the " .. CFG.Name .. " button anywhere") or "Window locked")
        if not v then applyPosition() end
    end)

    toggle(cell(g1, "Snow effect"), "snow", function(v) mainSnow.holder.Visible = v end)
    toggle(cell(g1, "Neon borders"), "neon", function(v) for _, n in ipairs(FX.neon) do n.g.Enabled = v end end)
    toggle(cell(g1, "HUD bar"), "hud", function(v) if hudBar then hudBar.Visible = v end end)
    toggle(cell(g1, "HUD snow"), "hudSnow")
    toggle(cell(g1, "24h clock"), "hud24h")

    section("Injector")
    local gI = grid()
    toggle(cell(gI, "Auto INJECT"), "autoInject")
    toggle(cell(gI, "Auto exec"), "autoExec")
    stepper(cell(gI, "Auto exec delay"), function() return S.autoDelay or 1 end, function(v) S.autoDelay = math.floor(v * 10 + 0.5) / 10 end, 0, 20, 0.5,
        function(v) return string.format("%.1fs", v) end)
    toggle(cell(gI, "Stop spam on error"), "spamStopOnError")
    stepper(cell(gI, "Spam interval"), function() return S.spamInterval end,
        function(v) S.spamInterval = math.floor(v * 100 + 0.5) / 100 end, 0, 10, 0.05, function(v) return string.format("%.2fs", v) end)
    stepper(cell(gI, "Spam count"), function() return S.spamCount end, function(v) S.spamCount = v end, 0, 5000, 10,
        function(v) return v == 0 and "∞" or tostring(v) end)
    stepper(cell(gI, "Spam burst"), function() return S.spamBurst end, function(v) S.spamBurst = v end, 1, 10, 1,
        function(v) return "x" .. v end)

    local OUT_MODES = { "Auto", "Roblox", "Executor", "TestService", "Error" }
    local outRefresh
    outRefresh = valueBtn(cell(gI, "Roblox console"), function() return S.outMode or "Auto" end, function()
        local idx = 1
        for i, m in ipairs(OUT_MODES) do if m == (S.outMode or "Auto") then idx = i end end
        S.outMode = OUT_MODES[idx % #OUT_MODES + 1]
        saveDB()
        outRefresh()
    end, 130)
    local testCell = cell(gI, "Test F9 output")
    local testP = pill(testCell, "Test", "play", UDim2.fromOffset(100, 30), function()
        local mode = S.outMode or "Auto"
        local m = "SM1LER test [" .. mode .. "] - if you can read this in the Roblox console (F9), this mode works"
        realOut("print", m)
        realOut("warn", m)
        addLog("INFO", "F9 test sent with mode '" .. mode .. "' (getrenv=" .. tostring(getrenv ~= nil) .. "). Open F9 > Client log and look for 'SM1LER test'. If it is missing, switch mode and test again.")
        notify("Test sent - check F9 (Client)")
    end, true)
    testP.b.AnchorPoint, testP.b.Position = Vector2.new(1, 0.5), UDim2.new(1, -8, 0.5, 0)

    section("Game")
    local g2 = grid()
    local afkConn
    local function setAfk(v)
        if afkConn then afkConn:Disconnect() afkConn = nil end
        if v then afkConn = LP.Idled:Connect(function() pcall(function() game:GetService("VirtualUser"):CaptureController() game:GetService("VirtualUser"):ClickButton2(Vector2.new()) end) end) end
    end
    toggle(cell(g2, "Anti-AFK"), "afk", setAfk)
    if S.afk then setAfk(true) end
    local function applyFps()
        local n = S.fps == "Max" and 0 or tonumber(S.fps)
        if setfpscap then pcall(setfpscap, n) elseif S.fps ~= "60" then notify("FPS cap not supported here") end
    end
    local fpsRefresh
    fpsRefresh = valueBtn(cell(g2, "FPS cap"), function() return S.fps end, function()
        local card, close = modal("FPS cap", 300, 150)
        local g = new("Frame", { Parent = card, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34), BackgroundTransparency = 1, ZIndex = 22 },
            { new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 36), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
        for i, o in ipairs({ "60", "90", "120", "Max" }) do
            local P = pill(g, nil, nil, UDim2.new(), function() S.fps = o saveDB() applyFps() fpsRefresh() close() end)
            P.b.LayoutOrder = i
            P.b.ZIndex = 22
            P.t = new("TextLabel", { Parent = P.b, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text, Text = o, ZIndex = 23 })
            P.set(o == S.fps)
        end
    end, 90)

    oc = oc + 1
    local srv = new("Frame", { Parent = scroll, LayoutOrder = oc, Size = UDim2.new(1, -6, 0, 46), BackgroundColor3 = C.panel }, { round(12) })
    local sl = txt(srv, "", 13, C.text, Enum.Font.GothamMedium)
    sl.Position = UDim2.fromOffset(14, 0)
    sl.Size = UDim2.fromOffset(80, 46)
    reg(sl, "Server")
    local sb = new("Frame", { Parent = srv, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(1, -110, 0, 32), BackgroundTransparency = 1 },
        { hlist(8, Enum.HorizontalAlignment.Right) })
    local function hop(sort)
        notify("Searching for a server...")
        task.spawn(function()
            local body = http(("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100"):format(game.PlaceId, sort))
            local ok, res = pcall(function() return HttpService:JSONDecode(body) end)
            if not body or not ok or type(res) ~= "table" or not res.data then
                notify("Server list unavailable here")
                addLog("WARN", "Server list request failed (needs HTTP access)")
                return
            end
            local pool = {}
            for _, sv in ipairs(res.data) do
                if sv.id ~= game.JobId and sv.playing and sv.maxPlayers and sv.playing < sv.maxPlayers then pool[#pool + 1] = sv end
            end
            if #pool == 0 then notify("No suitable server found") return end
            local pick = (sort == "Asc") and pool[1] or pool[math.random(1, #pool)]
            game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, pick.id, LP)
        end)
    end
    local p1 = pill(sb, "Rejoin", "refresh", UDim2.fromOffset(100, 32), function()
        notify("Rejoining...")
        if #Players:GetPlayers() <= 1 then game:GetService("TeleportService"):Teleport(game.PlaceId, LP)
        else game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end
    end)
    p1.b.LayoutOrder = 1
    local p2 = pill(sb, "Server hop", "server", UDim2.fromOffset(116, 32), function() hop("Desc") end)
    p2.b.LayoutOrder = 2
    local p3 = pill(sb, "Small server", "server", UDim2.fromOffset(124, 32), function() hop("Asc") end)
    p3.b.LayoutOrder = 3
        -- custom themes
    do
        DB.customThemes = type(DB.customThemes) == "table" and DB.customThemes or {}
        section(G("Custom themes", "Свои темы"))
        oc = oc + 1
        local tbar = new("Frame", { Parent = scroll, LayoutOrder = oc, Size = UDim2.new(1, -6, 0, 34), BackgroundTransparency = 1 }, { hlist(8) })
        oc = oc + 1
        local hintL = txt(scroll, G("Put .theme files into workspace/SM1LER/themes - they are found automatically.", "Положи файлы .theme в workspace/SM1LER/themes - они находятся автоматически."), 12, C.sub)
        hintL.LayoutOrder, hintL.Size, hintL.TextWrapped = oc, UDim2.new(1, -6, 0, 28), true
        oc = oc + 1
        local listF = new("Frame", { Parent = scroll, LayoutOrder = oc, Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, { vlist(6) })

        local exportModal
        local function renderList()
            for _, c in ipairs(listF:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
            if #DB.customThemes == 0 then
                local e = txt(listF, G("No custom themes yet. Import a .realtheme file or create one from the current look.", "Своих тем пока нет. Импортируй .realtheme или создай тему из текущего вида."), 12, C.sub)
                e.Size, e.TextWrapped = UDim2.new(1, 0, 0, 34), true
                return
            end
            for i, th in ipairs(DB.customThemes) do
                local r = new("Frame", { Parent = listF, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = C.panel }, { round(12) })
                local nm = txt(r, (DB.activeCustom == th.name and "● " or "") .. tostring(th.name), 13, C.text, Enum.Font.GothamMedium)
                nm.Position, nm.Size, nm.TextTruncate = UDim2.fromOffset(14, 0), UDim2.new(1, -270, 1, 0), Enum.TextTruncate.AtEnd
                local btns = new("Frame", { Parent = r, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(252, 30), BackgroundTransparency = 1 },
                    { hlist(6, Enum.HorizontalAlignment.Right) })
                local a = pill(btns, G("Apply", "Применить"), "check", UDim2.fromOffset(112, 30), function() CT.apply(th) end, true)
                a.b.LayoutOrder = 1
                local ex = pill(btns, G("Export", "Экспорт"), "copy", UDim2.fromOffset(96, 30), function() exportModal(th) end)
                ex.b.LayoutOrder = 2
                local del = iconBtn(btns, "trash", 30)
                del.LayoutOrder = 3
                bind(del.MouseButton1Click, function()
                    table.remove(DB.customThemes, i)
                    if DB.activeCustom == th.name then DB.activeCustom = nil end
                    saveDB()
                    renderList()
                end)
            end
        end
        CT.refreshList = renderList

        local function importModal()
            local card, close = modal(G("Import theme", "Импорт темы"), 480, 330)
            local hint = txt(card, G("File name from your executor's workspace (folder SM1LER/themes), or paste the theme JSON:", "Имя файла из папки workspace (SM1LER/themes) или вставь JSON темы:"), 12, C.sub)
            hint.Position, hint.Size, hint.TextWrapped, hint.ZIndex = UDim2.fromOffset(0, 34), UDim2.new(1, 0, 0, 32), true, 22
            local inp = new("TextBox", { Parent = card, Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, -112, 0, 34), BackgroundColor3 = C.item, TextColor3 = C.text,
                PlaceholderColor3 = C.sub, PlaceholderText = "volt.realtheme", Font = Enum.Font.Gotham, TextSize = 13, Text = "", ClearTextOnFocus = false,
                TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 }, { round(9), new("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
            local msg = txt(card, "", 12, C.sub)
            msg.Position, msg.Size, msg.TextWrapped, msg.ZIndex = UDim2.fromOffset(0, 112), UDim2.new(1, 0, 0, 30), true, 22
            local function doImport(spec)
                local ok, err = CT.import(spec)
                if ok then close() else msg.Text, msg.TextColor3 = err or "", C.err end
            end
            local go = pill(card, G("Import", "Импорт"), "check", UDim2.fromOffset(100, 34), function() doImport(inp.Text) end, true)
            go.b.AnchorPoint, go.b.Position, go.b.ZIndex = Vector2.new(1, 0), UDim2.new(1, 0, 0, 72), 22
            -- file browser: folders + theme-compatible files (.realtheme / .json)
            local cwd = ""
            if isfolder then
                if isfolder("SM1LER/themes") then cwd = "SM1LER/themes" elseif isfolder("SM1LER") then cwd = "SM1LER" end
            end
            local upB = iconBtn(card, "left", 26)
            upB.Position, upB.ZIndex = UDim2.fromOffset(0, 146), 22
            local pathL = txt(card, "", 12, C.sub, Enum.Font.Code)
            pathL.Position, pathL.Size, pathL.TextTruncate, pathL.ZIndex = UDim2.fromOffset(34, 146), UDim2.new(1, -34, 0, 26), Enum.TextTruncate.AtEnd, 22
            local lst = new("ScrollingFrame", { Parent = card, Position = UDim2.fromOffset(0, 176), Size = UDim2.new(1, 0, 1, -176), BackgroundTransparency = 1, BorderSizePixel = 0,
                ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, { vlist(6) })
            local function render()
                for _, c in ipairs(lst:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
                pathL.Text = "workspace/" .. cwd
                local items
                for _, q in ipairs(cwd == "" and { "", "." } or { cwd }) do
                    local ok, r = pcall(listfiles, q)
                    if ok and type(r) == "table" and #r > 0 then items = r break end
                end
                local folders, files = {}, {}
                for _, it in ipairs(items or {}) do
                    if type(it) == "string" then
                        local path = string.gsub(it, "\\", "/")
                        local okF, isF = pcall(isfolder, path)
                        if okF and isF then
                            folders[#folders + 1] = path
                        else
                            local low = string.lower(path)
                            if string.sub(low, -6) == ".theme" or string.sub(low, -10) == ".realtheme" or string.sub(low, -5) == ".json" then files[#files + 1] = path end
                        end
                    end
                end
                table.sort(folders) table.sort(files)
                local n = 0
                for _, f in ipairs(folders) do
                    n = n + 1
                    local P = pill(lst, "📁 " .. (string.match(f, "[^/]+$") or f), nil, UDim2.new(1, -6, 0, 32), function() cwd = f render() end)
                    P.b.LayoutOrder = n
                end
                for _, f in ipairs(files) do
                    n = n + 1
                    local P = pill(lst, string.match(f, "[^/]+$") or f, "paste", UDim2.new(1, -6, 0, 32), function() doImport(f) end, true)
                    P.b.LayoutOrder = n
                end
                if n == 0 then
                    local t = txt(lst, G("No theme files here (.theme / .realtheme / .json). Open another folder or put files into workspace/SM1LER/themes.", "Здесь нет файлов тем (.theme / .realtheme / .json). Открой другую папку или положи файлы в workspace/SM1LER/themes."), 12, C.sub)
                    t.Size, t.TextWrapped = UDim2.new(1, -6, 0, 40), true
                end
            end
            bind(upB.MouseButton1Click, function()
                cwd = string.match(cwd, "^(.*)/[^/]*$") or ""
                render()
            end)
            if listfiles then render() else
                local t = txt(lst, G("This executor has no listfiles: type the file name above.", "У этого экзекьютора нет listfiles: введи имя файла выше."), 12, C.sub)
                t.Size, t.TextWrapped = UDim2.new(1, -6, 0, 34), true
            end
        end

        function exportModal(e)
            local card, close = modal(G("Export theme", "Экспорт темы"), 440, 316)
            local fmt = "sm1ler"
            local function lab(text, y)
                local l = txt(card, text, 12, C.sub)
                l.Position, l.Size, l.ZIndex = UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, 18), 22
                return l
            end
            lab(G("File name (saved to workspace/SM1LER/themes)", "Имя файла (сохранится в workspace/SM1LER/themes)"), 34)
            local nameB = new("TextBox", { Parent = card, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = C.item, TextColor3 = C.text, Font = Enum.Font.Gotham,
                TextSize = 13, Text = tostring(e.name), ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 },
                { round(9), new("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
            lab(G("Format", "Формат"), 98)
            local row = new("Frame", { Parent = card, Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, ZIndex = 22 }, { hlist(8) })
            local btns = {}
            local info = lab("", 160)
            info.Size, info.TextWrapped, info.TextYAlignment = UDim2.new(1, 0, 0, 44), true, Enum.TextYAlignment.Top
            local function paint()
                for k, b in pairs(btns) do
                    local on = k == fmt
                    b.BackgroundColor3 = on and C.white or C.item
                    b:FindFirstChildOfClass("TextLabel").TextColor3 = on and C.black or C.text
                end
                info.Text = fmt == "real"
                    and G("Real-compatible: colors + code colors only. Opens in the Real app.", "Совместимый с Real: только цвета и цвета кода. Открывается в приложении Real.")
                    or G("SM1LER: everything (background, neon, effects, palette, code colors).", "SM1LER: всё (фон, неон, эффекты, палитра, цвета кода).")
            end
            for i, d in ipairs({ { "sm1ler", "SM1LER (.theme)" }, { "real", "Real (.realtheme)" } }) do
                local b = new("TextButton", { Parent = row, LayoutOrder = i, Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = C.item, AutoButtonColor = false, Text = "", ZIndex = 22 }, { round(9) })
                local t = txt(b, d[2], 13, C.text, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
                t.Size = UDim2.fromScale(1, 1)
                btns[d[1]] = b
                b.MouseButton1Click:Connect(function() fmt = d[1] paint() end)
            end
            paint()
            local msg = lab("", 214)
            msg.TextWrapped, msg.Size = true, UDim2.new(1, 0, 0, 30)
            local save = pill(card, G("Save file", "Сохранить файл"), "save", UDim2.fromOffset(150, 34), function()
                local json = CT.encode(e, fmt)
                if not json then msg.Text, msg.TextColor3 = G("Export failed", "Не удалось экспортировать"), C.err return end
                local path = CT.writeFile(nameB.Text, json, fmt == "real" and ".realtheme" or ".theme")
                if path then
                    msg.Text, msg.TextColor3 = G("Saved: ", "Сохранено: ") .. path, C.ok
                else
                    if setclipboard then pcall(setclipboard, json) end
                    msg.Text, msg.TextColor3 = G("Cannot write files here. JSON copied to clipboard.", "Здесь нельзя писать файлы. JSON скопирован в буфер."), C.warn
                end
            end, true)
            save.b.AnchorPoint, save.b.Position, save.b.ZIndex = Vector2.new(0, 1), UDim2.fromScale(0, 1), 22
            local copy = pill(card, G("Copy JSON", "Копировать JSON"), "copy", UDim2.fromOffset(150, 34), function()
                local json = CT.encode(e, fmt)
                if json and setclipboard then pcall(setclipboard, json) msg.Text, msg.TextColor3 = G("JSON copied.", "JSON скопирован."), C.ok
                else msg.Text, msg.TextColor3 = G("Clipboard is not available.", "Буфер обмена недоступен."), C.err end
            end)
            copy.b.AnchorPoint, copy.b.Position, copy.b.ZIndex = Vector2.new(0, 1), UDim2.new(0, 158, 1, 0), 22
        end

        local function createModal()
            local card, close = modal(G("Create theme", "Создать тему"), 460, 348)
            local note = txt(card, G("Background, gradient and neon are taken from the Theme page (current look). Pick the code colors:", "Фон, градиент и неон берутся со страницы Theme (текущий вид). Выбери цвета кода:"), 12, C.sub)
            note.Position, note.Size, note.TextWrapped, note.ZIndex = UDim2.fromOffset(0, 34), UDim2.new(1, 0, 0, 32), true, 22
            local function field(y, label, default)
                local l = txt(card, label, 13, C.text, Enum.Font.GothamMedium)
                l.Position, l.Size, l.ZIndex = UDim2.fromOffset(0, y), UDim2.fromOffset(140, 28), 22
                return new("TextBox", { Parent = card, Position = UDim2.fromOffset(150, y), Size = UDim2.new(1, -150, 0, 28), BackgroundColor3 = C.item, TextColor3 = C.text,
                    Font = Enum.Font.Code, TextSize = 13, Text = default, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 },
                    { round(8), new("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
            end
            local syn = getSyntax()
            local nameB = field(72, G("Name", "Название"), "My theme")
            local kwB = field(104, G("Keywords", "Ключевые слова"), syn.kw)
            local strB = field(136, G("Strings", "Строки"), syn.str)
            local numB = field(168, G("Numbers", "Числа"), syn.num)
            local cmB = field(200, G("Comments", "Комментарии"), syn.comment)
            local biB = field(232, G("Functions", "Функции"), syn.bi)
            local function norm(b, fb)
                local t = string.gsub(b.Text, "%s", "")
                if string.sub(t, 1, 1) ~= "#" then t = "#" .. t end
                return hexToColor(t) and t or fb
            end
            local save = pill(card, G("Save theme", "Сохранить тему"), "save", UDim2.fromOffset(160, 34), function()
                local e = CT.saveCurrent(nameB.Text, { kw = norm(kwB, syn.kw), str = norm(strB, syn.str), num = norm(numB, syn.num), comment = norm(cmB, syn.comment), bi = norm(biB, syn.bi) })
                local jf = CT.encode(e, "sm1ler")
                local path = jf and CT.writeFile(e.name, jf, ".theme")
                notify(G("Theme saved: ", "Тема сохранена: ") .. e.name .. (path and ("\n" .. path) or ""))
                close()
            end, true)
            save.b.Position, save.b.ZIndex = UDim2.fromOffset(0, 274), 22
        end

        local imp = pill(tbar, G("Import", "Импорт"), "paste", UDim2.fromOffset(110, 34), importModal)
        imp.b.LayoutOrder = 1
        local crt = pill(tbar, G("Create", "Создать"), "plus", UDim2.fromOffset(110, 34), createModal)
        crt.b.LayoutOrder = 2
        local rsc = pill(tbar, G("Rescan", "Обновить"), "refresh", UDim2.fromOffset(110, 34), function()
            local n, added = CT.autoScan(false)
            notify(G("Theme files: ", "Файлов тем: ") .. n .. G(", new: ", ", новых: ") .. added)
        end)
        rsc.b.LayoutOrder = 3
        renderList()
    end

    -- branding
    do
    -- Backdoor Mode + Discord status webhook
    do
    -- AI tab: your own key, saved locally, never bundled with the script
    do
        section(G("AI", "ИИ"))
        DB.ai = type(DB.ai) == "table" and DB.ai or { key = "", provider = "gemini", model = "" }
        local prow = new("Frame", { Parent = scroll, LayoutOrder = (oc + 1), Size = UDim2.new(1, -6, 0, 34), BackgroundTransparency = 1 }, { hlist(8) })
        oc = oc + 1
        local provBtns = {}
        local function paintProv()
            for k, b in pairs(provBtns) do
                local on = DB.ai.provider == k
                b.BackgroundColor3 = on and C.white or C.item
                b:FindFirstChildOfClass("TextLabel").TextColor3 = on and C.black or C.text
            end
        end
        for i, d in ipairs({ { "gemini", "Gemini (Google AI Studio)" }, { "groq", "Groq" } }) do
            local b = new("TextButton", { Parent = prow, LayoutOrder = i, Size = UDim2.fromOffset(190, 34), BackgroundColor3 = C.item, AutoButtonColor = false, Text = "" }, { round(9) })
            local t = txt(b, d[2], 13, C.text, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
            t.Size = UDim2.fromScale(1, 1)
            provBtns[d[1]] = b
            b.MouseButton1Click:Connect(function() DB.ai.provider = d[1] saveDB() paintProv() end)
        end
        paintProv()

        local kr = new("Frame", { Parent = scroll, LayoutOrder = (oc + 1), Size = UDim2.new(1, -6, 0, 36), BackgroundTransparency = 1 })
        oc = oc + 1
        local kl = txt(kr, G("API key", "API-ключ"), 12, C.sub)
        kl.Size = UDim2.fromOffset(64, 36)
        local keyTb = new("TextBox", { Parent = kr, Position = UDim2.fromOffset(68, 3), Size = UDim2.new(1, -68, 0, 30), BackgroundColor3 = C.item, TextColor3 = C.text,
            PlaceholderColor3 = C.sub, PlaceholderText = "AIzaSy... / gsk_...", Font = Enum.Font.Code, TextSize = 13, Text = DB.ai.key, ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left }, { round(9), new("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
        bind(keyTb.FocusLost, function() DB.ai.key = keyTb.Text saveDB() end)

        local mr = new("Frame", { Parent = scroll, LayoutOrder = (oc + 1), Size = UDim2.new(1, -6, 0, 36), BackgroundTransparency = 1 })
        oc = oc + 1
        local ml = txt(mr, G("Model", "Модель"), 12, C.sub)
        ml.Size = UDim2.fromOffset(64, 36)
        local modelTb = new("TextBox", { Parent = mr, Position = UDim2.fromOffset(68, 3), Size = UDim2.new(1, -68, 0, 30), BackgroundColor3 = C.item, TextColor3 = C.text,
            PlaceholderColor3 = C.sub, PlaceholderText = G("leave empty for the default", "пусто = модель по умолчанию"), Font = Enum.Font.Code, TextSize = 13, Text = DB.ai.model,
            ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, { round(9), new("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
        bind(modelTb.FocusLost, function() DB.ai.model = modelTb.Text saveDB() end)

        local aiHint = txt(scroll, G("Get a free key at aistudio.google.com (Gemini) or console.groq.com (Groq). Saved only on this device, sent only to that provider.",
            "Бесплатный ключ: aistudio.google.com (Gemini) или console.groq.com (Groq). Хранится только у тебя, уходит только этому провайдеру."), 11, C.sub)
        oc = oc + 1
        aiHint.LayoutOrder, aiHint.Size, aiHint.TextWrapped = oc, UDim2.new(1, -6, 0, 42), true
        oc = oc + 1
        local testB = pill(scroll, G("Test key", "Проверить ключ"), "bolt", UDim2.fromOffset(170, 32), function()
            notify(G("Testing...", "Проверяю..."))
            AI.ask({ { role = "user", text = "Say OK in one word." } }, function(ok, res)
                notify(ok and (G("Works: ", "Работает: ") .. tostring(res)) or (G("Failed: ", "Ошибка: ") .. tostring(res)))
            end)
        end)
        testB.b.LayoutOrder = oc
    end

        section(G("Security", "Безопасность"))
        local bg = grid()
        toggle(cell(bg, G("Backdoor Mode", "Backdoor Mode")), "backdoorScan")
        local hint = txt(scroll, G("Heuristic only: checks instance names and exposed webhook-looking strings already visible to the client. It cannot read the source of scripts it did not inject - a clean result is not proof.",
            "Эвристика: проверяет имена объектов и похожие на вебхук строки, уже видимые клиенту. Код чужих скриптов прочитать не может - чистый результат не доказательство."), 11, C.sub)
        oc = oc + 1
        hint.LayoutOrder, hint.Size, hint.TextWrapped = oc, UDim2.new(1, -6, 0, 42), true
        do
            oc = oc + 1
            local rb = pill(scroll, G("View last scan", "Последний скан"), "terminal", UDim2.fromOffset(220, 32), function()
                if not BD.lastHits then
                    notify(G("No scan yet: enable Backdoor Mode and press Inject", "Скана ещё не было: включи Backdoor Mode и нажми Inject"))
                    return
                end
                local card = modal(G("Backdoor Mode: last scan", "Backdoor Mode: последний скан"), 480, 320)
                local lst = new("ScrollingFrame", { Parent = card, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1,
                    BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, { vlist(4) })
                if #BD.lastHits == 0 then
                    local t = txt(lst, G("No suspicious items found.", "Подозрительных объектов не найдено."), 12, C.sub)
                    t.Size = UDim2.new(1, 0, 0, 24)
                end
                for i, h in ipairs(BD.lastHits) do
                    local t = txt(lst, h.why .. "  ·  " .. h.path, 11, C.text, Enum.Font.Code)
                    t.LayoutOrder, t.Size, t.TextWrapped = i, UDim2.new(1, -6, 0, 18), true
                end
            end)
            rb.b.LayoutOrder = oc
        end

        section(G("Discord status webhook", "Статус-вебхук Discord"))
        local dHint = txt(scroll, G("Posts an embed to your Discord channel when someone injects (name, status, detect status, version). No personal data is sent. Set CFG.Discord.WebhookUrl in the script.",
            "Отправляет эмбед в твой канал Discord при каждом Inject (название, статус, детект, версия). Личные данные не отправляются. Укажи CFG.Discord.WebhookUrl в скрипте."), 11, C.sub)
        oc = oc + 1
        dHint.LayoutOrder, dHint.Size, dHint.TextWrapped = oc, UDim2.new(1, -6, 0, 42), true
        oc = oc + 1
        local dState = txt(scroll, DISC.enabled() and G("Webhook: configured ✓", "Вебхук: настроен ✓") or G("Webhook: not set (CFG.Discord.WebhookUrl is empty)", "Вебхук: не задан (CFG.Discord.WebhookUrl пуст)"),
            12, DISC.enabled() and C.ok or C.sub, Enum.Font.GothamMedium)
        dState.LayoutOrder, dState.Size = oc, UDim2.new(1, -6, 0, 20)
        oc = oc + 1
        local testB = pill(scroll, G("Send test message", "Отправить тест"), "bolt", UDim2.fromOffset(190, 32), function()
            if not DISC.enabled() then notify(G("Set CFG.Discord.WebhookUrl first", "Сначала укажи CFG.Discord.WebhookUrl")) return end
            DISC.post("test")
            notify(G("Sent (check your Discord channel)", "Отправлено (проверь канал Discord)"))
        end)
        testB.b.LayoutOrder = oc
    end

        section(G("Branding", "Брендинг"))
        oc = oc + 1
        local bx = new("Frame", { Parent = scroll, LayoutOrder = oc, Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.panel },
            { round(12), vlist(8), pad(12) })
        local function boxIn(parent, x, w, default, placeholder)
            return new("TextBox", { Parent = parent, Position = UDim2.fromOffset(x, 3), Size = UDim2.new(1, -(x + 112), 0, 30), BackgroundColor3 = C.item, TextColor3 = C.text,
                PlaceholderColor3 = C.sub, PlaceholderText = placeholder, Font = Enum.Font.Gotham, TextSize = 13, Text = default, ClearTextOnFocus = false,
                TextXAlignment = Enum.TextXAlignment.Left }, { round(9), new("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
        end
        local function applyBtn(parent, cb)
            local ap = pill(parent, G("Apply", "Применить"), "check", UDim2.fromOffset(104, 30), cb, true)
            ap.b.AnchorPoint, ap.b.Position = Vector2.new(1, 0), UDim2.new(1, 0, 0, 3)
        end
        local nr = new("Frame", { Parent = bx, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1 })
        local nl = txt(nr, G("Name", "Название"), 12, C.sub)
        nl.Size = UDim2.fromOffset(70, 36)
        local nameTb = boxIn(nr, 74, 0, CFG.Name, BR.defaultName)
        applyBtn(nr, function()
            local n, ok = BR.setName(nameTb.Text)
            nameTb.Text = n
            if ok then notify(G("Name changed: ", "Название изменено: ") .. n) else notify(G("Name must be 3-14 characters", "Название: от 3 до 14 символов")) end
        end)
        local lr = new("Frame", { Parent = bx, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1 })
        local ll = txt(lr, G("Logo", "Логотип"), 12, C.sub)
        ll.Size = UDim2.fromOffset(70, 36)
        BR.addLogo(new("TextLabel", { Parent = lr, Position = UDim2.fromOffset(74, 2), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = C.white, Text = "S",
            Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = C.black }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) }))
        local logoTb = boxIn(lr, 114, 0, (DB.brand.vectorLogo and "bolt") or DB.brand.imgSpec or DB.brand.logo or "S", "S  |  bolt  |  rbxassetid://123  |  logo.png")
        applyBtn(lr, function()
            local ok, err = BR.setLogo(logoTb.Text)
            if ok then notify(G("Logo updated", "Логотип обновлён")) else notify(err) end
        end)
        local genB = pill(lr, G("Generated bolt", "Сген. молния"), "bolt", UDim2.fromOffset(150, 30), function()
            BR.setLogo("bolt")
            logoTb.Text = "bolt"
            notify(G("Logo updated: generated bolt mark", "Логотип: сгенерированная молния"))
        end)
        genB.b.AnchorPoint, genB.b.Position = Vector2.new(1, 0), UDim2.new(1, -112, 0, 3)
        local hint = txt(bx, G("Logo: type \"bolt\" for a generated vector mark (drawn in-engine, no external image), 1-2 characters/emoji, an image id (rbxassetid://...) or a .png/.jpg file from the workspace folder. The name changes everywhere in the interface.",
            "Логотип: напиши \"bolt\" для сгенерированного векторного значка (рисуется движком, без внешней картинки), 1-2 символа/эмодзи, id картинки (rbxassetid://...) или файл .png/.jpg из папки workspace. Название меняется во всём интерфейсе."), 11, C.sub)
        hint.LayoutOrder, hint.Size, hint.TextWrapped = 3, UDim2.new(1, 0, 0, 56), true
        hint.TextYAlignment = Enum.TextYAlignment.Top
        local rst = pill(bx, G("Reset branding", "Сбросить бренд"), "refresh", UDim2.fromOffset(170, 32), function()
            BR.setName(BR.defaultName)
            BR.setLogo("")
            nameTb.Text, logoTb.Text = CFG.Name, "S"
            notify(G("Branding reset", "Бренд сброшен"))
        end)
        rst.b.LayoutOrder = 4
    end
    genv.__SM1LER_applyFps = applyFps
end) if not ok_blk19 then warn("[blk19] " .. tostring(err_blk19)) end

----------------------------------------------------------------------
-- ACCOUNT
----------------------------------------------------------------------
local ok_blk20, err_blk20 = pcall(function()
    local accountPage = addPage("Account", "user")
    header(accountPage, "Account")
    local card = new("Frame", { Parent = accountPage, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 130), BackgroundColor3 = C.panel }, { round(14), stroke() })
    local av = new("ImageLabel", { Parent = card, Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(98, 98), BackgroundColor3 = C.item, Image = "" }, { round(49) })
    task.spawn(function()
        local ok, img = pcall(Players.GetUserThumbnailAsync, Players, LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
        if ok and img then av.Image = img end
    end)
    local L = {}
    for i = 1, 5 do
        L[i] = txt(card, "", i == 1 and 18 or 13, i == 1 and C.text or C.sub, i == 1 and Enum.Font.GothamBold or Enum.Font.Gotham)
        L[i].Position = UDim2.fromOffset(132, 14 + (i == 1 and 0 or (i - 1) * 21 + 6))
        L[i].Size = UDim2.new(1, -150, 0, i == 1 and 26 or 20)
    end
    local function refresh()
        L[1].Text = dispName()
        L[2].Text = "@" .. userName()
        L[3].Text = "UserId: " .. userIdText()
        L[4].Text = ("Account age: %d days"):format(LP.AccountAge)
        local ex = "unknown"
        pcall(function() if identifyexecutor then ex = tostring((identifyexecutor())) end end)
        L[5].Text = "Runtime: " .. ex
    end
    refresh()
    genv.__SM1LER_acc = refresh
    local row = new("Frame", { Parent = accountPage, Position = UDim2.fromOffset(0, 192), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1 }, { hlist(8) })
    local function copyBtn(label, getv, order)
        local P = pill(row, nil, "copy", UDim2.fromOffset(150, 36), function()
            if setclipboard then setclipboard(tostring(getv())) notify(label .. " copied") else notify("Clipboard not supported") end
        end)
        P.t = new("TextLabel", { Parent = P.b, LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text, Text = label })
        P.b.LayoutOrder = order
    end
    copyBtn("Place ID", function() return game.PlaceId end, 1)
    copyBtn("Job ID", function() return game.JobId end, 2)
    copyBtn("User ID", function() return LP.UserId end, 3)
end) if not ok_blk20 then warn("[blk20] " .. tostring(err_blk20)) end

----------------------------------------------------------------------
-- Quick tour
----------------------------------------------------------------------
function startTour()
    local steps = {
        { "Home", "Home shows your player, game, FPS, ping and quick scripts." },
        { "Editor", "Editor: tabs, undo/redo, syntax colors. Run executes the current tab." },
        { "Scripts", "Scripts: Local saves, the ScriptBlox hub with filters, or a raw URL." },
        { "Console", "Console collects prints, warnings and errors. Filter or save them." },
        { "Settings", "Settings: size, language, blur, drag, anti-AFK, FPS cap, server tools." },
    }
    local i = 0
    local card, close, body, nextP
    local function step()
        i = i + 1
        if i > #steps then close() notify("Tour finished") return end
        showPage(steps[i][1])
        body.Text = steps[i][2]
    end
    card, close = modal("Quick tour", 340, 150)
    body = txt(card, "", 13, C.text)
    body.Position = UDim2.fromOffset(0, 34)
    body.Size = UDim2.new(1, 0, 0, 50)
    body.TextWrapped = true
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.ZIndex = 22
    local skip = pill(card, "Skip", nil, UDim2.fromOffset(90, 34), close)
    skip.b.AnchorPoint = Vector2.new(0, 1) skip.b.Position = UDim2.fromScale(0, 1) skip.b.ZIndex = 22
    if skip.t then skip.t.ZIndex = 23 end
    nextP = pill(card, "Next", "right", UDim2.fromOffset(110, 34), step, true)
    nextP.b.AnchorPoint = Vector2.new(1, 1) nextP.b.Position = UDim2.fromScale(1, 1) nextP.b.ZIndex = 22
    step()
end

----------------------------------------------------------------------
-- Top "S" button, hotkey, dragging
----------------------------------------------------------------------
topBtn = BR.addLogo(new("TextButton", {
    Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(40, 40),
    BackgroundColor3 = C.bg, AutoButtonColor = false, Text = "S", Font = Enum.Font.GothamBlack, TextSize = 22,
    TextColor3 = C.white, Visible = false, ZIndex = 60, -- shown after the key is accepted
}, { round(20), stroke() }))
local movedBtn = false
bind(topBtn.MouseButton1Click, function()
    if movedBtn then movedBtn = false return end
    setOpen(not open)
end)
bind(UIS.InputBegan, function(input, gpe)
    if not gpe and input.KeyCode == CFG.ToggleKey then setOpen(not open) end
end)

local ok_blk21, err_blk21 = pcall(function()
    local dragging, target, startMouse, startPos
    local function isPointer(i) return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch end
    bind(topBtn.InputBegan, function(input)
        if S.drag and isPointer(input) then
            dragging, target, startMouse, startPos, movedBtn = true, topBtn, Vector2.new(input.Position.X, input.Position.Y), topBtn.Position, false
        end
    end)
    bind(UIS.InputBegan, function(input)
        if not (S.drag and open and isPointer(input)) then return end
        local p = Vector2.new(input.Position.X, input.Position.Y)
        local ap, as = win.AbsolutePosition, win.AbsoluteSize
        if p.X >= ap.X and p.X <= ap.X + as.X and p.Y >= ap.Y and p.Y <= ap.Y + 50 * uiScale.Scale then
            dragging, target, startMouse, startPos = true, win, p, win.Position
        end
    end)
    bind(UIS.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = Vector2.new(input.Position.X, input.Position.Y) - startMouse
            if d.Magnitude > 5 then movedBtn = target == topBtn end
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    bind(UIS.InputEnded, function(input) if isPointer(input) then dragging = false end end)
end) if not ok_blk21 then warn("[blk21] " .. tostring(err_blk21)) end
if workspace.CurrentCamera then
    bind(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function() if open then uiScale.Scale = targetScale() end end)
end

----------------------------------------------------------------------
-- THEME (full background + neon customization)
----------------------------------------------------------------------
----------------------------------------------------------------------
-- PALETTES: a theme can recolour the whole UI (C + every existing element)
----------------------------------------------------------------------
local PALS, curPal = {}, "default"
local PAL = { keys = { "bg", "panel", "item", "hover", "line", "text", "sub", "white", "ok", "warn", "err", "info" } }
local ok_blk22, err_blk22 = pcall(function()
    local base = {}
    for k, v in pairs(C) do base[k] = v end
    PALS.default = base
    local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
    -- Volt: flat neutral greys (#111111 / #171717 / #242424 / #262626, text #cccccc)
    PALS.volt = { bg = rgb(17, 17, 17), panel = rgb(23, 23, 23), item = rgb(36, 36, 36), hover = rgb(52, 52, 52), line = rgb(38, 38, 38),
        text = rgb(204, 204, 204), sub = rgb(163, 163, 163), white = rgb(229, 229, 229), black = base.black, ok = rgb(16, 185, 129), warn = rgb(234, 179, 8), err = rgb(239, 68, 68), info = base.info }
end) if not ok_blk22 then warn("[blk22] " .. tostring(err_blk22)) end
-- full colour table of a palette; "custom" = TH.palCustom on top of the default one (every colour kept unique)
local function palTarget(name)
    if name ~= "custom" then return PALS[name] or PALS.default end
    local t = {}
    for k, v in pairs(PALS.default) do
        local h = TH.palCustom and TH.palCustom[k]
        t[k] = (type(h) == "string" and hexToColor(h)) or v
    end
    local seen = { t.black }
    local function taken(c) for _, o in ipairs(seen) do if o == c then return true end end return false end
    for _, k in ipairs(PAL.keys) do
        local c, tries = t[k], 0
        while taken(c) and tries < 255 do
            tries = tries + 1
            c = Color3.fromRGB(math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), (math.floor(c.B * 255 + 0.5) + 1) % 256)
        end
        t[k] = c
        seen[#seen + 1] = c
    end
    return t
end
local function setPalette(name)
    if not (name == "custom" or PALS[name]) then name = "default" end
    local new, old, keys = palTarget(name), {}, {}
    for k, v in pairs(C) do old[k] = v end
    for k, v in pairs(new) do if old[k] ~= v then keys[#keys + 1] = k end end
    curPal = name
    if #keys == 0 then return end
    for _, k in ipairs(keys) do C[k] = new[k] end
    local function map(c)
        for _, k in ipairs(keys) do if c == old[k] then return new[k] end end
        return nil
    end
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("GuiObject") then
            local m = map(d.BackgroundColor3)
            if m then d.BackgroundColor3 = m end
            if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                local t = map(d.TextColor3)
                if t then d.TextColor3 = t end
                if d:IsA("TextBox") then
                    local pc = map(d.PlaceholderColor3)
                    if pc then d.PlaceholderColor3 = pc end
                end
            elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
                local ic = map(d.ImageColor3)
                if ic then d.ImageColor3 = ic end
            end
        elseif d:IsA("UIStroke") then
            local m = map(d.Color)
            if m then d.Color = m end
        end
    end
end
-- edit one colour of the interface (switches the theme to the custom palette)
function PAL.set(key, hexstr)
    if not hexToColor(hexstr) then return false end
    if TH.pal ~= "custom" then
        TH.palCustom = {}
        for _, k in ipairs(PAL.keys) do TH.palCustom[k] = hex(C[k]) end
        TH.pal = "custom"
    end
    TH.palCustom[key] = hexstr
    if key == "bg" then TH.mode, TH.color = "color", hexstr end   -- the window background follows the "Window" colour
    setPalette("custom")
    return true
end
function PAL.reset()
    TH.pal, TH.palCustom = nil, nil
    setPalette("default")
end

----------------------------------------------------------------------
-- INTERFACE STYLE: corner radius, border width, font family, text size
----------------------------------------------------------------------
local STY = { fonts = { "Gotham", "Builder Sans", "Source Sans", "Ubuntu", "Roboto", "Nunito" } }
local ok_blk23, err_blk23 = pcall(function()
    local FAM = {
        ["Builder Sans"] = { Gotham = "BuilderSans", GothamMedium = "BuilderSansMedium", GothamSemibold = "BuilderSansMedium", GothamBold = "BuilderSansBold", GothamBlack = "BuilderSansExtraBold" },
        ["Source Sans"] = { Gotham = "SourceSans", GothamMedium = "SourceSansSemibold", GothamSemibold = "SourceSansSemibold", GothamBold = "SourceSansBold", GothamBlack = "SourceSansBold" },
        Ubuntu = { all = "Ubuntu" }, Roboto = { all = "Roboto" }, Nunito = { all = "Nunito" },
    }
    local KEEP = { Code = true, RobotoMono = true }   -- code font is never touched (editor alignment)
    local DEFAULT_KEY = "1|1|Gotham|1"
    local lastKey, skip, pending = DEFAULT_KEY, {}, false
    local function curKey()
        return table.concat({ tostring(TH.radius or 1), tostring(TH.borderScale or 1), tostring(TH.font or "Gotham"), tostring(TH.textScale or 1) }, "|")
    end
    local function rebuildSkip()
        skip = {}
        for _, n in ipairs(FX.neon) do if n.st then skip[n.st] = true end end
    end
    local function styleOne(d)
        if d:IsA("UICorner") then
            local cr = d.CornerRadius
            if cr.Scale ~= 0 then return end
            local r0 = d:GetAttribute("r0")
            if r0 == nil then r0 = cr.Offset d:SetAttribute("r0", r0) end
            d.CornerRadius = UDim.new(0, math.floor(r0 * (TH.radius or 1) + 0.5))
        elseif d:IsA("UIStroke") then
            if skip[d] then return end
            local t0 = d:GetAttribute("t0")
            if t0 == nil then t0 = d.Thickness d:SetAttribute("t0", t0) end
            d.Thickness = t0 * (TH.borderScale or 1)
        elseif d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
            local f0 = d:GetAttribute("f0")
            if f0 == nil then
                f0 = d.Font.Name
                d:SetAttribute("f0", f0)
                d:SetAttribute("s0", d.TextSize)
            end
            if KEEP[f0] then return end
            local s0 = d:GetAttribute("s0") or d.TextSize
            local fam = FAM[TH.font or "Gotham"]
            local nf = (fam and (fam.all or fam[f0])) or f0
            pcall(function() d.Font = Enum.Font[nf] end)
            d.TextSize = math.max(8, math.floor(s0 * (TH.textScale or 1) + 0.5))
        end
    end
    function STY.apply()
        if pending then return end
        pending = true
        task.delay(0.12, function()
            pending = false
            local k = curKey()
            if k == lastKey then return end
            lastKey = k
            rebuildSkip()
            for _, d in ipairs(gui:GetDescendants()) do pcall(styleOne, d) end
        end)
    end
    bind(gui.DescendantAdded, function(d)
        if lastKey == DEFAULT_KEY then return end
        task.defer(function()
            if not d.Parent then return end
            if d:IsA("UIStroke") then rebuildSkip() end
            pcall(styleOne, d)
        end)
    end)
end) if not ok_blk23 then warn("[blk23] " .. tostring(err_blk23)) end

----------------------------------------------------------------------
-- VOLT theme extras: silver light sweeps running along the window edges
----------------------------------------------------------------------
local VT = { on = false }
local ok_blk24, err_blk24 = pcall(function()
    local function mkBar(pos)
        local holder = new("Frame", { Parent = content, Position = pos, Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 17, Visible = false })
        local bar = new("Frame", { Parent = holder, Size = UDim2.fromOffset(180, 2), BackgroundColor3 = Color3.fromRGB(240, 240, 246), BorderSizePixel = 0, ZIndex = 17 },
            { new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.05), NumberSequenceKeypoint.new(1, 1) }) }) })
        return holder, bar
    end
    local topH, topB = mkBar(UDim2.fromOffset(0, 0))
    local botH, botB = mkBar(UDim2.new(0, 0, 1, -2))
    local tc = 0
    bind(RunService.Heartbeat, function(dt)
        if not VT.on or not win.Visible then return end
        tc = tc + dt
        local cyc = tc % 4.4
        if cyc < 1.7 then
            local f = cyc / 1.7
            f = f * f * (3 - 2 * f)
            topB.Position = UDim2.new(f, -180 * (1 - f), 0, 0)
            botB.Position = UDim2.new(1 - f, -180 * f, 0, 0)
        else
            topB.Position, botB.Position = UDim2.new(2, 0, 0, 0), UDim2.new(2, 0, 0, 0)
        end
    end)
    function VT.set(on)
        on = on and true or false
        VT.on = on
        topH.Visible, botH.Visible = on, on
    end
end) if not ok_blk24 then warn("[blk24] " .. tostring(err_blk24)) end

----------------------------------------------------------------------
-- NEW YEAR theme extras: garland, countdown plaque, falling snowflakes, fireworks
----------------------------------------------------------------------
local NY = { on = false, was = false }
local ok_blk25, err_blk25 = pcall(function()
    local W = WIN_W
    local bulbs, ptxt, nyText = {}, nil, nil
    local COLS = { Color3.fromRGB(255, 70, 85), Color3.fromRGB(255, 205, 80), Color3.fromRGB(90, 220, 130), Color3.fromRGB(90, 170, 255), Color3.fromRGB(255, 120, 200) }
    local WIRE = Color3.fromRGB(16, 70, 40)
    local deco = new("Frame", { Parent = win, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(0, 6), Size = UDim2.fromOffset(W, 74),
        BackgroundTransparency = 1, ZIndex = 60, Visible = false })
    local function wireY(x) return 52 + 13 * math.sin(math.pi * ((x % 100) / 100)) end
    local function buildDeco()
    W = WIN_W
    deco.Size = UDim2.fromOffset(W, 74)
    deco:ClearAllChildren()
    -- wire (sagging swags)
    for x = 0, W - 20, 20 do
        local x2 = x + 20
        local y1, y2 = wireY(x), wireY(x2)
        local dx, dy = x2 - x, y2 - y1
        new("Frame", { Parent = deco, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((x + x2) / 2, (y1 + y2) / 2),
            Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 1, 2), Rotation = math.deg(math.atan2(dy, dx)), BackgroundColor3 = WIRE, BorderSizePixel = 0, ZIndex = 61 })
    end
    -- bulbs
    bulbs = {}
    for k = 1, 19 do
        local x = k * 35
        local y = wireY(x)
        local col = COLS[(k - 1) % #COLS + 1]
        local glow = new("Frame", { Parent = deco, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, y - 3), Size = UDim2.fromOffset(24, 24),
            BackgroundColor3 = col, BackgroundTransparency = 0.82, BorderSizePixel = 0, ZIndex = 61 }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
        new("Frame", { Parent = deco, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(3, 4), BackgroundColor3 = WIRE, BorderSizePixel = 0, ZIndex = 62 })
        local bulb = new("Frame", { Parent = deco, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, y + 4), Size = UDim2.fromOffset(8, 11),
            BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = 63 }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
        bulbs[#bulbs + 1] = { b = bulb, g = glow, ph = k * 1.7 }
    end
    -- plaque with countdown (stands on the garland)
    for _, dx in ipairs({ -60, 60 }) do
        new("Frame", { Parent = deco, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(W / 2 + dx, 32), Size = UDim2.fromOffset(2, 24),
            BackgroundColor3 = Color3.fromRGB(255, 215, 106), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 62 })
    end
    local plaque = new("Frame", { Parent = deco, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(W / 2, 4), Size = UDim2.fromOffset(272, 30),
        BackgroundColor3 = Color3.fromRGB(8, 14, 12), BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 64 }, { round(15), neonStroke(1.5, 40) })
    ptxt = txt(plaque, "", 12, Color3.fromRGB(255, 226, 150), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
    ptxt.Size, ptxt.ZIndex = UDim2.fromScale(1, 1), 65
    function nyText()
        local now = os.time()
        local d = os.date("*t", now)
        if d.month == 1 and d.day <= 7 then
            return G("🎆 Happy New Year ", "🎆 С Новым ") .. d.year .. G("! 🎆", " годом! 🎆")
        end
        local target = os.time({ year = d.year + 1, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
        local left = math.max(0, target - now)
        return string.format("❄ %s %d%s %02d:%02d:%02d ❄", G("New Year in", "До Нового года:"), math.floor(left / 86400), G("d", "д"),
            math.floor(left % 86400 / 3600), math.floor(left % 3600 / 60), left % 60)
    end
    ptxt.Text = nyText()
    end
    buildDeco()
    NY.rebuild = buildDeco
    local lastW = WIN_W
    LY.hooks[#LY.hooks + 1] = function() if WIN_W ~= lastW then lastW = WIN_W buildDeco() end end

    -- glyph snowflakes inside the window
    local fl = new("Frame", { Parent = content, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, BorderSizePixel = 0, ZIndex = 18, Visible = false },
        { round(18) })
    local GL = { "❄", "❅", "❆", "✦", "✧" }
    local FC = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 225, 255), Color3.fromRGB(255, 226, 150) }
    local flakes = {}
    for i = 1, 22 do
        local sz = math.random(9, 19)
        flakes[i] = {
            f = new("TextLabel", { Parent = fl, BackgroundTransparency = 1, Size = UDim2.fromOffset(sz + 6, sz + 6), AnchorPoint = Vector2.new(0.5, 0.5),
                Text = GL[math.random(#GL)], TextSize = sz, Font = Enum.Font.GothamBold, TextColor3 = FC[math.random(#FC)], TextTransparency = 0.25 + math.random() * 0.4 }),
            x = math.random(), y = math.random(), sp = 0.03 + (sz / 19) * 0.06, sw = math.random() * 6.28, rs = (math.random() - 0.5) * 50,
        }
    end

    local acc, tClock, lastSec = 0, 0, -1
    bind(RunService.Heartbeat, function(dt)
        if not NY.on or not win.Visible then return end
        acc = acc + dt
        if acc < 0.033 then return end
        local d = acc
        acc = 0
        tClock = tClock + d
        fl.Visible = true   -- the snowflakes belong to the New Year theme
        if fl.Visible then
            for _, f in ipairs(flakes) do
                f.y = f.y + f.sp * d
                if f.y > 1.06 then f.y, f.x = -0.06, math.random() end
                f.f.Position = UDim2.new(f.x + math.sin(tClock * 0.8 + f.sw) * 0.02, 0, f.y, 0)
                f.f.Rotation = (f.f.Rotation + f.rs * d) % 360
            end
        end
        for _, b in ipairs(bulbs) do
            local k = 0.5 + 0.5 * math.sin(tClock * 3.4 + b.ph)
            b.b.BackgroundTransparency = 0.05 + 0.55 * (1 - k)
            b.g.BackgroundTransparency = 0.72 + 0.26 * (1 - k)
        end
        local sec = math.floor(os.clock())
        if sec ~= lastSec then lastSec = sec ptxt.Text = nyText() end
    end)

    function NY.burst()
        if not win.Visible then return end
        local fx = new("Frame", { Parent = content, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 40, ClipsDescendants = true, BorderSizePixel = 0 }, { round(18) })
        task.spawn(function()
            for _ = 1, 4 do
                local cx, cy = math.random(120, 500), math.random(60, 200)
                local base = COLS[math.random(#COLS)]
                for i = 1, 18 do
                    local a, r = (i / 18) * math.pi * 2, math.random(50, 95)
                    local pt = new("Frame", { Parent = fx, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(6, 6),
                        BackgroundColor3 = (i % 3 == 0) and Color3.new(1, 1, 1) or base, BorderSizePixel = 0 }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
                    tween(pt, 1.0, { Position = UDim2.fromOffset(cx + math.cos(a) * r, cy + math.sin(a) * r + 14), Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 })
                end
                task.wait(0.4)
            end
            task.wait(1.1)
            fx:Destroy()
        end)
    end

    function NY.set(on)
        on = on and true or false
        NY.on = on
        deco.Visible = on
        if not on then fl.Visible = false end
        if on and not NY.was then NY.burst() end
        NY.was = on
    end
end) if not ok_blk25 then warn("[blk25] " .. tostring(err_blk25)) end

local applyTheme, resolveImage
local ok_blk26, err_blk26 = pcall(function()
local themePage = addPage("Theme", "filter")
local imgMsgLbl
local lastPanelAlpha = 0

function applyTheme()
    setPalette(TH.pal)
    local mode = TH.mode
    for _, L in ipairs({ bgC, sbBg }) do
        local g = L:FindFirstChildOfClass("UIGradient")
        if mode == "color" then
            L.BackgroundTransparency = 0
            L.BackgroundColor3 = hexToColor(TH.color) or C.bg
            g.Enabled = false
        elseif mode == "gradient" then
            L.BackgroundTransparency = 0
            L.BackgroundColor3 = Color3.new(1, 1, 1)
            local c1, c2 = hexToColor(TH.g1) or C.bg, hexToColor(TH.g2) or C.bg
            local c3 = hexToColor(TH.g3)
            if c3 then
                g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, c1), ColorSequenceKeypoint.new(0.5, c2), ColorSequenceKeypoint.new(1, c3) })
            else
                g.Color = ColorSequence.new(c1, c2)
            end
            g.Rotation = TH.angle
            g.Enabled = true
        else
            L.BackgroundTransparency = 1
            g.Enabled = false
        end
    end
    local hasImg = mode == "image" and bgI.Image ~= ""
    bgI.Visible = hasImg
    bgI.ImageTransparency = TH.imgAlpha
    local sc = ({ Crop = Enum.ScaleType.Crop, Fit = Enum.ScaleType.Fit, Stretch = Enum.ScaleType.Stretch, Tile = Enum.ScaleType.Tile })[TH.imgScale] or Enum.ScaleType.Crop
    bgI.ScaleType = sc
    if sc == Enum.ScaleType.Tile then bgI.TileSize = UDim2.fromOffset(160, 160) end
    bgD.BackgroundTransparency = hasImg and (1 - TH.dim) or 1
    local seq = neonSeq()
    for _, n in ipairs(FX.neon) do
        n.g.Color = seq
        n.g.Transparency = neonTrans()
        if n.main then n.speed, n.st.Thickness = TH.neonSpeed, TH.neonThick end
    end
    local a = TH.panelAlpha
    for _, d in ipairs(content:GetDescendants()) do
        if d:IsA("GuiObject") and d.BackgroundColor3 == C.panel and d.BackgroundTransparency == lastPanelAlpha then d.BackgroundTransparency = a end
    end
    lastPanelAlpha = a
    NY.set(TH.special == "newyear")
    VT.set(TH.special == "volt")
    STY.apply()
    if LY.apply then
        local okL, errL = pcall(LY.apply, false)
        if not okL then warn("[layout] " .. tostring(errL)) end
    end
end
bind(content.DescendantAdded, function(d)
    if TH.panelAlpha ~= 0 and d:IsA("GuiObject") and d.BackgroundColor3 == C.panel and d.BackgroundTransparency == 0 then
        d.BackgroundTransparency = TH.panelAlpha
    end
end)

local function setImgMsg(t, color)
    if imgMsgLbl and imgMsgLbl.Parent then imgMsgLbl.Text = t imgMsgLbl.TextColor3 = color or C.sub end
end
function resolveImage(spec)
    spec = string.gsub(tostring(spec or ""), "^%s*(.-)%s*$", "%1")
    if spec == "" then
        bgI.Image = ""
        setImgMsg(G("No image set.", "Картинка не задана."))
        return true
    end
    if string.match(spec, "^%d+$") then
        bgI.Image = "rbxassetid://" .. spec
    elseif string.match(spec, "^rbx") then
        bgI.Image = spec
    elseif string.match(spec, "^https?://") then
        local getA = getcustomasset or getsynasset
        if not (writefile and getA) then
            setImgMsg(G("URL images need writefile + getcustomasset here. Use an asset id instead.", "Для картинок по ссылке нужны writefile и getcustomasset. Используй id ассета."), C.err)
            return false
        end
        setImgMsg(G("Downloading...", "Скачивание..."))
        local body, err = http(spec)
        if not body then setImgMsg(G("Download failed: ", "Не удалось скачать: ") .. tostring(err), C.err) return false end
        local ext
        if string.sub(body, 1, 4) == "\137PNG" then ext = "png"
        elseif string.byte(body, 1) == 255 and string.byte(body, 2) == 216 then ext = "jpg" end
        if not ext then setImgMsg(G("Only PNG or JPG images are supported.", "Поддерживаются только PNG и JPG."), C.err) return false end
        local file = "sm1ler_bg." .. ext
        local ok, asset = pcall(function() writefile(file, body) return getA(file) end)
        if not ok or not asset then setImgMsg(G("Could not load the downloaded file.", "Не удалось загрузить файл."), C.err) return false end
        bgI.Image = asset
    else
        setImgMsg(G("Use an image id (number / rbxassetid://) or a PNG/JPG link.", "Укажи id картинки (число / rbxassetid://) или ссылку на PNG/JPG."), C.err)
        return false
    end
    setImgMsg(G("Image set.", "Картинка установлена."), C.ok)
    return true
end

-- slider (one shared drag handler) -----------------------------------
local activeSlider
bind(UIS.InputChanged, function(i)
    if activeSlider and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then activeSlider(i.Position.X) end
end)
bind(UIS.InputEnded, function(i)
    if activeSlider and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
        activeSlider = nil
        saveDB()
    end
end)
local function slider(parent, w, mn, mx, step, get, set, fmt)
    local f = new("Frame", { Parent = parent, Size = UDim2.fromOffset(w, 28), BackgroundTransparency = 1 })
    local val = txt(f, "", 12, C.sub, Enum.Font.GothamMedium, Enum.TextXAlignment.Right)
    val.AnchorPoint, val.Position, val.Size = Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0), UDim2.fromOffset(46, 20)
    local track = new("Frame", { Parent = f, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, -54, 0, 6),
        BackgroundColor3 = C.item, BorderSizePixel = 0 }, { round(3) })
    local fillF = new("Frame", { Parent = track, Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.white, BorderSizePixel = 0 }, { round(3) })
    local knob = new("Frame", { Parent = track, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = C.white, BorderSizePixel = 0 }, { round(7) })
    local function show()
        local a = math.clamp((get() - mn) / (mx - mn), 0, 1)
        fillF.Size = UDim2.fromScale(a, 1)
        knob.Position = UDim2.fromScale(a, 0.5)
        val.Text = fmt and fmt(get()) or tostring(get())
    end
    local function fromX(x)
        local a = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
        local v = mn + (mx - mn) * a
        v = math.floor(v / step + 0.5) * step
        set(math.floor(math.clamp(v, mn, mx) * 1000 + 0.5) / 1000)
        show()
    end
    local hit = new("TextButton", { Parent = f, Size = UDim2.new(1, -54, 1, 0), BackgroundTransparency = 1, Text = "" })
    bind(hit.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            activeSlider = fromX
            fromX(i.Position.X)
        end
    end)
    show()
    return f, show
end

local function pickColor(initial, cb)
    local cur = hexToColor(initial) or Color3.new(1, 1, 1)
    local ch = { math.floor(cur.R * 255 + 0.5), math.floor(cur.G * 255 + 0.5), math.floor(cur.B * 255 + 0.5) }
    local card, close = modal("Pick color", 400, 304)
    local prev = new("Frame", { Parent = card, Position = UDim2.fromOffset(0, 34), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = cur }, { round(12), stroke() })
    local hexBox = new("TextBox", { Parent = card, Position = UDim2.fromOffset(78, 34), Size = UDim2.fromOffset(130, 30), BackgroundColor3 = C.item, TextColor3 = C.text,
        Font = Enum.Font.Code, TextSize = 14, Text = "", ClearTextOnFocus = false }, { round(8) })
    local shows = {}
    local function sync()
        local c = Color3.fromRGB(ch[1], ch[2], ch[3])
        prev.BackgroundColor3 = c
        hexBox.Text = hex(c)
        for _, sh in ipairs(shows) do sh() end
    end
    for i, nm in ipairs({ "R", "G", "B" }) do
        local y = 106 + (i - 1) * 30
        local l = txt(card, nm, 13, C.sub, Enum.Font.GothamBold)
        l.Position, l.Size = UDim2.fromOffset(0, y), UDim2.fromOffset(16, 28)
        local f, sh = slider(card, 340, 0, 255, 1, function() return ch[i] end, function(v) ch[i] = v sync() end)
        f.Position = UDim2.fromOffset(22, y)
        shows[#shows + 1] = sh
    end
    bind(hexBox.FocusLost, function()
        local c = hexToColor(hexBox.Text)
        if c then ch = { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } end
        sync()
    end)
    local sw = new("Frame", { Parent = card, Position = UDim2.fromOffset(0, 202), Size = UDim2.fromOffset(368, 30), BackgroundTransparency = 1 }, { hlist(6) })
    for i, hx in ipairs({ "#ffffff", "#a0a0a0", "#000000", "#ff4d4d", "#ff9e4d", "#ffd84d", "#4dff88", "#4dd2ff", "#6a7bff", "#c04dff", "#ff4dc8" }) do
        local b = new("TextButton", { Parent = sw, LayoutOrder = i, Size = UDim2.fromOffset(28, 28), BackgroundColor3 = hexToColor(hx), AutoButtonColor = false, Text = "" },
            { round(8), stroke(C.line) })
        bind(b.MouseButton1Click, function()
            local c = hexToColor(hx)
            ch = { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
            sync()
        end)
    end
    local ap = pill(card, "Apply", "check", UDim2.fromOffset(120, 34), function() cb(hex(Color3.fromRGB(ch[1], ch[2], ch[3]))) close() end, true)
    ap.b.AnchorPoint, ap.b.Position = Vector2.new(1, 1), UDim2.fromScale(1, 1)
    sync()
end

local function applyThemeBrand()
    if type(TH.brandName) == "string" and TH.brandName ~= "" then BR.setName(TH.brandName) end
    if type(TH.brandLogo) == "string" and TH.brandLogo ~= "" then BR.setLogo(TH.brandLogo) end
end
local THEME_PRESETS = {
    -- layout presets: the original SM1LER window and a top-navigation variant (any layout can be built in Theme > Layout)
    { G("🧩 SM1LER Classic", "🧩 SM1LER Classic"), { brandName = "SM1LER", brandLogo = "S", winW = 700, winH = 372, sbPos = "left", sbW = 58, sbLabels = false, sbSplit = true, sbGap = 10, sbFooter = false, sbCollapse = false,
        titleBar = false, ctrlLoc = "header", edTree = false, edCrumb = false, edStatus = false, tabStyle = "pill", radius = 1.3,
        home = { account = true, plan = true, license = true, version = true, exec = true, news = false } } },
    { G("📑 Top bar", "📑 Верхняя панель"), { winW = 820, winH = 430, sbPos = "top", sbLabels = true, sbSplit = false, sbFooter = false, sbCollapse = false,
        titleBar = true, ctrlLoc = "title", edTree = false, edCrumb = true, edStatus = true, tabStyle = "flat", radius = 0.8 } },
    { G("⚡ Volt", "⚡ Volt"), { brandName = "Volt", brandLogo = "bolt", mode = "color", color = "#111111", g3 = "", neonA = "#3a3a3a", neonB = "#262626",
        rainbow = false, neonSpeed = 1, neonThick = 1, panelAlpha = 0, pal = "volt", radius = 0.6, borderScale = 1, font = "Builder Sans", textScale = 1 },
      { kw = "#C586C0", str = "#CE9178", num = "#B5CEA8", comment = "#5E6878", bi = "#DCDCAA" } },
    { G("🎄 New Year", "🎄 Новый год"), { mode = "gradient", g1 = "#040a1c", g2 = "#0b3d2e", g3 = "#6b0f24", angle = 150, neonA = "#ffd76a", neonB = "#ff4d5e",
        rainbow = false, neonSpeed = 45, neonThick = 2, panelAlpha = 0.22, special = "newyear" } },
    { "Midnight", { mode = "gradient", g1 = "#000000", g2 = "#0b1026", g3 = "", angle = 135, neonA = "#ffffff", neonB = "#8fb4ff" } },
    { "Aurora",   { mode = "gradient", g1 = "#02100f", g2 = "#0a3b3a", g3 = "#1b2a6b", angle = 120, neonA = "#7cffcb", neonB = "#74a8ff" } },
    { "Sunset",   { mode = "gradient", g1 = "#12031f", g2 = "#5a1a6b", g3 = "#ff5e78", angle = 60, neonA = "#ff9e7a", neonB = "#ff5ec8" } },
    { "Ocean",    { mode = "gradient", g1 = "#00080f", g2 = "#003b5c", g3 = "", angle = 90, neonA = "#00e5ff", neonB = "#6aa8ff" } },
    { "Matrix",   { mode = "gradient", g1 = "#000000", g2 = "#002b0f", g3 = "", angle = 90, neonA = "#00ff66", neonB = "#b6ffcc" } },
    { "Rainbow",  { mode = "gradient", g1 = "#000000", g2 = "#0a0a16", g3 = "", angle = 135, rainbow = true, neonSpeed = 60 } },
    { "Mono",     { mode = "none", neonA = "#ffffff", neonB = "#ffffff" } },
}

----------------------------------------------------------------------
-- CUSTOM THEMES (import .realtheme / create / export)
----------------------------------------------------------------------
do
    local function trim(t) return (string.gsub(tostring(t or ""), "^%s*(.-)%s*$", "%1")) end
    local function jsonDecode(t)
        local ok, r = pcall(function() return HttpService:JSONDecode(t) end)
        if ok then return r end
        return nil
    end

    -- converts a Real (.realtheme) table or an SM1LER theme table into { name, th, syn, note }
    local function num01(v, fb) return (type(v) == "number" and v >= 0 and v <= 1) and v or fb end
    function CT.fromReal(d)
        if type(d) ~= "table" then return nil, G("This is not a theme file", "Это не файл темы") end
        local e = { name = tostring(d.name or "Imported theme") }
        local extra = {}
        if type(d.windowCornerRadius) == "number" then extra.radius = math.clamp(d.windowCornerRadius / 10, 0, 2) end
        if type(d.windowBorderWidth) == "number" then extra.borderScale = math.clamp(d.windowBorderWidth, 0, 3) end
        if type(d.windowBorderColor) == "string" and hexToColor(d.windowBorderColor) then extra.neonA, extra.neonB = d.windowBorderColor, d.windowBorderColor end
        if type(d.windowBorderRainbow) == "boolean" then extra.rainbow = d.windowBorderRainbow end
        if type(d.watermark) == "boolean" then extra.watermark = d.watermark end
        if type(d.showTitlebarVersion) == "boolean" then extra.showTitleVersion = d.showTitlebarVersion end
        if type(d.showLogoIcon) == "boolean" then extra.logoIcon = d.showLogoIcon end
        if type(d.showLogoText) == "boolean" then extra.logoText = d.showLogoText end
        if d.navLabelMode == "icon-only" then extra.navLabelMode = "icon" elseif d.navLabelMode == "text-only" then extra.navLabelMode = "text" elseif d.navLabelMode == "both" then extra.navLabelMode = "both" end
        if d.explorerSide == "right" or d.explorerSide == "left" then extra.treeSide = d.explorerSide end
        if d.toolbarPosition == "top" or d.toolbarPosition == "bottom" then extra.toolbarPos = d.toolbarPosition end
        if d.navPosition == "top" or d.navPosition == "left" or d.navPosition == "right" then extra.sbPos = d.navPosition end
        if type(d.uiGridEnabled) == "boolean" then extra.uiGrid = d.uiGridEnabled end
        if type(d.colorfulIcons) == "boolean" then extra.colorfulIcons = d.colorfulIcons end
        if type(d.bgUrl) == "string" and d.bgUrl ~= "" then extra.mode, extra.image = "image", d.bgUrl end
        if type(d.bgOpacity) == "number" then extra.imgAlpha = 1 - math.clamp(d.bgOpacity, 0, 1) end
        if type(d.bgStrength) == "number" then extra.dim = math.clamp(d.bgStrength, 0, 1) end
        if type(d.th) == "table" then
            e.th, e.syn = d.th, d.syn
            return e
        end
        local th = {}
        for k, v in pairs(TD) do th[k] = cpv(v) end
        local ct = d.customTheme
        if type(ct) == "table" and (ct.bg or ct.surface) then
            local tk = type(ct.tokens) == "table" and ct.tokens or {}
            th.mode, th.angle, th.g3 = "gradient", 90, ""
            th.g1 = ct.bg or ct.surface
            th.g2 = ct.surface or ct.bg
            th.neonA = ct.accent or tk.accent2 or "#ffffff"
            th.neonB = tk.accent2 or ct.accent or "#ffffff"
        else
            local pn = string.gsub(string.lower(tostring(d.theme or "")), "^theme%-", "")
            local found
            for _, pr in ipairs(THEME_PRESETS) do if string.lower(pr[1]) == pn then found = pr end end
            if found then
                for k, v in pairs(found[2]) do th[k] = v end
            end
            e.note = G("The file has no colors, so a built-in preset was used.", "В файле нет цветов, использован встроенный пресет.")
        end
        local cs = d.customSyntaxTheme
        if type(cs) == "table" and type(cs.json) == "string" then
            local sj = jsonDecode(cs.json)
            if type(sj) == "table" and type(sj.rules) == "table" then
                local map = { keyword = { "kw", 1 }, string = { "str", 1 }, number = { "num", 1 }, comment = { "comment", 1 },
                    ["function"] = { "bi", 1 }, ["function.defaultLibrary"] = { "bi", 2 }, ["function.builtin"] = { "bi", 3 } }
                local rank, syn = {}, {}
                for _, r in ipairs(sj.rules) do
                    local m = map[r.token]
                    if m and type(r.foreground) == "string" and r.foreground ~= "" and (rank[m[1]] or 0) < m[2] then
                        syn[m[1]] = "#" .. string.sub((string.gsub(r.foreground, "#", "")), 1, 6)
                        rank[m[1]] = m[2]
                    end
                end
                if next(syn) then e.syn = syn end
            end
        end
        for k, v in pairs(extra) do th[k] = v end
        e.th = th
        return e
    end

    function CT.store(e)
        DB.customThemes = type(DB.customThemes) == "table" and DB.customThemes or {}
        for i, x in ipairs(DB.customThemes) do
            if x.name == e.name then DB.customThemes[i] = e saveDB() return end
        end
        DB.customThemes[#DB.customThemes + 1] = e
        saveDB()
    end

    function CT.apply(e)
        TH.special, TH.pal, TH.palCustom = nil, nil, nil
        for k, v in pairs(TD) do TH[k] = cpv(v) end
        for k, v in pairs(e.th or {}) do
            if type(v) == "table" then local cp = {} for a, b in pairs(v) do cp[a] = b end v = cp end
            TH[k] = v
        end
        applyThemeBrand()
        resetSyntax()
        if e.syn then setSyntax(e.syn) end
        DB.activeCustom, DB.activeSyn = e.name, e.syn
        bgI.Image = ""
        applyTheme()
        saveDB()
        refreshCode()
        if CT.rebuild then CT.rebuild() end
        if CT.refreshList then CT.refreshList() end
    end

    function CT.saveCurrent(name, syn)
        name = trim(name)
        if name == "" then name = "My theme" end
        local th = {}
        for k in pairs(TD) do th[k] = cpv(TH[k]) end
        th.special, th.pal = TH.special, TH.pal
        th.brandName, th.brandLogo = CFG.Name, (DB.brand.vectorLogo and "bolt") or DB.brand.imgSpec or DB.brand.logo or "S"
        if TH.palCustom then th.palCustom = {} for a, b in pairs(TH.palCustom) do th.palCustom[a] = b end end
        local e = { name = name, th = th, syn = syn or getSyntax() }
        CT.store(e)
        DB.activeCustom, DB.activeSyn = name, e.syn
        setSyntax(e.syn)
        refreshCode()
        saveDB()
        if CT.refreshList then CT.refreshList() end
        return e
    end

    function CT.readFile(spec)
        spec = trim(spec)
        if spec == "" then return nil, G("Enter a file name or paste the theme JSON", "Введи имя файла или вставь JSON темы") end
        local body
        if string.sub(spec, 1, 1) == "{" then
            body = spec
        else
            if not (readfile and isfile) then return nil, G("File access is not supported here", "Доступ к файлам здесь не поддерживается") end
            for _, path in ipairs({ spec, "SM1LER/themes/" .. spec, "SM1LER/" .. spec, spec .. ".realtheme", "SM1LER/themes/" .. spec .. ".realtheme" }) do
                local ok, has = pcall(isfile, path)
                if ok and has then
                    local ok2, t = pcall(readfile, path)
                    if ok2 and type(t) == "string" then body = t break end
                end
            end
            if not body then return nil, G("File not found: ", "Файл не найден: ") .. spec end
        end
        local d = jsonDecode(body)
        if not d then return nil, G("Invalid JSON", "Некорректный JSON") end
        return CT.fromReal(d)
    end

    function CT.import(spec)
        local e, err = CT.readFile(spec)
        if not e then return false, err end
        CT.store(e)
        CT.apply(e)
        notify(G("Theme imported: ", "Тема импортирована: ") .. e.name .. (e.note and ("\n" .. e.note) or ""))
        return true
    end

    -- finds our own .theme files and keeps them in the theme list (file = source of truth)
    function CT.discover()
        local out, seen = {}, {}
        if not listfiles then return out end
        for _, folder in ipairs({ "SM1LER/themes", "SM1LER", "." }) do
            local ok, files = pcall(listfiles, folder)
            if ok and type(files) == "table" then
                for _, f in ipairs(files) do
                    if type(f) == "string" then
                        local path = (string.gsub(f, "\\", "/"))
                        if string.lower(string.sub(path, -6)) == ".theme" and not seen[path] then
                            seen[path] = true
                            out[#out + 1] = path
                        end
                    end
                end
            end
        end
        return out
    end
    function CT.autoScan(announce)
        pcall(function()
            if makefolder and isfolder then
                if not isfolder("SM1LER") then makefolder("SM1LER") end
                if not isfolder("SM1LER/themes") then makefolder("SM1LER/themes") end
            end
        end)
        local files = CT.discover()
        DB.customThemes = type(DB.customThemes) == "table" and DB.customThemes or {}
        local added = 0
        for _, f in ipairs(files) do
            local e = CT.readFile(f)
            if e then
                local existed = false
                for _, x in ipairs(DB.customThemes) do if x.name == e.name then existed = true break end end
                CT.store(e)
                if not existed then added = added + 1 end
            end
        end
        if CT.refreshList then CT.refreshList() end
        if announce and added > 0 then
            notify(G("Found ", "Найдено ") .. added .. G(" new .theme file(s). Open Settings > Custom themes.", " новых файлов .theme. Открой Settings > Custom themes."))
        end
        return #files, added
    end
    function CT.scan()
        local out, seen = {}, {}
        if not listfiles then return out end
        for _, folder in ipairs({ "SM1LER/themes", "SM1LER", ".", "" }) do
            local ok, files = pcall(listfiles, folder)
            if ok and type(files) == "table" then
                for _, f in ipairs(files) do
                    if type(f) == "string" and string.lower(string.sub(f, -10)) == ".realtheme" and not seen[f] then
                        seen[f] = true
                        out[#out + 1] = f
                    end
                end
            end
        end
        return out
    end

    -- Real-app compatible theme (colors + code colors only)
    function CT.toReal(e)
        local th, syn = e.th or {}, e.syn or {}
        local rules = {}
        for k, token in pairs({ kw = "keyword", str = "string", num = "number", comment = "comment", bi = "function" }) do
            if syn[k] then rules[#rules + 1] = { token = token, foreground = (string.gsub(syn[k], "#", "")) } end
        end
        local sj = HttpService:JSONEncode({ base = "vs-dark", inherit = true, rules = rules, colors = {} })
        local pc = th.palCustom or {}
        local volt = th.pal == "volt"
        local bg = pc.bg or (th.mode == "color" and th.color) or th.g1 or "#111111"
        return { ["$app"] = "Real", name = e.name,
            customTheme = { id = "c" .. string.lower((string.gsub(e.name, "[^%w]", ""))), name = e.name, bg = bg,
                surface = pc.panel or (volt and "#171717") or th.g2 or bg, text = pc.text or "#cccccc",
                accent = pc.white or th.neonA or "#ffffff", tokens = { accent2 = th.neonB or th.neonA or "#ffffff",
                    border = pc.line or (volt and "#262626") or nil, bg3 = pc.item or (volt and "#242424") or nil } },
            customSyntaxTheme = { name = e.name, json = sj } }
    end
    function CT.encode(e, fmt)
        local data = fmt == "real" and CT.toReal(e) or { ["$app"] = "SM1LER", ["$version"] = 1, name = e.name, th = e.th, syn = e.syn }
        local ok, json = pcall(function() return HttpService:JSONEncode(data) end)
        return ok and json or nil
    end
    function CT.writeFile(name, json, ext)
        if not writefile then return nil end
        pcall(function()
            if makefolder and isfolder then
                if not isfolder("SM1LER") then makefolder("SM1LER") end
                if not isfolder("SM1LER/themes") then makefolder("SM1LER/themes") end
            end
        end)
        local clean = string.gsub(tostring(name), "[^%w%-_ ]", "_")
        if clean == "" then clean = "theme" end
        local path = "SM1LER/themes/" .. clean .. (ext or ".theme")
        if pcall(writefile, path, json) then return path end
        return nil
    end

    function CT.export(e)
        local ok, json = pcall(function()
            return HttpService:JSONEncode({ ["$app"] = "SM1LER", ["$version"] = 1, name = e.name, th = e.th, syn = e.syn })
        end)
        if not ok then notify(G("Export failed", "Не удалось экспортировать")) return end
        local where
        if writefile then
            pcall(function()
                if makefolder and isfolder then
                    if not isfolder("SM1LER") then makefolder("SM1LER") end
                    if not isfolder("SM1LER/themes") then makefolder("SM1LER/themes") end
                end
            end)
            local path = "SM1LER/themes/" .. (string.gsub(e.name, "[^%w%-_ ]", "_")) .. ".realtheme"
            if pcall(writefile, path, json) then where = path end
        end
        if setclipboard then pcall(setclipboard, json) end
        if where then notify(G("Saved to ", "Сохранено в ") .. where .. (setclipboard and G(" (also copied)", " (и скопировано)") or ""))
        elseif setclipboard then notify(G("Theme JSON copied", "JSON темы скопирован"))
        else notify(G("Export is not supported here", "Экспорт здесь не поддерживается")) end
    end
end

do
    local h = header(themePage, "Theme")
    local scroll = new("ScrollingFrame", {
        Parent = themePage, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
    }, { vlist(8) })
    local rows, build = {}, nil
    CT.rebuild = function() if build then build() end end

    local function updateVis()
        local m = TH.mode
        for name, r in pairs(rows) do
            local show = true
            if name == "color" then show = (m == "color")
            elseif string.sub(name, 1, 4) == "grad" then show = (m == "gradient")
            elseif string.sub(name, 1, 3) == "img" then show = (m == "image") end
            r.Visible = show
        end
    end
    local function commit() applyTheme() saveDB() end

    function build()
        for _, c in ipairs(scroll:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
        rows = {}
        local order = 0
        local function nxt() order = order + 1 return order end
        local function section(key)
            local l = txt(scroll, "", 12, C.sub, Enum.Font.GothamBold)
            l.LayoutOrder, l.Size = nxt(), UDim2.new(1, 0, 0, 18)
            reg(l, key)
        end
        local function rowF(name, labelKey, height)
            local r = new("Frame", { Parent = scroll, LayoutOrder = nxt(), Size = UDim2.new(1, -6, 0, height or 42), BackgroundColor3 = C.panel }, { round(12) })
            if labelKey then
                local l = txt(r, "", 13, C.text, Enum.Font.GothamMedium)
                l.Position, l.Size = UDim2.fromOffset(14, 0), UDim2.new(0.4, 0, 1, 0)
                reg(l, labelKey)
            end
            if name then rows[name] = r end
            return r
        end
        local function chipRow(items, current, onPick, height)
            local f = new("Frame", { Parent = scroll, LayoutOrder = nxt(), Size = UDim2.new(1, -6, 0, height or 36), BackgroundTransparency = 1 },
                { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
            local chips = {}
            for i, it in ipairs(items) do
                local P = pill(f, it, nil, UDim2.fromOffset(112, 34), function()
                    for k, c in pairs(chips) do c.set(k == it) end
                    onPick(it)
                end)
                P.b.LayoutOrder = i
                P.set(it == current)
                chips[it] = P
            end
        end
        local function colorRow(name, labelKey, field, optional)
            local r = rowF(name, labelKey)
            local sw = new("TextButton", { Parent = r, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(30, 30),
                AutoButtonColor = false, Text = "", BackgroundColor3 = C.item }, { round(8), stroke(C.line) })
            local box = new("TextBox", { Parent = r, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -46, 0.5, 0), Size = UDim2.fromOffset(96, 30),
                BackgroundColor3 = C.item, TextColor3 = C.text, Font = Enum.Font.Code, TextSize = 13, Text = "", ClearTextOnFocus = false }, { round(8) })
            local function refresh()
                local c = hexToColor(TH[field])
                sw.BackgroundColor3 = c or C.item
                box.Text = (TH[field] ~= "" and TH[field]) or "none"
            end
            refresh()
            local function setHex(hs) TH[field] = hs refresh() commit() end
            bind(box.FocusLost, function()
                local t = string.lower(box.Text)
                if hexToColor(t) then setHex("#" .. string.gsub(t, "#", ""))
                elseif optional and (t == "" or t == "none") then setHex("")
                else refresh() end
            end)
            bind(sw.MouseButton1Click, function() pickColor(TH[field], setHex) end)
        end
        local function sliderRow(name, labelKey, mn, mx, step, get, set, fmt)
            local r = rowF(name, labelKey)
            local f = slider(r, 230, mn, mx, step, get, function(v) set(v) applyTheme() end, fmt)
            f.AnchorPoint, f.Position = Vector2.new(1, 0.5), UDim2.new(1, -12, 0.5, 0)
        end
        local pct = function(v) return math.floor(v * 100 + 0.5) .. "%" end
        local function palRow(key, label)
            local r = rowF(nil, label)
            local sw = new("TextButton", { Parent = r, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(30, 30),
                AutoButtonColor = false, Text = "", BackgroundColor3 = C[key] }, { round(8), stroke(C.line) })
            local box = new("TextBox", { Parent = r, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -46, 0.5, 0), Size = UDim2.fromOffset(96, 30),
                BackgroundColor3 = C.item, TextColor3 = C.text, Font = Enum.Font.Code, TextSize = 13, Text = hex(C[key]), ClearTextOnFocus = false }, { round(8) })
            local function refresh() sw.BackgroundColor3, box.Text = C[key], hex(C[key]) end
            local function setHex(hs) if PAL.set(key, hs) then refresh() commit() end end
            bind(box.FocusLost, function()
                local t = string.lower(string.gsub(box.Text, "%s", ""))
                if string.sub(t, 1, 1) ~= "#" then t = "#" .. t end
                if hexToColor(t) then setHex(t) else refresh() end
            end)
            bind(sw.MouseButton1Click, function() pickColor(hex(C[key]), setHex) end)
        end

        section("Presets")
        local pg = new("Frame", { Parent = scroll, LayoutOrder = nxt(), Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 },
            { new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 0, 34), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
        for i, p in ipairs(THEME_PRESETS) do
            local P = pill(pg, p[1], nil, UDim2.new(), function()
                for k, v in pairs(TD) do TH[k] = cpv(v) end   -- a theme replaces the whole configuration
                TH.rainbow, TH.special, TH.pal, TH.palCustom = false, nil, nil, nil
                for k, v in pairs(p[2]) do TH[k] = cpv(v) end
                if p[2].g3 == nil then TH.g3 = "" end
                DB.activeCustom, DB.activeSyn = nil, nil
                applyThemeBrand()
                resetSyntax()
                if p[3] then setSyntax(p[3]) DB.activeSyn = p[3] end
                refreshCode()
                commit()
                build()
            end, p[2].special and true or nil)
            P.b.LayoutOrder = i
        end

        section("Background")
        chipRow({ "None", "Color", "Gradient", "Image" }, ({ none = "None", color = "Color", gradient = "Gradient", image = "Image" })[TH.mode] or "None", function(it)
            TH.mode = string.lower(it)
            updateVis()
            commit()
        end)
        colorRow("color", "Color", "color")
        colorRow("grad1", "Color 1", "g1")
        colorRow("grad2", "Color 2", "g2")
        colorRow("grad3", "Color 3 (optional)", "g3", true)
        sliderRow("gradAngle", "Angle", 0, 360, 5, function() return TH.angle end, function(v) TH.angle = v end, function(v) return v .. "°" end)

        local ir = rowF("imgInput", "Image", 46)
        local ibox = new("TextBox", { Parent = ir, Position = UDim2.fromOffset(84, 6), Size = UDim2.new(1, -196, 0, 34), BackgroundColor3 = C.item, TextColor3 = C.text,
            PlaceholderColor3 = C.sub, PlaceholderText = "rbxassetid://… / number / PNG-JPG link", Font = Enum.Font.Gotham, TextSize = 12, Text = TH.image,
            ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, { round(8), new("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
        local loadP = pill(ir, "Load", "check", UDim2.fromOffset(92, 34), function()
            TH.image = ibox.Text
            task.spawn(function()
                resolveImage(TH.image)
                commit()
            end)
        end, true)
        loadP.b.AnchorPoint, loadP.b.Position = Vector2.new(1, 0.5), UDim2.new(1, -8, 0.5, 0)
        local mr = rowF("imgMsg", nil, 30)
        mr.BackgroundTransparency = 1
        imgMsgLbl = txt(mr, "", 12, C.sub)
        imgMsgLbl.Position, imgMsgLbl.Size, imgMsgLbl.TextWrapped = UDim2.fromOffset(4, 0), UDim2.new(1, -8, 1, 0), true
        setImgMsg(G("Image ids must be Image assets (not Decals). Links need writefile + getcustomasset.", "id должен быть Image-ассетом (не Decal). Для ссылок нужны writefile и getcustomasset."))
        rows.imgScale = nil
        local sr = new("Frame", { Parent = scroll, LayoutOrder = nxt(), Size = UDim2.new(1, -6, 0, 36), BackgroundTransparency = 1 },
            { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
        rows.imgScale = sr
        local scChips = {}
        for i, it in ipairs({ "Crop", "Fit", "Stretch", "Tile" }) do
            local P = pill(sr, it, nil, UDim2.fromOffset(112, 34), function()
                for k, c in pairs(scChips) do c.set(k == it) end
                TH.imgScale = it
                commit()
            end)
            P.b.LayoutOrder = i
            P.set(TH.imgScale == it)
            scChips[it] = P
        end
        sliderRow("imgAlpha", "Image opacity", 0.05, 1, 0.05, function() return 1 - TH.imgAlpha end, function(v) TH.imgAlpha = 1 - v end, pct)
        sliderRow("imgDim", "Darkness", 0, 0.9, 0.05, function() return TH.dim end, function(v) TH.dim = v end, pct)

        sliderRow(nil, "Panel transparency", 0, 0.85, 0.05, function() return TH.panelAlpha end, function(v) TH.panelAlpha = v end, pct)

        local function tgl(label, getter, setter)
            local rr = rowF(nil, label)
            local on = getter()
            local track = new("TextButton", { Parent = rr, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(46, 26),
                AutoButtonColor = false, Text = "", BackgroundColor3 = on and C.white or C.item }, { round(13) })
            new("Frame", { Parent = track, AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(20, 20), BorderSizePixel = 0,
                Position = on and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = on and C.black or C.sub }, { round(10) })
            bind(track.MouseButton1Click, function()
                setter(not getter())
                commit()
                build()
            end)
        end
        local num = function(v) return tostring(v) end

        section(G("Layout: window", "Раскладка: окно"))
        sliderRow(nil, G("Window width", "Ширина окна"), 560, 1100, 10, function() return TH.winW end, function(v) TH.winW = v end, num)
        sliderRow(nil, G("Window height", "Высота окна"), 340, 600, 10, function() return TH.winH end, function(v) TH.winH = v end, num)
        tgl(G("Title bar", "Строка заголовка"), function() return TH.titleBar == true end, function(v) TH.titleBar = v end)
        sliderRow(nil, G("Title bar height", "Высота заголовка"), 28, 48, 2, function() return TH.titleH end, function(v) TH.titleH = v end, num)
        chipRow({ "title", "header" }, TH.ctrlLoc, function(it) TH.ctrlLoc = it commit() build() end)
        chipRow({ "win", "sm1ler", "mac", "linux" }, S.guiStyle, function(it) S.guiStyle = it saveDB() applyGuiStyle() build() end)

        section(G("Layout: sidebar", "Раскладка: боковая панель"))
        chipRow({ "left", "right", "top" }, TH.sbPos, function(it) TH.sbPos = it commit() build() end)
        chipRow({ "flat", "card" }, TH.sbSplit and "card" or "flat", function(it) TH.sbSplit = (it == "card") commit() build() end)
        sliderRow(nil, G("Sidebar width", "Ширина панели"), 48, 260, 4, function() return TH.sbW end, function(v) TH.sbW = v end, num)
        sliderRow(nil, G("Gap (card mode)", "Отступ (режим карточек)"), 0, 20, 1, function() return TH.sbGap end, function(v) TH.sbGap = v end, num)
        tgl(G("Menu labels", "Подписи в меню"), function() return TH.sbLabels == true end, function(v) TH.sbLabels = v end)
        tgl(G("User card", "Карточка пользователя"), function() return TH.sbFooter == true end, function(v) TH.sbFooter = v end)
        tgl(G("Collapse button", "Кнопка сворачивания"), function() return TH.sbCollapse == true end, function(v) TH.sbCollapse = v end)

        section(G("Layout: editor", "Раскладка: редактор"))
        tgl(G("File tree", "Дерево файлов"), function() return TH.edTree == true end, function(v) TH.edTree = v end)
        tgl(G("Tab name + Inject row", "Строка вкладки + Inject"), function() return TH.edCrumb == true end, function(v) TH.edCrumb = v end)
        tgl(G("Status line", "Строка состояния"), function() return TH.edStatus == true end, function(v) TH.edStatus = v end)
        chipRow({ "flat", "pill" }, TH.tabStyle, function(it) TH.tabStyle = it commit() build() end)

        section(G("Layout: home cards", "Раскладка: карточки главной"))
        for _, hk in ipairs({ { "account", G("Account", "Аккаунт") }, { "plan", G("Plan", "Тариф") }, { "license", G("License + time", "Лицензия + время") },
            { "status", G("Status", "Статус") }, { "version", G("Version", "Версия") }, { "exec", G("Executor", "Экзекьютор") }, { "news", G("What's new", "Что нового") } }) do
            tgl(hk[2], function() return not (type(TH.home) == "table" and TH.home[hk[1]] == false) end,
                function(v) TH.home = type(TH.home) == "table" and TH.home or {} TH.home[hk[1]] = v end)
        end

        section(G("Layout: menu pages", "Раскладка: страницы меню"))
        for _, pn in ipairs({ "Home", "Editor", "Scripts", "Console", "AI", "Account", "Info" }) do
            tgl(G("Show ", "Показывать ") .. pn, function() return not (type(TH.navOff) == "table" and TH.navOff[pn] == true) end,
                function(v) TH.navOff = type(TH.navOff) == "table" and TH.navOff or {} TH.navOff[pn] = (not v) or nil end)
        end

        section(G("Layout: extras", "Раскладка: дополнительно"))
        chipRow({ "icon", "text", "both" }, TH.navLabelMode, function(it) TH.navLabelMode = it commit() build() end)
        chipRow({ "left", "right" }, TH.treeSide, function(it) TH.treeSide = it commit() build() end)
        chipRow({ "top", "bottom" }, TH.toolbarPos, function(it) TH.toolbarPos = it commit() build() end)
        tgl(G("Colorful menu icons", "Цветные иконки меню"), function() return TH.colorfulIcons == true end, function(v) TH.colorfulIcons = v end)
        tgl(G("Title bar version", "Версия в заголовке"), function() return TH.showTitleVersion == true end, function(v) TH.showTitleVersion = v end)
        tgl(G("Show logo icon", "Показывать значок"), function() return TH.logoIcon ~= false end, function(v) TH.logoIcon = v end)
        tgl(G("Show logo text (name)", "Показывать текст (название)"), function() return TH.logoText ~= false end, function(v) TH.logoText = v end)
        tgl(G("Watermark", "Водяной знак"), function() return TH.watermark == true end, function(v) TH.watermark = v end)
        tgl(G("Faint grid background", "Фоновая сетка"), function() return TH.uiGrid == true end, function(v) TH.uiGrid = v end)
        sliderRow(nil, G("Panel depth (shadow)", "Глубина панелей (тень)"), 0, 3, 1, function() return TH.panelDepth end, function(v) TH.panelDepth = v end, num)

        section(G("Interface", "Интерфейс"))
        sliderRow(nil, G("Corner radius", "Скругление углов"), 0, 2, 0.1, function() return TH.radius end, function(v) TH.radius = v end, pct)
        sliderRow(nil, G("Border width", "Толщина рамок"), 0, 3, 0.5, function() return TH.borderScale end, function(v) TH.borderScale = v end, pct)
        sliderRow(nil, G("Text size", "Размер текста"), 0.85, 1.2, 0.05, function() return TH.textScale end, function(v) TH.textScale = v end, pct)
        chipRow({ STY.fonts[1], STY.fonts[2], STY.fonts[3] }, TH.font, function(it) TH.font = it commit() build() end)
        chipRow({ STY.fonts[4], STY.fonts[5], STY.fonts[6] }, TH.font, function(it) TH.font = it commit() build() end)

        section(G("Palette (recolors the whole interface)", "Палитра (перекрашивает весь интерфейс)"))
        for _, k in ipairs(PAL.keys) do
            palRow(k, ({ bg = G("Window", "Окно"), panel = G("Panels", "Панели"), item = G("Items / inputs", "Элементы / поля"), hover = G("Hover", "Наведение"),
                line = G("Borders", "Границы"), text = G("Text", "Текст"), sub = G("Secondary text", "Второй текст"), white = G("Accent / buttons", "Акцент / кнопки"),
                ok = G("Success", "Успех"), warn = G("Warning", "Предупреждение"), err = G("Error", "Ошибка"), info = G("Info", "Инфо") })[k])
        end
        do
            local rp = pill(scroll, G("Reset palette", "Сбросить палитру"), "refresh", UDim2.fromOffset(170, 34), function()
                PAL.reset()
                commit()
                build()
            end)
            rp.b.LayoutOrder = nxt()
        end

        section("Neon border")
        do
            local rr = rowF(nil, "Rainbow neon")
            local on = TH.rainbow == true
            local track = new("TextButton", { Parent = rr, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(46, 26),
                AutoButtonColor = false, Text = "", BackgroundColor3 = on and C.white or C.item }, { round(13) })
            new("Frame", { Parent = track, AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(20, 20), BorderSizePixel = 0,
                Position = on and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = on and C.black or C.sub }, { round(10) })
            bind(track.MouseButton1Click, function()
                TH.rainbow = not TH.rainbow
                if TH.rainbow and TH.neonSpeed < 40 then TH.neonSpeed = 60 end
                commit()
                build()
            end)
        end
        colorRow(nil, "Neon color A", "neonA")
        colorRow(nil, "Neon color B", "neonB")
        sliderRow(nil, "Neon speed", 0, 120, 5, function() return TH.neonSpeed end, function(v) TH.neonSpeed = v end, function(v) return tostring(v) end)
        sliderRow(nil, "Neon thickness", 1, 4, 0.5, function() return TH.neonThick end, function(v) TH.neonThick = v end, function(v) return tostring(v) end)
        updateVis()
    end
    build()

    local resetP = pill(h, "Reset", "refresh", UDim2.fromOffset(100, 32), function()
        for k, v in pairs(TD) do TH[k] = cpv(v) end
        TH.special, TH.pal, TH.palCustom = nil, nil, nil
        bgI.Image = ""
        commit()
        build()
    end)
    resetP.b.AnchorPoint = Vector2.new(1, 0)
    placeRight(resetP.b, 2)
end

end) if not ok_blk26 then warn("[blk26] " .. tostring(err_blk26)) end

-- INJECT status bar on Home ----------------------------------------------
local ok_blk27, err_blk27 = pcall(function()
    local pg = pages.Home
    local bar = new("Frame", { Parent = pg, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = C.panel }, { round(14), stroke() })
    local dot = new("Frame", { Parent = bar, Position = UDim2.fromOffset(16, 18), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = C.err, BorderSizePixel = 0 }, { round(5) })
    local lbl = txt(bar, "", 13, C.text, Enum.Font.GothamMedium)
    lbl.Position, lbl.Size = UDim2.fromOffset(36, 0), UDim2.new(1, -210, 1, 0)
    local P = makeInjectButton(bar, UDim2.fromOffset(150, 34))
    P.b.AnchorPoint, P.b.Position = Vector2.new(1, 0.5), UDim2.new(1, -8, 0.5, 0)
    INJ.hooks[#INJ.hooks + 1] = function()
        if injecting then lbl.Text, dot.BackgroundColor3 = G("Injector: attaching...", "Инжектор: подключение..."), C.warn
        elseif injected then lbl.Text, dot.BackgroundColor3 = G("Injector: injected - scripts can run", "Инжектор: подключён - скрипты можно запускать"), C.ok
        elseif injectError then lbl.Text, dot.BackgroundColor3 = G("Injector failed: cannot run code here (see Console)", "Ошибка инжектора: здесь нельзя запускать код (см. Console)"), C.err
        else lbl.Text, dot.BackgroundColor3 = G("Injector: not injected - press INJECT", "Инжектор: не подключён - нажми INJECT"), C.err end
    end
    INJ.hooks[#INJ.hooks + 1] = function()
        if injecting then TBAR.lbl.Text, TBAR.dot.BackgroundColor3 = G("Attaching...", "Подключение..."), C.warn
        elseif injected then TBAR.lbl.Text, TBAR.dot.BackgroundColor3 = G("Injected", "Подключён"), C.ok
        else TBAR.lbl.Text, TBAR.dot.BackgroundColor3 = G("Not injected", "Не подключён"), C.err end
    end
    refreshInjectUI()
end) if not ok_blk27 then warn("[blk27] " .. tostring(err_blk27)) end

----------------------------------------------------------------------
-- STREAMER ENGINE (hides your real name in every GUI you can reach)
----------------------------------------------------------------------
local ok_blk28, err_blk28 = pcall(function()
    local function replaceWord(text, real, fake)
        if real == "" or not string.find(text, real, 1, true) then return text end
        local out, i, n = {}, 1, #text
        while i <= n do
            local a, b = string.find(text, real, i, true)
            if not a then out[#out + 1] = string.sub(text, i) break end
            local before = a > 1 and string.sub(text, a - 1, a - 1) or ""
            local after = b < n and string.sub(text, b + 1, b + 1) or ""
            local okB = before == "" or not string.match(before, "[%w_]") or string.sub(real, 1, 1) == "@"
            local okA = after == "" or not string.match(after, "[%w_]")
            if okB and okA then out[#out + 1] = string.sub(text, i, a - 1) .. fake
            else out[#out + 1] = string.sub(text, i, b) end
            i = b + 1
        end
        return table.concat(out)
    end
    local function transform(text, toFake)
        local real, rdisp = LP.Name, LP.DisplayName
        if toFake then
            text = replaceWord(text, "@" .. real, "@" .. Stream.handle)
            if rdisp ~= real then text = replaceWord(text, rdisp, Stream.display) end
            text = replaceWord(text, real, rdisp ~= real and Stream.handle or Stream.display)
        else
            text = replaceWord(text, "@" .. Stream.handle, "@" .. real)
            text = replaceWord(text, Stream.display, rdisp)
            if Stream.handle ~= Stream.display then text = replaceWord(text, Stream.handle, real) end
        end
        return text
    end
    local function isText(d) return d:IsA("TextLabel") or d:IsA("TextButton") end
    local function scrub(obj)
        if not Stream.active then return end
        local t = obj.Text
        if t ~= "" then
            local n = transform(t, true)
            if n ~= t then obj.Text = n end
        end
    end
    local function hook(obj)
        if Stream.hooked[obj] then return end
        Stream.hooked[obj] = true
        scrub(obj)
        Stream.conns[#Stream.conns + 1] = obj:GetPropertyChangedSignal("Text"):Connect(function() scrub(obj) end)
    end
    local function charHumanoid() local c = LP.Character return c and c:FindFirstChildOfClass("Humanoid") end
    local function setHumanoid(on)
        local h = charHumanoid()
        if not h then return end
        if on then
            if Stream.humOrig == nil then Stream.humOrig = h.DisplayName end
            h.DisplayName = Stream.display
        elseif Stream.humOrig ~= nil then
            h.DisplayName = Stream.humOrig
            Stream.humOrig = nil
        end
    end
    local function containers()
        local list = {}
        local okC, core = pcall(function() local c = game:GetService("CoreGui") local _ = #c:GetChildren() return c end)
        if okC and core then list[#list + 1] = core end
        local pgui = LP:FindFirstChildOfClass("PlayerGui")
        if pgui then list[#list + 1] = pgui end
        return list, okC
    end

    function applyStreamer(on)
        if on then
            Stream.active = true
            setHumanoid(true)
            local list, coreOk = containers()
            if not coreOk then addLog("WARN", "Streamer: CoreGui is not accessible here - the ESC menu / leaderboard / chat can't be masked (needs an executor).") end
            for _, c in ipairs(list) do
                Stream.watch[#Stream.watch + 1] = c.DescendantAdded:Connect(function(d) if isText(d) then hook(d) end end)
                task.spawn(function()
                    local k = 0
                    for _, d in ipairs(c:GetDescendants()) do
                        if not Stream.active then return end
                        if isText(d) then hook(d) end
                        k = k + 1
                        if k % 300 == 0 then task.wait() end
                    end
                end)
            end
            addLog("INFO", "Streamer mode ON - shown as " .. Stream.display .. " (@" .. Stream.handle .. ")")
        else
            Stream.active = false
            for _, c in ipairs(Stream.watch) do pcall(function() c:Disconnect() end) end
            Stream.watch = {}
            for _, c in ipairs(Stream.conns) do pcall(function() c:Disconnect() end) end
            Stream.conns = {}
            for obj in pairs(Stream.hooked) do
                if obj.Parent then
                    local t = obj.Text
                    local n = transform(t, false)
                    if n ~= t then obj.Text = n end
                end
            end
            Stream.hooked = setmetatable({}, { __mode = "k" })
            setHumanoid(false)
            addLog("INFO", "Streamer mode OFF")
        end
        if refreshHome then refreshHome() end
        if genv.__SM1LER_acc then genv.__SM1LER_acc() end
    end

    bind(LP.CharacterAdded, function(c)
        if S.streamer then
            c:WaitForChild("Humanoid", 10)
            task.wait(0.2)
            setHumanoid(true)
        end
    end)
end) if not ok_blk28 then warn("[blk28] " .. tostring(err_blk28)) end

----------------------------------------------------------------------
-- INFO PAGE
----------------------------------------------------------------------
local ok_blk29, err_blk29 = pcall(function()
    local pg = addPage("Info", "info")
    header(pg, "Info")
    local scroll = new("ScrollingFrame", { Parent = pg, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, { vlist(5) })
    local vals, order = {}, 0
    local function section(key)
        order = order + 1
        local l = txt(scroll, "", 12, C.sub, Enum.Font.GothamBold)
        l.LayoutOrder, l.Size = order, UDim2.new(1, 0, 0, 18)
        reg(l, key)
    end
    local function row(id, labelKey, copyable)
        order = order + 1
        local r = new("TextButton", { Parent = scroll, LayoutOrder = order, Size = UDim2.new(1, -6, 0, 32), BackgroundColor3 = C.panel, AutoButtonColor = false, Text = "" }, { round(10) })
        local l = txt(r, "", 12, C.sub, Enum.Font.GothamMedium)
        l.Position, l.Size = UDim2.fromOffset(14, 0), UDim2.new(0.38, 0, 1, 0)
        reg(l, labelKey)
        local v = txt(r, "-", 12, C.text, Enum.Font.GothamMedium, Enum.TextXAlignment.Right)
        v.AnchorPoint, v.Position, v.Size = Vector2.new(1, 0), UDim2.new(1, -14, 0, 0), UDim2.new(0.6, 0, 1, 0)
        v.TextTruncate = Enum.TextTruncate.AtEnd
        vals[id] = v
        if copyable then
            bind(r.MouseButton1Click, function()
                if S.streamer then notify("Hidden in streamer mode") return end
                if setclipboard then setclipboard(v.Text) notify("Copied: " .. v.Text) else notify("Clipboard not supported") end
            end)
        end
    end

    section("Player")
    row("display", "Display name") row("user", "Username") row("uid", "User ID", true) row("age", "Account age") row("member", "Membership") row("team", "Team")
    section("Game")
    row("gname", "Name") row("pid", "Place ID", true) row("gid", "Game ID", true) row("creator", "Creator") row("players", "Players")
    row("job", "Server ID", true) row("up", "Server uptime")
    section("Performance")
    row("fps", "FPS") row("ping", "Ping") row("mem", "Memory") row("inst", "Instances")
    section("Environment")
    row("exec", "Executor") row("injected", "Injector") row("caps", "Capabilities") row("core", "CoreGui access") row("rak", "RakNet library")
    section("Session")
    row("uptime", "SM1LER uptime") row("key", "Key time left") row("spam", "Spam runs")

    local fpsAvg, t0 = 60, os.clock()
    bind(RunService.Heartbeat, function(dt) fpsAvg = fpsAvg + ((1 / math.max(dt, 0.001)) - fpsAvg) * 0.05 end)
    local function clock(sec)
        sec = math.floor(sec)
        return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60)
    end
    local gname, creator
    task.spawn(function()
        local ok, inf = pcall(function() return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId) end)
        if ok and inf then gname = inf.Name creator = inf.Creator and inf.Creator.Name end
    end)
    -- static environment facts
    local caps = {}
    if request or http_request or (syn and syn.request) then caps[#caps + 1] = "request" end
    local okH, vH = pcall(function() return game.HttpGet end)
    if okH and vH ~= nil then caps[#caps + 1] = "HttpGet" end
    if writefile and readfile then caps[#caps + 1] = "files" end
    if setclipboard then caps[#caps + 1] = "clipboard" end
    if getgenv then caps[#caps + 1] = "getgenv" end
    if getrenv then caps[#caps + 1] = "getrenv" end
    if queue_on_teleport then caps[#caps + 1] = "queue_on_teleport" end
    local exName = "unknown"
    pcall(function() if identifyexecutor then exName = tostring((identifyexecutor())) end end)
    local coreOk = pcall(function() return #game:GetService("CoreGui"):GetChildren() end)
    local hasRak = (type(raknet) == "table") or (getgenv ~= nil and type(getgenv().raknet) == "table")

    task.spawn(function()
        while alive do
            if pg.Visible then
                vals.display.Text = dispName()
                vals.user.Text = "@" .. userName()
                vals.uid.Text = userIdText()
                vals.age.Text = LP.AccountAge .. " days"
                vals.member.Text = (pcall(function() return LP.MembershipType.Name end) and LP.MembershipType.Name) or "-"
                vals.team.Text = LP.Team and LP.Team.Name or "-"
                vals.gname.Text = gname or game.Name
                vals.pid.Text = tostring(game.PlaceId)
                vals.gid.Text = tostring(game.GameId)
                vals.creator.Text = creator or "-"
                vals.players.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
                vals.job.Text = S.streamer and "••••••••" or (game.JobId ~= "" and game.JobId or "(private / studio)")
                vals.up.Text = clock(workspace.DistributedGameTime)
                vals.fps.Text = tostring(math.floor(fpsAvg + 0.5))
                local okp, ping = pcall(function() return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
                vals.ping.Text = okp and (ping .. " ms") or "-"
                local okm, mem = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
                vals.mem.Text = okm and string.format("%.0f MB", mem) or "-"
                local oki, inst = pcall(function() return Stats.InstanceCount end)
                vals.inst.Text = oki and tostring(inst) or "-"
                vals.exec.Text = exName
                vals.injected.Text = injected and "injected" or (injectError and "failed" or "not injected")
                vals.caps.Text = #caps > 0 and table.concat(caps, ", ") or "none"
                vals.core.Text = coreOk and "yes" or "no"
                vals.rak.Text = hasRak and "detected (provided by your executor)" or "not available"
                vals.uptime.Text = clock(os.clock() - t0)
                vals.key.Text = keyLeftText()
                vals.spam.Text = tostring(spam.n)
            end
            task.wait(1)
        end
    end)
end) if not ok_blk29 then warn("[blk29] " .. tostring(err_blk29)) end

----------------------------------------------------------------------
-- KEY SYSTEM · LOADER · INTRO · EXPIRY
----------------------------------------------------------------------
local function fitScale(w, h)
    local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    return math.min(1, (vp.X - 24) / w, (vp.Y - 24) / h)
end

local GT = {}
local gateEvent = Instance.new("BindableEvent")

local function activateKey(key, exp)
    KEY.value, KEY.expires = key, exp
    DB.key = key
    unlocked = true
    saveDB()
    if topBtn then topBtn.Visible = S.topbtn end
    if refreshHome then refreshHome() end
end

-- Ads: { name, english tagline, russian tagline, color 1, color 2, link (nil = random "demo" ad without a link) }
-- Cards are decorative; the links open the brands' official sites. Edit / add / remove freely.
local ADS = {
    { "Ozon",         "Marketplace · delivery to your door",   "Маркетплейс · доставка до двери",       Color3.fromRGB(0, 91, 255),   Color3.fromRGB(0, 170, 255),  "https://www.ozon.ru" },
    { "AliExpress",   "Global marketplace · deals every day",  "Товары со всего мира · скидки",         Color3.fromRGB(230, 46, 4),   Color3.fromRGB(255, 130, 40), "https://www.aliexpress.com" },
    { "Wildberries",  "Online store · fashion, home and more", "Интернет-магазин · одежда, дом и многое", Color3.fromRGB(203, 17, 171), Color3.fromRGB(110, 30, 170), "https://www.wildberries.ru" },
    { "Standoff 2",   "Mobile shooter · play with friends",    "Мобильный шутер · играй с друзьями",    Color3.fromRGB(30, 30, 36),   Color3.fromRGB(240, 110, 20), "https://standoff2.com" },
    { "Discord",      "Chat, hang out, play together",         "Общайся и играй вместе с друзьями",     Color3.fromRGB(88, 101, 242), Color3.fromRGB(55, 65, 190),  "https://discord.com" },
    { "Minecraft",    "Build, explore, survive",               "Строй, исследуй, выживай",              Color3.fromRGB(58, 130, 36),  Color3.fromRGB(125, 88, 50),  "https://www.minecraft.net" },
    { "Claude",       "AI assistant by Anthropic",             "ИИ-ассистент от Anthropic",             Color3.fromRGB(204, 108, 78), Color3.fromRGB(240, 165, 125), "https://claude.ai" },
    { "ChatGPT",      "AI assistant by OpenAI",                "ИИ-ассистент от OpenAI",                Color3.fromRGB(16, 163, 127), Color3.fromRGB(8, 85, 70),    "https://chatgpt.com" },
    { "Gemini",       "AI assistant by Google",                "ИИ-ассистент от Google",                Color3.fromRGB(66, 133, 244), Color3.fromRGB(165, 105, 205), "https://gemini.google.com" },
    { "DeepSeek",     "AI chat and reasoning",                 "ИИ-чат и рассуждения",                  Color3.fromRGB(77, 107, 254), Color3.fromRGB(35, 55, 165),  "https://www.deepseek.com" },
    -- random ads (fictional, no link)
    { "Pixel Quest",   "Tiny heroes. Huge dungeons.",     "Маленькие герои. Огромные подземелья.", Color3.fromRGB(96, 64, 214),  Color3.fromRGB(34, 150, 226) },
    { "Turbo Kart",    "Drift. Boost. Repeat.",           "Дрифт. Ускорение. Повтор.",             Color3.fromRGB(226, 70, 70),  Color3.fromRGB(240, 160, 50) },
    { "Lumen Audio",   "Sound that fills the room.",      "Звук, который наполняет комнату.",      Color3.fromRGB(30, 140, 120), Color3.fromRGB(70, 200, 150) },
    { "Zen Tea Co.",   "One cup. Zero stress.",           "Одна чашка. Ноль стресса.",             Color3.fromRGB(60, 130, 70),  Color3.fromRGB(150, 190, 80) },
    { "Skyline Cloud", "Hosting that never sleeps.",      "Хостинг, который не спит.",             Color3.fromRGB(40, 70, 170),  Color3.fromRGB(110, 120, 240) },
    { "Byte Bakery",   "Fresh code, baked daily.",        "Свежий код, выпечка каждый день.",      Color3.fromRGB(190, 110, 50), Color3.fromRGB(240, 190, 90) },
    { "Orbit Fit",     "Train like gravity is optional.", "Тренируйся, будто гравитации нет.",     Color3.fromRGB(160, 50, 160), Color3.fromRGB(230, 90, 150) },
    { "Neon Noodles",  "Late-night ramen, lit up.",       "Ночной рамен, весь в неоне.",           Color3.fromRGB(200, 40, 110), Color3.fromRGB(110, 50, 210) },
}
-- shuffled bag: every ad is shown once before any repeats
local adBag = {}
local function nextAd()
    if #adBag == 0 then
        for i = 1, #ADS do adBag[i] = i end
        for i = #adBag, 2, -1 do
            local j = math.random(i)
            adBag[i], adBag[j] = adBag[j], adBag[i]
        end
    end
    return ADS[table.remove(adBag)]
end
-- opens a link in the real browser (executor dependent); copies it when that is not possible
local function openUrl(url)
    local ok = pcall(function() game:GetService("GuiService"):OpenBrowserWindow(url) end)
    if not ok and type(openurl) == "function" then ok = pcall(openurl, url) end
    if ok then
        notify(G("Opening: ", "Открываю: ") .. url)
    else
        if setclipboard then pcall(setclipboard, url) end
        notify(G("Could not open the browser. Link copied: ", "Не удалось открыть браузер. Ссылка скопирована: ") .. url)
    end
end

-- pill with a bilingual label
local function gpill(parent, en, ru, iconName, size, cb, primary)
    local P = pill(parent, nil, iconName, size, cb, primary)
    P.t = new("TextLabel", {
        Parent = P.b, LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = primary and C.black or C.text, Text = G(en, ru),
    })
    return P
end

local function closeGate(keepBlack)
    if GT.conn then GT.conn:Disconnect() GT.conn = nil end
    for _, c in ipairs(GT.conns or {}) do pcall(function() c:Disconnect() end) end
    GT.conns = {}
    if GT.reopen then GT.reopen.Visible = false end
    local r, g = GT.root, GT.grp
    GT.root, GT.grp, GT.ctl = nil, nil, nil
    if not r then return end
    tw2(g, 0.3, { GroupTransparency = 1 })
    if not keepBlack then tw2(r, 0.3, { BackgroundTransparency = 1 }) end
    task.delay(0.6, function() r:Destroy() end)
end

local function openGate(mode, message)
    -- already open (maybe hidden): just bring it back
    if GT.root and GT.root.Parent then
        GT.root.Visible = true
        if GT.reopen then GT.reopen.Visible = false end
        return
    end
    GT.conns = {}
    local root = new("Frame", { Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 300, Active = true })
    local grp = new("CanvasGroup", { Parent = root, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1 })
    GT.root, GT.grp = root, grp
    makeSnow(grp, 90, 5)
    tw2(grp, 0.35, { GroupTransparency = 0 })

    local GW, GH = 480, 440
    local box = new("Frame", { Parent = grp, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(GW, GH), BackgroundTransparency = 1 },
        { new("UIScale", { Scale = fitScale(GW, GH) }) })
    new("Frame", { Parent = box, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 16, 1, 16), BackgroundTransparency = 1 },
        { round(30), new("UIStroke", { Color = C.white, Transparency = 0.86, Thickness = 8 }) })
    local card = new("Frame", { Parent = box, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 6, 8), BorderSizePixel = 0, ClipsDescendants = true },
        { round(22), neonStroke(2, 50) })

    BR.addLogo(new("TextLabel", { Parent = card, Position = UDim2.fromOffset(22, 18), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = C.white, Text = "S",
        Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = Color3.new(0, 0, 0) }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) }))
    local title = txt(card, CFG.Name, 20, C.text, Enum.Font.GothamBold)
    title.Position, title.Size = UDim2.fromOffset(72, 16), UDim2.fromOffset(240, 24)
    local sub = txt(card, G("Key system · choose a service · keys last 1 / 5 / 12 hours", "Ключ-система · выбери сервис · ключи на 1 / 5 / 12 часов"), 12, C.sub)
    sub.Position, sub.Size = UDim2.fromOffset(72, 40), UDim2.fromOffset(300, 16)

    -- hide button: tucks the window away (the injector stays locked until a key is entered)
    local hideP = gpill(card, "Hide", "Скрыть", "down", UDim2.fromOffset(96, 32), function()
        if mode == "renew" then closeGate() return end
        root.Visible = false
        if GT.reopen then GT.reopen.Visible = true end
    end)
    hideP.b.AnchorPoint, hideP.b.Position = Vector2.new(1, 0), UDim2.new(1, -18, 0, 20)

    -- status line
    local status = txt(card, "", 12, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)
    status.Position, status.Size, status.TextWrapped = UDim2.fromOffset(22, 356), UDim2.fromOffset(436, 60), true
    status.TextYAlignment = Enum.TextYAlignment.Top
    local function setStatus(text, color) status.Text = text status.TextColor3 = color or C.sub end
    if message then setStatus(message, C.warn)
    else
        setStatus(mode == "renew"
            and G("Renew your key. You can keep using the script until the old one expires.", "Обнови ключ. Скрипт работает, пока не истёк старый.")
            or G("Pick a service to get a free key, or enter a key you already have.", "Выбери сервис, чтобы получить бесплатный ключ, или введи готовый."))
    end
    GT.ctl = { toExpired = function(msg)
        mode = "expired"
        root.Visible = true
        if GT.reopen then GT.reopen.Visible = false end
        setStatus(msg, C.warn)
    end }

    -- step header + progress
    local stepLbl = txt(card, "", 12, C.sub, Enum.Font.GothamMedium)
    stepLbl.Position, stepLbl.Size = UDim2.fromOffset(22, 70), UDim2.fromOffset(320, 18)
    local changeB = new("TextButton", { Parent = card, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 70), Size = UDim2.fromOffset(120, 18),
        BackgroundTransparency = 1, Text = G("Change method", "Сменить способ"), Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.sub,
        TextXAlignment = Enum.TextXAlignment.Right, AutoButtonColor = false, Visible = false })
    local barTrack = new("Frame", { Parent = card, Position = UDim2.fromOffset(22, 92), Size = UDim2.fromOffset(436, 4), BackgroundColor3 = Color3.fromRGB(26, 26, 30), BorderSizePixel = 0 }, { round(2) })
    local barFill = new("Frame", { Parent = barTrack, Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.white, BorderSizePixel = 0 }, { round(2) })

    local panel = new("Frame", { Parent = card, Position = UDim2.fromOffset(22, 108), Size = UDim2.fromOffset(436, 154), BackgroundTransparency = 1, ClipsDescendants = true })

    -- footer: ready key
    new("Frame", { Parent = card, Position = UDim2.fromOffset(22, 274), Size = UDim2.fromOffset(436, 1), BackgroundColor3 = Color3.fromRGB(34, 34, 38), BorderSizePixel = 0 })
    local fl = txt(card, G("Already have a key?", "Уже есть ключ?"), 12, C.sub)
    fl.Position, fl.Size = UDim2.fromOffset(22, 282), UDim2.fromOffset(300, 18)
    local keyIn = new("TextBox", { Parent = card, Position = UDim2.fromOffset(22, 304), Size = UDim2.fromOffset(318, 40), BackgroundColor3 = Color3.fromRGB(10, 10, 12),
        TextColor3 = C.white, PlaceholderColor3 = C.sub, PlaceholderText = "SM1-XXXXX-XXXXX-XXXXXXX", Font = Enum.Font.Code, TextSize = 15, Text = "",
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left },
        { round(12), stroke(C.line), new("UIPadding", { PaddingLeft = UDim.new(0, 12) }) })

    -- state
    local method, steps, si = nil, {}, 0
    local svcName = ""
    local newKey, newExp
    local cur, adUpd, adOv
    local mouseMoves = 0
    GT.conns[#GT.conns + 1] = UIS.InputChanged:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement then mouseMoves = mouseMoves + 1 end
    end)
    local function isTouchOnly() return UIS.TouchEnabled and not UIS.MouseEnabled end

    local nextStep, showSelect

    local function clearPanel()
        cur, adUpd = nil, nil
        if adOv then adOv:Destroy() adOv = nil end
        for _, ch in ipairs(panel:GetChildren()) do ch:Destroy() end
    end

    local function paintProgress()
        local st = steps[si]
        stepLbl.Text = svcName .. " · " .. G("step ", "шаг ") .. si .. "/" .. #steps .. " · " .. st.name
        tw2(barFill, 0.3, { Size = UDim2.fromScale((si - 1) / #steps, 1) })
    end

    ------------------------------------------------------------------
    -- fake ad overlay
    ------------------------------------------------------------------
    local function showAd(idx, total, secs, onClosed)
        local d = nextAd()
        local W = Color3.new(1, 1, 1)
        local ov = new("Frame", { Parent = card, Position = UDim2.fromOffset(22, 68), Size = UDim2.fromOffset(436, 196), BackgroundColor3 = W, BorderSizePixel = 0, ZIndex = 40, ClipsDescendants = true },
            { round(14), new("UIGradient", { Color = ColorSequence.new(d[4], d[5]), Rotation = 35 }) })
        adOv = ov
        new("TextLabel", { Parent = ov, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(34, 18), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4,
            Text = G("AD", "РЕКЛ"), Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = W, ZIndex = 41 }, { round(5) })
        local cnt = txt(ov, G("Sponsored · ", "Реклама · ") .. idx .. "/" .. total, 11, W) cnt.ZIndex = 41
        cnt.Position, cnt.Size = UDim2.fromOffset(54, 12), UDim2.fromOffset(200, 18)
        local nm = txt(ov, d[1], 32, W, Enum.Font.GothamBlack, Enum.TextXAlignment.Center) nm.ZIndex = 41
        nm.Position, nm.Size = UDim2.fromOffset(0, 58), UDim2.new(1, 0, 0, 40)
        local tg = txt(ov, G(d[2], d[3]), 14, Color3.fromRGB(240, 240, 248), Enum.Font.Gotham, Enum.TextXAlignment.Center) tg.ZIndex = 41
        tg.Position, tg.Size = UDim2.fromOffset(0, 102), UDim2.new(1, 0, 0, 20)
        if d[6] then
            local cta = new("TextButton", { Parent = ov, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 134), Size = UDim2.fromOffset(160, 30),
                BackgroundColor3 = W, AutoButtonColor = false, Text = G("Learn more  →", "Подробнее  →"), Font = Enum.Font.GothamBold, TextSize = 13,
                TextColor3 = Color3.new(0, 0, 0), ZIndex = 41 }, { round(15) })
            cta.MouseEnter:Connect(function() tween(cta, 0.1, { BackgroundColor3 = Color3.fromRGB(230, 230, 235) }) end)
            cta.MouseLeave:Connect(function() tween(cta, 0.1, { BackgroundColor3 = W }) end)
            cta.MouseButton1Click:Connect(function() openUrl(d[6]) end)
        end
        local track = new("Frame", { Parent = ov, Position = UDim2.fromOffset(16, 180), Size = UDim2.fromOffset(404, 4), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.6,
            BorderSizePixel = 0, ZIndex = 41 }, { round(2) })
        local fill = new("Frame", { Parent = track, Size = UDim2.fromScale(0, 1), BackgroundColor3 = W, BorderSizePixel = 0, ZIndex = 42 }, { round(2) })
        local closeB = new("TextButton", { Parent = ov, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(118, 26),
            BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, AutoButtonColor = false, Text = "", ZIndex = 41 }, { round(13) })
        local closeT = txt(closeB, "", 12, W, Enum.Font.GothamBold, Enum.TextXAlignment.Center) closeT.ZIndex = 42
        closeT.Size = UDim2.fromScale(1, 1)
        local left, ready = secs, false
        closeT.Text = G("Close in ", "Закрыть через ") .. secs
        closeB.MouseButton1Click:Connect(function()
            if not ready then return end
            adUpd = nil
            adOv = nil
            ov:Destroy()
            onClosed()
        end)
        adUpd = function(dt)
            if ready then return end
            left = left - dt
            if left <= 0 then
                ready = true
                fill.Size = UDim2.fromScale(1, 1)
                closeT.Text = G("Close ad ✕", "Закрыть ✕")
            else
                fill.Size = UDim2.fromScale(1 - left / secs, 1)
                closeT.Text = G("Close in ", "Закрыть через ") .. math.ceil(left)
            end
        end
    end

    ------------------------------------------------------------------
    -- step builders (each returns { update = fn(dt) } or {})
    ------------------------------------------------------------------
    local function stepWait(st)
        local count = txt(panel, tostring(st.secs), 46, C.white, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
        count.Size = UDim2.new(1, 0, 0, 54)
        local track = new("Frame", { Parent = panel, Position = UDim2.fromOffset(0, 62), Size = UDim2.fromOffset(436, 6), BackgroundColor3 = Color3.fromRGB(26, 26, 30), BorderSizePixel = 0 }, { round(3) })
        local fill = new("Frame", { Parent = track, Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.white, BorderSizePixel = 0 }, { round(3) })
        local hint = txt(panel, G("Press Start. The timer can't be skipped.", "Нажми «Старт». Таймер нельзя пропустить."), 12, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)
        hint.Position, hint.Size = UDim2.fromOffset(0, 76), UDim2.new(1, 0, 0, 16)
        local started, left = false, st.secs
        local startP
        startP = gpill(panel, "Start", "Старт", "play", UDim2.fromOffset(150, 30), function()
            if started then return end
            started = true
            startP.b.Visible = false
            hint.Text = G("Waiting... stay on this screen.", "Ожидание... оставайся на этом экране.")
        end, true)
        startP.b.AnchorPoint, startP.b.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 96)
        return { update = function(dt)
            if not started then return end
            left = left - dt
            if left <= 0 then
                count.Text = "0"
                fill.Size = UDim2.fromScale(1, 1)
                nextStep()
            else
                count.Text = tostring(math.ceil(left))
                fill.Size = UDim2.fromScale(1 - left / st.secs, 1)
            end
        end }
    end

    local function stepAds(st)
        local N = st.n
        local done, doneCount, busy, waiting, waitIdx = {}, 0, false, 0, 0
        local head = txt(panel, "", 13, C.text, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
        head.Size = UDim2.new(1, 0, 0, 18)
        local row = new("Frame", { Parent = panel, Position = UDim2.fromOffset(0, 28), Size = UDim2.fromOffset(436, 40), BackgroundTransparency = 1 }, { hlist(8, Enum.HorizontalAlignment.Center) })
        local info = txt(panel, "", 12, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)
        info.Position, info.Size, info.TextWrapped = UDim2.fromOffset(0, 80), UDim2.new(1, 0, 0, 36), true
        info.TextYAlignment = Enum.TextYAlignment.Top
        local wTrack = new("Frame", { Parent = panel, Position = UDim2.fromOffset(0, 126), Size = UDim2.fromOffset(436, 5), BackgroundColor3 = Color3.fromRGB(26, 26, 30), BorderSizePixel = 0, Visible = false }, { round(3) })
        local wFill = new("Frame", { Parent = wTrack, Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.white, BorderSizePixel = 0 }, { round(3) })
        local slots = {}
        local function refresh()
            head.Text = G("Ads watched: ", "Просмотрено реклам: ") .. doneCount .. "/" .. N
            for i, s in ipairs(slots) do
                local d = done[i]
                s.t.Text = (d and "✓ " or "") .. (N > 4 and G("Ad ", "Р ") or G("Ad ", "Реклама ")) .. i
                s.b.BackgroundColor3 = d and C.white or C.item
                s.t.TextColor3 = d and C.black or C.text
            end
        end
        local function idleInfo()
            if st.after > 0 then
                info.Text = G("Choose an ad and watch it to the end, close it, then wait " .. st.after .. "s.",
                    "Выбери рекламу и досмотри до конца, закрой её и подожди " .. st.after .. " с.")
            else
                info.Text = G("Choose an ad and watch it for " .. st.view .. "s, then close it.",
                    "Выбери рекламу и смотри " .. st.view .. " с, потом закрой её.")
            end
        end
        local function finishOne(i)
            done[i] = true
            doneCount = doneCount + 1
            refresh()
            if doneCount >= N then nextStep() return end
            idleInfo()
        end
        local w = math.min(120, math.floor((436 - (N - 1) * 8) / N))
        for i = 1, N do
            local b = new("TextButton", { Parent = row, LayoutOrder = i, Size = UDim2.fromOffset(w, 38), BackgroundColor3 = C.item, AutoButtonColor = false, Text = "" }, { round(10), stroke(C.line) })
            local t = txt(b, "", 13, C.text, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
            t.Size = UDim2.fromScale(1, 1)
            slots[i] = { b = b, t = t }
            b.MouseButton1Click:Connect(function()
                if busy or done[i] or waiting > 0 then return end
                busy = true
                showAd(i, N, st.view, function()
                    busy = false
                    if st.after > 0 then
                        waiting, waitIdx = st.after, i
                        wTrack.Visible = true
                        wFill.Size = UDim2.fromScale(0, 1)
                    else
                        finishOne(i)
                    end
                end)
            end)
        end
        refresh()
        idleInfo()
        return { update = function(dt)
            if waiting > 0 then
                waiting = waiting - dt
                if waiting <= 0 then
                    waiting = 0
                    wTrack.Visible = false
                    finishOne(waitIdx)
                else
                    info.Text = G("Ad counted. Wait ", "Реклама засчитана. Подожди ") .. math.ceil(waiting) .. G("s before the next step.", " с до следующего шага.")
                    wFill.Size = UDim2.fromScale(1 - waiting / st.after, 1)
                end
            end
        end }
    end

    local function stepScan(st)
        local info = txt(panel, G("Press Verify: the script scans your session and prepares the injector data.", "Нажми «Проверить»: скрипт проверит сессию и подготовит данные инжектора."),
            12, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)
        info.Position, info.Size, info.TextWrapped = UDim2.fromOffset(0, 4), UDim2.new(1, 0, 0, 34), true
        local count = txt(panel, "", 38, C.white, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
        count.Position, count.Size = UDim2.fromOffset(0, 40), UDim2.new(1, 0, 0, 44)
        local track = new("Frame", { Parent = panel, Position = UDim2.fromOffset(0, 90), Size = UDim2.fromOffset(436, 6), BackgroundColor3 = Color3.fromRGB(26, 26, 30), BorderSizePixel = 0 }, { round(3) })
        local fill = new("Frame", { Parent = track, Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.white, BorderSizePixel = 0 }, { round(3) })
        local line = txt(panel, "", 12, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)
        line.Position, line.Size = UDim2.fromOffset(0, 102), UDim2.new(1, 0, 0, 16)
        local started, left, compOk, compMsg = false, st.secs, nil, ""
        local startP
        startP = gpill(panel, "Verify", "Проверить", "check", UDim2.fromOffset(150, 30), function()
            if started then return end
            started = true
            startP.b.Visible = false
            info.Text = G("Stay on this screen while the scan runs.", "Оставайся на этом экране, пока идёт проверка.")
            count.Text = tostring(st.secs)
            task.spawn(function()
                compOk = UPD.ensure(function(_, msg) if msg then compMsg = msg end end)
            end)
        end, true)
        startP.b.AnchorPoint, startP.b.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 112)
        return { update = function(dt)
            if not started then return end
            left = left - dt
            local frac = math.clamp(1 - left / st.secs, 0, 1)
            fill.Size = UDim2.fromScale(frac, 1)
            count.Text = tostring(math.max(0, math.ceil(left)))
            if frac < 0.35 then line.Text = G("Scanning environment...", "Сканирование окружения...")
            elseif frac < 0.85 then line.Text = (compMsg ~= "" and compMsg) or G("Preparing injector data...", "Подготовка данных инжектора...")
            else line.Text = G("Finalizing...", "Завершение...") end
            if left <= 0 then
                if compOk == nil and left > -25 then
                    line.Text = G("Downloading injector data...", "Загрузка данных инжектора...")
                    return
                end
                if not isTouchOnly() and mouseMoves < 2 then
                    started, left = false, st.secs
                    startP.b.Visible = true
                    fill.Size = UDim2.fromScale(0, 1)
                    count.Text = ""
                    setStatus(G("Scan failed: no real input detected. Try again.", "Проверка не пройдена: не найден реальный ввод. Попробуй ещё раз."), C.err)
                    return
                end
                if compOk == false then
                    setStatus(G("Injector data will be downloaded on first start (server unreachable).", "Данные инжектора скачаются при первом запуске (сервер недоступен)."), C.warn)
                end
                nextStep()
            end
        end }
    end

    local function stepContinue()
        local t1 = txt(panel, G("Everything is ready ✓", "Всё готово ✓"), 18, C.white, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        t1.Position, t1.Size = UDim2.fromOffset(0, 24), UDim2.new(1, 0, 0, 26)
        local t2 = txt(panel, G("Scan finished and injector data is prepared. Press Continue for the last check.", "Проверка завершена, данные инжектора готовы. Нажми «Продолжить» для последней проверки."),
            12, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)
        t2.Position, t2.Size, t2.TextWrapped = UDim2.fromOffset(0, 56), UDim2.new(1, 0, 0, 34), true
        local p = gpill(panel, "Continue", "Продолжить", "right", UDim2.fromOffset(170, 34), function() nextStep() end, true)
        p.b.AnchorPoint, p.b.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 100)
        return {}
    end

    local function stepBot()
        local cardB = new("Frame", { Parent = panel, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(320, 66),
            BackgroundColor3 = Color3.fromRGB(12, 12, 15) }, { round(12), stroke(C.line) })
        local cb = new("TextButton", { Parent = cardB, Position = UDim2.fromOffset(18, 18), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.fromRGB(6, 6, 8),
            AutoButtonColor = false, Text = "", Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = C.white }, { round(6), new("UIStroke", { Color = C.sub, Thickness = 2 }) })
        local cbStroke = cb:FindFirstChildOfClass("UIStroke")
        local lbl = txt(cardB, G("I'm not a robot", "Я не робот"), 15, C.text, Enum.Font.GothamMedium)
        lbl.Position, lbl.Size = UDim2.fromOffset(62, 0), UDim2.new(1, -72, 1, 0)
        local hint = txt(panel, G("Click the empty square. The script checks that you are a real person.", "Нажми на пустой квадрат. Скрипт проверит, что ты человек."),
            12, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)
        hint.Position, hint.Size, hint.TextWrapped = UDim2.fromOffset(0, 96), UDim2.new(1, 0, 0, 34), true

        local shownAt, busy, hoverSeen, realInputAt, moves0 = os.clock(), false, false, 0, mouseMoves
        cb.MouseEnter:Connect(function() hoverSeen = true cbStroke.Color = C.white end)
        cb.MouseLeave:Connect(function() cbStroke.Color = C.sub end)
        cb.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then realInputAt = os.clock() end
        end)
        cb.MouseButton1Click:Connect(function()
            if busy then return end
            busy = true
            local clickT = os.clock()
            task.spawn(function()
                lbl.Text = G("Analyzing...", "Анализ...")
                for k = 1, 6 do
                    cb.Text = ({ "·", "··", "···" })[(k - 1) % 3 + 1]
                    task.wait(0.3)
                end
                if not (cb and cb.Parent) then return end
                local touch = isTouchOnly()
                local why
                if clickT - shownAt < 0.8 then why = G("Too fast.", "Слишком быстро.")
                elseif realInputAt == 0 or clickT - realInputAt > 1.5 then why = G("No real click detected.", "Реальный клик не найден.")
                elseif not touch and not hoverSeen then why = G("No pointer movement detected.", "Не видно движения курсора.")
                elseif not touch and (mouseMoves - moves0) < 3 then why = G("No pointer movement detected.", "Не видно движения курсора.") end
                if not why then
                    cb.Text = "✓"
                    cbStroke.Color = C.ok
                    lbl.Text = G("Verified", "Проверено")
                    setStatus(G("Human check passed.", "Проверка на бота пройдена."), C.ok)
                    task.wait(0.6)
                    if cb.Parent then nextStep() end
                else
                    cb.Text = ""
                    cbStroke.Color = C.err
                    lbl.Text = G("I'm not a robot", "Я не робот")
                    setStatus(G("Looks like a bot: ", "Похоже на бота: ") .. why .. G(" Try again.", " Попробуй ещё раз."), C.err)
                    task.wait(0.4)
                    if cb.Parent then cbStroke.Color = C.sub end
                    shownAt, moves0, realInputAt, hoverSeen = os.clock(), mouseMoves, 0, false
                    busy = false
                end
            end)
        end)
        return {}
    end

    ------------------------------------------------------------------
    -- apply / key panel
    ------------------------------------------------------------------
    local function apply(key, exp, tier)
        if tier then DB.planTier = tier end
        activateKey(key, exp)
        setStatus(G("Key accepted.", "Ключ принят."), C.ok)
        local m = mode
        if m == "first" then
            closeGate(true)
            gateEvent:Fire()
        else
            closeGate()
            if m == "expired" then setOpen(true) end
            notify(G("Key activated · valid for ", "Ключ активирован · действует ") .. keyLeftText())
        end
    end

    local function verifyTyped()
        local ok, a, formatted, tier = validateKey(keyIn.Text)
        if ok then apply(formatted, a, tier) return end
        local msgs = {
            expired = G("This key has expired.", "Срок действия этого ключа истёк."),
            clock = G("This key looks issued in the future. Check your clock.", "Ключ выдан «в будущем». Проверь время."),
        }
        setStatus(msgs[a] or G("That key isn't valid.", "Этот ключ недействителен."), C.err)
    end
    local verifyP = gpill(card, "Verify", "Проверить", "check", UDim2.fromOffset(104, 40), verifyTyped, true)
    verifyP.b.Position = UDim2.fromOffset(354, 304)
    bind(keyIn.FocusLost, function(enter) if enter then verifyTyped() end end)

    local function finishKey()
        clearPanel()
        changeB.Visible = false
        stepLbl.Text = G("All steps done ✓", "Все шаги выполнены ✓")
        tw2(barFill, 0.3, { Size = UDim2.fromScale(1, 1) })
        newKey, newExp = makeKey(method)
        local hrs = CFG.Key["M" .. tostring(method)].Hours
        setStatus(G("Verified. Your key is ready · valid for ", "Проверка пройдена. Ключ готов · действует ") .. hrs .. G(" h.", " ч."), C.ok)
        local kl = txt(panel, G("Verified ✓  Your key:", "Проверено ✓  Твой ключ:"), 12, C.sub, Enum.Font.Gotham, Enum.TextXAlignment.Center)
        kl.Size = UDim2.new(1, 0, 0, 16)
        local keyBox = new("TextBox", { Parent = panel, Position = UDim2.fromOffset(0, 28), Size = UDim2.fromOffset(436, 42), BackgroundColor3 = Color3.fromRGB(10, 10, 12),
            TextColor3 = C.white, Font = Enum.Font.Code, TextSize = 17, Text = newKey or "", ClearTextOnFocus = false, TextEditable = false },
            { round(12), new("UIStroke", { Color = C.white, Thickness = 1.2, Transparency = 0.4 }) })
        local brow = new("Frame", { Parent = panel, Position = UDim2.fromOffset(0, 84), Size = UDim2.fromOffset(436, 36), BackgroundTransparency = 1 }, { hlist(10, Enum.HorizontalAlignment.Center) })
        local copyP = gpill(brow, "Copy", "Копировать", "copy", UDim2.fromOffset(130, 34), function()
            if newKey and setclipboard then setclipboard(newKey) notify(G("Key copied", "Ключ скопирован")) else notify(G("Select the key and copy it manually", "Выдели ключ и скопируй вручную")) end
        end)
        copyP.b.LayoutOrder = 1
        local actP = gpill(brow, "Activate", "Активировать", "check", UDim2.fromOffset(150, 34), function()
            if not newKey then return end
            local ok, a, formatted, tier = validateKey(newKey)
            if ok then apply(formatted, a, tier) else setStatus(G("Could not activate. Start again.", "Не удалось активировать. Начни заново."), C.err) end
        end, true)
        actP.b.LayoutOrder = 2
        if newKey and setclipboard then pcall(setclipboard, newKey) end
    end

    ------------------------------------------------------------------
    -- flow
    ------------------------------------------------------------------
    local builders = { wait = stepWait, ads = stepAds, scan = stepScan, continue = stepContinue, bot = stepBot }
    local function runStep()
        clearPanel()
        paintProgress()
        cur = builders[steps[si].t](steps[si])
    end
    function nextStep()
        si = si + 1
        if si > #steps then finishKey() else runStep() end
    end

    local function startMethod(m)
        method = m
        local K = CFG.Key
        local svc = K["M" .. m]
        svcName = svc.Name
        local function T_(en, ru) return G(en, ru) end
        if m == 1 then
            steps = {
                { t = "ads", n = svc.Ads, view = svc.AdSeconds, after = 0, name = T_("Ads", "Реклама") },
                { t = "scan", secs = svc.ScanSeconds, name = T_("Verify", "Проверка") },
                { t = "continue", name = T_("Continue", "Продолжить") },
                { t = "bot", name = T_("Robot check", "Проверка на бота") },
            }
        elseif m == 2 then
            steps = {
                { t = "wait", secs = K.WaitSeconds, name = T_("Wait", "Ожидание") },
                { t = "ads", n = math.random(svc.AdsMin, svc.AdsMax), view = svc.AdSeconds, after = svc.AfterAdWait, name = T_("Ads", "Реклама") },
                { t = "bot", name = T_("Robot check", "Проверка на бота") },
                { t = "ads", n = math.random(svc.AdsMin, svc.AdsMax), view = svc.AdSeconds, after = svc.AfterAdWait, name = T_("Ads", "Реклама") },
                { t = "bot", name = T_("Robot check", "Проверка на бота") },
            }
        else
            -- GoldPass: 5-9 ads split over 4 stages, a robot check after every stage
            local stages = svc.Stages
            local total = math.max(stages, math.random(svc.AdsMin, svc.AdsMax))
            local counts = {}
            for i = 1, stages do counts[i] = 1 end
            for _ = 1, total - stages do
                local i = math.random(stages)
                counts[i] = counts[i] + 1
            end
            steps = {}
            for i = 1, stages do
                steps[#steps + 1] = { t = "ads", n = counts[i], view = svc.AdSeconds, after = svc.AfterAdWait, name = T_("Stage ", "Этап ") .. i .. T_(" · ads", " · реклама") }
                steps[#steps + 1] = { t = "bot", name = T_("Stage ", "Этап ") .. i .. T_(" · robot check", " · проверка") }
            end
        end
        si = 0
        changeB.Visible = true
        setStatus(G("Complete every step to get your key.", "Пройди все шаги, чтобы получить ключ."))
        nextStep()
    end

    function showSelect()
        method, si, svcName = nil, 0, ""
        clearPanel()
        changeB.Visible = false
        stepLbl.Text = G("Choose a service", "Выбери сервис")
        tw2(barFill, 0.2, { Size = UDim2.fromScale(0, 1) })
        local K = CFG.Key
        local defs = {
            { 1, K.M1.Name, G("Key: 1 hour", "Ключ: 1 час"),
              G("2 ads · 30s each\nVerify · 15s\nRobot check", "2 рекламы по 30 с\nПроверка 15 с\nПроверка на бота"), "bolt" },
            { 2, K.M2.Name, G("Key: 5 hours", "Ключ: 5 часов"),
              G("Wait 100s\nAds 1–5 · 70s each\n2 robot checks", "Ожидание 100 с\nРеклама 1–5 · по 70 с\n2 проверки на бота"), "list" },
            { 3, K.M3.Name, G("Key: 12 hours", "Ключ: 12 часов"),
              G("5–9 ads · 4 stages\nRobot check after\neach stage", "5–9 реклам · 4 этапа\nПроверка на бота\nпосле каждого"), "star" },
        }
        for i, d in ipairs(defs) do
            local b = new("TextButton", { Parent = panel, Position = UDim2.fromOffset((i - 1) * 148, 4), Size = UDim2.fromOffset(140, 146), BackgroundColor3 = Color3.fromRGB(12, 12, 15),
                AutoButtonColor = false, Text = "" }, { round(14), stroke(C.line) })
            local ic = icon(b, d[5], 14, C.white)
            ic.Position = UDim2.fromOffset(10, 11)
            local t = txt(b, d[2], 14, C.text, Enum.Font.GothamBold)
            t.Position, t.Size = UDim2.fromOffset(30, 8), UDim2.new(1, -36, 0, 22)
            local badge = new("Frame", { Parent = b, Position = UDim2.fromOffset(10, 36), Size = UDim2.fromOffset(118, 20), BackgroundColor3 = C.white, BorderSizePixel = 0 }, { round(10) })
            local bt = txt(badge, d[3], 11, Color3.new(0, 0, 0), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
            bt.Size = UDim2.fromScale(1, 1)
            local ds = txt(b, d[4], 11, C.sub)
            ds.Position, ds.Size, ds.TextWrapped = UDim2.fromOffset(10, 62), UDim2.new(1, -16, 0, 54), true
            ds.TextYAlignment = Enum.TextYAlignment.Top
            local go = txt(b, G("Select  →", "Выбрать  →"), 12, C.white, Enum.Font.GothamBold)
            go.Position, go.Size = UDim2.fromOffset(10, 122), UDim2.fromOffset(120, 18)
            b.MouseEnter:Connect(function() tw2(b, 0.1, { BackgroundColor3 = Color3.fromRGB(20, 20, 24) }) end)
            b.MouseLeave:Connect(function() tw2(b, 0.1, { BackgroundColor3 = Color3.fromRGB(12, 12, 15) }) end)
            b.MouseButton1Click:Connect(function() startMethod(d[1]) end)
        end
    end
    changeB.MouseButton1Click:Connect(function() showSelect() end)

    -- timers only run while the window is visible (hidden = paused)
    GT.conn = RunService.Heartbeat:Connect(function(dt)
        if not root.Visible then return end
        dt = math.min(dt, 0.25)
        if adUpd then adUpd(dt) end
        if cur and cur.update then cur.update(dt) end
    end)
    showSelect()
end

local function lockApp(reason)
    unlocked = false
    KEY.value = nil
    DB.key = nil
    saveDB()
    setOpen(false)
    if topBtn then topBtn.Visible = false end
    if GT.chip then GT.chip.Visible = false end
    if GT.root and GT.ctl then GT.ctl.toExpired(reason) else openGate("expired", reason) end
end

local function expiryPopup()
    if GT.popup and GT.popup.Parent then return end
    local dim = new("TextButton", { Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
        Text = "", AutoButtonColor = false, ZIndex = 250 })
    GT.popup = dim
    tw2(dim, 0.2, { BackgroundTransparency = 0.45 })
    local card = new("Frame", { Parent = dim, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(400, 200),
        BackgroundColor3 = Color3.fromRGB(6, 6, 8), BorderSizePixel = 0 }, { round(18), neonStroke(2, 50), new("UIScale", { Scale = fitScale(400, 200) }) })
    local t = txt(card, G("Your key is about to expire", "Ключ скоро истечёт"), 18, C.text, Enum.Font.GothamBold)
    t.Position, t.Size = UDim2.fromOffset(22, 18), UDim2.new(1, -44, 0, 24)
    local body = txt(card, "", 13, C.sub)
    body.Position, body.Size, body.TextWrapped = UDim2.fromOffset(22, 52), UDim2.new(1, -44, 0, 60), true
    body.TextYAlignment = Enum.TextYAlignment.Top
    local function close() if dim.Parent then tw2(dim, 0.15, { BackgroundTransparency = 1 }) task.delay(0.2, function() dim:Destroy() end) end end
    local row = new("Frame", { Parent = card, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, -44, 0, 40), BackgroundTransparency = 1 },
        { hlist(10, Enum.HorizontalAlignment.Center) })
    local cont = pill(row, "Continue", "play", UDim2.fromOffset(170, 40), close)
    cont.b.LayoutOrder = 1
    local renew = pill(row, "Renew key", "refresh", UDim2.fromOffset(170, 40), function() close() openGate("renew") end, true)
    renew.b.LayoutOrder = 2
    task.spawn(function()
        while dim.Parent and alive do
            local left = KEY.expires - nowT()
            body.Text = G("Time left: ", "Осталось: ") .. fmtDur(left) .. G(
                ".\nYou can keep working until it ends, or renew the key now.",
                ".\nМожно продолжить работу до конца или обновить ключ сейчас.")
            task.wait(1)
        end
    end)
end

-- key card on the Account page
local ok_blk30, err_blk30 = pcall(function()
    local pg = pages.Account
    local card = new("Frame", { Parent = pg, Position = UDim2.fromOffset(0, 238), Size = UDim2.new(1, 0, 0, 84), BackgroundColor3 = C.panel }, { round(14), stroke() })
    local kt = txt(card, "KEY", 11, C.sub, Enum.Font.GothamBold)
    kt.Position, kt.Size = UDim2.fromOffset(14, 10), UDim2.fromOffset(60, 14)
    GT.keyLbl = txt(card, "", 14, C.text, Enum.Font.Code)
    GT.keyLbl.Position, GT.keyLbl.Size = UDim2.fromOffset(14, 28), UDim2.new(1, -170, 0, 20)
    GT.leftLbl = txt(card, "", 12, C.sub)
    GT.leftLbl.Position, GT.leftLbl.Size = UDim2.fromOffset(14, 54), UDim2.new(1, -170, 0, 18)
    local r = pill(card, "Renew key", "refresh", UDim2.fromOffset(130, 30), function() openGate("renew") end, true)
    r.b.AnchorPoint, r.b.Position = Vector2.new(1, 0), UDim2.new(1, -10, 0, 9)
    local f = pill(card, "Forget key", "trash", UDim2.fromOffset(130, 30), function()
        lockApp(G("Key removed. Get or enter a new key.", "Ключ удалён. Получи или введи новый."))
    end)
    f.b.AnchorPoint, f.b.Position = Vector2.new(1, 1), UDim2.new(1, -10, 1, -9)
end) if not ok_blk30 then warn("[blk30] " .. tostring(err_blk30)) end

-- chip shown during the last minutes
GT.chip = new("TextButton", { Parent = gui, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 52), Size = UDim2.fromOffset(118, 30),
    BackgroundColor3 = Color3.fromRGB(6, 6, 8), Text = "", AutoButtonColor = false, Visible = false, ZIndex = 120 },
    { new("UICorner", { CornerRadius = UDim.new(0, 15) }), neonStroke(1.5, 60) })
GT.chipLbl = txt(GT.chip, "", 12, C.white, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
GT.chipLbl.Size = UDim2.fromScale(1, 1)
bind(GT.chip.MouseButton1Click, expiryPopup)

-- small button that brings the key window back after "Hide"
GT.reopen = new("TextButton", { Parent = gui, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -12), Size = UDim2.fromOffset(132, 34),
    BackgroundColor3 = Color3.fromRGB(6, 6, 8), Text = "", AutoButtonColor = false, Visible = false, ZIndex = 120 },
    { new("UICorner", { CornerRadius = UDim.new(0, 17) }), neonStroke(1.5, 60) })
local ok_blk31, err_blk31 = pcall(function()
    local t = txt(GT.reopen, G("🔑 Key system", "🔑 Ключ-система"), 12, C.white, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
    t.Size = UDim2.fromScale(1, 1)
end) if not ok_blk31 then warn("[blk31] " .. tostring(err_blk31)) end
bind(GT.reopen.MouseButton1Click, function()
    if GT.root and GT.root.Parent then GT.root.Visible = true GT.reopen.Visible = false end
end)

-- session (editor tabs, last page) ------------------------------------
local function restoreSession()
    if type(DB.tabs) == "table" and #DB.tabs > 0 then
        for i = #tabs, 1, -1 do table.remove(tabs, i) end
        for _, t in ipairs(DB.tabs) do
            if type(t) == "table" and type(t.src) == "string" then
                tabs[#tabs + 1] = { name = tostring(t.name or "Script"), src = t.src, hist = { t.src }, hi = 1 }
            end
        end
        if #tabs == 0 then newTab("") else
            tabCounter = #tabs
            activeTab = math.clamp(tonumber(DB.activeTab) or 1, 1, #tabs)
        end
        loadTab()
    end
end
local function saveSession()
    local list = {}
    for i, t in ipairs(tabs) do
        if i <= 20 then list[i] = { name = t.name, src = string.sub(t.src, 1, 60000) } end
    end
    DB.tabs, DB.activeTab = list, activeTab
    saveDB()
end

-- monitor: expiry countdown, warnings, autosave --------------------
task.spawn(function()
    local warned = {}
    local tick = 0
    while alive do
        task.wait(1)
        tick = tick + 1
        if unlocked and KEY.value then
            local rem = KEY.expires - nowT()
            if rem <= 0 then
                lockApp(G("Your key has expired. Get a new one below.", "Срок действия ключа истёк. Получи новый ниже."))
            else
                if rem <= CFG.Key.WarnSeconds then
                    GT.chip.Visible = true
                    GT.chipLbl.Text = "KEY  " .. fmtDur(rem)
                    if not warned[KEY.value] then
                        warned[KEY.value] = true
                        if open then expiryPopup() else notify(G("Your key expires in ", "Ключ истекает через ") .. fmtDur(rem)) end
                    end
                else
                    GT.chip.Visible = false
                end
                if tick % 5 == 0 then
                    if refreshHome then refreshHome() end
                    if GT.keyLbl then
                        GT.keyLbl.Text = S.streamer and "SM1-•••••-•••••-•••••••" or (string.sub(KEY.value, 1, 9) .. "-•••••-•••••••")
                        GT.leftLbl.Text = G("Time left: ", "Осталось: ") .. fmtDur(rem)
                    end
                end
            end
        end
        if tick % 20 == 0 and unlocked then pcall(saveSession) end
    end
end)

----------------------------------------------------------------------
-- HUD watermark bar (time / FPS / ping / players, always on screen)
----------------------------------------------------------------------
-- (hudBar is forward-declared at the top of the file)
local ok_blk32, err_blk32 = pcall(function()
    local bar = new("Frame", {
        Parent = gui, AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(8, 46),
        Size = UDim2.fromOffset(372, 40), BackgroundColor3 = C.bg, Visible = S.hud, ZIndex = 80, ClipsDescendants = true, Active = true,
    }, { round(20), neonStroke(TH.neonThick, TH.neonSpeed, true) })
    hudBar = bar
    if not DB.hudLeft then DB.hudLeft = true DB.hudPos = nil end -- one-time reset: HUD now starts top-left
    if type(DB.hudPos) == "table" and DB.hudPos.x and DB.hudPos.y then
        bar.AnchorPoint = Vector2.new(0, 0)
        bar.Position = UDim2.fromOffset(DB.hudPos.x, DB.hudPos.y)
    end
    do
        local dragging, startMouse, startPos
        local function isPointer(i) return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch end
        bind(bar.InputBegan, function(i)
            if isPointer(i) then
                dragging, startMouse, startPos = true, Vector2.new(i.Position.X, i.Position.Y), bar.Position
                if bar.AnchorPoint ~= Vector2.new(0, 0) then
                    bar.AnchorPoint = Vector2.new(0, 0)
                    bar.Position = UDim2.fromOffset(bar.AbsolutePosition.X, bar.AbsolutePosition.Y)
                    startPos = bar.Position
                end
            end
        end)
        bind(UIS.InputChanged, function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                local d = Vector2.new(i.Position.X, i.Position.Y) - startMouse
                bar.Position = UDim2.fromOffset(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
            end
        end)
        bind(UIS.InputEnded, function(i)
            if dragging and isPointer(i) then
                dragging = false
                DB.hudPos = { x = bar.Position.X.Offset, y = bar.Position.Y.Offset }
                saveDB()
            end
        end)
    end
    local snow = makeSnow(bar, 10, 3, bar)
    snow.always = false

    local function stat(xs, w, glyph)
        local wrap = new("Frame", { Parent = bar, Position = UDim2.new(xs, 0, 0, 0), Size = UDim2.new(w, 0, 1, 0), BackgroundTransparency = 1 },
            { hlist(5, Enum.HorizontalAlignment.Center) })
        local ic = icon(wrap, glyph, 13, C.sub) ic.LayoutOrder = 1
        local v = txt(wrap, "-", 12, C.text, Enum.Font.GothamBold) v.LayoutOrder = 2
        v.Size = UDim2.fromOffset(0, 16) v.AutomaticSize = Enum.AutomaticSize.X
        return v
    end
    local vTime = stat(0.0, 0.3, "info")
    local vFps = stat(0.3, 0.22, "bolt")
    local vPing = stat(0.52, 0.24, "globe")
    local vPlayers = stat(0.76, 0.24, "user")

    local hudFrames, hudAcc, hudFps = 0, 0, 60
    bind(RunService.RenderStepped, function(dt)
        if not S.hud then return end
        hudFrames = hudFrames + 1
        hudAcc = hudAcc + dt
        if hudAcc >= 0.5 then
            hudFps = math.floor(hudFrames / hudAcc + 0.5)
            hudFrames, hudAcc = 0, 0
        end
    end)
    task.spawn(function()
        while alive do
            bar.Visible = S.hud
            snow.always = S.hud and S.hudSnow
            if S.hud then
                vTime.Text = os.date(S.hud24h and "%H:%M:%S" or "%I:%M:%S %p")
                vFps.Text = tostring(hudFps)
                local okp, ping = pcall(function() return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
                vPing.Text = okp and (ping .. "ms") or "-"
                vPlayers.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
            end
            task.wait(0.5)
        end
    end)
end) if not ok_blk32 then warn("[blk32] " .. tostring(err_blk32)) end

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------
genv.__SM1LER = function()
    alive = false
    pcall(saveSession)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() blur:Destroy() end)
    pcall(function() gui:Destroy() end)
end

task.spawn(function()
    local t0 = os.clock()
    local function step(msg, p, wait)
        splash.status(msg)
        splash.progress(p)
        if os.clock() - t0 < CFG.MaxLoad - 1.8 then task.wait(wait) end
    end
    step(G("Loading settings", "Загрузка настроек"), 0.3, 0.3)
    pcall(restoreSession)
    task.spawn(function() pcall(CT.autoScan, true) end)
    task.spawn(function()
        while alive do
            pcall(STAT.refresh)
            task.wait(90)
        end
    end)
    pcall(LY.apply, false)
    -- auto-update: starts a newer saved/downloaded build and stops this one
    do
        local okU, launched = pcall(UPD.boot, function(msg, p) splash.status(msg) splash.progress(p) end)
        if okU and launched then alive = false return end
    end
    for _, n in ipairs(FX.neon) do n.g.Enabled = S.neon ~= false end
    if TH.mode == "image" and TH.image ~= "" then task.spawn(function() resolveImage(TH.image) applyTheme() end) end
    pcall(applyTheme)
    if S.streamer then pcall(applyStreamer, true) end

    step(G("Checking key", "Проверка ключа"), 0.6, 0.3)
    local valid, exp, reason = false, nil, nil
    if type(DB.key) == "string" then
        local ok, a, formatted, tier = validateKey(DB.key)
        if ok then valid, exp, DB.key = true, a, formatted
            if tier then DB.planTier = tier end
        else
            DB.key = nil
            if a == "expired" then reason = G("Your key has expired. Get a new one below.", "Срок действия ключа истёк. Получи новый ниже.") end
        end
    end

    step(G("Preparing interface", "Подготовка интерфейса"), 0.9, 0.25)
    applyLang()
    applyPosition()
    if genv.__SM1LER_applyFps and S.fps ~= "60" then genv.__SM1LER_applyFps() end
    showPage(pages[S.lastPage] and S.lastPage or "Home")
    splash.status(G("Ready", "Готово"))
    splash.progress(1)
    task.wait(0.2)

    -- one-time injector setup: downloads the data once, never again
    local function runSetup(b)
        if DB.setupDone then return end
        b.status(G("First launch: preparing injector", "Первый запуск: подготовка инжектора"))
        b.progress(0.08)
        local ok = UPD.ensure(function(p, msg)
            b.progress(0.1 + 0.6 * p)
            if msg then b.status(msg) end
        end)
        local fin = { G("Unpacking components", "Распаковка компонентов"), G("Verifying integrity", "Проверка целостности"), G("Finalizing", "Завершение") }
        for i, m in ipairs(fin) do
            b.status(m)
            b.progress(0.7 + 0.1 * i)
            task.wait(0.45)
        end
        if ok then DB.setupDone, DB.setupVersion = true, CFG.Version saveDB() end
        b.progress(1)
        task.wait(0.25)
    end

    local who = G("Welcome, ", "Добро пожаловать, ") .. dispName()
    if valid then
        activateKey(DB.key, exp)
        runSetup(splash)
        splash.play(who)
        setOpen(true)
        splash.close()
    else
        splash.close()
        task.wait(0.4)
        openGate("first", reason)
        gateEvent.Event:Wait()
        if not alive then return end
        task.wait(0.35)
        local b = makeBrand(450)
        runSetup(b)
        b.play(who)
        setOpen(true)
        b.close()
    end
    if S.autoInject then doInject(true) else addLog("INFO", "Press INJECT (Editor or Home) to enable script execution") end
    addLog("INFO", CFG.Name .. " loaded")
    notify(CFG.Name .. " ready · RightShift toggles · key valid " .. keyLeftText())
    if not S.tour then
        S.tour = true
        saveDB()
        task.wait(0.8)
        if alive and open then pcall(startTour) end   -- first launch only
    end
end)
