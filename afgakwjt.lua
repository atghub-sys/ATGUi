---@diagnostic disable: undefined-global
local httpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local SaveManager = {} do
	SaveManager.FolderRoot = "ATGSettings"
	SaveManager.Ignore = {}
	SaveManager.Options = {}
	SaveManager.AutoSaveEnabled = false
	SaveManager.AutoSaveConfig = nil
	SaveManager.AutoSaveDebounce = false
	SaveManager.OriginalCallbacks = {}
	SaveManager.DefaultValues = {} -- เก็บค่า Default
	SaveManager.Parser = {
		Toggle = {
			Save = function(idx, object) 
				-- ตรวจสอบว่าค่าตรงกับ Default หรือไม่
				local defaultValue = SaveManager.DefaultValues[idx]
				if defaultValue ~= nil and defaultValue == object.Value then
					return nil -- ไม่ต้อง save ถ้าค่าเท่ากับ default
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
				if defaultValue ~= nil and tostring(defaultValue) == tostring(object.Value) then
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
				if defaultValue ~= nil and defaultValue == object.Value then
					return nil
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
				if defaultValue ~= nil then
					local defaultHex = defaultValue:ToHex()
					if defaultHex == hexValue and object.Transparency == (SaveManager.DefaultValues[idx .. "_transparency"] or 0) then
						return nil
					end
				end
				return { type = "Colorpicker", idx = idx, value = hexValue, transparency = object.Transparency }
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

	-- helpers
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
		if not isfolder(path) then
			makefolder(path)
		end
	end

	local function getConfigsFolder(self)
		local root = self.FolderRoot
		local placeId = getPlaceId()
		return root .. "/" .. placeId
	end

	local function getConfigFilePath(self, name)
		local folder = getConfigsFolder(self)
		return folder .. "/" .. name .. ".json"
	end

	local function getSaveManagerUIPath(self)
		local folder = getConfigsFolder(self)
		return folder .. "/savemanager_ui.json"
	end

	function SaveManager:BuildFolderTree()
		local root = self.FolderRoot
		ensureFolder(root)

		local placeId = getPlaceId()
		local placeFolder = root .. "/" .. placeId
		ensureFolder(placeFolder)
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

	function SaveManager:SetLibrary(library)
		self.Library = library
		self.Options = library.Options
	end

	-- บันทึกค่า Default ของแต่ละ Option
	function SaveManager:RegisterDefaultValue(idx, value, extraData)
		self.DefaultValues[idx] = value
		if extraData then
			for k, v in pairs(extraData) do
				self.DefaultValues[idx .. "_" .. k] = v
			end
		end
	end

	function SaveManager:Save(name)
		if (not name) then
			return false, "no config file is selected"
		end

		local fullPath = getConfigFilePath(self, name)
		local data = { objects = {} }

		for idx, option in next, SaveManager.Options do
			if not self.Parser[option.Type] then continue end
			if self.Ignore[idx] then continue end
			
			local saved = self.Parser[option.Type].Save(idx, option)
			if saved then -- เฉพาะค่าที่ไม่ใช่ default
				table.insert(data.objects, saved)
			end
		end

		local success, encoded = pcall(httpService.JSONEncode, httpService, data)
		if not success then
			return false, "failed to encode data"
		end

		local folder = fullPath:match("^(.*)/[^/]+$")
		if folder then ensureFolder(folder) end

		writefile(fullPath, encoded)
		return true
	end

	function SaveManager:SaveUI()
		local uiPath = getSaveManagerUIPath(self)
		local uiData = {
			autoload_enabled = (self:GetAutoloadConfig() ~= nil),
			autoload_config = (self:GetAutoloadConfig() or nil),
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
		if success then
			return decoded
		end
		return nil
	end

	-- โหลดแบบ Fast Load: แยก Toggle ออกมาโหลดทีหลัง
	function SaveManager:Load(name)
		if (not name) then
			return false, "no config file is selected"
		end

		local file = getConfigFilePath(self, name)
		if not isfile(file) then return false, "invalid file" end

		local success, decoded = pcall(httpService.JSONDecode, httpService, readfile(file))
		if not success then return false, "decode error" end

		local toggles = {}
		local others = {}

		-- แยก Toggle ออกจาก options อื่นๆ
		for _, option in next, decoded.objects do
			if option.type == "Toggle" then
				table.insert(toggles, option)
			else
				table.insert(others, option)
			end
		end

		-- โหลด options อื่นๆ ก่อน (ไม่ใช่ Toggle)
		for i, option in ipairs(others) do
			if self.Parser[option.type] then
				local parser = self.Parser[option.type]
				pcall(parser.Load, option.idx, option)
			end

			if i % 5 == 0 then
				task.wait() -- yield ทุก 5 items
			end
		end

		-- รอให้ UI พร้อม แล้วค่อยโหลด Toggle
		task.defer(function()
			task.wait(0.1) -- รอ UI render เสร็จ

			for i, option in ipairs(toggles) do
				if self.Parser.Toggle then
					pcall(self.Parser.Toggle.Load, option.idx, option)
				end

				if i % 5 == 0 then
					task.wait()
				end
			end
		end)

		return true
	end

	function SaveManager:Delete(name)
		if not name then
			return false, "no config file is selected"
		end

		local file = getConfigFilePath(self, name)
		if not isfile(file) then 
			return false, "config does not exist" 
		end

		delfile(file)
		
		local autopath = getConfigsFolder(self) .. "/autoload.txt"
		if isfile(autopath) then
			local currentAutoload = readfile(autopath)
			if currentAutoload == name then
				delfile(autopath)
			end
		end
		
		return true
	end

	function SaveManager:GetAutoloadConfig()
		local autopath = getConfigsFolder(self) .. "/autoload.txt"
		if isfile(autopath) then
			return readfile(autopath)
		end
		return nil
	end

	function SaveManager:SetAutoloadConfig(name)
		if not name then
			return false, "no config name provided"
		end
		
		local file = getConfigFilePath(self, name)
		if not isfile(file) then
			return false, "config does not exist"
		end
		
		local autopath = getConfigsFolder(self) .. "/autoload.txt"
		writefile(autopath, name)
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
		self:SetIgnoreIndexes({
			"InterfaceTheme", "AcrylicToggle", "TransparentToggle", "MenuKeybind"
		})
	end

	SaveManager._configListCache = nil
	SaveManager._configListCacheTime = 0

	function SaveManager:RefreshConfigList()
		local folder = getConfigsFolder(self)
		if not isfolder(folder) then
			return {}
		end

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
		if name then
			self:Load(name)
		end
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
					if option._isInCallback then
						return
					end

					option._isInCallback = true

					if originalCallback then
						local success, err = pcall(originalCallback, ...)
						if not success then
							warn("Callback error for " .. tostring(idx) .. ": " .. tostring(err))
						end
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

		-- Input สำหรับชื่อไฟล์
		local ConfigNameInput = section:AddInput("SaveManager_ConfigName", {
			Title = "Config Name",
			Description = "Enter config file name",
			Default = "MyConfig",
			Placeholder = "Enter name...",
			Numeric = false,
			Finished = false,
		})

		-- Dropdown สำหรับเลือกไฟล์
		local configList = self:RefreshConfigList()
		local ConfigDropdown = section:AddDropdown("SaveManager_ConfigDropdown", {
			Title = "Select Config",
			Description = "Choose a config to load",
			Values = configList,
			Default = configList[1] or nil,
		})

		-- Button สร้างไฟล์ใหม่
		section:AddButton({
			Title = "Create Config",
			Description = "Create new config file",
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigName.Value
				if name and name ~= "" then
					name = sanitizeFilename(name)
					local success, err = self:Save(name)
					if success then
						print("✅ Created config: " .. name)
						-- Refresh dropdown
						local newList = self:RefreshConfigList()
						ConfigDropdown:SetValues(newList)
						ConfigDropdown:SetValue(name)
					else
						warn("❌ Failed to create config: " .. tostring(err))
					end
				else
					warn("⚠️ Please enter a config name")
				end
			end
		})

		-- Button Save
		section:AddButton({
			Title = "Save Config",
			Description = "Save current settings",
			Callback = function()
				local selected = SaveManager.Options.SaveManager_ConfigDropdown.Value
				if selected then
					local success, err = self:Save(selected)
					if success then
						print("✅ Saved config: " .. selected)
					else
						warn("❌ Failed to save: " .. tostring(err))
					end
				else
					warn("⚠️ No config selected")
				end
			end
		})

		-- Button Load
		section:AddButton({
			Title = "Load Config",
			Description = "Load selected config",
			Callback = function()
				local selected = SaveManager.Options.SaveManager_ConfigDropdown.Value
				if selected then
					local success, err = self:Load(selected)
					if success then
						print("✅ Loaded config: " .. selected)
					else
						warn("❌ Failed to load: " .. tostring(err))
					end
				else
					warn("⚠️ No config selected")
				end
			end
		})

		-- Button Delete
		section:AddButton({
			Title = "Delete Config",
			Description = "Delete selected config",
			Callback = function()
				local selected = SaveManager.Options.SaveManager_ConfigDropdown.Value
				if selected then
					local success, err = self:Delete(selected)
					if success then
						print("✅ Deleted config: " .. selected)
						-- Refresh dropdown
						local newList = self:RefreshConfigList()
						ConfigDropdown:SetValues(newList)
						if #newList > 0 then
							ConfigDropdown:SetValue(newList[1])
						end
					else
						warn("❌ Failed to delete: " .. tostring(err))
					end
				else
					warn("⚠️ No config selected")
				end
			end
		})

		-- Button Refresh
		section:AddButton({
			Title = "Refresh List",
			Description = "Refresh config list",
			Callback = function()
				local newList = self:RefreshConfigList()
				ConfigDropdown:SetValues(newList)
				print("🔄 Refreshed config list")
			end
		})

		-- Auto Load Toggle
		local AutoloadToggle = section:AddToggle("SaveManager_AutoloadToggle", {
			Title = "Auto Load",
			Description = "Auto load config on startup",
			Default = (uiSettings and uiSettings.autoload_enabled) or false,
			Callback = function(value)
				if value then
					local selected = SaveManager.Options.SaveManager_ConfigDropdown.Value
					if selected then
						local ok, err = self:SetAutoloadConfig(selected)
						if not ok then
							if SaveManager.Options.SaveManager_AutoloadToggle then
								SaveManager.Options.SaveManager_AutoloadToggle:SetValue(false)
							end
							warn("❌ Failed to set autoload: " .. tostring(err))
						else
							print("✅ Auto load enabled for: " .. selected)
						end
					else
						SaveManager.Options.SaveManager_AutoloadToggle:SetValue(false)
						warn("⚠️ Please select a config first")
					end
				else
					self:DisableAutoload()
					print("🔴 Auto load disabled")
				end
			end
		})

		-- Auto Save Toggle
		local AutoSaveToggle = section:AddToggle("SaveManager_AutoSaveToggle", {
			Title = "Auto Save",
			Description = "Auto save when you change settings",
			Default = (uiSettings and uiSettings.autosave_enabled) or false,
			Callback = function(value)
				if value then
					local selected = SaveManager.Options.SaveManager_ConfigDropdown.Value
					if selected then
						self:EnableAutoSave(selected)
						print("✅ Auto save enabled for: " .. selected)
					else
						SaveManager.Options.SaveManager_AutoSaveToggle:SetValue(false)
						warn("⚠️ Please select a config first")
					end
				else
					self:DisableAutoSave()
					print("🔴 Auto save disabled")
				end
			end
		})

		-- ตั้งให้ไม่เซฟตัวเอง
		SaveManager:SetIgnoreIndexes({ 
			"SaveManager_AutoloadToggle",
			"SaveManager_AutoSaveToggle",
			"SaveManager_ConfigName",
			"SaveManager_ConfigDropdown"
		})

		-- โหลด Auto Load และ Auto Save
		if uiSettings then
			if uiSettings.autoload_enabled and uiSettings.autoload_config then
				task.defer(function()
					if isfile(getConfigFilePath(self, uiSettings.autoload_config)) then
						SaveManager:Load(uiSettings.autoload_config)
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
