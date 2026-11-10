-- The specs must run under Lua 5.4, which is what REAPER embeds (see .busted).
describe("toolchain", function()
  it("runs under Lua 5.4", function()
    assert.are.equal("Lua 5.4", _VERSION)
  end)
end)
