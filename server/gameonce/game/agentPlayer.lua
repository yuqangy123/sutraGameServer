local skynet = require "skynet"
--local netpack = require "netpack"
local socket = require "skynet.socket"
local sproto = require "sproto"
local sprotoloader = require "sprotoloader"
local datacenter = require "skynet.datacenter"
require "functions"
--local sproto_core = require "sproto.core"

local WATCHDOG
local game_root
local host
local packMsg

local CMD = {}
local REQUEST = {}

local STATE = {}
local fd = nil
local agent = nil

local pinfo = {
	uuid = "",
	totalRank = 0,
	registerTime = 0,
	signNum = 0,
	censerNum = 0,
	sutraNum = 0,
	signRank = 0,
	censerRank = 0,
	sutraRank = 0,
	jingtuGroup = "",
	lotusNum = 0,
	fohaoNum = 0,			--佛号总数
	phoneType = "",
	signLine = 0,
	month = 0,
	musicScore = {},
	first = false,
	ostime = 0,
	incenseLastTime = 0,
	sutraLastTime = 0,
	loginLastTime = 0,
}

local passedFohaoMathCount = 30000

local function printTable(lua_table, indent)
    if not lua_table then
        return
    end
    indent = indent or 0
    for k, v in pairs(lua_table) do
        if type(k) == "string" then
            k = string.format("%q", k)
        end
        local szSuffix = ""
        if type(v) == "table" then
            szSuffix = "{"
        end
        local szPrefix = string.rep("    ", indent)
        local formatting = szPrefix.."["..k.."]".." = "..szSuffix
        if type(v) == "table" then
            print(formatting)
            printTable(v, indent + 1)
            print(szPrefix.."},")
        else
            local szValue = ""
            if type(v) == "string" then
                szValue = string.format("%q", v)
            else
                szValue = tostring(v)
            end
            print(formatting..szValue..",")
        end
    end
end


local function split(input, delimiter)
    if input == "" then return {} end
    input = tostring(input)
    delimiter = tostring(delimiter)
    if (delimiter=='') then return {} end
    local pos,arr = 0, {}
    -- for each divider found
    for st,sp in function() return string.find(input, delimiter, pos, true) end do
        table.insert(arr, string.sub(input, pos, st - 1))
        pos = sp + 1
    end
    table.insert(arr, string.sub(input, pos))
    return arr
end

local function getDayByTime( t )
	local dates = os.date("*t", t)
	return dates
end



local function updateTotalRank()
	local r = skynet.call("rankService", "lua", "getTotalRank", pinfo.uuid)
	CMD.pushUserData("totalRank", r or 0)
end
local function updateSignRank()
	skynet.call("rankService", "lua", "updateSign", pinfo.uuid, pinfo.signNum)
	local r = skynet.call("rankService", "lua", "getSignRank", pinfo.uuid)
	CMD.pushUserData("signRank", r or 0)
	updateTotalRank()	
end
local function updateCenserRank()
	skynet.call("rankService", "lua", "updateCenser", pinfo.uuid, pinfo.censerNum)
	local r = skynet.call("rankService", "lua", "getCenserRank", pinfo.uuid)
	CMD.pushUserData("censerRank", r or 0)
	updateTotalRank()
end
local function updateSutraRank()
	skynet.call("rankService", "lua", "updateSutra", pinfo.uuid, pinfo.sutraNum)
	local r = skynet.call("rankService", "lua", "getSutraRank", pinfo.uuid)
	CMD.pushUserData("sutraRank", r or 0)
	updateTotalRank()
end
local function updateFohaoRank()
	skynet.call("rankService", "lua", "updateFohao", pinfo.uuid, pinfo.fohaoNum)
	local r = skynet.call("rankService", "lua", "getFohaoRank", pinfo.uuid)
	
	updateTotalRank()
end

local function updateSign(month, signLine)
	
	pinfo.signLine = signLine
	pinfo.signNum = pinfo.signNum + 1
	
	CMD.pushUserData("signNum", pinfo.signNum)
	
	skynet.call("db_service", "lua", "updateMonthCollect", pinfo.uuid, month ,"signLine", pinfo.signLine)
	skynet.call("db_service", "lua", "updateUserUpdate", pinfo.uuid, "signNum", pinfo.signNum)
	updateSignRank()
end
local function updateCenserNum(isSync)
	local ser = getDayByTime(pinfo.ostime)
	local last = getDayByTime(pinfo.incenseLastTime)
	if isSync or (ser.year ~= last.year or ser.month ~= last.month or ser.day ~= last.day) then
		pinfo.censerNum = pinfo.censerNum + 1
		if not isSync then
			pinfo.incenseLastTime = pinfo.ostime
			CMD.pushUserData("incenseLastTime", pinfo.incenseLastTime)
			skynet.call("db_service", "lua", "updateUserUpdate", pinfo.uuid, "incenseLastTime", pinfo.incenseLastTime)
		end
		
		CMD.pushUserData("censerNum", pinfo.censerNum)
		skynet.call("db_service", "lua", "updateUserUpdate", pinfo.uuid, "censerNum", pinfo.censerNum)		
		updateCenserRank()
		return true
	else
		return false
	end
end
local function updateSongScore(scoreData)
	local s = split(scoreData, ":")
	local musicName = s[1]
	local sc = split(s[2], ",")
	local score = tonumber(sc[1]) or 0
	local clickCount = tonumber(sc[2]) or 0
	if not pinfo.musicScore[musicName] then
		--return {errCode=1, desc="cant find the song ", musicName}
		pinfo.musicScore[musicName] = 0
	end
	
	--大于100下佛句就算敲成功		
	if clickCount > 99 then
		local ser = getDayByTime(pinfo.ostime)
		local last = getDayByTime(pinfo.sutraLastTime)
	
		if ser.year ~= last.year or ser.month ~= last.month or ser.day ~= last.day then
			pinfo.sutraNum = pinfo.sutraNum + 1
			pinfo.sutraLastTime = pinfo.ostime
			
	
			CMD.pushUserData("sutraNum", pinfo.sutraNum)
			skynet.call("db_service", "lua", "updateUserUpdate", pinfo.uuid, "sutraNum", pinfo.sutraNum)
			
			CMD.pushUserData("sutraLastTime", pinfo.sutraLastTime)
			skynet.call("db_service", "lua", "updateUserUpdate", pinfo.uuid, "sutraLastTime", pinfo.sutraLastTime)
			
			updateSutraRank()
		end
	end

	--保存佛句,增加得分
	local addScore = score
	local lastScore = pinfo.musicScore[musicName]
	pinfo.musicScore[musicName] = pinfo.musicScore[musicName] + addScore
	pinfo.fohaoNum = pinfo.fohaoNum + addScore
	local fohaoGroup = ""
	for k,v in pairs(pinfo.musicScore) do
		fohaoGroup = fohaoGroup .. k .. ":" .. v .. ","
	end
	if string.len(fohaoGroup) > 0 then
		fohaoGroup = string.sub(fohaoGroup, 1, -2)
	end
	CMD.pushUserData("fohaoGroup", fohaoGroup)
	skynet.call("db_service", "lua", "updateMonthCollect", pinfo.uuid, pinfo.month, "fohaoGroup", fohaoGroup)
	skynet.call("db_service", "lua", "updateUserUpdate", pinfo.uuid, "fohaoNum", pinfo.fohaoNum)
	updateFohaoRank()
	
	local totalMonthScore = 0
	local songList, jingtu = skynet.call(game_root, "lua", "getJingtuListIdWithSongId", musicName)
	if songList then
		for k,v in pairs(songList) do
			if pinfo.musicScore[v] then
				totalMonthScore = totalMonthScore + pinfo.musicScore[v]
			end
		end
	end
	
	--一个月内累计敲3万下佛号
	if totalMonthScore > passedFohaoMathCount and totalMonthScore - addScore < passedFohaoMathCount then
		local s1, s2 = string.find(pinfo.jingtuGroup, jingtu, 1, true)
		if not s1 then
			if pinfo.jingtuGroup == "" then
				pinfo.jingtuGroup = jingtu .. ":1"
			else
				pinfo.jingtuGroup = pinfo.jingtuGroup .. "," .. jingtu .. ":1"
			end
		else
			s1, s2 = string.find(pinfo.jingtuGroup, ":", s2+1, true)
			local s3 = string.find(pinfo.jingtuGroup, ",", s2+1, true)
			local jtNum = tonumber(string.find(s2+1, s3-1)) + 1
			pinfo.jingtuGroup = string.sub(pinfo.jingtuGroup, 1, s2) .. jtNum .. string.sub(pinfo.jingtuGroup, s2+1, -1)
		end			
		CMD.pushUserData("jingtuGroup", pinfo.jingtuGroup)
		
		skynet.call("db_service", "lua", "updateUserBaseData", pinfo.uuid, "jingtuGroup", pinfo.jingtuGroup)
	end
end
local function init()
	pinfo.ostime = os.time()
	print("totalpush pinfo.ostime")
	local date = getDayByTime(pinfo.ostime )
	printTable(date)

	local r 

	r = skynet.call("db_service", "lua", "getUserBaseData", pinfo.uuid)	
	if r then
		pinfo.uuid = r.uuid
		pinfo.registerTime = r.registerTime
		pinfo.jingtuGroup = r.jingtuGroup
		pinfo.lotusNum = r.lotusNum
		pinfo.phoneType = r.phoneType
	end
	
	r = skynet.call("db_service", "lua", "getUserMonthCollect", pinfo.uuid, date.month)
	print("getUserMonthCollect data info")
	printTable(r)
	if r then
		--signLine, mouth, fohaoGroup
		pinfo.signLine = r.signLine
		pinfo.month = r.month
		local scores = split(r.fohaoGroup, ",")
		for k,v in pairs(scores) do
			local s = split(v, ":")
			if #s == 2 then
				pinfo.musicScore[s[1]] = tonumber(s[2])
			end
		end
	end
	
	r = skynet.call("db_service", "lua", "getUserUpdateData", pinfo.uuid)
	if r then
		pinfo.signNum = r.signNum
		pinfo.censerNum = r.censerNum
		pinfo.sutraNum = r.sutraNum
		pinfo.signRank = r.signRank
		pinfo.censerRank = r.censerRank
		pinfo.sutraRank = r.sutraRank
		pinfo.totalRank = r.totalRank
		pinfo.incenseLastTime = r.incenseLastTime
		pinfo.sutraLastTime = r.sutraLastTime
		pinfo.fohaoNum = r.fohaoNum
		pinfo.loginLastTime = r.loginLastTime
	end
	
	--最后，校验是否跨月，做相关逻辑
	local lastLoginDate = getDayByTime(pinfo.loginLastTime)
	if lastLoginDate.month ~= date.month then
		pinfo.loginLastTime = pinfo.ostime
		skynet.call("db_service", "lua", "updateUserUpdate", pinfo.uuid, "loginLastTime", pinfo.loginLastTime)
		
		r = skynet.call("db_service", "lua", "getUserMonthCollect", pinfo.uuid, lastLoginDate.month)
		if r then
			local songlist = skynet.call(game_root, "lua", "getSongList")
			
			local scores = split(r.fohaoGroup, ",")
			local jingtuList = {}
			for k,v in pairs(scores) do
				local s = split(v, ":")
				if #s == 2 then
					local jt = songlist[s[1]].jingtuId
					if not jingtuList[jt] then jingtuList[jt] = 0 end
					jingtuList[jt] = jingtuList[jt] + tonumber(s[2])
				end
			end
			
			local jingtuInvalid = {}
			for jt, score in pairs(jingtuList) do
				if score < passedFohaoMathCount then
					jingtuInvalid[jt] = true
				end
			end
			
			local jtGroup = split(pinfo.jingtuGroup, ",")
			local newJtGroup = {}
			for i=1, #jtGroup do
				local jt2num = split(jtGroup[i], ":")
				if not jingtuInvalid[jt2num[1]] then
					newJtGroup[#newJtGroup+1] = jtGroup[i]
				end
			end
			local oldJingtuGroup = pinfo.jingtuGroup
			pinfo.jingtuGroup = table.concat(newJtGroup, ",")
			skynet.call("db_service", "lua", "updateUserBaseData", pinfo.uuid, "jingtuGroup", pinfo.jingtuGroup)
			
			print("NEW MONTH: clear jingtuGroup from " .. oldJingtuGroup .. " to " .. pinfo.jingtuGroup)
		end
	end
end


function REQUEST:updateUserData()
	print("REQUEST:updateUserData", pinfo.uuid, self.type, self.data)
	if not self.isSync then
		if self.ostime ~= pinfo.ostime then
			return {errCode=1, desc="err ostime"}
		end
	end
	
	if "signLine" == self.type then
		local month = pinfo.month
		if self.isSync then
			local t = getDayByTime(self.ostime)
			month = t.month
		end
		updateSign(month, tonumber(self.data))
	
	elseif "censerNum" == self.type then
		if not updateCenserNum(self.isSync) then
			return {errCode=1, desc="today already senserd"}
		end
		
	elseif "songScore" == self.type then
		updateSongScore(self.data)
	end
	
	return {errCode = 0, desc = ""}
end


function REQUEST:notifyUUID()
	pinfo.uuid = self.uuid
	CMD.sendNoteInfo("歡迎進入彩繪凈土世界，請簽到後上香，選取聖號後開始，敲擊木魚完成功課。詢問聯系請電話：65-96620296")
	init()
end

function REQUEST:totalPush()
	local fohaoGroup = ""
	for k,v in pairs(pinfo.musicScore) do
		fohaoGroup = fohaoGroup .. k .. ":" .. v .. ","
	end
	if string.len(fohaoGroup) > 0 then
		fohaoGroup = string.sub(fohaoGroup, 1, -2)
	end
	
	local ret = {incenseLastTime=pinfo.incenseLastTime, sutraLastTime=pinfo.sutraLastTime, 
			totalRank=skynet.call("rankService", "lua", "getTotalRank", self.uuid), 
			signNum=pinfo.signNum, 
			signRank=skynet.call("rankService", "lua", "getSignRank", self.uuid), 
			censerNum=pinfo.censerNum, 
			censerRank=skynet.call("rankService", "lua", "getCenserRank", self.uuid), 
			sutraNum=pinfo.sutraNum,
			sutraRank=skynet.call("rankService", "lua", "getSutraRank", self.uuid), 
			jingtuGroup=pinfo.jingtuGroup, lotusNum=pinfo.lotusNum,fohaoMonthNum=0,
			signLine=pinfo.signLine, serverTime=pinfo.ostime, fohaoGroup=fohaoGroup}
	
	printTable(ret)
	
	return ret
end

function REQUEST:quit()
	skynet.call(WATCHDOG, "lua", "close", fd)
end

local function request(name, args, response)
	print("agent.request.name", name)
	local f = assert(REQUEST[name])
	local r = f(args)

	if response then
		return response(r)
	end
end

local function send_package(pack)
	local package = string.pack(">s2", pack)
	socket.write(fd, package)
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		--local bin = sproto_core.unpack(msg, sz)
		print("agent.unpack.msg",msg,sz)
		return host:dispatch(msg, sz)
	end,
	dispatch = function (_, _, type, ...)
		if type == "REQUEST" then
			local ok, result  = pcall(request, ...)
			if ok then
				if result then
					send_package(result)
				end
			else
				skynet.error(result)
			end
		else
			assert(type == "RESPONSE")
			error "This example doesn't support request client"
		end
	end
}

function CMD.pushUserData(type, data)
	print("pushUserData", type, data)
	send_package(packMsg("pushUserData", {type=type, data=tostring(data)}))
end

function CMD.sendNoteInfo(noteStr)
	send_package(packMsg("sendNote", {note=noteStr}))
end



function CMD.start(conf)
	fd = conf.client
	local gate = conf.gate
	game_root = conf.gameRoot
	WATCHDOG = conf.watchdog
	agent = skynet.self()
	
	-- slot 1,2 set at main.lua
	host = sprotoloader.load(1):host "package"
	packMsg = host:attach(sprotoloader.load(2))
  
  
	skynet.fork(function()
		while true do
			send_package(packMsg "heartbeat")
			skynet.sleep(1500)
		end
	end)
  
	skynet.call(gate, "lua", "forward", fd)
end

function CMD.disconnect()
	-- todo: do something before exit
	--[[if pinfo.uuid ~= "" then
		local r = skynet.call("loginserver", "lua", "logOut", pinfo.uuid)
	end--]]
	
	
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		print("agent dispatch lua:", command)
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
end)
