local obj = {}
obj.__index = obj

-- Metadata
obj.name = "FotMobSchedule"
obj.version = "2.11"
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
local HEADER_SERVER_URL = "http://46.101.91.154:6006/"

-- Configuration
obj.logger = hs.logger.new('FotMobSchedule', 'info')
obj.interval = DEFAULT_INTERVAL
obj.menuBar = nil
obj.lastSchedule = nil
obj.teams = hs.settings.get("FotMobSchedule_teams") or { DEFAULT_TEAM }
obj.showNextGames = hs.settings.get("FotMobSchedule_showNextGames") or DEFAULT_SHOW_NEXT_GAMES
obj.showLastGames = hs.settings.get("FotMobSchedule_showLastGames") or DEFAULT_SHOW_LAST_GAMES
obj.headers = nil -- Placeholder for dynamic headers

-- Helper functions
local function fetchHeaders(callback)
    obj.logger.d("Fetching dynamic headers from server: " .. HEADER_SERVER_URL)
    hs.http.asyncGet(HEADER_SERVER_URL, nil, function(status, body, responseHeaders)
        if status ~= 200 then
            obj.logger.ef("Failed to fetch headers. Status: %d", status)
            callback(nil)
        else
            local headers = hs.json.decode(body)
            if headers then
                obj.logger.d("Successfully fetched headers.")
                callback(headers)
            else
                obj.logger.ef("Failed to decode headers response.")
                callback(nil)
            end
        end
    end)
end

local function fetchData(url, callback)
    if not obj.headers then
        obj.logger.e("Headers are not initialized. Aborting fetch.")
        callback(nil)
        return
    end

    obj.logger.d("Fetching data from URL: " .. url)
    hs.http.asyncGet(url, obj.headers, function(status, body, responseHeaders)
        if status ~= 200 then
            obj.logger.ef("Failed to fetch data from %s. Status: %d", url, status)
            callback(nil)
        else
            callback(hs.json.decode(body))
        end
    end)
end

local function getTimestampFromUTCDateTable(dateTable)
    local timestampUTC = os.time(dateTable)
    local timeDiff = os.difftime(os.time(), os.time(os.date("!*t")))
    return timestampUTC + timeDiff
end

local function formatDate(utcTime)
    local timestamp = nil
    if type(utcTime) == "string" then
        local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+)"
        local year, month, day, hour, min = utcTime:match(pattern)
        if year then
            local dateTable = {year=year, month=month, day=day, hour=hour, min=min, sec=0}
            timestamp = getTimestampFromUTCDateTable(dateTable)
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

-- Main functions
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
            
            local homeScore = fixture.home.score
            local awayScore = fixture.away.score
            
            obj.logger.d("Fixture status: " .. hs.inspect(fixture.status))
            obj.logger.d(string.format("Home Score: %s, Away Score: %s", tostring(homeScore), tostring(awayScore)))

            local winner = nil
            if status == "finished" then
                obj.logger.d(string.format("Match finished between %s and %s", fixture.home.name, fixture.away.name))
                if homeScore ~= nil and awayScore ~= nil then
                    if homeScore > awayScore then
                        winner = fixture.home.id
                    elseif awayScore > homeScore then
                        winner = fixture.away.id
                    else
                        winner = "draw"
                    end
                else
                    obj.logger.w("Scores are nil; cannot determine winner")
                end
            else
                obj.logger.d("Match status is not 'finished'; skipping winner determination")
            end

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
                winner = winner,
            }

            table.insert(schedule, matchData)
        end
    else
        obj.logger.w("No fixtures found or unexpected data structure")
    end
    obj.logger.d("Processed " .. #schedule .. " fixtures")
    return schedule
end

function obj:updateMenu()
    self:fetchSchedule(function(schedules)
        if not schedules then
            hs.notify.new({title="FotMob Schedule Error", informativeText="Failed to fetch FotMob schedule"}):send()
            return
        end

        local menuItems = {}
        local matches = {}

        for team, schedule in pairs(schedules) do
            for _, match in ipairs(schedule) do
                table.insert(matches, match)
            end
        end

        local matchesByTournament = {}
        for _, match in ipairs(matches) do
            local tournament = match.tournament
            if not matchesByTournament[tournament] then
                matchesByTournament[tournament] = {}
            end
            table.insert(matchesByTournament[tournament], match)
        end

        local sortedTournaments = {}
        for tournament in pairs(matchesByTournament) do
            table.insert(sortedTournaments, tournament)
        end
        table.sort(sortedTournaments)

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
                    local trophy = "🏆 "
                    local drawEmoji = "🤝 "
                    local matchTitleWithEmoji = title
                    if match.winner then
                        if match.winner == "draw" then
                            matchTitleWithEmoji = string.format("%s%s vs %s", drawEmoji, match.home.name, match.away.name)
                        elseif match.winner == match.home.id then
                            matchTitleWithEmoji = string.format("%s%s vs %s", trophy, match.home.name, match.away.name)
                        elseif match.winner == match.away.id then
                            matchTitleWithEmoji = string.format("%s vs %s%s", match.home.name, match.away.name, trophy)
                        end
                    end
                    title = string.format("%s (%s)", matchTitleWithEmoji, match.result)
                elseif match.status == "in-progress" then
                    title = string.format("%s (Live)", title)
                else
                    title = string.format("%s - %s", title, match.date)
                end

                local styledTitle = hs.styledtext.new(title, {
                    font = { name = "Helvetica", size = 14 },
                    paragraphStyle = { alignment = "left" }
                })

                table.insert(menuItems, {
                    title = styledTitle,
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


function obj:fetchSchedule(callback)
    if not obj.headers then
        obj.logger.e("Headers are not initialized. Fetch aborted.")
        callback(nil)
        return
    end

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

function obj:start()
    obj.logger.d("Starting FotMobSchedule")
    fetchHeaders(function(headers)
        if not headers then
            hs.notify.new({title="FotMob Schedule Error", informativeText="Failed to fetch headers"}):send()
            return
        end

        obj.headers = headers
        obj.headers["User-Agent"] = "Hammerspoon/FotMobSchedule"

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
    end)
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