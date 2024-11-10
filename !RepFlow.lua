require 'lib.moonloader'
local imgui = require 'mimgui'
local sampev = require 'lib.samp.events'
local vkeys = require 'vkeys'
local encoding = require 'encoding'
local inicfg = require 'inicfg'
local ffi = require 'ffi'
local IniFilename = 'AutoReportCFG.ini'
local new = imgui.new
local faicons = require('fAwesome6')
local scriptver = "3.1 | Lite"

local changelogEntries = {
    { version = "2.6", description = "- Добавлено окно информации.\n- Исправлен баг с массовым спамом при сворачивании игры.\n- Исправлен баг с крашем игры при окне информации.\n- Добавлена новая вкладка 'ChangeLog'\n- Убрана вся лишняя информация с основного меню." },
    { version = "2.7", description = "- Изменен цвет сообщений скрипта.\n- Убран лишний спам при сворачивании игры.\n- Исправлен баг в информации версии 2.6.\n- Добавлена новая информация в окно информации\n- Изменена логика сворачивания игры." },
    { version = "2.8", description = "- Добавлен новый цвет меню.\n- Переименована вкладка 'Главная'.\nтеперь она называется флудер.\n- Добавлена функция отключить не флуди(сейчас нету репорта).\n- Мелкие исправления." },
    { version = "3.0", description = "- Ползунки теперь настраиваются!!.\n- Изменен код меню флудера и настроек.\n- Исправлено перемещение окна информации.\n- Заменена клавиша прикрепления окна на пробел.\n- Версия 2.9 и 3.0 объединены описанием" },
    { version = "3.1 | Lite", description = "- Новая тема - 'Светлая'.\n- Полностью переписана логика чата.\n- Было добавлено немного информации во вкладки.\n- Добавлены иконки в меню (fontAwesome6).\n- Добавлены новые индикаторы сообщений\n 'Информация' и 'RepFlow'.\n- Переписан код некоторых функций.\n- Разделение скрипта на Lite и Premium версию.\n- Улучшена оптимизация скрипта.\n- Мелкие исправления. " },
}

local keyBind = 0x5A -- клавиша активации: Z (по умолчанию)
local keyBindName = 'Z' -- Название клавиши активации

local lastDialogId = nil
local reportActive = false

local lastOtTime = 0 -- Время последней отправки /ot в секундах
local active = false
local otInterval = new.int(10) -- Интервал для автоматической отправки /ot
local dialogTimeout = new.int(600)
local otIntervalBuffer = imgui.new.char[5](tostring(otInterval[0])) -- Буфер на 5 символов (значения до 9999)
local useMilliseconds = new.bool(false) -- Флаг для использования миллисекунд
local infoWindowVisible = false -- Флаг для отображения окна информации
local reportAnsweredCount = 0 -- Счетчик для диалога 1334
local cursorVisible = false -- Для отслеживания видимости курсора

local main_window_state = new.bool(false)
local info_window_state = new.bool(false)
local active_tab = new.int(0)
local sw, sh = getScreenResolution()
local tag = "{1E90FF} [RepFlow]: {FFFFFF}"
local taginf = "{1E90FF} [Информация]: {FFFFFF}"

local startTime = 0 -- Время старта автоловли
local gameMinimized = false  -- Флаг для отслеживания сворачивания игры
local wasActiveBeforePause = false
local afkExitTime = 0  -- Время выхода из AFK
local afkCooldown = 30  -- Задержка в секундах перед началом ловли после выхода из AFK

local disableAutoStartOnToggle = false -- Флаг для отключения автостарта при ручном отключении ловли

local changingKey = false -- Флаг для отслеживания смены главной клавиши

encoding.default = 'CP1251'
u8 = encoding.UTF8

local dialogHandlerEnabled = true
local autoStartEnabled = true
local hideFloodMsg = new.bool(true)

--------- Актив и все, что с ним связано
local lastDialogTime = os.clock()
local dialogTimeoutBuffer = imgui.new.char[5](tostring(dialogTimeout[0])) -- Буфер на 5 символов (значения до 9999)
local manualDisable = false
local autoStartEnabled = new.bool(true)
local dialogHandlerEnabled = new.bool(true)
----------------------------------------

local colorList = {u8'Красная', u8'Зелёная', u8'Синяя', u8'Оранжевая', u8'Серая', u8'Светлая'}
local colorListNumber = new.int(0)
local colorListBuffer = new['const char*'][#colorList](colorList)

-- Загрузка конфигурации
local ini = inicfg.load({
    main = {
        keyBind = string.format("0x%X", keyBind),
        keyBindName = keyBindName,
        otInterval = 10,
        useMilliseconds = false,
        themes = 1,
		dialogTimeout = 600,
		dialogHandlerEnabled = true,
        autoStartEnabled = true,
        otklflud = false,
    },
    widget = {
        posX = 400,
        posY = 400
    }
}, IniFilename)
local MoveWidget = false

-- Применение загруженной конфигурации
keyBind = tonumber(ini.main.keyBind)
keyBindName = ini.main.keyBindName
otInterval[0] = tonumber(ini.main.otInterval)
useMilliseconds[0] = ini.main.useMilliseconds
colorListNumber[0] = tonumber(ini.main.themes)
dialogTimeout[0] = tonumber(ini.main.dialogTimeout)
dialogHandlerEnabled[0] = ini.main.dialogHandlerEnabled
autoStartEnabled[0] = ini.main.autoStartEnabled or false
hideFloodMsg[0] = ini.main.otklflud

local themes = {
    {
        change = function()
			local ImVec4 = imgui.ImVec4
			imgui.SwitchContext()
			local style = imgui.GetStyle()
			style.Colors[imgui.Col.Text]                   = imgui.ImVec4(0.90, 0.85, 0.85, 1.00)
			style.Colors[imgui.Col.TextDisabled]           = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
			style.Colors[imgui.Col.WindowBg]               = imgui.ImVec4(0.15, 0.03, 0.03, 1.00)
			style.Colors[imgui.Col.ChildBg]                = imgui.ImVec4(0.18, 0.05, 0.05, 0.30)
			style.Colors[imgui.Col.PopupBg]                = imgui.ImVec4(0.15, 0.03, 0.03, 1.00)
			style.Colors[imgui.Col.Border]                 = imgui.ImVec4(0.50, 0.10, 0.10, 1.00)
			style.Colors[imgui.Col.BorderShadow]           = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
			style.Colors[imgui.Col.FrameBg]                = imgui.ImVec4(0.25, 0.07, 0.07, 1.00)
			style.Colors[imgui.Col.FrameBgHovered]         = imgui.ImVec4(0.25, 0.08, 0.08, 1.00)
			style.Colors[imgui.Col.FrameBgActive]          = imgui.ImVec4(0.30, 0.10, 0.10, 1.00)
			style.Colors[imgui.Col.TitleBg]                = imgui.ImVec4(0.20, 0.05, 0.05, 1.00)
			style.Colors[imgui.Col.TitleBgCollapsed]       = imgui.ImVec4(0.15, 0.03, 0.03, 1.00)
			style.Colors[imgui.Col.TitleBgActive]          = imgui.ImVec4(0.25, 0.07, 0.07, 1.00)
			style.Colors[imgui.Col.MenuBarBg]              = imgui.ImVec4(0.20, 0.05, 0.05, 1.00)
			style.Colors[imgui.Col.ScrollbarBg]            = imgui.ImVec4(0.15, 0.03, 0.03, 1.00)
			style.Colors[imgui.Col.ScrollbarGrab]          = imgui.ImVec4(0.50, 0.10, 0.10, 1.00)
			style.Colors[imgui.Col.ScrollbarGrabHovered]   = imgui.ImVec4(0.60, 0.12, 0.12, 1.00)
			style.Colors[imgui.Col.ScrollbarGrabActive]    = imgui.ImVec4(0.70, 0.15, 0.15, 1.00)
			style.Colors[imgui.Col.CheckMark]              = imgui.ImVec4(0.90, 0.15, 0.15, 1.00)
			style.Colors[imgui.Col.SliderGrab]             = imgui.ImVec4(0.90, 0.25, 0.25, 1.00)
			style.Colors[imgui.Col.SliderGrabActive]       = imgui.ImVec4(0.90, 0.25, 0.25, 1.00)
			style.Colors[imgui.Col.Button]                 = imgui.ImVec4(0.25, 0.07, 0.07, 1.00)
			style.Colors[imgui.Col.ButtonHovered]          = imgui.ImVec4(0.80, 0.20, 0.20, 1.00)
			style.Colors[imgui.Col.ButtonActive]           = imgui.ImVec4(0.90, 0.25, 0.25, 1.00)
			style.Colors[imgui.Col.Header]                 = imgui.ImVec4(0.25, 0.07, 0.07, 1.00)
			style.Colors[imgui.Col.HeaderHovered]          = imgui.ImVec4(0.80, 0.20, 0.20, 1.00)
			style.Colors[imgui.Col.HeaderActive]           = imgui.ImVec4(0.90, 0.25, 0.25, 1.00)
			style.Colors[imgui.Col.Separator]              = imgui.ImVec4(0.50, 0.10, 0.10, 1.00)
			style.Colors[imgui.Col.SeparatorHovered]       = imgui.ImVec4(0.60, 0.12, 0.12, 1.00)
			style.Colors[imgui.Col.SeparatorActive]        = imgui.ImVec4(0.70, 0.15, 0.15, 1.00)
			style.Colors[imgui.Col.ResizeGrip]             = imgui.ImVec4(0.25, 0.07, 0.07, 1.00)
			style.Colors[imgui.Col.ResizeGripHovered]      = imgui.ImVec4(0.80, 0.20, 0.20, 1.00)
			style.Colors[imgui.Col.ResizeGripActive]       = imgui.ImVec4(0.90, 0.25, 0.25, 1.00)
			style.Colors[imgui.Col.PlotLines]              = imgui.ImVec4(0.80, 0.10, 0.10, 1.00)
			style.Colors[imgui.Col.PlotLinesHovered]       = imgui.ImVec4(0.90, 0.15, 0.15, 1.00)
			style.Colors[imgui.Col.PlotHistogram]          = imgui.ImVec4(0.80, 0.10, 0.10, 1.00)
			style.Colors[imgui.Col.PlotHistogramHovered]   = imgui.ImVec4(0.90, 0.15, 0.15, 1.00)
			style.Colors[imgui.Col.TextSelectedBg]         = imgui.ImVec4(0.90, 0.15, 0.15, 1.00)
			style.Colors[imgui.Col.ModalWindowDimBg]       = imgui.ImVec4(0.20, 0.05, 0.05, 0.80)
			style.Colors[imgui.Col.Tab]                    = imgui.ImVec4(0.25, 0.07, 0.07, 1.00)
			style.Colors[imgui.Col.TabHovered]             = imgui.ImVec4(0.80, 0.20, 0.20, 1.00)
			style.Colors[imgui.Col.TabActive]              = imgui.ImVec4(0.90, 0.25, 0.25, 1.00)
        end
    },
    {
        change = function()
			local ImVec4 = imgui.ImVec4
			imgui.SwitchContext()
			local style = imgui.GetStyle()
			style.Colors[imgui.Col.Text]                   = imgui.ImVec4(0.85, 0.93, 0.85, 1.00)
			style.Colors[imgui.Col.TextDisabled]           = imgui.ImVec4(0.55, 0.65, 0.55, 1.00)
			style.Colors[imgui.Col.WindowBg]               = imgui.ImVec4(0.13, 0.22, 0.13, 1.00)
			style.Colors[imgui.Col.ChildBg]                = imgui.ImVec4(0.17, 0.27, 0.17, 1.00)
			style.Colors[imgui.Col.PopupBg]                = imgui.ImVec4(0.15, 0.24, 0.15, 1.00)
			style.Colors[imgui.Col.Border]                 = imgui.ImVec4(0.25, 0.35, 0.25, 1.00)
			style.Colors[imgui.Col.BorderShadow]           = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
			style.Colors[imgui.Col.FrameBg]                = imgui.ImVec4(0.19, 0.29, 0.19, 1.00)
			style.Colors[imgui.Col.FrameBgHovered]         = imgui.ImVec4(0.23, 0.33, 0.23, 1.00)
			style.Colors[imgui.Col.FrameBgActive]          = imgui.ImVec4(0.25, 0.35, 0.25, 1.00)
			style.Colors[imgui.Col.TitleBg]                = imgui.ImVec4(0.15, 0.25, 0.15, 1.00)
			style.Colors[imgui.Col.TitleBgCollapsed]       = imgui.ImVec4(0.15, 0.25, 0.15, 1.00)
			style.Colors[imgui.Col.TitleBgActive]          = imgui.ImVec4(0.18, 0.28, 0.18, 1.00)
			style.Colors[imgui.Col.MenuBarBg]              = imgui.ImVec4(0.15, 0.25, 0.15, 1.00)
			style.Colors[imgui.Col.ScrollbarBg]            = imgui.ImVec4(0.15, 0.25, 0.15, 1.00)
			style.Colors[imgui.Col.ScrollbarGrab]          = imgui.ImVec4(0.25, 0.35, 0.25, 1.00)
			style.Colors[imgui.Col.ScrollbarGrabHovered]   = imgui.ImVec4(0.30, 0.40, 0.30, 1.00)
			style.Colors[imgui.Col.ScrollbarGrabActive]    = imgui.ImVec4(0.35, 0.45, 0.35, 1.00)
			style.Colors[imgui.Col.CheckMark]              = imgui.ImVec4(0.50, 0.70, 0.50, 1.00)
			style.Colors[imgui.Col.SliderGrab]             = imgui.ImVec4(0.50, 0.70, 0.50, 1.00)
			style.Colors[imgui.Col.SliderGrabActive]       = imgui.ImVec4(0.55, 0.75, 0.55, 1.00)
			style.Colors[imgui.Col.Button]                 = imgui.ImVec4(0.19, 0.29, 0.19, 1.00)
			style.Colors[imgui.Col.ButtonHovered]          = imgui.ImVec4(0.23, 0.33, 0.23, 1.00)
			style.Colors[imgui.Col.ButtonActive]           = imgui.ImVec4(0.25, 0.35, 0.25, 1.00)
			style.Colors[imgui.Col.Header]                 = imgui.ImVec4(0.23, 0.33, 0.23, 1.00)
			style.Colors[imgui.Col.HeaderHovered]          = imgui.ImVec4(0.28, 0.38, 0.28, 1.00)
			style.Colors[imgui.Col.HeaderActive]           = imgui.ImVec4(0.30, 0.40, 0.30, 1.00)
			style.Colors[imgui.Col.Separator]              = imgui.ImVec4(0.25, 0.35, 0.25, 1.00)
			style.Colors[imgui.Col.SeparatorHovered]       = imgui.ImVec4(0.30, 0.40, 0.30, 1.00)
			style.Colors[imgui.Col.SeparatorActive]        = imgui.ImVec4(0.35, 0.45, 0.35, 1.00)
			style.Colors[imgui.Col.ResizeGrip]             = imgui.ImVec4(0.19, 0.29, 0.19, 1.00)
			style.Colors[imgui.Col.ResizeGripHovered]      = imgui.ImVec4(0.23, 0.33, 0.23, 1.00)
			style.Colors[imgui.Col.ResizeGripActive]       = imgui.ImVec4(0.25, 0.35, 0.25, 1.00)
			style.Colors[imgui.Col.PlotLines]              = imgui.ImVec4(0.60, 0.70, 0.60, 1.00)
			style.Colors[imgui.Col.PlotLinesHovered]       = imgui.ImVec4(0.65, 0.75, 0.65, 1.00)
			style.Colors[imgui.Col.PlotHistogram]          = imgui.ImVec4(0.60, 0.70, 0.60, 1.00)
			style.Colors[imgui.Col.PlotHistogramHovered]   = imgui.ImVec4(0.65, 0.75, 0.65, 1.00)
			style.Colors[imgui.Col.TextSelectedBg]         = imgui.ImVec4(0.25, 0.35, 0.25, 1.00)
			style.Colors[imgui.Col.ModalWindowDimBg]       = imgui.ImVec4(0.15, 0.25, 0.15, 0.80)
			style.Colors[imgui.Col.Tab]                    = imgui.ImVec4(0.19, 0.29, 0.19, 1.00)
			style.Colors[imgui.Col.TabHovered]             = imgui.ImVec4(0.23, 0.33, 0.23, 1.00)
			style.Colors[imgui.Col.TabActive]              = imgui.ImVec4(0.25, 0.35, 0.25, 1.00)
        end
    },
    {
        change = function()
            local ImVec4 = imgui.ImVec4
			imgui.SwitchContext()
			local style = imgui.GetStyle()
			style.Colors[imgui.Col.Text]                   = imgui.ImVec4(0.90, 0.90, 0.93, 1.00)
			style.Colors[imgui.Col.TextDisabled]           = imgui.ImVec4(0.40, 0.40, 0.45, 1.00)
			style.Colors[imgui.Col.WindowBg]               = imgui.ImVec4(0.12, 0.12, 0.14, 1.00)
			style.Colors[imgui.Col.ChildBg]                = imgui.ImVec4(0.18, 0.20, 0.22, 0.30)
			style.Colors[imgui.Col.PopupBg]                = imgui.ImVec4(0.13, 0.13, 0.15, 1.00)
			style.Colors[imgui.Col.Border]                 = imgui.ImVec4(0.30, 0.30, 0.35, 1.00)
			style.Colors[imgui.Col.BorderShadow]           = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
			style.Colors[imgui.Col.FrameBg]                = imgui.ImVec4(0.18, 0.18, 0.20, 1.00)
			style.Colors[imgui.Col.FrameBgHovered]         = imgui.ImVec4(0.25, 0.25, 0.28, 1.00)
			style.Colors[imgui.Col.FrameBgActive]          = imgui.ImVec4(0.30, 0.30, 0.34, 1.00)
			style.Colors[imgui.Col.TitleBg]                = imgui.ImVec4(0.15, 0.15, 0.17, 1.00)
			style.Colors[imgui.Col.TitleBgCollapsed]       = imgui.ImVec4(0.10, 0.10, 0.12, 1.00)
			style.Colors[imgui.Col.TitleBgActive]          = imgui.ImVec4(0.15, 0.15, 0.17, 1.00)
			style.Colors[imgui.Col.MenuBarBg]              = imgui.ImVec4(0.12, 0.12, 0.14, 1.00)
			style.Colors[imgui.Col.ScrollbarBg]            = imgui.ImVec4(0.12, 0.12, 0.14, 1.00)
			style.Colors[imgui.Col.ScrollbarGrab]          = imgui.ImVec4(0.30, 0.30, 0.35, 1.00)
			style.Colors[imgui.Col.ScrollbarGrabHovered]   = imgui.ImVec4(0.40, 0.40, 0.45, 1.00)
			style.Colors[imgui.Col.ScrollbarGrabActive]    = imgui.ImVec4(0.50, 0.50, 0.55, 1.00)
			style.Colors[imgui.Col.CheckMark]              = imgui.ImVec4(0.70, 0.70, 0.90, 1.00)
			style.Colors[imgui.Col.SliderGrab]             = imgui.ImVec4(0.70, 0.70, 0.90, 1.00)
			style.Colors[imgui.Col.SliderGrabActive]       = imgui.ImVec4(0.80, 0.80, 0.90, 1.00)
			style.Colors[imgui.Col.Button]                 = imgui.ImVec4(0.18, 0.18, 0.20, 1.00)
			style.Colors[imgui.Col.ButtonHovered]          = imgui.ImVec4(0.60, 0.60, 0.90, 1.00)
			style.Colors[imgui.Col.ButtonActive]           = imgui.ImVec4(0.28, 0.56, 0.96, 1.00)
			style.Colors[imgui.Col.Header]                 = imgui.ImVec4(0.20, 0.20, 0.23, 1.00)
			style.Colors[imgui.Col.HeaderHovered]          = imgui.ImVec4(0.25, 0.25, 0.28, 1.00)
			style.Colors[imgui.Col.HeaderActive]           = imgui.ImVec4(0.30, 0.30, 0.34, 1.00)
			style.Colors[imgui.Col.Separator]              = imgui.ImVec4(0.40, 0.40, 0.45, 1.00)
			style.Colors[imgui.Col.SeparatorHovered]       = imgui.ImVec4(0.50, 0.50, 0.55, 1.00)
			style.Colors[imgui.Col.SeparatorActive]        = imgui.ImVec4(0.60, 0.60, 0.65, 1.00)
			style.Colors[imgui.Col.ResizeGrip]             = imgui.ImVec4(0.20, 0.20, 0.23, 1.00)
			style.Colors[imgui.Col.ResizeGripHovered]      = imgui.ImVec4(0.25, 0.25, 0.28, 1.00)
			style.Colors[imgui.Col.ResizeGripActive]       = imgui.ImVec4(0.30, 0.30, 0.34, 1.00)
			style.Colors[imgui.Col.PlotLines]              = imgui.ImVec4(0.61, 0.61, 0.64, 1.00)
			style.Colors[imgui.Col.PlotLinesHovered]       = imgui.ImVec4(0.70, 0.70, 0.75, 1.00)
			style.Colors[imgui.Col.PlotHistogram]          = imgui.ImVec4(0.61, 0.61, 0.64, 1.00)
			style.Colors[imgui.Col.PlotHistogramHovered]   = imgui.ImVec4(0.70, 0.70, 0.75, 1.00)
			style.Colors[imgui.Col.TextSelectedBg]         = imgui.ImVec4(0.30, 0.30, 0.34, 1.00)
			style.Colors[imgui.Col.ModalWindowDimBg]       = imgui.ImVec4(0.10, 0.10, 0.12, 0.80)
			style.Colors[imgui.Col.Tab]                    = imgui.ImVec4(0.18, 0.20, 0.22, 1.00)
			style.Colors[imgui.Col.TabHovered]             = imgui.ImVec4(0.60, 0.60, 0.90, 1.00)
			style.Colors[imgui.Col.TabActive]              = imgui.ImVec4(0.28, 0.56, 0.96, 1.00)
        end
    },
    {
        change = function()
			imgui.SwitchContext()
			local style = imgui.GetStyle()
			style.Colors[imgui.Col.Text]                   = imgui.ImVec4(1.00, 0.90, 0.85, 1.00)
			style.Colors[imgui.Col.TextDisabled]           = imgui.ImVec4(0.75, 0.60, 0.55, 1.00)
			style.Colors[imgui.Col.WindowBg]               = imgui.ImVec4(0.25, 0.15, 0.10, 1.00)
			style.Colors[imgui.Col.ChildBg]                = imgui.ImVec4(0.30, 0.20, 0.15, 0.30)
			style.Colors[imgui.Col.PopupBg]                = imgui.ImVec4(0.30, 0.20, 0.15, 1.00)
			style.Colors[imgui.Col.Border]                 = imgui.ImVec4(0.80, 0.35, 0.20, 1.00)
			style.Colors[imgui.Col.BorderShadow]           = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
			style.Colors[imgui.Col.FrameBg]                = imgui.ImVec4(0.30, 0.20, 0.15, 1.00)
			style.Colors[imgui.Col.FrameBgHovered]         = imgui.ImVec4(0.45, 0.25, 0.20, 1.00)
			style.Colors[imgui.Col.FrameBgActive]          = imgui.ImVec4(0.55, 0.35, 0.25, 1.00)
			style.Colors[imgui.Col.TitleBg]                = imgui.ImVec4(0.25, 0.15, 0.10, 1.00)
			style.Colors[imgui.Col.TitleBgCollapsed]       = imgui.ImVec4(0.20, 0.10, 0.05, 1.00)
			style.Colors[imgui.Col.TitleBgActive]          = imgui.ImVec4(0.30, 0.20, 0.15, 1.00)
			style.Colors[imgui.Col.MenuBarBg]              = imgui.ImVec4(0.25, 0.15, 0.10, 1.00)
			style.Colors[imgui.Col.ScrollbarBg]            = imgui.ImVec4(0.25, 0.15, 0.10, 1.00)
			style.Colors[imgui.Col.ScrollbarGrab]          = imgui.ImVec4(0.80, 0.35, 0.20, 1.00)
			style.Colors[imgui.Col.ScrollbarGrabHovered]   = imgui.ImVec4(0.90, 0.50, 0.35, 1.00)
			style.Colors[imgui.Col.ScrollbarGrabActive]    = imgui.ImVec4(1.00, 0.65, 0.50, 1.00)
			style.Colors[imgui.Col.CheckMark]              = imgui.ImVec4(1.00, 0.65, 0.50, 1.00)
			style.Colors[imgui.Col.SliderGrab]             = imgui.ImVec4(1.00, 0.65, 0.50, 1.00)
			style.Colors[imgui.Col.SliderGrabActive]       = imgui.ImVec4(1.00, 0.70, 0.55, 1.00)
			style.Colors[imgui.Col.Button]                 = imgui.ImVec4(0.30, 0.20, 0.15, 1.00)
			style.Colors[imgui.Col.ButtonHovered]          = imgui.ImVec4(0.90, 0.50, 0.35, 1.00)
			style.Colors[imgui.Col.ButtonActive]           = imgui.ImVec4(1.00, 0.55, 0.40, 1.00)
			style.Colors[imgui.Col.Header]                 = imgui.ImVec4(0.45, 0.25, 0.20, 1.00)
			style.Colors[imgui.Col.HeaderHovered]          = imgui.ImVec4(0.55, 0.30, 0.25, 1.00)
			style.Colors[imgui.Col.HeaderActive]           = imgui.ImVec4(0.65, 0.40, 0.30, 1.00)
			style.Colors[imgui.Col.Separator]              = imgui.ImVec4(0.80, 0.35, 0.20, 1.00)
			style.Colors[imgui.Col.SeparatorHovered]       = imgui.ImVec4(0.90, 0.50, 0.35, 1.00)
			style.Colors[imgui.Col.SeparatorActive]        = imgui.ImVec4(1.00, 0.65, 0.50, 1.00)
			style.Colors[imgui.Col.ResizeGrip]             = imgui.ImVec4(0.45, 0.25, 0.20, 1.00)
			style.Colors[imgui.Col.ResizeGripHovered]      = imgui.ImVec4(0.55, 0.30, 0.25, 1.00)
			style.Colors[imgui.Col.ResizeGripActive]       = imgui.ImVec4(0.65, 0.40, 0.30, 1.00)
			style.Colors[imgui.Col.PlotLines]              = imgui.ImVec4(0.90, 0.50, 0.35, 1.00)
			style.Colors[imgui.Col.PlotLinesHovered]       = imgui.ImVec4(1.00, 0.55, 0.40, 1.00)
			style.Colors[imgui.Col.PlotHistogram]          = imgui.ImVec4(0.90, 0.50, 0.35, 1.00)
			style.Colors[imgui.Col.PlotHistogramHovered]   = imgui.ImVec4(1.00, 0.55, 0.40, 1.00)
			style.Colors[imgui.Col.TextSelectedBg]         = imgui.ImVec4(0.55, 0.30, 0.25, 1.00)
			style.Colors[imgui.Col.ModalWindowDimBg]       = imgui.ImVec4(0.25, 0.15, 0.10, 0.80)
			style.Colors[imgui.Col.Tab]                    = imgui.ImVec4(0.30, 0.20, 0.15, 1.00)
			style.Colors[imgui.Col.TabHovered]             = imgui.ImVec4(0.90, 0.50, 0.35, 1.00)
			style.Colors[imgui.Col.TabActive]              = imgui.ImVec4(1.00, 0.55, 0.40, 1.00)		
		end
	},
    {
        change = function()
			imgui.SwitchContext()
			local style = imgui.GetStyle()
            style.Colors[imgui.Col.Text]                   = imgui.ImVec4(0.90, 0.90, 0.80, 1.00)
            style.Colors[imgui.Col.TextDisabled]           = imgui.ImVec4(0.60, 0.50, 0.50, 1.00)
            style.Colors[imgui.Col.WindowBg]               = imgui.ImVec4(0.10, 0.10, 0.10, 1.00)
            style.Colors[imgui.Col.ChildBg]                = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
            style.Colors[imgui.Col.PopupBg]                = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
            style.Colors[imgui.Col.Border]                 = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
            style.Colors[imgui.Col.BorderShadow]           = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
            style.Colors[imgui.Col.FrameBg]                = imgui.ImVec4(0.20, 0.20, 0.20, 1.00)
            style.Colors[imgui.Col.FrameBgHovered]         = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
            style.Colors[imgui.Col.FrameBgActive]          = imgui.ImVec4(0.25, 0.25, 0.25, 1.00)
            style.Colors[imgui.Col.TitleBg]                = imgui.ImVec4(0.15, 0.15, 0.15, 1.00)
            style.Colors[imgui.Col.TitleBgCollapsed]       = imgui.ImVec4(0.10, 0.10, 0.10, 1.00)
            style.Colors[imgui.Col.TitleBgActive]          = imgui.ImVec4(0.20, 0.20, 0.20, 1.00)
            style.Colors[imgui.Col.MenuBarBg]              = imgui.ImVec4(0.15, 0.15, 0.15, 1.00)
            style.Colors[imgui.Col.ScrollbarBg]            = imgui.ImVec4(0.10, 0.10, 0.10, 1.00)
            style.Colors[imgui.Col.ScrollbarGrab]          = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
            style.Colors[imgui.Col.ScrollbarGrabHovered]   = imgui.ImVec4(0.40, 0.40, 0.40, 1.00)
            style.Colors[imgui.Col.ScrollbarGrabActive]    = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
            style.Colors[imgui.Col.CheckMark]              = imgui.ImVec4(0.66, 0.66, 0.66, 1.00)
            style.Colors[imgui.Col.SliderGrab]             = imgui.ImVec4(0.66, 0.66, 0.66, 1.00)
            style.Colors[imgui.Col.SliderGrabActive]       = imgui.ImVec4(0.70, 0.70, 0.73, 1.00)
            style.Colors[imgui.Col.Button]                 = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
            style.Colors[imgui.Col.ButtonHovered]          = imgui.ImVec4(0.40, 0.40, 0.40, 1.00)
            style.Colors[imgui.Col.ButtonActive]           = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
            style.Colors[imgui.Col.Header]                 = imgui.ImVec4(0.20, 0.20, 0.20, 1.00)
            style.Colors[imgui.Col.HeaderHovered]          = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
            style.Colors[imgui.Col.HeaderActive]           = imgui.ImVec4(0.25, 0.25, 0.25, 1.00)
            style.Colors[imgui.Col.Separator]              = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
            style.Colors[imgui.Col.SeparatorHovered]       = imgui.ImVec4(0.40, 0.40, 0.40, 1.00)
            style.Colors[imgui.Col.SeparatorActive]        = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
            style.Colors[imgui.Col.ResizeGrip]             = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
            style.Colors[imgui.Col.ResizeGripHovered]      = imgui.ImVec4(0.40, 0.40, 0.40, 1.00)
            style.Colors[imgui.Col.ResizeGripActive]       = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
            style.Colors[imgui.Col.PlotLines]              = imgui.ImVec4(0.70, 0.70, 0.73, 1.00)
            style.Colors[imgui.Col.PlotLinesHovered]       = imgui.ImVec4(0.95, 0.95, 0.70, 1.00)
            style.Colors[imgui.Col.PlotHistogram]          = imgui.ImVec4(0.70, 0.70, 0.73, 1.00)
            style.Colors[imgui.Col.PlotHistogramHovered]   = imgui.ImVec4(0.95, 0.95, 0.70, 1.00)
            style.Colors[imgui.Col.TextSelectedBg]         = imgui.ImVec4(0.25, 0.25, 0.15, 1.00)
            style.Colors[imgui.Col.ModalWindowDimBg]       = imgui.ImVec4(0.10, 0.10, 0.10, 0.80)
            style.Colors[imgui.Col.Tab]                    = imgui.ImVec4(0.20, 0.20, 0.20, 1.00)
            style.Colors[imgui.Col.TabHovered]             = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
            style.Colors[imgui.Col.TabActive]              = imgui.ImVec4(0.25, 0.25, 0.25, 1.00)		
		end
	},
    {
        change = function()
			imgui.SwitchContext()
			local style = imgui.GetStyle()
            style.Colors[imgui.Col.Text]                   = imgui.ImVec4(0.10, 0.10, 0.10, 1.00)
            style.Colors[imgui.Col.TextDisabled]           = imgui.ImVec4(0.60, 0.60, 0.60, 1.00)
            style.Colors[imgui.Col.WindowBg]               = imgui.ImVec4(0.95, 0.95, 0.95, 1.00)
            style.Colors[imgui.Col.ChildBg]                = imgui.ImVec4(0.90, 0.90, 0.90, 1.00)
            style.Colors[imgui.Col.PopupBg]                = imgui.ImVec4(0.95, 0.95, 0.95, 1.00)
            style.Colors[imgui.Col.Border]                 = imgui.ImVec4(0.80, 0.80, 0.80, 1.00)
            style.Colors[imgui.Col.BorderShadow]           = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
            style.Colors[imgui.Col.FrameBg]                = imgui.ImVec4(0.85, 0.85, 0.85, 1.00)
            style.Colors[imgui.Col.FrameBgHovered]         = imgui.ImVec4(0.75, 0.75, 0.75, 1.00)
            style.Colors[imgui.Col.FrameBgActive]          = imgui.ImVec4(0.65, 0.65, 0.65, 1.00)
            style.Colors[imgui.Col.TitleBg]                = imgui.ImVec4(0.80, 0.80, 0.80, 1.00)
            style.Colors[imgui.Col.TitleBgCollapsed]       = imgui.ImVec4(0.70, 0.70, 0.70, 1.00)
            style.Colors[imgui.Col.TitleBgActive]          = imgui.ImVec4(0.75, 0.75, 0.75, 1.00)
            style.Colors[imgui.Col.MenuBarBg]              = imgui.ImVec4(0.85, 0.85, 0.85, 1.00)
            style.Colors[imgui.Col.ScrollbarBg]            = imgui.ImVec4(0.90, 0.90, 0.90, 1.00)
            style.Colors[imgui.Col.ScrollbarGrab]          = imgui.ImVec4(0.75, 0.75, 0.75, 1.00)
            style.Colors[imgui.Col.ScrollbarGrabHovered]   = imgui.ImVec4(0.65, 0.65, 0.65, 1.00)
            style.Colors[imgui.Col.ScrollbarGrabActive]    = imgui.ImVec4(0.55, 0.55, 0.55, 1.00)
            style.Colors[imgui.Col.CheckMark]              = imgui.ImVec4(0.35, 0.35, 0.35, 1.00)
            style.Colors[imgui.Col.SliderGrab]             = imgui.ImVec4(0.45, 0.45, 0.45, 1.00)
            style.Colors[imgui.Col.SliderGrabActive]       = imgui.ImVec4(0.55, 0.55, 0.55, 1.00)
            style.Colors[imgui.Col.Button]                 = imgui.ImVec4(0.80, 0.80, 0.80, 1.00)
            style.Colors[imgui.Col.ButtonHovered]          = imgui.ImVec4(0.70, 0.70, 0.70, 1.00)
            style.Colors[imgui.Col.ButtonActive]           = imgui.ImVec4(0.60, 0.60, 0.60, 1.00)
            style.Colors[imgui.Col.Header]                 = imgui.ImVec4(0.85, 0.85, 0.85, 1.00)
            style.Colors[imgui.Col.HeaderHovered]          = imgui.ImVec4(0.75, 0.75, 0.75, 1.00)
            style.Colors[imgui.Col.HeaderActive]           = imgui.ImVec4(0.65, 0.65, 0.65, 1.00)
            style.Colors[imgui.Col.Separator]              = imgui.ImVec4(0.80, 0.80, 0.80, 1.00)
            style.Colors[imgui.Col.SeparatorHovered]       = imgui.ImVec4(0.70, 0.70, 0.70, 1.00)
            style.Colors[imgui.Col.SeparatorActive]        = imgui.ImVec4(0.60, 0.60, 0.60, 1.00)
            style.Colors[imgui.Col.ResizeGrip]             = imgui.ImVec4(0.85, 0.85, 0.85, 1.00)
            style.Colors[imgui.Col.ResizeGripHovered]      = imgui.ImVec4(0.75, 0.75, 0.75, 1.00)
            style.Colors[imgui.Col.ResizeGripActive]       = imgui.ImVec4(0.65, 0.65, 0.65, 1.00)
            style.Colors[imgui.Col.PlotLines]              = imgui.ImVec4(0.40, 0.40, 0.40, 1.00)
            style.Colors[imgui.Col.PlotLinesHovered]       = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
            style.Colors[imgui.Col.PlotHistogram]          = imgui.ImVec4(0.40, 0.40, 0.40, 1.00)
            style.Colors[imgui.Col.PlotHistogramHovered]   = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
            style.Colors[imgui.Col.TextSelectedBg]         = imgui.ImVec4(0.75, 0.75, 0.75, 1.00)
            style.Colors[imgui.Col.ModalWindowDimBg]       = imgui.ImVec4(0.85, 0.85, 0.85, 0.80)
            style.Colors[imgui.Col.Tab]                    = imgui.ImVec4(0.85, 0.85, 0.85, 1.00)
            style.Colors[imgui.Col.TabHovered]             = imgui.ImVec4(0.75, 0.75, 0.75, 1.00)
            style.Colors[imgui.Col.TabActive]              = imgui.ImVec4(0.65, 0.65, 0.65, 1.00)	
		end
	}
}

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
    sampRegisterChatCommand("arep", cmd_arep)

    sampAddChatMessage(tag .. 'Скрипт {00FF00}загружен.{FFFFFF} Активация меню: {00FF00}/arep', -1)

    show_arz_notify('success', 'RepFlow', 'Успешная загрузка. Активация: /arep', 9000)

    while true do
        wait(0)

        checkPauseAndDisableAutoStart() -- Проверяем сворачивание игры
        checkAutoStart() -- Выполняется с задержкой, если игра не свернута

        imgui.Process = main_window_state[0] and not isGameMinimized

        -- Логика перемещения окна
        if MoveWidget then
            ini.widget.posX, ini.widget.posY = getCursorPos()
            local cursorX, cursorY = getCursorPos()
            ini.widget.posX = cursorX
            ini.widget.posY = cursorY
            if isKeyJustPressed(0x20) then -- Пробел для фиксации позиции
                MoveWidget = false
                sampToggleCursor(false)
                saveWindowSettings()
            end
        end

        -- Логика отображения окна информации
        if active or MoveWidget then
            showInfoWindow() -- Показываем окно информации только если ловля активна или идет перемещение
        else
            showInfoWindowOff() -- Скрываем окно, если ни одно условие не выполнено
        end

        -- Ловля активируется по клавише
        if not changingKey and isKeyJustPressed(keyBind) and not isSampfuncsConsoleActive() and not sampIsChatInputActive() and not sampIsDialogActive() and not isPauseMenuActive() then
            onToggleActive()
        end

        -- Если автоловля активна
        if active then
            local currentTime = os.clock() * 1000 -- Текущее время в миллисекундах

            -- Ловля репортов
            if useMilliseconds[0] then
                if currentTime - lastOtTime >= otInterval[0] then
                    sampSendChat('/ot')
                    lastOtTime = currentTime
                end
            else
                if (currentTime - lastOtTime) >= (otInterval[0] * 1000) then
                    sampSendChat('/ot')
                    lastOtTime = currentTime
                end
            end
        else
            -- Если автоловля неактивна, сбрасываем таймеры
            startTime = os.clock() -- Сбрасываем и фиксируем время начала автоловли
            attemptCount = 0 -- Сбрасываем количество попыток
        end
    end
end

function resetIO()
    for i = 0, 511 do
        imgui.GetIO().KeysDown[i] = false
    end
    for i = 0, 4 do
        imgui.GetIO().MouseDown[i] = false
    end
    imgui.GetIO().KeyCtrl = false
    imgui.GetIO().KeyShift = false
    imgui.GetIO().KeyAlt = false
    imgui.GetIO().KeySuper = false
end

function startMovingWindow()
    MoveWidget = true -- Включаем режим перемещения
    showInfoWindow() -- Показываем окно информации, чтобы пользователь мог его перемещать
    sampToggleCursor(true) -- Показываем курсор
    main_window_state[0] = false -- Закрываем основное окно
    sampAddChatMessage(taginf .. '{FFFF00}Режим перемещения окна активирован. Нажмите "Пробел" для подтверждения.', -1)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    iconRanges = imgui.new.ImWchar[3](faicons.min_range, faicons.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('solid'), 14, config, iconRanges) -- solid - тип иконок, так же есть thin, regular, light и duotone
	decor() -- применяем декор часть
    themes[colorListNumber[0]+1].change() -- применяем цветовую часть
end)

local dialogHandlerEnabled = new.bool(ini.main.dialogHandlerEnabled)

function decor()
    -- == Декор часть == --
	local ImVec4 = imgui.ImVec4
	imgui.SwitchContext()
	local style = imgui.GetStyle()
	style.WindowPadding = imgui.ImVec2(15, 15)
	style.WindowRounding = 10.0
	style.ChildRounding = 6.0
	style.FramePadding = imgui.ImVec2(8, 7)
	style.FrameRounding = 8.0
	style.ItemSpacing = imgui.ImVec2(8, 8)
	style.ItemInnerSpacing = imgui.ImVec2(10, 6)
	style.IndentSpacing = 25.0
	style.ScrollbarSize = 13.0
	style.ScrollbarRounding = 12.0
	style.GrabMinSize = 10.0
	style.GrabRounding = 6.0
	style.PopupRounding = 8
	style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
	style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)
end

function sampev.onServerMessage(color, text)
    if text:find('%[(%W+)%] от (%w+_%w+)%[(%d+)%]:') then
        if active then
            sampSendChat('/ot')
        end
    end
    return filterFloodMessage(text)
end

function onToggleActive()
    active = not active
    manualDisable = not active  -- Устанавливаем флаг для автостарта
    disableAutoStartOnToggle = not active -- Если ловля отключена вручную, отключаем автостарт

    local status = active and '{00FF00}включена' or '{FF0000}выключена'
    local statusArz = active and 'включена' or 'выключена'

    show_arz_notify('info', 'RepFlow', 'Ловля ' .. statusArz .. '!', 2000)
end

function saveWindowSettings()
    ini.widget.posX = ini.widget.posX or 400 -- Устанавливаем значение по умолчанию
    ini.widget.posY = ini.widget.posY or 400 -- Устанавливаем значение по умолчанию
    inicfg.save(ini, IniFilename) -- Сохраняем в INI-файл
    sampAddChatMessage(taginf .. '{00FF00}Положение окна сохранено!', -1)
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    if dialogId == 1334 then
        lastDialogTime = os.clock() -- Сброс таймера при появлении диалога
        reportAnsweredCount = reportAnsweredCount + 1 -- Увеличиваем счетчик
        sampAddChatMessage(tag .. '{00FF00}Репорт принят! Отвечено репорта: ' .. reportAnsweredCount, -1)
        if active then
            active = false
            show_arz_notify('info', 'RepFlow', 'Ловля отключена из-за окна репорта!', 3000)
        end
    end
end

function checkAutoStart()
    local currentTime = os.clock()
    
    -- Проверяем, что ловля не активна, игра не свернута и прошло достаточно времени с выхода из AFK
    if autoStartEnabled[0] and not active and not gameMinimized and (afkExitTime == 0 or currentTime - afkExitTime >= afkCooldown) then
        -- Если отключение автостарта не было активировано вручную
        if not disableAutoStartOnToggle and (currentTime - lastDialogTime) > dialogTimeout[0] then
            active = true
            show_arz_notify('info', 'RepFlow', 'Ловля включена по таймауту', 3000)
        end
    end
end

function saveSettings()
    ini.main.dialogTimeout = dialogTimeout[0]
    inicfg.save(ini, IniFilename)
end

function imgui.Link(link, text)
	text = text or link
	local tSize = imgui.CalcTextSize(text)
	local p = imgui.GetCursorScreenPos()
	local DL = imgui.GetWindowDrawList()
	local col = { 0xFFFF7700, 0xFFFF9900 }
	if imgui.InvisibleButton('##' .. link, tSize) then os.execute('explorer ' .. link) end
	local color = imgui.IsItemHovered() and col[1] or col[2]
	DL:AddText(p, color, text)
	DL:AddLine(imgui.ImVec2(p.x, p.y + tSize.y), imgui.ImVec2(p.x + tSize.x, p.y + tSize.y), color)
end

function cmd_arep(arg)
    main_window_state[0] = not main_window_state[0]
    imgui.Process = main_window_state[0]
end

function drawMainTab()
    -- Отображение заголовка
    imgui.CenterText(u8"Настройки флудера")
    imgui.Separator()

    imgui.PushItemWidth(100)

    -- Чекбокс для использования миллисекунд
    if imgui.Checkbox(u8'Использовать миллисекунды', useMilliseconds) then
        ini.main.useMilliseconds = useMilliseconds[0]
        inicfg.save(ini, IniFilename)
    end

    imgui.PopItemWidth()

    -- Текстовое поле для интервала отправки команды /ot
    imgui.Text(u8'Интервал отправки команды /ot (' .. (useMilliseconds[0] and u8'в миллисекундах' or u8'в секундах') .. '):')

    -- Текущее значение интервала
    imgui.Text(u8'Текущий интервал: ' .. otInterval[0] .. (useMilliseconds[0] and u8' мс' or u8' секунд'))

    imgui.PushItemWidth(45)

    -- Поле для ввода интервала
    imgui.InputText(u8'##otIntervalInput', otIntervalBuffer, ffi.sizeof(otIntervalBuffer))
    imgui.SameLine()
    -- Кнопка для сохранения интервала
    if imgui.Button(faicons('floppy_disk') .. u8" Сохранить интервал") then
        local newValue = tonumber(ffi.string(otIntervalBuffer)) -- Преобразуем строку в число
        if newValue ~= nil then
            otInterval[0] = newValue -- Обновляем значение otInterval
            ini.main.otInterval = otInterval[0] -- Сохраняем в конфиг
            inicfg.save(ini, IniFilename)
            sampAddChatMessage(taginf .. "Интервал сохранён: {32CD32}" .. newValue .. (useMilliseconds[0] and " мс" or " секунд"), -1)
        else
            sampAddChatMessage(taginf .. "Некорректное значение. {32CD32}Введите число.", -1)
        end
    end

    imgui.PopItemWidth()

    imgui.Separator()

    -- Информационные сообщения
    imgui.Text(u8'Скрипт также ищет надпись в чате [Репорт] от Имя_Фамилия.')
    imgui.Text(u8'Флудер нужен для дополнительного способа ловли репорта.')

    imgui.Separator()
end

function drawSettingsTab()
    imgui.CenterText(u8'Настройки ловли')
    imgui.Separator()
    imgui.Text(u8'Текущая клавиша активации:')
    imgui.SameLine()
    if imgui.Button(u8'' .. keyBindName) then
        changingKey = true
        show_arz_notify('info', 'RepFlow', 'Нажмите новую клавишу для активации', 2000)
    end

    imgui.Separator()

    -- Выбор темы
    imgui.Text(u8'Выберите тему:')
    if imgui.Combo(u8'Темы', colorListNumber, colorListBuffer, #colorList) then
        themes[colorListNumber[0] + 1].change()
        ini.main.themes = colorListNumber[0]
        inicfg.save(ini, IniFilename)
    end

    imgui.Separator()

    -- Обработка диалогов
    if imgui.Checkbox(u8'Обрабатывать диалоги', dialogHandlerEnabled) then
        ini.main.dialogHandlerEnabled = dialogHandlerEnabled[0]
        inicfg.save(ini, IniFilename)
    end

    -- Автостарт
    if imgui.Checkbox(u8'Автостарт ловли по большому активу', autoStartEnabled) then
        ini.main.autoStartEnabled = autoStartEnabled[0]
        inicfg.save(ini, IniFilename)
    end

    -- Отключение сообщения "Не флуди"
    if imgui.Checkbox(u8'Отключить сообщение "Не флуди"', hideFloodMsg) then
        ini.main.otklflud = hideFloodMsg[0]
        inicfg.save(ini, IniFilename)
    end

    imgui.Separator()

    -- Поле для ввода тайм-аута автостарта
    imgui.PushItemWidth(45)
    imgui.Text(u8'Тайм-аут для автостарта в (секундах):')
    imgui.Text(u8'Текущий тайм-аут: ' .. dialogTimeout[0] .. u8' секунд')
    imgui.InputText(u8'', dialogTimeoutBuffer, ffi.sizeof(dialogTimeoutBuffer))
    imgui.SameLine()

    -- Кнопка "Сохранить" для тайм-аута
    if imgui.Button(faicons('floppy_disk') .. u8" Сохранить тайм-аут") then
        local newValue = tonumber(ffi.string(dialogTimeoutBuffer))
        if newValue ~= nil and newValue >= 1 and newValue <= 9999 then
            dialogTimeout[0] = newValue -- Обновляем тайм-аут
            saveSettings() -- Сохраняем изменения
            sampAddChatMessage(taginf .. "Тайм-аут сохранён: {32CD32}" .. newValue .. " секунд", -1)
        else
            sampAddChatMessage(taginf .. "Некорректное значение. {32CD32}Введите от 1 до 9999.", -1)
        end
    end
    imgui.PopItemWidth()

    imgui.Separator()

    -- Изменение положения окна
    imgui.Text(u8'Положение окна информации:')
    imgui.SameLine()
    if imgui.Button(u8'Изменить положение') then
        startMovingWindow() -- Активируем перемещение окна при нажатии
    end
end

function saveColorCode()
    ini.main.colorCode = ffi.string(colorCode)
    inicfg.save(ini, IniFilename)
end

function filterFloodMessage(text)
    if hideFloodMsg[0] and text:find("%[Ошибка%] {FFFFFF}Сейчас нет вопросов в репорт!") then
        return false -- Блокируем сообщение "Не флуди"
    end
end

-- Функция для проверки сворачивания игры и отключения автостарта
function checkPauseAndDisableAutoStart()
    if isPauseMenuActive() then
        -- Игра свернута
        if not gameMinimized then
            -- Сохраняем состояние ловли перед сворачиванием
            wasActiveBeforePause = active

            -- Отключаем автоловлю, если она была активна
            if active then
                active = false -- Отключаем ловлю
            end

            -- Ставим флаг, что игра свернута
            gameMinimized = true
        end
    else
        -- Игра развернута
        if gameMinimized then
            -- Если игра была свернута и ловля была активна, можно снова её включить или вывести сообщение
            gameMinimized = false

            -- Если ловля была активна перед сворачиванием, возможно, можно активировать её через таймер
            if wasActiveBeforePause then
                sampAddChatMessage(tag .. '{FFFFFF}Вы вышли из паузы. Ловля отключена из-за AFK!!', -1)
            end
        end
    end
end

function drawInfoTab()
    imgui.CenterText(u8'Информация о скрипте')
    imgui.Separator()
    imgui.Text(u8'Автор: Matthew_McLaren[18]')
    imgui.Text(u8'Версия: %s', scriptver)
	imgui.Text(u8'Связь с разработчиком:')
	imgui.SameLine()
	imgui.Link('https://t.me/Zorahm', 'Telegram')
    imgui.Text(u8'')
    imgui.Text(u8'Скрипт автоматически отправляет команду /ot.')
    imgui.Text(u8'Через определенные интервалы времени.')
    imgui.Text(u8'А также выслеживает определенные надписи.')
	imgui.Text(u8'')
    imgui.CenterText(u8'А также спасибо:')
    imgui.Text(u8'Тестер: Carl_Mort[18].')
end

-- Функция для отрисовки вкладки "ChangeLog"
function drawChangeLogTab()
    imgui.CenterText(u8("Изменения по версиям:"))
    imgui.Separator()

    -- Проходим по каждому элементу в changelog
    for _, entry in ipairs(changelogEntries) do
        if imgui.CollapsingHeader(u8("Версия ") .. entry.version) then
            -- Если заголовок раскрыт, отображаем описание изменений
            imgui.Text(u8(entry.description)) -- Указываем кодировку UTF-8 для отображения русского текста
        end
    end
end

imgui.OnFrame(function() return main_window_state[0] end, function(player)
    imgui.SetNextWindowSize(imgui.ImVec2(600, 400), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.Begin(u8'RepFlow ' .. faicons('STAR'), main_window_state, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
    resetIO()
    
    imgui.BeginChild('left_panel', imgui.ImVec2(150, 0), true)
    if imgui.Button(faicons("comment") .. u8' Флудер', imgui.ImVec2(125, 40)) then
        active_tab[0] = 0
    end
    if imgui.Button(faicons("GEAR") .. u8' Настройки', imgui.ImVec2(125, 40)) then
        active_tab[0] = 1
    end
    if imgui.Button(faicons("circle_info") .. u8' Информация', imgui.ImVec2(125, 40)) then
        active_tab[0] = 2
    end
    if imgui.Button(faicons("wrench") .. u8' ChangeLog', imgui.ImVec2(125, 40)) then
        active_tab[0] = 3
    end
    imgui.EndChild()

    imgui.SameLine()

    imgui.BeginChild('right_panel', imgui.ImVec2(0, 0), true)
    if active_tab[0] == 0 then
        drawMainTab()
    elseif active_tab[0] == 1 then
        drawSettingsTab()
    elseif active_tab[0] == 2 then
        drawInfoTab()
    elseif active_tab[0] == 3 then
        drawChangeLogTab()
    end
    imgui.EndChild()

    imgui.End()
end)

function onWindowMessage(msg, wparam, lparam)
    if changingKey then
        if msg == 0x100 or msg == 0x101 then -- WM_KEYDOWN or WM_KEYUP
            keyBind = wparam
            keyBindName = vkeys.id_to_name(keyBind) -- Вызов функции для получения имени клавиши
            changingKey = false
            ini.main.keyBind = string.format("0x%X", keyBind)
            ini.main.keyBindName = keyBindName
            inicfg.save(ini, IniFilename)
            sampAddChatMessage(string.format(tag .. '{FFFFFF}Новая клавиша активации ловли репорта: {00FF00}%s', keyBindName), -1)
            return false -- предотвращает дальнейшую обработку сообщения
        end
    end
end

function imgui.CenterText(text)
    local width = imgui.GetWindowWidth()
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX(width / 2 - calc.x / 2)
    imgui.Text(text)
end

-- Аризоновские уведомления
function show_arz_notify(type, title, text, time)
    if MONET_VERSION ~= nil then
        if type == 'info' then
            type = 3
        elseif type == 'error' then
            type = 2
        elseif type == 'success' then
            type = 1
        end
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, 62)
        raknetBitStreamWriteInt8(bs, 6)
        raknetBitStreamWriteBool(bs, true)
        raknetEmulPacketReceiveBitStream(220, bs)
        raknetDeleteBitStream(bs)
        local json = encodeJson({
            styleInt = type,
            title = title,
            text = text,
            duration = time
        })
        local interfaceid = 6
        local subid = 0
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, 84)
        raknetBitStreamWriteInt8(bs, interfaceid)
        raknetBitStreamWriteInt8(bs, subid)
        raknetBitStreamWriteInt32(bs, #json)
        raknetBitStreamWriteString(bs, json)
        raknetEmulPacketReceiveBitStream(220, bs)
        raknetDeleteBitStream(bs)
    else
        local str = ('window.executeEvent(\'event.notify.initialize\', \'["%s", "%s", "%s", "%s"]\');'):format(type, title, text, time)
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, 17)
        raknetBitStreamWriteInt32(bs, 0)
        raknetBitStreamWriteInt32(bs, #str)
        raknetBitStreamWriteString(bs, str)
        raknetEmulPacketReceiveBitStream(220, bs)
        raknetDeleteBitStream(bs)
    end
end

-- Функция для отрисовки окна информации
imgui.OnFrame(function() return info_window_state[0] end, function(self)
    self.HideCursor = true
    -- Устанавливаем минимальные и максимальные размеры окна
    imgui.SetNextWindowSize(imgui.ImVec2(220, 175), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(ini.widget.posX, ini.widget.posY), imgui.Cond.Always)

    -- Начало окна с флагами
    imgui.Begin(faicons('gear') .. u8" Информация " .. faicons('gear'), info_window_state, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
    imgui.CenterText(u8'Статус Ловли: Включена')
    -- Время работы автоловли
    local elapsedTime = os.clock() - startTime
    imgui.CenterText(string.format(u8'Время работы: %.2f сек', elapsedTime))

    -- Количество ответов на репорт (появление диалога 1334)
    imgui.CenterText(string.format(u8'Отвечено репорта: %d', reportAnsweredCount))
    imgui.Separator()
    -- Статус обработки диалогов
    imgui.Text(u8'Обработка диалогов:')
    imgui.SameLine()
    if dialogHandlerEnabled[0] then
        imgui.Text(u8'Включена')
    else
        imgui.Text(u8'Выкл.')
    end

    -- Статус автостарта
    imgui.Text(u8'Автостарт:')
    imgui.SameLine()
    if autoStartEnabled[0] then
        imgui.Text(u8'Включен')
    else
        imgui.Text(u8'Выключен')
    end
    imgui.End() -- Завершение окна
end)

-- Пример функции для активации окна информации
function showInfoWindow()
    info_window_state[0] = true
end

function showInfoWindowOff()
    info_window_state[0] = false
end