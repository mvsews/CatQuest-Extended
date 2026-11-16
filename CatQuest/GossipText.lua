local ns=CatQuest335 or {}
CatQuest335=ns

local function Chars(text)
    local out={}
    for c in text:gmatch("[^\128-\191][\128-\191]*") do out[#out+1]=c end
    return out
end
local upper=Chars("АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯІЇЄҐÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞ")
local lower=Chars("абвгдеёжзийклмнопрстуфхцчшщъыьэюяіїєґàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþ")
local case={}
for i,c in ipairs(upper) do case[c]=lower[i] end
local function Fold(text)
    return (text:gsub("[^\128-\191][\128-\191]*",function(c)
        if #c==1 then return c:lower() end
        return case[c] or c
    end))
end
local punctuation={}
for _,c in ipairs(Chars("«»“”„…—–‘’（）。，！？：；、")) do punctuation[c]=true end
local function Word(c)
    if not c or c=="" then return false end
    if #c==1 then return c:match("[%w_]")~=nil end
    return not punctuation[c] and c~="\194\160"
end
local function Replace(text,term,allow)
    if not term or term=="" then return text end
    local folded,needle=Fold(text),Fold(term)
    local out,at={},1
    while true do
        local first,last=folded:find(needle,at,true)
        if not first then out[#out+1]=text:sub(at);break end
        local prefix,suffix=text:sub(1,first-1),text:sub(last+1)
        local before=prefix:match("([^\128-\191][\128-\191]*)$")
        local after=suffix:match("^([^\128-\191][\128-\191]*)")
        out[#out+1]=text:sub(at,first-1)
        if Word(before) or Word(after) or (allow and not allow(prefix,suffix)) then
            out[#out+1]=text:sub(first,last)
        end
        at=last+1
    end
    return table.concat(out)
end
local function Address(prefix,suffix)
    local before=prefix:gsub("%s+$",""):gsub("«$",""):gsub('"$',""):gsub("%s+$","")
    local after=suffix:gsub("^%s+",""):gsub("^»",""):gsub('^"',""):gsub("^%s+","")
    local relative=Fold(after)
    if relative:match("^,%s*котор") or relative:match("^,%s*с%s+котор") then return false end
    local left=before=="" or before:match("[,]$")
    local right=after=="" or after:match("^[,%.!?:;]")
    return left and right
end
local CLASSES={"рыцарь смерти","чернокнижница","чернокнижник","разбойница","разбойник","воительница",
    "волшебница","волшебник","охотница","охотник","паладин","друидка","друид","шаманка","шаман",
    "жрица","жрец","воин","маг","death knight","warrior","warlock","paladin","hunter","priest","rogue","shaman","druid","mage"}

function ns.UniversalGossipText(text,playerName,classes)
    text=tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|n"," ")
    text=text:gsub("\194\160"," ")
    -- Raw format tokens sometimes survive on custom clients. Never speak them.
    text=text:gsub("|3%-%d+%(%$[nNcC]%)",""):gsub("%$[nNcC]","")
    playerName=playerName or (UnitName and UnitName("player"))
    text=Replace(text,playerName)
    local candidates={}
    for _,name in ipairs(CLASSES) do candidates[#candidates+1]=name end
    for _,tableName in ipairs({"LOCALIZED_CLASS_NAMES_MALE","LOCALIZED_CLASS_NAMES_FEMALE"}) do
        for _,name in pairs(_G[tableName] or {}) do candidates[#candidates+1]=name end
    end
    if UnitClass then local name=UnitClass("player");if name then candidates[#candidates+1]=name end end
    for _,name in ipairs(classes or {}) do candidates[#candidates+1]=name end
    table.sort(candidates,function(a,b)return #a>#b end)
    for _,name in ipairs(candidates) do text=Replace(text,name,Address) end
    text=text:gsub("%s+"," "):gsub("%s+([,%.!?:;])","%1")
    repeat local n;text,n=text:gsub(",%s*,",",") until n==0
    text=text:gsub("[,;:]%s*([%.!?])","%1"):gsub("«%s*»",""):gsub('"%s*"',"")
    text=text:gsub("^[%s,;:]+",""):gsub("[%s,;:]+$","")
    return text
end
