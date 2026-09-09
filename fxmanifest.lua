fx_version 'cerulean'
game 'gta5'

name 'XS-Dispatch'
description 'Multi-department live dispatch and unit tracking for QBox/QBCore'
author 'XyraL'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'bridge/framework.lua',
    'client/tracking.lua',
    'client/main.lua',
}

server_scripts {
    'bridge/framework.lua',
    'server/main.lua',
    'server/providers.lua',
    'server/units.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/extras.css',
    'html/units.css',
    'html/network.css',
    'html/layout-fixes.css',
    'html/app.js',
}

dependencies {
    'ox_lib',
}
