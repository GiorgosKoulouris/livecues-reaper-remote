-- A minimal fake REAPER for the bridge specs: only what the service front end reads so far (the project path).
local fake_project = {}

function fake_project.new(spec)
  local api = {}
  function api.EnumProjects() return nil, spec.path or "" end
  return api
end

return fake_project
