-- Local sound playback through the NUI (bundled .ogg files in web/public/sounds).
-- Nothing is streamed from external URLs.

local function masterVolume()
    local s = Carnival.Client.settings
    return s and s.audio and s.audio.masterVolume or 0.6
end

function Carnival.playSound(name, volume, loop)
    if type(name) ~= 'string' or name == '' then return end
    Carnival.nui('audio', { action = 'play', sound = name, volume = (volume or 1.0) * masterVolume(), loop = loop == true })
end

function Carnival.stopSound(name)
    Carnival.nui('audio', { action = 'stop', sound = name })
end

function Carnival.stopAllSounds()
    Carnival.nui('audio', { action = 'stopAll' })
end

Carnival.onCleanup(function() Carnival.stopAllSounds() end)
