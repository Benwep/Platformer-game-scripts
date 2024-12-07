local mobilityEvent = game.ReplicatedStorage.Events.Mobility
local ClientDest = game.ReplicatedStorage.Events.DestroyOnClient -- event for destroying something ONLY for PLAYER and not everyone on server
local DTStore = game:GetService("DataStoreService"):GetDataStore("StickersDatastore")
local animIDs = {
	["Dash"] = 132474881127098,
	["Jump"] = 124357803628347,
	["Climb"] = 109940810216166,
}
local playersData = {}
local loadedPlayers = {}
local debris = game:GetService("Debris")

local function PlayAnimation(animName,hum)
	local anim = Instance.new("Animation")
	anim.Name = animName
	local animID = animIDs[animName]
	
	if animID then
		anim.AnimationId = "http://www.roblox.com/asset/?id="..animIDs[animName]
		local track = hum:LoadAnimation(anim)
		track:Play()
	end
end
local function ApplyVelocity(VelParent,power)
	local velocity = Instance.new("BodyVelocity")
	velocity.MaxForce = Vector3.new(1,1,1) * math.huge
	velocity.Velocity = Vector3.new(0,1,0) * power
	velocity.Parent = VelParent
	
	return velocity
end
local function SaveData(player)
	for i=1,5 do
		local success,err = pcall(function()
			DTStore:SetAsync(player.UserId,playersData[player.UserId],{player.UserId})
		end)
		if success then
			break
		end
		task.wait(1)
	end
end
local function LoadData(player)
	for i=1,3 do
		local success,data = pcall(function()
			return DTStore:GetAsync(player.UserId)
		end)
		if success then
			if not data then
				local defaultData = {
					["FoundStickers"] = {},
				}
				data = defaultData
			end
			playersData[player.UserId] = data
			return data
		end
		task.wait(1)
	end
end
game.ReplicatedStorage.Events.PlayerLoaded.OnServerEvent:Connect(function(player)
	table.insert(loadedPlayers,player.UserId)
end)
local function CheckPlayersLoad(player)
	for index,userID in ipairs(loadedPlayers) do -- when we use table.insert we are not giving keys to user ids,so we must check through loop
		if userID == player.UserId then
			return index
		end
	end
end
game.Players.PlayerAdded:Connect(function(player)
	local plrData = LoadData(player)
	
	local timeout = 60
	local i = 0
	local playerLoaded = CheckPlayersLoad(player)
	repeat
		task.wait(1)
		i += 1
		if not playerLoaded then
			playerLoaded = CheckPlayersLoad(player)
			if playerLoaded then
				for key,found in pairs(plrData.FoundStickers) do
					if game.Workspace.Stickers:FindFirstChild(key) then
						ClientDest:FireClient(player,game.Workspace.Stickers:FindFirstChild(key))-- incase we've already collected sticker we should remove it
					end
				end
				break
			end
		end
	until i >= timeout
	
end)
local function UnloadPlayer(player)
	if CheckPlayersLoad(player) then
		table.remove(loadedPlayers,CheckPlayersLoad(player)) -- remove it to prevent bugs with loading/removing stickers after player rejoins
	end
end
game.Players.PlayerRemoving:Connect(function(player)
	UnloadPlayer(player)
	SaveData(player)
end)
game:BindToClose(function()
	for i,player in game.Players:GetPlayers() do
		UnloadPlayer(player)
		SaveData(player)
	end
end)
mobilityEvent.OnServerEvent:Connect(function(player,action)
	local char = player.Character
	local hum = char:FindFirstChild("Humanoid")
	local HumanoidRootPart = char:FindFirstChild("HumanoidRootPart")
	
	if action == "Dash" then
		local velocity = ApplyVelocity(HumanoidRootPart,1)
		
		local IsInAir = false
		local humTypes = {Enum.HumanoidStateType.Jumping,Enum.HumanoidStateType.FallingDown,Enum.HumanoidStateType.Freefall}
		
		for index,stateType in ipairs(humTypes) do
			if hum:GetState() == stateType then
				IsInAir = true
			end
		end
		if IsInAir then
			-- when we're in air,velocity works better,so we're gonna lower velocity to make dash same in any case
			velocity.Velocity = HumanoidRootPart.CFrame.lookVector * 60
		else
			velocity.Velocity = HumanoidRootPart.CFrame.lookVector * 90
		end
		
		velocity.Parent = HumanoidRootPart
		PlayAnimation("Dash",hum)
		
		debris:AddItem(velocity,0.1) -- destroy velocity almost immediately so it velocity won't slowly fade
	elseif action == "Jump" then
		local orb = nil -- nearest available orb
		local sizeMultiplier = 1 -- so orb could reach player
		for i,orbToCheck in game.Workspace.Orbs:GetChildren() do
			local heightDif = char.PrimaryPart.Position.Y - orbToCheck.Position.Y
			if heightDif < 15 and heightDif > 5 then
				sizeMultiplier = 3 -- in case orb is slightly lower then,increase so player would be able to reach it after for example performing a few orbs in a row
			else
				sizeMultiplier = 1 -- set back incase previous orb was lower than player
			end
			if (char.PrimaryPart.Position - orbToCheck.Position).Magnitude < (orbToCheck.Size.X * sizeMultiplier) then
				orb = orbToCheck
			end
		end
		
		if orb then
			-- we're gonna be able to perform double jump with orb if its near
			local velocity = ApplyVelocity(HumanoidRootPart,orb:WaitForChild("OrbStats").Height.Value * 10)
			
			orb.Color = orb.OrbStats.ActivationColor.Value
			task.delay(0.5,function() orb.Color = orb.OrbStats.DefaultColor.Value end) -- set orb colour back to default after set amount pf time passes(0.5 right now)
			PlayAnimation("Jump",hum)
			debris:AddItem(velocity,0.1)
		else
			--we're gonna be able to climb wall if its in front of us
			local frontDirection = (HumanoidRootPart.CFrame.LookVector * 5)
			local raycastDirection = frontDirection - Vector3.new(0,frontDirection.Y - HumanoidRootPart.Position.Y,0) 
			-- if we're multiplying vector,then we're multiplying each axe,we need axe Y to stay the same and aslong as we cannot change it directly we're gonna have to make it 0 and add needed y
			local raycastParams = RaycastParams.new()
			local playerChars = {}
			for i, plr in game.Players:GetPlayers() do
				if plr.Character then
					table.insert(playerChars,plr.Character) -- we don't want raycast to detect this or other players
				end
			end
			raycastParams.FilterDescendantsInstances = playerChars
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			local raycast = workspace:Raycast(HumanoidRootPart.Position, raycastDirection,raycastParams)
			if raycast and raycast.Instance then
				local wall = raycast.Instance
				if wall:FindFirstChild("CanClimb") and wall.CanClimb.Value then
					PlayAnimation("Climb",hum)
					game.ReplicatedStorage.Events.ChangeGravityEvent:FireClient(player,0) -- change the gravity so when we climb it wont drag player down
					for i=1,3 do
						local velocity = ApplyVelocity(HumanoidRootPart,(wall.Size.Y + wall.Position.Y - (HumanoidRootPart.Position.Y)))
						-- to climb we must go all the way up and a few more studs up for player to be able to get on it
						-- also we remove current player Y position so that we wont climb more then needed to get on the platform if player is higher than the bottom of the wall
						debris:AddItem(velocity,0.1)
						task.wait(0.3)
					end
					for index,animation in ipairs(hum:GetPlayingAnimationTracks()) do 
						-- because :GetPlayingAnimationTracks() returns an array(metatable) with each animation key being an index (we cant use table.find as it only checks index) we have to loop and check it via loop
						if animation.Name == "Climb" then
							animation:Stop() -- because i looped climb animation for visual effect,we should stop it manually
						end
					end
					game.ReplicatedStorage.Events.ChangeGravityEvent:FireClient(player,game.Workspace.Gravity) -- set it back to default
				end
			end
		end
	end
end)
for i,stickerPart in game.Workspace.Stickers:GetChildren() do
	stickerPart.Touched:Connect(function(touchedPart)
		local player = game.Players:FindFirstChild(touchedPart.Parent.Name)
		if player then
			ClientDest:FireClient(player,stickerPart,true)
			if playersData[player.UserId] then
				playersData[player.UserId].FoundStickers[stickerPart.Name] = true -- save sticker on player account.Also we're not using table insert to search it with just table.find
				SaveData(player)
			end
		end
	end)
end
