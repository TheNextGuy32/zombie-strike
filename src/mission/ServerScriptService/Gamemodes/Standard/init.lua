local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Dungeon = require(ReplicatedStorage.Libraries.Dungeon)
local DungeonState = require(ServerScriptService.DungeonState)
local ExperienceUtil = require(ServerScriptService.Libraries.ExperienceUtil)
local FastSpawn = require(ReplicatedStorage.Core.FastSpawn)
local Gamemode = require(script.Parent.Gamemode)
local GenerateTreasureLoot = require(ServerScriptService.Libraries.GenerateTreasureLoot)
local GetAvailableMissions = require(ReplicatedStorage.Core.GetAvailableMissions)
local RealDelay = require(ReplicatedStorage.Core.RealDelay)
local WaveDefense = require(script.WaveDefense)

local BossTimer = ReplicatedStorage.BossTimer
local Rooms = ServerStorage.Rooms

local SCALED_REWARD_MISSIONS_BEHIND = 1
local SCALED_REWARDS = {
	0.7,
	0.85,
	1,
	1.05,
	1.1,
}

local SPEED_BONUS = 0.33
local SPEED_TIME = 3.5

local SPECIAL_ZOMBIE_RATE_STANDARD = 0.065
local SPECIAL_ZOMBIE_RATE_INSANE = 0.11

local TREASURE_DELAY_TIME = 4
local WAVE_CHANCE = 0.4

local Standard = {}

local function createRoom(room, parent, connectTo)
	local room = room:Clone()

	if connectTo then
		local front = assert(connectTo:FindFirstChild("Front", true))
		local back = assert(room:FindFirstChild("Back", true))

		room:SetPrimaryPartCFrame(
			-- front.WorldCFrame
			-- + (back.WorldPosition - room.PrimaryPart.Position)
			CFrame.new(front.WorldPosition - back.Position)
		)
	end

	local decor = {}
	for _, thing in pairs(room:GetDescendants()) do
		if CollectionService:HasTag(thing, "Decor") then
			table.insert(decor, thing)
		end
	end

	if #decor > 0 then
		for _ = 1, math.random(#decor * 0.5) do
			table.remove(decor, math.random(#decor)):Destroy()
		end
	end

	room.Parent = parent
	return room
end

local function isTutorial()
	return Dungeon.GetDungeonData("Campaign") == 1
		and Dungeon.GetDungeonData("Difficulty") == 1
end

local function generateDungeon(roomModels, numRooms)
	local roomTypes = {
		boss = {},
		bossBefore = {},
		enemy = {},
		obby = {},
		treasure = {},
		wave = {},
	}

	for _, room in pairs(roomModels:GetChildren()) do
		local obbyType = room:FindFirstChild("ObbyType")
		if obbyType ~= nil then
			local roomTable = assert(roomTypes[obbyType.Value])
			table.insert(roomTable, room)
		end
	end

	local obbyParent = Instance.new("Folder")

	local base = createRoom(roomModels.StartSection, obbyParent)
	DungeonState.CurrentSpawn = base.SpawnLocation
	local nextRoom = base

	local rooms = {}
	local lastRoom = Workspace -- lol

	local halfway = math.floor(numRooms / 2)

	local waveRoom

	if math.random() <= WAVE_CHANCE and not isTutorial() then
		waveRoom = math.random(2, numRooms)
		if waveRoom == halfway then
			waveRoom = waveRoom + 1
		end
	end

	for room = 1, numRooms do
		local treasure = GenerateTreasureLoot:expect()
		if room == halfway and treasure ~= nil then
			local treasures = roomTypes.treasure
			nextRoom = createRoom(treasures[math.random(#treasures)], obbyParent, nextRoom)
			if treasure.Rarity == 5 then
				nextRoom.ChestEpic:Destroy()
			elseif treasure.Rarity == 4 then
				nextRoom.ChestLegendary:Destroy()
			end
			table.insert(rooms, nextRoom)
		end

		local roomChoice
		if room == waveRoom then
			roomChoice = roomTypes.wave[#roomTypes.wave]
		else
			local zombies = roomTypes.enemy

			repeat
				roomChoice = zombies[math.random(#zombies)]
			until roomChoice.Name ~= lastRoom.Name
		end

		lastRoom = roomChoice
		nextRoom = createRoom(roomChoice, obbyParent, nextRoom)

		table.insert(rooms, nextRoom)
	end

	local bossBeforeRoom = createRoom(roomTypes.bossBefore[1], obbyParent, nextRoom)
	table.insert(rooms, bossBeforeRoom)

	local bossRoom = createRoom(roomTypes.boss[math.random(#roomTypes.boss)], obbyParent, bossBeforeRoom)
	table.insert(rooms, bossRoom)

	obbyParent.Name = "Rooms"
	obbyParent.Parent = Workspace

	return rooms
end

local function getBossSequence()
	return require(ReplicatedStorage.BossSequences[Dungeon.GetDungeonData("Campaign")])
end

local function spawnBoss(position, room)
	local bossZombie = Gamemode.SpawnBoss(getBossSequence(), position, room)
	bossZombie.Died:connect(function()
		if DungeonState.CurrentGamemode.Scales() then
			for _, player in pairs(Players:GetPlayers()) do
				local rewards = DungeonState.CurrentGamemode.GetEndRewards(player)
				ExperienceUtil.GivePlayerXP(player, rewards.XP, bossZombie.instance.PrimaryPart)
			end
		end

		Gamemode.EndMission()
	end)
end

local function getSpecialZombieRate()
	if Dungeon.GetDungeonData("Difficulty") == 5 then
		return SPECIAL_ZOMBIE_RATE_INSANE
	else
		return SPECIAL_ZOMBIE_RATE_STANDARD
	end
end

function Standard.Init()
	local rooms = generateDungeon(
		Rooms[Dungeon.GetDungeonData("Campaign")],
		Dungeon.GetDungeonData("DifficultyInfo").Rooms
	)

	local zombieTypes = Gamemode.GetZombieTypes()

	local difficulty = Dungeon.GetDungeonData("Difficulty")
	local specialZombies = {}

	for index, special in ipairs(Dungeon.GetDungeonData("CampaignInfo").SpecialZombies) do
		-- Only allow special zombies at the right difficulty
		-- If SpecialZombies == { "a", "b", "c" }
		-- And difficulty is Hard (3), then only "a" and "b" will be added
		if (difficulty - 1) >= index then
			table.insert(specialZombies, special)
		end
	end

	local function startBoss(room)
		DungeonState.CurrentSpawn = assert(room:FindFirstChild("RespawnPoint", true))

		for _, player in pairs(Players:GetPlayers()) do
			FastSpawn(function()
				(player.Character or player.CharacterAdded:wait())
					:MoveTo(DungeonState.CurrentSpawn.WorldPosition)
			end)
		end

		local bossSpawn = room:FindFirstChild("BossSpawn", true)

		spawnBoss(bossSpawn and bossSpawn.WorldPosition, room)
	end

	local lastRoom = Workspace.Rooms.StartSection
	local usedNewSpecialZombie = false

	local function randomZombieType()
		if math.random() <= getSpecialZombieRate() and #specialZombies > 0 then
			if not usedNewSpecialZombie then
				usedNewSpecialZombie = true

				if Dungeon.GetDungeonData("Difficulty") - 1 == #specialZombies then
					return specialZombies[#specialZombies]
				end
			end

			return specialZombies[math.random(#specialZombies)]
		else
			return zombieTypes[math.random(#zombieTypes)]
		end
	end

	local function openNextGate()
		local room = table.remove(rooms, 1)
		local gate = assert(room:FindFirstChild("Gate", true), "No Gate")

		DungeonState.CurrentRoom = room

		local obbyType = room.ObbyType.Value

		local spawnPoint = assert(room:FindFirstChild("RespawnPoint", true), "No RespawnPoint")

		DungeonState.CurrentSpawn = spawnPoint
		ReplicatedStorage.CurrentSpawn.Value = spawnPoint

		if obbyType == "enemy" then
			local enemiesLeft = room.EnemiesLeft.Value
			local zombieSpawns = {}
			for _, thing in pairs(room:GetDescendants()) do
				if CollectionService:HasTag(thing, "ZombieSpawn") then
					table.insert(zombieSpawns, thing)
				end
			end

			local zombies = {}

			for _ = 1, enemiesLeft do
				local spawnPoint = table.remove(zombieSpawns, math.random(#zombieSpawns))
				local zombie

				repeat
					zombie = Gamemode.SpawnZombie(
						randomZombieType(),
						Dungeon.RNGZombieLevel(),
						spawnPoint.WorldPosition
					)
				until zombie

				table.insert(zombies, zombie)

				local maxEnemies = enemiesLeft

				zombie.Died:connect(function()
					enemiesLeft = enemiesLeft - 1
					if enemiesLeft == 0 then
						wait(1)
						openNextGate()
					elseif enemiesLeft < maxEnemies / 2 then
						for _, zombie in pairs(zombies) do
							if zombie.alive and zombie.wandering then
								zombie:Aggro()
							end
						end
					end
				end)
			end

			wait(1)
		elseif obbyType == "treasure" then
			RealDelay(Dungeon.GetDungeonData("CampaignInfo").TreasureDelayTime or TREASURE_DELAY_TIME, openNextGate)
		elseif obbyType == "wave" then
			WaveDefense.StartWaveDefenseRoom(room):andThen(openNextGate)
		end

		for _, player in pairs(Players:GetPlayers()) do
			local speedMultiplier = player:WaitForChild("SpeedMultiplier")
			speedMultiplier.Value = speedMultiplier.Value + SPEED_BONUS
			delay(SPEED_TIME, function()
				speedMultiplier.Value = speedMultiplier.Value - SPEED_BONUS
			end)
		end

		if Dungeon.GetDungeonData("Campaign") == 6 then
			-- Tower gates are in the current room, not the next one
			room, lastRoom = lastRoom, room
		else
			-- Tower has portals instead of traditional gates
			Debris:AddItem(gate, 4)
		end

		ReplicatedStorage.Remotes.OpenGate:FireAllClients(room)
		Players.PlayerAdded:connect(function(player)
			ReplicatedStorage.Remotes.OpenGate:FireClient(player, room)
		end)

		if obbyType == "bossBefore" then
			for timer = 5, 1, -1 do
				BossTimer.Value = timer
				wait(1)
			end

			BossTimer.Value = 0

			startBoss(rooms[#rooms])
		end
	end

	ServerStorage.Events.ToBoss.Event:connect(function(showSequence)
		ReplicatedStorage.SkipBossSequence.Value = not showSequence

		local room = rooms[#rooms]
		DungeonState.CurrentSpawn = assert(room:FindFirstChild("RespawnPoint", true))
		startBoss(room)
	end)

	local difficultyInfo = Dungeon.GetDungeonData("DifficultyInfo")

	for _, room in pairs(rooms) do
		if room.ObbyType.Value == "enemy" then
			local zombieSpawns = {}
			for _, thing in pairs(room:GetDescendants()) do
				if CollectionService:HasTag(thing, "ZombieSpawn") then
					table.insert(zombieSpawns, thing)
				end
			end

			local amount = math.ceil(#zombieSpawns * difficultyInfo.ZombieSpawnRate)

			local enemiesLeft = Instance.new("NumberValue")
			enemiesLeft.Name = "EnemiesLeft"
			enemiesLeft.Value = amount
			enemiesLeft.Parent = room

			DungeonState.NormalZombies = DungeonState.NormalZombies + amount
		elseif room.ObbyType.Value == "wave" then
			DungeonState.NormalZombies = DungeonState.NormalZombies + WaveDefense.ZombiesToKill()
		end
	end

	return {
		Countdown = function(time)
			if time == 2 then
				FastSpawn(openNextGate)
			end
		end,

		GetEndRewards = function(player)
			if Dungeon.GetDungeonData("CampaignInfo").Scales then
				local missions = GetAvailableMissions(player)
				local earlierMission

				for index = SCALED_REWARD_MISSIONS_BEHIND, 0, -1 do
					local nearbyMission = missions[#missions - index]
					if nearbyMission then
						earlierMission = nearbyMission
						break
					end
				end

				assert(earlierMission, "No earlier mission?")

				local difficulty = Dungeon.GetDungeonData("Difficulty")

				return {
					XP = earlierMission.XP * SCALED_REWARDS[difficulty],
					Gold = earlierMission.Gold * SCALED_REWARDS[difficulty],
				}
			else
				return Dungeon.GetDungeonData("DifficultyInfo")
			end
		end,

		Scales = function()
			return Dungeon.GetDungeonData("CampaignInfo").Scales
		end,

		SpecialZombies = specialZombies,
	}
end

return Standard
