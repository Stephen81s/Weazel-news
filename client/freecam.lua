local resourceName = GetCurrentResourceName()
local freecamConfig = {}
local generalConfig = {}
local freecamState = {
    enabled = false,
    camera = nil,
    coords = nil,
    rotation = vector3(0.0, 0.0, 0.0),
    speed = 1.0,
    fov = 60.0,
    pov = false,
    filter = false
}

local defaultControls = {
    forward = 32,
    backward = 33,
    left = 34,
    right = 35,
    up = 44,
    down = 38,
    faster = 21,
    slower = 36,
    togglePov = 74,
    toggleFilter = 311,
    exit = 177
}

local filterName = 'heliGunCam'

local function loadJsonConfig(path)
    -- Role: load and decode a JSON configuration file shipped with the resource.
    -- Params: path (string) relative path inside the resource.
    -- Return: decoded table or empty table on failure.
    -- Behavior: prints a warning when a config is unreadable.
    -- Security: only reads packaged resource files, never arbitrary disk paths.
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
    -- Role: show a lightweight in-game notification.
    -- Params: message (string).
    -- Return: none.
    -- Behavior: uses feed ticker for broad compatibility.
    -- Security: notification text is display-only.
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function getControlConfig()
    -- Role: merge configured controls with safe defaults.
    -- Params: none.
    -- Return: table of control ids.
    -- Behavior: allows config overrides without breaking missing values.
    -- Security: validates types by falling back to defaults when absent.
    local configured = generalConfig.Controls or {}
    local controls = {}

    for key, value in pairs(defaultControls) do
        controls[key] = tonumber(configured[key]) or value
    end

    return controls
end

local function sendClientLog(action, details)
    -- Role: forward a client-side action to the server logger.
    -- Params: action (string), details (table|string|nil).
    -- Return: none.
    -- Behavior: wraps all local freecam actions with consistent server logging.
    -- Security: sends descriptive metadata only, without trusting it for permissions.
    TriggerServerEvent('weazel_news:server:logAction', action, details or {})
end

local function clampSpeed(value)
    -- Role: keep the camera speed inside configured bounds.
    -- Params: value (number).
    -- Return: number inside min/max range.
    -- Behavior: defaults to configured minimum speed when values are invalid.
    -- Security: avoids extreme or malformed speeds affecting camera movement.
    local minSpeed = tonumber(freecamConfig.FreecamMinSpeed) or 0.05
    local maxSpeed = tonumber(freecamConfig.FreecamMaxSpeed) or 20.0

    if value < minSpeed then
        return minSpeed
    end

    if value > maxSpeed then
        return maxSpeed
    end

    return value
end

local function createFreecam()
    -- Role: spawn the scripted camera used by the freecam system.
    -- Params: none.
    -- Return: none.
    -- Behavior: mirrors the gameplay camera position so activation feels seamless.
    -- Security: destroys any previous scripted camera before creating a new one.
    if freecamState.camera and DoesCamExist(freecamState.camera) then
        DestroyCam(freecamState.camera, false)
    end

    freecamState.coords = GetGameplayCamCoord()
    freecamState.rotation = GetGameplayCamRot(2)
    freecamState.camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    freecamState.fov = GetGameplayCamFov()

    SetCamCoord(freecamState.camera, freecamState.coords.x, freecamState.coords.y, freecamState.coords.z)
    SetCamRot(freecamState.camera, freecamState.rotation.x, freecamState.rotation.y, freecamState.rotation.z, 2)
    SetCamFov(freecamState.camera, freecamState.fov)
    RenderScriptCams(true, true, 300, true, true)
end

local function disableFreecamVisuals()
    -- Role: reset camera visuals when freecam stops.
    -- Params: none.
    -- Return: none.
    -- Behavior: clears timecycle modifiers and restores normal rendering.
    -- Security: always checks camera existence before touching engine state.
    if freecamState.filter then
        ClearTimecycleModifier()
        freecamState.filter = false
    end

    if freecamState.camera and DoesCamExist(freecamState.camera) then
        RenderScriptCams(false, true, 300, true, true)
        DestroyCam(freecamState.camera, false)
    end

    freecamState.camera = nil
end

local function setFreecamFilter(enabled)
    -- Role: enable or disable the visual filter available in freecam.
    -- Params: enabled (boolean).
    -- Return: none.
    -- Behavior: applies a simple news-camera look through a timecycle modifier.
    -- Security: only applies filters when explicitly enabled in config.
    if not freecamConfig.FiltersEnabled then
        return
    end

    freecamState.filter = enabled and true or false

    if freecamState.filter then
        SetTimecycleModifier(filterName)
        SetTimecycleModifierStrength(0.35)
    else
        ClearTimecycleModifier()
    end

    sendClientLog('freecam_filter_changed', { enabled = freecamState.filter })
end

local function setFreecamPov(enabled)
    -- Role: switch between standard freecam and first-person style freecam.
    -- Params: enabled (boolean).
    -- Return: none.
    -- Behavior: slightly narrows FOV for a POV feel when active.
    -- Security: only activates when the feature is enabled in config.
    if not freecamConfig.POVEnabled or not freecamState.camera then
        return
    end

    freecamState.pov = enabled and true or false
    SetCamFov(freecamState.camera, freecamState.pov and 48.0 or freecamState.fov)
    sendClientLog('freecam_pov_changed', { enabled = freecamState.pov })
end

local function getRotationDirection(rotation)
    -- Role: convert camera rotation into forward movement vectors.
    -- Params: rotation (vector3) in degrees.
    -- Return: vector3 forward direction.
    -- Behavior: ignores roll and computes a normalized forward vector.
    -- Security: math-only helper without external side effects.
    local pitch = math.rad(rotation.x)
    local yaw = math.rad(rotation.z)
    local cosPitch = math.cos(pitch)

    return vector3(-math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch))
end

local function getRightDirection(rotation)
    -- Role: convert camera rotation into strafe movement vectors.
    -- Params: rotation (vector3) in degrees.
    -- Return: vector3 right direction.
    -- Behavior: computes movement perpendicular to the current yaw.
    -- Security: math-only helper without external side effects.
    local yaw = math.rad(rotation.z + 90.0)
    return vector3(-math.sin(yaw), math.cos(yaw), 0.0)
end

local function getDistanceFromPlayer()
    -- Role: compute current camera distance from the controlled player.
    -- Params: none.
    -- Return: number distance in meters.
    -- Behavior: uses player ped coordinates as the audio anchor reference.
    -- Security: avoids using stale coordinates by reading the ped each tick.
    local playerCoords = GetEntityCoords(PlayerPedId())
    return #(freecamState.coords - playerCoords)
end

local function stopFreecam(reason)
    -- Role: fully disable the freecam session and restore player control.
    -- Params: reason (string|nil) informational reason for logs.
    -- Return: none.
    -- Behavior: unlocks the player, resets visuals and logs the stop event.
    -- Security: idempotent to avoid duplicate cleanup bugs.
    if not freecamState.enabled then
        return
    end

    freecamState.enabled = false
    disableFreecamVisuals()
    sendClientLog('freecam_disabled', { reason = reason or 'manual' })
end

local function startFreecam()
    -- Role: activate the freecam after the server approved permissions.
    -- Params: none.
    -- Return: none.
    -- Behavior: freezes the player in place while keeping local audio on the ped.
    -- Security: only reachable from a positive server authorization response.
    if freecamState.enabled then
        return
    end

    freecamState.speed = clampSpeed(freecamState.speed)
    freecamState.pov = false
    freecamState.filter = false
    freecamState.enabled = true

    createFreecam()
    sendClientLog('freecam_enabled', {
        speed = freecamState.speed,
        maxDistance = freecamConfig.FreecamMaxDistance
    })
end

RegisterNetEvent('weazel_news:client:setFreecamAllowed', function(allowed, reason)
    -- Role: receive the server decision for a freecam access request.
    -- Params: allowed (boolean), reason (string|nil).
    -- Return: none.
    -- Behavior: starts freecam on success, otherwise informs the player.
    -- Security: keeps the actual permission decision on the server.
    if not allowed then
        notify(reason or 'Freecam refusee.')
        return
    end

    startFreecam()
end)

CreateThread(function()
    -- Role: boot the client freecam subsystem and register commands.
    -- Params: none.
    -- Return: none.
    -- Behavior: loads configs once and exposes a command configured in JSON.
    -- Security: all privilege checks still occur server-side on command usage.
    freecamConfig = loadJsonConfig('configs/freecam_config.json')
    generalConfig = loadJsonConfig('configs/weazel_config.json')

    local commandName = ((generalConfig.Commands or {}).Freecam or 'weazelcam')

    RegisterCommand(commandName, function()
        if freecamState.enabled then
            stopFreecam('command_toggle')
            return
        end

        TriggerServerEvent('weazel_news:server:requestFreecam')
    end, false)
end)

CreateThread(function()
    -- Role: process freecam controls every frame while active.
    -- Params: none.
    -- Return: none.
    -- Behavior: updates scripted camera position, rotation, speed and toggles.
    -- Security: enforces the configured max distance client-side for resilience.
    while true do
        if not freecamState.enabled or not freecamState.camera then
            Wait(250)
        else
            Wait(0)

            local controls = getControlConfig()
            local lookX = GetDisabledControlNormal(0, 1)
            local lookY = GetDisabledControlNormal(0, 2)

            DisableAllControlActions(0)
            EnableControlAction(0, controls.exit, true)

            freecamState.rotation = vector3(
                math.min(89.0, math.max(-89.0, freecamState.rotation.x + (lookY * -5.0))),
                0.0,
                freecamState.rotation.z + (lookX * -5.0)
            )

            local forward = getRotationDirection(freecamState.rotation)
            local right = getRightDirection(freecamState.rotation)
            local moveDelta = vector3(0.0, 0.0, 0.0)

            if IsDisabledControlPressed(0, controls.forward) then
                moveDelta = moveDelta + forward
            end

            if IsDisabledControlPressed(0, controls.backward) then
                moveDelta = moveDelta - forward
            end

            if IsDisabledControlPressed(0, controls.left) then
                moveDelta = moveDelta - right
            end

            if IsDisabledControlPressed(0, controls.right) then
                moveDelta = moveDelta + right
            end

            if IsDisabledControlPressed(0, controls.up) then
                moveDelta = moveDelta + vector3(0.0, 0.0, 1.0)
            end

            if IsDisabledControlPressed(0, controls.down) then
                moveDelta = moveDelta - vector3(0.0, 0.0, 1.0)
            end

            if IsDisabledControlJustPressed(0, controls.faster) then
                freecamState.speed = clampSpeed(freecamState.speed + 0.25)
                sendClientLog('freecam_speed_changed', { speed = freecamState.speed })
            end

            if IsDisabledControlJustPressed(0, controls.slower) then
                freecamState.speed = clampSpeed(freecamState.speed - 0.25)
                sendClientLog('freecam_speed_changed', { speed = freecamState.speed })
            end

            if IsDisabledControlJustPressed(0, controls.togglePov) then
                setFreecamPov(not freecamState.pov)
            end

            if IsDisabledControlJustPressed(0, controls.toggleFilter) then
                setFreecamFilter(not freecamState.filter)
            end

            if IsDisabledControlJustPressed(0, controls.exit) then
                stopFreecam('exit_control')
            end

            if #(moveDelta) > 0.0 then
                moveDelta = moveDelta / #(moveDelta)
                freecamState.coords = freecamState.coords + (moveDelta * freecamState.speed * GetFrameTime() * 60.0)
            end

            local maxDistance = tonumber(freecamConfig.FreecamMaxDistance) or 100.0

            if getDistanceFromPlayer() > maxDistance then
                local playerCoords = GetEntityCoords(PlayerPedId())
                local direction = freecamState.coords - playerCoords
                local normalized = direction / #(direction)
                freecamState.coords = playerCoords + (normalized * maxDistance)
            end

            SetCamCoord(freecamState.camera, freecamState.coords.x, freecamState.coords.y, freecamState.coords.z)
            SetCamRot(freecamState.camera, freecamState.rotation.x, freecamState.rotation.y, freecamState.rotation.z, 2)
        end
    end
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    -- Role: clean up freecam state when the resource stops.
    -- Params: stoppedResource (string).
    -- Return: none.
    -- Behavior: safely restores camera rendering during reloads.
    -- Security: only reacts to this resource stopping.
    if stoppedResource ~= resourceName then
        return
    end

    stopFreecam('resource_stop')
end)
