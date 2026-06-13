-- Flat navigation environment: walk to the orange tower.
--
-- The world uses the `flat` mapgen, so no path ever requires jumping.
-- Vegetation (trees, bushes, grass) is planted once and persisted in the
-- world; the target tower and the player's look direction are randomized
-- on every episode. All cross-run state is recovered by scanning the
-- arena for nodes (no mod storage), so the mod is robust to the engine
-- exiting without flushing its databases.

if minetest.settings:has("fixed_map_seed") then
	math.randomseed(minetest.settings:get("fixed_map_seed"))
else
	math.randomseed(os.time())
end

local function rand(lower, greater)
	return lower + math.random() * (greater - lower)
end

local GROUND_Y = 4          -- top dirt_with_grass layer built by the superflat mod
local ARENA_RADIUS = 40     -- vegetation is planted inside this radius
local TARGET_MIN_DIST = 20  -- distance range of the target tower
local TARGET_MAX_DIST = 32
local TARGET_HEIGHT = 10  -- tall enough to rise above the tree canopy
local TARGET_RADIUS_SQ = 9.0  -- squared distance that counts as "reached"
local NUM_TREES = 22
local NUM_BUSHES = 10
local NUM_GRASS = 120

local target_pos = nil

local ARENA_MIN = { x = -ARENA_RADIUS - 2, y = GROUND_Y, z = -ARENA_RADIUS - 2 }
local ARENA_MAX = { x = ARENA_RADIUS + 2, y = GROUND_Y + 14, z = ARENA_RADIUS + 2 }

local function plant_vegetation()
	-- trees, keeping the spawn area and a minimum spacing free
	local placed = {}
	local attempts = 0
	while #placed < NUM_TREES and attempts < NUM_TREES * 30 do
		attempts = attempts + 1
		local ang = rand(0, 2 * math.pi)
		local r = rand(8, ARENA_RADIUS)
		local x = math.floor(r * math.cos(ang) + 0.5)
		local z = math.floor(r * math.sin(ang) + 0.5)
		local ok = true
		for _, p in ipairs(placed) do
			if (p.x - x) ^ 2 + (p.z - z) ^ 2 < 36 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(placed, { x = x, z = z })
			default.grow_tree({ x = x, y = GROUND_Y + 1, z = z }, math.random() < 0.3)
		end
	end

	for _ = 1, NUM_BUSHES do
		local ang = rand(0, 2 * math.pi)
		local r = rand(6, ARENA_RADIUS)
		local pos = {
			x = math.floor(r * math.cos(ang) + 0.5),
			y = GROUND_Y + 1,
			z = math.floor(r * math.sin(ang) + 0.5),
		}
		if minetest.get_node(pos).name == "air" then
			default.grow_bush(pos)
		end
	end

	for _ = 1, NUM_GRASS do
		local ang = rand(0, 2 * math.pi)
		local r = rand(2, ARENA_RADIUS)
		local pos = {
			x = math.floor(r * math.cos(ang) + 0.5),
			y = GROUND_Y + 1,
			z = math.floor(r * math.sin(ang) + 0.5),
		}
		if minetest.get_node(pos).name == "air" then
			minetest.set_node(pos, { name = "default:grass_" .. math.random(1, 5) })
		end
	end
end

local function place_target()
	-- sweep the arena for tower nodes from previous episodes or runs
	local old = minetest.find_nodes_in_area(ARENA_MIN, ARENA_MAX, "default:coral_orange")
	for _, pos in ipairs(old) do
		minetest.remove_node(pos)
	end

	local ang = rand(0, 2 * math.pi)
	local r = rand(TARGET_MIN_DIST, TARGET_MAX_DIST)
	target_pos = {
		x = math.floor(r * math.cos(ang) + 0.5),
		y = GROUND_Y + 1,
		z = math.floor(r * math.sin(ang) + 0.5),
	}
	for dy = 0, TARGET_HEIGHT - 1 do
		minetest.set_node(
			{ x = target_pos.x, y = target_pos.y + dy, z = target_pos.z },
			{ name = "default:coral_orange" }
		)
	end
end

reset_environment = function()
	local player = minetest.get_connected_players()[1]

	-- plant the forest only if the world doesn't have one yet
	local trees = minetest.find_nodes_in_area(ARENA_MIN, ARENA_MAX, "default:tree")
	if #trees == 0 then
		plant_vegetation()
	end

	place_target()

	player:set_pos({ x = 0, y = GROUND_Y + 1.5, z = 0 })
	player:set_look_horizontal(rand(0, 2 * math.pi))
	player:set_look_vertical(0)

	player:hud_set_flags({
		hotbar = false,
		crosshair = false,
		healthbar = false,
		chat = false,
	})
end

minetest.register_on_joinplayer(function(player, _last_login)
	minetest.set_timeofday(0.5)
	reset_environment()
end)

minetest.register_globalstep(function(dtime)
	local player = minetest.get_connected_players()[1]
	if player == nil or target_pos == nil then
		return
	end

	-- reset the environment if requested by the python interface
	if get_soft_reset() == 1 then
		reset_environment()
		reset_termination()
	end

	local player_pos = player:get_pos()
	local sq_dist = (target_pos.x - player_pos.x) ^ 2 +
		(target_pos.z - player_pos.z) ^ 2

	-- constant time pressure, the episode ends at the tower
	set_reward(-1.0)

	if sq_dist < TARGET_RADIUS_SQ then
		set_termination()
	end
end)
