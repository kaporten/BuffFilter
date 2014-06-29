require "Window"

local BuffFilter = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("BuffFilter", true)
BuffFilter.ADDON_VERSION = {0, 7, 0}

local log

function BuffFilter:OnInitialize()
	-- Tables for criss-cross references of buffs & tooltips
	self.tBuffsById = self.tBuffsById or {}
	self.tBuffStatusByTooltip = self.tBuffStatusByTooltip or {}
end

function BuffFilter:OnEnable()	
	-- GeminiLogger options
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	log = GeminiLogging:GetLogger({
		level = GeminiLogging.DEBUG,
		pattern = "%d %n %c %l - %m",
		appender = "GeminiConsole"
	})
	
	self.log = log -- store ref for GeminiConsole-access to loglevel
	log:info("Initializing addon 'BuffFilter'")

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
	if self.tSavedData ~= nil and type(self.tSavedData) == "table" then
		log:info("Loading saved configuration")
		
		-- Register buffs from savedata
		if type(self.tSavedData.tKnownBuffs) == "table" then
			for _,b in pairs(self.tSavedData.tKnownBuffs) do		
				BuffFilter:RegisterBuff(
					b.nBaseSpellId,
					b.strName,		
					b.strTooltip,
					b.strIcon,		
					b.bIsBeneficial,
					b.bHide
				)
			end			
		end
		
		-- Restore interval timer setting			
		if type(self.tSavedData.nTimer) == "number" then
			self.wndSettings:FindChild("Slider"):SetValue(self.tSavedData.nTimer)
		else
			self.wndSettings:FindChild("Slider"):SetValue(3000)
		end
		self.wndSettings:FindChild("SliderValue"):SetText(tostring(self.wndSettings:FindChild("Slider"):GetValue()))
		
		-- Clear saved data object
		self.tSavedData = nil
	else
		log:info("No saved config found. First run?")
	end
			
	-- Fire scanner once and start timer
	BuffFilter:OnTimer()
	self.scanTimer = ApolloTimer.Create(self.wndSettings:FindChild("Slider"):GetValue()/1000, true, "OnTimer", self)
	
	-- Hook into tooltip generation
	BuffFilter:HookBuffTooltipGeneration()
	
	-- TODO: showing settings is only for dev, not prod
	self.wndSettings:Show(true, true)	
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
			false)

		-- Return generated tooltip to client addon
		return wndTooltip
	end
end

-- Scan all active buffs for hide-this-buff config
function BuffFilter:OnTimer()
	log:debug("BuffFilter timer")
	BuffFilter:FilterBuffsOnBar(BuffFilter:GetPlayerBeneBuffBar())
end


function BuffFilter:GetPlayerBeneBuffBar()
	if self.playerBeneBuffBar ~= nil then
		--log:debug("Reference to Player BeneBuffBar already found, returning that")
		return self.playerBeneBuffBar
	else
		--log:debug("Searching for reference to Player BeneBuffBar")
		
		-- Safely dig into the GUI elements
		local addonTargetFrame = Apollo.GetAddon("TargetFrame")
		if addonTargetFrame == nil then return end
		
		local luaUnitFrame = addonTargetFrame.luaUnitFrame
		if luaUnitFrame == nil then return end
		
		local wndMainClusterFrame = luaUnitFrame.wndMainClusterFrame
		if wndMainClusterFrame == nil then return end
		
		local wndBeneBuffBar = wndMainClusterFrame:FindChild("BeneBuffBar")
		if wndBeneBuffBar == nil then return end
		
		-- Player BeneBuffBar found, store ref for later use
		self.playerBeneBuffBar = wndBeneBuffBar
		return wndBeneBuffBar
	end
end

function BuffFilter:FilterBuffsOnBar(wndBuffBar)
	log:debug("Filtering buffs on Bar")
	-- Get buff child windows on bar
	local wndCurrentBuffs = wndBuffBar:GetChildren()
	
	if wndCurrentBuffs == nil then return end	
			
	-- Buffs found, loop over them all, hide ones on todo list
	for _,wndCurrentBuff in ipairs(wndCurrentBuffs) do
		local strBuffTooltip = wndCurrentBuff:GetBuffTooltip()
		
		local bShouldHide = BuffFilter.tBuffStatusByTooltip[strBuffTooltip]
		wndCurrentBuff:Show(not bShouldHide)
	end
end

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

-- Register buffs either by reading from addon savedata file, or from tooltip mouseovers
function BuffFilter:RegisterBuff(nBaseSpellId, strName, strTooltip, strIcon, bIsBeneficial, bHide)	
	--log:debug("RegisterBuff called")
	-- Assume the two buff tables are in sync, and just check for presence in the first
	if BuffFilter.tBuffsById[nBaseSpellId] ~= nil then
		-- Buff already known, do nothing
		return
	end
	
	log:info("Registering buff: '%s'", strName)
	
	-- Construct buff details table
	local tBuffDetails =  {
		nBaseSpellId = nBaseSpellId,
		strName = strName,		
		strTooltip = strTooltip,
		strIcon = strIcon,		
		bIsBeneficial = bIsBeneficial,
		bHide = bHide
	}
	
	-- Add to byId table
	BuffFilter.tBuffsById[tBuffDetails.nBaseSpellId] = tBuffDetails

	-- Update summarized show/hide status for this tooltip	
	if BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] == nil then
		BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] = false
	end
	if bHide == true then
		BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] = true
	end	
	
	-- Add buff to Settings window grid
	local grid = self.wndSettings:FindChild("Grid")
	local nRow = grid:AddRow("", "", tBuffDetails)
	grid:SetCellImage(nRow, 1, tBuffDetails.strIcon)
	grid:SetCellText(nRow, 2, tBuffDetails.strName)
	
	BuffFilter:SetGridRowStatus(nRow, tBuffDetails.bHide)
end

function BuffFilter:OnConfigure()
	self.wndSettings:Show(true, false)	
end


function BuffFilter:OnHideSettings()
	self.wndSettings:Show(false, true)
end


function BuffFilter:OnTimerIntervalChange(wndHandler, wndControl, fNewValue, fOldValue)
	self.wndSettings:FindChild("SliderValue"):SetText(tostring(fNewValue))
	self.scanTimer:Stop()
	self.scanTimer = ApolloTimer.Create(fNewValue/1000, true, "OnTimer", self)
end

function BuffFilter:OnGridSelChange(wndControl, wndHandler, nRow, nColumn)
	local grid = self.wndSettings:FindChild("Grid")	
	local tBuffDetails = grid:GetCellData(nRow, 1)
	local bUpdatedHide = not tBuffDetails.bHide
	
	--log:info("Toggling buff '%s', %s --> %s", tBuffDetails.strName, tostring(tBuffDetails.bHide), tostring(bUpdatedHide))
	
	local strTooltip = tBuffDetails.strTooltip
	
		
	-- When a buff is checked/unchecked, update *all* buffs with same tooltip, not just the checked one
	for r = 1, grid:GetRowCount() do -- for every row on the grid
		-- Get buff for this row
		local tRowBuffDetails = grid:GetCellData(r, 1)
			
		-- Check if this buff has same tooltip
		if tRowBuffDetails.strTooltip == strTooltip then
			tRowBuffDetails.bHide = bUpdatedHide
			self:SetGridRowStatus(r, bUpdatedHide)	
			log:info("Toggling buff '%s', %s --> %s", tBuffDetails.strName, tostring(tBuffDetails.bHide), tostring(bUpdatedHide))
		end

	end
	
	-- Also update the by-tooltip summary table to latest value
	BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] = tBuffDetails.bHide
	
	-- Force update
	BuffFilter:OnTimer()
end


function BuffFilter:SetGridRowStatus(nRow, bHide)
	local grid = self.wndSettings:FindChild("Grid")	

	if bHide == true then
		grid:SetCellImage(nRow, 3, "achievements:sprAchievements_Icon_Complete")
		grid:SetCellSortText(nRow, 3, "1")
	else
		grid:SetCellImage(nRow, 3, "")
		grid:SetCellSortText(nRow, 3, "0")
	end	
end

function BuffFilter:OnWindowKeyDown( wndHandler, wndControl, strKeyName, nScanCode, nMetakeys )
	log:debug("OnWindowKeyDown")
end

