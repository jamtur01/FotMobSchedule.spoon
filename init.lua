local obj = {}
obj.__index = obj

-- Metadata
obj.name = "FotMobSchedule"
obj.version = "2.7"
obj.author = "James Turnbull <james@lovedthanlost.net>"
obj.homepage = "https://github.com/jamtur01/FotMobSchedule.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Constants
local DEFAULT_INTERVAL = 3600
local BASE_URL = "https://www.fotmob.com"
local API_BASE_URL = "https://www.fotmob.com/api/"
local DEFAULT_TEAM = { name = "Arsenal Women", id = 258657 }
local DEFAULT_SHOW_NEXT_GAMES = 5
local DEFAULT_SHOW_LAST_GAMES = 5

-- Configuration
obj.logger = hs.logger.new('FotMobSchedule', 'info')
obj.interval = DEFAULT_INTERVAL
obj.menuBar = nil
obj.lastSchedule = nil
obj.teams = hs.settings.get("FotMobSchedule_teams") or { DEFAULT_TEAM }
obj.showNextGames = hs.settings.get("FotMobSchedule_showNextGames") or DEFAULT_SHOW_NEXT_GAMES
obj.showLastGames = hs.settings.get("FotMobSchedule_showLastGames") or DEFAULT_SHOW_LAST_GAMES

-- Helper functions
local function fetchData(url, callback)
    obj.logger.d("Fetching data from URL: " .. url)
    hs.http.asyncGet(url, nil, function(status, body, headers)
        if status ~= 200 then
            obj.logger.ef("Failed to fetch data from %s. Status: %d", url, status)
            callback(nil)
        else
            callback(hs.json.decode(body))
        end
    end)
end

local function formatDate(utcTime)
    if type(utcTime) == "string" then
        local year, month, day, hour, min = utcTime:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
        if year then
            local timestamp = os.time({year=year, month=month, day=day, hour=hour, min=min})
            return os.date("%a %b %d, %I:%M %p", timestamp)
        end
    elseif type(utcTime) == "number" then
        return os.date("%a %b %d, %I:%M %p", utcTime / 1000)
    end
    return "Date unknown"
end

local function processSchedule(teamData)
    obj.logger.d("Processing schedule for team: " .. teamData.details.name)
    local schedule = {}
    local fixtures = teamData.fixtures and teamData.fixtures.allFixtures and teamData.fixtures.allFixtures.fixtures
    if fixtures then
        for _, fixture in ipairs(fixtures) do
            local dateStr = fixture.status.utcTime
            local timestamp = nil
            if dateStr and type(dateStr) == "string" then
                local year, month, day, hour, min = dateStr:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
                if year then
                    timestamp = os.time({year=year, month=month, day=day, hour=hour, min=min})
                end
            end
            table.insert(schedule, {
                date = formatDate(fixture.status.utcTime),
                match = string.format("%s vs %s", teamData.details.name, fixture.opponent.name),
                home = fixture.home.id == teamData.details.id,
                url = BASE_URL .. fixture.pageUrl,
                finished = fixture.status.finished,
                result = fixture.status.scoreStr,
                timestamp = timestamp
            })
        end
    else
        obj.logger.w("No fixtures found or unexpected data structure")
    end
    obj.logger.d("Processed " .. #schedule .. " fixtures")
    return schedule
end

-- Main functions
function obj:fetchSchedule(callback)
    obj.logger.d("Starting to fetch schedules")
    local allSchedules = {}
    local remainingTeams = #self.teams

    for _, team in ipairs(self.teams) do
        obj.logger.d("Fetching schedule for team: " .. team.name)
        fetchData(API_BASE_URL .. "teams?id=" .. team.id, function(data)
            if data then
                allSchedules[team.name] = processSchedule(data)
            else
                obj.logger.e("Failed to fetch data for team: " .. team.name)
            end
            remainingTeams = remainingTeams - 1
            if remainingTeams == 0 then
                obj.logger.d("Finished fetching schedules")
                self.lastSchedule = allSchedules
                callback(allSchedules)
            end
        end)
    end
end

function obj:updateMenu()
    self:fetchSchedule(function(schedules)
        if not schedules then
            hs.notify.new({title="FotMob Schedule Error", informativeText="Failed to fetch FotMob schedule"}):send()
            return
        end

        local menuItems = {}
        local matches = {}

        -- Collect all matches into a single list
        for team, schedule in pairs(schedules) do
            for _, match in ipairs(schedule) do
                table.insert(matches, match)
            end
        end

        -- Sort matches by timestamp
        table.sort(matches, function(a, b)
            return a.timestamp < b.timestamp
        end)

        -- Separate past and future matches
        local pastMatches = {}
        local futureMatches = {}
        local now = os.time()
        for _, match in ipairs(matches) do
            if match.timestamp and match.timestamp < now and match.finished then
                table.insert(pastMatches, match)
            elseif match.timestamp and match.timestamp >= now then
                table.insert(futureMatches, match)
            end
        end

        -- Add last N past matches
        local numPastMatches = self.showLastGames or self.showNextGames
        if numPastMatches > 0 and #pastMatches > 0 then
            table.insert(menuItems, { title = "Previous Games", disabled = true })
            for i = math.max(#pastMatches - numPastMatches + 1,1), #pastMatches do
                local match = pastMatches[i]
                local title = string.format("%s - %s", match.match, match.result or "N/A")
                table.insert(menuItems, {
                    title = title,
                    fn = function() hs.urlevent.openURL(match.url) end,
                    tooltip = match.date
                })
            end
            table.insert(menuItems, { title = "-" })
        end

        local numFutureMatches = self.showNextGames
        if numFutureMatches > 0 and #futureMatches > 0 then
            table.insert(menuItems, { title = "Upcoming Games", disabled = true })
            for i = 1, math.min(numFutureMatches, #futureMatches) do
                local match = futureMatches[i]
                local title = string.format("%s - %s", match.match, match.date)
                table.insert(menuItems, {
                    title = title,
                    fn = function() hs.urlevent.openURL(match.url) end,
                    tooltip = match.date
                })
            end
        end

        if #menuItems == 0 then
            table.insert(menuItems, {title = "No games found"})
        end

        self.menuBar:setMenu(menuItems)
    end)
end

function obj:start()
    obj.logger.d("Starting FotMobSchedule")
    if not self.menuBar then
        self.menuBar = hs.menubar.new()
        local iconPath = hs.spoons.resourcePath("fotmob-icon.png")
        local iconImage = hs.image.imageFromPath(iconPath)
        if not self.menuBar:setIcon(iconImage) then
            self.menuBar:setTitle("F")
        end
        self.menuBar:setTooltip("FotMob Schedule")
    end
    
    self:updateMenu()
    self.timer = hs.timer.new(self.interval, function() self:updateMenu() end)
    self.timer:start()
    return self
end

function obj:stop()
    obj.logger.i("Stopping FotMobSchedule")
    if self.timer then self.timer:stop() end
    if self.menuBar then
        self.menuBar:delete()
        self.menuBar = nil
    end
    return self
end

function obj:setTeams()
    hs.chooser.new(function(choice)
        if choice then
            local teams = {}
            for team in string.gmatch(choice.text, '([^,]+)') do
                local trimmedTeam = team:match("^%s*(.-)%s*$")
                local teamId = self:getTeamIdByName(trimmedTeam)
                if teamId then
                    table.insert(teams, { name = trimmedTeam, id = teamId })
                end
            end
            if #teams > 0 then
                self.teams = teams
                hs.settings.set("FotMobSchedule_teams", teams)
                hs.notify.new({title="FotMob Schedule", informativeText="Teams set to: " .. table.concat(choice.text, ", ")}):send()
            else
                hs.notify.new({title="FotMob Schedule", informativeText="No valid teams found. Please try again."}):send()
            end
        end
    end)
    :choices({
        {text = "Arsenal Women"}, {text = "Chelsea Women"}, {text = "Manchester City Women"}, {text = "Manchester United Women"}
    })
    :placeholderText("Enter teams (comma separated)")
    :show()
end

function obj:getTeamIdByName(teamName)
    local teamIds = {
        ["Arsenal Women"] = 258657,
        ["Chelsea Women"] = 104952,
        ["Manchester City Women"] = 205850,
        ["Manchester United Women"] = 1122357
    }
    return teamIds[teamName]
end

function obj:setNumGames()
    hs.chooser.new(function(choice)
        if choice then
            local nums = {}
            for num in string.gmatch(choice.text, '([^,]+)') do
                table.insert(nums, tonumber(num))
            end
            if #nums >= 1 then
                self:setNextGamesCount(nums[1])
            end
            if #nums >= 2 then
                self:setLastGamesCount(nums[2])
            end
            hs.notify.new({title="FotMob Schedule", informativeText="Number of games to show set to Next: " .. self.showNextGames .. ", Previous: " .. self.showLastGames}):send()
        end
    end)
    :choices({
        {text = "5,5"}, {text = "3,3"}, {text = "5,0"}, {text = "0,5"}
    })
    :placeholderText("Enter number of next,previous games (e.g., 5,5)")
    :show()
end

function obj:setNextGamesCount(count)
    if type(count) == "number" and count >= 0 then
        self.showNextGames = count
        hs.settings.set("FotMobSchedule_showNextGames", count)
        obj.logger.d("Set to show next " .. count .. " games")
    else
        obj.logger.e("Invalid next game count. Please provide a non-negative number.")
    end
end

function obj:setLastGamesCount(count)
    if type(count) == "number" and count >= 0 then
        self.showLastGames = count
        hs.settings.set("FotMobSchedule_showLastGames", count)
        obj.logger.d("Set to show last " .. count .. " games")
    else
        obj.logger.e("Invalid last game count. Please provide a non-negative number.")
    end
end

return obj
