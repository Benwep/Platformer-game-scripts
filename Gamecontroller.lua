local mobilityEvent = game.ReplicatedStorage.Events.Mobility
local ClientDest = game.ReplicatedStorage.Events.DestroyOnClient -- event for destroying something ONLY for PLAYER and not everyone on server
local DTStore = game:GetService("DataStoreService"):GetDataStore("StickersDatastore")
local animIDs = {
	["Dash"] = 132474881127098,
	["Jump"] = 124357803628347,
	["Climb"] = 109940810216166,
}
local playersData = {}
local loadedPlayers = {} -- We need to remove all previously collected stickers on user's client, so we use contentProvider service to preload all assets(parts) so that we won't start removing stickers before game is loaded on client
local debris = game:GetService("Debris")
local tweenService = game:GetService("TweenService")

local function PlayAnimation(animName,hum)
	local anim = Instance.new("Animation")
	anim.Name = animName
	local animID = animIDs[animName] -- search for animation in animIds table by its name
	
	if animID then -- if it exists we play it
		anim.AnimationId = "http://www.roblox.com/asset/?id="..animIDs[animName] -- set the id
		local track = hum:LoadAnimation(anim) -- load animation on character before playing
		track:Play()
	end
end
local function ApplyVelocity(VelParent,power)
	local velocity = Instance.new("BodyVelocity")
	velocity.MaxForce = Vector3.new(1,1,1) * math.huge -- setting max force to be huge so it won't cap at low numbers
	velocity.Velocity = Vector3.new(0,1,0) * power -- we only use this function to apply velocity by Y axis,but in case we want to change it how u want to we return velocity instance
	velocity.Parent = VelParent
	
	return velocity
end
local function SaveData(player)
	for i=1,5 do
		local success,err = pcall(function()
			DTStore:SetAsync(player.UserId,playersData[player.UserId],{player.UserId}) -- overwriting user's previous data
		end)
		if success then -- stop the loop if successful
			break
		end
		task.wait(1)
	end
end
local function LoadData(player)
	for i=1,3 do
		local success,data = pcall(function()
			return DTStore:GetAsync(player.UserId) --trying to load users data
		end)
		if success then
			if not data then -- if user hasn't played previously or doesn't have data then we set it to default
				local defaultData = {
					["FoundStickers"] = {},
				}
				data = defaultData
			end
			playersData[player.UserId] = data -- save users data in script so we won't need to call server again
			return data
		end
		task.wait(1)
	end
end
game.ReplicatedStorage.Events.PlayerLoaded.OnServerEvent:Connect(function(player) -- once client script finished loading assets via contentProvider service it sends signal so that we would mark player as loaded
	table.insert(loadedPlayers,player.UserId)
end)
local function CheckPlayersLoad(player) -- check if player's client fully loaded
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
	repeat -- script will wait until player loads before doing something
		task.wait(1)
		i += 1
		if not playerLoaded then
			playerLoaded = CheckPlayersLoad(player)
			if playerLoaded then
				for key,found in pairs(plrData.FoundStickers) do -- loop through stickers saved in player data
					if game.Workspace.Stickers:FindFirstChild(key) then -- if there are stickers in workspace with the same name as in player data then we call to client to remove it(remove it locally so it would only be removed to that user)
						ClientDest:FireClient(player,game.Workspace.Stickers:FindFirstChild(key))-- incase we've already collected sticker we should remove it
					end
				end
				break
			end
		end
	until i >= timeout
	
end)
local function UnloadPlayer(player)
	if CheckPlayersLoad(player) then -- if player was added to loaded players we would remove them, we need to do that to increase perfomance by keeping table small
		table.remove(loadedPlayers,CheckPlayersLoad(player)) -- remove it to prevent bugs with loading/removing stickers after player rejoins
	end
end
game.Players.PlayerRemoving:Connect(function(player) -- once player leaves we're gonna remove him from loaded players table
	UnloadPlayer(player)
	SaveData(player) -- save data to prevent data loss
end)
game:BindToClose(function() -- if player doesnt leave and its just server shutting down we need to use this instead of playerRemoving
	for i,player in game.Players:GetPlayers() do
		UnloadPlayer(player)
		SaveData(player)
	end
end)
mobilityEvent.OnServerEvent:Connect(function(player,action) -- client fires this event once it detects inputBegan and key pressed is what we set them on client
	local char = player.Character
	local hum = char:FindFirstChild("Humanoid")
	local HumanoidRootPart = char:FindFirstChild("HumanoidRootPart")
	-- actions will be passed from client based on which key was pressed
	if action == "Dash" then
		local velocity = ApplyVelocity(HumanoidRootPart,1)
		
		local IsInAir = false
		local humTypes = {Enum.HumanoidStateType.Jumping,Enum.HumanoidStateType.FallingDown,Enum.HumanoidStateType.Freefall} -- types which will count as being in air
		
		for index,stateType in ipairs(humTypes) do
			if hum:GetState() == stateType then 
				IsInAir = true -- if our state Type matches one of those then it marks that player's in air
			end
		end
		if IsInAir then
			-- when we're in air,velocity is stronger,so we're gonna lower velocity to make dash same in any case
			velocity.Velocity = HumanoidRootPart.CFrame.lookVector * 60
		else
			velocity.Velocity = HumanoidRootPart.CFrame.lookVector * 90
		end
		
		velocity.Parent = HumanoidRootPart -- apply velocity to character so it would work on it
		PlayAnimation("Dash",hum)
		
		debris:AddItem(velocity,0.1) -- destroy velocity almost immediately so it velocity won't slowly fade
	elseif action == "Jump" then
		local orb = nil -- nearest available orb
		local sizeMultiplier = 1 -- so orb could reach player
		for i,orbToCheck in game.Workspace.Orbs:GetChildren() do
			local heightDif = char.PrimaryPart.Position.Y - orbToCheck.Position.Y -- distance between character and orb that's gonna trigger
			if heightDif < 15 and heightDif > 5 then
				sizeMultiplier = 3 -- in case orb is slightly lower then,increase so player would be able to reach it after for example performing a few orbs in a row
			else
				sizeMultiplier = 1 -- set back incase previous orb was lower than player
			end
			if (char.PrimaryPart.Position - orbToCheck.Position).Magnitude < (orbToCheck.Size.X * sizeMultiplier) then -- we're looping through all orbs to find the nearest one to our character
				orb = orbToCheck
			end
		end
		
		if orb then -- if there's orb nearby
			-- we're gonna be able to perform double jump with orb if its near
			local velocity = ApplyVelocity(HumanoidRootPart,orb:WaitForChild("OrbStats").Height.Value * 10)
			
			orb.Color = orb.OrbStats.ActivationColor.Value -- set it's color to already choosen one on activation
			task.delay(0.5,function() orb.Color = orb.OrbStats.DefaultColor.Value end) -- set orb colour back to default after set amount pf time passes(0.5 right now)
			PlayAnimation("Jump",hum)
			debris:AddItem(velocity,0.1)
		else --aslong as there're just 3 events we can just use else instead of checking if action == "Climb"
			--we're gonna be able to climb wall if its in front of us
			local frontDirection = (HumanoidRootPart.CFrame.LookVector * 5) -- direction forward from player
			local raycastDirection = frontDirection - Vector3.new(0,frontDirection.Y - HumanoidRootPart.Position.Y,0) 
			-- if we're multiplying vector,then we're multiplying each axe,we need axe Y to stay the same and aslong as we cannot change it directly we're gonna have to make it 0 and add needed y
			local raycastParams = RaycastParams.new()
			local playerChars = {plr.Character} -- we're gonna use this table as a blacklist for raycast so that it will ignore our character if somehow it finds itself instead of wall
			raycastParams.FilterDescendantsInstances = playerChars
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			local raycast = workspace:Raycast(HumanoidRootPart.Position, raycastDirection,raycastParams)
			if raycast and raycast.Instance then -- if raycast found something infront
				local wall = raycast.Instance
				if wall:FindFirstChild("CanClimb") and wall.CanClimb.Value then -- check if its really a wall and if its climbable
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
for index,slingshot in game.Workspace.Interactibles.Slingshots:GetChildren() do -- we connect each slingshot's proximity prompt to a function
	slingshot.PrimaryPart.ProximityPrompt.Triggered:Connect(function(playerWhoTriggered) -- function's gonna run when we activate prompt
		local targetPosition = slingshot.PlayerTargetPos.Position -- position we're gonna get launched at
		local launchTime = 0.05 -- time needed to complete animation/launch
		local height = 25 -- Height of the arc
		game.ReplicatedStorage.Events.ChangeGravityEvent:FireClient(playerWhoTriggered,0) -- removing gravity for player to not fall down during animation

		local function calculateCurve(startPos, endPos, height)
			return function(alpha)
				local midPos = (startPos + endPos) / 2 + Vector3.new(0, height, 0) -- find the center between start and end positions
				return startPos:Lerp(midPos, alpha):Lerp(midPos:Lerp(endPos, alpha), alpha) -- Returns a CFrame interpolated between itself and goal by the fraction alpha.
			end
		end

		local character = playerWhoTriggered.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local curve = calculateCurve(slingshot.PlayerPos.Position, targetPosition, height) -- PlayerPos is a part on top of slingshot determining a pos where player would start launch
			-- Making a Tween like effect using interpolation
			for i = 0, 1, 0.01 do -- Finally launch the player
				task.wait(launchTime * 0.01)
				character.PrimaryPart.CFrame = CFrame.new(curve(i))
			end
		end
		game.ReplicatedStorage.Events.ChangeGravityEvent:FireClient(playerWhoTriggered,game.Workspace.Gravity) --setting gravity back to normal
	end)
end
for i,stickerPart in game.Workspace.Stickers:GetChildren() do
	stickerPart.Touched:Connect(function(touchedPart) -- connect all stickers in workspace so that we would be able to collect them
		local player = game.Players:FindFirstChild(touchedPart.Parent.Name)
		if player then -- if instance that touched sticker is a part of a player then we can proceed
			ClientDest:FireClient(player,stickerPart,true) -- firing event to destroy sticker on client
			if playersData[player.UserId] then -- if we've previously loaded playerdata in that array then we can input this sticker
				playersData[player.UserId].FoundStickers[stickerPart.Name] = true -- save sticker on player account.Also we're not using table insert to search it with just table.find
				SaveData(player)
			end
		end
	end)
end
