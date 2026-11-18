--!strict
-- NoclipConfig: every tunable value for the first-person "noclip into the Backrooms" sequence.
-- Change numbers here; you shouldn't need to touch the client or server scripts.

local Config = {
	-- Any BasePart with this CollectionService tag starts the sequence when touched.
	-- Place it right in front of the wall, with its front face (LookVector) pointing INTO the wall.
	TriggerTag = "NoclipTrigger",
	-- BasePart in Workspace where the player lands (Backrooms Level 0 spawn). Searched recursively.
	-- The player gets up facing this part's front face.
	SpawnName = "Level0Spawn",
	-- RemoteEvent created in ReplicatedStorage by the server script.
	RemoteName = "NoclipSequence",
	-- Seconds before the same player can trigger it again.
	CooldownSeconds = 12,
	-- Keep the player in first person after the sequence.
	FirstPersonAfter = true,

	-- Timeline (seconds). Total ~10.3s.
	Timeline = {
		Reach = 1.6, -- camera turns to the wall, the hand reaches out and sinks into it
		Enter = 2.0, -- the body pushes slowly into the wall while the screen fades to black
		Fall = 3.2, -- long fall in the dark, ending with a short visible drop (Fall.Visible)
		ImpactHold = 0.7, -- hard cut to black on hitting the floor
		WakeUp = 1.0, -- fade in lying on the floor, looking at the ceiling
		StandUp = 1.8, -- push off the floor and get up
	},

	Camera = {
		FieldOfView = 80, -- FOV during the sequence
		EnterShake = 0.6, -- degrees of jitter while pushing into the wall
		FallShake = 6, -- degrees of head jerking while falling
		ImpactKick = 14, -- degrees the camera snaps on impact
	},

	Arms = {
		-- Hand position for the reach, in camera space (x right, y up, -z forward).
		ReachStart = Vector3.new(1.1, -2.3, -0.9),
		ReachPenetration = 1.4, -- how far (studs) the hand sinks into the wall
	},

	Desaturate = {
		Saturation = -1, -- 0 = normal, -1 = black and white
		Contrast = 0.35,
		Brightness = -0.1,
		Blur = 8, -- max blur while entering the wall / waking up
	},

	Glitch = {
		Bars = 18, -- pool size of glitch/static bars
		MaxOpacity = 0.7,
	},

	Fall = {
		-- Most of the fall is black: only the wind and the Backrooms hum, which grows louder.
		Visible = 0.7, -- seconds visible at the end: dropping onto the Level 0 carpet
		VisibleHeight = 7.5, -- studs above the landing spot where the visible drop starts
		HumStart = 0.04, -- hum volume at the start of the fall (fraction of Audio.AmbientVolume)
		HumEnd = 0.6, -- hum volume right before the impact (it reaches 100% while waking up)
	},

	Audio = {
		-- Replace with your own IDs. "rbxassetid://0" (or "") disables a sound.
		Breathing = "rbxassetid://0", -- loop while reaching and entering
		BreathingVolume = 0.9,
		WallSting = "rbxassetid://0", -- the moment the hand goes through the wall
		WallStingVolume = 0.6,
		Wind = "rbxassetid://0", -- loop while falling
		WindVolume = 0.8,
		Thud = "rbxassetid://0", -- hitting the floor
		ThudVolume = 1,
		Ambient = "rbxassetid://0", -- looping Level 0 hum after waking up
		AmbientVolume = 0.35,
	},

	VHS = {
		Enabled = true,
		ScanlineSpacing = 4, -- pixels between scanlines
		ScanlineTransparency = 0.82,
		TintColor = Color3.fromRGB(255, 240, 205),
		Saturation = -0.2,
		Contrast = 0.12,
		Label = "PLAY ▶",
		ShowTimestamp = true,
		TrackingBar = true, -- a soft bar that rolls down the screen
	},
}

return Config
