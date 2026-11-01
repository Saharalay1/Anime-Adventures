-- ===== MACRO SYSTEM (Main tab) =====
-- Waits for hub UI, then builds everything under table1.mainpage
do
	local function waitForHub(timeout)
		local t0 = os.clock()
		timeout = timeout or 30
		while os.clock() - t0 < timeout do
			if table1
				and table1.mainpage
				and table1.maintoggle
				and table1.maintoggleState
				and table1.player
				and table1.Workspace
				and table1.HttpService
				and table1.Players
			then
				return true
			end
			task.wait(0.1)
		end
		return false
	end

	if not waitForHub(30) then
		return
	end

	table1.macroSettings = table1.macroSettings or {
		failureretry = true,
		skipfailuresandmoveontothenextwave = true,
		wavebasedtime = true,
		autovotestart = true,
		startupdelay = 5,
		spaminterval = 0.05,
		maxspamattempts = 200,
	}

	table1.recording = false
	table1.replaying = false
	table1.currentMacroName = nil
	table1.recordedActions = {}
	table1.waveStartTimes = {}
	table1.currentWave = 0
	table1.lastPlaceArgs = nil
	table1.lastPlaceTime = 0
	table1.macroIgnoreReplay = false

	local endpoints = nil
	local unitsFolder = nil
	local waveValue = nil

	local function safeGetEndpoints()
		if endpoints and endpoints.Parent then return endpoints end
		local ok, rs = pcall(function() return game:GetService("ReplicatedStorage") end)
		if not ok or not rs then return nil end
		local e = rs:FindFirstChild("endpoints")
		if e then e = e:FindFirstChild("client_to_server") end
		endpoints = e
		return endpoints
	end

	local function safeGetUnits()
		if unitsFolder and unitsFolder.Parent then return unitsFolder end
		unitsFolder = table1.Workspace:FindFirstChild("_UNITS")
		return unitsFolder
	end

	local function safeGetWave()
		if waveValue and waveValue.Parent then return waveValue end
		waveValue = table1.Workspace:FindFirstChild("_wave_num")
		return waveValue
	end

	local ACTION_REMOTES = {
		spawn_unit = true,
		upgrade_unit_ingame = true,
		sell_unit_ingame = true,
		change_priority = true,
		use_active_attack = true,
		vote_start = true,
	}

	local function deepCopy(t)
		if type(t) ~= "table" then return t end
		local n = {}
		for k, v in pairs(t) do
			n[k] = deepCopy(v)
		end
		return n
	end

	local function getMoney()
		local ok, gui = pcall(function()
			return table1.player.PlayerGui.spawn_units.Lives.Frame.Resource.Money
		end)
		if not ok or not gui then return 0 end
		local text = gui.Text or tostring(gui.Value or "0")
		return tonumber((tostring(text):gsub("%D", ""))) or 0
	end

	local function getCurrentWave()
		local w = safeGetWave()
		return (w and w.Value) or 0
	end

	local function getTimeSinceWaveStart(wave)
		local start = table1.waveStartTimes[wave]
		if not start then return 0 end
		return os.clock() - start
	end

	local function ensureMacroFolder()
		local femboy = table1.Workspace:FindFirstChild("FEMBOY")
		if not femboy then
			femboy = Instance.new("Folder")
			femboy.Name = "FEMBOY"
			femboy.Parent = table1.Workspace
		end
		local configs = femboy:FindFirstChild("macroconfigs")
		if not configs then
			configs = Instance.new("Folder")
			configs.Name = "macroconfigs"
			configs.Parent = femboy
		end
		return configs
	end

	local function onWaveChanged(newWave)
		table1.currentWave = newWave
		if not table1.waveStartTimes[newWave] then
			table1.waveStartTimes[newWave] = os.clock()
		end
	end

	task.spawn(function()
		local w = safeGetWave()
		if w then
			onWaveChanged(w.Value)
			w.Changed:Connect(function(nv)
				onWaveChanged(nv)
			end)
		end
	end)

	task.spawn(function()
		local uf = safeGetUnits()
		if not uf then return end
		uf.ChildAdded:Connect(function(child)
			if not table1.recording then return end
			if not table1.lastPlaceArgs then return end
			if os.clock() - table1.lastPlaceTime > 1.5 then return end
			local unitName = child.Name
			for i = #table1.recordedActions, 1, -1 do
				local act = table1.recordedActions[i]
				if act.actionType == "spawn_unit" and not act.unitName then
					act.unitName = unitName
					act.unitInstancePath = child:GetFullName()
					break
				end
			end
			table1.lastPlaceArgs = nil
		end)
	end)

	do
		local okHook = pcall(function()
			local mt = getrawmetatable(game)
			local oldNamecall = mt.__namecall
			setreadonly(mt, false)
			mt.__namecall = newcclosure(function(self, ...)
				local method = getnamecallmethod()
				local args = {...}
				if (method == "FireServer" or method == "InvokeServer")
					and typeof(self) == "Instance"
					and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction"))
					and not self:IsA("UnreliableRemoteEvent")
				then
					local remoteName = self.Name
					if ACTION_REMOTES[remoteName] and table1.recording and not table1.replaying and not table1.macroIgnoreReplay then
						local wave = getCurrentWave()
						local timeOffset = getTimeSinceWaveStart(wave)
						local entry = {
							wave = wave,
							timeOffset = timeOffset,
							actionType = remoteName,
							method = method,
							args = deepCopy(args),
							unitName = nil,
							unitId = args[1],
							remotePath = self:GetFullName(),
							moneyAtTime = getMoney(),
							timestamp = os.clock(),
						}
						table.insert(table1.recordedActions, entry)
						if remoteName == "spawn_unit" then
							table1.lastPlaceArgs = args
							table1.lastPlaceTime = os.clock()
						end
					end
				end
				return oldNamecall(self, ...)
			end)
			setreadonly(mt, true)
		end)
	end

	function table1.clearTemporaryMacro()
		table1.recordedActions = {}
		table1.waveStartTimes = {}
		table1.currentMacroName = nil
		table1.lastPlaceArgs = nil
	end

	function table1.startRecording()
		if table1.recording then return end
		table1.clearTemporaryMacro()
		table1.recording = true
		onWaveChanged(getCurrentWave())
	end

	function table1.stopRecording()
		if not table1.recording then return end
		table1.recording = false
	end

	function table1.toggleRecording()
		if table1.recording then
			table1.stopRecording()
		else
			table1.startRecording()
		end
	end

	function table1.saveMacro(name)
		if type(name) ~= "string" or name == "" then return false end
		local folder = ensureMacroFolder()
		local data = {
			name = name,
			created = os.time(),
			settings = deepCopy(table1.macroSettings),
			actions = deepCopy(table1.recordedActions),
		}
		local json = table1.HttpService:JSONEncode(data)
		local existing = folder:FindFirstChild(name)
		if existing then existing:Destroy() end
		local sv = Instance.new("StringValue")
		sv.Name = name
		sv.Value = json
		sv.Parent = folder
		table1.currentMacroName = name
		return true
	end

	function table1.loadMacro(name)
		local folder = ensureMacroFolder()
		local sv = folder:FindFirstChild(name)
		if not sv or not sv:IsA("StringValue") then return false end
		local ok, data = pcall(function()
			return table1.HttpService:JSONDecode(sv.Value)
		end)
		if not ok or type(data) ~= "table" then return false end
		table1.recordedActions = data.actions or {}
		table1.currentMacroName = name
		return true
	end

	function table1.deleteMacro(name)
		local folder = ensureMacroFolder()
		local sv = folder:FindFirstChild(name)
		if sv then
			sv:Destroy()
			if table1.currentMacroName == name then
				table1.currentMacroName = nil
			end
			return true
		end
		return false
	end

	function table1.listMacros()
		local folder = ensureMacroFolder()
		local list = {}
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("StringValue") then
				table.insert(list, child.Name)
			end
		end
		return list
	end

	local function getRemoteByName(name)
		local ep = safeGetEndpoints()
		if not ep then return nil end
		return ep:FindFirstChild(name)
	end

	local function callRemote(entry)
		local remote = getRemoteByName(entry.actionType)
		if not remote then return false end
		local args = entry.args or {}
		table1.macroIgnoreReplay = true
		local success = false
		if entry.method == "InvokeServer" and remote:IsA("RemoteFunction") then
			local ok, result = pcall(function()
				return remote:InvokeServer(table.unpack(args))
			end)
			if ok then
				if entry.actionType == "spawn_unit"
					or entry.actionType == "upgrade_unit_ingame"
					or entry.actionType == "sell_unit_ingame"
				then
					success = (result == true)
				else
					success = true
				end
			end
		elseif remote:IsA("RemoteEvent") then
			local ok = pcall(function()
				remote:FireServer(table.unpack(args))
			end)
			success = ok
		end
		table1.macroIgnoreReplay = false
		return success
	end

	local function spamUntilSuccess(entry)
		local attempts = 0
		while attempts < table1.macroSettings.maxspamattempts do
			if table1.macroSettings.skipfailuresandmoveontothenextwave then
				if getCurrentWave() > entry.wave then
					return false
				end
			end
			if callRemote(entry) then
				return true
			end
			attempts = attempts + 1
			task.wait(table1.macroSettings.spaminterval)
		end
		return false
	end

	local function spamActiveAttack(entry)
		local attempts = 0
		while attempts < table1.macroSettings.maxspamattempts do
			if table1.macroSettings.skipfailuresandmoveontothenextwave and getCurrentWave() > entry.wave then
				return false
			end
			callRemote(entry)
			attempts = attempts + 1
			task.wait(table1.macroSettings.spaminterval)
			if attempts >= 5 then return true end
		end
		return false
	end

	function table1.replayMacro(name)
		if table1.replaying then return end
		if name then
			if not table1.loadMacro(name) then return end
		end
		if #table1.recordedActions == 0 then return end
		table1.replaying = true

		if table1.macroSettings.autovotestart then
			local voteRemote = getRemoteByName("vote_start")
			if voteRemote and voteRemote:IsA("RemoteFunction") then
				table1.macroIgnoreReplay = true
				pcall(function() voteRemote:InvokeServer() end)
				table1.macroIgnoreReplay = false
			end
		end

		local actionsByWave = {}
		for _, act in ipairs(table1.recordedActions) do
			local w = act.wave or 0
			actionsByWave[w] = actionsByWave[w] or {}
			table.insert(actionsByWave[w], act)
		end
		local waves = {}
		for w in pairs(actionsByWave) do table.insert(waves, w) end
		table.sort(waves)

		task.spawn(function()
			for _, wave in ipairs(waves) do
				while getCurrentWave() < wave do
					if not table1.replaying then return end
					task.wait(0.1)
				end
				if getCurrentWave() > wave and table1.macroSettings.skipfailuresandmoveontothenextwave then
					continue
				end
				local waveActions = actionsByWave[wave]
				table.sort(waveActions, function(a, b)
					return (a.timeOffset or 0) < (b.timeOffset or 0)
				end)
				if not table1.waveStartTimes[wave] then
					table1.waveStartTimes[wave] = os.clock()
				end
				local waveStartClock = table1.waveStartTimes[wave]
				for _, entry in ipairs(waveActions) do
					if not table1.replaying then return end
					if table1.macroSettings.skipfailuresandmoveontothenextwave and getCurrentWave() > wave then
						break
					end
					if table1.macroSettings.wavebasedtime then
						local targetTime = waveStartClock + (entry.timeOffset or 0)
						while os.clock() < targetTime do
							if not table1.replaying then return end
							if table1.macroSettings.skipfailuresandmoveontothenextwave and getCurrentWave() > wave then
								break
							end
							task.wait(0.05)
						end
					end
					if entry.actionType == "use_active_attack" then
						spamActiveAttack(entry)
					elseif entry.actionType == "spawn_unit"
						or entry.actionType == "upgrade_unit_ingame"
						or entry.actionType == "sell_unit_ingame"
					then
						spamUntilSuccess(entry)
					else
						callRemote(entry)
					end
				end
			end
			table1.replaying = false
		end)
	end

	function table1.stopReplay()
		table1.replaying = false
	end

	table1.Players.PlayerRemoving:Connect(function(p)
		if p == table1.player then
			table1.clearTemporaryMacro()
			table1.recording = false
			table1.replaying = false
		end
	end)

	table1.macroRecordToggle, table1.macroRecordChanged, table1.macroRecordAction =
		table1.maintoggle("Record Macro", "On", 1, table1.mainpage, true, 0, 0, 1)

	do
		local st = table1.maintoggleState[table1.macroRecordToggle]
		if st then
			st.actiontext = "REC"
			if st.actiontextbox then st.actiontextbox.Text = "REC" end
			table1.macroRecordToggle.Position = UDim2.new(0, 10, 0, 10)
			table1.macroRecordToggle:SetAttribute("LayoutOrder", 1)
		end
	end

	if table1.macroRecordAction then
		table1.macroRecordAction:Connect(function()
			table1.toggleRecording()
			local st = table1.maintoggleState[table1.macroRecordToggle]
			if st then
				local newMode = table1.recording and 1 or 0
				table1.macroRecordToggle:SetAttribute("Mode", newMode)
				st.currentmode = newMode
				st.lastMode = newMode
				if st.setoutline then st.setoutline(newMode, false) end
				if st.modechanged then st.modechanged:Fire(newMode) end
			end
		end)
	end

	table1.macroRecordChanged:Connect(function()
		local mode = table1.macroRecordToggle:GetAttribute("Mode") or 0
		if mode == 1 and not table1.recording then
			table1.startRecording()
		elseif mode == 0 and table1.recording then
			table1.stopRecording()
		end
	end)

	table1.macroInfoToggle, table1.macroInfoChanged =
		table1.maintoggle("Macro Info", "Refresh", 1, table1.mainpage, true, 3, 0)

	table1.macroInfoLabel = Instance.new("TextLabel")
	table1.macroInfoLabel.Name = "MacroInfoLabel"
	table1.macroInfoLabel.Size = UDim2.new(1, -16, 0, 160)
	table1.macroInfoLabel.Position = UDim2.new(0, 8, 0, 36)
	table1.macroInfoLabel.BackgroundTransparency = 1
	table1.macroInfoLabel.TextColor3 = table1.white
	table1.macroInfoLabel.Font = table1.font
	table1.macroInfoLabel.TextSize = 11
	table1.macroInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
	table1.macroInfoLabel.TextYAlignment = Enum.TextYAlignment.Top
	table1.macroInfoLabel.TextWrapped = true
	table1.macroInfoLabel.ZIndex = 5
	table1.macroInfoLabel.Text = "Wave: -\nMoney: -\nTime on wave: -\nMacro: (none)\nActions: 0"
	table1.macroInfoLabel.Parent = table1.macroInfoToggle

	do
		local st = table1.maintoggleState[table1.macroInfoToggle]
		if st then
			st.normalHeight = 200
			table1.macroInfoToggle:SetAttribute("LayoutHeight", 200)
			table1.macroInfoToggle.Size = UDim2.new(0, st.toggleWidth or 180, 0, 200)
			table1.macroInfoToggle:SetAttribute("LayoutOrder", 2)
		end
	end

	local function refreshMacroInfo()
		if not table1.macroInfoLabel or not table1.macroInfoLabel.Parent then return end
		local lines = {}
		table.insert(lines, "Wave: " .. tostring(getCurrentWave()))
		table.insert(lines, "Money: " .. tostring(getMoney()))
		table.insert(lines, string.format("Time on wave: %.2fs", getTimeSinceWaveStart(getCurrentWave())))
		table.insert(lines, "Macro: " .. (table1.currentMacroName or "(temporary)"))
		table.insert(lines, "Recording: " .. (table1.recording and "YES" or "no"))
		table.insert(lines, "Replaying: " .. (table1.replaying and "YES" or "no"))
		table.insert(lines, "Actions: " .. tostring(#table1.recordedActions))
		table.insert(lines, "----------")
		local byWave = {}
		for _, act in ipairs(table1.recordedActions) do
			byWave[act.wave] = byWave[act.wave] or {}
			table.insert(byWave[act.wave], act)
		end
		local waves = {}
		for w in pairs(byWave) do table.insert(waves, w) end
		table.sort(waves)
		for _, w in ipairs(waves) do
			table.insert(lines, string.format("Wave %d:", w))
			for _, act in ipairs(byWave[w]) do
				table.insert(lines, string.format("  [%.2fs] %s  %s",
					act.timeOffset or 0,
					act.actionType,
					tostring(act.unitName or act.unitId or "")))
			end
		end
		table1.macroInfoLabel.Text = table.concat(lines, "\n")
	end

	table1.macroInfoChanged:Connect(function()
		refreshMacroInfo()
	end)

	task.spawn(function()
		while table1.maingui and table1.maingui.Parent do
			if table1.macroInfoToggle and table1.macroInfoToggle.Parent then
				local st = table1.maintoggleState[table1.macroInfoToggle]
				if st and not st.folded then
					refreshMacroInfo()
				end
			end
			task.wait(0.5)
		end
	end)

	table1.macroNameBoxToggle, table1.macroNameBoxChanged, table1.macroNameBox =
		table1.maintoggle("Macro Name", "Set", 1, table1.mainpage, true, 3, 1)
	if table1.macroNameBox then
		table1.macroNameBox.Text = ""
		table1.macroNameBox.PlaceholderText = "macro name"
		pcall(function() table1.macroNameBox:SetAttribute("Numberlocked", false) end)
	end
	do local st = table1.maintoggleState[table1.macroNameBoxToggle]; if st then table1.macroNameBoxToggle:SetAttribute("LayoutOrder", 3) end end

	table1.macroSaveToggle, table1.macroSaveChanged =
		table1.maintoggle("Save Macro", "Save", 1, table1.mainpage, true, 3, 0)
	table1.macroSaveChanged:Connect(function()
		local name = table1.macroNameBox and table1.macroNameBox.Text or ""
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" then table1.saveMacro(name) refreshMacroInfo() end
	end)
	do local st = table1.maintoggleState[table1.macroSaveToggle]; if st then table1.macroSaveToggle:SetAttribute("LayoutOrder", 4) end end

	table1.macroLoadToggle, table1.macroLoadChanged =
		table1.maintoggle("Load Macro", "Load", 1, table1.mainpage, true, 3, 0)
	table1.macroLoadChanged:Connect(function()
		local name = table1.macroNameBox and table1.macroNameBox.Text or ""
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" then table1.loadMacro(name) refreshMacroInfo() end
	end)
	do local st = table1.maintoggleState[table1.macroLoadToggle]; if st then table1.macroLoadToggle:SetAttribute("LayoutOrder", 5) end end

	table1.macroDeleteToggle, table1.macroDeleteChanged =
		table1.maintoggle("Delete Macro", "Delete", 1, table1.mainpage, true, 3, 0)
	table1.macroDeleteChanged:Connect(function()
		local name = table1.macroNameBox and table1.macroNameBox.Text or ""
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" then table1.deleteMacro(name) refreshMacroInfo() end
	end)
	do local st = table1.maintoggleState[table1.macroDeleteToggle]; if st then table1.macroDeleteToggle:SetAttribute("LayoutOrder", 6) end end

	table1.macroReplayToggle, table1.macroReplayChanged =
		table1.maintoggle("Replay Macro", "Replay", 1, table1.mainpage, true, 3, 0)
	table1.macroReplayChanged:Connect(function()
		local name = table1.macroNameBox and table1.macroNameBox.Text or ""
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" then table1.replayMacro(name) else table1.replayMacro() end
		refreshMacroInfo()
	end)
	do local st = table1.maintoggleState[table1.macroReplayToggle]; if st then table1.macroReplayToggle:SetAttribute("LayoutOrder", 7) end end

	table1.macroStopReplayToggle, table1.macroStopReplayChanged =
		table1.maintoggle("Stop Replay", "Stop", 1, table1.mainpage, true, 3, 0)
	table1.macroStopReplayChanged:Connect(function()
		table1.stopReplay()
		refreshMacroInfo()
	end)
	do local st = table1.maintoggleState[table1.macroStopReplayToggle]; if st then table1.macroStopReplayToggle:SetAttribute("LayoutOrder", 8) end end

	table1.macroWaveTimeToggle, table1.macroWaveTimeChanged =
		table1.maintoggle("Wave Based Time", "On", 1, table1.mainpage, true, 0, 0)
	table1.macroWaveTimeChanged:Connect(function()
		table1.macroSettings.wavebasedtime = (table1.macroWaveTimeToggle:GetAttribute("Mode") or 0) == 1
	end)
	do local st = table1.maintoggleState[table1.macroWaveTimeToggle]; if st then table1.macroWaveTimeToggle:SetAttribute("LayoutOrder", 9) end end

	table1.macroAutoVoteToggle, table1.macroAutoVoteChanged =
		table1.maintoggle("Auto Vote Start", "On", 1, table1.mainpage, true, 0, 0)
	table1.macroAutoVoteChanged:Connect(function()
		table1.macroSettings.autovotestart = (table1.macroAutoVoteToggle:GetAttribute("Mode") or 0) == 1
	end)
	do local st = table1.maintoggleState[table1.macroAutoVoteToggle]; if st then table1.macroAutoVoteToggle:SetAttribute("LayoutOrder", 10) end end

	table1.macroSkipFailToggle, table1.macroSkipFailChanged =
		table1.maintoggle("Skip Failures Next Wave", "On", 1, table1.mainpage, true, 0, 0)
	table1.macroSkipFailChanged:Connect(function()
		table1.macroSettings.skipfailuresandmoveontothenextwave = (table1.macroSkipFailToggle:GetAttribute("Mode") or 0) == 1
	end)
	do local st = table1.maintoggleState[table1.macroSkipFailToggle]; if st then table1.macroSkipFailToggle:SetAttribute("LayoutOrder", 11) end end

	task.defer(function()
		local any = table1.macroRecordToggle
		if any and table1.maintoggleState[any] and table1.maintoggleState[any].relayout then
			table1.maintoggleState[any].relayout()
		end
		if table1.mainpage and table1.mainpage:IsA("ScrollingFrame") then
			local maxY = 0
			for _, ch in ipairs(table1.mainpage:GetChildren()) do
				if ch:IsA("GuiObject") and ch:GetAttribute("Maintoggle") then
					local bottom = ch.Position.Y.Offset + ch.Size.Y.Offset
					if bottom > maxY then maxY = bottom end
				end
			end
			if maxY > 0 then
				table1.mainpage.CanvasSize = UDim2.new(0, 0, 0, maxY + 40)
			end
		end
	end)
end
