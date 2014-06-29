require "Window"

local BuffFilter = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("BuffFilter", false)
BuffFilter.ADDON_VERSION = {0, 1, 0}

local log

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
	
	self.xmlDoc = XmlDoc.CreateFromFile("BuffFilter.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	-- Initialize empty settings, if none were loaded
	if self.tSettings == nil or self.tSettings.tBuffs == nil then
		self.tSettings = {}
		self.tSettings.tBuffs = {}
		log:info("No saved settings, first time load?")
	end

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
		self.xmlDoc = nil
	end
		
	-- Start timer for buff scanning
	self.scanTimer = ApolloTimer.Create(3, true, "OnTimer", self)
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
			 
			-- Extract info required to combine spellid + tooltip string
			local tBuffs = self.tSettings.tBuffs
			local splId = splSource:GetBaseSpellId()
			local conf = tBuffs[splId]
				
			-- First time this buff is seen?
			if conf == nil then
				-- NB: At this point in time, wndParent actually targets the icon-to-hide. 
				-- But using this ref would mean relying on the user to mouse-over the tooltip 
				-- every time it should be hidden. So, better to re-scan and tooltip-match later.
				local strTooltip = wndParent:GetBuffTooltip()
				conf = BuffFilter:ConstructSettings(splSource, strTooltip)
				tBuffs[splId] = conf
			end

			-- Return generated tooltip to client addon
			return wndTooltip
		end
	end	
end

-- Scan all active buffs for hide-this-buff config
function BuffFilter:OnTimer()
	--log:debug("BuffFilter timer")
	
	local activeBuffs = GameLib.GetPlayerUnit():GetBuffs()
	local tHideBene = BuffFilter:ScanBuffs(activeBuffs.arBeneficial)
	
	if #tHideBene > 0 then
		--log:debug("Hiding %d buffs", #tHideBene)
		BuffFilter:FilterBuffs(tHideBene)
	end
end

function BuffFilter:ScanBuffs(tActiveBuffs)
	--log:debug("Scanning buff list")
	if tActiveBuffs == nil then return {} end
	
	local tHide = {}
	local tBuffConfigs = self.tSettings.tBuffs
	
	-- For each active buff, check if we have a known config indicating that it should be hidden
	for _,splActiveBuff in ipairs(tActiveBuffs) do
		local splId = splActiveBuff.splEffect:GetBaseSpellId()
		local conf = tBuffConfigs[splId]
		
		if conf ~= nil and conf.Show == false then
			-- Buff to hide identified, add to TODO list
			tHide[#tHide+1] = conf		
			--log:debug("Active buff '%s' configured hiding", conf.Name)
		end
	end
	return tHide
end

function BuffFilter:ConstructSettings(splEffect, strTooltip)	
	--log:debug("New buff registered: '%s', tooltip: '%s'", splEffect:GetName(), strTooltip)
	return {
		BaseSpellId = splEffect:GetBaseSpellId(),
		Name = splEffect:GetName(),		
		Icon = splEffect:GetIcon(),		
		IsBeneficial = splEffect:IsBeneficial(),
		Tooltip = strTooltip,
		Show = true,		
	}
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

function BuffFilter:FilterBuffs(tHide)
	--log:debug("Filtering buffs")
	local playerBeneBuffBar = self:GetPlayerBeneBuffBar()
	self:FilterBuffsOnBar(playerBeneBuffBar, tHide)
end

function BuffFilter:FilterBuffsOnBar(wndBuffBar, tToHide)
	--log:debug("Filtering buffs on Bar")
	-- Get buff child windows on bar
	local wndCurrentBuffs = wndBuffBar:GetChildren()
	
	if wndCurrentBuffs == nil then return end	
			
	-- Buffs found, loop over them all, hide ones on todo list
	for _,wndCurrentBuff in ipairs(wndCurrentBuffs) do
		for _,b in ipairs(tToHide) do
			local strHideTooltip = b.Tooltip
			
			if wndCurrentBuff:GetBuffTooltip() == strHideTooltip then
				
				--log:debug("Hiding buff '%s'", b.Name)
				wndCurrentBuff:Show(false)
			end		
		end
	end
end

-- Save addon config per character. Called by engine when performing a controlled game shutdown.
function BuffFilter:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	-- Add current addon version to settings, for future compatibility/load checks
	self.tSettings.addonVersion = self.ADDON_VERSION
	
	-- Simply save the entire tSettings structure
	return self.tSettings
end

-- Restore addon config per character. Called by engine when loading UI.
function BuffFilter:OnRestore(eType, tSavedData)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	-- Store saved settings directly on self
	self.tSettings = tSavedData
end


