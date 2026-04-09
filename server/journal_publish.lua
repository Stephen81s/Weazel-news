RegisterNetEvent('weazel_news:server:publishJournal', function(clientImport)
    -- Role: publish the last validated journal import into the database.
    -- Params: clientImport (table) metadata echoed by the client.
    -- Return: none.
    -- Behavior: reuses the server-cached import and inserts a published row.
    -- Security: validates publish permission and never trusts raw client payload alone.
    local source = source
    local allowed, reason = WeazelPermissionService.canPublish(source)

    if not allowed then
        WeazelPermissionService.log(source, 'journal_publish_refused', { reason = reason })
        TriggerClientEvent('weazel_news:client:publishCompleted', source, false, reason)
        return
    end

    local pending = GetPendingWeazelImport(source)

    if not pending then
        TriggerClientEvent('weazel_news:client:publishCompleted', source, false, 'Aucun import valide en attente.')
        return
    end

    if clientImport and clientImport.filename and pending.filename ~= clientImport.filename then
        TriggerClientEvent('weazel_news:client:publishCompleted', source, false, 'Le journal a change, veuillez reimporter le fichier.')
        return
    end

    local author = GetPlayerName(source) or 'Unknown'
    local uniqueId = ('WZ-%s-%s'):format(os.time(), math.random(1000, 9999))

    local insertId = MySQL.insert.await([[
        INSERT INTO weazel_journals (unique_id, author, publish_date, image, mime_type, resolution, filename, status)
        VALUES (?, ?, NOW(), ?, ?, ?, ?, 'published')
    ]], {
        uniqueId,
        author,
        pending.image,
        pending.mimeType,
        pending.resolution,
        pending.filename
    })

    ClearPendingWeazelImport(source)

    WeazelPermissionService.log(source, 'journal_published', {
        id = insertId,
        uniqueId = uniqueId,
        filename = pending.filename
    })

    TriggerClientEvent('weazel_news:client:publishCompleted', source, true, {
        id = insertId,
        uniqueId = uniqueId,
        filename = pending.filename
    })
end)
