
# FotMobSchedule Spoon

FotMobSchedule is a Hammerspoon Spoon that fetches and displays schedules for specified football (err soccer for y'all Americans) teams using FotMob's API. Notifications are shown for upcoming matches, and the number of matches to display can be configured.

## Features

- Fetches schedules for specified teams from FotMob.
- Displays notifications for upcoming matches with clickable links to the match details.
- Configurable number of games to display.
- Easy-to-use menu bar integration.

## Installation

1. **Download** the Spoon from the GitHub repository:

   ```bash
   git clone https://github.com/jamtur01/FotMobSchedule.spoon.git ~/.hammerspoon/Spoons/FotMobSchedule.spoon
   ```

2. **Load** the Spoon in your `init.lua`:

   ```lua
   hs.loadSpoon("FotMobSchedule")
   spoon.FotMobSchedule:start()
   ```

## Configuration

### Setting Teams

By default, the Spoon is configured to follow the Arsenal Women team. You can modify the `obj.teams` table in the Spoon's code to follow different teams. Each team needs a `name` and an `id` which can be found on FotMob's website.

Example:

```lua
spoon.FotMobSchedule.teams = {
    { name = "Arsenal Women", id = 258657 },
    { name = "Liverpool", id = 10260 }
}
```

### Setting the Number of Games to Display

You can configure how many upcoming games should be displayed using the `setNextGamesCount` method or through the menu bar:

```lua
spoon.FotMobSchedule:setNextGamesCount(3)
```

Alternatively, you can select the number of games via the menu bar:

1. Click the "FB" icon in the menu bar.
2. Select "Set Number of Games" and choose from the options presented.

## Usage

Once the Spoon is loaded and started, it will periodically fetch the latest schedule for your specified teams and display notifications for upcoming matches.

- **Menu Bar**: The Spoon adds an "FB" icon to your menu bar with options to show the schedule and set the number of games to display.
- **Notifications**: Notifications include the match details, such as the date, opponent, and whether it's a home or away game. Clicking on the "Open" button in the notification will take you to the match details on FotMob's website.

## License

FotMobSchedule is released under the MIT License. See the [LICENSE](https://opensource.org/licenses/MIT) for details.

## Author

FotMobSchedule was created by [James Turnbull](https://github.com/jamtur01).
