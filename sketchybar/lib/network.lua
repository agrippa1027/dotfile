local network = {}

function network.trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function network.interface(hardware_ports)
  local is_wifi = false
  for line in tostring(hardware_ports or ""):gmatch("[^\r\n]+") do
    local port = line:match("^Hardware Port:%s*(.+)")
    if port then is_wifi = port == "Wi-Fi" or port == "AirPort" end
    local device = line:match("^Device:%s*([%w]+)")
    if is_wifi and device then return device end
  end
end

function network.quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function network.parse(data)
  local summary = tostring(data.summary or "")
  local ip = network.trim(data.ip)
  if not ip:match("^%d+%.%d+%.%d+%.%d+$") or ip == "0.0.0.0" then ip = nil end
  local ssid = network.trim(summary:match("\n%s*SSID%s*:%s*([^\r\n]+)"))
  if ssid == "" or ssid:lower() == "<redacted>" or ssid == "(null)" then ssid = nil end
  local router = summary:match("\n%s*Router%s*:%s*(%d+%.%d+%.%d+%.%d+)")
  local link = summary:match("LinkStatusActive%s*:%s*(%u+)")
  local active = link == "TRUE" or (link == nil and tostring(data.link or ""):match("status:%s*active") ~= nil)
  local state
  if not data.interface then
    state = "unavailable"
  elseif tostring(data.power or ""):match(":%s*Off%s*$") then
    state = "off"
    ip, ssid, router = nil, nil, nil
  elseif active and ip then
    state = "connected"
  elseif active then
    state = "connecting"
  else
    state = "disconnected"
    ip, ssid, router = nil, nil, nil
  end
  return { state = state, interface = data.interface, ip = ip, ssid = ssid, router = router }
end

return network
