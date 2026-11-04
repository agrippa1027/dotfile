local M = {}

-- Normalize with local noon so month/day arithmetic also survives DST changes.
local function date(year, month, day)
	local timestamp = os.time({ year = year, month = month, day = day, hour = 12 })
	return os.date("*t", timestamp), timestamp
end

function M.month(year, month, today)
	today = today or os.date("*t")
	local first, timestamp = date(year, month, 1)
	local offset = (first.wday + 5) % 7
	local result = {
		year = first.year,
		month = first.month,
		title = os.date("%B %Y", timestamp),
		weeks = {},
	}
	for week = 1, 6 do
		local _, monday = date(first.year, first.month, 1 - offset + (week - 1) * 7)
		local row = { number = os.date("%V", monday), days = {} }
		for weekday = 1, 7 do
			local day = date(first.year, first.month, 1 - offset + (week - 1) * 7 + weekday - 1)
			row.days[weekday] = {
				day = day.day,
				in_month = day.month == first.month and day.year == first.year,
				today = day.year == today.year and day.month == today.month and day.day == today.day,
			}
		end
		result.weeks[week] = row
	end
	return result
end

return M
