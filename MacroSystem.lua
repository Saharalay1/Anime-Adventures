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
		if not isfolder(table1.folder1) then
			makefolder(table1.folder1)
		end
		local path = table1.folder1 .. "/macroconfigs"
		if not isfolder(path) then
			makefolder(path)
		end
		return path
	end

	local function macroFilePath(name)
		return ensureMacroFolder() .. "/" .. tostring(name) .. ".json"
	end

	if not table1.autoloadPath then
		table1.autoloadPath = function()
			if not isfolder(table1.folder1) then makefolder(table1.folder1) end
			return table1.folder1 .. "/autoload.json"
		end
	end
	if not table1.readAutoload then
		table1.readAutoload = function()
			local data = { enabled = false, rezeConfig = "", macroConfig = "" }
			local path = table1.autoloadPath()
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
	end
	if not table1.writeAutoload then
		table1.writeAutoload = function(data)
			local path = table1.autoloadPath()
			pcall(function()
				writefile(path, table1.HttpService:JSONEncode({
					enabled = data.enabled == true,
					rezeConfig = tostring(data.rezeConfig or ""),
					macroConfig = tostring(data.macroConfig or ""),
				}))
			end)
		end
	end

	table1.autoloadData = table1.autoloadData or table1.readAutoload()

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

	local function safeCopyArgs(args)
		local out = {}
		for i = 1, #args do
			local v = args[i]
			if typeof(v) == "table" then
				local ok, copied = pcall(deepCopy, v)
				out[i] = ok and copied or v
			else
				out[i] = v
			end
		end
		return out
	end

	-- Forward call first, capture return. Only log successful calls (not false).
	if type(hookmetamethod) == "function" then
		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			local method = getnamecallmethod()
			local results = table.pack(oldNamecall(self, ...))
			if table1.recording and not table1.replaying and not table1.macroIgnoreReplay then
				if method == "FireServer" or method == "InvokeServer" then
					local remoteSelf = self
					local nArgs = select("#", ...)
					local packed = { ... }
					local ret = results[1]
					task.defer(function()
						pcall(function()
							if ret == false then return end
							if typeof(remoteSelf) ~= "Instance" then return end
							local cn = remoteSelf.ClassName
							if cn ~= "RemoteEvent" and cn ~= "RemoteFunction" then return end
							local remoteName = remoteSelf.Name
							if not ACTION_REMOTES[remoteName] then return end
							local args = {}
							for i = 1, nArgs do
								args[i] = packed[i]
							end
							local wave = getCurrentWave()
							table.insert(table1.recordedActions, {
								wave = wave,
								timeOffset = getTimeSinceWaveStart(wave),
								actionType = remoteName,
								method = method,
								args = safeCopyArgs(args),
								unitName = nil,
								unitId = args[1],
								remotePath = remoteSelf:GetFullName(),
								moneyAtTime = getMoney(),
								timestamp = os.clock(),
								result = ret,
							})
							if remoteName == "spawn_unit" then
								table1.lastPlaceArgs = args
								table1.lastPlaceTime = os.clock()
							end
						end)
					end)
				end
			end
			return table.unpack(results, 1, results.n)
		end))
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
		if table1.refreshMacroInfo then table1.refreshMacroInfo() end
	end

	function table1.stopRecording()
		if not table1.recording then return end
		table1.recording = false
		if table1.refreshMacroInfo then table1.refreshMacroInfo() end
	end

	function table1.toggleRecording()
		if table1.recording then
			table1.stopRecording()
		else
			table1.startRecording()
		end
	end

	function table1.getMacroList()
		local folder = ensureMacroFolder()
		table1.macrolistnames = {}
		if type(listfiles) == "function" then
			local ok, files = pcall(listfiles, folder)
			if ok and type(files) == "table" then
				for _, f in ipairs(files) do
					local name = tostring(f):match("([^/\\]+)%.json$")
					if name and name ~= "" then
						table.insert(table1.macrolistnames, name)
					end
				end
			end
		end
		table.sort(table1.macrolistnames)
		return table1.macrolistnames
	end

	function table1.saveMacro(name)
		if type(name) ~= "string" or name == "" then return false end
		ensureMacroFolder()
		local data = {
			name = name,
			created = os.time(),
			settings = deepCopy(table1.macroSettings),
			actions = deepCopy(table1.recordedActions),
		}
		local ok = pcall(function()
			writefile(macroFilePath(name), table1.HttpService:JSONEncode(data))
		end)
		if not ok then return false end
		table1.currentMacroName = name
		return true
	end

	function table1.loadMacro(name)
		if type(name) ~= "string" or name == "" then return false end
		local path = macroFilePath(name)
		if type(isfile) ~= "function" or not isfile(path) then return false end
		local ok, data = pcall(function()
			return table1.HttpService:JSONDecode(readfile(path))
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
		if type(name) ~= "string" or name == "" then return false end
		local path = macroFilePath(name)
		if type(isfile) == "function" and isfile(path) and type(delfile) == "function" then
			pcall(delfile, path)
			if table1.currentMacroName == name then
				table1.currentMacroName = nil
			end
			return true
		end
		return false
	end

	function table1.createMacro(name)
		if type(name) ~= "string" or name == "" then return false end
		ensureMacroFolder()
		local path = macroFilePath(name)
		if type(isfile) == "function" and isfile(path) then return false end
		local data = {
			name = name,
			created = os.time(),
			settings = deepCopy(table1.macroSettings),
			actions = {},
		}
		local ok = pcall(function()
			writefile(path, table1.HttpService:JSONEncode(data))
		end)
		if not ok then return false end
		table1.currentMacroName = name
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
			if attempts >= 5 then
				return true
			end
		end
		return false
	end

	function table1.replayMacro(name)
		if table1.replaying then return end
		if name and name ~= "" then
			if not table1.loadMacro(name) then return end
		end
		if #table1.recordedActions == 0 then return end
		table1.replaying = true
		if table1.macroSettings.autovotestart then
			local voteRemote = getRemoteByName("vote_start")
			if voteRemote and voteRemote:IsA("RemoteFunction") then
				table1.macroIgnoreReplay = true
				pcall(function()
					voteRemote:InvokeServer()
				end)
				table1.macroIgnoreReplay = false
			end
		end
		local startWave = getCurrentWave()
		onWaveChanged(startWave)
		local actionsByWave = {}
		for _, act in ipairs(table1.recordedActions) do
			local w = act.wave or 0
			if w >= startWave then
				actionsByWave[w] = actionsByWave[w] or {}
				table.insert(actionsByWave[w], act)
			end
		end
		local waves = {}
		for w in pairs(actionsByWave) do
			table.insert(waves, w)
		end
		table.sort(waves)
		task.spawn(function()
			if table1.macroSettings.startupdelay and table1.macroSettings.startupdelay > 0 then
				task.wait(table1.macroSettings.startupdelay)
			end
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

	-- ORDER:
	-- 1 Macro Selection
	-- 2 Macro Configurations
	-- 3 Macro Replay
	-- 4 Macro Record
	-- 5 Macro Autoload Target
	-- 6 Macro Autoload
	-- 7 Macro Settings
	-- 8 Macro Info

	table1.rebuildMacroSelection = function(force)
		table1.getMacroList()
		if table1.macroSelectMain and table1.macroSelectMain.Parent and not force then
			return
		end
		local savedOrder, savedPos
		if table1.macroSelectMain and table1.macroSelectMain.Parent then
			savedOrder = table1.macroSelectMain:GetAttribute("LayoutOrder")
			savedPos = table1.macroSelectMain.Position
			table1.macroSelectMain:Destroy()
		end
		local args = { "Macro Selection" }
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
		table1.macroSelectMain:SetAttribute("LayoutOrder", savedOrder or 1)
		if savedPos then
			table1.macroSelectMain.Position = savedPos
		end
		table1.macroSelectChanged:Connect(function(mode)
			mode = tonumber(mode) or 0
			table1.getMacroList()
			if #table1.macrolistnames == 0 then return end
			local name = table1.macrolistnames[mode]
			local st = table1.maintoggleState[table1.macroSelectMain]
			if st and st.dropdownButtons and st.dropdownButtons[mode] then
				local t = st.dropdownButtons[mode].Text
				if t and t ~= "None" then
					name = t
				end
			end
			if name and name ~= "None" then
				if table1.macroNameBox then
					table1.macroNameBox.Text = name
				end
				table1.loadMacro(name)
				if table1.refreshMacroInfo then
					table1.refreshMacroInfo()
				end
			end
		end)
	end
	table1.rebuildMacroSelection(true)

	table1.macroConfigActions, table1.macroConfigActionsChanged, table1.macroNameBox =
		table1.maintoggle("Macro Configurations", "Save", "Load", "Delete", "Create", 1, table1.mainpage, true, 3, 1)
	table1.macroConfigActions:SetAttribute("LayoutOrder", 2)
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
			table1.rebuildMacroSelection(true)
			if table1.rebuildMacroAutoloadSelect then
				table1.rebuildMacroAutoloadSelect(true)
			end
		elseif mode == 4 then
			if name ~= "" then
				table1.createMacro(name)
				table1.rebuildMacroSelection(true)
				if table1.rebuildMacroAutoloadSelect then
					table1.rebuildMacroAutoloadSelect(true)
				end
			end
		end
		if table1.refreshMacroInfo then
			table1.refreshMacroInfo()
		end
	end)

	table1.macroReplayToggle, table1.macroReplayChanged =
		table1.maintoggle("Macro Replay", "Replay", "Stop", 1, table1.mainpage, true, 3, 0)
	table1.macroReplayToggle:SetAttribute("LayoutOrder", 3)
	table1.macroReplayChanged:Connect(function(mode)
		if mode == 1 then
			local name = table1.macroNameBox and table1.macroNameBox.Text or ""
			name = name:gsub("^%s+", ""):gsub("%s+$", "")
			if name ~= "" then
				table1.replayMacro(name)
			else
				table1.replayMacro()
			end
		elseif mode == 2 then
			table1.stopReplay()
		end
		if table1.refreshMacroInfo then
			table1.refreshMacroInfo()
		end
	end)

	table1.macroRecordToggle, table1.macroRecordChanged, table1.macroRecordAction =
		table1.maintoggle("Record Macro", "On", 1, table1.mainpage, true, 0, 0, 1)
	do
		local st = table1.maintoggleState[table1.macroRecordToggle]
		if st then
			st.actiontext = "REC"
			if st.actiontextbox then
				st.actiontextbox.Text = "REC"
			end
			table1.macroRecordToggle:SetAttribute("LayoutOrder", 4)
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

	table1.syncMacroAutoloadSelectionFromUI = function()
		local name = ""
		if table1.macroAutoloadSelect and table1.macroAutoloadSelect.Parent then
			local mode = tonumber(table1.macroAutoloadSelect:GetAttribute("Mode")) or 0
			local st = table1.maintoggleState[table1.macroAutoloadSelect]
			if st and st.dropdownButtons and st.dropdownButtons[mode] then
				local t = st.dropdownButtons[mode].Text
				if t and t ~= "None" and not string.find(t, "Select") then
					name = t
				end
			elseif table1.autoloadMacroNames and table1.autoloadMacroNames[mode] then
				local t = table1.autoloadMacroNames[mode]
				if t and t ~= "None" then
					name = t
				end
			end
		end
		table1.autoloadData.macroConfig = name
		return name
	end

	table1.rebuildMacroAutoloadSelect = function(force)
		table1.getMacroList()
		if table1.macroAutoloadSelect and table1.macroAutoloadSelect.Parent and not force then
			return
		end
		local savedOrder, savedPos
		if table1.macroAutoloadSelect and table1.macroAutoloadSelect.Parent then
			savedOrder = table1.macroAutoloadSelect:GetAttribute("LayoutOrder")
			savedPos = table1.macroAutoloadSelect.Position
			table1.macroAutoloadSelect:Destroy()
		end
		table1.autoloadMacroNames = { "None" }
		for _, n in ipairs(table1.macrolistnames) do
			table.insert(table1.autoloadMacroNames, n)
		end
		local args = { "Macro Autoload Target" }
		for _, n in ipairs(table1.autoloadMacroNames) do
			table.insert(args, n)
		end
		table.insert(args, 1)
		table.insert(args, table1.mainpage)
		table.insert(args, true)
		table.insert(args, 4)
		table.insert(args, 0)
		table1.macroAutoloadSelect, table1.macroAutoloadSelectChanged = table1.maintoggle(table.unpack(args))
		table1.macroAutoloadSelect:SetAttribute("LayoutOrder", savedOrder or 5)
		if savedPos then
			table1.macroAutoloadSelect.Position = savedPos
		end
		local restoreMode = 1
		if table1.autoloadData.macroConfig and table1.autoloadData.macroConfig ~= "" then
			for i, n in ipairs(table1.autoloadMacroNames) do
				if n == table1.autoloadData.macroConfig then
					restoreMode = i
					break
				end
			end
		end
		table1.macroAutoloadSelect:SetAttribute("Mode", restoreMode)
		local st = table1.maintoggleState[table1.macroAutoloadSelect]
		if st then
			st.currentmode = restoreMode
			st.lastMode = restoreMode
			st.selectedMode = restoreMode
			if st.selectedModes then
				for i = 1, (st.modecount or 0) do
					local sel = (i == restoreMode)
					st.selectedModes[i] = sel
					table1.macroAutoloadSelect:SetAttribute("Selected" .. i, sel)
					if st.dropdownButtons and st.dropdownButtons[i] then
						st.dropdownButtons[i].BackgroundColor3 = sel and table1.selectedtabcolor or table1.tabinactive
						st.dropdownButtons[i].BackgroundTransparency = sel and 0 or 0.15
					end
				end
			end
			if st.updateDropdownText then
				st.updateDropdownText()
			end
		end
		table1.macroAutoloadSelectChanged:Connect(function(mode)
			mode = tonumber(mode) or 0
			local chosen = ""
			if table1.autoloadMacroNames and table1.autoloadMacroNames[mode] then
				chosen = table1.autoloadMacroNames[mode]
			end
			local st2 = table1.maintoggleState[table1.macroAutoloadSelect]
			if st2 and st2.dropdownButtons and st2.dropdownButtons[mode] then
				local t = st2.dropdownButtons[mode].Text
				if type(t) == "string" and t ~= "" then
					chosen = t
				end
			end
			if chosen == "None" or chosen == "" then
				table1.autoloadData.macroConfig = ""
			else
				table1.autoloadData.macroConfig = chosen
			end
			table1.writeAutoload(table1.autoloadData)
		end)
	end
	table1.rebuildMacroAutoloadSelect(true)

	table1.macroAutoloadEnable, table1.macroAutoloadEnableChanged =
		table1.maintoggle("Macro Autoload", "On", 1, table1.mainpage, true, 0, 0)
	table1.macroAutoloadEnable:SetAttribute("LayoutOrder", 6)
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
		if table1.syncMacroAutoloadSelectionFromUI then
			table1.syncMacroAutoloadSelectionFromUI()
		end
		if table1.syncAutoloadSelectionFromUI then
			table1.syncAutoloadSelectionFromUI()
		end
		table1.writeAutoload(table1.autoloadData)
	end)

	table1.macroSettingsToggle, table1.macroSettingsChanged =
		table1.maintoggle("Macro Settings", "Wave Based Time", "Auto Vote Start", "Skip Failures Next Wave", 1, table1.mainpage, true, 2, 0)
	table1.macroSettingsToggle:SetAttribute("LayoutOrder", 7)
	do
		local st = table1.maintoggleState[table1.macroSettingsToggle]
		local function setSel(i, on)
			table1.macroSettingsToggle:SetAttribute("Selected" .. i, on == true)
			if st and st.selectedModes then
				st.selectedModes[i] = on == true
			end
			if st and st.dropdownButtons and st.dropdownButtons[i] then
				st.dropdownButtons[i].BackgroundColor3 = on and table1.selectedtabcolor or table1.tabinactive
				st.dropdownButtons[i].BackgroundTransparency = on and 0 or 0.15
			end
		end
		setSel(1, table1.macroSettings.wavebasedtime)
		setSel(2, table1.macroSettings.autovotestart)
		setSel(3, table1.macroSettings.skipfailuresandmoveontothenextwave)
		if st and st.updateDropdownText then
			st.updateDropdownText()
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

	-- Macro Info: unlocked textboxes, hide when folded
	table1.macroInfoToggle, table1.macroInfoChanged,
		table1.macroInfoWaveBox, table1.macroInfoTimeBox, table1.macroInfoMoneyBox,
		table1.macroInfoNameBox2, table1.macroInfoStatusBox, table1.macroInfoLogBox =
		table1.maintoggle("Macro Info", "Refresh", 1, table1.mainpage, true, 3, 6)
	table1.macroInfoToggle:SetAttribute("LayoutOrder", 8)
	local infoBoxes = {
		table1.macroInfoWaveBox,
		table1.macroInfoTimeBox,
		table1.macroInfoMoneyBox,
		table1.macroInfoNameBox2,
		table1.macroInfoStatusBox,
		table1.macroInfoLogBox,
	}
	local placeholders = { "Wave", "Time on wave", "Money", "Macro name", "Status", "Action log" }
	for i, box in ipairs(infoBoxes) do
		if box then
			pcall(function()
				box:SetAttribute("Numberlocked", false)
				box:SetAttribute("preventchange", true)
			end)
			box.PlaceholderText = placeholders[i]
			box.Text = placeholders[i]
			box.ClearTextOnFocus = false
		end
	end
	do
		local st = table1.maintoggleState[table1.macroInfoToggle]
		if st then
			st.normalHeight = 220
			table1.macroInfoToggle:SetAttribute("LayoutHeight", 220)
			if not st.folded then
				table1.macroInfoToggle.Size = UDim2.new(0, st.toggleWidth or 180, 0, 220)
			end
		end
	end

	table1.refreshMacroInfo = function()
		local wave = getCurrentWave()
		if not table1.waveStartTimes[wave] then
			table1.waveStartTimes[wave] = os.clock()
		end
		local st = table1.maintoggleState[table1.macroInfoToggle]
		local folded = st and st.folded
		for _, box in ipairs(infoBoxes) do
			if box then
				box.Visible = not folded
			end
		end
		if folded then return end
		if table1.macroInfoWaveBox then
			table1.macroInfoWaveBox.Text = "Wave: " .. tostring(wave)
		end
		if table1.macroInfoTimeBox then
			table1.macroInfoTimeBox.Text = string.format("Time on wave: %.2fs", getTimeSinceWaveStart(wave))
		end
		if table1.macroInfoMoneyBox then
			table1.macroInfoMoneyBox.Text = "Money: " .. tostring(getMoney())
		end
		if table1.macroInfoNameBox2 then
			table1.macroInfoNameBox2.Text = "Macro: " .. (table1.currentMacroName or "(temporary)")
		end
		if table1.macroInfoStatusBox then
			table1.macroInfoStatusBox.Text = string.format(
				"Rec:%s Replay:%s Actions:%d",
				table1.recording and "ON" or "off",
				table1.replaying and "ON" or "off",
				#table1.recordedActions
			)
		end
		if table1.macroInfoLogBox then
			local lines = {}
			local byWave = {}
			for _, act in ipairs(table1.recordedActions) do
				byWave[act.wave] = byWave[act.wave] or {}
				table.insert(byWave[act.wave], act)
			end
			local waves = {}
			for w in pairs(byWave) do
				table.insert(waves, w)
			end
			table.sort(waves)
			for _, w in ipairs(waves) do
				table.insert(lines, "W" .. tostring(w))
				for _, act in ipairs(byWave[w]) do
					table.insert(lines, string.format(
						"%.1f %s %s",
						act.timeOffset or 0,
						act.actionType,
						tostring(act.unitName or act.unitId or "")
					))
				end
			end
			table1.macroInfoLogBox.Text = (#lines > 0) and table.concat(lines, " | ") or "Action log (empty)"
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
				else
					for _, box in ipairs(infoBoxes) do
						if box then box.Visible = false end
					end
				end
			end
			task.wait(0.5)
		end
	end)

	task.spawn(function()
		task.wait(1.2)
		local data = table1.readAutoload()
		table1.autoloadData = data
		if data.enabled ~= true then return end
		local name = tostring(data.macroConfig or "")
		if name == "" or name == "None" then return end
		if table1.loadMacro(name) then
			if table1.macroNameBox then
				table1.macroNameBox.Text = name
			end
			if table1.refreshMacroInfo then
				table1.refreshMacroInfo()
			end
		end
	end)

	task.defer(function()
		if table1.refreshMacroInfo then
			table1.refreshMacroInfo()
		end
	end)
end
-- ============================================================
-- END MACRO SYSTEM
-- ============================================================
