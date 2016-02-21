-- Minetest mod "Sheriff voting"
-- Allows players to vote to elect sheriff, who can defend them from griefers.

--This library is free software; you can redistribute it and/or
--modify it under the terms of the GNU Lesser General Public
--License as published by the Free Software Foundation; either
--version 2.1 of the License, or (at your option) any later version.

sheriff_voting={}
sheriff_voting.vote_needed=8;  --needed votes
sheriff_voting.formspec_buffer={}
sheriff_voting.candidate_by_name={}

sheriff_voting.mute_by_name={}	--player name => sheriff name

sheriff_voting.filename = minetest.get_worldpath() .. "/sheriff_voting_by_name.txt"

function sheriff_voting:save()
    local datastring = minetest.serialize(self.candidate_by_name)
    if not datastring then
        return
    end
    local file, err = io.open(self.filename, "w")
    if err then
        return
    end
    file:write(datastring)
    file:close()
end

function sheriff_voting:load()
    local file, err = io.open(self.filename, "r")
    if err then
        self.candidate_by_name = {}
        return
    end
    self.candidate_by_name = minetest.deserialize(file:read("*all"))
    if type(self.candidate_by_name) ~= "table" then
        self.candidate_by_name = {}
    end
    file:close()
end

sheriff_voting:load();

--every restart - decrease vote result
--also allows people to vote again
for key, val in pairs(sheriff_voting.candidate_by_name) do
	val.ip_voters={}
    if val.votes > 30 then
        val.votes = val.votes - math.floor(val.votes/10);   -- 10% off to prevent creation of "untouchable" sheriff
    elseif val.votes < -30 then
        val.votes = val.votes + math.floor(math.abs(val.votes)/10);  --at least a little hope to not be demoted eternally
    elseif val.votes > 0 then
        val.votes = val.votes - 1;
    elseif val.votes < 0 then
        val.votes = val.votes + 1;
	else
		sheriff_voting.candidate_by_name[key] = nil;
    end
	
end

sheriff_voting.after_place_node = function(pos, placer)
    if placer and placer:is_player() then
        local node = minetest.get_node(pos);
        local meta = minetest.get_meta(pos);
        local description = "Specify player name for sheriff candidate";
        local player_name = placer:get_player_name();
        meta:set_string("infotext", description);
        meta:set_string("owner", player_name);
        meta:set_string("formspec", "size[6,3;]"
            .."label[0,0;Write player name to vote sheriff:]"
            .."field[1,1;3,1;candidate;;]"
            .."button_exit[0,2;2,0.5;save;OK]");
    end
end

sheriff_voting.receive_config_fields = function(pos, formname, fields, sender)
    local node = minetest.get_node(pos);
    local meta = minetest.get_meta(pos);
    local candidate_name = tostring(fields.candidate);
    local player_name = sender:get_player_name();
    local description = "Vote for <".. candidate_name .."> to become sheriff until the end of the day. Click with gold bar to vote.";
    if fields.candidate and player_name and candidate_name~="" then
        meta:set_string("infotext", description);
        meta:set_string("owner", nil);
        meta:set_string("formspec", nil);
        meta:set_string("candidate", candidate_name);
        sheriff_voting.register_vote(player_name, candidate_name, pos);
    end
end

sheriff_voting.on_rightclick = function(pos, node, player, itemstack, pointed_thing)
    local meta = minetest.get_meta(pos);
    local candidate_name = meta:get_string("candidate");
    local player_name = player:get_player_name();
    if itemstack:get_name()=="default:gold_ingot" and candidate_name then
		sheriff_voting.register_vote(player_name, candidate_name, pos);
		
		itemstack:take_item();
		
        local formspec = "size[6,3;]"..
            "label[0,0;Vote to promote player <".. candidate_name .."> as sheriff?]"..
            "button_exit[0,1;2,0.5;confirm;Yes, trust him.]"..
            "button_exit[3,1;3,0.5;cancel;No, <".. candidate_name .."> is bad.]"..
            "button_exit[1,2;3,0.5;cancel2;No, <".. candidate_name .."> is fearsome.]";
        sheriff_voting.formspec_buffer[player_name] = {candidate=candidate_name, pos=pos};
        minetest.show_formspec(player_name, "sheriff_voting:vote", formspec)
    elseif candidate_name then
        minetest.chat_send_player(player_name, "Use gold ingot for voting. (Ingot will be consumed)");
    end
end

sheriff_voting.on_voting = function(player, formname, fields)
    if formname=="sheriff_voting:vote" and player:is_player() then
        local player_name = player:get_player_name();
        local candidate_name = sheriff_voting.formspec_buffer[player_name].candidate;
        local player_ip = minetest.get_player_ip( player_name );
        if candidate_name and sheriff_voting.candidate_by_name[candidate_name].ip_voters[player_ip] then
            local votes_result = sheriff_voting.candidate_by_name[candidate_name].votes;
            minetest.chat_send_player( player_name, "Already voted! Result:"..votes_result.." of ".. sheriff_voting.vote_needed );
        elseif candidate_name and sheriff_voting.candidate_by_name[candidate_name] then
            if fields.confirm then
                sheriff_voting.candidate_by_name[candidate_name].ip_voters[player_ip] = "voted";
                
                local votes_result = sheriff_voting.candidate_by_name[candidate_name].votes + 1;
                sheriff_voting.candidate_by_name[candidate_name].votes = votes_result;
                minetest.chat_send_all("Voted by <"..player_name.."> to  promote <"..candidate_name..">. Result:"..votes_result.." of ".. sheriff_voting.vote_needed);
                minetest.log("action", "Voted by <"..player_name.."> to  promote <"..candidate_name..">. Result:"..votes_result.." of ".. sheriff_voting.vote_needed);
                if votes_result == sheriff_voting.vote_needed then
                    minetest.chat_send_all("Player <"..candidate_name.."> now has sheriff powers." );
                end
            elseif fields.cancel then
                sheriff_voting.candidate_by_name[candidate_name].ip_voters[player_ip] = "voted";
                
                local votes_result = sheriff_voting.candidate_by_name[candidate_name].votes - 1;
                sheriff_voting.candidate_by_name[candidate_name].votes = votes_result;
                minetest.chat_send_all("Voted by <"..player_name.."> to demote <"..candidate_name..">. Result:"..votes_result.." of ".. sheriff_voting.vote_needed);
                minetest.log("action", "Voted by <"..player_name.."> to demote <"..candidate_name..">. Result:"..votes_result.." of ".. sheriff_voting.vote_needed);
                if votes_result == (sheriff_voting.vote_needed-1) then
                    minetest.chat_send_all("Player <"..candidate_name.."> is no longer sheriff." );
                    
                    --Unmute all victims of old sheriff
                    for key, val in pairs(sheriff_voting.mute_by_name) do
                        if val == candidate_name then
                            sheriff_voting.mute_by_name[key] = nil;
                        end
                    end
                    
                end
            elseif fields.cancel2 then
                sheriff_voting.candidate_by_name[candidate_name].ip_voters[player_ip] = "voted";
                
                local votes_result = sheriff_voting.candidate_by_name[candidate_name].votes - 1;
                sheriff_voting.candidate_by_name[candidate_name].votes = votes_result;
                minetest.chat_send_all("Voted by scared player to demote <"..candidate_name..">. Result:"..votes_result.." of ".. sheriff_voting.vote_needed);
                minetest.log("action", "Voted by <"..player_name.."> to demote <"..candidate_name..">. Result:"..votes_result.." of ".. sheriff_voting.vote_needed);
                if votes_result == (sheriff_voting.vote_needed-1) then
                    minetest.chat_send_all("Player <"..candidate_name.."> is no longer sheriff." );
                    
                    --Unmute all victims of old sheriff
                    for key, val in pairs(sheriff_voting.mute_by_name) do
                        if val == candidate_name then
                            sheriff_voting.mute_by_name[key] = nil;
                        end
                    end
                    
                end
            end
            sheriff_voting:save();
        end
    end
end

sheriff_voting.register_vote = function(player_name, candidate_name, pos)
    if candidate_name then
        if not sheriff_voting.candidate_by_name[candidate_name] then
            sheriff_voting.candidate_by_name[candidate_name]={};
            sheriff_voting.candidate_by_name[candidate_name].votes=0;
            sheriff_voting.candidate_by_name[candidate_name].ip_voters={};
			sheriff_voting.candidate_by_name[candidate_name].action_delay=0;
        end
		minetest.chat_send_all("Voting <"..candidate_name.."> to be sheriff. Come to "..minetest.pos_to_string(pos));
    end
end

sheriff_voting.vote = function(player_name, candidate_name)

end

sheriff_voting.unvote = function(player_name, candidate_name)

end

minetest.register_on_player_receive_fields( sheriff_voting.on_voting );

minetest.register_node("sheriff_voting:table", {
	description = "Voting table",
	tiles = {"sheriff_voting_top.png", "sheriff_voting.png"},
	is_ground_content = false,
	groups = {cracky=3,level=3,disable_jump=1},
    is_ground_content = false,
    after_place_node = sheriff_voting.after_place_node,
    on_receive_fields = sheriff_voting.receive_config_fields,
    on_rightclick = sheriff_voting.on_rightclick,
});


minetest.register_craft({
	output = 'sheriff_voting:table',
	recipe = {
		{'', 'default:bookshelf', ''},
		{'default:bronze_ingot', 'default:bronze_ingot', 'default:bronze_ingot'},
		{'default:bronze_ingot', '', 'default:bronze_ingot'},
	}
});

--And here is how sheriff powers are working
minetest.register_chatcommand("mute", {
	params = "<playername>",
	description = "Forbid players to write in chat. Elected Sheriff can use this command.",
	func = function(sheriffname, playername)
		if playername and sheriffname and sheriff_voting.candidate_by_name[sheriffname] then
			if sheriff_voting.candidate_by_name[sheriffname].votes >= sheriff_voting.vote_needed then
				sheriff_voting.mute_by_name[playername] = sheriffname;
				minetest.chat_send_all("Sheriff <"..sheriffname.."> muted player <"..playername..">.");
				minetest.log("action", "Sheriff <"..sheriffname.."> muted player <"..playername..">.");
			else
				minetest.chat_send_player(sheriffname, "You are not elected as sheriff.");
			end
		end
	end,
})

minetest.register_chatcommand("unmute", {
	params = "<playername>",
	description = "Allow players to write in chat. Elected Sheriff can use this command.",
	func = function(sheriffname, playername)
		if playername and sheriffname and sheriff_voting.candidate_by_name[sheriffname] then
			if sheriff_voting.candidate_by_name[sheriffname].votes >= sheriff_voting.vote_needed then
				sheriff_voting.mute_by_name[playername] = nil;
				minetest.chat_send_all("Sheriff <"..sheriffname.."> unmuted player <"..playername..">.");
				minetest.log("action", "Sheriff <"..sheriffname.."> unmuted player <"..playername..">.");
			else
				minetest.chat_send_player(sheriffname, "You are not elected as sheriff.");
			end
		end
	end,
})

minetest.register_on_chat_message(function(playername, message)
	if sheriff_voting.mute_by_name[playername] then
		minetest.chat_send_player(playername, "Sheriff <"..sheriff_voting.mute_by_name[playername].."> muted you until server restart or sheriff is demoted.");
		return true	--prevent message
	end
end)

minetest.register_chatcommand("jail", {
	params = "<playername>",
	description = "Send specified player to jail. Only elected Sheriff with at least "..(sheriff_voting.vote_needed*2).." votes can use this command.",
	func = function(sheriffname, playername)
		if playername and sheriffname and sheriff_voting.candidate_by_name[sheriffname] then
			if sheriff_voting.candidate_by_name[sheriffname].votes >= sheriff_voting.vote_needed*2 then
				if sheriff_voting.candidate_by_name[sheriffname].action_delay < 1 then
                    local suspect = minetest.get_player_by_name(playername);
                    if suspect then
                        suspect:setpos( {x=0, y=-2, z=0} );
                        minetest.chat_send_player(playername, "Sheriff <"..sheriffname.."> jailed player <"..playername..">. If you think this is wrong, then ask help from other players to demote sheriff.");
                        minetest.chat_send_all("Sheriff <"..sheriffname.."> jailed player <"..playername..">.");
                        minetest.log("action", "Sheriff <"..sheriffname.."> jailed player <"..playername..">.");
                        sheriff_voting.candidate_by_name[sheriffname].action_delay = sheriff_voting.candidate_by_name[sheriffname].action_delay + 1;
                    else
                        minetest.chat_send_player(sheriffname, "Player <"..playername.."> not online.");
                    end
				else
					minetest.chat_send_player(sheriffname, "There is small delay for jailing players, just in case.");
				end
			else
				minetest.chat_send_player(sheriffname, "You need to be sheriff with at least"..(sheriff_voting.vote_needed*2).." votes.");
			end
		end
	end,
})

minetest.register_chatcommand("kicks", {
	params = "<playername>",
	description = "Kick specified player. Only elected Sheriff with at least "..(sheriff_voting.vote_needed*3).." votes can use this command.",
	func = function(sheriffname, playername)
		if playername and sheriffname and sheriff_voting.candidate_by_name[sheriffname] then
			if sheriff_voting.candidate_by_name[sheriffname].votes >= sheriff_voting.vote_needed*3 then
				if sheriff_voting.candidate_by_name[sheriffname].action_delay < 1 then
					minetest.kick_player(playername, "Sheriff <"..sheriffname.."> kicked player <"..playername..">. If you think this is wrong, then ask help from other players to demote sheriff.");
					minetest.chat_send_all("Sheriff <"..sheriffname.."> kicked player <"..playername..">.");
					minetest.log("action", "Sheriff <"..sheriffname.."> kicked player <"..playername..">.");
					sheriff_voting.candidate_by_name[sheriffname].action_delay = sheriff_voting.candidate_by_name[sheriffname].action_delay + 1;
				else
					minetest.chat_send_player(sheriffname, "There is small delay for kicking players, just in case.");
				end
			else
				minetest.chat_send_player(sheriffname, "You need to be sheriff with at least"..(sheriff_voting.vote_needed*3).." votes.");
			end
		end
	end,
})

minetest.register_chatcommand("sheriffs", {
	params = "",
	description = "List all sheriff names.",
	func = function(playername)
        for key, val in pairs(sheriff_voting.candidate_by_name) do
            if val.votes >= sheriff_voting.vote_needed*3 then
                minetest.chat_send_player(playername, "Sheriff ***"..key.."***");
            elseif val.votes >= sheriff_voting.vote_needed*2 then
                minetest.chat_send_player(playername, "Sheriff **"..key.."**");
            elseif val.votes >= sheriff_voting.vote_needed then
                minetest.chat_send_player(playername, "Sheriff *"..key.."*");
            elseif val.votes < -sheriff_voting.vote_needed then
                minetest.chat_send_player(playername, "Outlaw -"..key.."-");
            end
        end
	end,
})

--clear action delays
sheriff_voting.vote = function()
	
	for key, val in pairs(sheriff_voting.candidate_by_name) do
		val.action_delay = 0;
	end
	minetest.after(15, function()
        sheriff_voting.vote();
	end)
end
sheriff_voting.vote();
