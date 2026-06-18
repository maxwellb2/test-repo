-- Standalone headless test runner (plain Lua 5.1+/LuaJIT).
-- Usage:  lua balatro-copy/tests/run.lua   (or: cd balatro-copy && lua tests/run.lua)
-- For LOVE-based running (no system Lua needed):  love balatro-copy test

local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = here .. "/../?.lua;" .. package.path

local cases = require("tests.cases")
local _, failed = cases.run(print)
os.exit(failed == 0 and 0 or 1)
