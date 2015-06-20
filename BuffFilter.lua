--[[
	BuffFilter by porten.
	Comments/suggestions/bug reports welcome, find me on Curse or porten@gmail.com
--]]
require "Apollo"
require "Window"


local Major, Minor, Patch = 4, 3, 0
local BuffFilter = {}

-- Enums for target/bufftype combinations
local eTargetTypes = {
	Player = "Player",
	Target = "Target",
	Focus = "Focus",
	TargetOfTarget = "TargetOfTarget"
}
local eBuffTypes = {
	Buff = "Buff",
	Debuff = "Debuff"
}

-- Buff sort priorities (just high/low for now)
local ePriority = {
	High = 1,
	Unset = 5,
	Low = 9
}

function BuffFilter:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 
    return o
end

function BuffFilter:Init()
	-- Only actually load BuffFilter if it is not already loaded
	-- This is to prevent double-loads caused by "bufffilter" vs "BuffFilter" dir renames
	if Apollo.GetAddon("BuffFilter") ~= nil then
		return
	end
	
	-- Tables for criss-cross references of buffs & tooltips. May be initialized & populated during OnRestore.
	self.tBuffsById = self.tBuffsById or {}
	self.tBuffStatusByTooltip = self.tBuffStatusByTooltip or {}
	
	-- Configuration for supported bar providers (Addons). Key must match actual Addon name.
	self.tSupportedBarProviders = {
		-- Stock UI
		["TargetFrame"] = {
			fDiscoverBar =
				function(addonProvider, strTargetType, strBuffType)
					return addonProvider[strTargetType].wndMainClusterFrame:FindChild(strBuffType)
				end,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "luaUnitFrame",
				[eTargetTypes.Target] = "luaTargetFrame",
				[eTargetTypes.Focus] = "luaFocusFrame"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BeneBuffBar",
				[eBuffTypes.Debuff] = "HarmBuffBar"
			},
		},
		
		-- Potato UI 2.8
		["PotatoBuffs"] = {
			fDiscoverBar =
				function(addonProvider, strTargetType, strBuffType)
					return addonProvider[strTargetType .. strBuffType].wndBuffs:FindChild("Buffs")
				end,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "luaPlayer",
				[eTargetTypes.Target] = "luaTarget",
				[eTargetTypes.Focus] = "luaFocus",
				[eTargetTypes.TargetOfTarget] = "luaToT"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "Buffs",
				[eBuffTypes.Debuff] = "Debuffs"
			},
		},		
		
		-- SimpleBuffBar
		["SimpleBuffBar"] = {
			fDiscoverBar =
				function(addonProvider, strTargetType, strBuffType)
					return addonProvider.bars[strTargetType .. strBuffType]
				end,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "Player",
				[eTargetTypes.Target] = "Target",
				[eTargetTypes.Focus] = "Focus"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BuffBar",
				[eBuffTypes.Debuff] = "DebuffBar"
			},
		},
		
		-- Viking Unit Frames
		["VikingUnitFrames"] = {
			fDiscoverBar =
				function(addonProvider, strTargetType, strBuffType)
					return addonProvider[strTargetType].wndUnitFrame:FindChild(strBuffType)
				end,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "tPlayerFrame",
				[eTargetTypes.Target] = "tTargetFrame",
				[eTargetTypes.Focus] = "tFocusFrame",
				[eTargetTypes.TargetOfTarget] = "tToTFrame"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "Good",
				[eBuffTypes.Debuff] = "Bad"
			},		
		},
		
		["FastTargetFrame"] = {
			fDiscoverBar =
				function(addonProvider, strTargetType, strBuffType)
					return addonProvider[strTargetType].wndMainClusterFrame:FindChild(strBuffType)
				end,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "luaUnitFrame",
				[eTargetTypes.Target] = "luaTargetFrame",
				[eTargetTypes.Focus] = "luaFocusFrame"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BeneBuffBar",
				[eBuffTypes.Debuff] = "HarmBuffBar"
			},
		},

		["KuronaFrames"] = {
			fDiscoverBar =
				function(addonProvider, strTargetType, strBuffType)
					return addonProvider[strTargetType]:FindChild(strBuffType)
				end,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "playerFrame",
				[eTargetTypes.Target] = "targetFrame",
				[eTargetTypes.Focus] = "focusFrame"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BeneBuffBar",
				[eBuffTypes.Debuff] = "HarmBuffBar"
			},
		},
		
		["AlterFrame"] = {
			fDiscoverBar =
				function(addonProvider, strTargetType, strBuffType)
					return addonProvider[strTargetType]:FindChild(strBuffType)
				end,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "wndMain",
				[eTargetTypes.Target] = "wndTarget",
				[eTargetTypes.Focus] = "wndFocus"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BeneBuffBar",
				[eBuffTypes.Debuff] = "HarmBuffBar"
			},
		},
		
		["CandyUI_UnitFrames"] = {
			fDiscoverBar =
				function(addonProvider, strTargetType, strBuffType)
					return addonProvider[strTargetType]:FindChild(strBuffType)
				end,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "wndPlayerUF",
				[eTargetTypes.Target] = "wndTargetUF",
				[eTargetTypes.Focus] = "wndFocusUF",
				[eTargetTypes.TargetOfTarget] = "wndToTUF"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BuffContainerWindow",
				[eBuffTypes.Debuff] = "DebuffContainerWindow"
			},
		},
		
		["ForgeUI_UnitFrames"] = {
			fDiscoverBar =
				function(addonProvider, strTargetType, strBuffType)
					return addonProvider[strTargetType .. strBuffType]
				end,
			fFilterBar = BuffFilter.FilterStockBar,
			tTargetType = {
				[eTargetTypes.Player] = "wndPlayer",
				[eTargetTypes.Target] = "wndTarget",
				[eTargetTypes.Focus] = "wndFocus"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BuffFrame",
				[eBuffTypes.Debuff] = "DebuffFrame"
			},
		},		
	}
	
	-- Mapping tables for the Grids column-to-targettype translation
	self.tTargetToColumn = {
		[eTargetTypes.Player] = 4,
		[eTargetTypes.Target] = 5,
		[eTargetTypes.Focus] = 6,
		[eTargetTypes.TargetOfTarget] = 7,
	}
	
	-- Reverse map tTargetToColumn
	self.tColumnToTarget = {}
	for k,v in pairs(self.tTargetToColumn) do self.tColumnToTarget[v] = k end

	-- Used to control the settings gui tab buttons
	self.tTabButtonToForm = {
		BuffsTabBtn = "BuffsGroup",
		ConfigurationTabBtn = "ConfigurationGroup",
	}
	
	-- Shallow copy the supported bar provider list
	self.tActiveBarProviders = {}
	for k,v in pairs(self.tSupportedBarProviders) do self.tActiveBarProviders[k] = v end
	
	Apollo.RegisterAddon(self, true, "BuffFilter", {"ToolTips", "VikingTooltips"})
end

function BuffFilter:OnLoad()	
	-- Load up forms
	self.xmlDoc = XmlDoc.CreateFromFile("BuffFilter.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	Event_FireGenericEvent("OneVersion_ReportAddonInfo", "BuffFilter", Major, Minor, Patch)
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
	
	-- Preselect tab 1
	self.wndSettings:FindChild("BuffsTabBtn"):SetCheck(true)
	self.wndSettings:FindChild("BuffsGroup"):Show(true, true)
	self.wndSettings:FindChild("ConfigurationGroup"):Show(false, true)
	
	-- Set default values
	BuffFilter:SetDefaultValues()
	
	-- Override default values with saved data (if present)	
	local bStatus, message = pcall(BuffFilter.RestoreSaveData)
	if not bStatus then 
		local errmsg = string.format("Error restoring settings:\n%s", message)
		Apollo.AddAddonErrorText(self, errmsg)
	end
		
	-- Update GUI with current values
	self:UpdateSettingsGUI()
					
	-- Hook into tooltip generation
	BuffFilter:HookBuffTooltipGeneration()
	
	-- Register slash command to display settings
	Apollo.RegisterSlashCommand("bf", "OnConfigure", self)
	Apollo.RegisterSlashCommand("bufffilter", "OnConfigure", self)

	-- Register events so buffs can be re-filtered outside of the timered schedule
	Apollo.RegisterEventHandler("ChangeWorld", "OnChangeWorld", self) -- on /reloadui and instance-changes	
	Apollo.RegisterEventHandler("UnitEnteredCombat", "OnUnitEnteredCombat", self) -- when entering/exiting combat
	Apollo.RegisterEventHandler("TargetUnitChanged", "OnTargetUnitChanged", self) -- when changing target
	Apollo.RegisterEventHandler("AlternateTargetUnitChanged", "OnTargetUnitChanged", self) -- when changing focus
	
	-- New Buff update events
	Apollo.RegisterEventHandler("BuffAdded", "OnBuffAdded", self)
	
	self:StartInitialTimer()
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
			{	
				[eTargetTypes.Player] = false,
				[eTargetTypes.Target] = false,
				[eTargetTypes.Focus] = false,
				[eTargetTypes.TargetOfTarget] = false
			},
			ePriority.Unset)

		-- Return generated tooltip to client addon
		return wndTooltip
	end
end

function BuffFilter:OnDependencyError()
	-- Either regular Tooltip or VikingTooltips must be present
	if Apollo.GetAddon("ToolTips") ~= nil then
		return true
	end
	
	if Apollo.GetAddon("VikingTooltips") ~= nil	then
		Tooltip = Apollo.GetAddon("VikingTooltips")
		return true
	end
end

function BuffFilter:ScheduleFilter(bOverrideCooldown, nOverrideDelay)
	-- Cooldown override = stop any cooldown timer, then schedule as normal
	if bOverrideCooldown and self.timerCooldown ~= nil then
		self.timerCooldown:Stop()
		self.timerCooldown = nil
	end

	--[[
		Scheduled filter is pending, or cooldown is in effect. 
		In either case, just indicate the need for an extra filtering pass.
	--]]
	if self.timerDelay ~= nil or self.timerCooldown ~= nil then 
		self.bScheduleExtraFiltering = true
	else
		-- No pending scheduled filter, no cooldown. Schedule filtering.
		-- Use a timer even if nTimerDelay is 0. This allows other event-driven processes to finish up their work (such as actually constructing the buff icon) before it is filtered.
		self.timerDelay = ApolloTimer.Create((nOverrideDelay or self.tSettings.nTimerDelay)/1000, false, "ExecuteScheduledFilter", BuffFilter)		
	end
end

function BuffFilter:ExecuteScheduledFilter()
	-- Perform filter & sort
	self:Filter()

	-- Start cooldown timer
	self.timerDelay = nil
	
	-- No cooldown? No need for a timer then.
	if self.tSettings.nTimerCooldown == 0 then
		self:OnCooldownFinished()
	else
		self.timerCooldown = ApolloTimer.Create(self.tSettings.nTimerCooldown/1000, false, "OnCooldownFinished", BuffFilter)
	end
end

function BuffFilter:OnCooldownFinished()
	self.timerCooldown = nil

	-- If another filtering was queued up, clear the queue-indicator and schedule another
	if self.bScheduleExtraFiltering == true then
		self.bScheduleExtraFiltering = false
		self:ScheduleFilter()
	end
end


-- Scan all active buffs for hide-this-buff config
function BuffFilter:Filter()
	-- Determine if "only hide in combat" is enabled, and affects this pass
	-- NB: Even if hiding is disabled, the pass must go on to re-show hidden buffs.
	if BuffFilter.tSettings.bOnlyHideInCombat == true then
		local pu = GameLib.GetPlayerUnit()
		if pu ~= nil then
			self.bDisableHiding = not pu:IsInCombat()
		end		
	else
		self.bDisableHiding = false
	end
	
	local tBarsToFilter = self:GetBarsToFilter()
	
	for _,b in ipairs(tBarsToFilter) do		
		-- Call provider-specific filter function.
		-- TODO: Safe call / error reporting? Nah, skipping in favor of performance for now.
		b.fFilterBar(b.bar, b.eTargetType, b.eBuffType)
		
		if BuffFilter.tSettings.bEnableSorting == true then
			self:SortStockBar(b.bar)
		end
	end
end

-- Based on config for bars / providers, attempt to locate all buffbars on the GUIs.
function BuffFilter:GetBarsToFilter()
	local result = {}

	-- For every provider/target/bufftype combination,
	-- call each provider-specific function to scan for the bar
	for strProvider, tProviderDetails in pairs(BuffFilter.tActiveBarProviders) do
		local addonProvider = Apollo.GetAddon(strProvider)
		if addonProvider ~= nil then 
			for _,eTargetType in pairs(eTargetTypes) do
				local strBarTypeParam = tProviderDetails.tTargetType[eTargetType]
				if strBarTypeParam ~= nil then
					for _,eBuffType in pairs(eBuffTypes) do		
						local strBuffTypeParam = tProviderDetails.tBuffType[eBuffType]
						if strBuffTypeParam ~= nil then																	
							-- Safe call provider-specific discovery function
							local bStatus, foundBar = pcall(tProviderDetails.fDiscoverBar, addonProvider, strBarTypeParam, strBuffTypeParam)					
							if bStatus == true and foundBar ~= nil then
								-- Bar was found. Construct table with ref to bar, and provider-specific filter function.
								local tFoundBar = {									
									eTargetType = eTargetType,					-- Target-type (Player, Target, Focus etc)
									eBuffType = eBuffType,						-- Buff type (Buffs or Debuffs)
									fFilterBar = tProviderDetails.fFilterBar,	-- Provider-specific filter function
									addonProvider = addonProvider,				-- Addon which provides the bar to filter
									bar = foundBar,								-- Reference to actual bar instance
								}
								-- Add found bar to result. Check remaining combos, more providers may be active at the same time, for the same bar
								result[#result+1] = tFoundBar
							end
						end
					end
				end
			end
		end
	end	
	
	return result
end

-- Function for filtering buffs from any stock buff-bar. 
-- This function does not distinguish between buff and debuff-bars, since
-- they are the same kind of monster, just with different flags.
function BuffFilter.FilterStockBar(wndBuffBar, eTargetType, eBuffType)
	-- Get buff child windows on bar	
	if wndBuffBar == nil then
		--log:warn("Unable to filter bar, wndBuffBar input is nil")
		return
	end
	
	local wndCurrentBuffs = wndBuffBar:GetChildren()
	
	-- No buffs on buffbar? Just do nothing then.
	if wndCurrentBuffs == nil then 
		--log:warn("No child windows on buffbar")
		return
	end
			
	-- Buffs icons found, loop over them all, hide marked ones
	for _,wndCurrentBuff in ipairs(wndCurrentBuffs) do
		-- Default behaviour is to always show (or re-show hidden) buffs
		local bShow = true
		
		-- Only choose to hide (or keep hidden) buffs if hiding is enabled
		-- (Currently, the only way to completely disable hiding is via hide-in-combat-only feature (while out of combat))
		if BuffFilter.bDisableHiding == false then
			-- Get tooltip for buff-icon currently being inspected
			local strBuffTooltip = wndCurrentBuff:GetBuffTooltip()
			
			-- Certain buffs will have no tooltip message - just ignore these for now, only handle buffs with tooltip
			if strBuffTooltip ~= nil and strBuffTooltip:len() > 0 then
				-- Check if tooltip is marked for hiding
				local bMarked = BuffFilter.tBuffStatusByTooltip[strBuffTooltip] and BuffFilter.tBuffStatusByTooltip[strBuffTooltip][eTargetType]
				
				-- Check if inverse-hiding flag is set, if so, flip the bMarked flag
				if BuffFilter.tSettings.bInverseFiltering[eBuffType] == true then
					bMarked = not bMarked
				end
				
				-- Finally, flip marked-for-hiding flag to match wnd:Show input
				bShow = not bMarked
			end
		end

		-- Show/hide current buff icon
		wndCurrentBuff:Show(bShow)
	end
end

function BuffFilter:SortStockBar(wndBuffBar)
	wndBuffBar:ArrangeChildrenHorz(0, 
		function(a, b) 
			local strTooltipA = a:GetBuffTooltip()
			local strTooltipB = b:GetBuffTooltip()
			
			-- Tooltip-less buffs encountered. Buff with tooltip wins the priority-check.
			if strTooltipA == nil or strTooltipA:len() <= 1 or strTooltipB == nil or strTooltipB:len() <= 1 then
				return strTooltipA ~= nil and strTooltipA:len() >= 1
			end
			
			local tStatusA = BuffFilter.tBuffStatusByTooltip[strTooltipA]
			local tStatusB = BuffFilter.tBuffStatusByTooltip[strTooltipB]
		
			local nPrioA = tStatusA and tStatusA.nPriority or ePriority.Unset
			local nPrioB = tStatusB and tStatusB.nPriority or ePriority.Unset

			return nPrioA < nPrioB
		end
	)
end

-- When target changes, schedule an extra near-immediate buff filtering. 
function BuffFilter:OnTargetUnitChanged(unitTarget)
	-- Schedule a cooldown-ignoring filtering. Allow a few hundred ms so the target/focus frame is loaded
	self:ScheduleFilter(true, 300)	
end

-- Register buffs either by reading from addon savedata file, or from tooltip mouseovers
function BuffFilter:RegisterBuff(nBaseSpellId, strName, strTooltip, strIcon, bIsBeneficial, bHide, nPriority)
	-- Assume the two buff tables are in sync, and just check for presence in the first
	if BuffFilter.tBuffsById[nBaseSpellId] ~= nil then	
		-- Buff already known, do nothing
		return
	end
	
	-- Input sanity check
	if type(nBaseSpellId) ~= "number" then
		--log:debug("Trying to register buff with no spellId. Name: %s, Tooltip: %s", tostring(strName), tostring(strTooltip))
		return
	end
	
	if type(strName) ~= "string" or strName:len() < 1 then
		--log:debug("Trying to register buff with no name. SpellId: %d, Tooltip: %s", nBaseSpellId, tostring(strTooltip))
		return
	end

	if type(strTooltip) ~= "string" or strTooltip:len() < 1 then
		--log:debug("Trying to register buff with no tooltip. SpellId: %d, Name: %s", nBaseSpellId, tostring(strName))
		return
	end
	
	if type(strIcon) ~= "string" or strIcon:len() < 1 then
		--log:debug("Trying to register buff with no icon. SpellId: %d, Name: %s", nBaseSpellId, tostring(strName))
		return
	end	
	
	--log:info("Registering buff: '%s', priority: %s", strName, tostring(nPriority))
	
	-- Construct buff details table
	local tBuffDetails = {
		nBaseSpellId = nBaseSpellId,
		strName = strName,		
		strTooltip = strTooltip,
		strIcon = strIcon,		
		bIsBeneficial = bIsBeneficial,
		bHide = bHide,
		nPriority = nPriority or ePriority.Unset
	}
	
	-- Add to byId table
	BuffFilter.tBuffsById[tBuffDetails.nBaseSpellId] = tBuffDetails
	
	-- Add buff to Settings window grid
	
	local grid = self.wndSettings:FindChild("Grid")
	local nRow = grid:AddRow("", "", tBuffDetails)
	grid:SetCellImage(nRow, 1, tBuffDetails.bIsBeneficial and "ClientSprites:QuestJewel_Complete_Green" or "ClientSprites:QuestJewel_Offer_Red")
	grid:SetCellSortText(nRow, 1, tBuffDetails.bIsBeneficial and "ClientSprites:QuestJewel_Complete_Green" or "ClientSprites:QuestJewel_Offer_Red")
	grid:SetCellImage(nRow, 2, tBuffDetails.strIcon)	
	grid:SetCellText(nRow, 3, tBuffDetails.strName)	
	
	-- Update tooltip summary status for buff
	local tTTStatus = BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] or {}
	for k,v in pairs(bHide) do
		tTTStatus[k] = tTTStatus[k] or v
		BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip] = tTTStatus
	end

	-- Update settings gui grid
	for k,v in pairs(bHide) do
		BuffFilter:SetGridRowStatus(nRow, k, v)
	end
	
	-- Also update priority (if not already set)
	BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip].nPriority = BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip].nPriority or nPriority
	BuffFilter:SetGridRowPriority(nRow, BuffFilter.tBuffStatusByTooltip[tBuffDetails.strTooltip].nPriority)
end


--[[ SETTINGS SAVE/RESTORE ]]

-- Save addon config per character. Called by engine when performing a controlled game shutdown.
function BuffFilter:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	local tSaveData = {}
	tSaveData.tKnownBuffs = BuffFilter.tBuffsById -- easy-save, dump buff-by-id struct
	tSaveData.nTimerDelay = self.tSettings.nTimerDelay
	tSaveData.nTimerCooldown = self.tSettings.nTimerCooldown
	tSaveData.bOnlyHideInCombat = self.tSettings.bOnlyHideInCombat
	tSaveData.bEnableSorting = self.tSettings.bEnableSorting
	tSaveData.bInverseFiltering = self.tSettings.bInverseFiltering
	
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

-- Called prior to loading saved settings. Ensures all fields have meaningful defaults
function BuffFilter:SetDefaultValues()
	self.tSettings = {}
	self.tSettings.nTimerDelay = 0
	self.tSettings.nTimerCooldown = 1000
	
	-- Various config options
	self.tSettings.bOnlyHideInCombat = false	
	self.tSettings.bEnableSorting = false
	
	-- Inverse filtering table
	self.tSettings.bInverseFiltering = {
		[eBuffTypes.Buff] = false,
		[eBuffTypes.Debuff] = false	
	}	
end

-- Called after restoring saved data. Updates all GUI elements.
function BuffFilter:UpdateSettingsGUI()
	-- Update timer value and labels
	self.wndSettings:FindChild("DelaySlider"):SetValue(self.tSettings.nTimerDelay)
	self.wndSettings:FindChild("DelaySliderLabel"):SetText(string.format("Event filter-delay (%.2fs):", self.tSettings.nTimerDelay/1000))	

	self.wndSettings:FindChild("CooldownSlider"):SetValue(self.tSettings.nTimerCooldown)
	self.wndSettings:FindChild("CooldownSliderLabel"):SetText(string.format("Filtering cooldown (%.2fs):", self.tSettings.nTimerCooldown/1000))	
	
	self.wndSettings:FindChild("InCombatBtn"):SetCheck(self.tSettings.bOnlyHideInCombat)
	self.wndSettings:FindChild("InverseBuffsBtn"):SetCheck(self.tSettings.bInverseFiltering[eBuffTypes.Buff])
	self.wndSettings:FindChild("InverseDebuffsBtn"):SetCheck(self.tSettings.bInverseFiltering[eBuffTypes.Debuff])
	self.wndSettings:FindChild("EnableSortingBtn"):SetCheck(self.tSettings.bEnableSorting)
end

-- Actual use of table stored in OnRestore is postponed until addon is fully loaded, 
-- so GUI elements can be updated as well.
function BuffFilter:RestoreSaveData()
	-- Assume OnRestore has placed actual save-data in BuffFilter.tSavedData. Abort restore if no data is found.
	-- NB: RestoreSaveData is pcall'ed with no self context, so use BuffFilter global rather than self
	if BuffFilter.tSavedData == nil or type(BuffFilter.tSavedData) ~= "table" then
		Print("No saved BuffFilter configuration found. First run?")
		return
	end
	
	-- Register buffs from savedata
	if type(BuffFilter.tSavedData.tKnownBuffs) == "table" then
		for id,b in pairs(BuffFilter.tSavedData.tKnownBuffs) do
			local bStatus, message = pcall(BuffFilter.RestoreSaveDataBuff, id, b)
			if not bStatus then
				local errmsg = string.format("Error restoring settings for a buff:\n%s", message)
				Apollo.AddAddonErrorText(BuffFilter, errmsg)
			end
		end			
	end
	
	--[[ Override default values with savedata, when present ]]	
	
	-- Delay timer setting
	if type(BuffFilter.tSavedData.nTimerDelay) == "number" then
		BuffFilter.tSettings.nTimerDelay = BuffFilter.tSavedData.nTimerDelay
	end
	
	-- Cooldown timer setting
	if type(BuffFilter.tSavedData.nTimerCooldown) == "number" then
		BuffFilter.tSettings.nTimerCooldown = BuffFilter.tSavedData.nTimerCooldown
	end
	
	-- Only hide in combat flag
	if type(BuffFilter.tSavedData.bOnlyHideInCombat) == "boolean" then
		BuffFilter.tSettings.bOnlyHideInCombat =  BuffFilter.tSavedData.bOnlyHideInCombat
	end	

	-- Enable sorting flag
	if type(BuffFilter.tSavedData.bEnableSorting) == "boolean" then
		BuffFilter.tSettings.bEnableSorting = BuffFilter.tSavedData.bEnableSorting
	end	
	
	-- Inverse buff/debuff filtering
	if type(BuffFilter.tSavedData.bInverseFiltering) == "table" then
		for _,eBuffType in pairs(eBuffTypes) do
			if type(BuffFilter.tSavedData.bInverseFiltering[eBuffType]) == "boolean" then
				BuffFilter.tSettings.bInverseFiltering[eBuffType] = BuffFilter.tSavedData.bInverseFiltering[eBuffType]
			end
		end
	end	
end

-- Restores saved buff-data for an individual buff.
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
	
	-- Focus is a new property, so it may be missing. Default-set it to the Target-hide value.
	if type(b.bHide[eTargetTypes.Focus]) ~= "boolean" then 
		b.bHide[eTargetTypes.Focus] = b.bHide[eTargetTypes.Target]
	end	
	-- TargetOfTarget is a new property, so it may be missing. Default-set it to the Target-hide value.
	if type(b.bHide[eTargetTypes.TargetOfTarget]) ~= "boolean" then 
		b.bHide[eTargetTypes.TargetOfTarget] = b.bHide[eTargetTypes.Target]
	end	
	
	-- All good, now register buff
	BuffFilter:RegisterBuff(
		b.nBaseSpellId,
		b.strName,		
		b.strTooltip,
		b.strIcon,		
		b.bIsBeneficial,
		{	
			[eTargetTypes.Player] = b.bHide[eTargetTypes.Player],
			[eTargetTypes.Target] = b.bHide[eTargetTypes.Target],
			[eTargetTypes.Focus] = b.bHide[eTargetTypes.Focus],
			[eTargetTypes.TargetOfTarget] = b.bHide[eTargetTypes.TargetOfTarget]
		},
		b.nPriority or ePriority.Unset -- Sort-priority may be missing, default to Unset
	)
end


--[[ SETTINGS GUI ]]

function BuffFilter:OnConfigure()
	-- Sort buffs before showing settings, but only if not already sorted (allow preservation of other sorting)
	if self.wndSettings:FindChild("Grid"):GetSortColumn() == nil then
		self.wndSettings:FindChild("Grid"):SetSortColumn(3, true)
	end
	
	-- Show settings window
	self.wndSettings:Show(true, false)
	
	-- Show incompatible addon warning window?
	self:CheckAddons()

	-- Show error window?
	if self.errorMessages ~= nil and #self.errorMessages > 0 then
		local msg = "Errors have occurred. Please report this incident to me on Curse. \n \n"
		for i,e in ipairs(self.errorMessages) do
			msg = msg .. string.format("Error #%d: %s \n \n", i, e)
		end
		self.wndSettings:FindChild("ErrorMessage"):SetText(msg)
		
		-- Clear, so that errors are only shown once? 
		-- Nah, ppl might click it away and then not be able to report the error in detail.
		--self.errorMessages = {}
		
		self.wndSettings:FindChild("ErrorFrame"):Show(true, true)
	end
end

function BuffFilter:OnHideSettings()
	self.wndSettings:Show(false, true)
end

function BuffFilter:OnGridSelChange(wndControl, wndHandler, nRow, nColumn)
	local grid = self.wndSettings:FindChild("Grid")	
	local tBuffDetails = grid:GetCellData(nRow, 1)
	local strTooltip = tBuffDetails.strTooltip

	-- Determine which column was clicked
	local eTargetType = self.tColumnToTarget[nColumn]
	if eTargetType ~= nil then -- Individual target-type column clicked
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
	elseif nColumn == 3 then
		--log:info("Toggling buff '%s' for all target types", tBuffDetails.strName)
		-- Clicking name inverses all column selections
		-- Do this the easy way - by simulating user input on each column
		for t,c in pairs(self.tTargetToColumn) do
			BuffFilter:OnGridSelChange(wndControl, wndHandler, nRow, c)
		end
	elseif nColumn == 8 then
		local nPriority = tBuffDetails.nPriority
		
		-- Sort toggle order: Unset -> High -> Low -> Unset
		if nPriority == nil or nPriority == ePriority.Unset then -- Unset -> High
			nPriority = ePriority.High
		elseif nPriority == ePriority.High then -- High -> Low
			nPriority = ePriority.Low
		else -- Low -> Unset
			nPriority = nil
		end
		
		-- When a buff has priority changed, update *all* buffs with same tooltip, not just the checked one
		for r = 1, grid:GetRowCount() do -- for every row on the grid
			-- Get buff for this row
			local tRowBuffDetails = grid:GetCellData(r, 1)
				
			-- Check if this buff has same tooltip
			if tRowBuffDetails.strTooltip == strTooltip then
				--log:info("Setting priority for buff '%s' to %s", tRowBuffDetails.strName, tostring(nPriority))
				tRowBuffDetails.nPriority = nPriority				
				BuffFilter:SetGridRowPriority(r, nPriority)
			end
		end
		
		-- Also add priority to the "buff status by tooltip" table
		BuffFilter.tBuffStatusByTooltip[strTooltip].nPriority = nPriority
	end
	
	-- Force update
	BuffFilter:Filter()
end

function BuffFilter:OnDelayTimerIntervalChange(wndHandler, wndControl, fNewValue, fOldValue)
	self.tSettings.nTimerDelay = fNewValue
	self.wndSettings:FindChild("DelaySliderLabel"):SetText(string.format("Event filter-delay (%.2fs):", self.tSettings.nTimerDelay/1000))
end

function BuffFilter:OnCooldownTimerIntervalChange(wndHandler, wndControl, fNewValue, fOldValue)
	self.tSettings.nTimerCooldown = fNewValue
	self.wndSettings:FindChild("CooldownSliderLabel"):SetText(string.format("Filtering cooldown (%.2fs):", self.tSettings.nTimerCooldown/1000))
end

function BuffFilter:SetGridRowStatus(nRow, eTargetType, bHide)
	local grid = self.wndSettings:FindChild("Grid")	

	-- Determine column from target type.
	local nColumn = self.tTargetToColumn[eTargetType]
	
	grid:SetCellImage(nRow, nColumn, bHide and "IconSprites:Icon_Windows_UI_CRB_Marker_Ghost" or "")
	grid:SetCellSortText(nRow, nColumn, bHide and "1" or "0")
end

function BuffFilter:SetGridRowPriority(nRow, nPriority)
	local grid = self.wndSettings:FindChild("Grid")	
	if nPriority == nil or nPriority == ePriority.Unset then
		grid:SetCellImage(nRow, 8, "")					
	else				
		grid:SetCellImage(nRow, 8, nPriority == ePriority.High and "CRB_Basekit:kitIcon_Holo_UpArrow" or "CRB_Basekit:kitIcon_Holo_DownArrow")
	end
	grid:SetCellSortText(nRow, 8, nPriority or ePriority.Unset)
end

function BuffFilter:OnTabBtn(wndHandler, wndControl)	
	local strFormName = self.tTabButtonToForm[wndControl:GetName()]
	--log:info("Showing Settings-tab '%s'", strFormName)
	
	for _,child in pairs(self.wndSettings:FindChild("TabContentArea"):GetChildren()) do
		child:Show(strFormName == child:GetName())
	end	
end


function BuffFilter:InCombatBtnChange(wndHandler, wndControl, eMouseButton)
	--log:info("In-combat only " .. (wndControl:IsChecked() and "checked" or "unchecked"))
	self.tSettings.bOnlyHideInCombat = wndControl:IsChecked()
	BuffFilter:Filter()
end

function BuffFilter:EnableSortingBtnChange(wndHandler, wndControl, eMouseButton)
	--log:info("Buff sorting " .. (wndControl:IsChecked() and "checked" or "unchecked"))
	self.tSettings.bEnableSorting = wndControl:IsChecked()
	BuffFilter:Filter()
end

function BuffFilter:InverseBuffsBtnChange(wndHandler, wndControl, eMouseButton)
	--log:info("Inverse buff filtering " .. (wndControl:IsChecked() and "checked" or "unchecked"))	
	self.tSettings.bInverseFiltering[eBuffTypes.Buff] = wndControl:IsChecked()
	BuffFilter:Filter()
end

function BuffFilter:InverseDebuffsBtnChange( wndHandler, wndControl, eMouseButton )
	--log:info("Inverse debuff filtering " .. (wndControl:IsChecked() and "checked" or "unchecked"))	
	self.tSettings.bInverseFiltering[eBuffTypes.Debuff] = wndControl:IsChecked()
	BuffFilter:Filter()
end

function BuffFilter:OnUnitEnteredCombat(unit, bCombat)	
	-- When player enters or exits combat, schedule regular update
	if unit:IsThePlayer() then 
		BuffFilter:ScheduleFilter()
	end
end

-- Changing world or /reloadui, trigger an extraordinary pass in 5 secs
function BuffFilter:OnChangeWorld()
	-- World change, schedule a few bonus-updates to ensure fresh buff state is updated (hard to tell when UI is fully loaded)
	self:StartInitialTimer()
end

-- When first loaded, changed instance or /reloadui, some startup timers are required
function BuffFilter:StartInitialTimer(nInitialTimerCount, nInitialTimerDelay) 
	-- Default is 3 second intervals, 10 times = 30 seconds
	self:ScheduleFilter()
	self.nInitialTimersLeft = nInitialTimerCount or 10
	self.timerInitial = ApolloTimer.Create(nInitialTimerDelay or 3, true, "OnInitialTimer", BuffFilter)
end

function BuffFilter:OnInitialTimer()
	-- On initial timer pules, just schedule a regular filtering
	self.nInitialTimersLeft = self.nInitialTimersLeft - 1
	self:ScheduleFilter()	

	-- On final pulse, scrub the list of known/registered addons so we dont keep scanning for stuff that isn't installed
	if self.nInitialTimersLeft <= 0 then
		self:ScrubAddonList()
		
		--[[	In some borked loading scenarios (long loading-screen time), 
			the timerInitial will have been stopped/nilled, but OnTimerInitial is still fired. 
			Don't try to stop the timer if it no longer exists. --]]
		if self.timerInitial ~= nil then
			self.timerInitial:Stop()
			self.timerInitial = nil
		end
	end
end

function BuffFilter:ScrubAddonList()
	-- Scrub list of Active Bar Providers, so that it only contains addons that actually exist
	self.tActiveBarProviders = {}
	for strProvider,provider in pairs(self.tSupportedBarProviders) do		
		if Apollo.GetAddon(strProvider) ~= nil then 
			self.tActiveBarProviders[strProvider] = provider
		end
	end
end

function BuffFilter:OnGenerateGridTooltip( wndHandler, wndControl, eToolTipType, x, y )
	local grid = self.wndSettings:FindChild("Grid")

	local tBuffDetails = grid:GetCellData(x+1,1)
	if tBuffDetails ~= nil then		
		local wndTooltip = grid:LoadTooltipForm("BuffFilter.xml", "TooltipForm")
		wndTooltip:FindChild("BuffIcon"):SetSprite(tBuffDetails.strIcon)		
		wndTooltip:FindChild("BuffName"):SetText(tBuffDetails.strName)
		
		local wndDesc = wndTooltip:FindChild("BuffDescription")
		local nMinimumHeight = wndTooltip:GetHeight() -- Original tooltip height

		-- Set description and recalc height
		wndDesc:SetText(tBuffDetails.strTooltip)
		wndDesc:SetHeightToContentHeight()
		
		local nHeight = math.max(wndDesc:GetHeight() + 40, nMinimumHeight) -- 40 for fixed name+padding height
		wndTooltip:SetAnchorOffsets(0, 0, wndTooltip:GetWidth(), nHeight)
	end
end

-- Checks if any supported addon is found, displays warning message overlay in settings if not
function BuffFilter:CheckAddons()
	-- For each supported addon, check if the Player/Buff bar can be found
	local tSupportedAddons = {}
	local bCheckPassed = false
	for strProvider,provider in pairs(self.tSupportedBarProviders) do		
		if Apollo.GetAddon(strProvider) == nil then 
			BuffFilter:CheckAddon_AddLine(tSupportedAddons, strProvider, "Not installed")
		else		
			-- Supported addon installed, check Player Buff bar can be found
			local bStatus, discoveryResult = pcall(
				provider.fDiscoverBar,
				Apollo.GetAddon(strProvider),
				provider.tTargetType[eTargetTypes.Player],
				provider.tBuffType[eBuffTypes.Buff])

			if bStatus == true and discoveryResult ~= nil then
				BuffFilter:CheckAddon_AddLine(tSupportedAddons, strProvider, "OK") -- kinda pointless, wont be shown anyway
				bCheckPassed = true
			else
				BuffFilter:CheckAddon_AddLine(tSupportedAddons, strProvider, "Unsupported version")
			end
		end
	end
	
	-- Convert list of supported addon (with status) to return-delimited list	
	local strSupportedAddons = table.concat(tSupportedAddons, "\n")
		
	-- Show warning message
	self.wndSettings:FindChild("GeneralDescription"):SetText("BuffFilter only works with the stock Unit Frames, or a specific list of replacement / additional Unit Frame addons.\n\nWithout one of the following addons installed, BuffFilter will simply not hide any buffs.")
	self.wndSettings:FindChild("SupportedAddonList"):SetText(strSupportedAddons)	
	self.wndSettings:FindChild("WarningFrame"):Show(not bCheckPassed, false)
end

function BuffFilter:CheckAddon_AddLine(tSupportedAddons, strAddon, strStatus)
	local textColor = strStatus == "OK" and "xkcdBoringGreen" or "AddonError"
	tSupportedAddons[#tSupportedAddons+1] = string.format("<P TextColor=\"%s\" Font=\"CRB_InterfaceLarge\" Align=\"Center\">%s (%s)</P>",
		textColor, strAddon, strStatus)	
end

function BuffFilter:CloseWarningButton()
	self.wndSettings:FindChild("WarningFrame"):Show(false, true)
end

function BuffFilter:OnResetButton(wndHandler, wndControl, eMouseButton)
	self.tBuffsById = {}
	self.tBuffStatusByTooltip = {}
	self:SetDefaultValues()
	self.wndSettings:FindChild("Grid"):DeleteAll()
	self:UpdateSettingsGUI()
end

-- Schedule an update whenever a buff is added to the player, target, focus or tot unit
function BuffFilter:OnBuffAdded(unit, tBuff)
	if unit ~= nil then
		local playerUnit = GameLib.GetPlayerUnit()
		if unit == playerUnit then
			-- Player unit buff update
			return self:ScheduleFilter()			
		else			
			local targetUnit = playerUnit:GetTarget()			
			if targetUnit ~= nil then
				if unit == targetUnit then
					-- Target unit buff update
					return self:ScheduleFilter()
				end
								
				local totUnit = targetUnit:GetTarget()
				if totUnit ~= nil and unit == totUnit then
					-- Target of target unit buff update
					return self:ScheduleFilter()
				end
			end
						
			local focusUnit = playerUnit:GetAlternateTarget()
			if focusUnit ~= nil and unit == focusUnit then
				-- Focus unit buff update
				return self:ScheduleFilter()
			end
		end
	end	
end

BuffFilter:Init()
