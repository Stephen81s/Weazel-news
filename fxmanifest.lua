fx_version 'cerulean'
game 'gta5'

lua54 'yes'

ui_page 'nui/import.html'

files {
    'configs/freecam_config.json',
    'configs/weazel_config.json',
    'configs/weazel_shops.json',
    'nui/import.html',
    'nui/reader.html',
    'nui/styles.css',
    'nui/script.js'
}

client_scripts {
    'client/freecam.lua',
    'client/nui_reader.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/freecam_permissions.lua',
    'server/journal_import.lua',
    'server/journal_publish.lua',
    'server/journal_sales.lua'
}
