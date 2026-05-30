local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local md5 = require("ffi/sha2").md5

local CACHE_DIR = DataStorage:getDataDir() .. "/cache/simple-opds-covers"
local INDEX_FILE = CACHE_DIR .. "/index.lua"
local MAX_BYTES = 50 * 1024 * 1024

local CoverCache = {}

local function ensure_dir()
    if lfs.attributes(CACHE_DIR, "mode") ~= "directory" then
        lfs.mkdir(CACHE_DIR)
    end
end

local function index()
    ensure_dir()
    return LuaSettings:open(INDEX_FILE)
end

function CoverCache.path_for(url)
    if not url or url == "" then return nil end
    return CACHE_DIR .. "/" .. md5(url)
end

function CoverCache.has(url)
    local path = CoverCache.path_for(url)
    return path and lfs.attributes(path, "mode") == "file"
end

function CoverCache.record(url, meta)
    if not url then return end
    local idx = index()
    local entries = idx:readSetting("entries", {})
    entries[url] = {
        path = CoverCache.path_for(url),
        title = meta and meta.title,
        author = meta and meta.author,
        fetched_at = os.time(),
    }
    idx:saveSetting("entries", entries)
    idx:flush()
end

function CoverCache.lookup(url)
    if not url then return nil end
    local entries = index():readSetting("entries", {})
    return entries[url]
end

function CoverCache.prune()
    ensure_dir()
    local total = 0
    local files = {}
    for name in lfs.dir(CACHE_DIR) do
        if name ~= "." and name ~= ".." and name ~= "index.lua" then
            local p = CACHE_DIR .. "/" .. name
            local attr = lfs.attributes(p)
            if attr and attr.mode == "file" then
                total = total + attr.size
                table.insert(files, { path = p, size = attr.size, mtime = attr.modification })
            end
        end
    end
    if total <= MAX_BYTES then return end
    table.sort(files, function(a, b) return a.mtime < b.mtime end)
    for _, f in ipairs(files) do
        if total <= MAX_BYTES then break end
        os.remove(f.path)
        total = total - f.size
    end
end

function CoverCache.dir()
    ensure_dir()
    return CACHE_DIR
end

return CoverCache
