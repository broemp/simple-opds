-- OPDSParser lives in opds.koplugin and is only searchable on package.path
-- once all plugins have finished loading, so resolve it lazily.
local _opds_parser
local function OPDSParser()
    if not _opds_parser then _opds_parser = require("opdsparser") end
    return _opds_parser
end
local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local url = require("socket.url")
local logger = require("logger")

local FeedClient = {}

local CATALOG_TYPE = "application/atom%+xml"
local SEARCH_TYPE = "application/opensearchdescription%+xml"
local ACQUISITION_REL = "^http://opds%-spec%.org/acquisition"
local IMAGE_RELS = {
    ["http://opds-spec.org/image"] = true,
    ["http://opds-spec.org/cover"] = true,
    ["x-stanza-cover-image"] = true,
}
local THUMBNAIL_RELS = {
    ["http://opds-spec.org/image/thumbnail"] = true,
    ["http://opds-spec.org/thumbnail"] = true,
    ["x-stanza-cover-image-thumbnail"] = true,
}

local function http_get(item_url, username, password)
    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code, headers, status = socket.skip(1, http.request{
        url = item_url,
        method = "GET",
        headers = { ["Accept-Encoding"] = "identity" },
        sink = ltn12.sink.table(sink),
        user = username,
        password = password,
    })
    socketutil:reset_timeout()
    if code == 200 then
        local body = table.concat(sink)
        return body ~= "" and body or nil, headers
    end
    logger.dbg("simple-opds: GET failed", item_url, code, status)
    return nil, headers, code, status
end

local function download_to(local_path, remote_url, username, password)
    -- Write to a sibling .tmp first and rename on success, so a reader
    -- watching `local_path` only ever sees a complete file. (This matters for
    -- subprocess-based cover fetches polled by file existence.)
    local tmp = local_path .. ".tmp"
    local file, ferr = io.open(tmp, "w")
    if not file then
        logger.dbg("simple-opds: cannot open", tmp, ferr)
        return false
    end
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code = socket.skip(1, http.request{
        url = remote_url,
        headers = { ["Accept-Encoding"] = "identity" },
        sink = ltn12.sink.file(file),
        user = username,
        password = password,
    })
    socketutil:reset_timeout()
    if code == 200 then
        os.rename(tmp, local_path)
        return true
    end
    os.remove(tmp)
    return false, code
end

FeedClient.fetch_xml = http_get
FeedClient.download_to = download_to

local function abs(base, href)
    if not href then return nil end
    return url.absolute(base, href)
end

-- Parse the root feed of a server, classify its navigation links.
function FeedClient.fetch_feed(server, item_url)
    local xml, _h, code = http_get(item_url, server.username, server.password)
    if not xml then return nil, code end
    local ok, feed = pcall(function() return OPDSParser():parse(xml) end)
    if not ok or not feed then
        logger.dbg("simple-opds: parse failed for", item_url)
        return nil, "parse"
    end
    return feed.feed or feed
end

local function classify_link(link, links)
    local rel = link.rel
    if not rel then return end
    if rel:find("http://opds%-spec%.org/sort/new") or rel == "new" then
        links.recent = links.recent or link.href
    elseif rel:find("http://opds%-spec%.org/sort/popular") or rel == "popular" then
        links.popular = links.popular or link.href
    elseif rel:lower():find("subject") or rel:lower():find("categor") then
        links.categories = links.categories or link.href
    end
end

local function normalize_entry(entry, base_url)
    local item = {
        title = "Unknown",
        author = nil,
        cover_url = nil,
        acquisitions = {},
        sub_feed_url = nil,
        searchable = false,
    }

    if type(entry.title) == "string" then
        item.title = entry.title
    elseif type(entry.title) == "table" and type(entry.title.div) == "string" then
        item.title = entry.title.div
    end

    if type(entry.author) == "table" and entry.author.name then
        local n = entry.author.name
        if type(n) == "string" then item.author = n
        elseif type(n) == "table" and #n > 0 then item.author = table.concat(n, ", ") end
    end

    if entry.link then
        for _, link in ipairs(entry.link) do
            local href = abs(base_url, link.href)
            if href then
                if link.type and link.type:find(CATALOG_TYPE)
                        and (not link.rel
                             or link.rel == "subsection"
                             or link.rel == "http://opds-spec.org/subsection"
                             or link.rel == "http://opds-spec.org/sort/new"
                             or link.rel == "http://opds-spec.org/sort/popular") then
                    item.sub_feed_url = href
                end
                if link.rel then
                    if THUMBNAIL_RELS[link.rel] then
                        item.cover_url = href -- thumbnails preferred
                    elseif IMAGE_RELS[link.rel] and not item.cover_url then
                        item.cover_url = href
                    elseif link.rel:match(ACQUISITION_REL) then
                        table.insert(item.acquisitions, {
                            type = link.type,
                            href = href,
                            title = link.title,
                        })
                    end
                end
            end
        end
    end

    return item
end

-- Returns: listing-table on success; nil, code on failure (code is HTTP status
-- when the request reached the server, or "parse" when the XML was unreadable).
function FeedClient.list_items(server, item_url)
    local feed, code = FeedClient.fetch_feed(server, item_url)
    if not feed then return nil, code end

    local nav_links = {}
    local next_url, search_url

    if feed.link then
        for _, link in ipairs(feed.link) do
            local href = abs(item_url, link.href)
            if href then
                classify_link(link, nav_links)
                -- Also store an absolute href version so the shell can navigate directly.
                if link.rel and (nav_links[link.rel] == link.href) then
                    -- keep relative for diagnostics; absolute below
                end
                if link.type and link.type:find(SEARCH_TYPE) then
                    search_url = href
                end
                if link.rel == "next" then
                    next_url = href
                end
            end
        end
    end

    -- Re-absolutize the nav_links
    for k, v in pairs(nav_links) do
        nav_links[k] = abs(item_url, v)
    end

    local items = {}
    for _, entry in ipairs(feed.entry or {}) do
        table.insert(items, normalize_entry(entry, item_url))
    end

    return {
        items = items,
        nav_links = nav_links,
        next_url = next_url,
        search_url = search_url,
    }
end

-- Probe server root. Returns { nav_links, search_url } from the root feed,
-- or nil if the request failed.
function FeedClient.discover(server)
    local listing = FeedClient.list_items(server, server.url)
    if not listing then return nil end
    return {
        nav_links = listing.nav_links or {},
        search_url = listing.search_url,
    }
end

-- Resolve a search URL (OpenSearch description doc) into a usable template.
-- Returns a template with `{searchTerms}` rewritten to `%s` and any other
-- `{foo?}` placeholders stripped, resolved against the description doc URL
-- so relative templates become absolute.
function FeedClient.resolve_search_template(server, search_url)
    local xml = http_get(search_url, server.username, server.password)
    if not xml then
        logger.dbg("simple-opds: opensearch GET failed for", search_url)
        return nil
    end
    local ok, parsed = pcall(function() return OPDSParser():parse(xml) end)
    if not ok or not parsed then
        logger.dbg("simple-opds: opensearch parse failed for", search_url)
        return nil
    end
    local urls = parsed.OpenSearchDescription and parsed.OpenSearchDescription.Url
    if type(urls) ~= "table" then return nil end

    -- Prefer an Atom/OPDS Url; fall back to the first one with a template.
    local picked
    for _, u in ipairs(urls) do
        if u.template and u.type and u.type:find("atom") then picked = u; break end
    end
    if not picked then
        for _, u in ipairs(urls) do
            if u.template then picked = u; break end
        end
    end
    if not picked then return nil end

    local tpl = picked.template
    -- {searchTerms} → %s; drop any other optional placeholders like {foo?}.
    tpl = tpl:gsub("{searchTerms}", "%%s")
    tpl = tpl:gsub("{[^}]*}", "")
    -- Tidy up dangling separators left by stripped placeholders.
    tpl = tpl:gsub("&+", "&"):gsub("&$", ""):gsub("?&", "?"):gsub("%?$", "")
    tpl = url.absolute(search_url, tpl)
    return tpl
end

function FeedClient.search(server, search_url, query)
    if not search_url or not query or query == "" then return nil end
    local template = search_url
    if not template:find("%%s") then
        local resolved = FeedClient.resolve_search_template(server, search_url)
        if resolved then template = resolved end
    end
    local encoded = url.escape(query)
    local target
    if template:find("%%s") then
        target = template:format(encoded)
    else
        target = template .. (template:find("?", 1, true) and "&" or "?") .. "q=" .. encoded
    end
    logger.dbg("simple-opds: search target", target)
    return FeedClient.list_items(server, target)
end

-- Heuristic: a feed is treated as an A-Z index if at least 3 of its entries
-- are single-letter titles. Returns a map { ["A"] = sub_feed_url, … } or nil.
function FeedClient.detect_az_index(listing)
    if not listing or not listing.items then return nil end
    local letters = {}
    local hits = 0
    for _, item in ipairs(listing.items) do
        local t = item.title and item.title:match("^%s*([A-Za-z])%s*$")
        if t and item.sub_feed_url then
            letters[t:upper()] = item.sub_feed_url
            hits = hits + 1
        end
    end
    if hits >= 3 then return letters end
    return nil
end

return FeedClient
