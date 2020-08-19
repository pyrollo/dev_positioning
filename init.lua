
local contexts = {}
local mod_storage = minetest.get_mod_storage()
local positionings_store = minetest.deserialize(
		mod_storage:get_string("positionings"), true) or {}

local function load_positionings(player_name)
	return positionings_store[player_name] or {}
end

local function save_positionings(player_name, player_positionings)
	positionings_store[player_name] = player_positionings
	mod_storage:set_string("positionings", minetest.serialize(positionings_store))
end

local function set_positioning(player_name, positioning)
	local player = minetest.get_player_by_name(player_name)
	if not player then
		return
	end
	player:set_pos(positioning.pos)
	player:set_look_vertical(positioning.look_vertical)
	player:set_look_horizontal(positioning.look_horizontal)
end

local function get_positioning(player_name)
	local player = minetest.get_player_by_name(player_name)
	if not player then
		return
	end
	return {
			pos = player:get_pos(),
			look_vertical = player:get_look_vertical(),
			look_horizontal = player:get_look_horizontal(),
		}
end

local todeg = 180 / math.pi
local torad = math.pi / 180

local function fields_to_positioning(fields)
	local look_v = tonumber(fields.look_v)
	local look_h = tonumber(fields.look_h)
	local pos = { 
			x = tonumber(fields.pos_x),
			y = tonumber(fields.pos_y), 
			z = tonumber(fields.pos_z),
		}
	if look_v and look_h and pos.x and pos.y and pos.z then
		return {
			pos = pos,
			look_horizontal = look_h * torad,
			look_vertical = look_v * torad,
		}
	end
end

local function show_formspec(player_name)

	local context = contexts[player_name] or {}
	local positioning = get_positioning(player_name)
	local positioning_name = "New positioning"

	local list
	local index = 0
	for name, pos in pairs(load_positionings(player_name)) do
		list = list and list .. "," .. name or name
		index = index + 1
		if index == context.selected then
			positioning = pos
			positioning_name = name
		end
	end

	fs = "formspec_version[2]size[8.5,6]" ..
		"textlist[0.5,0.5;2,4;list;" .. list .. ";" .. (context.selected or 1) .. ";false]" ..
		"button[3,0.5;1,0.7;btn_save;Save]" ..
		"button[3,1.5;1,0.7;btn_delete;Delete]" ..
		"button[6,5;2,0.5;btn_apply;Apply to player]" ..
		"button_exit[3.5,5;2,0.5;btn_cancel;Close]" ..
		"field[4.5,0.5;3.5,0.5;name;Name;" .. positioning_name .. "]" ..
		"label[4.5,1.5;Position:]" ..
		("field[4.5,2;1.5,0.5;pos_x;X;%.3f]"):format(positioning.pos.x) ..
		("field[4.5,3;1.5,0.5;pos_y;Y;%.3f]"):format(positioning.pos.y) ..
		("field[4.5,4;1.5,0.5;pos_z;Z;%.3f]"):format(positioning.pos.z) ..
		"label[6.5,1.5;Look:]" ..
		("field[6.5,2;1.5,0.5;look_v;Vetical;%.3f]"):format(positioning.look_vertical * todeg) ..
		("field[6.5,3;1.5,0.5;look_h;Horizontal;%.3f]"):format(positioning.look_horizontal * todeg)
	
	if context.message then
		fs = fs .. "label[0.5,5;" .. context.message .. "]"
		context.message = nil
	end
	contexts[player_name] = context
	minetest.show_formspec(player_name, "dev_positioning", fs)
end


minetest.register_on_player_receive_fields(
	function(player, formname, fields)
		if formname ~= "dev_positioning" then
			return
		end
		print(dump(fields))
		
		local player_name = player:get_player_name()
		local context = contexts[player_name]
		if not context then
			minetest.log("error", "Suspicious fields received. Player:" .. player_name .. " Formspec:" .. formname)
			return
		end
		
		if fields.list then
			local event = minetest.explode_textlist_event(fields.list)
			if event.type == "CHG" then
				context.selected = event.index
				show_formspec(player_name)
			end
			return
		end
		
		if fields.btn_apply or fields.key_enter then
			local positioning = fields_to_positioning(fields)
			if positioning then
				set_positioning(player_name, positioning)
			else
				context.message = "Invalid positioning"
				show_formspec(player_name)
			end
			return
		end
		
		if fields.btn_save then
			local positioning = fields_to_positioning(fields)
			if not positioning then
				context.message = "Invalid positioning"
				show_formspec(player_name)
				return
			end
			if not fields.name or fields.name == "" then
				context.message = "Please enter a name"
				show_formspec(player_name)
				return
			end
			local positionings = load_positionings(player_name)
			positionings[fields.name] = get_positioning(player_name)
			save_positionings(player_name, positionings)
			show_formspec(player_name)	
			return
		end

		if fields.btn_delete and context.selected then
			local index = 0
			local positionings = load_positionings(player_name)
			for name, _ in pairs(positionings) do
				index = index + 1
				if index == context.selected then
					positionings[name] = nil
					save_positionings(player_name, positionings)
					show_formspec(player_name)
					return
				end
			end
			return
		end
	end)

minetest.register_chatcommand("devpos",
    {
        params = "<action> <name>",  
        description = "load/save/list/delete current player positioning. <action> is load/save/list/delete, <name> is the name of the saved positioning",
--        privs = {dev=true},
        func = function(player_name, param)
			local action, name = param:match("([^ ]+)[ ]*(.*[^ ])")
			if not action or action == "" then
				show_formspec(player_name)
				return true
			end

			if action == "list" then
				local positionings = load_positionings(player_name)
				minetest.chat_send_player(player_name, "Saved positionings:")
				for name, _ in pairs(positionings) do
					minetest.chat_send_player(player_name, name)
				end
				return true
			end

			if action ~= "save" and action ~= "load" and action ~= "delete" then
				return false, "\""..action.."\" is not a valid action."
			end

			if action == "save" then
				local positionings = load_positionings(player_name)
				if positionings[name] then
					return false, "A positioning named \"" .. name .. "\" already exists."
				end
				positionings[name] = get_positioning(player_name)
				save_positionings(player_name, positionings)		
				return true, "Positioning saved as \"" .. name .. "\"."
			end
			
			if action == "load" then
				local positionings = load_positionings(player_name)
				if not positionings[name] then
					return false, "No positioning named \"" .. name .. "\" saved."
				end
				set_positioning(player_name, positionings[name])
				return true, "Positioning \"" .. name .. "\" restored."
			end

			if action == "delete" then
				local positionings = load_positionings(player_name)
				if not positionings[name] then
					return false, "No positioning named \"" .. name .. "\" saved."
				end
				positionings[name] = nil
				save_positionings(player_name, positionings)
				return true, "Positioning \"" .. name .. "\" deleted."
			end
		end
    })
    
