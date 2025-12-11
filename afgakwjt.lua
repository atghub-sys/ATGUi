---@diagnostic disable: undefined-global
local httpService = game:GetService("HttpService")

local SaveManager = {} do
	SaveManager.FolderRoot = "ATGSettings"
	SaveManager.Ignore = {}
	SaveManager.Options = {}
	SaveManager.AutoSaveEnabled = false
	SaveManager.AutoSaveConfig = nil
	SaveManager.AutoSaveDebounce = false
	SaveManager.OriginalCallbacks = {}
	SaveManager.DefaultValues = {}
	SaveManager._hookedTabs = {}
	SaveManager.Parser = {
		Toggle = {
			Save = function(idx, object) 
				local defaultValue = SaveManager.DefaultValues[idx]
				if defaultValue ~= nil and defaultValue == object.Value then
					return nil
				end
				return { type = "Toggle", idx = idx, value = object.Value } 
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Slider = {
			Save = function(idx, object)
				local defaultValue = SaveManager.DefaultValues[idx]
				if defaultValue ~= nil and tonumber(defaultValue) == tonumber(object.Value) then
					return nil
				end
				return { type = "Slider", idx = idx, value = tostring(object.Value) }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(tonumber(data.value))
				end
			end,
		},
		Dropdown = {
			Save = function(idx, object)
				local defaultValue = SaveManager.DefaultValues[idx]
				
				if object.Multi then
					if defaultValue ~= nil then
						local isDefault = true
						for k, v in pairs(object.Value) do
							if defaultValue[k] ~= v then
								isDefault = false
								break
							end
						end
						if isDefault then
							for k, v in pairs(defaultValue) do
								if object.Value[k] ~= v then
									isDefault = false
									break
								end
							end
						end
						if isDefault then return nil end
					end
				else
					if defaultValue ~= nil and defaultValue == object.Value then
						return nil
					end
				end
				
				return { type = "Dropdown", idx = idx, value = object.Value, multi = object.Multi }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Colorpicker = {
			Save = function(idx, object)
				local hexValue = object.Value:ToHex()
				local defaultValue = SaveManager.DefaultValues[idx]
				local defaultTransparency = SaveManager.DefaultValues[idx .. "_transparency"]
				
				if defaultValue ~= nil then
					local defaultHex = defaultValue:ToHex()
					local currentTransparency = object.Transparency or 0
					local defTrans = defaultTransparency or 0
					
					if defaultHex == hexValue and currentTransparency == defTrans then
						return nil
					end
				end
				return { type = "Colorpicker", idx = idx, value = hexValue, transparency = object.Transparency or 0 }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency)
				end
			end,
		},
		Keybind = {
			Save = function(idx, object)
				local defaultValue = SaveManager.DefaultValues[idx]
				local defaultMode = SaveManager.DefaultValues[idx .. "_mode"]
				if defaultValue ~= nil and defaultValue == object.Value and defaultMode == object.Mode then
					return nil
				end
				return { type = "Keybind", idx = idx, mode = object.Mode, key = object.Value }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.key, data.mode)
				end
			end,
		},
		Input = {
			Save = function(idx, object)
				local defaultValue = SaveManager.DefaultValues[idx]
				if defaultValue ~= nil and defaultValue == object.Value then
					return nil
				end
				return { type = "Input", idx = idx, text = object.Value }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] and type(data.text) == "string" then
					SaveManager.Options[idx]:SetValue(data.text)
				end
			end,
		},
	}

	local function sanitizeFilename(name)
		name = tostring(name or "")
		name = name:gsub("%s+", "_")
		name = name:gsub("[^%w%-%_]", "")
		if name == "" then return "Unknown" end
		return name
	end

	local function getPlaceId()
		local ok, id = pcall(function() return tostring(game.PlaceId) end)
		if ok and id then return id end
		return "UnknownPlace"
	end

	local function ensureFolder(path)
		if not isfolder(path) then makefolder(path) end
	end

	local function getConfigsFolder(self)
		return self.FolderRoot .. "/" .. getPlaceId()
	end

	local function getConfigFilePath(self, name)
		return getConfigsFolder(self) .. "/" .. name .. ".json"
	end

	local function getSaveManagerUIPath(self)
		return getConfigsFolder(self) .. "/savemanager_ui.json"
	end

	function SaveManager:BuildFolderTree()
		ensureFolder(self.FolderRoot)
		ensureFolder(getConfigsFolder(self))
	end

	function SaveManager:SetIgnoreIndexes(list)
		for _, key in next, list do
			self.Ignore[key] = true
		end
	end

	function SaveManager:SetFolder(folder)
		self.FolderRoot = tostring(folder or "ATGSettings")
		self:BuildFolderTree()
	end

	-- Hook ตัว Tab เพื่อดักจับการสร้าง Element
	function SaveManager:HookTab(tab)
		if self._hookedTabs[tab] then return end
		self._hookedTabs[tab] = true

		local methods = {
			{name = "AddToggle", type = "Toggle"},
			{name = "AddSlider", type = "Slider"},
			{name = "AddDropdown", type = "Dropdown"},
			{name = "AddColorpicker", type = "Colorpicker"},
			{name = "AddKeybind", type = "Keybind"},
			{name = "AddInput", type = "Input"},
		}

		for _, method in ipairs(methods) do
			local originalFunc = tab[method.name]
			if originalFunc then
				tab[method.name] = function(...)
					local result = originalFunc(...)
					
					-- ดักจับค่า Default
					local args = {...}
					local idx = args[2] -- idx อยู่ตำแหน่งที่ 2
					local config = args[3] -- config อยู่ตำแหน่งที่ 3
					
					if idx and config and config.Default ~= nil then
						if method.type == "Toggle" then
							SaveManager.DefaultValues[idx] = config.Default
						elseif method.type == "Slider" then
							SaveManager.DefaultValues[idx] = config.Default
						elseif method.type == "Dropdown" then
							if config.Multi and type(config.Default) == "table" then
								local defaultTable = {}
								for _, v in ipairs(config.Default) do
									defaultTable[v] = true
								end
								SaveManager.DefaultValues[idx] = defaultTable
							else
								SaveManager.DefaultValues[idx] = config.Default
							end
						elseif method.type == "Colorpicker" then
							SaveManager.DefaultValues[idx] = config.Default
							SaveManager.DefaultValues[idx .. "_transparency"] = config.Transparency or 0
						elseif method.type == "Keybind" then
							SaveManager.DefaultValues[idx] = config.Default or "None"
							SaveManager.DefaultValues[idx .. "_mode"] = config.Mode or "Toggle"
						elseif method.type == "Input" then
							SaveManager.DefaultValues[idx] = config.Default
						end
					end
					
					return result
				end
			end
		end
	end

	function SaveManager:SetLibrary(library)
		self.Library = library
		self.Options = library.Options

		-- Hook ทุก Tab ที่มีอยู่แล้ว
		if library.Tabs then
			for _, tab in pairs(library.Tabs) do
				self:HookTab(tab)
			end
		end

		-- Hook Window:AddTab เพื่อดักจับ Tab ใหม่
		if library.Window and library.Window.AddTab then
			local originalAddTab = library.Window.AddTab
			library.Window.AddTab = function(...)
				local tab = originalAddTab(...)
				SaveManager:HookTab(tab)
				return tab
			end
		end
	end

	function SaveManager:Save(name)
		if not name then return false, "no config file is selected" end

		local fullPath = getConfigFilePath(self, name)
		local data = { objects = {} }

		for idx, option in next, self.Options do
			if not self.Parser[option.Type] then continue end
			if self.Ignore[idx] then continue end
			
			local saved = self.Parser[option.Type].Save(idx, option)
			if saved then
				table.insert(data.objects, saved)
			end
		end

		local success, encoded = pcall(httpService.JSONEncode, httpService, data)
		if not success then return false, "failed to encode data" end

		local folder = fullPath:match("^(.*)/[^/]+$")
		if folder then ensureFolder(folder) end

		writefile(fullPath, encoded)
		return true
	end

	function SaveManager:SaveUI()
		local uiPath = getSaveManagerUIPath(self)
		local uiData = {
			autoload_enabled = (self:GetAutoloadConfig() ~= nil),
			autoload_config = self:GetAutoloadConfig(),
			autosave_enabled = self.AutoSaveEnabled,
			autosave_config = self.AutoSaveConfig
		}

		local success, encoded = pcall(httpService.JSONEncode, httpService, uiData)
		if success then
			local folder = uiPath:match("^(.*)/[^/]+$")
			if folder then ensureFolder(folder) end
			writefile(uiPath, encoded)
		end
	end

	function SaveManager:LoadUI()
		local uiPath = getSaveManagerUIPath(self)
		if not isfile(uiPath) then return nil end

		local success, decoded = pcall(httpService.JSONDecode, httpService, readfile(uiPath))
		return success and decoded or nil
	end

	function SaveManager:Load(name)
		if not name then return false, "no config file is selected" end

		local file = getConfigFilePath(self, name)
		if not isfile(file) then return false, "invalid file" end

		local success, decoded = pcall(httpService.JSONDecode, httpService, readfile(file))
		if not success then return false, "decode error" end

		local toggles, others = {}, {}

		for _, option in next, decoded.objects do
			if option.type == "Toggle" then
				table.insert(toggles, option)
			else
				table.insert(others, option)
			end
		end

		-- โหลด non-toggles
		for i, option in ipairs(others) do
			if self.Parser[option.type] then
				pcall(self.Parser[option.type].Load, option.idx, option)
			end
			if i % 5 == 0 then task.wait() end
		end

		-- โหลด toggles ทีหลัง
		task.defer(function()
			task.wait(0.1)
			for i, option in ipairs(toggles) do
				if self.Parser.Toggle then
					pcall(self.Parser.Toggle.Load, option.idx, option)
				end
				if i % 5 == 0 then task.wait() end
			end
		end)

		return true
	end

	function SaveManager:Delete(name)
		if not name then return false, "no config file is selected" end

		local file = getConfigFilePath(self, name)
		if not isfile(file) then return false, "config does not exist" end

		delfile(file)
		
		local autopath = getConfigsFolder(self) .. "/autoload.txt"
		if isfile(autopath) and readfile(autopath) == name then
			delfile(autopath)
		end
		
		return true
	end

	function SaveManager:GetAutoloadConfig()
		local autopath = getConfigsFolder(self) .. "/autoload.txt"
		return isfile(autopath) and readfile(autopath) or nil
	end

	function SaveManager:SetAutoloadConfig(name)
		if not name then return false, "no config name provided" end
		if not isfile(getConfigFilePath(self, name)) then return false, "config does not exist" end
		
		writefile(getConfigsFolder(self) .. "/autoload.txt", name)
		self:SaveUI()
		return true
	end

	function SaveManager:DisableAutoload()
		local autopath = getConfigsFolder(self) .. "/autoload.txt"
		if isfile(autopath) then
			delfile(autopath)
			self:SaveUI()
			return true
		end
		return false, "no autoload config set"
	end

	function SaveManager:IgnoreThemeSettings()
		self:SetIgnoreIndexes({"InterfaceTheme", "AcrylicToggle", "TransparentToggle", "MenuKeybind"})
	end

	SaveManager._configListCache = nil
	SaveManager._configListCacheTime = 0

	function SaveManager:RefreshConfigList()
		local folder = getConfigsFolder(self)
		if not isfolder(folder) then return {} end

		local now = os.clock()
		if self._configListCache and (now - self._configListCacheTime) < 1 then
			return self._configListCache
		end

		local list = listfiles(folder)
		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == ".json" then
				local name = file:match("([^/\\]+)%.json$")
				if name and name ~= "options" and name ~= "autoload" and name ~= "savemanager_ui" then
					table.insert(out, name)
				end
			end
		end

		self._configListCache = out
		self._configListCacheTime = now
		return out
	end

	function SaveManager:LoadAutoloadConfig()
		local name = self:GetAutoloadConfig()
		if name then self:Load(name) end
	end

	function SaveManager:EnableAutoSave(configName)
		self.AutoSaveEnabled = true
		self.AutoSaveConfig = configName
		self:SaveUI()

		for idx, option in next, self.Options do
			if not self.Ignore[idx] and self.Parser[option.Type] then
				if not self.OriginalCallbacks[idx] then
					self.OriginalCallbacks[idx] = option.Callback
				end

				local originalCallback = self.OriginalCallbacks[idx]
				option.Callback = function(...)
					if option._isInCallback then return end
					option._isInCallback = true

					if originalCallback then
						pcall(originalCallback, ...)
					end

					option._isInCallback = false

					if self.AutoSaveEnabled and self.AutoSaveConfig and not self.AutoSaveDebounce then
						self.AutoSaveDebounce = true
						task.spawn(function()
							task.wait(1)
							if self.AutoSaveEnabled and self.AutoSaveConfig then
								self:Save(self.AutoSaveConfig)
							end
							self.AutoSaveDebounce = false
						end)
					end
				end
			end
		end
	end

	function SaveManager:DisableAutoSave()
		self.AutoSaveEnabled = false
		self.AutoSaveConfig = nil
		self:SaveUI()
		
		for idx, option in next, self.Options do
			if self.OriginalCallbacks[idx] then
				option.Callback = self.OriginalCallbacks[idx]
			end
		end
	end

	function SaveManager:BuildConfigSection(tab)
		assert(self.Library, "Must set SaveManager.Library")

		local section = tab:AddSection("[ 📁 ] Configuration Manager")
		local uiSettings = self:LoadUI()

		local ConfigNameInput = section:AddInput("SaveManager_ConfigName", {
			Title = "Config Name",
			Description = "Enter config file name",
			Default = "MyConfig",
			Placeholder = "Enter name...",
		})

		local configList = self:RefreshConfigList()
		local ConfigDropdown = section:AddDropdown("SaveManager_ConfigDropdown", {
			Title = "Select Config",
			Description = "Choose a config to load",
			Values = configList,
			Default = configList[1],
		})

		section:AddButton({
			Title = "Create Config",
			Description = "Create new config file",
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigName.Value
				if name and name ~= "" then
					name = sanitizeFilename(name)
					local success = self:Save(name)
					if success then
						print("✅ Created: " .. name)
						local newList = self:RefreshConfigList()
						ConfigDropdown:SetValues(newList)
						ConfigDropdown:SetValue(name)
					end
				end
			end
		})

		section:AddButton({
			Title = "Save Config",
			Callback = function()
				local selected = SaveManager.Options.SaveManager_ConfigDropdown.Value
				if selected then
					self:Save(selected)
					print("✅ Saved: " .. selected)
				end
			end
		})

		section:AddButton({
			Title = "Load Config",
			Callback = function()
				local selected = SaveManager.Options.SaveManager_ConfigDropdown.Value
				if selected then
					self:Load(selected)
					print("✅ Loaded: " .. selected)
				end
			end
		})

		section:AddButton({
			Title = "Delete Config",
			Callback = function()
				local selected = SaveManager.Options.SaveManager_ConfigDropdown.Value
				if selected then
					self:Delete(selected)
					print("✅ Deleted: " .. selected)
					local newList = self:RefreshConfigList()
					ConfigDropdown:SetValues(newList)
					if #newList > 0 then ConfigDropdown:SetValue(newList[1]) end
				end
			end
		})

		section:AddButton({
			Title = "Refresh List",
			Callback = function()
				ConfigDropdown:SetValues(self:RefreshConfigList())
				print("🔄 Refreshed")
			end
		})

		section:AddToggle("SaveManager_AutoloadToggle", {
			Title = "Auto Load",
			Default = (uiSettings and uiSettings.autoload_enabled) or false,
			Callback = function(value)
				if value then
					local selected = SaveManager.Options.SaveManager_ConfigDropdown.Value
					if selected then
						self:SetAutoloadConfig(selected)
						print("✅ Auto load: " .. selected)
					end
				else
					self:DisableAutoload()
				end
			end
		})

		section:AddToggle("SaveManager_AutoSaveToggle", {
			Title = "Auto Save",
			Default = (uiSettings and uiSettings.autosave_enabled) or false,
			Callback = function(value)
				if value then
					local selected = SaveManager.Options.SaveManager_ConfigDropdown.Value
					if selected then
						self:EnableAutoSave(selected)
						print("✅ Auto save: " .. selected)
					end
				else
					self:DisableAutoSave()
				end
			end
		})

		self:SetIgnoreIndexes({"SaveManager_AutoloadToggle", "SaveManager_AutoSaveToggle", "SaveManager_ConfigName", "SaveManager_ConfigDropdown"})

		if uiSettings then
			if uiSettings.autoload_enabled and uiSettings.autoload_config then
				task.defer(function()
					if isfile(getConfigFilePath(self, uiSettings.autoload_config)) then
						self:Load(uiSettings.autoload_config)
						task.wait(0.1)
						if SaveManager.Options.SaveManager_AutoloadToggle then
							SaveManager.Options.SaveManager_AutoloadToggle:SetValue(true)
						end
						if SaveManager.Options.SaveManager_ConfigDropdown then
							ConfigDropdown:SetValue(uiSettings.autoload_config)
						end
					end
				end)
			end

			if uiSettings.autosave_enabled and uiSettings.autosave_config then
				task.defer(function()
					if isfile(getConfigFilePath(self, uiSettings.autosave_config)) then
						self:EnableAutoSave(uiSettings.autosave_config)
						task.wait(0.1)
						if SaveManager.Options.SaveManager_AutoSaveToggle then
							SaveManager.Options.SaveManager_AutoSaveToggle:SetValue(true)
						end
					end
				end)
			end
		end
	end

	SaveManager:BuildFolderTree()
end

return SaveManager
