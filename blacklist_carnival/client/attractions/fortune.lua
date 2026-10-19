-- Fortune Teller client: opens the fortune NUI for automated visits and for
-- questions/fortunes presented by staff. Answers are marked by the server.

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
    if data.action == 'question' then
        Carnival.openView('fortune', { visitId = data.visitId, question = data.question, greeting = data.greeting, staffLed = true })
    elseif data.action == 'fortune' then
        Carnival.openView('fortuneCard', { text = data.text }, { focus = false })
        Carnival.playSound('carnival_chime', 0.6)
        SetTimeout(15000, function() Carnival.closeView('fortuneCard') end)
    elseif data.action == 'close' then
        Carnival.closeView('fortune')
    end
end)
