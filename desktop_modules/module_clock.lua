-- module_clock.lua — Simple UI
-- Clock module: clock always visible, with optional date and battery toggles.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local datetime        = require("datetime")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Screen          = Device.screen
local _               = require("gettext")

local UI           = require("ui")
local PAD          = UI.PAD
local PAD2         = UI.PAD2
local CLR_TEXT_SUB = UI.CLR_TEXT_SUB

-- ---------------------------------------------------------------------------
-- Pixel constants — computed once at load time.
-- ---------------------------------------------------------------------------

local CLOCK_W       = Screen:scaleBySize(50)  -- CenterContainer height for clock text
local CLOCK_FS      = Screen:scaleBySize(44)
local DATE_H        = Screen:scaleBySize(17)
local DATE_GAP      = Screen:scaleBySize(19)
local DATE_FS       = Screen:scaleBySize(11)
local BATT_FS       = Screen:scaleBySize(10)
local BATT_H        = Screen:scaleBySize(15)
local BATT_GAP      = Screen:scaleBySize(6)
local BOT_PAD_EXTRA = Screen:scaleBySize(4)

-- Font faces cached at load time.
local _FACE_CLOCK = Font:getFace("smallinfofont", CLOCK_FS)
local _FACE_DATE  = Font:getFace("smallinfofont", DATE_FS)
local _FACE_BATT  = Font:getFace("smallinfofont", BATT_FS)

-- Battery is always rendered in the same subdued colour as other auxiliary
-- text (date, authors, etc.) — no colour-coded feedback needed here.

-- Precomputed heights for the 4 toggle combinations.
local _H_BASE      = CLOCK_W + PAD * 2 + PAD2
local _H_DATE      = _H_BASE + DATE_GAP + DATE_H
local _H_BATT      = _H_BASE + BATT_GAP + BATT_H
local _H_DATE_BATT = _H_DATE + BATT_GAP + BATT_H

-- Cached Geom instances — mutated in build() to avoid per-render allocation.
local _dimen_clock = Geom:new{ w = 0, h = CLOCK_W }
local _dimen_date  = Geom:new{ w = 0, h = DATE_H  }
local _dimen_batt  = Geom:new{ w = 0, h = BATT_H  }

-- ---------------------------------------------------------------------------
-- Settings keys
-- ---------------------------------------------------------------------------

local SETTING_ON      = "clock_enabled"   -- pfx .. "clock_enabled"
local SETTING_DATE    = "clock_date"      -- pfx .. "clock_date"    (default ON)
local SETTING_BATTERY = "clock_battery"   -- pfx .. "clock_battery" (default ON)

local function isDateEnabled(pfx)
    local v = G_reader_settings:readSetting(pfx .. SETTING_DATE)
    return v ~= false   -- default ON
end

local function isBattEnabled(pfx)
    local v = G_reader_settings:readSetting(pfx .. SETTING_BATTERY)
    return v ~= false   -- default ON
end

-- ---------------------------------------------------------------------------
-- Battery helpers
-- ---------------------------------------------------------------------------

-- Returns battery level clamped to [0,100] and charging flag.
local function _battInfo()
    local pwr = Device:getPowerDevice()
    if not pwr then return nil, false end
    local lvl, charging = nil, false
    if pwr.getCapacity then
        local ok, v = pcall(pwr.getCapacity, pwr)
        if ok and type(v) == "number" then
            lvl = v < 0 and 0 or v > 100 and 100 or v
        end
    end
    if pwr.isCharging then
        local ok, v = pcall(pwr.isCharging, pwr); if ok then charging = v end
    end
    return lvl, charging
end

-- lvl is always a number in [0,100] or nil (normalised by _battInfo).
-- Battery always uses CLR_TEXT_SUB — same subdued grey as date and author text.

-- Builds the battery display string.
-- Uses ▰/▱ (filled/empty blocks) matching module_header.lua visual style.
-- Charging replaces the first block with ⚡.
local function _battText(lvl, charging)
    if type(lvl) ~= "number" then return "N/A" end
    local bars
    if     lvl >= 90 then bars = "▰▰▰▰"
    elseif lvl >= 60 then bars = "▰▰▰▱"
    elseif lvl >= 40 then bars = "▰▰▱▱"
    elseif lvl >= 20 then bars = "▰▱▱▱"
    else                  bars = "▱▱▱▱" end
    local icon = charging and ("⚡" .. bars:sub(4)) or bars
    return string.format("%s %d%%", icon, lvl)
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function _vspan(px, pool)
    if pool then
        if not pool[px] then pool[px] = VerticalSpan:new{ width = px } end
        return pool[px]
    end
    return VerticalSpan:new{ width = px }
end

local function build(w, pfx, vspan_pool)
    local inner_w   = w - PAD * 2
    local show_date = isDateEnabled(pfx)
    local show_batt = isBattEnabled(pfx)

    _dimen_clock.w = inner_w
    _dimen_date.w  = inner_w
    _dimen_batt.w  = inner_w

    local vg = VerticalGroup:new{ align = "center" }

    -- Clock — always shown.
    vg[#vg+1] = CenterContainer:new{
        dimen = _dimen_clock,
        TextWidget:new{
            text = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")),
            face = _FACE_CLOCK,
            bold = true,
        },
    }

    if show_date then
        vg[#vg+1] = _vspan(DATE_GAP, vspan_pool)
        vg[#vg+1] = CenterContainer:new{
            dimen = _dimen_date,
            TextWidget:new{
                text    = os.date("%A, %d %B"),
                face    = _FACE_DATE,
                fgcolor = CLR_TEXT_SUB,
            },
        }
    end

    if show_batt then
        vg[#vg+1] = _vspan(BATT_GAP, vspan_pool)
        local lvl, charging = _battInfo()
        vg[#vg+1] = CenterContainer:new{
            dimen = _dimen_batt,
            TextWidget:new{
                text    = _battText(lvl, charging),
                face    = _FACE_BATT,
                fgcolor = CLR_TEXT_SUB,
            },
        }
    end

    return FrameContainer:new{
        bordersize     = 0,
        padding        = PAD,
        padding_bottom = PAD2 + BOT_PAD_EXTRA,
        vg,
    }
end

-- ---------------------------------------------------------------------------
-- Module API
-- ---------------------------------------------------------------------------

local M = {}

M.id         = "clock"
M.name       = _("Clock")
M.label      = nil
M.default_on = true

function M.isEnabled(pfx)
    local v = G_reader_settings:readSetting(pfx .. SETTING_ON)
    if v ~= nil then return v == true end
    return true
end

function M.setEnabled(pfx, on)
    G_reader_settings:saveSetting(pfx .. SETTING_ON, on)
end

M.getCountLabel = nil

function M.build(w, ctx)
    return build(w, ctx.pfx, ctx.vspan_pool)
end

function M.getHeight(ctx)
    local pfx       = ctx.pfx
    local show_date = isDateEnabled(pfx)
    local show_batt = isBattEnabled(pfx)
    if show_date and show_batt then return _H_DATE_BATT end
    if show_date               then return _H_DATE      end
    if show_batt               then return _H_BATT      end
    return _H_BASE
end

function M.getMenuItems(ctx_menu)
    local pfx     = ctx_menu.pfx
    local refresh = ctx_menu.refresh
    local _lc     = ctx_menu._

    local function toggle(key, current)
        G_reader_settings:saveSetting(pfx .. key, not current)
        refresh()
    end

    return {
        {
            text_func    = function()
                return _lc("Show Date") .. " — " .. (isDateEnabled(pfx) and _lc("On") or _lc("Off"))
            end,
            checked_func   = function() return isDateEnabled(pfx) end,
            keep_menu_open = true,
            callback       = function() toggle(SETTING_DATE, isDateEnabled(pfx)) end,
        },
        {
            text_func    = function()
                return _lc("Show Battery") .. " — " .. (isBattEnabled(pfx) and _lc("On") or _lc("Off"))
            end,
            checked_func   = function() return isBattEnabled(pfx) end,
            keep_menu_open = true,
            callback       = function() toggle(SETTING_BATTERY, isBattEnabled(pfx)) end,
        },
    }
end

return M