-- ------------------------------------------------------------
-- Optional compatibility shim for Lua 5.2+ / 5.3+ / 5.4
-- (No effect on Lua 5.1 / LuaJIT. Helps when running the generator
--  with a plain Lua 5.4 interpreter by providing 5.1-era globals.)
-- ------------------------------------------------------------
if _VERSION ~= "Lua 5.1" then
	-- Lua 5.1 had global `unpack`; in 5.2+ it moved to `table.unpack`
	unpack = unpack or table.unpack

	-- Some legacy modules may call `module(...)`. Provide a tiny shim.
	if type(module) ~= "function" then
		function module(name)
			local M = package.loaded[name] or {}
			package.loaded[name] = M
			_G[name] = M
			return M
		end
	end
end

-- Determine execution mode and require logging module
executionArgs = {...}
local isCLI = executionArgs[2] == "cli"
local rootPath = isCLI and "" or "data/talkactions/scripts/otMapGenPublic/"

require(isCLI and "lib/modules/logging/file" or "data/talkactions/scripts/otMapGenPublic/lib/modules/logging/file")

logger = nil

-- Initialize execution mode
if isCLI then
	RUNNING_MODE = "cli"
	dofile("bootstrapCli.lua")
else
	RUNNING_MODE = "tfs"
	dofile(rootPath .. "bootstrap.lua")
end

-- Configure logger
local function setupLogger(scriptName, logType, timestamp)
	return logging.file(
		rootPath .. "logs/" .. scriptName .. "-" .. logType .. "-%s.log",
		"%Y_%m_%d-" .. timestamp,
		"%date::%level: %message\n"
	)
end

-- Load script file path
local function loadScriptFile(params, generalStartTime)
	local scriptPath = rootPath .. "data/genScripts/" .. params[1] .. ".lua"
	print("# Executing script: " .. scriptPath .. ", logIdentifier: " .. generalStartTime)
	return scriptPath
end

-- Erase map
local function eraseGeneratedMap(scriptPath)
	dofile(scriptPath)
	eraseMap()
	print("Map was erased for script: " .. scriptPath)
end

-- Save map in .otbm format
local function saveGeneratedMap(scriptName, generatedMap, generalStartTime)
	logger = setupLogger(scriptName, "saving-map", generalStartTime)

	local filename = rootPath ..
		"generatedFiles/" .. MAP_CONFIGURATION.saveMapFilename ..
		string.format("-%s.otbm", generalStartTime)
	local mainPos = generatedMap.mainPos
	local mapSizeX, mapSizeY, mapSizeZ = generatedMap.sizeX, generatedMap.sizeY, generatedMap.sizeZ - 1

	local fromPos = { x = mainPos.x - 5, y = mainPos.y - 5, z = mainPos.z - mapSizeZ }
	local toPos = { x = mainPos.x + mapSizeX + 5, y = mainPos.y + mapSizeY + 5, z = mainPos.z }

	print("# Running saving map: " .. filename)
	saveMap3(filename, fromPos, toPos) -- Resource-based saving method
	print("# Saving map: " .. filename .. " finished.")
end

-- Save map in JSON format
local function saveGeneratedJson(scriptName, generatedMap, generalStartTime)
	logger = setupLogger(scriptName, "saving-map", generalStartTime)

	local mapJsonSaver = MapJsonSaver.new(generatedMap, CLI_FINAL_MAP_TABLE)
	mapJsonSaver:save(generalStartTime)
end

-- Read map from JSON
local function readGeneratedJson(filename, generatedMap)
	local mapReader = MapJsonReader.new(generatedMap)
	return mapReader:load(filename)
end

-- Draw map from memory (e.g. previously loaded from json)
local function drawMemoryMap(generatedMap)
	if (PRECREATION_TABLE_MODE and RUNNING_MODE == 'tfs') then
		local mapCreator = MapCreator.new(generatedMap)
		mapCreator:drawMap()
	else
		error('Drawning map available only in running TFS with tableMode.')
	end
end

-- Process map operations (execution, saving, etc.)
local function processMapOperation(scriptName, params, generatedMap, generalStartTime)
	local endMessage = "# General execution time: " .. (os.clock() - generalStartTime)
	if LOG_TO_FILE then
		endMessage = endMessage .. ", logIdentifier: " .. generalStartTime
	end

	if params[2] == "save" or params[3] == "save" then
		saveGeneratedMap(scriptName, generatedMap, generalStartTime)
	elseif params[2] == "saveJson" or params[3] == "saveJson" then
		saveGeneratedJson(scriptName, generatedMap, generalStartTime)
	end

	print(endMessage)
end

-- Main function executed in TFS when using talk action
function onSay(player, words, param)
	if not param or param == "" then return end

	local params = explode(removeWhitespace(param), ",")
	local scriptName = params[1]
	if not scriptName then return end

	local generalStartTime = os.clock()
	logger = setupLogger(scriptName, "execution", generalStartTime)

	if RUNNING_MODE == "tfs" then
		TFS_CID = player:getId()
		TFS_MESSAGE_CLASSES = MESSAGE_EVENT_DEFAULT
	end

	local scriptPath = loadScriptFile(params, generalStartTime)

	if params[2] == "erase" then
		eraseGeneratedMap(scriptPath)
		return
	end

	if params[2] == "tableMode" then
		PRECREATION_TABLE_MODE = true
	end

	local runningScript = dofile(scriptPath)

	if ((params[2] == "readJson" or params[3] == "readJson") and
		(params[3] ~= nil or params[4] ~= nil)
	) then
		local map = runningScript.getMap()
		local filename = params[3] ~= "readJson" and params[3] or params[4]

		CLI_FINAL_MAP_TABLE = readGeneratedJson(filename, map)
		if RUNNING_MODE == "tfs" then
			PRECREATION_TABLE_MODE = true
			drawMemoryMap(map)
		else
			saveGeneratedMap(scriptName, map, generalStartTime)
		end

		print("# General execution time: " .. (os.clock() - generalStartTime))
	else
		local generatedMap = runningScript.run()
		processMapOperation(scriptName, params, generatedMap, generalStartTime)
	end
end

-- Execute as CLI if running from terminal
if isCLI then
	onSay(nil, {}, executionArgs[1])
end
