local resourceName = GetCurrentResourceName()

local function loadJsonConfig(path)
    -- Role: load and decode a JSON configuration file used by sales logic.
    -- Params: path (string) relative resource path.
    -- Return: table decoded config or empty table.
    -- Behavior: emits a warning if the file cannot be read.
    -- Security: only accesses packaged resource files.
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

local function getFramework()
    -- Role: obtain the same framework decision used for permissions.
    -- Params: none.
    -- Return: string framework id.
    -- Behavior: reuses the permission service detector for consistency.
    -- Security: keeps all money interactions on the server.
    return detectFramework()
end

local function removeMoney(source, amount)
    -- Role: charge a player through the active RP framework.
    -- Params: source (number), amount (number).
    -- Return: boolean success.
    -- Behavior: supports ox_core, qb-core, esx and a free standalone fallback.
    -- Security: never trusts client-side cash data and charges server-side only.
    local framework = getFramework()

    if framework == 'ox_core' then
        local player = exports.ox_core:GetPlayer(source)
        return player and player.removeAccountMoney and player:removeAccountMoney('money', amount) or false
    end

    if framework == 'qb-core' then
        local core = exports['qb-core']:GetCoreObject()
        local player = core and core.Functions.GetPlayer(source)

        if not player then
            return false
        end

        return player.Functions.RemoveMoney('cash', amount, 'weazel-journal-purchase')
    end

    if framework == 'esx' then
        local esx = exports['es_extended']:getSharedObject()
        local player = esx and esx.GetPlayerFromId(source)

        if not player or player.getMoney() < amount then
            return false
        end

        player.removeMoney(amount)
        return true
    end

    return true
end

local function fetchLatestJournal()
    -- Role: fetch the latest published journal from the database.
    -- Params: none.
    -- Return: table|nil journal row.
    -- Behavior: returns the newest published record for reading or purchase.
    -- Security: performs a parameter-free read-only query.
    return MySQL.single.await([[
        SELECT id, unique_id, author, publish_date, image, mime_type, resolution, filename
        FROM weazel_journals
        WHERE status = 'published'
        ORDER BY publish_date DESC, id DESC
        LIMIT 1
    ]])
end

local function formatJournalForClient(journal)
    -- Role: convert a database row into the payload expected by the NUI.
    -- Params: journal (table).
    -- Return: table formatted journal payload.
    -- Behavior: rebuilds the full data URL for direct browser rendering.
    -- Security: uses stored mime type and base64 text without evaluating content.
    return {
        id = journal.id,
        uniqueId = journal.unique_id,
        author = journal.author,
        publishDate = journal.publish_date,
        filename = journal.filename,
        resolution = journal.resolution,
        imageUrl = ('data:%s;base64,%s'):format(journal.mime_type or 'image/png', journal.image or '')
    }
end

RegisterNetEvent('weazel_news:server:purchaseJournal', function(shopIndex)
    -- Role: process a journal purchase at one of the configured kiosks.
    -- Params: shopIndex (number) index from the client-side shop list.
    -- Return: none.
    -- Behavior: checks shop existence, charges the player and opens the latest journal.
    -- Security: validates the shop index and payment on the authoritative server.
    local source = source
    local shops = loadJsonConfig('configs/weazel_shops.json')
    local config = loadJsonConfig('configs/weazel_config.json')
    local shop = shops[tonumber(shopIndex or 0)]
    local price = tonumber(config.JournalPrice) or 50

    if not shop then
        TriggerClientEvent('weazel_news:client:purchaseCompleted', source, false, 'Point de vente invalide.')
        return
    end

    local journal = fetchLatestJournal()

    if not journal then
        TriggerClientEvent('weazel_news:client:purchaseCompleted', source, false, 'Aucun journal publie pour le moment.')
        return
    end

    if not removeMoney(source, price) then
        WeazelPermissionService.log(source, 'journal_purchase_failed', {
            shop = shop.name,
            price = price
        })
        TriggerClientEvent('weazel_news:client:purchaseCompleted', source, false, 'Fonds insuffisants.')
        return
    end

    MySQL.insert.await([[
        INSERT INTO weazel_journal_purchases (journal_id, buyer_name, purchase_date, price, shop_name)
        VALUES (?, ?, NOW(), ?, ?)
    ]], {
        journal.id,
        GetPlayerName(source) or 'Unknown',
        price,
        shop.name or ('Shop %s'):format(shopIndex)
    })

    WeazelPermissionService.log(source, 'journal_purchased', {
        journalId = journal.id,
        price = price,
        shop = shop.name
    })

    TriggerClientEvent('weazel_news:client:purchaseCompleted', source, true, formatJournalForClient(journal))
end)

RegisterNetEvent('weazel_news:server:requestLatestJournal', function()
    -- Role: fetch the latest journal for the reader command.
    -- Params: none (uses implicit source).
    -- Return: none.
    -- Behavior: opens the latest publication without a purchase workflow.
    -- Security: read-only database access from the server.
    local source = source
    local journal = fetchLatestJournal()

    if not journal then
        TriggerClientEvent('weazel_news:client:openLatestJournal', source, false, 'Aucun journal publie pour le moment.')
        return
    end

    WeazelPermissionService.log(source, 'journal_read_requested', { journalId = journal.id })
    TriggerClientEvent('weazel_news:client:openLatestJournal', source, true, formatJournalForClient(journal))
end)
