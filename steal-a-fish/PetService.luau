-- STEAL A FISH (Deep Dive Tycoon) · PetService: pets hatched from eggs.
-- · Rolls eggs, adds up the bonus of the equipped pets.
-- · Equipped pets follow their owner: server-built models pulled by AlignPosition/AlignOrientation
--   towards attachments on the owner's HumanoidRootPart. The owner simulates them (network owner),
--   so they move smoothly for everyone. The owner's client also bobs/sways their slots (Visuals).
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DeepDive")
local Config = require(Shared.Config)

local PetService = {}
local rng = Random.new()
local folder
local spawned = {} -- player -> { uid -> model }

-- chosen pet id for an egg (weights in Config.Eggs[i].Pets = { { petId, weight } })
function PetService.Roll(eggId)
	local egg = Config.EggById[eggId]
	if not egg then
		return nil
	end
	local total = 0
	for _, e in ipairs(egg.Pets) do
		total += e[2]
	end
	local r = rng:NextNumber() * total
	for _, e in ipairs(egg.Pets) do
		r -= e[2]
		if r <= 0 then
			return e[1]
		end
	end
	return egg.Pets[#egg.Pets][1]
end

function PetService.BonusOf(petId, golden)
	local p = Config.PetById[petId]
	local b = p and (Config.PetBonus[p.Rarity] or 0) / 100 or 0
	return golden and b * Config.PetFuse.GoldenMult or b
end

-- multiplier from the equipped pets (money and capacity per click)
function PetService.Mult(d)
	local m = 1
	for _, pet in ipairs(d.Pets or {}) do
		if d.PetEquipped and d.PetEquipped[pet.U] then
			m += PetService.BonusOf(pet.P, pet.G)
		end
	end
	return m
end

local function clearPlayer(player)
	local list = spawned[player]
	if list then
		for _, m in pairs(list) do
			m:Destroy()
		end
	end
	spawned[player] = nil
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hrp then
		for _, a in ipairs(hrp:GetChildren()) do
			if a.Name == "PetSlot" then
				a:Destroy()
			end
		end
	end
end

-- where a pet floats next to its owner: the equipped pets share a half circle behind the diver (left side -> behind ->
-- right side), wide enough for the biggest of them so neighbours never overlap (VIP: 4 pets) and with room for the
-- arms, so big divers (muscle body, scaled up) don't swallow their pets. Recomputed whenever the character changes size.
local function slotPosition(slot, count, char, petRadius, y)
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	local arm = char:FindFirstChild("RightUpperArm") or char:FindFirstChild("Right Arm")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local side = (torso and torso.Size.X or 2) / 2 + (arm and arm.Size.X or 1) + petRadius + 1.5
	local back = (torso and torso.Size.Z or 1) / 2 + petRadius + 0.5
	y = y or -(hrp and hrp.Size.Y / 2 or 1)
	local z0 = math.max(back, 2) -- the side pets sit a little behind the shoulders
	if count <= 1 then
		return Vector3.new(-math.max(side, 5), y, z0)
	end
	local step = math.pi / (count - 1)
	-- two neighbours on the arc are 2 R sin(step / 2) apart: at least two pet radii plus a gap
	local radius = math.max(side, 5, (petRadius * 2 + 1.5) / (2 * math.sin(step / 2)))
	local a = (slot - 1) * step
	return Vector3.new(-math.cos(a) * radius, y, z0 + math.sin(a) * radius)
end

-- half the widest footprint of a pet (golden ones are 25% bigger)
local function petRadiusOf(petId, golden)
	local assets = Shared:FindFirstChild("Assets")
	local tpl = assets and assets:FindFirstChild("Pets") and assets.Pets:FindFirstChild(petId)
	if not tpl then
		return 1
	end
	local ext = tpl:GetExtentsSize()
	return math.max(ext.X, ext.Z) / 2 * (golden and 1.25 or 1)
end

local function spawnPet(player, hrp, petId, slot, golden, count, sharedRadius)
	local assets = Shared:FindFirstChild("Assets")
	local tpl = assets and assets:FindFirstChild("Pets") and assets.Pets:FindFirstChild(petId)
	if not tpl then
		return nil
	end
	local m = tpl:Clone()
	if golden then
		m:ScaleTo(m:GetScale() * 1.25)
	end
	local root = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		m:Destroy()
		return nil
	end
	-- glue every part to the root so the whole pet is one assembly
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = p ~= root
			if p ~= root then
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = p
				w.Parent = p
			end
		end
	end
	local slotAtt = Instance.new("Attachment")
	slotAtt.Name = "PetSlot"
	local char = hrp.Parent
	local hum = char:FindFirstChildOfClass("Humanoid")
	-- pets grow with their owner (a bigger diver = bigger pets) and never sink into the floor
	local baseScale = m:GetScale()
	local petRadius, bottom, petHeight = 1, 1, 2
	local tag -- its name tag (created below), lifted above the pet when it grows
	local function charScale()
		return math.max(1, hrp.Size.Y / 2) -- an R15 root part is 2 studs tall at scale 1
	end
	local function place()
		local s = charScale()
		if math.abs(m:GetScale() - baseScale * s) > 1e-3 then
			m:ScaleTo(baseScale * s)
		end
		-- its size now, and how high its pivot is above its lowest point
		local cf, size = m:GetBoundingBox()
		bottom = m:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
		petRadius = math.max(size.X, size.Z) / 2
		petHeight = size.Y
		if tag then
			tag.StudsOffset = Vector3.new(0, math.max(2.6, petHeight * 0.5 + 1.6), 0)
		end
		-- floating at hip height, but its feet always above the ground (+ a small gap)
		local ground = -(hrp.Size.Y / 2 + (hum and hum.HipHeight or 2))
		local y = math.max(-hrp.Size.Y / 2, ground + bottom + 0.5 * s)
		local pos = slotPosition(slot, count, char, math.max(petRadius, (sharedRadius or 0) * s), y)
		slotAtt.Position = pos
		slotAtt:SetAttribute("Base", pos) -- the owner's client bobs the slot around this point (only upwards)
	end
	place()
	local sizeConn = hrp:GetPropertyChangedSignal("Size"):Connect(place)
	slotAtt.Destroying:Connect(function()
		sizeConn:Disconnect()
	end)
	slotAtt:SetAttribute("Index", slot)
	slotAtt.Parent = hrp
	-- the pet's own attachment sits on its pivot so the model's front faces the player's front
	local att = Instance.new("Attachment")
	att.Name = "PetAttachment"
	att.CFrame = root.CFrame:ToObjectSpace(m:GetPivot())
	att.Parent = root
	local ap = Instance.new("AlignPosition")
	ap.Attachment0 = att
	ap.Attachment1 = slotAtt
	ap.MaxForce = 1e6
	ap.MaxVelocity = 200
	ap.Responsiveness = 18
	ap.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Attachment0 = att
	ao.Attachment1 = slotAtt
	ao.MaxTorque = 1e6
	ao.Responsiveness = 14
	ao.Parent = root
	-- rarity sparkles + name tag
	local p = Config.PetById[petId]
	local rarity = Config.RarityById[p.Rarity]
	local pTpl = Shared.Assets:FindFirstChild("Particles") and Shared.Assets.Particles:FindFirstChild("Sparkle")
	if pTpl then
		local e = pTpl:Clone()
		e.Name = "PetSparkles"
		e.Color = Config.RarityGradient(rarity)
		e.Rate = 2 + rarity.Order * 0.5
		e.Parent = root
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "PetTag"
	bb:SetAttribute("Rarity", rarity.Id) -- every client makes its gradient move (Visuals)
	bb.Size = UDim2.fromOffset(160, 34)
	bb.StudsOffset = Vector3.new(0, math.max(2.6, petHeight * 0.5 + 1.6), 0)
	tag = bb
	bb.MaxDistance = 60
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = golden and ("GOLDEN " .. string.upper(rarity.Name)) or string.upper(rarity.Name)
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Parent = bb
	local g = Instance.new("UIGradient")
	g.Color = Config.RarityGradient(rarity)
	g.Parent = t
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Color3.fromRGB(10, 15, 30)
	st.Parent = t
	bb.Parent = root
	if golden and pTpl then
		local gold = pTpl:Clone()
		gold.Name = "GoldenSparkles"
		gold.Color = ColorSequence.new(Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 170, 20))
		gold.Rate = 10
		gold.Parent = root
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 200, 60)
		l.Range = 8
		l.Brightness = 1.5
		l.Parent = root
	end
	m:PivotTo(hrp.CFrame * CFrame.new(slotAtt.Position))
	m.Name = player.Name .. "_" .. petId
	m.Parent = folder
	pcall(function()
		root:SetNetworkOwner(player)
	end)
	-- (the pet pack's own animations belong to another creator and can't be played here:
	--  the owner's client animates the pets procedurally, see Visuals "pet bob")
	return m
end

-- rebuilds the followers of a player from their equipped list
function PetService.Refresh(player, d)
	clearPlayer(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not d then
		return
	end
	local list = {}
	local maxSlots = player:GetAttribute("PetSlots") or Config.PetSlots
	local equipped = {}
	local radius = 0
	for _, pet in ipairs(d.Pets or {}) do
		if d.PetEquipped and d.PetEquipped[pet.U] and #equipped < maxSlots then
			table.insert(equipped, pet)
			radius = math.max(radius, petRadiusOf(pet.P, pet.G))
		end
	end
	for slot, pet in ipairs(equipped) do
		local m = spawnPet(player, hrp, pet.P, slot, pet.G, #equipped, radius)
		if m then
			list[pet.U] = m
		end
	end
	spawned[player] = list
end

function PetService.Remove(player)
	clearPlayer(player)
end

function PetService.Start()
	local runtime = Workspace:FindFirstChild("DeepDiveRuntime") or Instance.new("Folder")
	runtime.Name = "DeepDiveRuntime"
	runtime.Parent = Workspace
	folder = runtime:FindFirstChild("Pets") or Instance.new("Folder")
	folder.Name = "Pets"
	folder.Parent = runtime
	Players.PlayerRemoving:Connect(clearPlayer)
end

return PetService
