-- Root of the map generator inside TFS data folder (keep trailing slash)
ROOT_PATH = "data/talkactions/scripts/otMapGen/"

-- ----------------------------
-- Load config for the generator
-- ----------------------------
dofile(ROOT_PATH .. 'config.lua')

local prefix = ">> "

-- OS detection:
-- 1) LuaJIT provides `jit.os == "Windows"` on Windows
-- 2) Fallback check: on Windows, package.config starts with a backslash ('\')
local isWindows = (jit and jit.os == "Windows") or package.config:sub(1,1) == '\\'

-- Folders to scan for *.lua files (relative to ROOT_PATH)
local folders = {
	'lib/externalResources',
	'lib',
	'lib/classes/data',
	'lib/classes/data/reader',
	'lib/classes/data/saver',
	'lib/classes/tools',
	'lib/classes',
	'lib/data',
	'lib/data/borders',
	'lib/data/brushes',
	'lib/data/elevation',
	'lib/data/shapes',
	'lib/commonScripts',
}

-- Return ONLY file names (no directory prefix), filtered to *.lua
local function listFiles(dir)
	-- `dir` is an absolute/normalized directory path (with trailing slash added by caller)
	local cmd
	if isWindows then
		-- /b  = bare format (names only)
		-- /a-d = include files only (exclude directories)
		-- Quote the dir for safety (spaces in paths)
		cmd = string.format('dir "%s" /b /a-d', dir)
	else
		-- GNU find: print only the file *name* (no path) with -printf "%f\n"
		-- -maxdepth 1 = only current directory
		-- -type f      = files only
		cmd = string.format('find "%s" -maxdepth 1 -type f -printf "%%f\\n"', dir)
	end

	local t, p = {}, io.popen(cmd)
	if not p then
		return t -- return empty list on failure, do not crash the whole bootstrap
	end

	for name in p:lines() do
		if name:match("%.lua$") then
			t[#t+1] = name
		end
	end
	p:close()
	return t
end

local filesCount = 0

for i = 1, #folders do
	local base = ROOT_PATH .. folders[i] .. '/'

	if DEBUG_OUTPUT then
		print(prefix .. 'Loading ' .. MAP_GEN_CFG.generatorName .. ': ' .. folders[i] .. '... ')
	end

	local files = listFiles(base)
	for _, filename in ipairs(files) do
		local filePath = base .. filename
		print('Loading file: ' .. filePath)

		-- Use pcall to surface a precise error without killing the entire loop instantly.
		local ok, err = pcall(dofile, filePath)
		if not ok then
			error("Error while loading " .. filePath .. ":\n" .. tostring(err), 0)
		end

		filesCount = filesCount + 1
	end

	if DEBUG_OUTPUT then
		print(filesCount .. ' file(s) loaded.')
	end

	filesCount = 0
end

PRECREATION_TABLE_MODE = false
