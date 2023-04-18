--[[
    idea:
        * have agents
        * having dna
        * transcribe all of it (maybe starting from random locations)
            - instead of transcribing it, parse it and make a diff equations for each "word"
            - "-> X" : generate X
            - "X -> Y" : from X generate Y
            - "X :" : a prefix that adds a condition (implemented by slowing or speeding up the rest of word)
            - some "and", "or" etc...
            - have different efficiency options for same words
            - have some way to have Dt X/Y, Dt X^2, X^2 etc...
        * some codes generate signal strengths (e.g. move forward)
        * some codes have preconditions (e.g. food available)
        * some codes are more resistant to mutations (e.g. growth logic)
        * biggest strength gets executed
        * cell signals can be
            - local -> only in the cell itself
            - body-local -> in all of the agent
            - diffusive -> strength S in cell and exp lowering from the source
        * signals can be:
            - commandlike -> move, grow, etc...
            - anti commands??
            - poisons -> drains energy if not coutered
            - anti-poison -> basicaly counters the poison
            - energy storage -> easier energy -> this signal
            - enzymes -> storage to energy with good efficiency
            - photosynthesis enzyme -> gain energy by burning not a lot of this
                - limit it somehow?? poison?
            - breakdown enzyme -> organics to soil, also poison
            - data and anti-data -> misc signaling
        * eating others consumes some signals (more than others)
        * energy for most actions needed
        * some way of breeding/mutations etc
        * cell specilization???
    must support:
        * plants
            - roots(???)
            - trunk
            - leaves (light -> energy)
            - seeds/fruits
        * worms
            - grow
            - move
            - eat (non-armored -> energy)
        * mushrooms
            - grow
            - spores
            - organics -> soil + energy
    enviroment:
        * diffusive (two types: carried by e.g. sand and empty air)
            - pheromones
            - water
        * raytracive
            - sunlight
        * structural
        * sand-like
--]]
settings={
    max_energy=100,

    max_signal=100,
    command_signal_trigger=50,
    signal_decay=0.99,
    anti_signal_influence=-1,
    storage_efficiency=10, --i.e. max_signal*storage_efficiency= max stored energy in storage signal
    storage_decay=0.9999
    min_energy_storage=10, --does not decrease if energy<this when making storage signals
    cost_move=0.5,
    cost_grow=3,
}
command_signals={
    {"cmd_move",1,signal_move},
    {"cmd_grow",2,signal_grow},
    --directions, not actually command, but commands read these
    {"cmd_up",3},
    {"cmd_down",4},
    {"cmd_left",5},
    {"cmd_right",6},
    --todo other
}
poison_signals={
    --name,id,power,transfer_power
    {"apaptosis",1,10,0},
    {"poison1",1,1,1},
    {"poison2",1,5,0.8},
    {"poison3",1,25,0.5},
    {"poison4",1,0.5,1},
}
function meta_signal_anti(org_signal_id)
    return function ( state,this_signal )
        local anti_amount=state[this_signal[2]]
        local was_amount=state[org_signal_id]
        was_amount=was_amount+anti_amount*settings.anti_signal_influence
        state[org_id]=math.min(math.max(was_amount,0),settings.max_signal)
    end
end
function generate_anti_signal( s,my_id )
    local ret={}
    ret[1]="anti_"..s[1]
    ret[2]=my_id
    ret[3]=meta_signal_anti(s[2])
    return ret
end
function generate_all_signals()
    signal_list={}
    --commands
    for i,v in ipairs(command_signals) do
        v[2]=#signal_list+1
        table.insert(signal_list,v)
    end
    --anti-commands
    for i,v in ipairs(command_signals) do
        table.insert(signal_list,generate_anti_signal(v,#signal_list+1))
    end
    --poisons
    for i,v in ipairs(poison_signals) do
        v[2]=#signal_list+1
        table.insert(signal_list,v)
    end
    for i,v in ipairs(poison_signals) do
        table.insert(signal_list,generate_anti_signal(v,#signal_list+1))
    end

end
cell={
    --agent?
    pos={},
    local_signals={},
    --diffuse_signals={} probably provided by the agent
    --enviroment_signals={} probably provided by the runner
    --energy maybe in agent?
    last_dna_pointer=0, --where it last executed dna
    dna_sleep=0, --how long until next dna execution
}
agent={
    dna={},
    cells={}
}
local agents={}

