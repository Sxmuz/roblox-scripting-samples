--!strict
-- NoclipClient: first-person "noclip into the Backrooms" cinematic for the local player.
--
--   1. Reach     the camera turns to the wall and your hand sinks into it
--   2. Enter     you push slowly into the wall while the screen fades to black
--   3. Fall      a long fall in the dark (wind + Backrooms hum growing), then a short
--                visible drop onto the Level 0 carpet
--   4. Impact    hard cut to black and a thud as you hit the floor
--   5. Wake up   fade in lying on the Level 0 carpet, looking at the lights (VHS look)
--   6. Stand up  push off the floor and get up, then control is handed back
--
-- The arms are a viewmodel built from the player's own avatar (R6 or R15, with their shirt).
-- Every timing, intensity and sound ID lives in NoclipConfig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("NoclipConfig"))
local remote = ReplicatedStorage:WaitForChild(Config.RemoteName) :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local rng = Random.new()

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Remaps t from [a, b] to [0, 1], clamped.
local function span(t: number, a: number, b: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end

local function hasAudio(id: string?): boolean
	return id ~= nil and id ~= "" and id ~= "rbxassetid://0"
end

local function makeSound(id: string, volume: number, looped: boolean): Sound?
	if not hasAudio(id) then
		return nil
	end
	return make("Sound", { SoundId = id, Volume = volume, Looped = looped }, SoundService)
end

local function playOnce(id: string, volume: number)
	local sound = makeSound(id, volume, false)
	if sound then
		sound:Play()
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end
end

local function getControls(): any
	local ok, controls = pcall(function()
		local playerModule = require((player:WaitForChild("PlayerScripts") :: any):WaitForChild("PlayerModule"))
		return playerModule:GetControls()
	end)
	return if ok then controls else nil
end

-- Runs step(alpha, elapsed, dt) every frame for `duration` seconds.
local function runPhase(duration: number, step: (number, number, number) -> ())
	local start = os.clock()
	local last = start
	while true do
		local now = os.clock()
		local elapsed = now - start
		local alpha = if duration > 0 then math.clamp(elapsed / duration, 0, 1) else 1
		step(alpha, elapsed, now - last)
		last = now
		if alpha >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

--------------------------------------------------------------------------------
-- Screen layers (built once, reused)
--------------------------------------------------------------------------------

local gui = make("ScreenGui", {
	Name = "NoclipFX",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local glitchLayer = make("Frame", {
	Name = "Glitch",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	ZIndex = 2,
}, gui)

local glitchBars: { Frame } = {}
for i = 1, Config.Glitch.Bars do
	glitchBars[i] = make("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
	}, glitchLayer)
end

local vhsLayer = make("Frame", {
	Name = "VHS",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 3,
}, gui)

local scanlines = make("Frame", {
	Name = "Scanlines",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, vhsLayer)

local trackingBar = make("Frame", {
	Name = "TrackingBar",
	Size = UDim2.new(1, 0, 0, 70),
	BorderSizePixel = 0,
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.9,
}, vhsLayer)
make("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, trackingBar)

local function vhsText(name: string, position: UDim2, anchor: Vector2, alignment: Enum.TextXAlignment): TextLabel
	return make("TextLabel", {
		Name = name,
		Position = position,
		AnchorPoint = anchor,
		Size = UDim2.fromOffset(420, 44),
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		TextSize = 34,
		TextColor3 = Color3.fromRGB(240, 240, 240),
		TextStrokeTransparency = 0.6,
		TextXAlignment = alignment,
		Text = "",
	}, vhsLayer)
end

local playLabel = vhsText("Play", UDim2.new(0, 48, 0, 40), Vector2.zero, Enum.TextXAlignment.Left)
local stampLabel = vhsText("Stamp", UDim2.new(0, 48, 1, -40), Vector2.new(0, 1), Enum.TextXAlignment.Left)
local counterLabel = vhsText("Counter", UDim2.new(1, -48, 1, -40), Vector2.new(1, 1), Enum.TextXAlignment.Right)

local blackout = make("Frame", {
	Name = "Blackout",
	Size = UDim2.fromScale(1, 1),
	BorderSizePixel = 0,
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, gui)

local function buildScanlines()
	scanlines:ClearAllChildren()
	local height = math.max(gui.AbsoluteSize.Y, 720)
	local spacing = math.max(2, Config.VHS.ScanlineSpacing)
	for y = 0, height, spacing do
		make("Frame", {
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = Config.VHS.ScanlineTransparency,
		}, scanlines)
	end
end

--------------------------------------------------------------------------------
-- Post-processing and glitch
--------------------------------------------------------------------------------

local fxCC = make("ColorCorrectionEffect", { Name = "NoclipFX", Enabled = false }, Lighting)
local fxBlur = make("BlurEffect", { Name = "NoclipBlur", Size = 0, Enabled = false }, Lighting)
local vhsCC = make("ColorCorrectionEffect", { Name = "NoclipVHS", Enabled = false }, Lighting)

-- 0 = normal colours, 1 = fully desaturated/dark (values from Config.Desaturate)
local function setDesaturation(amount: number, blur: number)
	fxCC.Enabled = amount > 0 or blur > 0
	fxBlur.Enabled = blur > 0
	fxCC.Saturation = lerp(0, Config.Desaturate.Saturation, amount)
	fxCC.Contrast = lerp(0, Config.Desaturate.Contrast, amount)
	fxCC.Brightness = lerp(0, Config.Desaturate.Brightness, amount)
	fxBlur.Size = blur
end

local function setGlitch(intensity: number)
	local size = gui.AbsoluteSize
	for _, bar in glitchBars do
		if intensity > 0 and rng:NextNumber() < intensity * 0.85 then
			local h = rng:NextInteger(2, math.floor(lerp(6, 46, intensity)))
			bar.Visible = true
			if rng:NextNumber() < 0.45 then
				-- short static chunk somewhere on the line
				bar.Size = UDim2.fromOffset(rng:NextInteger(40, math.max(60, math.floor(size.X * 0.4))), math.max(2, h // 2))
				bar.Position = UDim2.fromOffset(rng:NextInteger(0, math.max(1, size.X)), rng:NextInteger(0, math.max(1, size.Y)))
			else
				-- full-width tear, slightly offset sideways
				bar.Size = UDim2.new(1, rng:NextInteger(40, 220), 0, h)
				bar.Position = UDim2.fromOffset(rng:NextInteger(-160, 40), rng:NextInteger(0, math.max(1, size.Y)))
			end
			local grey = rng:NextNumber(0.55, 1)
			bar.BackgroundColor3 = if rng:NextNumber() < 0.15
				then Color3.fromRGB(rng:NextInteger(120, 255), 40, 40) -- rare colour tear
				else Color3.new(grey, grey, grey)
			bar.BackgroundTransparency = 1 - Config.Glitch.MaxOpacity * intensity * rng:NextNumber(0.35, 1)
		else
			bar.Visible = false
		end
	end
end

local vhsConnection: RBXScriptConnection? = nil

local function enableVHS()
	if not Config.VHS.Enabled then
		return
	end
	buildScanlines()
	vhsLayer.Visible = true
	vhsCC.Enabled = true
	vhsCC.TintColor = Config.VHS.TintColor
	vhsCC.Saturation = Config.VHS.Saturation
	vhsCC.Contrast = Config.VHS.Contrast
	playLabel.Text = Config.VHS.Label
	trackingBar.Visible = Config.VHS.TrackingBar
	local vhsStart = os.clock()

	if vhsConnection then
		vhsConnection:Disconnect()
	end
	vhsConnection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - vhsStart
		-- Blink "PLAY" for the first seconds, then keep it on.
		playLabel.Visible = elapsed > 4 or (math.floor(elapsed * 2) % 2 == 0)
		if Config.VHS.ShowTimestamp then
			stampLabel.Text = os.date("%p %I:%M  %b. %d %Y"):upper()
			local s = math.floor(elapsed)
			counterLabel.Text = string.format("SP %d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60)
		end
		if Config.VHS.TrackingBar then
			local h = gui.AbsoluteSize.Y
			trackingBar.Position = UDim2.fromOffset(0, (elapsed * 90) % (h + 140) - 70)
		end
		-- Subtle flicker.
		scanlines.Position = UDim2.fromOffset(0, if rng:NextNumber() < 0.08 then 1 else 0)
	end)
end

--------------------------------------------------------------------------------
-- First-person arms (viewmodel built from the player's avatar)
--------------------------------------------------------------------------------

-- lower/upper: where this segment joins the next one (part space). The hand's lower point is its tip.
type Segment = { part: BasePart, lower: Vector3, upper: Vector3 }
type Arm = { segments: { Segment } }

local ARM_PARTS = {
	-- ordered from the hand back to the shoulder: { part name, lower joint, upper joint }
	R15 = {
		Right = {
			{ "RightHand", nil, "RightWristRigAttachment" },
			{ "RightLowerArm", "RightWristRigAttachment", "RightElbowRigAttachment" },
			{ "RightUpperArm", "RightElbowRigAttachment", "RightShoulderRigAttachment" },
		},
		Left = {
			{ "LeftHand", nil, "LeftWristRigAttachment" },
			{ "LeftLowerArm", "LeftWristRigAttachment", "LeftElbowRigAttachment" },
			{ "LeftUpperArm", "LeftElbowRigAttachment", "LeftShoulderRigAttachment" },
		},
	},
	R6 = {
		Right = { { "Right Arm", nil, "RightShoulderAttachment" } },
		Left = { { "Left Arm", nil, "LeftShoulderAttachment" } },
	},
}

-- Position of a rig attachment inside a part, with a fallback to the part's top/bottom.
local function jointOffset(part: BasePart, attachmentName: string?, fallbackY: number): Vector3
	local attachment = attachmentName and part:FindFirstChild(attachmentName)
	if attachment and attachment:IsA("Attachment") then
		return attachment.Position
	end
	return Vector3.new(0, fallbackY, 0)
end

local viewmodel: Model? = nil
local arms: { [string]: Arm } = {}

local function clearViewmodel()
	if viewmodel then
		viewmodel:Destroy()
	end
	viewmodel = nil
	arms = {}
end

local function buildViewmodel(character: Model)
	clearViewmodel()
	local model = Instance.new("Model")
	model.Name = "NoclipArms"
	-- A Humanoid makes Roblox render the cloned Shirt on the arm parts.
	make("Humanoid", {
		DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None,
		RequiresNeck = false,
		BreakJointsOnDeath = false,
	}, model)
	local shirt = character:FindFirstChildOfClass("Shirt")
	if shirt then
		shirt:Clone().Parent = model
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rig = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then "R6" else "R15"
	for side, names in ARM_PARTS[rig] do
		local segments: { Segment } = {}
		for _, entry in names do
			local name, lowerName, upperName = entry[1], entry[2], entry[3]
			local source = character:FindFirstChild(name)
			local part: BasePart
			if source and source:IsA("BasePart") then
				part = source:Clone()
				for _, child in part:GetChildren() do
					if child:IsA("JointInstance") or child:IsA("Constraint") or child:IsA("BaseScript") then
						child:Destroy()
					end
				end
			else
				-- Fallback block if the avatar doesn't have this part.
				part = make("Part", { Size = Vector3.new(0.9, if rig == "R6" then 2 else 0.8, 0.9), Color = Color3.fromRGB(205, 160, 125) }, nil)
				part.Name = name
			end
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Massless = true
			part.LocalTransparencyModifier = 0
			part.Parent = model
			local half = part.Size.Y / 2
			table.insert(segments, {
				part = part,
				-- the hand's "lower" point is its fingertips: the bottom of the part
				lower = if lowerName then jointOffset(part, lowerName, -half) else Vector3.new(0, -half, 0),
				upper = jointOffset(part, upperName, half),
			})
		end
		arms[side] = { segments = segments }
	end

	model.Parent = workspace.CurrentCamera
	viewmodel = model
end

local function setArmVisible(side: string, visible: boolean)
	local arm = arms[side]
	if not arm then
		return
	end
	for _, segment in arm.segments do
		segment.part.Transparency = if visible then 0 else 1
	end
end

-- Places an arm so its hand ends at `hand` (world) and the arm points along `dir` (world).
local function poseArm(side: string, hand: Vector3, dir: Vector3, camera: Camera)
	local arm = arms[side]
	if not arm or dir.Magnitude < 1e-4 then
		return
	end
	local up = -dir.Unit -- a limb's -Y end is its hand end
	local ref = camera.CFrame.RightVector
	local right = ref - up * ref:Dot(up)
	if right.Magnitude < 1e-3 then
		right = camera.CFrame.UpVector - up * camera.CFrame.UpVector:Dot(up)
	end
	right = right.Unit
	-- Same rotation for every segment (a straight arm); chain them joint to joint
	-- using the avatar's own wrist/elbow attachments so the pieces line up.
	local rotation = CFrame.fromMatrix(Vector3.zero, right, up)
	local joint = hand
	for _, segment in arm.segments do
		local position = joint - rotation:VectorToWorldSpace(segment.lower)
		local cf = rotation + position
		segment.part.CFrame = cf
		joint = cf:PointToWorldSpace(segment.upper)
	end
end

-- Pose in camera space: hand position and the virtual shoulder the arm comes from.
local function poseArmLocal(side: string, handLocal: Vector3, shoulderLocal: Vector3, camera: Camera)
	local cf = camera.CFrame
	local hand = cf:PointToWorldSpace(handLocal)
	local shoulder = cf:PointToWorldSpace(shoulderLocal)
	poseArm(side, hand, hand - shoulder, camera)
end

--------------------------------------------------------------------------------
-- Character visibility and floor
--------------------------------------------------------------------------------

local function setCharacterHidden(character: Model, hidden: boolean)
	local value = if hidden then 1 else 0
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = value
		end
	end
end

local function floorBelow(position: Vector3, exclude: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(position, Vector3.new(0, -50, 0), params)
	return if hit then hit.Position.Y else position.Y - 3
end

--------------------------------------------------------------------------------
-- Sequence
--------------------------------------------------------------------------------

local running = false
local ambientSound: Sound? = nil

local function play(trigger: BasePart?)
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if running or not character or not head or not root then
		return
	end
	running = true

	local camera = workspace.CurrentCamera
	local timeline = Config.Timeline
	local controls = getControls()
	if controls then
		controls:Disable()
	end

	local oldFov = camera.FieldOfView
	local startCF = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Config.Camera.FieldOfView

	buildViewmodel(character)
	setArmVisible("Right", false)
	setArmVisible("Left", false)

	-- Hide the real body every frame (the default camera may try to show it again).
	local hideConnection = RunService.RenderStepped:Connect(function()
		setCharacterHidden(character, true)
	end)

	-- Find the wall: cast from the head along the trigger's front face.
	local headPos = head.Position + Vector3.new(0, 0.15, 0)
	local wallDir = if trigger then trigger.CFrame.LookVector else root.CFrame.LookVector
	wallDir = Vector3.new(wallDir.X, 0, wallDir.Z)
	wallDir = if wallDir.Magnitude > 1e-3 then wallDir.Unit else Vector3.new(0, 0, -1)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, camera, trigger :: Instance }
	local hit = workspace:Raycast(headPos, wallDir * 12, params)
	local wallPoint = if hit then hit.Position else headPos + wallDir * 2.5
	local normal = if hit then hit.Normal else -wallDir

	local wallDistance = math.clamp((wallPoint - headPos):Dot(wallDir), 2.6, 3.2)
	local facePos = wallPoint + normal * wallDistance
	local faceCF = CFrame.lookAt(facePos, wallPoint)
	local wallRight = faceCF.RightVector
	local contact = wallPoint + wallRight * 0.45 - Vector3.new(0, 0.55, 0)
	local leftContact = wallPoint - wallRight * 0.55 - Vector3.new(0, 0.35, 0)

	local breathing = makeSound(Config.Audio.Breathing, 0, true)
	if breathing then
		breathing:Play()
	end

	------------------------------------------------------------------ 1) Reach
	local stung = false
	runPhase(timeline.Reach, function(a)
		local turn = smooth(span(a, 0, 0.35))
		camera.CFrame = startCF:Lerp(faceCF, turn)

		if breathing then
			breathing.Volume = lerp(0.1, Config.Audio.BreathingVolume * 0.6, a)
		end

		local r = span(a, 0.25, 1)
		if r > 0 then
			setArmVisible("Right", true)
			local startHand = camera.CFrame:PointToWorldSpace(Config.Arms.ReachStart)
			local hand: Vector3
			if r < 0.6 then
				hand = startHand:Lerp(contact, smooth(r / 0.6))
			else
				local p = smooth((r - 0.6) / 0.4)
				hand = contact - normal * Config.Arms.ReachPenetration * p
				if not stung then
					stung = true
					playOnce(Config.Audio.WallSting, Config.Audio.WallStingVolume)
				end
				setGlitch(0.25 * (1 - p))
				-- the wall "pulls": a small tremble once the hand goes in
				camera.CFrame *= CFrame.Angles(math.rad(rng:NextNumber(-0.3, 0.3) * p), math.rad(rng:NextNumber(-0.3, 0.3) * p), 0)
			end
			local shoulder = camera.CFrame:PointToWorldSpace(Vector3.new(1.4, -1.9, 0.9))
			poseArm("Right", hand, hand - shoulder, camera)
		end
	end)

	------------------------------------------------------------------ 2) Enter
	local enterFrom = facePos
	local enterTo = wallPoint + normal * 0.3
	runPhase(timeline.Enter, function(a)
		local move = smooth(a)
		local shake = Config.Camera.EnterShake * (0.3 + a)
		local t = os.clock() * 9
		camera.CFrame = CFrame.lookAt(enterFrom:Lerp(enterTo, move), enterTo - normal)
			* CFrame.Angles(math.rad(math.noise(t, 0.1) * shake), math.rad(math.noise(0.4, t) * shake), math.rad(math.noise(t, t) * shake * 0.5))

		-- right hand keeps sinking, left hand follows into the wall
		local hand = contact - normal * (Config.Arms.ReachPenetration + 0.8 * move)
		poseArm("Right", hand, hand - camera.CFrame:PointToWorldSpace(Vector3.new(1.4, -1.9, 0.9)), camera)
		local l = span(a, 0.1, 0.6)
		if l > 0 then
			setArmVisible("Left", true)
			local startLeft = camera.CFrame:PointToWorldSpace(Vector3.new(-0.9, -2.0, -0.6))
			local leftHand = if l < 0.6
				then startLeft:Lerp(leftContact, smooth(l / 0.6))
				else leftContact - normal * Config.Arms.ReachPenetration * smooth((l - 0.6) / 0.4)
			poseArm("Left", leftHand, leftHand - camera.CFrame:PointToWorldSpace(Vector3.new(-1.4, -1.9, 0.9)), camera)
		end

		blackout.BackgroundTransparency = 1 - smooth(span(a, 0.15, 0.85))
		setDesaturation(smooth(a), Config.Desaturate.Blur * smooth(span(a, 0.3, 1)))
		setGlitch(0.8 * a * a)
		if breathing then
			breathing.Volume = lerp(Config.Audio.BreathingVolume * 0.6, Config.Audio.BreathingVolume, a)
			breathing.PlaybackSpeed = lerp(1, 1.2, a)
		end
	end)

	blackout.BackgroundTransparency = 0
	setGlitch(0)
	if breathing then
		breathing:Stop()
		breathing:Destroy()
	end

	------------------------------------------------------------------ 3) Fall
	-- A long fall in the dark: only the wind and the Backrooms hum, faint at first and growing.
	-- At the very end a short fragment is visible: the Level 0 carpet rushing up, then the impact.
	local wind = makeSound(Config.Audio.Wind, 0, true)
	if wind then
		wind:Play()
	end
	if not ambientSound then
		ambientSound = makeSound(Config.Audio.Ambient, 0, true)
		if ambientSound then
			ambientSound:Play()
		end
	end
	local fallStart = os.clock()
	local function setFallAudio()
		local f = math.clamp((os.clock() - fallStart) / timeline.Fall, 0, 1)
		if wind then
			wind.Volume = Config.Audio.WindVolume * smooth(span(f, 0, 0.15))
			wind.PlaybackSpeed = lerp(0.9, 1.2, f)
		end
		if ambientSound then
			ambientSound.Volume = Config.Audio.AmbientVolume * lerp(Config.Fall.HumStart, Config.Fall.HumEnd, f * f)
		end
	end

	runPhase(math.max(0, timeline.Fall - Config.Fall.Visible), function()
		setFallAudio()
	end)

	-- Landing spot: the server has moved the character to the Level 0 spawn by now.
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local right = look:Cross(Vector3.yAxis)
	local floorY = floorBelow(root.Position, { character, camera })
	local base = Vector3.new(root.Position.X, floorY, root.Position.Z)

	-- Face down on the carpet: camera close to the floor looking down-forward, hands flat on it.
	local pronePos = base - look * 0.5 + Vector3.new(0, 1.0, 0)
	local floorTarget = base + look * 0.6
	local proneCF = CFrame.lookAt(pronePos, floorTarget, look) * CFrame.Angles(0, 0, math.rad(-6))
	local kneelPos = base - look * 0.2 + Vector3.new(0, 2.3, 0)
	local kneelCF = CFrame.lookAt(kneelPos, base + look * 3)
	local standPos = head.Position + Vector3.new(0, 0.15, 0)
	local standCF = CFrame.lookAt(standPos, standPos + look)

	-- The visible fragment: dropping from under the ceiling, arms flailing, straight onto the carpet.
	local dropTop = pronePos + Vector3.new(0, Config.Fall.VisibleHeight, 0)
	setArmVisible("Right", true)
	setArmVisible("Left", true)
	runPhase(Config.Fall.Visible, function(a, elapsed)
		setFallAudio()
		local position = dropTop:Lerp(pronePos, a * a) -- accelerating
		local t = os.clock()
		local shake = Config.Camera.FallShake
		local pitch = math.noise(t * 3.1, 0.2) * shake
		local yaw = math.noise(0.7, t * 2.6) * shake
		local roll = math.sin(t * 5) * shake * 0.6
		camera.CFrame = CFrame.lookAt(position, floorTarget, look) * CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))

		-- arms flailing
		local w = elapsed * 12
		poseArmLocal(
			"Right",
			Vector3.new(1.3 + 0.35 * math.sin(w * 0.7), -0.1 + 0.8 * math.sin(w), -1.8 + 0.3 * math.cos(w * 1.3)),
			Vector3.new(1.0, -1.7, 0.5),
			camera
		)
		poseArmLocal(
			"Left",
			Vector3.new(-1.3 - 0.35 * math.sin(w * 0.8 + 1), -0.1 + 0.8 * math.sin(w + 2.1), -1.8 + 0.3 * math.cos(w * 1.1 + 1)),
			Vector3.new(-1.0, -1.7, 0.5),
			camera
		)

		blackout.BackgroundTransparency = smooth(span(a, 0, 0.3))
		setDesaturation(0.4, 1.5)
	end)

	------------------------------------------------------------------ 4) Impact
	blackout.BackgroundTransparency = 0
	setArmVisible("Right", false)
	setArmVisible("Left", false)
	if wind then
		wind:Stop()
		wind:Destroy()
	end
	playOnce(Config.Audio.Thud, Config.Audio.ThudVolume)
	runPhase(0.12, function()
		setGlitch(0.9)
	end)
	setGlitch(0)
	task.wait(math.max(0, timeline.ImpactHold - 0.12))

	------------------------------------------------------------------ 5) Wake up
	-- Hands planted either side of the face; shoulders start on the floor and rise with the push-up.
	local plants = {
		Right = { hand = base + look * 1.7 + right * 0.85, shoulderDown = base - look * 0.7 + right * 1.0 + Vector3.new(0, 0.35, 0) },
		Left = { hand = base + look * 1.55 - right * 0.9, shoulderDown = base - look * 0.7 - right * 1.0 + Vector3.new(0, 0.35, 0) },
	}
	local function poseHands(push: number, slide: number, lift: number)
		for side, plant in plants do
			local hand = plant.hand - look * 0.25 * slide + Vector3.new(0, 0.05 + lift, 0)
			local shoulderUp = plant.shoulderDown + Vector3.new(0, 1.3, 0) - look * 0.1
			local shoulder = plant.shoulderDown:Lerp(shoulderUp, push)
			poseArm(side, hand, hand - shoulder, camera)
		end
	end

	enableVHS()
	if ambientSound then
		TweenService:Create(ambientSound, TweenInfo.new(timeline.WakeUp), { Volume = Config.Audio.AmbientVolume }):Play()
	end

	setArmVisible("Right", true)
	setArmVisible("Left", true)
	local kick = math.rad(Config.Camera.ImpactKick)
	runPhase(timeline.WakeUp, function(a, elapsed)
		local settle = (1 - smooth(a)) * kick
		-- still dazed: slow breathing bob, fingers dragging slightly on the carpet
		local bob = math.sin(elapsed * 2.2) * 0.04
		camera.CFrame = (proneCF + Vector3.new(0, bob, 0)) * CFrame.Angles(settle * 0.4, 0, settle * 0.6)
		poseHands(0, smooth(span(a, 0.4, 1)) * 0.4, 0)
		blackout.BackgroundTransparency = smooth(a) * 0.95 + 0.05 * a
		setDesaturation(lerp(0.7, 0.3, a), lerp(Config.Desaturate.Blur * 1.4, 3, a))
		setGlitch(0.35 * (1 - a))
	end)
	blackout.BackgroundTransparency = 1
	setGlitch(0)

	------------------------------------------------------------------ 6) Stand up
	runPhase(timeline.StandUp, function(a, elapsed)
		-- 0 - 0.5: push up onto the knees with the hands on the carpet
		-- 0.5 - 1: hands come off the floor and the player stands up
		local cf: CFrame
		if a < 0.5 then
			local push = smooth(a / 0.5)
			cf = proneCF:Lerp(kneelCF, push)
			-- effort: a small shake while pushing
			cf *= CFrame.Angles(math.rad(math.noise(elapsed * 8, 0.3) * 1.2 * (1 - push)), 0, 0)
		else
			cf = kneelCF:Lerp(standCF, smooth((a - 0.5) / 0.5))
		end
		local sway = math.sin(elapsed * 3) * 0.03 * (1 - a)
		camera.CFrame = cf * CFrame.Angles(0, 0, sway)

		local showHands = a < 0.66
		setArmVisible("Right", showHands)
		setArmVisible("Left", showHands)
		if showHands then
			local push = smooth(span(a, 0, 0.5))
			local lift = smooth(span(a, 0.48, 0.66)) * 1.2
			poseHands(push, 0.4, lift)
		end

		setDesaturation(lerp(0.3, 0, a), lerp(3, 0, smooth(a)))
	end)

	------------------------------------------------------------------ Hand control back
	setDesaturation(0, 0)
	clearViewmodel()
	hideConnection:Disconnect()
	setCharacterHidden(character, false)
	camera.FieldOfView = oldFov
	camera.CFrame = standCF
	camera.CameraType = Enum.CameraType.Custom
	if Config.FirstPersonAfter then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end
	if controls then
		controls:Enable()
	end
	running = false
end

remote.OnClientEvent:Connect(function(action: string, trigger: BasePart?)
	if action == "Start" then
		play(trigger)
	end
end)
