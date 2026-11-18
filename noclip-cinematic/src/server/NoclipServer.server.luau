--!strict
-- NoclipServer: detects the trigger in front of the wall, freezes the player, tells their
-- client to play the first-person sequence and moves them to the Level 0 spawn while the
-- screen is black.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("NoclipConfig"))

local remote = ReplicatedStorage:FindFirstChild(Config.RemoteName) :: RemoteEvent?
if not remote then
	local newRemote = Instance.new("RemoteEvent")
	newRemote.Name = Config.RemoteName
	newRemote.Parent = ReplicatedStorage
	remote = newRemote
end
local sequenceRemote = remote :: RemoteEvent

local active: { [Player]: boolean } = {}
local lastRun: { [Player]: number } = {}

local function getSpawnCFrame(): CFrame?
	local spawnPart = workspace:FindFirstChild(Config.SpawnName, true)
	if spawnPart and spawnPart:IsA("BasePart") then
		-- Stand slightly above the spawn part, facing its front face (flattened to Y).
		local look = spawnPart.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude < 1e-3 then
			look = Vector3.new(0, 0, -1)
		end
		local position = spawnPart.Position + Vector3.new(0, spawnPart.Size.Y / 2 + 3, 0)
		return CFrame.lookAt(position, position + look.Unit)
	end
	warn(`[Noclip] No BasePart named "{Config.SpawnName}" in Workspace; skipping teleport.`)
	return nil
end

local function totalDuration(): number
	local t = Config.Timeline
	return t.Reach + t.Enter + t.Fall + t.ImpactHold + t.WakeUp + t.StandUp
end

local function runSequence(player: Player, trigger: BasePart)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local previous = lastRun[player]
	if active[player] or (previous and now - previous < Config.CooldownSeconds) then
		return
	end
	active[player] = true
	lastRun[player] = now

	-- Freeze the character on the server; the client drives a scripted camera meanwhile.
	local walkSpeed, jumpPower, jumpHeight = humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	root.Anchored = true

	sequenceRemote:FireClient(player, "Start", trigger)

	local timeline = Config.Timeline
	-- The screen is fully black at the end of Enter; move the character just after.
	task.wait(timeline.Reach + timeline.Enter + 0.1)
	local target = getSpawnCFrame()
	if target and character.Parent then
		character:PivotTo(target)
	end

	task.wait(totalDuration() - (timeline.Reach + timeline.Enter + 0.1))

	if root.Parent then
		root.Anchored = false
	end
	if humanoid.Parent then
		humanoid.WalkSpeed = walkSpeed
		humanoid.JumpPower = jumpPower
		humanoid.JumpHeight = jumpHeight
	end
	active[player] = nil
end

local function bindTrigger(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local trigger = instance
	trigger.Touched:Connect(function(hit: BasePart)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			task.spawn(runSequence, player, trigger)
		end
	end)
end

for _, trigger in CollectionService:GetTagged(Config.TriggerTag) do
	bindTrigger(trigger)
end
CollectionService:GetInstanceAddedSignal(Config.TriggerTag):Connect(bindTrigger)

Players.PlayerRemoving:Connect(function(player)
	active[player] = nil
	lastRun[player] = nil
end)
