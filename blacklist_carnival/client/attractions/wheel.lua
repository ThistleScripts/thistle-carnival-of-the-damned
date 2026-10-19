-- Wheel of Misfortune client: opens the wheel NUI. The NUI asks the server to
-- spin (wheel.spin through the generic API bridge) and animates to the segment
-- the server chose.

local Wheel = {}
Carnival.Wheel = Wheel

function Wheel.open()
    local data, code, msg = Carnival.api('wheel.open', {})
    if not data then
        return lib.notify({ title = 'Wheel of Misfortune', description = msg or code, type = 'error' })
    end
    Carnival.openView('wheel', data)
end
