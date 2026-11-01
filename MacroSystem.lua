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

	-- JSON-safe arg packing (Instances / Vector3 / etc. break JSONEncode otherwise)
	local function serializeValue(v)
		local t = typeof(v)
		if t == "nil" then
			return { __t = "nil" }
		elseif t == "number" or t == "string" or t == "boolean" then
			return v
		elseif t == "Instance" then
			return { __t = "Instance", path = v:GetFullName(), className = v.ClassName, name = v.Name }
		elseif t == "Vector3" then
			return { __t = "Vector3", x = v.X, y = v.Y, z = v.Z }
		elseif t == "Vector2" then
			return { __t = "Vector2", x = v.X, y = v.Y }
		elseif t == "CFrame" then
			return { __t = "CFrame", c = { v:GetComponents() } }
		elseif t == "Color3" then
			return { __t = "Color3", r = v.R, g = v.G, b = v.B }
		elseif t == "table" then
			local out = {}
			for k, vv in pairs(v) do
				out[tostring(k)] = serializeValue(vv)
			end
			out.__t = "table"
			out.__arr = (#v > 0)
			if out.__arr then
				local arr = { __t = "array" }
				for i = 1, #v do
					arr[i] = serializeValue(v[i])
				end
				return arr
			end
			return out
		else
			return { __t = "string", v = tostring(v) }
		end
	end

	local function serializeArgs(args)
		local out = { __t = "array" }
		for i = 1, #args do
			out[i] = serializeValue(args[i])
		end
		out.n = #args
		return out
	end

	local function deserializeValue(v)
		if type(v) ~= "table" then
			return v
		end
		local t = v.__t
		if t == "nil" then
			return nil
		elseif t == "Instance" then
			local cur = game
			for part in string.gmatch(v.path or "", "[^%.]+") do
				if cur then
					cur = cur:FindFirstChild(part)
				end
			end
			return cur
		elseif t == "Vector3" then
			return Vector3.new(v.x or 0, v.y or 0, v.z or 0)
		elseif t == "Vector2" then
			return Vector2.new(v.x or 0, v.y or 0)
		elseif t == "CFrame" then
			local c = v.c or {}
			return CFrame.new(table.unpack(c))
		elseif t == "Color3" then
			return Color3.new(v.r or 0, v.g or 0, v.b or 0)
		elseif t == "array" then
			local out = {}
			for i = 1, (v.n or #v) do
				if v[i] ~= nil then
					out[i] = deserializeValue(v[i])
				end
			end
			return out
		elseif t == "table" then
			local out = {}
			for k, vv in pairs(v) do
				if k ~= "__t" and k ~= "__arr" then
					out[k] = deserializeValue(vv)
				end
			end
			return out
		elseif t == "string" then
			return v.v
		end
		-- plain array-like without __t
		if v.n or #v > 0 then
			local out = {}
			for i = 1, (v.n or #v) do
				out[i] = deserializeValue(v[i])
			end
			return out
		end
		return v
	end

	local function deserializeArgs(args)
		if type(args) ~= "table" then return {} end
		if args.__t == "array" or args.n then
			local out = {}
			for i = 1, (args.n or #args) do
				out[i] = deserializeValue(args[i])
			end
			return out
		end
		return deserializeValue(args)
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
							local copied = safeCopyArgs(args)
							table.insert(table1.recordedActions, {
								wave = wave,
								timeOffset = getTimeSinceWaveStart(wave),
								actionType = remoteName,
								method = method,
								args = serializeArgs(copied),
								unitName = nil,
								unitId = (typeof(args[1]) == "Instance" and args[1].Name) or args[1],
								remotePath = remoteSelf:GetFullName(),
								moneyAtTime = getMoney(),
								timestamp = os.clock(),
								result = ret,
							})
							if remoteName == "spawn_unit" then
								table1.lastPlaceArgs = args
								table1.lastPlaceTime = os.clock()
							end
							if table1.refreshMacroInfo then
								table1.refreshMacroInfo()
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
		-- always dump the live temporary recording (actions + wave + timeOffset + remotes)
		local actionsOut = {}
		for i, act in ipairs(table1.recordedActions or {}) do
			actionsOut[i] = {
				wave = act.wave,
				timeOffset = act.timeOffset,
				actionType = act.actionType,
				method = act.method,
				args = act.args,
				unitName = act.unitName,
				unitId = act.unitId,
				remotePath = act.remotePath,
				moneyAtTime = act.moneyAtTime,
				result = act.result,
			}
		end
		local data = {
			name = name,
			created = os.time(),
			settings = deepCopy(table1.macroSettings),
			actions = actionsOut,
			actionCount = #actionsOut,
		}
		local okEncode, jsonOrErr = pcall(function()
			return table1.HttpService:JSONEncode(data)
		end)
		if not okEncode or type(jsonOrErr) ~= "string" then
			return false
		end
		local okWrite = pcall(function()
			writefile(macroFilePath(name), jsonOrErr)
		end)
		if not okWrite then return false end
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
		local args = deserializeArgs(entry.args or {})
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

	-- Macro Info: 1 Refresh + manually placed textboxes (all visible when expanded)
	table1.macroInfoToggle, table1.macroInfoChanged =
		table1.maintoggle("Macro Info", "Refresh", 1, table1.mainpage, true, 3, 0)
	table1.macroInfoToggle:SetAttribute("LayoutOrder", 8)
	table1.macroInfoToggle.ClipsDescendants = true

	local function makeInfoBox(name, y)
		local box = Instance.new("TextBox")
		box.Name = name
		box.Size = UDim2.new(1, -12, 0, 22)
		box.Position = UDim2.new(0, 6, 0, y)
		box.BackgroundColor3 = table1.tabinactive
		box.BackgroundTransparency = 0.35
		box.BorderSizePixel = 0
		box.TextColor3 = table1.white
		box.Font = table1.font
		box.TextSize = 12
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ClearTextOnFocus = false
		box.TextEditable = false
		box.ZIndex = 15
		box.Visible = true
		box.Parent = table1.macroInfoToggle
		pcall(function()
			box:SetAttribute("Numberlocked", false)
			box:SetAttribute("preventchange", true)
		end)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = box
		return box
	end

	-- stacked so every line is on-screen (header ~28, refresh row ~26, then boxes)
	table1.macroInfoWaveBox = makeInfoBox("MacroInfoWave", 64)
	table1.macroInfoTimeBox = makeInfoBox("MacroInfoTime", 90)
	table1.macroInfoMoneyBox = makeInfoBox("MacroInfoMoney", 116)
	table1.macroInfoNameBox2 = makeInfoBox("MacroInfoName", 142)
	table1.macroInfoStatusBox = makeInfoBox("MacroInfoStatus", 168)
	table1.macroInfoLogBox = makeInfoBox("MacroInfoLog", 194)
	table1.macroInfoLogBox.Size = UDim2.new(1, -12, 0, 48)
	table1.macroInfoLogBox.TextWrapped = true
	table1.macroInfoLogBox.MultiLine = true
	table1.macroInfoLogBox.TextYAlignment = Enum.TextYAlignment.Top

	table1.macroInfoWaveBox.Text = "Wave: -"
	table1.macroInfoTimeBox.Text = "Time on wave: -"
	table1.macroInfoMoneyBox.Text = "Money: -"
	table1.macroInfoNameBox2.Text = "Macro: (temporary)"
	table1.macroInfoStatusBox.Text = "Rec:off Replay:off Actions:0"
	table1.macroInfoLogBox.Text = "Action log (empty)"

	do
		local st = table1.maintoggleState[table1.macroInfoToggle]
		local totalH = 194 + 72 + 12
		if st then
			st.normalHeight = totalH
			table1.macroInfoToggle:SetAttribute("LayoutHeight", totalH)
			if not st.folded then
				table1.macroInfoToggle.Size = UDim2.new(0, st.toggleWidth or 180, 0, totalH)
			end
			if st.relayout then
				st.relayout()
			end
		end
	end

	table1.macroInfoSetFolded = function(folded)
		local boxes = {
			table1.macroInfoWaveBox,
			table1.macroInfoTimeBox,
			table1.macroInfoMoneyBox,
			table1.macroInfoNameBox2,
			table1.macroInfoStatusBox,
			table1.macroInfoLogBox,
		}
		for _, box in ipairs(boxes) do
			if box then
				box.Visible = not folded
			end
		end
		local st = table1.maintoggleState[table1.macroInfoToggle]
		if st then
			st.folded = folded
		end
	end

	-- hide content whenever fold button is used
	do
		local st = table1.maintoggleState[table1.macroInfoToggle]
		if st and st.fold and st.fold:IsA("GuiButton") then
			st.fold.MouseButton1Click:Connect(function()
				task.defer(function()
					local s2 = table1.maintoggleState[table1.macroInfoToggle]
					local isFolded = false
					if s2 then
						isFolded = s2.folded == true
						-- also treat short height as folded
						if table1.macroInfoToggle.Size.Y.Offset <= (table1.toggleheight or 25) + 8 then
							isFolded = true
						end
					end
					table1.macroInfoSetFolded(isFolded)
				end)
			end)
		end
		-- size change watcher (covers any fold path)
		table1.macroInfoToggle:GetPropertyChangedSignal("Size"):Connect(function()
			local h = table1.macroInfoToggle.Size.Y.Offset
			local folded = h <= (table1.toggleheight or 25) + 10
			table1.macroInfoSetFolded(folded)
		end)
	end

	table1.refreshMacroInfo = function()
		local wave = getCurrentWave()
		if not table1.waveStartTimes[wave] then
			table1.waveStartTimes[wave] = os.clock()
		end
		local st = table1.maintoggleState[table1.macroInfoToggle]
		local folded = (st and st.folded == true)
			or (table1.macroInfoToggle.Size.Y.Offset <= (table1.toggleheight or 25) + 10)
		if table1.macroInfoSetFolded then
			table1.macroInfoSetFolded(folded)
		end
		if folded then
			return
		end
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
			local actions = table1.recordedActions or {}
			local lines = {}
			table.insert(lines, string.format("--- %d actions (temporary/saved) ---", #actions))
			local byWave = {}
			for _, act in ipairs(actions) do
				local w = act.wave
				if w == nil then w = 0 end
				byWave[w] = byWave[w] or {}
				table.insert(byWave[w], act)
			end
			local waves = {}
			for w in pairs(byWave) do
				table.insert(waves, w)
			end
			table.sort(waves)
			for _, w in ipairs(waves) do
				table.insert(lines, "")
				table.insert(lines, string.format("== Wave %s ==", tostring(w)))
				for _, act in ipairs(byWave[w]) do
					local label = tostring(act.unitName or act.unitId or "")
					if label ~= "" then label = " | " .. label end
					table.insert(lines, string.format(
						"  +%.2fs  %s%s",
						tonumber(act.timeOffset) or 0,
						tostring(act.actionType or "?"),
						label
					))
				end
			end
			local logText = table.concat(lines, "\n")
			table1.macroInfoLogBox.Text = logText
			table1.macroInfoLogBox.MultiLine = true
			table1.macroInfoLogBox.TextWrapped = true
			local logH = math.max(72, math.min(220, (#lines + 1) * 15))
			table1.macroInfoLogBox.Size = UDim2.new(1, -12, 0, logH)
			local totalH = 194 + logH + 12
			if st then
				st.normalHeight = totalH
				table1.macroInfoToggle:SetAttribute("LayoutHeight", totalH)
				if not st.folded then
					table1.macroInfoToggle.Size = UDim2.new(0, st.toggleWidth or 180, 0, totalH)
				end
				if st.relayout then
					st.relayout()
				end
			end
			if table1.mainpage and table1.mainpage:IsA("ScrollingFrame") then
				local maxY = 0
				for _, ch in ipairs(table1.mainpage:GetChildren()) do
					if ch:IsA("GuiObject") and ch:GetAttribute("Maintoggle") then
						local bottom = ch.Position.Y.Offset + ch.Size.Y.Offset
						if bottom > maxY then maxY = bottom end
					end
				end
				table1.mainpage.CanvasSize = UDim2.new(0, 0, 0, math.max(maxY + 80, (table1.frameheight - 80) * 12))
			end
		end
	end

	table1.macroInfoChanged:Connect(function()
		table1.refreshMacroInfo()
	end)

	task.spawn(function()
		while table1.maingui and table1.maingui.Parent do
			if table1.macroInfoToggle and table1.macroInfoToggle.Parent then
				table1.refreshMacroInfo()
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
