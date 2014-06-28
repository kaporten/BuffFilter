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
	    self.wndSettings:Show(true, true)
		
		self.xmlDoc = nil
		
		for idx = 1, 8 do
			self.wndSettings:FindChild("BuffContainerWindow"):SetUnit(GameLib.GetPlayerUnit())
			self.wndSettings:FindChild("BuffContainerWindow"):SetUnit(GameLib.GetPlayerUnit())
		end		
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
		
		-- Save the original function
		origGetBuffTooltipForm = Tooltip.GetBuffTooltipForm
		
		-- Now create a new callback function for the item form
		Tooltip.GetBuffTooltipForm = function(luaCaller, wndParent, splSource, tFlags)			
			-- Pass control to original tooltip generation function
			local wndTooltip = origGetBuffTooltipForm(luaCaller, wndParent, splSource, tFlags)
			 
			-- Register relevant info in BuffFilter addon
			local tBuffs = self.tSettings.tBuffs
			local splId = splSource:GetBaseSpellId()
			local conf = tBuffs[splId]
				
			-- First time this buff is seen
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


function BuffFilter:OnTimer()
	--log:debug("BuffFilter timer")
	
	local activeBuffs = GameLib.GetPlayerUnit():GetBuffs()
	local tBuffs = self.tSettings.tBuffs
	local tToHide = {}
	
	-- For each buff, check if we have known config
	for _,b in ipairs(activeBuffs.arBeneficial) do
		local splId = b.splEffect:GetBaseSpellId()
		local conf = tBuffs[splId]
		
		if conf ~= nil and conf.Show == false then
			-- Buff to hide identified, add to TODO list
			tToHide[#tToHide+1] = conf		
			log:debug("Marking buff '%s' for hiding", conf.Name)
		end
	end
	
	if #tToHide > 1 then
		BuffFilter:Hide(tToHide)
	end
end

function BuffFilter:ConstructSettings(splEffect, strTooltip)	
	log:debug("New buff registered: '%s', tooltip: '%s'", splEffect:GetName(), strTooltip)
	return {
		BaseSpellId = splEffect:GetBaseSpellId(),
		Name = splEffect:GetName(),		
		Icon = splEffect:GetIcon(),		
		IsBeneficial = splEffect:IsBeneficial(),
		Tooltip = strTooltip,
		Show = true,		
	}
end

function BuffFilter:Hide(tToHide)
	local playerBeneBuffBar = self:GetPlayerBeneBuffBar()
	self:FilterBuffsOnBar(playerBeneBuffBar, tToHide)
end

function BuffFilter:GetPlayerBeneBuffBar()
	if self.playerBeneBuffBar ~= nil then
		return self.playerBeneBuffBar
	else
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

function BuffFilter:FilterBuffsOnBar(wndBuffBar, tToHide)
	log:debug("FilterbuffsOnBar")
	-- Get buff child windows on bar
	local wndCurrentBuffs = wndBuffBar:GetChildren()
	if wndCurrentBuffs == nil then return end	
			
	-- Buffs found, loop over them all, hide ones on todo list
	for _,wndCurrentBuff in ipairs(wndCurrentBuffs) do
		if wndCurrentBuff:GetBuffTooltip() == tToHide.Tooltip then
			
			log:debug("Hiding buff '%s'", tToHide.Name)
			wndCurrentBuff:Show(false)
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

---------------------------------------------------------------------------------------------------
-- SettingsForm Functions
---------------------------------------------------------------------------------------------------

function BuffFilter:OnGenerateBuffTooltip(wndHandler, wndControl, tType, splBuff)
	log:debug("OnGenerateBuffTooltip")
	if wndHandler == wndControl then
		return
	end
	Tooltip.GetBuffTooltipForm(self, wndControl, splBuff, {bFutureSpell = false})
end


function BuffFilter:OnUDE( wndHandler, wndControl )
	log:debug("OnUDE")
end

function BuffFilter:OnWindowLoad( wndHandler, wndControl )
	log:debug("OnWindowLoad")
end

