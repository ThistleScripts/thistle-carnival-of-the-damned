-- Exports the config schema + factory defaults as JSON for the NUI tests.
-- Usage (from the resource directory): lua5.4 tests/export_schema.lua > web/src/__tests__/fixture.json
Carnival = {}
json = require('dkjson')
dofile('shared/constants.lua')
dofile('shared/utils.lua')
dofile('shared/schema.lua')
dofile('shared/defaults.lua')
io.write(json.encode({ schema = Carnival.Schema.root, defaults = Carnival.Defaults, sounds = Carnival.C.SOUNDS }))
