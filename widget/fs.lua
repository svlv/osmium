--[[

     Licensed under GNU General Public License v2
      * (c) 2018, Uli Schlacter
      * (c) 2018, Otto Modinos
      * (c) 2013, Luca CPZ

--]]

local helpers    = require("lain.helpers")
local Gio        = require("lgi").Gio
local focused    = require("awful.screen").focused
local wibox      = require("wibox")
local naughty    = require("naughty")
local math       = math
local string     = string
local tconcat    = table.concat
local type       = type
local tonumber   = tonumber
local query_size = Gio.FILE_ATTRIBUTE_FILESYSTEM_SIZE
local query_free = Gio.FILE_ATTRIBUTE_FILESYSTEM_FREE
local query_used = Gio.FILE_ATTRIBUTE_FILESYSTEM_USED
local query      = query_size .. "," .. query_free .. "," .. query_used

-- File systems info
-- lain.widget.fs

local function factory(args)
    local fs = {
        widget = wibox.widget.textbox(),
        units = {
            [1] = "KB", [2] = "MB", [3] = "GB",
            [4] = "TB", [5] = "PB", [6] = "EB",
            [7] = "ZB", [8] = "YB"
        }
    }

    function fs.hide()
        if not fs.notification then return end
        naughty.destroy(fs.notification)
        fs.notification = nil
    end

    function fs.show(seconds, scr)
        fs.hide(); fs.update()
        fs.notification_preset.screen = fs.followtag and focused() or scr or 1
        fs.notification = naughty.notify {
            preset  = fs.notification_preset,
            timeout = type(seconds) == "number" and seconds or 5
        }
    end

    local args      = args or {}
    local timeout   = args.timeout or 600
    local partition = args.partition
    local threshold = args.threshold or 99
    local showpopup = args.showpopup or "on"
    local settings  = args.settings or function() end

    fs.followtag           = args.followtag or false
    fs.notification_preset = args.notification_preset

    if not fs.notification_preset then
        fs.notification_preset = {
            font = "Monospace 10",
            fg   = "#FFFFFF",
            bg   = "#000000"
        }
    end

    function fs.update()
        local notifytable = { [1] = string.format("%-10s %4s\t%6s\t%6s\t", "path", "used", "free", "size") }
        local pathlen = 10
        local maxpathidx = 1
        fs_now = {}

        for _, mount in ipairs(Gio.unix_mounts_get()) do
            local path = Gio.unix_mount_get_mount_path(mount)
            local root = Gio.File.new_for_path(path)
            local info = root:query_filesystem_info(query)

            if info then
                local size = info:get_attribute_uint64(query_size)
                local used = info:get_attribute_uint64(query_used)
                local free = info:get_attribute_uint64(query_free)

                if size > 0 then
                    local units = math.floor(math.log(size)/math.log(1024))

                    fs_now[path] = {
                        units      = fs.units[units],
                        percentage = math.floor(100 * used / size), -- used percentage
                        size       = size / math.pow(1024, math.floor(units)),
                        used       = used / math.pow(1024, math.floor(units)),
                        free       = free / math.pow(1024, math.floor(units))
                    }

                    if fs_now[path].percentage > 0 then -- don't notify unused file systems
                        notifytable[#notifytable+1] = string.format("\n%-10s %3s%%\t%6.2f\t%6.2f\t%s", path,
                        math.floor(fs_now[path].percentage), fs_now[path].free, fs_now[path].size,
                        fs_now[path].units)

                        if #path > pathlen then
                            pathlen = #path
                            maxpathidx = #notifytable
                        end
                    end
                end
            end
        end

        widget = fs.widget
        settings()

        if partition and fs_now[partition] and fs_now[partition].percentage >= threshold then
            if not helpers.get_map(partition) then
                naughty.notify {
                    preset = naughty.config.presets.critical,
                    title  = "Warning",
                    text   = string.format("%s is above %d%% (%d%%)", partition, threshold, fs_now[partition].percentage)
                }
                helpers.set_map(partition, true)
            else
                helpers.set_map(partition, false)
            end
        end

        if pathlen > 10 then -- if are there paths longer than 10 chars, reformat first column accordingly
            local pathspaces
            for i = 1, #notifytable do
                pathspaces = notifytable[i]:match("[ ]+")
                if i ~= maxpathidx and pathspaces then
                    notifytable[i] = notifytable[i]:gsub(pathspaces, pathspaces .. string.rep(" ", pathlen - 10))
                end
            end
        end

        fs.notification_preset.text = tconcat(notifytable)
    end

    if showpopup == "on" then
       fs.widget:connect_signal('mouse::enter', function () fs.show(0) end)
       fs.widget:connect_signal('mouse::leave', function () fs.hide() end)
    end

    helpers.newtimer(partition or "fs", timeout, fs.update)

    return fs
end

return factory
