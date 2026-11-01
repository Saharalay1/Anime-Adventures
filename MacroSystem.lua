-- ============================================================
-- MACRO SYSTEM — paste right before:
--   -- beginning of absolute idk what i coded music stuff, dont touch
-- ============================================================
do
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
	table1.macrolistnames = {}

	local endpoints, unitsFolder, waveValue = nil, nil, nil

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
		for k, v in pairs(t) do n[k] = deepCopy(v) end
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

	local function ensureAutoloadPath()
		if not isfolder(table1.folder1) then makefolder(table1.folder1) end
		return table1.folder1 .. "/autoload.json"
	end

	local function readAutoload()
		local path = ensureAutoloadPath()
		local data = { enabled = false, rezeConfig = "", macroConfig = "" }
		if isfile and isfile(path) then
			local ok, decoded = pcall(function()
				return table1.HttpService:JSONDecode(readfile(path))
			end)
			if ok and type(decoded) == "table" then
				data.enabled = decoded.enabled == true
				data.rezeConfig = tostring(decoded.rezeConfig or "")
				data.macroConfig = tostring(decoded.macroConfig or "")
			end
		end
		return data
	end

	local function writeAutoload(data)
		local path = ensureAutoloadPath()
		pcall(function()
			writefile(path, table1.HttpService:JSONEncode({
				enabled = data.enabled == true,
				rezeConfig = tostring(data.rezeConfig or ""),
				macroConfig = tostring(data.macroConfig or ""),
			}))
		end)
	end

	table1.autoloadData = readAutoload()

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
			w.Changed:Connect(function(nv) onWaveChanged(nv) end)
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

	pcall(function()
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
					local entry = {
						wave = wave,
						timeOffset = getTimeSinceWaveStart(wave),
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
		if table1.recording then table1.stopRecording() else table1.startRecording() end
	end

	function table1.getMacroList()
		local folder = ensureMacroFolder()
		table1.macrolistnames = {}
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("StringValue") then
				table.insert(table1.macrolistnames, child.Name)
			end
		end
		table.sort(table1.macrolistnames)
		return table1.macrolistnames
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
		if type(data.settings) == "table" then
			for k, v in pairs(data.settings) do
				table1.macroSettings[k] = v
			end
		end
		return true
	end

	function table1.deleteMacro(name)
		local folder = ensureMacroFolder()
		local sv = folder:FindFirstChild(name)
		if sv then
			sv:Destroy()
			if table1.currentMacroName == name then table1.currentMacroName = nil end
			return true
		end
		return false
	end

	function table1.createMacro(name)
		if type(name) ~= "string" or name == "" then return false end
		local folder = ensureMacroFolder()
		if folder:FindFirstChild(name) then return false end
		local data = {
			name = name,
			created = os.time(),
			settings = deepCopy(table1.macroSettings),
			actions = {},
		}
		local sv = Instance.new("StringValue")
		sv.Name = name
		sv.Value = table1.HttpService:JSONEncode(data)
		sv.Parent = folder
		table1.currentMacroName = name
		table1.recordedActions = {}
		return true
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
				if getCurrentWave() > entry.wave then return false end
			end
			if callRemote(entry) then return true end
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

	if table1.mainpage and table1.mainpage:IsA("ScrollingFrame") then
		table1.mainpage.CanvasSize = UDim2.new(0, 0, 0, (table1.frameheight - 80) * 20)
	end

	table1.macroRecordToggle, table1.macroRecordChanged, table1.macroRecordAction =
		table1.maintoggle("Record Macro", "On", 1, table1.mainpage, true, 0, 0, 1)
	do
		local st = table1.maintoggleState[table1.macroRecordToggle]
		if st then
			st.actiontext = "REC"
			if st.actiontextbox then st.actiontextbox.Text = "REC" end
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

	table1.rebuildMacroSelection = function()
		local savedOrder, savedPos
		if table1.macroSelectMain and table1.macroSelectMain.Parent then
			savedOrder = table1.macroSelectMain:GetAttribute("LayoutOrder")
			savedPos = table1.macroSelectMain.Position
			table1.macroSelectMain:Destroy()
		end
		table1.getMacroList()
		local args = {"Macro Selection"}
		if #table1.macrolistnames == 0 then
			table.insert(args, "None")
		else
			for _, n in ipairs(table1.macrolistnames) do
				table.insert(args, n)
			end
		end
		table.insert(args, 1)
		table.insert(args, table1.mainpage)
		table.insert(args, true)
		table.insert(args, 4)
		table.insert(args, 0)
		table1.macroSelectMain, table1.macroSelectChanged = table1.maintoggle(table.unpack(args))
		if savedOrder then table1.macroSelectMain:SetAttribute("LayoutOrder", savedOrder) end
		if savedPos then table1.macroSelectMain.Position = savedPos end
		table1.macroSelectMain:SetAttribute("LayoutOrder", 2)
		table1.macroSelectChanged:Connect(function(mode)
			local list = table1.macrolistnames
			if #list == 0 then return end
			local name = list[mode]
			if name and table1.macroNameBox then
				table1.macroNameBox.Text = name
			end
			if name then
				table1.loadMacro(name)
				if table1.refreshMacroInfo then table1.refreshMacroInfo() end
			end
		end)
	end
	table1.rebuildMacroSelection()

	table1.macroConfigActions, table1.macroConfigActionsChanged, table1.macroNameBox =
		table1.maintoggle("Macro Configurations", "Save", "Load", "Delete", "Create", 1, table1.mainpage, true, 3, 1)
	table1.macroConfigActions:SetAttribute("LayoutOrder", 3)
	if table1.macroNameBox then
		table1.macroNameBox.Text = ""
		table1.macroNameBox.PlaceholderText = "Macro Name"
		pcall(function()
			table1.macroNameBox:SetAttribute("Numberlocked", false)
			table1.macroNameBox:SetAttribute("preventchange", true)
		end)
	end
	table1.macroConfigActionsChanged:Connect(function(mode)
		local name = table1.macroNameBox and table1.macroNameBox.Text or ""
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if mode == 1 then
			if name ~= "" then table1.saveMacro(name) end
		elseif mode == 2 then
			if name ~= "" then table1.loadMacro(name) end
		elseif mode == 3 then
			if name ~= "" then table1.deleteMacro(name) end
		elseif mode == 4 then
			if name ~= "" then table1.createMacro(name) end
		end
		table1.rebuildMacroSelection()
		if table1.refreshMacroInfo then table1.refreshMacroInfo() end
	end)

	table1.macroReplayToggle, table1.macroReplayChanged =
		table1.maintoggle("Macro Replay", "Replay", "Stop", 1, table1.mainpage, true, 3, 0)
	table1.macroReplayToggle:SetAttribute("LayoutOrder", 4)
	table1.macroReplayChanged:Connect(function(mode)
		if mode == 1 then
			local name = table1.macroNameBox and table1.macroNameBox.Text or ""
			name = name:gsub("^%s+", ""):gsub("%s+$", "")
			if name ~= "" then table1.replayMacro(name) else table1.replayMacro() end
		elseif mode == 2 then
			table1.stopReplay()
		end
		if table1.refreshMacroInfo then table1.refreshMacroInfo() end
	end)

	table1.macroSettingsToggle, table1.macroSettingsChanged =
		table1.maintoggle("Macro Settings", "Wave Based Time", "Auto Vote Start", "Skip Failures Next Wave", 1, table1.mainpage, true, 1, 0)
	table1.macroSettingsToggle:SetAttribute("LayoutOrder", 5)
	do
		if table1.macroSettings.wavebasedtime then
			table1.macroSettingsToggle:SetAttribute("Selected1", true)
		end
		if table1.macroSettings.autovotestart then
			table1.macroSettingsToggle:SetAttribute("Selected2", true)
		end
		if table1.macroSettings.skipfailuresandmoveontothenextwave then
			table1.macroSettingsToggle:SetAttribute("Selected3", true)
		end
	end
	table1.macroSettingsChanged:Connect(function(idx, selected)
		if idx == 1 then
			table1.macroSettings.wavebasedtime = selected == true
		elseif idx == 2 then
			table1.macroSettings.autovotestart = selected == true
		elseif idx == 3 then
			table1.macroSettings.skipfailuresandmoveontothenextwave = selected == true
		end
	end)

	table1.rebuildMacroAutoloadSelect = function()
		local savedOrder, savedPos
		if table1.macroAutoloadSelect and table1.macroAutoloadSelect.Parent then
			savedOrder = table1.macroAutoloadSelect:GetAttribute("LayoutOrder")
			savedPos = table1.macroAutoloadSelect.Position
			table1.macroAutoloadSelect:Destroy()
		end
		table1.getMacroList()
		local args = {"Macro Autoload Target", "None"}
		for _, n in ipairs(table1.macrolistnames) do
			table.insert(args, n)
		end
		table.insert(args, 1)
		table.insert(args, table1.mainpage)
		table.insert(args, true)
		table.insert(args, 4)
		table.insert(args, 0)
		table1.macroAutoloadSelect, table1.macroAutoloadSelectChanged = table1.maintoggle(table.unpack(args))
		if savedOrder then table1.macroAutoloadSelect:SetAttribute("LayoutOrder", savedOrder) else table1.macroAutoloadSelect:SetAttribute("LayoutOrder", 6) end
		if savedPos then table1.macroAutoloadSelect.Position = savedPos end
		table1.macroAutoloadSelectChanged:Connect(function(mode)
			if mode <= 1 then
				table1.autoloadData.macroConfig = ""
			else
				local name = table1.macrolistnames[mode - 1]
				table1.autoloadData.macroConfig = name or ""
			end
			writeAutoload(table1.autoloadData)
		end)
	end
	table1.rebuildMacroAutoloadSelect()

	table1.macroAutoloadEnable, table1.macroAutoloadEnableChanged =
		table1.maintoggle("Macro Autoload", "On", 1, table1.mainpage, true, 0, 0)
	table1.macroAutoloadEnable:SetAttribute("LayoutOrder", 7)
	if table1.autoloadData.enabled then
		table1.macroAutoloadEnable:SetAttribute("Mode", 1)
		local st = table1.maintoggleState[table1.macroAutoloadEnable]
		if st then
			st.currentmode = 1
			st.lastMode = 1
			if st.setoutline then st.setoutline(1, false) end
		end
	end
	table1.macroAutoloadEnableChanged:Connect(function()
		local mode = table1.macroAutoloadEnable:GetAttribute("Mode") or 0
		table1.autoloadData.enabled = (mode == 1)
		writeAutoload(table1.autoloadData)
	end)

	table1.macroInfoToggle, table1.macroInfoChanged =
		table1.maintoggle("Macro Info", "Refresh", 1, table1.mainpage, true, 3, 0)
	table1.macroInfoToggle:SetAttribute("LayoutOrder", 99)

	table1.macroInfoLabel = Instance.new("TextLabel")
	table1.macroInfoLabel.Name = "MacroInfoLabel"
	table1.macroInfoLabel.Size = UDim2.new(1, -16, 0, 40)
	table1.macroInfoLabel.Position = UDim2.new(0, 8, 0, 58)
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

	table1.refreshMacroInfo = function()
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
		local text = table.concat(lines, "\n")
		table1.macroInfoLabel.Text = text
		local lineCount = #lines
		local labelH = math.max(40, lineCount * 14 + 8)
		table1.macroInfoLabel.Size = UDim2.new(1, -16, 0, labelH)
		local totalH = 58 + labelH + 12
		local st = table1.maintoggleState[table1.macroInfoToggle]
		if st then
			st.normalHeight = totalH
			table1.macroInfoToggle:SetAttribute("LayoutHeight", totalH)
			if not st.folded then
				table1.macroInfoToggle.Size = UDim2.new(0, st.toggleWidth or 180, 0, totalH)
			end
			if st.relayout then st.relayout() end
		end
		if table1.mainpage and table1.mainpage:IsA("ScrollingFrame") then
			local maxY = 0
			for _, ch in ipairs(table1.mainpage:GetChildren()) do
				if ch:IsA("GuiObject") and ch:GetAttribute("Maintoggle") then
					local bottom = ch.Position.Y.Offset + ch.Size.Y.Offset
					if bottom > maxY then maxY = bottom end
				end
			end
			table1.mainpage.CanvasSize = UDim2.new(0, 0, 0, math.max(maxY + 60, (table1.frameheight - 80) * 12))
		end
	end

	table1.macroInfoChanged:Connect(function()
		table1.refreshMacroInfo()
	end)

	task.spawn(function()
		while table1.maingui and table1.maingui.Parent do
			if table1.macroInfoToggle and table1.macroInfoToggle.Parent then
				local st = table1.maintoggleState[table1.macroInfoToggle]
				if st and not st.folded then
					table1.refreshMacroInfo()
				end
			end
			task.wait(0.5)
		end
	end)

	if table1.settingspage and table1.maintoggle then
		table1.rezeAutoloadEnable, table1.rezeAutoloadEnableChanged =
			table1.maintoggle("Autoload Enabled", "On", 1, table1.settingspage, true, 0, 0)

		table1.rebuildRezeAutoloadSelect = function()
			local savedOrder, savedPos
			if table1.rezeAutoloadSelect and table1.rezeAutoloadSelect.Parent then
				savedOrder = table1.rezeAutoloadSelect:GetAttribute("LayoutOrder")
				savedPos = table1.rezeAutoloadSelect.Position
				table1.rezeAutoloadSelect:Destroy()
			end
			local names = {"None"}
			if table1.getconfiglist then
				local list = table1.getconfiglist()
				for _, n in ipairs(list) do
					if n ~= "(defaults)" then table.insert(names, n) end
				end
			end
			local args = {"Autoload"}
			for _, n in ipairs(names) do table.insert(args, n) end
			table.insert(args, 1)
			table.insert(args, table1.settingspage)
			table.insert(args, true)
			table.insert(args, 4)
			table.insert(args, 0)
			table1.rezeAutoloadSelect, table1.rezeAutoloadSelectChanged = table1.maintoggle(table.unpack(args))
			if savedOrder then table1.rezeAutoloadSelect:SetAttribute("LayoutOrder", savedOrder) end
			if savedPos then table1.rezeAutoloadSelect.Position = savedPos end
			table1.rezeAutoloadSelectChanged:Connect(function(mode)
				if mode <= 1 then
					table1.autoloadData.rezeConfig = ""
				else
					table1.autoloadData.rezeConfig = names[mode] or ""
				end
				writeAutoload(table1.autoloadData)
			end)
		end

		task.defer(function()
			if table1.rebuildRezeAutoloadSelect then
				table1.rebuildRezeAutoloadSelect()
			end
			if table1.autoloadData.enabled then
				table1.rezeAutoloadEnable:SetAttribute("Mode", 1)
				local st = table1.maintoggleState[table1.rezeAutoloadEnable]
				if st then
					st.currentmode = 1
					st.lastMode = 1
					if st.setoutline then st.setoutline(1, false) end
				end
			end
		end)

		table1.rezeAutoloadEnableChanged:Connect(function()
			local mode = table1.rezeAutoloadEnable:GetAttribute("Mode") or 0
			table1.autoloadData.enabled = (mode == 1)
			writeAutoload(table1.autoloadData)
		end)
	end

	task.defer(function()
		task.wait(0.5)
		local data = readAutoload()
		table1.autoloadData = data
		if not data.enabled then return end
		if data.macroConfig and data.macroConfig ~= "" then
			pcall(function()
				table1.loadMacro(data.macroConfig)
				if table1.macroNameBox then table1.macroNameBox.Text = data.macroConfig end
				if table1.refreshMacroInfo then table1.refreshMacroInfo() end
			end)
		end
		if data.rezeConfig and data.rezeConfig ~= "" and table1.loadconfigfile then
			pcall(function()
				table1.loadconfigfile(data.rezeConfig)
			end)
		end
	end)

	task.defer(function()
		local any = table1.macroRecordToggle
		if any and table1.maintoggleState[any] and table1.maintoggleState[any].relayout then
			table1.maintoggleState[any].relayout()
		end
		if table1.refreshMacroInfo then table1.refreshMacroInfo() end
	end)
end
-- ============================================================
-- END MACRO SYSTEM
-- ============================================================
