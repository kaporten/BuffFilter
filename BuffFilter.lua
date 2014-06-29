require "Window"

local BuffFilter = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("BuffFilter", "Buff Filter")
BuffFilter.ADDON_VERSION = {0, 2, 0}

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
		--self.xmlDoc = nil -- Keep in mem for spawning child forms
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
				true)

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
	
	-- "learn" buffs from savedata
	if tSavedData ~= nil and type(tSavedData) == "table" and type(tSavedData.tKnownBuffs) == "table" then
		for _,b in ipairs(tSavedData.tKnownBuffs) do
			BuffFilter:LearnBuff(
				b.nBaseSpellId,
				b.strName,		
				b.strTooltip,
				b.strIcon,		
				b.bIsBeneficial,
				b.bShow
			)
		end
	end
end

-- Learn buffs either by reading from addon savedata file, or from tooltip mouseovers
function BuffFilter:LearnBuff(nBaseSpellId, strName, strTooltip, strIcon, bIsBeneficial, bShow)	
	if BuffFilter.tBuffsById == nil then self.tBuffsById = {} end
	if BuffFilter.tBuffsByTooltip == nil then self.tBuffsByTooltip = {} end

	-- Assume the two buff tables are in sync, and just check for presence in the first
	if BuffFilter.tBuffsById[nBaseSpellId] ~= nil then
		-- Buff already known, do nothing
		return
	end
	
	log:debug("New buff registered: '%s', tooltip: '%s'", strName, strTooltip)
	
	-- Construct buff details table
	local tBuffDetails =  {
		nBaseSpellId = nBaseSpellId,
		strName = strName,		
		strTooltip = strTooltip,
		strIcon = strIcon,		
		bIsBeneficial = bIsBeneficial,
		bShow = bShow
	}
	
	-- Add to byId table
	BuffFilter.tBuffsById[tBuffDetails.nBaseSpellId] = tBuffDetails
	
	-- Add to byTooltip table (multiple buffs per tooltip possible)
	if BuffFilter.tBuffsByTooltip[tBuffDetails.strTooltip] == nil then
		BuffFilter.tBuffsByTooltip[tBuffDetails.strTooltip] = {}
	end
	BuffFilter.tBuffsByTooltip[tBuffDetails.strTooltip][#BuffFilter.tBuffsByTooltip+1] = tBuffDetails
	
	-- Add buff to the Settings window
	local wndBuffLine = Apollo.LoadForm(self.xmlDoc, "BuffLineForm", BuffFilter.wndSettings:FindChild("BuffLineArea"), self)
	wndBuffLine:FindChild("BuffIcon"):SetSprite(tBuffDetails.strIcon)
	wndBuffLine:FindChild("BuffName"):SetText(tBuffDetails.strName)
	wndBuffLine:SetData(tBuffDetails)
	wndBuffLine:Show(true, false)
	
	BuffFilter.wndSettings:FindChild("BuffLineArea"):ArrangeChildrenVert()
end

function BuffFilter:OnConfigure()
	log:debug("OnConfigure")
	self.wndSettings:Show(true, false)
end


function BuffFilter:OnAcceptSettings()
	self.wndSettings:Show(false, true)
end

function BuffFilter:OnCancelSettings()
	self.wndSettings:Show(false, true)
end
---------------------------------------------------------------------------------------------------
-- BuffLineForm Functions
---------------------------------------------------------------------------------------------------
function BuffFilter:OnHideButtonSignal(wndHandler, wndControl)
	log:debug("OnHideButtonSignal")
end