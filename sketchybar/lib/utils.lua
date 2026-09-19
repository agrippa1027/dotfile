local M = {}

function M.trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

function M.quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

return M
