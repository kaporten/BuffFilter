local BuffFilter = Apollo.GetAddon("BuffFilter")

--[[
	Configuration file for built-in supported addons. 
	
	You can add support for new unitframe addons here, just add a structure to the 
	list produced by GetSupportedAddons(). Table key must match actual addon name.
	
	Adding additional (unused) addons here does not impact BuffFilter performance:
	Once the game is fully loaded, any addon which is not currently installed will
	be removed from the list of addons to actively filter.
	
	The fDiscoverBar function must be implemented so that it returns a reference to your addons
	BeneBuffBar and HarmBuffBar for each possible combination of tTargetType/tBuffType
	(strTargetType/strBuffType input to fDiscoverBar).
	
	The fFilterBar function is responsible for actually filtering buffs on the buff/debuff bar
	identified by fDiscoverBar. If you use the stock "BuffContainerWindow" controls, just use
	fFilterBar = BuffFilter.FilterStockBar.
--]]

-- Registers all built-in supported addons
function BuffFilter:RegisterSupportedAddons()
	for strAddonName,tAddonDetails in pairs(BuffFilter:GetSupportedAddons()) do
		BuffFilter:RegisterSupportedAddon(strAddonName, tAddonDetails)
	end
end

-- Gets table of built-in supported addons
function BuffFilter:GetSupportedAddons()
	local eTargetTypes = BuffFilter.eTargetTypes
	local eBuffTypes = BuffFilter.eBuffTypes

	return {
		-- Stock UI
		["TargetFrame"] = {
			tTargetType = {
				[eTargetTypes.Player] = "luaUnitFrame",
				[eTargetTypes.Target] = "luaTargetFrame",
				[eTargetTypes.Focus] = "luaFocusFrame"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BeneBuffBar",
				[eBuffTypes.Debuff] = "HarmBuffBar"
			},
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType].wndMainClusterFrame:FindChild(strBuffType)
				end,
		},
		
		-- Potato UI 2.8+
		["PotatoBuffs"] = {
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
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType .. strBuffType].wndBuffs:FindChild("Buffs")
				end,
		},		
		
		["SimpleBuffBar"] = {
			tTargetType = {
				[eTargetTypes.Player] = "Player",
				[eTargetTypes.Target] = "Target",
				[eTargetTypes.Focus] = "Focus"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BuffBar",
				[eBuffTypes.Debuff] = "DebuffBar"
			},
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon.bars[strTargetType .. strBuffType]
				end,
		},
		
		["VikingUnitFrames"] = {
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
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType].wndUnitFrame:FindChild(strBuffType)
				end,
		},
		
		["FastTargetFrame"] = {
			tTargetType = {
				[eTargetTypes.Player] = "luaUnitFrame",
				[eTargetTypes.Target] = "luaTargetFrame",
				[eTargetTypes.Focus] = "luaFocusFrame"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BeneBuffBar",
				[eBuffTypes.Debuff] = "HarmBuffBar"
			},
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType].wndMainClusterFrame:FindChild(strBuffType)
				end,
		},

		["KuronaFrames"] = {
			tTargetType = {
				[eTargetTypes.Player] = "playerFrame",
				[eTargetTypes.Target] = "targetFrame",
				[eTargetTypes.Focus] = "focusFrame"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BeneBuffBar",
				[eBuffTypes.Debuff] = "HarmBuffBar"
			},
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType]:FindChild(strBuffType)
				end,
		},
		
		["AlterFrame"] = {
			tTargetType = {
				[eTargetTypes.Player] = "wndMain",
				[eTargetTypes.Target] = "wndTarget",
				[eTargetTypes.Focus] = "wndFocus"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "BeneBuffBar",
				[eBuffTypes.Debuff] = "HarmBuffBar"
			},
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType]:FindChild(strBuffType)
				end,
		},
		
		["CandyUI_UnitFrames"] = {
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
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType]:FindChild(strBuffType)
				end,
		},
		
		["ForgeUI_UnitFrames"] = {
			tTargetType = {
				[eTargetTypes.Player] = "wndPlayer",
				[eTargetTypes.Target] = "wndTarget",
				[eTargetTypes.Focus] = "wndFocus",
				[eTargetTypes.TargetOfTarget] = "wndToT"
			},
			tBuffType = {
				[eBuffTypes.Buff] = "Buffs",
				[eBuffTypes.Debuff] = "Debuffs"
			},
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType .. strBuffType]
				end,
		},		
	}
end