local obj = {}
obj.__index = obj

-- Metadata
obj.name = "FotMobSchedule"
obj.version = "2.9"
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
    local timestamp = nil
    if type(utcTime) == "string" then
        local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+)"
        local year, month, day, hour, min = utcTime:match(pattern)
        if year then
            timestamp = os.time({year=year, month=month, day=day, hour=hour, min=min})
        end
    elseif type(utcTime) == "number" then
        timestamp = utcTime / 1000
    end
    if timestamp then
        return os.date("%a %b %d, %I:%M %p", timestamp), timestamp
    else
        return "Date unknown", nil
    end
end

local function getMatchStatus(fixture)
    local status = fixture.status
    if status.cancelled then
        return "cancelled"
    elseif status.finished then
        return "finished"
    elseif status.started and status.ongoing then
        return "in-progress"
    elseif not status.started and not status.cancelled and not status.finished then
        local matchDate, _ = formatDate(status.utcTime)
        local today = os.date("%x", os.time())
        if matchDate and matchDate:find(today) then
            return "today"
        else
            return "upcoming"
        end
    else
        return "unknown"
    end
end

local function processSchedule(teamData)
    obj.logger.d("Processing schedule for team: " .. teamData.details.name)
    local schedule = {}
    local fixtures = teamData.fixtures and teamData.fixtures.allFixtures and teamData.fixtures.allFixtures.fixtures
    if fixtures then
        for _, fixture in ipairs(fixtures) do
            local matchDateStr, timestamp = formatDate(fixture.status.utcTime)
            local status = getMatchStatus(fixture)
            local matchTitle = string.format("%s vs %s", fixture.home.name, fixture.away.name)
            local tournamentName = fixture.tournament and fixture.tournament.name or "Unknown Tournament"
            local matchUrl = BASE_URL .. fixture.pageUrl
            local result = fixture.status.scoreStr or "Upcoming"

            local matchData = {
                date = matchDateStr,
                timestamp = timestamp,
                match = matchTitle,
                home = fixture.home,
                away = fixture.away,
                status = status,
                url = matchUrl,
                result = result,
                tournament = tournamentName,
            }

            table.insert(schedule, matchData)
        end
    else
        obj.logger.w("No fixtures found or unexpected data structure")
    end
    obj.logger.d("Processed " .. #schedule .. " fixtures")
    return schedule
end

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

        -- Group matches by tournament
        local matchesByTournament = {}
        for _, match in ipairs(matches) do
            local tournament = match.tournament
            if not matchesByTournament[tournament] then
                matchesByTournament[tournament] = {}
            end
            table.insert(matchesByTournament[tournament], match)
        end

        -- Sort tournaments alphabetically
        local sortedTournaments = {}
        for tournament in pairs(matchesByTournament) do
            table.insert(sortedTournaments, tournament)
        end
        table.sort(sortedTournaments)

        -- Build menu items
        for _, tournament in ipairs(sortedTournaments) do
            local tournamentMatches = matchesByTournament[tournament]
            table.sort(tournamentMatches, function(a, b)
                return a.timestamp < b.timestamp
            end)
            table.insert(menuItems, { title = tournament, disabled = true })
            for _, match in ipairs(tournamentMatches) do
                local icon = nil
                if match.status == "finished" then
                    icon = hs.image.imageFromName("NSStatusAvailable")
                elseif match.status == "in-progress" then
                    icon = hs.image.imageFromName("NSStatusPartiallyAvailable")
                elseif match.status == "cancelled" then
                    icon = hs.image.imageFromName("NSStatusUnavailable")
                elseif match.status == "today" then
                    icon = hs.image.imageFromName("NSTouchBarComposeTemplate")
                else
                    icon = hs.image.imageFromName("NSStatusNone")
                end

                local title = match.match
                if match.status == "finished" then
                    title = string.format("%s (%s)", title, match.result)
                elseif match.status == "in-progress" then
                    title = string.format("%s (Live)", title)
                else
                    title = string.format("%s - %s", title, match.date)
                end

                table.insert(menuItems, {
                    title = title,
                    image = icon,
                    fn = function() hs.urlevent.openURL(match.url) end,
                    tooltip = match.date
                })
            end
            table.insert(menuItems, { title = "-" })
        end

        if #menuItems == 0 then
            table.insert(menuItems, { title = "No matches found" })
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

return obj
