local BuffFilter = Apollo.GetAddon("BuffFilter")

--[[
	Configuration file for supported addons. 
	
	You can add support for new unitframe addons here, just add a structure to the list below.
	Table key must match actual addon name.
	
	Adding additional (unused) addons here does not impact BuffFilter performance:
	Once the game is fully loaded, any addon which is not currently installed will
	be removed from the list of addons to actively filter.
--]]
function BuffFilter:GetSupportedAddons()
	local eTargetTypes = BuffFilter.eTargetTypes
	local eBuffTypes = BuffFilter.eBuffTypes

	return {
		-- Stock UI
		["TargetFrame"] = {
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType].wndMainClusterFrame:FindChild(strBuffType)
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
		
		-- Potato UI 2.8+
		["PotatoBuffs"] = {
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType .. strBuffType].wndBuffs:FindChild("Buffs")
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
		
		["SimpleBuffBar"] = {
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon.bars[strTargetType .. strBuffType]
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
		
		["VikingUnitFrames"] = {
			fDiscoverBar =
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType].wndUnitFrame:FindChild(strBuffType)
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
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType].wndMainClusterFrame:FindChild(strBuffType)
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
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType]:FindChild(strBuffType)
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
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType]:FindChild(strBuffType)
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
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType]:FindChild(strBuffType)
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
				function(addon, strTargetType, strBuffType)
					return addon[strTargetType .. strBuffType]
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
end