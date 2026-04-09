local resourceName = GetCurrentResourceName()
local frameworkName = nil
WeazelPermissionService = WeazelPermissionService or {}

local function loadJsonConfig(path)
    -- Role: load and decode a server-side JSON config file.
    -- Params: path (string) relative resource path.
    -- Return: decoded table or empty table on failure.
    -- Behavior: prints a warning if config is absent or malformed.
    -- Security: only reads packaged files from the current resource.
    local rawConfig = LoadResourceFile(resourceName, path)

    if not rawConfig then
        print(('[WEAZEL] Missing config file: %s'):format(path))
        return {}
    end

    local ok, decoded = pcall(json.decode, rawConfig)

    if not ok or type(decoded) ~= 'table' then
        print(('[WEAZEL] Invalid JSON in config file: %s'):format(path))
        return {}
    end

    return decoded
end

function detectFramework()
    -- Role: detect the active RP framework to resolve jobs and money.
    -- Params: none.
    -- Return: string framework id.
    -- Behavior: prefers ox_core, then qb-core, then esx, then standalone.
    -- Security: uses safe resource state checks instead of assuming exports exist.
    if frameworkName then
        return frameworkName
    end

    if GetResourceState('ox_core') == 'started' then
        frameworkName = 'ox_core'
    elseif GetResourceState('qb-core') == 'started' then
        frameworkName = 'qb-core'
    elseif GetResourceState('es_extended') == 'started' then
        frameworkName = 'esx'
    else
        frameworkName = 'standalone'
    end

    return frameworkName
end

local function getPlayerJob(source)
    -- Role: resolve a player's current job name across supported frameworks.
    -- Params: source (number) server id.
    -- Return: lowercase job name string or nil.
    -- Behavior: gracefully handles missing player objects or unsupported frameworks.
    -- Security: reads authoritative server framework state only.
    local framework = detectFramework()

    if framework == 'ox_core' then
        local player = exports.ox_core:GetPlayer(source)
        return player and player.getGroup and string.lower(player:getGroup() or '') or nil
    end

    if framework == 'qb-core' then
        local core = exports['qb-core']:GetCoreObject()
        local player = core and core.Functions.GetPlayer(source)
        return player and player.PlayerData and player.PlayerData.job and string.lower(player.PlayerData.job.name or '') or nil
    end

    if framework == 'esx' then
        local esx = exports['es_extended']:getSharedObject()
        local player = esx and esx.GetPlayerFromId(source)
        return player and player.job and string.lower(player.job.name or '') or nil
    end

    return nil
end

local function getPlayerIdentifiersLookup(source)
    -- Role: normalize all player identifiers into a fast lookup table.
    -- Params: source (number) server id.
    -- Return: table keyed by lowercase identifier.
    -- Behavior: supports license/steam/discord and any other standard identifiers.
    -- Security: server-origin identifiers cannot be spoofed by the client.
    local lookup = {}

    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        lookup[string.lower(identifier)] = true
    end

    return lookup
end

local function isWhitelisted(source, whitelist)
    -- Role: check whether a player's identifiers match a config whitelist.
    -- Params: source (number), whitelist (table array).
    -- Return: boolean.
    -- Behavior: compares all entries case-insensitively.
    -- Security: evaluates only authoritative server identifiers.
    local identifiers = getPlayerIdentifiersLookup(source)

    for _, identifier in ipairs(whitelist or {}) do
        if identifiers[string.lower(identifier)] then
            return true
        end
    end

    return false
end

local function isJobAllowed(source, jobs)
    -- Role: determine whether the player's current job is allowed.
    -- Params: source (number), jobs (table array).
    -- Return: boolean.
    -- Behavior: handles missing jobs by denying access.
    -- Security: uses server-side framework job data.
    local jobName = getPlayerJob(source)

    if not jobName then
        return false
    end

    for _, allowedJob in ipairs(jobs or {}) do
        if jobName == string.lower(allowedJob) then
            return true
        end
    end

    return false
end

local function encodeDetails(details)
    -- Role: format structured log details for readable console output.
    -- Params: details (table|string|nil).
    -- Return: string.
    -- Behavior: JSON-encodes tables and stringifies scalar values.
    -- Security: log formatting never influences permissions or SQL.
    if type(details) == 'table' then
        return json.encode(details)
    end

    if details == nil then
        return '{}'
    end

    return tostring(details)
end

function WeazelPermissionService.log(source, action, details)
    -- Role: emit the standard resource audit log line.
    -- Params: source (number), action (string), details (table|string|nil).
    -- Return: none.
    -- Behavior: prints player name, source id and structured metadata.
    -- Security: logs are append-only console output for observability.
    local playerName = source and GetPlayerName(source) or 'system'
    print(('[WEAZEL] %s by %s (%s) %s'):format(action, playerName, source or 'n/a', encodeDetails(details)))
end

function WeazelPermissionService.canUseFreecam(source)
    -- Role: resolve whether a player can use freecam based on config.
    -- Params: source (number) server id.
    -- Return: boolean allowed, string reason.
    -- Behavior: honors everyone/job/player whitelist flags in priority order.
    -- Security: all permission evaluation happens server-side.
    local config = loadJsonConfig('configs/freecam_config.json')

    if config.FreecamEveryone then
        return true, 'Access granted to everyone.'
    end

    if config.FreecamByPlayer and isWhitelisted(source, config.FreecamWhitelist) then
        return true, 'Access granted by player whitelist.'
    end

    if config.FreecamByJob and isJobAllowed(source, config.FreecamJobs) then
        return true, 'Access granted by job.'
    end

    if IsPlayerAceAllowed(source, 'weazel_news.freecam') then
        return true, 'Access granted by ACE permission.'
    end

    return false, 'Vous n avez pas la permission d utiliser la freecam.'
end

function WeazelPermissionService.canPublish(source)
    -- Role: resolve whether a player can import or publish a journal.
    -- Params: source (number) server id.
    -- Return: boolean allowed, string reason.
    -- Behavior: reads rules from the general JSON config.
    -- Security: keeps publication permission checks authoritative on the server.
    local config = loadJsonConfig('configs/weazel_config.json')

    if config.PublishEveryone then
        return true, 'Publication ouverte a tous.'
    end

    if config.PublishByPlayer and isWhitelisted(source, config.PublishWhitelist) then
        return true, 'Publication autorisee par whitelist.'
    end

    if config.PublishByJob and isJobAllowed(source, config.PublishJobs) then
        return true, 'Publication autorisee par job.'
    end

    if IsPlayerAceAllowed(source, 'weazel_news.publish') then
        return true, 'Publication autorisee par ACE.'
    end

    return false, 'Vous n avez pas la permission de publier un journal.'
end

RegisterNetEvent('weazel_news:server:requestFreecam', function()
    -- Role: handle a client request to toggle freecam.
    -- Params: none (uses implicit source).
    -- Return: none.
    -- Behavior: evaluates permissions and returns the decision to the client.
    -- Security: denies by default when no rule matches.
    local source = source
    local allowed, reason = WeazelPermissionService.canUseFreecam(source)

    WeazelPermissionService.log(source, allowed and 'freecam_permission_granted' or 'freecam_permission_denied', {
        reason = reason
    })

    TriggerClientEvent('weazel_news:client:setFreecamAllowed', source, allowed, reason)
end)

RegisterNetEvent('weazel_news:server:requestPublishPermission', function()
    -- Role: handle a client request to open the import/publication UI.
    -- Params: none (uses implicit source).
    -- Return: none.
    -- Behavior: responds with the publication permission result.
    -- Security: denies by default when no rule matches.
    local source = source
    local allowed, reason = WeazelPermissionService.canPublish(source)

    WeazelPermissionService.log(source, allowed and 'publish_permission_granted' or 'publish_permission_denied', {
        reason = reason
    })

    TriggerClientEvent('weazel_news:client:publishPermissionResult', source, allowed, reason)
end)

RegisterNetEvent('weazel_news:server:logAction', function(action, details)
    -- Role: receive client-origin audit events and print them consistently.
    -- Params: action (string), details (table|string|nil).
    -- Return: none.
    -- Behavior: normalizes the event name and forwards it to the logger.
    -- Security: logs are informational only and never trusted for permissions.
    WeazelPermissionService.log(source, tostring(action), details)
end)
