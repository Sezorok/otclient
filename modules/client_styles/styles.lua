local resourceLoaders = {
    ["otui"] = g_ui.importStyle,
    ["otfont"] = g_fonts.importFont,
    ["otps"] = g_particles.importParticle,
}

function init()
    local device = g_platform.getDevice()
    importResources("styles", "otui", device)
    importResources("fonts", "otfont", device)
    importResources("particles", "otps", device)

    g_mouse.loadCursors('/cursors/cursors')
    g_gameConfig.loadFonts()
end

function terminate()
end

function importResources(dir, resType, device)
    local path = '/' .. dir .. '/'
  local files = g_resources.listDirectoryFiles(path)
  -- Ensure deterministic load order: numeric-prefixed files first (ascending),
  -- then alphabetical. This guarantees base styles like '10-windows.otui'
  -- are available before dependent styles (e.g., custom windows).
  table.sort(files, function(a, b)
    local function sortKey(f)
      local num = tonumber(f:match('^(%d+)[-_]')) or math.huge
      return num, f
    end
    local na, sa = sortKey(a)
    local nb, sb = sortKey(b)
    if na ~= nb then return na < nb end
    return sa < sb
  end)
    for _, file in pairs(files) do
        if g_resources.isFileType(file, resType) then
            resourceLoaders[resType](path .. file)
        end
    end

    -- try load device specific resources (avoid corelib helpers to prevent early dependency)
    if device then
        local devicePath = g_platform.getDeviceShortName(device.type)
        if devicePath ~= "" then
            local more = importResources(dir .. '/' .. devicePath, resType)
            if _G.type(more) == 'table' then for _, v in ipairs(more) do table.insert(files, v) end end
        end
        local osPath = g_platform.getOsShortName(device.os)
        if osPath ~= "" then
            local more = importResources(dir .. '/' .. osPath, resType)
            if _G.type(more) == 'table' then for _, v in ipairs(more) do table.insert(files, v) end end
        end
        return
    end
    return files
end

function reloadParticles()
    g_particles.terminate()
    local device = g_platform.getDevice()
    importResources("particles", "otps", device)
end
