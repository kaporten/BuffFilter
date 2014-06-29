require "Window"

local BuffFilter = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("BuffFilter", true)
BuffFilter.ADDON_VERSION = {0, 2, 0}

local log

function BuffFilter:OnInitialize()
	self.tBuffsById = self.tBuffsById or {}
	self.tBuffsByTooltip = self.tBuffsByTooltip or {}
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

	-- Hook into the tooltip generation framework
	self:HookBuffTooltipGeneration()	
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
		--self.xmlDoc = nil -- Keep in mem for spawning child forms
	end
		
	-- Set interval timer to saved value
	if self.tSavedData ~= nil and type(self.tSavedData) == "table" then
		-- "learn" buffs from savedata
		if type(self.tSavedData.tKnownBuffs) == "table" then
			log:info("Loading saved buff config")
			for _,b in pairs(self.tSavedData.tKnownBuffs) do		
				BuffFilter:LearnBuff(
					b.nBaseSpellId,
					b.strName,		
					b.strTooltip,
					b.strIcon,		
					b.bIsBeneficial,
					b.bHide
				)
			end			
		end
		
		-- Load interval timer setting
		if type(self.tSavedData.timer) == "number" then
			--self.wndSettings:FindChild("SliderBar")
		end
		
		self.tSavedData = nil
	else
		log:info("No saved config found. First run?")
	end
			
	-- Fire once and start timer for buff scanning
	BuffFilter:OnTimer()
	self.scanTimer = ApolloTimer.Create(3, true, "OnTimer", self)
	
	-- TODO: showing settings is only for dev, not prod
	self.wndSettings:Show(true, true)
end

-- Used to combine SpellID with the tooltip
function BuffFilter:HookBuffTooltipGeneration()
	local TT = Apollo.GetAddon("ToolTips")
	local origCreateCallNames = TT.CreateCallNames
	local origGetBuffTooltipForm

	-- Inject own function into CreateCallNames
	TT.CreateCallNames = function(luaCaller)	
		-- First, call the orignal function to create the original callbacks
		origCreateCallNames(luaCaller)
		
		-- Then, override GetBuffTooltipForm with own function
		origGetBuffTooltipForm = Tooltip.GetBuffTooltipForm
		Tooltip.GetBuffTooltipForm = function(luaCaller, wndParent, splSource, tFlags)			
			-- Let original function produce tooltip window
			local wndTooltip = origGetBuffTooltipForm(luaCaller, wndParent, splSource, tFlags)
			 
			-- Learn the buff.
			-- NB: At this point in time, wndParent actually targets the icon-to-hide. 
			-- But using this ref would mean relying on the user to mouse-over the tooltip 
			-- every time it should be hidden. So, better to re-scan and tooltip-match later.
			BuffFilter:LearnBuff(
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
	return tSaveData	
end

-- Restore addon config per character. Called by engine when loading UI.
function BuffFilter:OnRestore(eType, tSavedData)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	-- Store saved data for later use (wait with re-learning buffs until addon/gui is fully initialized)
	BuffFilter.tSavedData = tSavedData	
end

-- Learn buffs either by reading from addon savedata file, or from tooltip mouseovers
function BuffFilter:LearnBuff(nBaseSpellId, strName, strTooltip, strIcon, bIsBeneficial, bHide)	

	-- Assume the two buff tables are in sync, and just check for presence in the first
	if BuffFilter.tBuffsById[nBaseSpellId] ~= nil then
		-- Buff already known, do nothing
		return
	end
	
	log:debug("Buff registered: '%s'", strName)
	
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
	
	-- Add to byTooltip table (multiple buffs per tooltip possible)
	if BuffFilter.tBuffsByTooltip[tBuffDetails.strTooltip] == nil then
		BuffFilter.tBuffsByTooltip[tBuffDetails.strTooltip] = {}
	end
	BuffFilter.tBuffsByTooltip[tBuffDetails.strTooltip][#BuffFilter.tBuffsByTooltip+1] = tBuffDetails
	
	-- Update summarized show/hide status for this tooltip	
	if BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] == nil then
		BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] = false
	end
	if bHide == true then
		BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] = true
	end	
end

function BuffFilter:OnConfigure()
	table.sort(self.tBuffsById, 
		function(a, b)
			if a.bHide == true and b.bHide == false then return true end
			if a.bFailed == false and b.bFailed == true then return false end
			return a.strName < b.strName
		end
	)
	
	for _,b in ipairs(self.tBuffsById) do
		-- Add buff to the Settings window
		local wndBuffLine = Apollo.LoadForm(self.xmlDoc, "BuffLineForm", BuffFilter.wndSettings:FindChild("BuffLineArea"), self)
		wndBuffLine:FindChild("BuffIcon"):SetSprite(tBuffDetails.strIcon)
		wndBuffLine:FindChild("BuffName"):SetText(tBuffDetails.strName)
		wndBuffLine:FindChild("HideButton"):SetData(tBuffDetails)
		wndBuffLine:FindChild("HideButton"):SetCheck(tBuffDetails.bHide)
		wndBuffLine:Show(true, false)
	end
		
	BuffFilter.wndSettings:FindChild("BuffLineArea"):ArrangeChildrenVert()
	self.wndSettings:Show(true, false)	
end


function BuffFilter:OnHideSettings()
	self.wndSettings:Show(false, true)
end


function BuffFilter:OnHideButtonChange(wndHandler, wndControl)	
	log:debug("OnHideButtonChange")
	local tBuffDetails = wndControl:GetData()	
	local bHide = wndControl:IsChecked()
		
	-- When a buff is checked/unchecked, update *all* buffs with same tooltip, not just the checked one
	for _,b in ipairs(BuffFilter.tBuffsByTooltip[tBuffDetails.strTooltip]) do
		b.bHide = bHide
	end
	
	-- Also update the by-tooltip summary table 
	BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] = bHide
	
	-- Force update
	BuffFilter:OnTimer()
end


---------------------------------------------------------------------------------------------------
-- SettingsForm Functions
---------------------------------------------------------------------------------------------------
function BuffFilter:OnTimerIntervalChange(wndHandler, wndControl, fNewValue, fOldValue)
	self.wndSettings:FindChild("ScanIntervalLabel"):SetText(tostring(fNewValue))
	self.scanTimer:Stop()
	self.scanTimer = ApolloTimer.Create(fNewValue/1000, true, "OnTimer", self)
end

