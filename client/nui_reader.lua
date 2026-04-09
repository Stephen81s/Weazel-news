local resourceName = GetCurrentResourceName()
local generalConfig = {}
local shops = {}
local pendingImport = nil
local currentJournal = nil
local nuiOpen = false

local function loadJsonConfig(path)
    -- Role: load and decode a packaged JSON configuration file.
    -- Params: path (string) relative path inside the resource.
    -- Return: decoded table or empty table when unavailable.
    -- Behavior: emits a console warning if the file is missing or malformed.
    -- Security: only accesses files bundled with the current resource.
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

local function notify(message)
    -- Role: show a basic in-game feed notification.
    -- Params: message (string).
    -- Return: none.
    -- Behavior: displays concise user feedback for NUI workflows.
    -- Security: the message is local display only and not used for logic.
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function sendClientLog(action, details)
    -- Role: send a NUI or interaction log to the central server logger.
    -- Params: action (string), details (table|string|nil).
    -- Return: none.
    -- Behavior: keeps audit logs on the authoritative side.
    -- Security: metadata is descriptive only and does not grant actions.
    TriggerServerEvent('weazel_news:server:logAction', action, details or {})
end

local function setNuiState(page, payload)
    -- Role: open or update one of the Weazel NUI pages.
    -- Params: page (string), payload (table).
    -- Return: none.
    -- Behavior: focuses the UI and sends an update message to the browser.
    -- Security: only transmits validated in-resource data to the UI.
    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openPage',
        page = page,
        payload = payload or {}
    })
end

local function closeNui()
    -- Role: close the current NUI page and release focus.
    -- Params: none.
    -- Return: none.
    -- Behavior: hides the browser and clears cursor focus.
    -- Security: local-only cleanup without touching server state.
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closePage' })
end

local function openImportUi()
    -- Role: ask the server whether the player can open the journal import tool.
    -- Params: none.
    -- Return: none.
    -- Behavior: permission decision remains server-side.
    -- Security: the browser is opened only after a positive authorization response.
    TriggerServerEvent('weazel_news:server:requestPublishPermission')
end

local function openReader(journal)
    -- Role: display a published journal in the reader NUI.
    -- Params: journal (table) with image and metadata.
    -- Return: none.
    -- Behavior: stores the current journal and opens the dedicated reader page.
    -- Security: journal payload comes from the server after validation.
    currentJournal = journal
    setNuiState('reader', { journal = journal })
    sendClientLog('journal_opened', {
        journalId = journal.id,
        filename = journal.filename
    })
end

RegisterNetEvent('weazel_news:client:publishPermissionResult', function(allowed, reason)
    -- Role: receive publish/import permission state from the server.
    -- Params: allowed (boolean), reason (string|nil).
    -- Return: none.
    -- Behavior: opens the import page on success or notifies on refusal.
    -- Security: the permission decision cannot be forged client-side.
    if not allowed then
        notify(reason or 'Acces refuse.')
        return
    end

    setNuiState('import', {
        maxFileSizeMB = tonumber(generalConfig.MaxFileSizeMB) or 5,
        recommendedResolution = generalConfig.RecommendedResolution or '1080x1920'
    })
end)

RegisterNetEvent('weazel_news:client:importValidated', function(success, response)
    -- Role: receive validation feedback for a locally selected journal image.
    -- Params: success (boolean), response (table|string).
    -- Return: none.
    -- Behavior: caches validated file data client-side until publication.
    -- Security: only the server-confirmed metadata is kept for publish requests.
    if not success then
        notify(type(response) == 'string' and response or 'Import refuse.')
        return
    end

    pendingImport = response
    SendNUIMessage({
        action = 'importValidated',
        payload = response
    })

    sendClientLog('journal_imported', {
        filename = response.filename,
        mimeType = response.mimeType,
        resolution = response.resolution
    })
end)

RegisterNetEvent('weazel_news:client:publishCompleted', function(success, response)
    -- Role: receive the result of a publication attempt from the server.
    -- Params: success (boolean), response (table|string).
    -- Return: none.
    -- Behavior: clears pending import data on success and closes the UI.
    -- Security: publication outcome always comes from the server/database layer.
    if not success then
        notify(type(response) == 'string' and response or 'Publication refusee.')
        return
    end

    pendingImport = nil
    closeNui()
    notify(('Journal publie (#%s).'):format(response.id))
end)

RegisterNetEvent('weazel_news:client:purchaseCompleted', function(success, response)
    -- Role: receive the result of a journal purchase request.
    -- Params: success (boolean), response (table|string).
    -- Return: none.
    -- Behavior: opens the journal reader immediately after a successful purchase.
    -- Security: journal content is supplied by the server after payment validation.
    if not success then
        notify(type(response) == 'string' and response or 'Achat refuse.')
        return
    end

    openReader(response)
end)

RegisterNetEvent('weazel_news:client:openLatestJournal', function(success, response)
    -- Role: open the latest published journal without a purchase flow.
    -- Params: success (boolean), response (table|string).
    -- Return: none.
    -- Behavior: used by the reader command for quick staff testing.
    -- Security: content still comes from the server after fetch validation.
    if not success then
        notify(type(response) == 'string' and response or 'Aucun journal disponible.')
        return
    end

    openReader(response)
end)

RegisterNUICallback('close', function(_, cb)
    -- Role: handle browser close actions from both NUI pages.
    -- Params: _ (table), cb (function).
    -- Return: none.
    -- Behavior: clears focus and logs journal reader closure if relevant.
    -- Security: close is always safe and local to the client session.
    if currentJournal then
        sendClientLog('journal_closed', {
            journalId = currentJournal.id,
            filename = currentJournal.filename
        })
    end

    closeNui()
    currentJournal = nil
    cb({ ok = true })
end)

RegisterNUICallback('validateImport', function(data, cb)
    -- Role: forward a selected local image to the server for validation.
    -- Params: data (table with file metadata/base64), cb (function).
    -- Return: none.
    -- Behavior: does not trust the browser and relies on server-side checks.
    -- Security: file type and size are revalidated before any publish step.
    TriggerServerEvent('weazel_news:server:validateImport', data)
    cb({ ok = true })
end)

RegisterNUICallback('publishJournal', function(_, cb)
    -- Role: request publication of the last validated import.
    -- Params: _ (table), cb (function).
    -- Return: none.
    -- Behavior: only proceeds when a server-approved import is cached locally.
    -- Security: blocks publication if no validated import exists.
    if not pendingImport then
        cb({ ok = false, message = 'Aucun journal valide a publier.' })
        return
    end

    TriggerServerEvent('weazel_news:server:publishJournal', pendingImport)
    cb({ ok = true })
end)

CreateThread(function()
    -- Role: initialize configs, commands and shop interactions.
    -- Params: none.
    -- Return: none.
    -- Behavior: loads shops and exposes import/reader commands from config.
    -- Security: all commands still route through server-side permissions and payment.
    generalConfig = loadJsonConfig('configs/weazel_config.json')
    shops = loadJsonConfig('configs/weazel_shops.json')

    local commands = generalConfig.Commands or {}
    RegisterCommand(commands.Import or 'weazelimport', function()
        openImportUi()
    end, false)

    RegisterCommand(commands.Reader or 'weazeljournal', function()
        TriggerServerEvent('weazel_news:server:requestLatestJournal')
    end, false)
end)

CreateThread(function()
    -- Role: manage shop markers, help text and purchase interaction.
    -- Params: none.
    -- Return: none.
    -- Behavior: creates configured blips and checks purchase radius every tick.
    -- Security: the server performs the actual sale and latest journal lookup.
    Wait(500)

    for index, shop in ipairs(shops) do
        if shop.blip then
            local blip = AddBlipForCoord(shop.coords.x + 0.0, shop.coords.y + 0.0, shop.coords.z + 0.0)
            SetBlipSprite(blip, 184)
            SetBlipScale(blip, 0.8)
            SetBlipColour(blip, 1)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(shop.name or ('Weazel Shop %s'):format(index))
            EndTextCommandSetBlipName(blip)
        end
    end

    while true do
        local playerCoords = GetEntityCoords(PlayerPedId())
        local waitTime = 1000

        for index, shop in ipairs(shops) do
            local shopCoords = vector3(shop.coords.x + 0.0, shop.coords.y + 0.0, shop.coords.z + 0.0)
            local distance = #(playerCoords - shopCoords)
            local radius = tonumber(shop.radius) or 2.0

            if distance <= math.max(radius * 3.0, 10.0) then
                waitTime = 0
                DrawMarker(1, shopCoords.x, shopCoords.y, shopCoords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, radius * 2.0, radius * 2.0, 0.6, 196, 24, 24, 130, false, false, 2, false, nil, nil, false)

                if distance <= radius then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName(('Appuyez sur ~INPUT_CONTEXT~ pour acheter le journal (%s$)'):format(tonumber(generalConfig.JournalPrice) or 50))
                    EndTextCommandDisplayHelp(0, false, true, -1)

                    if IsControlJustPressed(0, 38) then
                        TriggerServerEvent('weazel_news:server:purchaseJournal', index)
                    end
                end
            end
        end

        Wait(waitTime)
    end
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    -- Role: close NUI cleanly when the resource stops.
    -- Params: stoppedResource (string).
    -- Return: none.
    -- Behavior: ensures focus is released during reloads.
    -- Security: only applies to this resource.
    if stoppedResource ~= resourceName then
        return
    end

    closeNui()
end)
