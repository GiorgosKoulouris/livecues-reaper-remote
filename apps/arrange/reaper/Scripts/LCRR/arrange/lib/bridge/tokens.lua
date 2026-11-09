-- Check tokens: what ties an Apply to the Check the user just read.
--
-- A Check that would proceed mints a short token, and the bridge keeps what
-- the Check saw: the Arrangement name, the project's path and its state-change
-- count. An Apply request carries only the token (and the Headroom answer), so
-- the page cannot apply something it never checked, and the bridge can tell
-- when the project has moved on since (the count differs), when another
-- project tab is active (the path differs), when the screen is stale or the
-- button was pressed twice (the token is gone) and when the bridge was
-- restarted (the store is in memory only).
--
-- Not a security feature: REAPER's web interface has no authentication to
-- protect. It is a guard against mistakes.

local tokens = {}

-- Enough for a person flipping between a few Arrangements, small enough that
-- an old screen's token is gone.
tokens.CAPACITY = 16

local ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"

local function make_token(random)
  local chars = {}
  for index = 1, 6 do
    local at = random(#ALPHABET)
    chars[index] = ALPHABET:sub(at, at)
  end
  return table.concat(chars)
end

--- A token store.
-- @param random function(n) -> integer in 1..n (injected for specs)
function tokens.new(random)
  random = random or math.random
  local store = { entries = {}, order = {} }

  --- Remember what a Check saw, and return its token.
  -- @param entry table { name, path, changes }
  function store.issue(entry)
    local token = make_token(random)
    while store.entries[token] do
      token = make_token(random)
    end
    store.entries[token] = entry
    store.order[#store.order + 1] = token
    while #store.order > tokens.CAPACITY do
      store.entries[table.remove(store.order, 1)] = nil
    end
    return token
  end

  --- What a token stands for, or nil when it is unknown.
  function store.get(token)
    return store.entries[token]
  end

  --- Forget a token. Safe on one that is already gone.
  function store.drop(token)
    if not store.entries[token] then
      return
    end
    store.entries[token] = nil
    for index, held in ipairs(store.order) do
      if held == token then
        table.remove(store.order, index)
        break
      end
    end
  end

  return store
end

return tokens
