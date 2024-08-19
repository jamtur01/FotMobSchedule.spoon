local obj = {}
obj.__index = obj

-- Metadata
obj.name = "FotMobSchedule"
obj.version = "2.5"
obj.author = "James Turnbull <james@lovedthanlost.net>"
obj.homepage = "https://github.com/jamtur01/FotMobSchedule.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

obj.logger = hs.logger.new('FotMobSchedule', 'info')
obj.interval = 3600
obj.baseUrl = "https://www.fotmob.com"
obj.apiBaseUrl = "https://www.fotmob.com/api/"
obj.menuBar = nil
obj.lastSchedule = nil

-- Load saved settings or use defaults
obj.teams = hs.settings.get("FotMobSchedule_teams") or {
    { name = "Arsenal Women", id = 258657 }
}
obj.showNextGames = hs.settings.get("FotMobSchedule_showNextGames") or 1  -- Default to showing only the next game

local function fetchData(url)
    obj.logger.d("Fetching data from URL: " .. url)
    local status, body, headers = hs.http.get(url)
    if status ~= 200 then
        obj.logger.ef("Failed to fetch data from %s. Status: %d", url, status)
        return nil
    end
    return hs.json.decode(body)
end

local function formatDate(utcTime)
    if type(utcTime) == "string" then
        local year, month, day, hour, min = utcTime:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
        if year then
            local timestamp = os.time({year=year, month=month, day=day, hour=hour, min=min})
            return os.date("%a %b %d", timestamp)
        end
    elseif type(utcTime) == "number" then
        return os.date("%a %b %d", utcTime / 1000)
    end
    return "Date unknown"
end

local function processSchedule(teamData)
    obj.logger.d("Processing schedule for team: " .. teamData.details.name)
    local schedule = {}
    if teamData and teamData.fixtures and teamData.fixtures.allFixtures and teamData.fixtures.allFixtures.fixtures then
        local fixtures = teamData.fixtures.allFixtures.fixtures
        for _, fixture in ipairs(fixtures) do
            local opponent = fixture.opponent.name
            local matchDisplay = string.format("%s vs %s", teamData.details.name, opponent)
            table.insert(schedule, {
                date = formatDate(fixture.status.utcTime),
                match = matchDisplay,
                home = fixture.home.id == teamData.details.id,
                url = obj.baseUrl .. fixture.pageUrl
            })
        end
    else
        obj.logger.w("No fixtures found or unexpected data structure")
    end
    obj.logger.d("Processed " .. #schedule .. " fixtures")
    return schedule
end

function obj:fetchSchedule()
    obj.logger.d("Starting to fetch schedules")
    local allSchedules = {}
    for _, team in ipairs(self.teams) do
        obj.logger.d("Fetching schedule for team: " .. team.name)
        local url = self.apiBaseUrl .. "teams?id=" .. team.id
        local data = fetchData(url)
        if data then
            allSchedules[team.name] = processSchedule(data)
        else
            obj.logger.e("Failed to fetch data for team: " .. team.name)
        end
    end
    obj.logger.d("Finished fetching schedules")
    self.lastSchedule = allSchedules
    return allSchedules
end

local function showNotifications(schedules)
    for team, schedule in pairs(schedules) do
        for i, match in ipairs(schedule) do
            if i > obj.showNextGames then
                break  -- Stop after showing the configured number of games
            end
            hs.timer.doAfter(i * 2, function()  -- Delay each notification by 2 seconds
                local notification = hs.notify.new(function()
                    hs.urlevent.openURL(match.url)
                end)
                :title(team)
                :subTitle(match.date)
                :informativeText(match.match .. " (" .. (match.home and "Home" or "Away") .. ")")
                :actionButtonTitle("Open")
                :hasActionButton(true)
                :withdrawAfter(0)  -- Don't automatically withdraw
                
                notification:send()
            end)
        end
    end
end

local function showSchedule()
    showNotifications(obj.lastSchedule or obj:fetchSchedule())
end

function obj:setNumGames()
    hs.chooser.new(function(choice)
        if choice then
            self:setNextGamesCount(tonumber(choice.text))
            hs.notify.new({title="FotMob Schedule", informativeText="Number of games to show set to " .. self.showNextGames}):send()
        end
    end)
    :choices({
        {text = "1"}, {text = "2"}, {text = "3"}, {text = "4"}, {text = "5"}
    })
    :placeholderText("Select number of games to show")
    :show()
end

function obj:setTeams()
    hs.chooser.new(function(choice)
        if choice then
            local teams = {}
            for team in string.gmatch(choice.text, '([^,]+)') do
                local trimmedTeam = team:match("^%s*(.-)%s*$")  -- Trim whitespace
                local teamId = self:getTeamIdByName(trimmedTeam)
                if teamId then
                    table.insert(teams, { name = trimmedTeam, id = teamId })
                end
            end
            if #teams > 0 then
                self.teams = teams
                hs.settings.set("FotMobSchedule_teams", teams)  -- Save the selected teams
                hs.notify.new({title="FotMob Schedule", informativeText="Teams set to: " .. table.concat(choice.text, ", ")}):send()
            else
                hs.notify.new({title="FotMob Schedule", informativeText="No valid teams found. Please try again."}):send()
            end
        end
    end)
    :choices({
        {text = "Arsenal Women"}, {text = "Chelsea Women"}, {text = "Manchester City Women"}, {text = "Manchester United Women"}
        -- Add more teams here as needed
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

function obj:start()
    obj.logger.i("Starting FotMobSchedule")
    
    if not self.menuBar then
        self.menuBar = hs.menubar.new()
        self.menuBar:setTitle("F")
        self.menuBar:setMenu({
            {title = "Show Schedule", fn = function() showSchedule() end},
            {title = "Set Teams", fn = function() self:setTeams() end},
            {title = "Set Number of Games", fn = function() self:setNumGames() end},
        })
    end
    
    self.timer = hs.timer.new(self.interval, function() self:fetchSchedule() end)
    self.timer:start()
    
    -- Initial fetch
    self:fetchSchedule()
    
    return self
end

function obj:stop()
    obj.logger.i("Stopping FotMobSchedule")
    if self.timer then
        self.timer:stop()
    end
    if self.menuBar then
        self.menuBar:delete()
        self.menuBar = nil
    end
    return self
end

function obj:setNextGamesCount(count)
    if type(count) == "number" and count > 0 then
        self.showNextGames = count
        hs.settings.set("FotMobSchedule_showNextGames", count)  -- Save the number of games to show
        obj.logger.d("Set to show next " .. count .. " games")
    else
        obj.logger.e("Invalid game count. Please provide a positive number.")
    end
end

return obj
