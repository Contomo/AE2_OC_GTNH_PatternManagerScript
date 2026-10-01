package.path = 'tests/lib/?.lua;' .. package.path
local B = require('assline_batch')
local Config = require('assline_config')
local U = require('assline_util')
local tests = 0
local function test(name, f)
  f(); tests = tests + 1; print('PASS ' .. name)
end
local function policy()
  return U.clone(Config.defaults.batch)
end

test('voltage boundaries follow the pinned GT tiers, including OpV and MAX', function()
  assert(B.voltageTier(0) == 'ULV' and B.voltageTier(8) == 'ULV')
  assert(B.voltageTier(9) == 'LV' and B.voltageTier(32) == 'LV')
  assert(B.voltageTier(33) == 'MV' and B.voltageTier(32768) == 'LuV')
  assert(B.voltageTier(2147483640) == 'OpV' and B.voltageTier(2147483641) == 'MAX')
  assert(B.voltageTier(nil) == nil and B.voltageTier(-1) == nil)
end)
test('relative curve shifts automatically while absolute overrides stay fixed', function()
  local p = policy()
  assert(B.budget(p, 'LuV') == 4 and B.budget(p, 'IV') == 32)
  assert(B.budget(p, 'EV') == 64 and B.budget(p, 'UV') == 1)
  p.overrideULV = '4096'
  p.currentTier = 'ZPM'
  assert(B.budget(p, 'LuV') == 32 and B.budget(p, 'IV') == 64)
  assert(B.budget(p, 'ULV') == 4096)
  p.currentTier = 'MAX'
  assert(B.budget(p, 'ULV') == 4096 and B.budget(p, 'LV') == 512)
end)
test('cheap processing never increases a high-tier material budget', function()
  local p = policy(); p.currentTier = 'UHV'
  local n, why = B.resolve(p, 'UHV', 128, 1)
  assert(n == 4 and why.materialBudget == 4 and why.voltageBudget == 512)
  p.overrideUHV = '2'
  assert(B.resolve(p, 'UHV', 8, 1) == 2)
end)
test('voltage constraint can lower a cheap material batch and is adjustable', function()
  local p = policy()
  assert(B.resolve(p, 'ULV', 32768, 1) == 4)
  p.voltagePolicy = 'off'
  assert(B.resolve(p, 'ULV', 32768, 1) == 448)
  p.voltagePolicy = 'cap'; p.voltageTier = 'IV'
  assert(B.resolve(p, 'ULV', 32768, 1) == 1)
end)
test('unknown material and missing voltage use explicit conservative fallbacks', function()
  local p = policy()
  assert(B.resolve(p, nil, 8, 1) == 1)
  assert(B.resolve(p, 'ULV', nil, 1) == 1)
  p.unknownMultiplier = '3'
  assert(B.resolve(p, nil, 8, 1) == 3)
end)
test('item and fluid limits shrink the common whole-recipe multiplier', function()
  local p = policy(); p.overrideULV = '4096'; p.maxMultiplier = '4096'
  p.voltagePolicy = 'off'
  local n = B.resolve(p, 'ULV', 8, 1, {{type='item',size=9}, {type='item',size=1}})
  assert(n == 455 and 9*n <= 4096 and 9*(n+1) > 4096)
  p.fluidLimit = '10000'
  n = B.resolve(p, 'ULV', 8, 1, {{type='fluid',size=864}, {type='item',size=1}})
  assert(n == 11 and n*864 == 9504)
  assert(not pcall(B.resolve, p, 'ULV', 8, 1, {{type='fluid',size=10001}}))
end)
test('program factors obey the final ceiling and fixed mode preserves old batches', function()
  local p = policy()
  assert(B.resolve(p, 'LuV', 8, 4) == 16)
  assert(B.resolve(p, 'ULV', 8, 256) == 512)
  p.mode = 'fixed'
  assert(B.resolve(p, nil, nil, 1024, {{type='fluid',size=864}}) == 1024)
end)
test('migration preserves existing fixed multipliers and new settings persist', function()
  local old = U.clone(Config.defaults); old.batch = nil
  old.programs.wiremill.multiplier = '256'
  local c = Config.migrate(old)
  assert(c.batch.mode == 'fixed' and c.programs.wiremill.multiplier == '256')
  c.batch.mode = 'tiered'; c.batch.currentTier = 'UV'; c.batch.overrideUHV = '2'
  assert(U.eq(Config.migrate(c), c))
  c.batch.overrideUHV = '0.5'
  assert(not pcall(Config.validate, c))
end)
test('numeric shorthand normalizes centrally without altering names or blank overrides', function()
  local c = U.clone(Config.defaults)
  c.shared.editor = '4k'
  c.shared.energyPause = '0.025K'
  c.batch.itemLimit = '4k'
  c.batch.fluidLimit = '4M'
  c.batch.overrideULV = '1.5K'
  c.batch.overrideLV = '2m'
  c.programs.wiremill.multiplier = '1.5k'
  c = Config.migrate(c)
  assert(c.shared.editor == '4k' and c.shared.energyPause == '25')
  assert(c.batch.itemLimit == '4000' and c.batch.fluidLimit == '4000000')
  assert(c.batch.overrideULV == '1500' and c.batch.overrideLV == '2000000')
  assert(c.batch.overrideMV == '' and c.programs.wiremill.multiplier == '1500')
  assert(U.eq(Config.normalize(U.clone(c)), c))
  assert(B.resolve(c.batch, 'ULV', 8, 1, {{type='item',size=2}}) == 448)
end)

test('shorthand retains numeric validation for malformed, fractional and excessive values', function()
  for _, value in ipairs({'4kk', '4MB', 'k', '0k', '-1k', '0.0001k', '2147.483648M', '1e309M'}) do
    local c = U.clone(Config.defaults)
    c.batch.itemLimit = value
    assert(not pcall(Config.migrate, c), 'Unexpectedly accepted: ' .. value)
  end
  local c = U.clone(Config.defaults)
  c.shared.energyPause = '4k'
  assert(not pcall(Config.migrate, c))
end)

print('SUCCESS: ' .. tests .. ' tests')
