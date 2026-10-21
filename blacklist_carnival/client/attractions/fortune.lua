-- Fortune Teller client: opens the fortune NUI for a reading. Answers are marked
-- by the server.

local Fortune = {}
Carnival.Fortune = Fortune

function Fortune.begin()
    local data, code, msg = Carnival.api('fortune.begin', {})
    if not data then
        return lib.notify({ title = 'The Fortune Teller', description = msg or code, type = 'error' })
    end
    Carnival.openView('fortune', data)
end

Carnival.onPush('fortune', function(data)
    if data.action == 'close' then
        Carnival.closeView('fortune')
    end
end)
