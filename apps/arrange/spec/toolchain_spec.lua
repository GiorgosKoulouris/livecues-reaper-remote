-- Guards the toolchain itself, not the suite.
--
-- Debian's lua-busted installs lua5.1 as its interpreter. If .busted loses its
-- `lua = "lua5.4"` setting, or the container is rebuilt without it, specs would
-- silently run under 5.1 -- passing here while the same code fails inside
-- REAPER, which embeds 5.4. This spec makes that regression loud.
describe("toolchain", function()
  it("runs specs under the Lua version REAPER embeds", function()
    assert.are.equal("Lua 5.4", _VERSION)
  end)

  it("accepts 5.4-only syntax", function()
    -- Integer division: a syntax error before 5.3.
    assert.are.equal(4, 9 // 2)
    -- Integer/float distinction: 5.3+ only.
    assert.are.equal("number", math.type(1) and "number")
    assert.are.equal("integer", math.type(1))
    assert.are.equal("float", math.type(1.0))
  end)
end)
