local server = "ws://192.168.1.191:7071"
-- local server = "ws://startendo.org:7071"

local ws, err = http.websocket(server)

if not ws then
    print("server imploded")
    return
end

local parent = term.current()
local width, height = parent.getSize()

local chat = window.create(parent, 1, 1, width, height - 1)
local input = window.create(parent, 1, height, width, 1)

local y = 1
local prefix = ""
local room = "general"
local sizechange = {}
local muted = {}
local motd = false
local motdLines = {}
local motdPage = 1

-- it's me new linity
local function urldecoding(text)
    return text:gsub("%%0A", "\n")
end

-- speaker support
local speaker = peripheral.find("speaker")
local function notification()
    if speaker then
            pcall(function()
                speaker.playSound("minecraft:block.note_block.pling", 0.8, 1.2)
            end)
        end
    end
-- find a floppy
local function mutePath()
    for _, name in ipairs(peripheral.getNames()) do
        local mount = disk.getMountPath(name)
        if mount then
            return fs.combine(mount, "muted.txt")
        end
    end
    return nil
end
-- load muted users
local function loadMuted()
    local path = mutePath()
    if not path or not fs.exists(path) then
        return
    end
    local file = fs.open(path, "r")
    while true do
        local user = file.readLine()
        if not user then break end
        muted[user] = true
    end
    file.close()
end
-- save muted users onto floppy
local function saveMuted()
    local path = mutePath()
    if not path then
        return false
    end
    local file = fs.open(path, "w")
    if not file then
        return false
    end
    for user in pairs(muted) do
        file.writeLine(user)
    end
    file.close()
    return true
end

loadMuted()

-- account on floppy
-- find file
local function accountfile()
    for _, name in ipairs(peripheral.getNames()) do local mount = disk.getMountPath(name)
        if mount then
            return fs.combine(mount, "aucaccount.txt")
        end
    end
    return nil
end
-- load account if file exists
local function apple()
    local path = accountfile()
    if not path or not fs.exists(path) then
        return nil, nil
    end
    local file = fs.open(path, "r")
    local username = file.readLine()
    local password = file.readLine()
    file.close()
    return username, password
end
-- account saving
local function accountsave(username, password)
    local path = accountfile()
    if not path then
        return false
    end
    local file = fs.open(path, "w")
    if not file then
        return false
    end
    file.writeLine(username)
    file.writeLine(password)
    file.close()
    return true
end

-- wrap messages if they're too long for the screen
local function wrap(message, wrapWidth)
    local lines = {}

    for paragraph in (message .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in paragraph:gmatch("%S+") do
            while #word > wrapWidth do
                if line ~= "" then
                    table.insert(lines, line)
                    line = ""
                end
                table.insert(lines, word:sub(1, wrapWidth))
                word = word:sub(wrapWidth + 1)
            end

            if line == "" then
                line = word
            elseif #line + #word + 1 <= wrapWidth then
                line = line .. " " .. word
            else
                table.insert(lines, line)
                line = word
            end
        end
        table.insert(lines, line)
    end
    return lines
end

-- fix auc imploding if on a monitor that changes size
local function redraw()
    width, height = parent.getSize()
    local chatHeight = math.max(1, height -1)
    chat.reposition(1, 1, width, chatHeight)
    input.reposition(1, height, width, 1)
    chat.clear()
    local displayLines = {}
    -- wrap messages if the monitor gets smaller
    for i = 1, #sizechange do
        local lines = wrap(sizechange[i], width)
        for j = 1, #lines do
            table.insert(displayLines, lines[j])
        end
    end
    y = 1
    local start = math.max(1, #displayLines - chatHeight + 1)
    for i = start, #displayLines do
        chat.setCursorPos(1, y)
        chat.write(displayLines[i])
        y = y + 1
    end
end


pcall(function()

    ws.receive()
    -- login
    term.redirect(parent)
    parent.clear()
    parent.setCursorPos(1, 1)
    -- auto login
    local username, password = apple()
    local saveaccount = username ~= nil and password ~= nil
    if not saveaccount then
        write("[L]ogin | [R]egister: ")
        local choice = read():lower()
        if choice ~= "l" and choice ~="r" and choice ~= "j" then
            print("wrong input twih")
            ws.close()
            return
        end
        if choice == "j" then
            print("im jacking you")
            ws.close()
            return
        end
        write("username: ")
        username = read()
        write("password: ")
        password = read(" ")
        if username:lower():find("jack") or password:lower():find("jack") then
            print("im jacking you.")
        end
        if choice == "r" then
            write("confirm password: ")
            password2 = read(" ")
            if password ~= password2 then
                print("have you tried matching them")
                ws.close()
                return
            end
            ws.send("register|" .. username .. "|" .. password .. "|\n")
        end
        if choice == "l" then
            ws.send("login|" .. username .. "|" .. password .. "|\n")
        end
    else
        ws.send("login|" .. username .. "|" .. password .. "|\n")
    end
    
    local response = ws.receive()
    if response and response:find("err|", 1, true) then
        print(response)
        ws.close()
        return
    end
    -- save to floppy
    if not saveaccount and response and response:find("ok|", 1, true) then
        accountsave(username, password)
    end

    parent.clear()
    parent.setCursorPos(1, 1)
    ws.send(
        "join|general|\n" ..
        "history|4000|\n"
    )

    parallel.waitForAny(
        function()
            while true do
                local data = ws.receive()
                if not data then
                    break
                end

                for message in (data .. "\n"):gmatch("(.-)\n") do
                    message = urldecoding(message:gsub("\r$", ""))
                    local username, content =
                    message:match("^msg|([^|]*)|([^|*]*)|$")
                if username and not muted[username] then
                    notification()
                    if username:match("^%[.*%]$") then
                        message = username .. " " .. content
                    else
                        message = "<" .. username .. "> " .. content
                    end
                    table.insert(sizechange, message)
                    if not motd then
                        local chatHeight = math.max(1, height - 1)
                        local lines = wrap(message, width)
                        for i = 1, #lines do
                            if y > chatHeight then
                                chat.scroll(1)
                                y = chatHeight
                            end
                            chat.setCursorPos(1, y)
                            chat.write(lines[i])
                            y = y + 1
                        end
                    end
                elseif message:sub(1, 5) == "motd|" or message:sub(1, 6) == "rules|" then
                    local content = message:match("^.-|(.-)|$")
                    motd = true
                    motdLines = wrap(content, width)
                    motdPage = 1
                    parent.clear()
                    for i = 1, height - 1 do
                        local line = motdLines[motdPage + i - 1]
                        if line then
                            parent.setCursorPos(1, i)
                            parent.write(line)
                        end
                    end
                    parent.setCursorPos(1, height)
                    if #motdLines > height - 1 then
                        write("press enter to continue")
                    else
                        write("press enter to go back")
                    end
                end
            end
        end
    end,
        
        function()
            while true do
                input.clear()
                input.setCursorPos(1, 1)
                term.redirect(input)
                local message = read()
                term.redirect(parent)
                if motd then
                    local pageHeight = height - 1
                    if motdPage + pageHeight - 1 < #motdLines then
                        motdPage = motdPage + pageHeight
                        parent.clear()
                        for i = 1, height - 1 do
                            local line = motdLines[motdPage + i - 1]
                            if line then
                                parent.setCursorPos(1, i)
                                parent.write(line)
                            end
                        end
                        parent.setCursorPos(1, height)
                        if motdPage + height - 2 < #motdLines then
                            write("press enter to continue")
                        else
                            write("press enter to go back")
                        end
                    else
                        motd = false
                        redraw()
                    end
                else
                -- commands
                -- rooms
                if message:sub(1, #prefix + 7) == "/" .. prefix .. "room #" then
                    room = message:sub(#prefix + 6)
                    ws.send("join|" .. room .. "|\nhistory|4000|\n")
                    y = 1
                    chat.clear()
                -- dms
                elseif message:sub(1, #prefix + 4) == "/" .. prefix .. "dm @" then
                    dm = message:sub(#prefix + 5)
                    ws.send("join|@" .. dm .. "|\n")
                    y = 1
                    chat.clear()                    
                -- muting
                elseif message:sub(1, #prefix + 7) == "/" .. prefix .. "mute @" then
                    local user = message:sub(#prefix + 8)
                    muted[user] = true
                    saveMuted()
                -- the opposite of muting
                elseif message:sub(1, #prefix + 9) == "/" .. prefix .. "unmute @" then
                    local user = message:sub(#prefix + 10)
                    muted[user] = nil
                    saveMuted()
                -- motd
                elseif message == "/" .. prefix .. "motd" then
                    ws.send("motd|\n")
                -- rules
                elseif message == "/" .. prefix .. "rules" then
                    ws.send("rules|\n")
                else
                    -- send normally if there's no commands matching
                    ws.send("msg|" .. message .. "|\n")
                end
            end    
        end
    end,

        -- monitor resize fix
        function()
            while true do
                local event = os.pullEvent()
                if event == "monitor_resize" or event == "term_resize" then
                    redraw()
                end
            end
        end
    )
end)

pcall(function()
    ws.close()
end)

term.redirect(parent)