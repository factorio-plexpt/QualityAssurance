EnableCraftingSpeedFunction = false

-- Returns the value of the setting with the provided name. Prefix should not be provided.
local function config(name)
    return settings.startup['qa_' .. name].value
end

-- A list of entity names to be skipped over when creating AMS machines.
local AMSBlocklist = {"awesome-sink-gui"}

function GetCraftingSpeedMultiplier(ModuleSlotDifference)
    -- low2 + (value - low1) * (high2 - low2) / (high1 - low1) Provided by "mmmPI" on the factorio forums. Thank you. (If I ever add a supporters list, you'll be on it!)
    return 0.01 + (ModuleSlotDifference - ( -10 )) * (100 - 0.01) / ( 10 - ( -10 ))
end

local function Localiser(AMS, Machine)
    -- Thank you, A.Freeman (from the mod portal) for providing me with this new localisation system. The function part was my idea though. (If I ever add a supporters list, you'll be on it!)
    if AMS.type == "technology" then
        if Machine.localised_name ~= nil and not Machine.localised_name == {} and not Machine.localised_name == "" then
            AMS.localised_name = {"ams.tech-name", {Machine.localised_name}}
            AMS.localised_description = {"ams.tech-description", {Machine.localised_name}}
        else
            AMS.localised_name = {"ams.tech-name", {"entity-name."..Machine.name}}
            AMS.localised_description = {"ams.tech-description", {"entity-name."..Machine.name}}
        end
    else
        if Machine.localised_name ~= nil and not Machine.localised_name == {} and not Machine.localised_name == "" then
            AMS.localised_name = {"ams.name", {Machine.localised_name}}
            AMS.localised_description = {"ams.description", {Machine.localised_name}}
        else
            AMS.localised_name = {"ams.name", {"entity-name."..Machine.name}}
            AMS.localised_description = {"ams.description", {"entity-name."..Machine.name}}
        end
    end
    return AMS
end

-- Thank you, A.Freeman (from the mod portal) for providing me with this new prerequisites system. (If I ever add a supporters list, you'll be on it!)
local function GetMachineTechnology(Machine)
    for i,Technology in pairs(data.raw["technology"]) do
        if Technology.effects ~= nil then
            for j,Effect in pairs(Technology.effects) do
                if Effect ~= nil and Effect.type == "unlock-recipe" and Effect.recipe == Machine.name then
                    return Technology.name
                end
            end
        end
    end
    return nil
end


local function AddQuality(Machine)
    -- Increase quality for a machine.
    if not config("base-quality") then
        log("Base Quality setting is disabled. Skipping.")
        return Machine
    end

    if not config("moduleless-quality") then
        if Machine.module_slots == nil then
            log("Moduleless Quality setting is disabled, and this machine doesn't have module slots. Skipping.")
            return Machine
        else
            if Machine.module_slots == 0 then
                log("Moduleless Quality setting is disabled, and this machine doesn't have module slots. Skipping.")
                return Machine
            end
        end
    end
    local BaseQuality = false
    while not BaseQuality do
        if Machine.effect_receiver ~= nil then
            if Machine.effect_receiver.base_effect ~= nil then
                if Machine.effect_receiver.base_effect.quality ~= nil then
                    if Machine.effect_receiver.base_effect.quality == 0 then
                        log("Machine does not contain base quality. Adding base quality.")
                        Machine.effect_receiver.base_effect.quality = config("base-quality-value") / 100
                    else
                        log("Machine contains base quality of amount " .. Machine.effect_receiver.base_effect.quality or 0 ..". Skipping.")
                        BaseQuality = true
                    end
                else
                    log("Machine does not contain base quality. Preparing to add base quality.")
                    Machine.effect_receiver.base_effect.quality = 0
                end
            else
                Machine.effect_receiver.base_effect = {}
            end
            if Machine.effect_receiver.uses_beacon_effects ~= true then
                Machine.effect_receiver.uses_beacon_effects = true
            end
            if Machine.effect_receiver.uses_module_effects ~= true then
                Machine.effect_receiver.uses_module_effects = true
            end
            if Machine.effect_receiver.uses_surface_effects ~= true then
                Machine.effect_receiver.uses_surface_effects = true
            end
        else
            Machine.effect_receiver = {}
        end
    end
    return Machine
end

local function EnableQuality(Machine)
    -- Allow Qualities in all Machines.
    local qualityadded = false
    local hasquality = false
    while not hasquality do
        if Machine.allowed_effects ~= nil then
            if type(Machine.allowed_effects) ~= "string" then
                for _, AllowedEffect in pairs(Machine.allowed_effects) do
                    if AllowedEffect == "quality" then
                        hasquality = true
                    end
                end
                if hasquality == false then
                    table.insert(Machine.allowed_effects, "quality")
                    hasquality = true
                end
            else
                Machine.allowed_effects = {Machine.allowed_effects}
            end
        else
            Machine.allowed_effects = {}
        end
    end
    return Machine
end

-- Perform operations on automated crafting.
local MachineTypes = {"crafting-machine", "furnace", "assembling-machine"}

log("Performing operations on Automated Crafting.")
for _,MachineType in pairs(MachineTypes) do
    if data.raw[MachineType] ~= nil then
        for j,Machine in pairs(data.raw[MachineType]) do
            log("Scanning Machine \"" .. Machine.name .. "\" now.")
            
            Machine = AddQuality(Machine)

            Machine = EnableQuality(Machine)

            data.raw[MachineType][j] = Machine

            local MachineBanned = false

            for _,EntityName in pairs(AMSBlocklist) do
                if Machine.name == EntityName then
                    MachineBanned = true
                end
            end

            if Machine.no_ams == true then
                MachineBanned = true
            end

            if MachineBanned then
                log("Machine \"" .. Machine.name .. "\" is banned from AMS!")
            end

            -- Create a new version of all machines which have additional module slots.
            if ( not string.find(Machine.name, "qa_") ) and config("ams-machines-toggle") and ( not MachineBanned ) then
                log("Creating AMS version of \"" .. Machine.name .. "\" now.")
                AMSMachine = table.deepcopy(Machine)
                AMSMachine.name = "qa_" .. AMSMachine.name .. "-ams"
                AMSMachine = Localiser(AMSMachine, Machine)

                local AddedModuleSlots = config("added-module-slots")
                local CraftingSpeedMultiplier = 1
                if AMSMachine.module_slots == nil then
                    AMSMachine.module_slots = 0
                end
                if EnableCraftingSpeedFunction == true then
                    if AMSMachine.module_slots + AddedModuleSlots < 0 then
                        CraftingSpeedMultiplier = GetCraftingSpeedMultiplier(AMSMachine.module_slots)
                        AMSMachine.module_slots = 0
                    elseif AddedModuleSlots ~= 0 then
                        CraftingSpeedMultiplier = GetCraftingSpeedMultiplier(AddedModuleSlots)
                        AMSMachine.module_slots = AMSMachine.module_slots + AddedModuleSlots
                    end
                else
                    AddedModuleSlots = 2
                    AMSMachine.module_slots = AMSMachine.module_slots + 2
                    CraftingSpeedMultiplier = 0.8
                end
                AMSMachine.crafting_speed = AMSMachine.crafting_speed * CraftingSpeedMultiplier
                AMSMachine["minable"] = AMSMachine["minable"] or {mining_time = 1}
                AMSMachine.minable.results = nil
                AMSMachine.minable.result = AMSMachine.name
                AMSMachine.minable.count = 1

                AMSMachine.allowed_effects = {"speed", "productivity", "consumption", "pollution", "quality"}
                AMSMachine.allowed_module_categories = {}
                for _,ModuleCatergory in pairs(data.raw["module-category"]) do
                    if ModuleCatergory ~= nil then
                        table.insert(AMSMachine.allowed_module_categories, ModuleCatergory.name)
                    end
                end
                if AMSMachine.effect_receiver == nil then
                    AMSMachine.effect_receiver = {uses_surface_effects = true, uses_beacon_effects = true, uses_module_effects = true}
                else
                    AMSMachine.effect_receiver.uses_beacon_effects = true
                    AMSMachine.effect_receiver.uses_module_effects = true
                    AMSMachine.effect_receiver.uses_surface_effects = true
                end
                AMSMachine.NAMSMachine = Machine.name

                local AMSMachineItem = {}
                if data.raw["item"][Machine.name] ~= nil then
                    AMSMachineItem = table.deepcopy(data.raw["item"][Machine.name])
                elseif data.raw["item"][Machine.MachineItem] ~= nil then
                    AMSMachineItem = table.deepcopy(data.raw["item"][Machine.MachineItem])
                else
                    AMSMachineItem = table.deepcopy(data.raw["item"]["assembling-machine-2"])
                end
                AMSMachineItem.name = AMSMachine.name
                AMSMachineItem.type = "item"
                AMSMachineItem = Localiser(AMSMachineItem, Machine)
                AMSMachineItem.stack_size = 50
                AMSMachineItem.place_result = AMSMachine.name
                AMSMachine.MachineItem = AMSMachineItem.name

                AMSMachineRecipe = {}
                AMSMachineRecipe.name = AMSMachineItem.name
                AMSMachineRecipe.type = "recipe"
                AMSMachineRecipe = Localiser(AMSMachineRecipe, Machine)
                if Machine.MachineItem == nil and Machine.minable ~= nil then
                    if Machine.minable.result ~= nil and Machine.minable.result ~= "" then
                        AMSMachineRecipe.ingredients = {{type = "item", name = Machine.minable.result, amount = 1}, {type = "item", name = "steel-plate", amount = 10}, {type = "item", name = "copper-cable", amount = 20}}
                    else
                        AMSMachineRecipe.ingredients = {{type = "item", name = "electronic-circuit", amount = 1}, {type = "item", name = "steel-plate", amount = 10}, {type = "item", name = "copper-cable", amount = 20}}
                    end
                else
                    AMSMachineRecipe.ingredients = {{type = "item", name = Machine.MachineItem, amount = 1}, {type = "item", name = "steel-plate", amount = 10}, {type = "item", name = "copper-cable", amount = 20}}
                end

                if AMSMachineRecipe.ingredients[1]["name"] == nil then
                    AMSMachineRecipe.ingredients[1]["name"] = "electronic-circuit"
                    log("Had to replace ingredient name for \"" .. AMSMachineRecipe.name .. "\"")
                end

                AMSMachineRecipe.results = {{type = "item", name = AMSMachineItem.name, amount = 1}}
                AMSMachineRecipe.category = "crafting"
                AMSMachineRecipe.enabled = false
                
                AMSMachineTechnology = table.deepcopy(data.raw["technology"]["automation"])
                AMSMachineTechnology.name = AMSMachine.name
                -- Thank you, A.Freeman (from the mod portal) for providing me this new prerequisites system. (If I ever add a supporters list, you'll be on it!)
                Prerequisite = GetMachineTechnology(Machine)
                if Prerequisite ~= nil then
                    AMSMachineTechnology.prerequisites = {Prerequisite, "steel-processing", "electronics"}
                    if data.raw["technology"][Prerequisite].icon ~= nil and data.raw["technology"][Prerequisite].icon ~= "" then
                        AMSMachineTechnology.icon = data.raw["technology"][Prerequisite].icon
                        AMSMachineTechnology.icon_size = data.raw["technology"][Prerequisite].icon_size
                    elseif data.raw["technology"][Prerequisite].icon ~= nil and data.raw["technology"][Prerequisite].icon ~= {} then
                        AMSMachineTechnology.icons = data.raw["technology"][Prerequisite].icons
                    end
                    if Prerequisite.unit ~= nil then
                        AMSMachineTechnology.unit.count = 2 * data.raw["technology"][Prerequisite].unit.count
                    end
                else
                    AMSMachineTechnology.prerequisites = {"steel-processing", "electronics"}
                    AMSMachineTechnology.research_trigger = {type = "build-entity", entity = {name = Machine.name}}
                    AMSMachineTechnology.unit = nil
                end
                AMSMachineTechnology.effects = {{type = "unlock-recipe", recipe = AMSMachineRecipe.name}}
                AMSMachineTechnology = Localiser(AMSMachineTechnology, Machine)

                log("Made AMS version of \"" .. Machine.name .. "\".")
                data:extend{AMSMachine, AMSMachineItem, AMSMachineRecipe, AMSMachineTechnology}
            else
                log("Machine \"" .. Machine.name .. "\" is an AMS machine, AMS machines are turrend off, or this machine is banned. Skipping the AMS machine making process.")
            end
        end
    end
end

-- Allow Quality Modules in Beacons.
if config("quality-beacons") then
    for _,Beacon in pairs(data.raw["beacon"]) do
        Beacon = EnableQuality(Beacon)
    end
end

-- Improve power of all quality modules.
log("Improving power of all quality modules.")
for _,Module in pairs(data.raw["module"]) do
    log("Scanning module \"" .. Module.name .. "\" now.")
    if Module.effect.quality ~= nil then
        if Module.effect.quality >= 0 then
            log("Module \"" .. Module.name .. "\" contians a Quality increase. Increasing bonus.")
            Module.effect.quality = Module.effect.quality * config("quality-module-multiplier")
            
        end
    end
end