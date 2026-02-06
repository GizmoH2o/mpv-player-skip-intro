local opts = require "mp.options"
local msg = require "mp.msg"

-- Options that can be loaded from .conf
local user_options = {
    skip_chapter = true,
	absolute_intro_skip = true,
    op_patterns = "OP|[Oo]pening$|^[Oo]pening:|[Oo]pening [Cc]redits",
    other_patterns = "",
    ed_patterns = "ED|[Ee]nding$|^[Ee]nding:|[Ee]nding [Cc]redits|[Cc]redits"
}

opts.read_options(user_options, "skip_intro")

-- Helper: split "a|b|c" into {"a","b","c"}
local function split_patterns(str)
    local t = {}
    for pattern in string.gmatch(str, "[^|]+") do
        table.insert(t, pattern)
    end
    return t
end

local patterns = {
    op_patterns = split_patterns(user_options.op_patterns),
    other_patterns = split_patterns(user_options.other_patterns),
    ed_patterns = split_patterns(user_options.ed_patterns)
}

---------------------------------------------------------------------
-- Helper: Show Netflix-style OSD
---------------------------------------------------------------------
local function prompt_msg(text, duration)
    local props = {
        "osd-font-size", "osd-color", "osd-background", "osd-back-color",
        "osd-border-color", "osd-shadow-offset", "osd-shadow-color",
        "osd-align-x", "osd-align-y", "osd-margin-x", "osd-margin-y"
    }

    local saved = {}
    for _, p in ipairs(props) do
        saved[p] = mp.get_property(p)
    end

    mp.set_property("osd-font-size", "25")
    mp.set_property("osd-color", "#FFFFFF")
    mp.set_property("osd-background", "3")
    mp.set_property("osd-back-color", "#00000080")
    mp.set_property("osd-border-color", "#000000")
    mp.set_property("osd-shadow-offset", "2")
    mp.set_property("osd-shadow-color", "#000000")
    mp.set_property("osd-align-x", "right")
    mp.set_property("osd-align-y", "bottom")
    mp.set_property("osd-margin-x", "30")
    mp.set_property("osd-margin-y", "110")

    mp.commandv("show-text", text, duration)

    mp.add_timeout(duration, function()
        for p, val in pairs(saved) do
            mp.set_property(p, val)
        end
    end)
end

---------------------------------------------------------------------
-- Chapter checking logic
---------------------------------------------------------------------
local function check_chapter(_, chapter)
    if not user_options.skip_chapter or not chapter then return end

    local chapters = mp.get_property_native("chapter-list") or {}

    local intro_count = 0
    for _, c in ipairs(chapters) do
        if c.title and (c.title:match("[Ii]ntro") or
            (function()
                for _, p in ipairs(patterns.op_patterns) do
                    if c.title:match(p) then return true end
                end
            end)()) then
            intro_count = intro_count + 1
        end
    end

    local function skip_current(label)
        mp.commandv('no-osd', 'add', 'chapter', 1)
        prompt_msg(label, 2000)
    end

    if chapter:match("[Ii]ntro") and intro_count == 1 and user_options.absolute_intro_skip then -- When only intro is found in the chapter list
        skip_current("Skipped Intro")
        return
    end

    for _, p in ipairs(patterns.op_patterns) do
        if chapter:match(p) then
            skip_current("Skipped Intro")
            return
        end
    end

    for _, p in ipairs(patterns.other_patterns) do
        if chapter:match(p) then
            skip_current("Skipped " .. chapter)
            return
        end
    end

    for _, p in ipairs(patterns.ed_patterns) do
        if chapter:match(p) then
            skip_current("Skipped Credits")
            return
        end
    end
end

---------------------------------------------------------------------
-- Updates chapter title checking
---------------------------------------------------------------------
local function update_chapter_title()
    if not user_options.skip_chapter then return end -- respect toggle

    local chapter_index = mp.get_property_number("chapter")
    if chapter_index and chapter_index >= 0 then
        local chapters = mp.get_property_native("chapter-list")
        if chapters and chapters[chapter_index + 1] then
            local title = chapters[chapter_index + 1].title or ""
            if title ~= "" then
                check_chapter(nil, title)
            end
        end
    end
end

---------------------------------------------------------------------
-- Timer + toggle logic
---------------------------------------------------------------------
local periodic = mp.add_periodic_timer(10, update_chapter_title)
if not user_options.skip_chapter then
    periodic:stop() -- respect initial .conf setting
end

local function toggle_skip()
    user_options.skip_chapter = not user_options.skip_chapter
    mp.set_property_native("user-data/skip_chapters", user_options.skip_chapter)

    if user_options.skip_chapter then
        periodic:resume()
    else
        periodic:stop()
    end

    prompt_msg("Skip chapters: " .. (user_options.skip_chapter and "ON" or "OFF"), 1500)
end

--------------------------------------------------------------------- 
-- Initialize the property 
--------------------------------------------------------------------- 
mp.set_property_native("user-data/skip_chapters", user_options.skip_chapter)

---------------------------------------------------------------------
-- Menu registration + keybind
---------------------------------------------------------------------
mp.register_script_message("toggle-skip-chapters", toggle_skip)
mp.add_key_binding("ctrl+w", "toggle-skip-chapters", toggle_skip)

---------------------------------------------------------------------
-- Always observe chapter property
---------------------------------------------------------------------
mp.observe_property("chapter", "number", function()
    update_chapter_title()
end)
