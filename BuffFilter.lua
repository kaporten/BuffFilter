
require "Apollo"
require "Window"

local BuffFilter = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("BuffFilter", true, {"ToolTips"})
BuffFilter.ADDON_VERSION = {1, 2, 0}

local log
local H = Apollo.GetPackage("Gemini:Hook-1.0").tPackage

-- Enums for target/bufftype combinations
local eTargetTypes = {
	Player = "Player",
	Target = "Target"
}
local eBuffTypes = {
	Buff = "Buff",
	Debuff = "Debuff"
}

function BuffFilter:OnInitialize()
	-- Tables for criss-cross references of buffs & tooltips. May be initialized & populated during OnRestore.
	self.tBuffsById = self.tBuffsById or {}
	self.tBuffStatusByTooltip = self.tBuffStatusByTooltip or {}

	-- Configuration for supported bar types
	self.tBars = {
		-- Player buff / debuff bar
		PlayerBeneBar = {
			eTargetType = eTargetTypes.Player, 
			eBuffType = eBuffTypes.Buff
		},			
		PlayerHarmBar = {
			eTargetType = eTargetTypes.Player, 
			eBuffType = eBuffTypes.Debuff
		},			

		-- Target buff / debuff bar
		TargetBeneBar = {
			eTargetType = eTargetTypes.Target, 
			eBuffType = eBuffTypes.Buff
		},			
		TargetHarmBar = {
			eTargetType = eTargetTypes.Target, 
			eBuffType = eBuffTypes.Debuff
		},
	}
	
	-- Configuration for supported bar providers (Addons). Key must match actual Addon name.
	self.tBarProviders = {
		-- Stock UI
		["TargetFrame"] = {
			fDiscoverBar = BuffFilter.FindBarStockUI,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "luaUnitFrame",
				[eTargetTypes.Target] = "luaTargetFrame"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BeneBuffBar",
				[eBuffTypes.Debuff] = "HarmBuffBar"
			},
		},

		-- Potato UI
		["PotatoFrames"] = {
			fDiscoverBar = BuffFilter.FindBarPotatoUI,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "Player Frame",
				[eTargetTypes.Target] = "Target Frame"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BeneBuffBar",
				[eBuffTypes.Debuff] = "HarmBuffBar"
			},
		},		
		
		--SimpleBuffBar
		["SimpleBuffBar"] = {
			fDiscoverBar = BuffFilter.FindBarSimpleBuffBarUI,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "Player",
				[eTargetTypes.Target] = "Target"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BuffBar",
				[eBuffTypes.Debuff] = "DebuffBar"
			},
		},
	}
end

function BuffFilter:OnEnable()	
	-- GeminiLogger options	
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	
	log = GeminiLogging:GetLogger({
		level = GeminiLogging.WARN,
		pattern = "%d %n %c %l - %m",
		appender = "GeminiConsole"
	})

	BuffFilter.log = log -- store ref for GeminiConsole-access to loglevel
	--log:info("Initializing addon 'BuffFilter'")
	
	-- Load up forms
	self.xmlDoc = XmlDoc.CreateFromFile("BuffFilter.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

function BuffFilter:OnDocLoaded()
	-- Load settings form
	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
		self.wndSettings = Apollo.LoadForm(self.xmlDoc, "SettingsForm", nil, self)
		if self.wndSettings == nil then
			Apollo.AddAddonErrorText(self, "Could not load the Settings form.")
			return
		end		
		self.wndSettings:Show(false, true)
		self.xmlDoc = nil
	end
		
	-- Restore saved data
	local bStatus, message = pcall(BuffFilter.RestoreSaveData)
	if not bStatus then 
		log:warn("Failed to restore all savedata: %s", message)
	end
			
	-- Fire scanner once and start timer
	BuffFilter:OnTimer()
	self.scanTimer = ApolloTimer.Create(self.wndSettings:FindChild("Slider"):GetValue()/1000, true, "OnTimer", self)
	
	-- Hook into tooltip generation
	BuffFilter:HookBuffTooltipGeneration()
	
	-- Register slash command to display settings
	Apollo.RegisterSlashCommand("bf", "OnConfigure", self)
	Apollo.RegisterSlashCommand("bufffilter", "OnConfigure", self)
	
	--self.wndSettings:Show(true, true)	
end

-- Hack to combine spellId/details with the tooltip, since only half of each 
-- data set is available on the PlayerUnit:GetBuffs() vs GUI buff container
function BuffFilter:HookBuffTooltipGeneration()
	-- Tooltip basic code hooking lifted from addon Generalist. Super addon, super idea :)
	local origGetBuffTooltipForm = Tooltip.GetBuffTooltipForm
	Tooltip.GetBuffTooltipForm = function(luaCaller, wndParent, splSource, tFlags)			
		-- Let original function produce tooltip window
		local wndTooltip = origGetBuffTooltipForm(luaCaller, wndParent, splSource, tFlags)
		 
		-- Register the buff having its tooltip displayed.
		-- NB: At this point in time, wndParent actually targets the icon-to-hide. 
		-- But using this ref would mean relying on the user to mouse-over the tooltip 
		-- every time it should be hidden. So, better to re-scan and tooltip-match later.
		BuffFilter:RegisterBuff(
			splSource:GetBaseSpellId(),
			splSource:GetName(),	
			wndParent:GetBuffTooltip(),
			splSource:GetIcon(),		
			splSource:IsBeneficial(),
			false,
			false)

		-- Return generated tooltip to client addon
		return wndTooltip
	end
end

-- Scan all active buffs for hide-this-buff config
function BuffFilter:OnTimer()
	--log:debug("BuffFilter timer")
	local tBarsToFilter = BuffFilter:GetBarsToFilter()
	--log:debug("%d bars to scan identified", #tBarsToFilter)
	
	for _,b in ipairs(tBarsToFilter) do		
		-- Call provider-specific filter function.
		-- TODO: Safe call / error reporting? Nah, skipping in favor of performance for now.
		b.fFilterBar(b.bar, b.tBar.eTargetType)
	end
end

--
function BuffFilter:GetBarsToFilter()
	local result = {}

	-- Identify all bars to filter
	for strBar, tBar in pairs(BuffFilter.tBars) do
		-- Bar not previously identified, or is not permanent.
		-- Call each provider-specific function to scan for the bar
		for strProvider, tProviderDetails in pairs(BuffFilter.tBarProviders) do				
			if tProviderDetails.fDiscoverBar ~= nil then
				-- Translate bar target/bufftype properties to provider specific values
				local strBarTypeParam = tProviderDetails.tTargetType[tBar.eTargetType]
				local strBuffTypeParam = tProviderDetails.tBuffType[tBar.eBuffType]
				--log:debug("Scanning for bar type %s on provider='%s'. Provider parameters: strBarTypeParam='%s' strBuffTypeParam='%s'", strBar, strProvider, strBarTypeParam, strBuffTypeParam)
									
				-- Safe call for provider-specific discovery function
				local bStatus, discoveryResult, bPermanent = pcall(tProviderDetails.fDiscoverBar, strBarTypeParam, strBuffTypeParam)					
				if bStatus == true and discoveryResult ~= nil then
					--log:info("Bar '%s' found for provider '%s'", strBar, strProvider)
				
					-- Bar was found. Construct table with ref to bar, and provider-specific filter function.
					local tFoundBar = {
						tBar = tBar,								-- Bar config we found a hit for
						fFilterBar = tProviderDetails.fFilterBar,	-- Provider-specific filter function
						bar = discoveryResult,						-- Reference to actual bar instance							
					}
					
					-- Provider allows permanent ref-storage?
					if bPermanent == true then							
						BuffFilter.tBarStorage[strBar] = tFoundBar
					end
					
					-- Add found bar to result. Keep scanning, more providers may be active at the same time, for the same bar
					-- (f.ex. PotatoUI + SimpleBuffBar)
					result[#result+1] = tFoundBar
				else
					-- This is expected to occur, since provider-scanning is not 
					-- sorted by known providers (TODO?), but just checked one at a time
					--log:info("Unable to locate bar '%s' for provider '%s':\n%s", strBar, strProvider, tostring(discoveryResult))
				end
			end
		end
	end
	
	return result
end

-- Stock UI-specific bar search
function BuffFilter.FindBarStockUI(strTargetType, strBuffType)	
	local TF = Apollo.GetAddon("TargetFrame")
	if TF == nil then return end	
	
	local targetFrame = TF[strTargetType]
	local bar = targetFrame.wndMainClusterFrame:FindChild(strBuffType)	
	if bar == nil then return end

	-- If bar is found (ie., if above lines of code didn't fail or return), check if we found a Target frame.
	-- If so, hook into the stock "target changed" function for immediate updates
	if strTargetType == BuffFilter.tBarProviders.TargetFrame.tTargetType[eTargetTypes.Target] then
		if not H:IsHooked(TF, "OnTargetUnitChanged") then
			--log:info("Hooking TargetFrames.OnTargetUnitChanged")
			H:RawHook(TF, "OnTargetUnitChanged", BuffFilter.TargetChangedStock)
		end
	end
	
	return bar
end

-- Function for filtering buffs from any stock buff-bar. 
-- This function does not distinguish between buff and debuff-bars, since
-- they are the same kind of monster, just with different flags.
function BuffFilter.FilterStockBar(wndBuffBar, eTargetType)
	--log:debug("Filtering buffs on stock %s-bar", eTargetType)
	
	-- Get buff child windows on bar	
	if wndBuffBar == nil then
		log:warn("Unable to filter bar, wndBuffBar input is nil")
		return
	end
	
	local wndCurrentBuffs = wndBuffBar:GetChildren()
	
	-- No buffs on buffbar? Just do nothing then.
	if wndCurrentBuffs == nil then return end	
			
	-- Buffs found, loop over them all, hide ones on todo list
	for _,wndCurrentBuff in ipairs(wndCurrentBuffs) do
		local strBuffTooltip = wndCurrentBuff:GetBuffTooltip()
		
		local bShouldHide = BuffFilter.tBuffStatusByTooltip[strBuffTooltip] and BuffFilter.tBuffStatusByTooltip[strBuffTooltip][eTargetType]
		wndCurrentBuff:Show(not bShouldHide)
	end
end

-- Called when the target changes. Setup is done in the stock bar discovery function "FindBarStockUI"
function BuffFilter:TargetChangedStock(unitTarget)
	--log:info("Stock Target change intercepted")
	
	-- First, pass call to the real TargetFrame addon
	local TF = Apollo.GetAddon("TargetFrame")	
	H.hooks[TF].OnTargetUnitChanged(TF, unitTarget)

	--[[
		Curiosity: the target change itself does not actually update the buff-bar contents.
		That apparently happens at 0.1s intervals, regardless of target change. So, once
		a target change is identified (=now), schedule a single buff-filter in 100ms. That
		should be enough time for the buffs to actually be present on the target bars.
	]]
	if unitTarget ~= nil then
		BuffFilter.targetChangeTimer = ApolloTimer.Create(0.1, false, "OnTimer", BuffFilter)		
	end
end

-- PotatoUI-specific bar search
function BuffFilter.FindBarPotatoUI(strTargetType, strBuffType)
	local PUI = Apollo.GetAddon("PotatoFrames")
	if PUI == nil then return end

	-- PotatoUI stores the actual buff bar as a sub-element called "buffs" or "debuffs".
	-- So translate "BeneBuffBar"->"buffs" and "HarmBuffBar"->"debuffs".	
	local strSubframe = strBuffType == BuffFilter.tBarProviders["PotatoFrames"].tBuffType[eBuffTypes.Buff] and "buffs" or "debuffs"
	
	for _,frame in ipairs(PUI.tFrames) do
		if frame.frameData.name == strTargetType then
			return frame[strSubframe]:FindChild(strBuffType)
		end
	end
end

-- SimplebuffBar-specific bar search
function BuffFilter.FindBarSimpleBuffBarUI(strTargetType, strBuffType)   
	local SBB = Apollo.GetAddon("SimpleBuffBar")
	if SBB == nil then return end
	
	local bar = SBB.bars[strTargetType .. strBuffType]   
	if bar == nil then return end

	-- SimpleBuffBar addon found, and bar could be dug out. Must be fully loaded then.
	-- Hook into OnTargetUnitChanged for immediate filter-updates.
	if not H:IsHooked(SBB, "OnTargetUnitChanged") then
		--log:info("Hooking SimpleBuffBar.OnTargetUnitChanged")
		H:RawHook(SBB, "OnTargetUnitChanged", BuffFilter.TargetChangedSimpleBuffBar)
	end
	
	return bar
end

function BuffFilter:TargetChangedSimpleBuffBar(unitTarget)
	--log:info("SimpleBuffBar change intercepted")
	
	-- First, pass call to the real TargetFrame addon
	local SBB = Apollo.GetAddon("SimpleBuffBar")	
	H.hooks[SBB].OnTargetUnitChanged(SBB, unitTarget)

	if unitTarget ~= nil then
		BuffFilter.targetChangeTimer = ApolloTimer.Create(0.1, false, "OnTimer", BuffFilter)		
	end
end


-- Register buffs either by reading from addon savedata file, or from tooltip mouseovers
function BuffFilter:RegisterBuff(nBaseSpellId, strName, strTooltip, strIcon, bIsBeneficial, bHidePlayer, bHideTarget)	
	--log:debug("RegisterBuff called")
	-- Assume the two buff tables are in sync, and just check for presence in the first
	if BuffFilter.tBuffsById[nBaseSpellId] ~= nil then
		-- Buff already known, do nothing
		return
	end
	
	--log:info("Registering buff: '%s'", strName)
	
	-- Construct buff details table
	local tBuffDetails =  {
		nBaseSpellId = nBaseSpellId,
		strName = strName,		
		strTooltip = strTooltip,
		strIcon = strIcon,		
		bIsBeneficial = bIsBeneficial,
		bHide = {
			[eTargetTypes.Player] = bHidePlayer,
			[eTargetTypes.Target] = bHideTarget
		}
	}
	
	-- Add to byId table
	BuffFilter.tBuffsById[tBuffDetails.nBaseSpellId] = tBuffDetails

	-- Update summarized show/hide status for this tooltip. Any existing hide=true is preserved.
	local tTTStatus = BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] or {}
	tTTStatus[eTargetTypes.Player] = tTTStatus[eTargetTypes.Player] or bHidePlayer
	tTTStatus[eTargetTypes.Target] = tTTStatus[eTargetTypes.Target] or bHideTarget
	BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] = tTTStatus
	
	-- Add buff to Settings window grid
	local grid = self.wndSettings:FindChild("Grid")
	local nRow = grid:AddRow("", "", tBuffDetails)
	grid:SetCellImage(nRow, 1, tBuffDetails.bIsBeneficial and "ClientSprites:QuestJewel_Complete_Green" or "ClientSprites:QuestJewel_Offer_Red")
	grid:SetCellSortText(nRow, 1, tBuffDetails.bIsBeneficial and "ClientSprites:QuestJewel_Complete_Green" or "ClientSprites:QuestJewel_Offer_Red")--tBuffDetails.bIsBeneficial and "1" or "0")
	grid:SetCellImage(nRow, 2, tBuffDetails.strIcon)	
	grid:SetCellText(nRow, 3, tBuffDetails.strName)	
	BuffFilter:SetGridRowStatus(nRow, eTargetTypes.Player, bHidePlayer)
	BuffFilter:SetGridRowStatus(nRow, eTargetTypes.Target, bHideTarget)
end


--[[ SETTINGS SAVE/RESTORE ]]

-- Save addon config per character. Called by engine when performing a controlled game shutdown.
function BuffFilter:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	-- Add current addon version to settings, for future compatibility/load checks
	local tSaveData = {}
	tSaveData.addonVersion = self.ADDON_VERSION
	tSaveData.tKnownBuffs = BuffFilter.tBuffsById -- easy-save, dump buff-by-id struct
	tSaveData.nTimer = self.wndSettings:FindChild("Slider"):GetValue()
	return tSaveData	
end

-- Restore addon config per character. Called by engine when loading UI.
function BuffFilter:OnRestore(eType, tSavedData)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	-- Store saved data for later use 
	-- (wait with registering buffs until addon/gui is fully initialized)
	BuffFilter.tSavedData = tSavedData	
end

-- Actual use of table stored in OnRestore is postponed until addon is fully loaded.
-- This func is called by On
function BuffFilter:RestoreSaveData()
	-- Assume OnRestore has placed actual save-data in self.tSavedData
	if BuffFilter.tSavedData ~= nil and type(BuffFilter.tSavedData) == "table" then
		--log:info("Loading saved configuration")

		-- Register buffs from savedata
		if type(BuffFilter.tSavedData.tKnownBuffs) == "table" then
			for id,b in pairs(BuffFilter.tSavedData.tKnownBuffs) do
				local bStatus, message = pcall(BuffFilter.RestoreSaveDataBuff, id, b)
				if not bStatus then
					log:warn("Error loading settings for a buff: %s", message)
				end
			end			
		end
		
		-- Restore interval timer setting			
		if type(BuffFilter.tSavedData.nTimer) == "number" then
			BuffFilter.wndSettings:FindChild("Slider"):SetValue(BuffFilter.tSavedData.nTimer)
		else
			BuffFilter.wndSettings:FindChild("Slider"):SetValue(3000)
		end
		BuffFilter.wndSettings:FindChild("SliderLabel"):SetText(string.format("Scan interval (%.1fs):", BuffFilter.wndSettings:FindChild("Slider"):GetValue()/1000))
		
		-- Clear saved data object
		BuffFilter.tSavedData = nil
		
	else
		--log:info("No saved config found. First run?")
	end
end

function BuffFilter.RestoreSaveDataBuff(id, b)
	-- Sanity check each individual field
	if type(b.nBaseSpellId) ~= "number" then error(string.format("Saved buff Id %d is missing nBaseSpellId number", id)) end
	if type(b.strName) ~= "string" then error(string.format("Saved buff Id %d is missing name string", id)) end
	if type(b.strTooltip) ~= "string" then error(string.format("Saved buff Id %d is missing tooltip string", id)) end
	if type(b.strIcon) ~= "string" then error(string.format("Saved buff Id %d is missing icon string", id)) end
	if type(b.bIsBeneficial) ~= "boolean" then error(string.format("Saved buff Id %d is missing isBeneficial boolean", id)) end
	if type(b.bHide) ~= "table" then error(string.format("Saved buff Id %d is missing bHide table", id)) end
	if type(b.bHide[eTargetTypes.Player]) ~= "boolean" then error(string.format("Saved buff Id %d is missing bHide[Player] boolean", id)) end
	if type(b.bHide[eTargetTypes.Target]) ~= "boolean" then error(string.format("Saved buff Id %d is missing bHide[Target] boolean", id)) end
	
	-- All good, now register buff
	BuffFilter:RegisterBuff(
		b.nBaseSpellId,
		b.strName,		
		b.strTooltip,
		b.strIcon,		
		b.bIsBeneficial,
		b.bHide[eTargetTypes.Player],
		b.bHide[eTargetTypes.Target]
	)
end


--[[ SETTINGS GUI ]]

function BuffFilter:OnConfigure()
	self.wndSettings:Show(true, false)	
end

function BuffFilter:OnHideSettings()
	self.wndSettings:Show(false, true)
end

function BuffFilter:OnGridSelChange(wndControl, wndHandler, nRow, nColumn)
	local grid = self.wndSettings:FindChild("Grid")	
	local tBuffDetails = grid:GetCellData(nRow, 1)
	local strTooltip = tBuffDetails.strTooltip

	-- Determine if the Player or Target column was clicked
	local eTargetType = nColumn == 4 and eTargetTypes.Player or eTargetTypes.Target
	
	-- Toggled hide boolean for this target type
	local bUpdatedHide = not tBuffDetails.bHide[eTargetType]
	
	-- When a buff is checked/unchecked, update *all* buffs with same tooltip, not just the checked one
	for r = 1, grid:GetRowCount() do -- for every row on the grid
		-- Get buff for this row
		local tRowBuffDetails = grid:GetCellData(r, 1)
			
		-- Check if this buff has same tooltip
		if tRowBuffDetails.strTooltip == strTooltip then
			--log:info("Toggling buff '%s' for %s-bar, %s --> %s", tRowBuffDetails.strName, eTargetType, tostring(tRowBuffDetails.bHide[eTargetType]), tostring(bUpdatedHide))
			tRowBuffDetails.bHide[eTargetType] = bUpdatedHide
			self:SetGridRowStatus(r, eTargetType, bUpdatedHide)				
		end
	end
	
	-- Also update the by-tooltip summary table to latest value	
	BuffFilter.tBuffStatusByTooltip[strTooltip][eTargetType] = bUpdatedHide
	
	-- Force update
	BuffFilter:OnTimer()
end

function BuffFilter:OnTimerIntervalChange(wndHandler, wndControl, fNewValue, fOldValue)
	self.wndSettings:FindChild("SliderLabel"):SetText(string.format("Scan interval (%.1fs):", self.wndSettings:FindChild("Slider"):GetValue()/1000))
	self.scanTimer:Stop()
	self.scanTimer = ApolloTimer.Create(fNewValue/1000, true, "OnTimer", self)
end

function BuffFilter:SetGridRowStatus(nRow, eTargetType, bHide)
	local grid = self.wndSettings:FindChild("Grid")	

	-- Determine column from target type. (TODO: add mapping table for this?)
	local nColumn = eTargetType == eTargetTypes.Player and 4 or 5
	
	grid:SetCellImage(nRow, nColumn, bHide and "IconSprites:Icon_Windows_UI_CRB_Marker_Ghost" or "")
	grid:SetCellSortText(nRow, nColumn, bHide and "1" or "0")
end

