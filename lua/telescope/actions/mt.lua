local action_state = require"telescope.actions.state"
local state = require"telescope.state"

local action_mt = {}

--- Checks all replacement combinations to determine which function to run.
--- If no replacement can be found, then it will run the original function
local run_replace_or_original = function(replacements, original_func, ...)
  for _, replacement_map in ipairs(replacements or {}) do
    for condition, replacement in pairs(replacement_map) do
      if condition == true or condition(...) then
        return replacement(...)
      end
    end
  end

  return original_func(...)
end

action_mt.create = function(mod)
  local mt = {
    __call = function(t, ...)
      local args = {...}
      local picker = action_state.get_current_picker(args[1])
      local items = { state.get_global_key("selected_entry") or "" }

      local values = {}
      for _, action_name in ipairs(t) do
        if string.match(action_name, '^select_*')
          and picker ~= nil
          and #picker:get_multi_selection() ~= 0
        then
          items = picker:get_multi_selection()
        end

        for _, entry in ipairs(items) do
          state.set_global_key('selected_entry', entry)

          if t._pre[action_name] then
            t._pre[action_name](...)
          end

          local result = {
            run_replace_or_original(
              t._replacements[action_name],
              mod[action_name],
              ...
            )
          }
          for _, res in ipairs(result) do
            table.insert(values, res)
          end

          if t._post[action_name] then
            t._post[action_name](...)
          end
        end
      end

      return unpack(values)
    end,

    __add = function(lhs, rhs)
      local new_actions = {}
      for _, v in ipairs(lhs) do
        table.insert(new_actions, v)
      end

      for _, v in ipairs(rhs) do
        table.insert(new_actions, v)
      end

      return setmetatable(new_actions, getmetatable(lhs))
    end,

    _pre = {},
    _replacements = {},
    _post = {},
  }

  mt.__index = mt

  mt.clear = function()
    mt._pre = {}
    mt._replacements = {}
    mt._post = {}
  end

  --- Replace the reference to the function with a new one temporarily
  function mt:replace(v)
    assert(#self == 1, "Cannot replace an already combined action")

    return self:replace_map { [true] = v }
  end

  function mt:replace_if(condition, replacement)
    assert(#self == 1, "Cannot replace an already combined action")

    return self:replace_map { [condition] = replacement }
  end

  --- Replace table with
  -- Example:
  --
  -- actions.select:replace_map {
  --   [function() return filetype == 'lua' end] = actions.file_split,
  --   [function() return filetype == 'other' end] = actions.file_split_edit,
  -- }
  function mt:replace_map(tbl)
    assert(#self == 1, "Cannot replace an already combined action")

    local action_name = self[1]

    if not mt._replacements[action_name] then
      mt._replacements[action_name] = {}
    end

    table.insert(mt._replacements[action_name], 1, tbl)
    return self
  end

  function mt:enhance(opts)
    assert(#self == 1, "Cannot enhance already combined actions")

    local action_name = self[1]
    if opts.pre then
      mt._pre[action_name] = opts.pre
    end

    if opts.post then
      mt._post[action_name] = opts.post
    end

    return self
  end

  return mt
end

action_mt.transform = function(k, mt)
  return setmetatable({k}, mt)
end

action_mt.transform_mod = function(mod)
  local mt = action_mt.create(mod)

  -- Pass the metatable of the module if applicable.
  --    This allows for custom errors, lookups, etc.
  local redirect = setmetatable({}, getmetatable(mod) or {})

  for k, _ in pairs(mod) do
    redirect[k] = action_mt.transform(k, mt)
  end

  redirect._clear = mt.clear

  return redirect
end

return action_mt
