fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'blacklist_carnival'
author 'Blacklist RP'
description 'Carnival of the Damned - six-attraction carnival event with rotation, scoring and management panels'
version '1.0.0'

dependencies {
    'oxmysql',
    'ox_lib',
    'qbx_core',
    'ox_target',
    'ox_inventory',
}


shared_scripts {
    '@ox_lib/init.lua',
    'shared/constants.lua',
    'shared/utils.lua',
    'shared/schema.lua',
    'shared/defaults.lua',
    'shared/validation.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'consumables.lua',
    'server/main.lua',
    'server/persistence.lua',
    'server/monitoring.lua',
    'server/discord.lua',
    'server/audit.lua',
    'server/identity.lua',
    'server/permissions.lua',
    'server/api.lua',
    'server/push.lua',
    'server/config_manager.lua',
    'server/inventory.lua',
    'server/prizes.lua',
    'server/event_manager.lua',
    'server/registration.lua',
    'server/group_manager.lua',
    'server/ticket_manager.lua',
    'server/scoring.lua',
    'server/rewards.lua',
    'server/leaderboard.lua',
    'server/rotation_manager.lua',
    'server/attraction_registry.lua',
    'server/attractions/shooting.lua',
    'server/attractions/wheel.lua',
    'server/attractions/fortune.lua',
    'server/attractions/puppets.lua',
    'server/attractions/deception.lua',
    'server/attractions/horror.lua',
    'server/props.lua',
    'server/layout.lua',
    'server/shop.lua',
    'server/consumables.lua',
    'server/setup.lua',
    'server/admin_api.lua',
    'server/commands.lua',
    'server/exports.lua',
}

client_scripts {
    'client/main.lua',
    'client/audio.lua',
    'client/interactions.lua',
    'client/tickets.lua',
    'client/participants.lua',
    'client/rotation.lua',
    'client/leaderboard.lua',
    'client/attractions/shooting.lua',
    'client/attractions/wheel.lua',
    'client/attractions/fortune.lua',
    'client/attractions/puppets.lua',
    'client/attractions/deception.lua',
    'client/attractions/horror.lua',
    'client/props.lua',
    'client/layout.lua',
    'client/shop.lua',
    'client/consumables.lua',
    'client/ambience.lua',
    'client/preview.lua',
}

ui_page 'web/dist/index.html'

-- Props streamed from stream/props/ (.ydr model, .ytd textures, .ytyp archetype):
-- the House of Horrors coins and anything placed with the prop placer. Every
-- .ytyp in that folder is loaded, so new props only need their files dropped in.
data_file 'DLC_ITYP_REQUEST' 'stream/props/*.ytyp'

-- NUI files sent to every player. Without these the interface never loads and
-- no carnival screen can open.
files {
    'locales/*.json',
    'web/dist/index.html',
    'web/dist/assets/*',
    'web/dist/sounds/*',
    'web/dist/backgrounds/*',
}
