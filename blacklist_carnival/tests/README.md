# Tests

| Suite | File | Needs |
|---|---|---|
| Static checks | `static_checks.lua` | lua5.4, lua-dkjson |
| Server integration (real server scripts + real database) | `server_spec.lua` + `harness.lua` | lua5.4, lua-sql-mysql, lua-dkjson, MariaDB/MySQL |
| NUI (jsdom) | `web/src/__tests__/nui.test.tsx` | Node 18+, `npm ci` in `web/` |

## Database for the integration tests

The suite **drops every table** in the configured database. Use a throwaway database:

```sql
CREATE DATABASE carnival_test;
CREATE USER 'carnival'@'localhost' IDENTIFIED BY 'carnival';
GRANT ALL ON carnival_test.* TO 'carnival'@'localhost';
```

Override with `CARNIVAL_DB_NAME`, `CARNIVAL_DB_USER`, `CARNIVAL_DB_PASS`, `CARNIVAL_DB_HOST`, `CARNIVAL_DB_PORT`. Set `CARNIVAL_TEST_VERBOSE=1` to see server console output.

## Run

```bash
cd blacklist_carnival
./tests/run_all.sh
```

`harness.lua` loads the scripts listed in `fxmanifest.lua` with a virtual clock and coroutine scheduler (so timers can be fast-forwarded), an oxmysql-compatible adapter over luasql-mysql (including TINYINT(1)→boolean like oxmysql), and fakes for qbx_core, ox_inventory, ox_lib callbacks, ACE, players and peds.

`export_schema.lua` regenerates the NUI test fixture from the Lua schema/defaults:
`lua5.4 tests/export_schema.lua > web/src/__tests__/fixture.json`
