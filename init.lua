dofile(minetest.get_modpath("rifts_by_artifoxer") .. "/crafts.lua")

local player_rifts = {}

local function remove_rift(pos, rift_name)
    if pos then
        if minetest.get_node(pos).name == rift_name then
            minetest.remove_node(pos)
        end
    end
end

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    if player_rifts[name] then
        remove_rift(player_rifts[name].green, "rifts_by_artifoxer:green_rift")
        remove_rift(player_rifts[name].blue, "rifts_by_artifoxer:blue_rift")
        player_rifts[name] = nil
    end
end)

minetest.register_tool("rifts_by_artifoxer:riftgun", {
    description = "let's hope this goes well (rift gun)",
    inventory_image = "riftgun.png",
    range = 100,

    on_use = function(itemstack, user, pointed_thing)
        if pointed_thing.type == "node" then
            local under = pointed_thing.under
            local above = pointed_thing.above
            local direction = vector.subtract(above, under)
            local name = user:get_player_name()

            if player_rifts[name] == nil then
                player_rifts[name] = {}
            end

            remove_rift(player_rifts[name].green, "rifts_by_artifoxer:green_rift")

            minetest.set_node(above, {
                name = "rifts_by_artifoxer:green_rift",
                param2 = minetest.dir_to_wallmounted(direction)
            })

            player_rifts[name].green = above
        end
    end,

    on_place = function(itemstack, user, pointed_thing)
        if pointed_thing.type == "node" then
            local under = pointed_thing.under
            local above = pointed_thing.above
            local direction = vector.subtract(above, under)
            local name = user:get_player_name()

            if player_rifts[name] == nil then
                player_rifts[name] = {}
            end

            remove_rift(player_rifts[name].blue, "rifts_by_artifoxer:blue_rift")

            minetest.set_node(above, {
                name = "rifts_by_artifoxer:blue_rift",
                param2 = minetest.dir_to_wallmounted(direction)
            })

            player_rifts[name].blue = above
        end
    end,
})

minetest.register_node("rifts_by_artifoxer:green_rift", {
    description = "Let's go. In and out, 20 minutes adventure",
    drawtype = "mesh",
    mesh = "green_rift.obj",
    tiles = {"green_rift.png"},
    paramtype = "light",
    paramtype2 = "wallmounted",
    use_texture_alpha = "blend",
    backface_culling = false,
    walkable = false,
    light_source = 12,
})

minetest.register_node("rifts_by_artifoxer:blue_rift", {
    description = "same thing, but blue",
    drawtype = "mesh",
    mesh = "blue_rift.obj",
    tiles = {"blue_rift.png"},
    paramtype = "light",
    paramtype2 = "wallmounted",
    use_texture_alpha = "blend",
    backface_culling = false,
    walkable = false,
    light_source = 12,
})

minetest.register_chatcommand("clear_rifts", {
    description = "Remove all your rifts",
    privs = {},
    func = function(name)
        if player_rifts[name] then
            remove_rift(player_rifts[name].green, "rifts_by_artifoxer:green_rift")
            remove_rift(player_rifts[name].blue, "rifts_by_artifoxer:blue_rift")
            player_rifts[name] = nil
            return true, "Rifts cleared."
        end
        return true, "No rifts found."
    end
})

minetest.register_on_player_hpchange(function(player, hp_change, reason)
    if hp_change < 0 and reason.type == "fall" then
        local name = player:get_player_name()
        if player_rifts[name] then
            local pos = player:get_pos()
            if player_rifts[name].green and vector.distance(pos, player_rifts[name].green) < 2 then
                return 0
            end
            if player_rifts[name].blue and vector.distance(pos, player_rifts[name].blue) < 2 then
                return 0
            end
        end
    end
    return hp_change
end, true)

local ARRIVAL_COOLDOWN = 1.8
local EXIT_OFFSET = 1.1
local arrival_immunity = {}

-- Get portal facing direction
local function get_portal_normal(pos)
    local node = minetest.get_node(pos)
    if not node or node.name == "air" or node.name == "ignore" then
        return vector.new(0, 1, 0)
    end
    return minetest.wallmounted_to_dir(node.param2) or vector.new(0, 1, 0)
end

-- Check if player is inside portal area
local function is_touching_portal(player_pos, portal_pos, normal)
    local rel = vector.subtract(player_pos, portal_pos)
    local depth = vector.dot(rel, normal)

    if depth < -0.5 or depth > 1.8 then
        return false
    end

    local planar = vector.subtract(rel, vector.multiply(normal, depth))
    return vector.length(planar) < 1.3
end

-- CLEAN teleport (NO velocity math)
local function do_teleport(player, from_pos, to_pos)
    local name = player:get_player_name()
    local now = minetest.get_us_time() / 1e6

    -- cooldown check
    local immun = arrival_immunity[name]
    if immun and immun.portal and vector.distance(immun.portal, from_pos) < 0.01 then
        if (now - immun.time) < ARRIVAL_COOLDOWN then
            return
        end
    end

    local to_normal = get_portal_normal(to_pos)

    -- place player outside exit portal
    local exit_pos = vector.add(
        to_pos,
        vector.multiply(to_normal, EXIT_OFFSET)
    )

    player:set_pos(exit_pos)

    -- STOP ALL MOMENTUM (prevents slam)
    player:set_velocity({x = 0, y = 0, z = 0})

    -- Face outward from portal
    local yaw = minetest.dir_to_yaw(to_normal)

    minetest.after(0, function()
        local p = minetest.get_player_by_name(name)
        if p then
            p:set_look_horizontal(yaw)
            p:set_look_vertical(0)
        end
    end)

    arrival_immunity[name] = {
        portal = vector.new(to_pos),
        time = now
    }
end

-- cleanup on leave
minetest.register_on_leaveplayer(function(player)
    arrival_immunity[player:get_player_name()] = nil
end)

-- main loop
minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local data = player_rifts[name]

        if data and data.green and data.blue then
            local pos = player:get_pos()

            local g_norm = get_portal_normal(data.green)
            local b_norm = get_portal_normal(data.blue)

            -- green → blue
            if is_touching_portal(pos, data.green, g_norm) then
                do_teleport(player, data.green, data.blue)
                break
            end

            -- blue → green
            if is_touching_portal(pos, data.blue, b_norm) then
                do_teleport(player, data.blue, data.green)
                break
            end
        end
    end
end)



-- recipes

-- rift core
minetest.register_craftitem("rifts_by_artifoxer:rift_core", {
	description = "rift core",
	inventory_image = "rift_core.png",
})

minetest.register_craft({
	output = "rifts_by_artifoxer:rift_core",
	recipe = {
		{"default:steel_ingot", "default:mese_crystal", "default:steel_ingot"},
		{"default:mese_crystal", "default:diamond", "default:mese_crystal"},
		{"default:steel_ingot", "default:mese_crystal", "default:steel_ingot"},
	}
})

-- rift destabilizer

minetest.register_craftitem("rifts_by_artifoxer:rift_destabilizer", {
	description = "rift_destabilizer",
	inventory_image = "rift_destabilizer.png",
})

minetest.register_craft({
	output = "rifts_by_artifoxer:rift_destabilizer",
	recipe = {
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
		{"default:mese_crystal", "default:obsidian_shard", "default:mese_crystal"},
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
	}
})

-- rift gun

minetest.register_craft({
    output = "rifts_by_artifoxer:riftgun",
    recipe = {
        {"default:copper_ingot", "default:copper_ingot", ""},
        {"rifts_by_artifoxer:rift_destabilizer", "rifts_by_artifoxer:rift_core", "default:steel_ingot"},
        {"", "default:copper_ingot", "default:copper_ingot"},
    }
})
