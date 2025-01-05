require 'lib.moonloader'
local imgui = require 'mimgui'
local sampev = require 'lib.samp.events'
local vkeys = require 'vkeys'
local encoding = require 'encoding'
local inicfg = require 'inicfg'
local ffi = require 'ffi'

local IniFilename = 'RepFlowCFG.ini'
local new = imgui.new
local faicons = require('fAwesome6')
local scriptver = "3.1 | Premium"

local changelogEntries = {
    { version = "3.1 | Premium", description = "- Новый стиль меню.\n- ChangeLog теперь разделён на две версии.\n\nHF-1.0: Исправлены грамматические ошибки\n\nHF-1.1: Налажен цвет плиток\n- Исправлены грамматические ошибки." },
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

local active_tab = new.int(0)

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
-- colorListNumber[0] = tonumber(ini.main.themes)
dialogTimeout[0] = tonumber(ini.main.dialogTimeout)
dialogHandlerEnabled[0] = ini.main.dialogHandlerEnabled
autoStartEnabled[0] = ini.main.autoStartEnabled or false
hideFloodMsg[0] = ini.main.otklflud

-- Основной цвет темы
local colors = {
    leftPanelColor = imgui.ImVec4(27 / 255, 20 / 255, 30 / 255, 1.0),        -- цвет левого прямоугольника
    rightPanelColor = imgui.ImVec4(24 / 255, 18 / 255, 28 / 255, 1.0),       -- цвет правого прямоугольника
    childPanelColor = imgui.ImVec4(18 / 255, 13 / 255, 22 / 255, 1.0),       -- цвет child-окна
    hoverColor = imgui.ImVec4(63 / 255, 59 / 255, 66 / 255, 1.0),            -- цвет наведения для кнопок
}

function drawThemeSelector()
    imgui.Text(u8"Выберите тему:")
    for i, theme in ipairs(themes) do
        local color = theme.previewColor or imgui.ImVec4(0.5, 0.5, 0.5, 1.0) -- Убедимся, что есть значение по умолчанию

        -- Добавляем ColorButton для выбора темы
        if imgui.ColorButton("##theme" .. i, color, imgui.ColorButtonFlags.NoTooltip + imgui.ColorButtonFlags.NoBorder, imgui.ImVec2(40, 40)) then
            theme.change() -- Применяем тему при клике на кнопку
            ini.main.themes = i - 1
            inicfg.save(ini, IniFilename)
        end

        -- Добавляем пробел между кнопками
        if i < #themes then
            imgui.SameLine()
        end
    end
end


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
    --themes[currentTheme[0]+1].change() -- применяем цветовую часть
end)

local dialogHandlerEnabled = new.bool(ini.main.dialogHandlerEnabled)

function decor()
    local ImVec4 = imgui.ImVec4
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    
    style.WindowPadding = imgui.ImVec2(12, 12)  -- Отступы внутри окон
    style.WindowRounding = 12.0  -- Закругление углов окон
    style.ChildRounding = 10.0   -- Закругление углов дочерних окон
    style.FramePadding = imgui.ImVec2(8, 6)  -- Отступы внутри кнопок и полей
    style.FrameRounding = 10.0  -- Закругление для кнопок и полей ввода
    style.ItemSpacing = imgui.ImVec2(10, 10)  -- Увеличено расстояние между элементами
    style.ItemInnerSpacing = imgui.ImVec2(10, 10)  -- Внутреннее расстояние для элементов
    style.ScrollbarSize = 12.0  -- Размер полосы прокрутки
    style.ScrollbarRounding = 10.0  -- Закругление полосы прокрутки
    style.GrabRounding = 10.0  -- Закругление ползунков
    style.PopupRounding = 10.0  -- Закругление всплывающих окон
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)  -- Выравнивание заголовков окон по центру
    style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)  -- Выравнивание текста кнопок по центру
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
    panelColor = panelColor or imgui.ImVec4(18 / 255, 13 / 255, 22 / 255, 1) -- Установим значение по умолчанию
    imgui.Text(faicons('gear') .. u8" Настройки  /  " .. faicons('message') .. u8" Флудер")
    imgui.Separator()
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor) -- Устанавливаем цвет
    if imgui.BeginChild("Flooder", imgui.ImVec2(0, 150), true) then
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
    end
    imgui.PopItemWidth()
    imgui.EndChild()
    imgui.PopStyleColor() -- Сбрасываем цвет

    -- Информационные сообщения
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor) -- Устанавливаем цвет
    if imgui.BeginChild("InfoFlooder", imgui.ImVec2(0, 65), true) then
        imgui.Text(u8'Скрипт также ищет надпись в чате [Репорт] от Имя_Фамилия.')
        imgui.Text(u8'Флудер нужен для дополнительного способа ловли репорта.')
    end
    imgui.EndChild()
    imgui.PopStyleColor() -- Сбрасываем цвет
end

function drawSettingsTab()
    -- Заголовок с иконками для вкладки
    imgui.Text(faicons('gear') .. u8" Настройки  /  " .. faicons('sliders') .. u8" Основные настройки")
    imgui.Separator()
    panelColor = panelColor or imgui.ImVec4(18 / 255, 13 / 255, 22 / 255, 1) -- Установим значение по умолчанию
    -- Первый блок: информация об авторе
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor) -- Устанавливаем цвет
    if imgui.BeginChild("KeyBind", imgui.ImVec2(0, 60), true) then
        imgui.Text(u8'Текущая клавиша активации:')
        imgui.SameLine()
        if imgui.Button(u8'' .. keyBindName) then
            changingKey = true
            show_arz_notify('info', 'RepFlow', 'Нажмите новую клавишу для активации', 2000)
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor() -- Сбрасываем цвет

    -- Блок обработки диалогов
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor) -- Устанавливаем цвет
    if imgui.BeginChild("DialogOptions", imgui.ImVec2(0, 150), true) then
        imgui.Text(u8"Обработка диалогов")
        if imgui.Checkbox(u8'Обрабатывать диалоги', dialogHandlerEnabled) then
            ini.main.dialogHandlerEnabled = dialogHandlerEnabled[0]
            inicfg.save(ini, IniFilename)
        end
        if imgui.Checkbox(u8'Автостарт ловли по большому активу', autoStartEnabled) then
            ini.main.autoStartEnabled = autoStartEnabled[0]
            inicfg.save(ini, IniFilename)
        end
        if imgui.Checkbox(u8'Отключить сообщение "Не флуди"', hideFloodMsg) then
            ini.main.otklflud = hideFloodMsg[0]
            inicfg.save(ini, IniFilename)
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor() -- Сбрасываем цвет

    -- Блок ввода тайм-аута для автостарта
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor) -- Устанавливаем цвет
    if imgui.BeginChild("AutoStartTimeout", imgui.ImVec2(0, 100), true) then
        imgui.Text(u8'Настройка тайм-аута автостарта')
        imgui.PushItemWidth(45)
        imgui.Text(u8'Текущий тайм-аут: ' .. dialogTimeout[0] .. u8' секунд')
        imgui.InputText(u8'', dialogTimeoutBuffer, ffi.sizeof(dialogTimeoutBuffer))
        imgui.SameLine()
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
    end
    imgui.PopItemWidth()
    imgui.PopStyleColor() -- Сбрасываем цвет
    imgui.EndChild()

    -- Блок изменения положения окна
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor) -- Устанавливаем цвет
    if imgui.BeginChild("WindowPosition", imgui.ImVec2(0, 50), true) then
        imgui.Text(u8'Положение окна информации:')
        imgui.SameLine()
        if imgui.Button(u8'Изменить положение') then
            startMovingWindow() -- Активируем перемещение окна при нажатии
        end
    end
    imgui.PopStyleColor() -- Сбрасываем цвет
    imgui.EndChild()
end

function saveColorCode()
    ini.main.colorCode = ffi.string(colorCode)
    inicfg.save(ini, IniFilename)
end

function filterFloodMessage(text)
    if hideFloodMsg[0] and text:find("%[Ошибка%] {FFFFFF}Сейчас нет вопросов в репорт!") or text:find("%[Ошибка%] {FFFFFF}Не флуди!") then
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

function drawInfoTab(panelColor)
    panelColor = panelColor or imgui.ImVec4(18 / 255, 13 / 255, 22 / 255, 1) -- Установим значение по умолчанию
    -- Заголовок с иконками
    imgui.Text(faicons('star') .. u8" RepFlow  /  " .. faicons('circle_info') .. u8" Информация")
    imgui.Separator()

    -- Первый блок: информация об авторе
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor) -- Устанавливаем цвет
    if imgui.BeginChild("Author", imgui.ImVec2(0, 100), true) then
        imgui.Text(u8'Автор: Matthew_McLaren[18]')
        imgui.Text(u8'Версия: ' .. scriptver) -- Используем конкатенацию вместо %s
        imgui.Text(u8'Связь с разработчиком:')
        imgui.SameLine()
        imgui.Link('https://t.me/Zorahm', 'Telegram')
    end
    imgui.EndChild()
    imgui.PopStyleColor() -- Сбрасываем цвет

    -- Второй блок: описание функционала
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor) -- Устанавливаем цвет
    if imgui.BeginChild("Info2", imgui.ImVec2(0, 100), true) then
        imgui.Text(u8'Скрипт автоматически отправляет команду /ot.')
        imgui.Text(u8'Через определенные интервалы времени.')
        imgui.Text(u8'А также выслеживает определенные надписи.')
    end
    imgui.EndChild()
    imgui.PopStyleColor() -- Сбрасываем цвет

    -- Третий блок: благодарности
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor) -- Устанавливаем цвет
    if imgui.BeginChild("Info3", imgui.ImVec2(0, 110), true) then
        imgui.CenterText(u8'А также спасибо:')
        imgui.Text(u8'Тестер: Carl_Mort[18].')
        imgui.Text(u8'Тестер: Sweet_Lemonte[18].')
        imgui.Text(u8'Тестер: Balenciaga_Collins[18].')
    end
    imgui.EndChild()
    imgui.PopStyleColor() -- Сбрасываем цвет
end


-- Функция для отрисовки вкладки "ChangeLog"
function drawChangeLogTab()
    imgui.Text(faicons('star') .. u8" RepFlow  /  " .. faicons('bolt') .. u8" ChangeLog")
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
    -- Настройка начального окна
    imgui.SetNextWindowSize(imgui.ImVec2(800, 500), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.PushStyleColor(imgui.Col.WindowBg, colors.rightPanelColor)
    resetIO()

    -- Открываем главное окно
    if imgui.Begin(faicons('bolt') .. u8' RepFlow | Premium', main_window_state, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse) then

        -- Левый панель с вкладками (убраны стили разделителей)
        imgui.PushStyleColor(imgui.Col.ChildBg, colors.leftPanelColor)
        if imgui.BeginChild("left_panel", imgui.ImVec2(130, -1), false) then
            local tabNames = { "Флудер", "Настройки", "Информация", "ChangeLog" }
            for i, name in ipairs(tabNames) do
                if i - 1 == active_tab[0] then
                    imgui.PushStyleColor(imgui.Col.Button, colors.hoverColor)
                else
                    imgui.PushStyleColor(imgui.Col.Button, colors.leftPanelColor)
                end
                imgui.PushStyleColor(imgui.Col.ButtonHovered, colors.hoverColor)
                imgui.PushStyleColor(imgui.Col.ButtonActive, colors.hoverColor)

                if imgui.Button(u8(name), imgui.ImVec2(125, 40)) then
                    active_tab[0] = i - 1
                end
                imgui.PopStyleColor(3)  -- Сбрасываем 3 стиля для каждой кнопки
            end
        end
        imgui.EndChild()
        imgui.PopStyleColor()


        -- Панель для содержимого вкладок без явного разделения
        imgui.SameLine() -- Убирает "разрыв" между панелями
        imgui.PushStyleColor(imgui.Col.ChildBg, colors.rightPanelColor)
        if imgui.BeginChild("right_panel", imgui.ImVec2(-1, 0), false) then
            if active_tab[0] == 0 then
                drawMainTab()
            elseif active_tab[0] == 1 then
                drawSettingsTab()
            elseif active_tab[0] == 2 then
                drawInfoTab(infoPanelColor)
            elseif active_tab[0] == 3 then
                drawChangeLogTab()
            end
        end
        imgui.EndChild()
        imgui.PopStyleColor()

    end
    imgui.End() -- Закрываем главное окно
    imgui.PopStyleColor() -- Сбрасываем цвет главного окна
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
    imgui.Begin(faicons('star') .. u8" | Информация ", info_window_state, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
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
