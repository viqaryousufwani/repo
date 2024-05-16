-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
Logs = Logs or {}

-- Define colors for console output
colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

-- Function to add logs
function addLog(msg, text)
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Function to calculate Euclidean distance between two points
function distance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

-- Function to find the nearest enemy player
function findNearestEnemy()
    local nearestPlayer = nil
    local minDistance = math.huge
    local me = LatestGameState.Players[ao.id]

    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id then
            local distanceToPlayer = distance(me.x, me.y, state.x, state.y)
            if distanceToPlayer < minDistance then
                nearestPlayer = state
                minDistance = distanceToPlayer
            end
        end
    end

    return nearestPlayer
end

-- Function to move towards the nearest enemy player
function moveTowardsEnemy()
    local me = LatestGameState.Players[ao.id]
    local nearestEnemy = findNearestEnemy()

    if nearestEnemy then
        -- Calculate direction towards the enemy
        local dx = nearestEnemy.x - me.x
        local dy = nearestEnemy.y - me.y

        -- Normalize direction vector
        local magnitude = math.sqrt(dx^2 + dy^2)
        dx = dx / magnitude
        dy = dy / magnitude

        -- Move towards the enemy (for simplicity, let's assume a fixed speed)
        local newX = me.x + dx
        local newY = me.y + dy

        -- Check if the new position is within the game boundaries
        if newX >= 0 and newX <= LatestGameState.GameWidth and newY >= 0 and newY <= LatestGameState.GameHeight then
            -- Update player position
            ao.send({ Target = Game, Action = "Move", Player = ao.id, X = newX, Y = newY })
        end
    end
end

-- Function to evade attacks
function evadeAttacks()
    -- Implement evasion tactics here
    -- For simplicity, let's assume random movement
    local randomX = math.random(0, LatestGameState.GameWidth)
    local randomY = math.random(0, LatestGameState.GameHeight)

    -- Move to a random position within the game boundaries
    ao.send({ Target = Game, Action = "Move", Player = ao.id, X = randomX, Y = randomY })
end

-- Function to attack the weakest player
function attackWeakestPlayer()
    local weakestPlayer = findWeakestPlayer()

    if weakestPlayer then
        local attackEnergy = LatestGameState.Players[ao.id].energy * weakestPlayer.health
        print(colors.red .. "Attacking weakest player with energy: " .. attackEnergy .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(attackEnergy) }) -- Attack with energy proportional to opponent's health
        InAction = false -- Reset InAction after attacking
        return true
    end

    return false
end

-- Decides the next action based on player proximity and energy.
-- If any player is within range, it initiates an attack; otherwise, moves towards the nearest enemy player.
function decideNextAction()
    local me = LatestGameState.Players[ao.id]

    if not attackWeakestPlayer() then
        print("No weak opponents found. Moving towards nearest enemy.")
        moveTowardsEnemy()
    end
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
            InAction = true  -- InAction logic added
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif InAction then -- InAction logic added
            print("Previous action still in progress. Skipping.")
        end

        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            print(colors.gray .. "Getting game state..." .. colors.reset)
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print("Auto-paying confirmation fees.")
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        print("Game state updated. Print \'LatestGameState\' for detailed view.")
        print("energy:" .. LatestGameState.Players[ao.id].energy)
    end
)

-- Handler to decide the next best action.
Handlers.add(
    "decideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        if LatestGameState.GameMode ~= "Playing" then
            print("game not start")
            InAction = false -- InAction logic added
            return
        end
        print("Deciding next action.")
        decideNextAction()
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            local playerEnergy = LatestGameState.Players[ao.id].energy
            if playerEnergy == undefined then
                print(colors.red .. "Unable to read energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
            elseif playerEnergy == 0 then
                print(colors.red .. "Player has insufficient energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
            else
                print(colors.red .. "Returning attack." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy) }) -- Attack with full energy
            end
            InAction = false -- InAction logic added
            ao.send({ Target = ao.id, Action = "Tick" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)
