-- lib/arrangement_ops.lua: pure operations over parsed Arrangements.

local ops = require("lib.arrangement_ops")
local sidecar = require("lib.sidecar")

local function arrangements()
  return assert(sidecar.parse([[
return {
  ["Live"] = { { "A", headroom = 2 }, "B", { "C", headroom = -1 } },
  ["Empty"] = {},
}
]]))
end

local function order(arrangement)
  return { table.unpack(arrangement) }
end

describe("lib/arrangement_ops.lua", function()
  it("never changes the table it is given", function()
    local before = arrangements()
    ops.move(before, "Live", "A", 3)
    ops.set_headroom(before, "Live", "A", 9)
    ops.remove(before, "Live", "B")
    ops.delete(before, "Live")
    assert.are.same(arrangements(), before)
  end)

  describe("move", function()
    it("moves a region to a slot and keeps its Headroom", function()
      local result = ops.move(arrangements(), "Live", "A", 3)
      assert.are.same({ "B", "C", "A" }, order(result.Live))
      assert.are.equal(2, result.Live.headroom.A)
    end)

    it("moves up as well as down", function()
      assert.are.same({ "C", "A", "B" }, order(ops.move(arrangements(), "Live", "C", 1).Live))
    end)

    it("refuses an unknown region, a bad slot and an unknown Arrangement", function()
      assert.are.same({ nil, "region_not_in_arrangement" }, { ops.move(arrangements(), "Live", "Z", 1) })
      assert.are.same({ nil, "slot_invalid" }, { ops.move(arrangements(), "Live", "A", 4) })
      assert.are.same({ nil, "slot_invalid" }, { ops.move(arrangements(), "Live", "A", 0) })
      assert.are.same({ nil, "slot_invalid" }, { ops.move(arrangements(), "Live", "A", 1.5) })
      assert.are.same({ nil, "arrangement_not_found" }, { ops.move(arrangements(), "Nope", "A", 1) })
    end)
  end)

  describe("set_headroom", function()
    it("sets a positive, zero or negative Headroom", function()
      assert.are.equal(4.5, ops.set_headroom(arrangements(), "Live", "B", 4.5).Live.headroom.B)
      assert.are.equal(0, ops.set_headroom(arrangements(), "Live", "A", 0).Live.headroom.A)
      assert.are.equal(-3, ops.set_headroom(arrangements(), "Live", "B", -3).Live.headroom.B)
    end)

    it("refuses a value that is not a finite number", function()
      for _, bad in ipairs({ math.huge, -math.huge, 0 / 0, "4", true }) do
        assert.are.same({ nil, "headroom_invalid" }, { ops.set_headroom(arrangements(), "Live", "A", bad) })
      end
    end)

    it("refuses a region that is not in the Arrangement", function()
      assert.are.same({ nil, "region_not_in_arrangement" },
        { ops.set_headroom(arrangements(), "Live", "Z", 1) })
    end)
  end)

  describe("add", function()
    it("appends by default, with Headroom 0", function()
      local result = ops.add(arrangements(), "Live", "D")
      assert.are.same({ "A", "B", "C", "D" }, order(result.Live))
      assert.are.equal(0, result.Live.headroom.D)
    end)

    it("inserts at a slot, including the first and one past the end", function()
      assert.are.same({ "D", "A", "B", "C" }, order(ops.add(arrangements(), "Live", "D", 1).Live))
      assert.are.same({ "A", "B", "C", "D" }, order(ops.add(arrangements(), "Live", "D", 4).Live))
    end)

    it("refuses a repeated region, an empty name and a bad slot", function()
      assert.are.same({ nil, "region_repeated" }, { ops.add(arrangements(), "Live", "A") })
      assert.are.same({ nil, "region_empty" }, { ops.add(arrangements(), "Live", "") })
      assert.are.same({ nil, "slot_invalid" }, { ops.add(arrangements(), "Live", "D", 5) })
    end)

    it("fills an empty Arrangement", function()
      assert.are.same({ "A" }, order(ops.add(arrangements(), "Empty", "A").Empty))
    end)
  end)

  describe("remove", function()
    it("removes a region and its Headroom", function()
      local result = ops.remove(arrangements(), "Live", "A")
      assert.are.same({ "B", "C" }, order(result.Live))
      assert.is_nil(result.Live.headroom.A)
    end)

    it("may leave the Arrangement empty", function()
      local result = ops.remove(ops.remove(ops.remove(arrangements(), "Live", "A"), "Live", "B"),
        "Live", "C")
      assert.are.same({}, order(result.Live))
    end)

    it("refuses a region that is not there", function()
      assert.are.same({ nil, "region_not_in_arrangement" }, { ops.remove(arrangements(), "Live", "Z") })
    end)
  end)

  describe("clear_headroom", function()
    it("zeroes every Headroom of one Arrangement and keeps the order", function()
      local result = ops.clear_headroom(arrangements(), "Live")
      assert.are.same({ "A", "B", "C" }, order(result.Live))
      assert.are.same({ A = 0, B = 0, C = 0 }, result.Live.headroom)
    end)

    it("refuses an unknown Arrangement", function()
      assert.are.same({ nil, "arrangement_not_found" }, { ops.clear_headroom(arrangements(), "Nope") })
    end)
  end)

  describe("new", function()
    it("adds an empty Arrangement to nothing at all", function()
      local result = ops.new({}, "Fresh")
      assert.are.same({}, order(result.Fresh))
    end)

    it("refuses a taken or empty name", function()
      assert.are.same({ nil, "name_taken" }, { ops.new(arrangements(), "Live") })
      assert.are.same({ nil, "name_empty" }, { ops.new(arrangements(), "") })
    end)
  end)

  describe("duplicate", function()
    it("copies order and Headroom, independently of the original", function()
      local result = ops.duplicate(arrangements(), "Live", "Copy")
      assert.are.same({ "A", "B", "C" }, order(result.Copy))
      assert.are.equal(2, result.Copy.headroom.A)
      result.Copy.headroom.A = 99
      assert.are.equal(2, result.Live.headroom.A)
    end)

    it("refuses a taken or empty name and an unknown source", function()
      assert.are.same({ nil, "name_taken" }, { ops.duplicate(arrangements(), "Live", "Empty") })
      assert.are.same({ nil, "name_taken" }, { ops.duplicate(arrangements(), "Live", "Live") })
      assert.are.same({ nil, "name_empty" }, { ops.duplicate(arrangements(), "Live", "") })
      assert.are.same({ nil, "arrangement_not_found" }, { ops.duplicate(arrangements(), "Nope", "X") })
    end)
  end)

  describe("rename", function()
    it("moves the Arrangement to its new name", function()
      local result = ops.rename(arrangements(), "Live", "Show")
      assert.is_nil(result.Live)
      assert.are.same({ "A", "B", "C" }, order(result.Show))
      assert.are.equal(-1, result.Show.headroom.C)
    end)

    it("refuses a taken or empty name and an unknown source", function()
      assert.are.same({ nil, "name_taken" }, { ops.rename(arrangements(), "Live", "Empty") })
      assert.are.same({ nil, "name_empty" }, { ops.rename(arrangements(), "Live", "") })
      assert.are.same({ nil, "arrangement_not_found" }, { ops.rename(arrangements(), "Nope", "X") })
    end)
  end)

  describe("delete", function()
    it("removes the Arrangement and nothing else", function()
      local result = ops.delete(arrangements(), "Live")
      assert.is_nil(result.Live)
      assert.is_not_nil(result.Empty)
    end)

    it("refuses an unknown Arrangement", function()
      assert.are.same({ nil, "arrangement_not_found" }, { ops.delete(arrangements(), "Nope") })
    end)
  end)
end)
