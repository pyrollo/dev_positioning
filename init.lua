
local todeg = 180 / math.pi
local torad = math.pi / 180

local contexts = {}

local mod_storage = minetest.get_mod_storage()
local saved_positionings = minetest.deserialize(
	mod_storage:get_string("positionings"), true) or {}

local function get_positionings(player_name)
	return saved_positionings[player_name] or {}
end

local function save_positionings(player_name, player_positionings)
	saved_positionings[player_name] = player_positionings
	mod_storage:set_string("positionings", minetest.serialize(saved_positionings))
end

local function list_positionings(player_name)
	local result = {}
	for name, _ in pairs(get_positionings(player_name)) do
		result[#result + 1] = name
	end
	
	table.sort(result)
	return result
end

local function set_player_positioning(player_name, positioning)
	local player = minetest.get_player_by_name(player_name)
	if not player then
		return
	end
	player:set_pos({
		x = positioning.pos_x,
		y = positioning.pos_y,
		z = positioning.pos_z,
	})
	player:set_look_vertical(positioning.look_v * torad)
	player:set_look_horizontal(positioning.look_h * torad)
	player:set_fov(positioning.fov)
end

local function get_player_positioning(player_name)
	local player = minetest.get_player_by_name(player_name)
	if not player then
		return
	end
	local pos = player:get_pos()
	local fov = player:get_fov()
	if fov == 0 then
		fov = minetest.settings:get("fov")
	end
	return {
			pos_x = pos.x,
			pos_y = pos.y,
			pos_z = pos.z,
			look_v = player:get_look_vertical() * todeg,
			look_h = player:get_look_horizontal() * todeg,
			fov = fov,
		}
end


local positioning_fields = {
	{ name = "pos_x",  label = "X",        step = 0.5, format = ".3f"},
	{ name = "pos_y",  label = "Y",        step = 0.5, format = ".3f"},
	{ name = "pos_z",  label = "Z",        step = 0.5, format = ".3f"},
	{ name = "look_v", label = "Vertical", step = 5.0, format = ".1f", min = -90, max = 90},
	{ name = "look_h", label = "Horiz.",   step = 5.0, format = ".1f"},
	{ name = "fov",    label = "FOV",      step = 5.0, format = ".1f", min = 45, max = 180},
}

local function fields_to_positioning(fields)

	local positioning = {}
	
	for _, field in ipairs(positioning_fields) do
		positioning[field.name] = tonumber(fields[field.name])
		if not positioning[field.name] then
			return
		end
	end
	
	return positioning
end

local function show_formspec(player_name)

	local positioning = get_player_positioning(player_name)
	local context = contexts[player_name] or 
		{ current_positioning = positioning }
	context.positionings = list_positionings(player_name)

	local list = "<current>"
	for _, name in pairs(context.positionings) do
		list = list .. "," .. name or name
	end

	local fs = "formspec_version[3]"..
		"size[15,12]" ..
		"no_prepend[]" ..
		"bgcolor[black;neither;black]" ..

		"container[0,0]"..
		"box[0,0;3,7;#00000040]"..
		"label[0.2,0.4;Saved positionings]"..
		"textlist[0.2,0.7;2.6,3;list;" .. list .. ";" .. (context.selected or 1) .. ";false]" ..
		"button[0.2,4;2.6,0.7;btn_delete;Delete selected]" ..
		"field[0.2,5.3;2.6,0.5;name;Save positioning as;]" .. 
		"button[0.2,6;2.6,0.7;btn_save;Save]" ..
		"container_end[]"..

		"container[2.25,9.8]"..
		"box[0,0;10.5,2.2;#00000040]"..
		"container[0.2,0.4]"..
		"label[0,0;Position:]" ..
		"label[4.5,0;Look:]"

	local x = 0
	for _, field in ipairs(positioning_fields) do
		fs = fs ..
			("field[%.1f,0.5;1.4,0.5;%s;%s;%".. field.format .."]")
				:format(x, field.name, field.label, positioning[field.name]) ..
			("button[%.1f,1.1;0.5,0.5;btn_%s_dec;-]"):format(x, field.name) ..
			("button[%.1f,1.1;0.5,0.5;btn_%s_inc;+]"):format(x + 0.9, field.name)
		x = x + 1.5
	end

	fs = fs ..
		("button[%.1f,0.5;1,0.5;btn_apply;Apply]"):format(x) ..
		"container_end[]" ..
		"container_end[]"

	if context.message then
		fs = fs ..
			"container[3.5,8]"..
			"box[0,0;8,1;#80000040]"..
			"label[1,0.5;" .. context.message .. "]" ..
			"container_end[]"

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

		local player_name = player:get_player_name()

		if fields.quit and not fields.key_enter then
			contexts[player_name] = nil
			minetest.close_formspec(player_name, formname)
			return
		end

		if not minetest.check_player_privs(player_name, {server=true}) then
			minetest.log("error", "Suspicious fields received. Player:" ..
					player_name .. " Formspec:" .. formname .. " (missing privilege).")
			minetest.close_formspec(player_name, formname)
			return
		end

		local context = contexts[player_name]
		
		if not context then
			minetest.log("error", "Suspicious fields received. Player:" .. 
					player_name .. " Formspec:" .. formname .. " (no context found).")
			minetest.close_formspec(player_name, formname)
			return
		end
		
		local positioning = fields_to_positioning(fields)
		if not positioning then
			context.message = "Invalid positioning"
			show_formspec(player_name)
			return
		end

		if fields.list then
			local event = minetest.explode_textlist_event(fields.list)
			if event.type == "CHG" then
				context.selected = event.index
				if context.selected == 1 then
					positioning = context.current_positioning
				else
					local positionings = get_positionings(player_name)
					positioning = positionings[context.positionings[context.selected - 1]]
				end
				if positioning then
					set_player_positioning(player_name, positioning)
					show_formspec(player_name)
				end
			end
			return
		end
			
		if fields.btn_save then
			if not fields.name or fields.name == "" then
				context.message = "Please enter a name"
				show_formspec(player_name)
				return
			end
			-- TODO : Add warning if name exists
			local positionings = get_positionings(player_name)
			positionings[fields.name] = positioning
			save_positionings(player_name, positionings)
			show_formspec(player_name)	
			return
		end

		if fields.btn_delete and context.selected then
			local positionings = get_positionings(player_name)
			if context.positionings[context.selected - 1] then
				positionings[context.positionings[context.selected - 1]] = nil
				save_positionings(player_name, positionings)
				context.selected = 1
				show_formspec(player_name)
			end
			return
		end

		for _, field in ipairs(positioning_fields) do
			local value = math.floor(positioning[field.name] 
					/ field.step + 0.5) * field.step
			if fields["btn_".. field.name .."_dec"] then
				positioning[field.name] = value - field.step
				if field.min and positioning[field.name] < field.min then
					positioning[field.name] = field.min
				end
			end
			if fields["btn_".. field.name .."_inc"] then
				positioning[field.name] = value + field.step
				if field.max and positioning[field.name] > field.max then
					positioning[field.name] = field.max
				end
			end
		end
		set_player_positioning(player_name, positioning)
		show_formspec(player_name)
	end)

minetest.register_chatcommand("devpos",
    {
        params = "<action> <name>",  
        description = "load/save/list/delete current player positioning. <action> is load/save/list/delete, <name> is the name of the saved positioning",
        privs = { server=true },
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
    
