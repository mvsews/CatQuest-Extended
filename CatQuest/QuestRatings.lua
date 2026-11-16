local ns = CatQuest335
local L = ns.L
local queue, seen, pending, snapshot = {}, {}, {}, nil
local current, nextShowAt = nil, 0
ns.db.questVotes = ns.db.questVotes or {}
ns.db.questVotePending = ns.db.questVotePending or {}
ns.db.questVoteContext = ns.db.questVoteContext or {}
for id, vote in pairs(CatQuest335_BridgeQuestVotes or {}) do
    id = tonumber(id)
    if id and id > 0 and (vote == 1 or vote == -1) then
        if not ns.db.questVotePending[id] or ns.db.questVotePending[id] == vote then
            ns.db.questVotes[id] = vote
            ns.db.questVotePending[id] = nil
            ns.db.questVoteContext[id] = nil
        end
    end
end

local frame = CreateFrame("Frame", "CatQuest335QuestRating", UIParent)
frame:SetWidth(336); frame:SetHeight(244)
frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -24, 180)
frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=16,
    insets={left=4,right=4,top=4,bottom=4}})
frame:Hide()
frame.heading=frame:CreateFontString(nil,"ARTWORK","GameFontNormal")
frame.heading:SetPoint("TOPLEFT",18,-18);frame.heading:SetWidth(274)
frame.heading:SetJustifyH("LEFT")
frame.quest=frame:CreateFontString(nil,"ARTWORK","GameFontHighlight")
frame.quest:SetPoint("TOPLEFT",frame.heading,"BOTTOMLEFT",0,-6)
frame.quest:SetWidth(296);frame.quest:SetHeight(34)
frame.quest:SetJustifyH("LEFT");frame.quest:SetJustifyV("TOP");frame.quest:SetWordWrap(true)
frame.objective=frame:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
frame.objective:SetPoint("TOPLEFT",frame.quest,"BOTTOMLEFT",0,-5)
frame.objective:SetWidth(296);frame.objective:SetHeight(54)
frame.objective:SetJustifyH("LEFT");frame.objective:SetJustifyV("TOP");frame.objective:SetWordWrap(true)
frame.caption=frame:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
frame.caption:SetPoint("BOTTOMLEFT",18,12);frame.caption:SetWidth(300)
frame.caption:SetJustifyH("LEFT")

local function CanShow(manual)
    return ns.db.enabled and (manual or ns.db.questRatings ~= false)
        and not (UnitAffectingCombat and UnitAffectingCombat("player"))
        and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
end

local function Display(item)
    current=item
    frame.item=item
    frame.heading:SetText(L.RATE_QUESTION)
    frame.quest:SetText(item.title or string.format(L.QUEST_N,tostring(item.id)))
    frame.objective:SetText(item.objective and string.format(L.RATE_OBJECTIVE,item.objective) or "")
    local vote=ns.db.questVotes[item.id]
    frame.caption:SetText(vote and string.format(L.RATE_CURRENT,vote==1 and L.RATE_LIKE or L.RATE_DISLIKE) or L.RATE_HINT)
    frame.up:SetAlpha(vote == -1 and 0.6 or 1)
    frame.down:SetAlpha(vote == 1 and 0.6 or 1)
    frame:Show()
end

local function ShowNext()
    if frame:IsShown() or not queue[1] or not CanShow(queue[1].manual) or GetTime()<nextShowAt then return end
    local item=table.remove(queue,1)
    if item then Display(item) end
end

local function Dismiss()
    frame:Hide();frame.item=nil;current=nil
    -- A double click must not vote for the next quest in the same position.
    nextShowAt=GetTime()+0.5
end

function ns.SetQuestRatingPrompts(on)
    ns.db.questRatings=on and true or false
    if not on then
        queue={}
        if current and not current.manual then Dismiss() end
    end
    local text="questRatings="..(on and "1" or "0")
    if ns.SendMessageBytes then ns.SendMessageBytes(5,{string.byte(text,1,-1)}) end
end

function ns.QuestVoteBytes(id,vote,context)
    id=tonumber(id)
    if not id or id<=0 or id>=10000000 or id~=math.floor(id) or (vote~=1 and vote~=-1) then return end
    local locale=0
    for i,value in ipairs(ns.VOICE_LOCALES or {}) do
        if value==ns.ClientLocale() then locale=i end
    end
    local bytes={math.floor(id/16777216)%256,math.floor(id/65536)%256,math.floor(id/256)%256,id%256,
        vote==1 and 1 or 2,locale}
    if context and context.id then
        for i=1,16,2 do bytes[#bytes+1]=tonumber(context.id:sub(i,i+1),16) end
        local at=tonumber(context.at) or 0
        for _,shift in ipairs({16777216,65536,256,1}) do bytes[#bytes+1]=math.floor(at/shift)%256 end
        local actor=context.character and ns.CharacterPayload(context.character)
        for _,byte in ipairs(actor or {}) do bytes[#bytes+1]=byte end
        if #bytes>253 then return ns.QuestVoteBytes(id,vote,{id=context.id,at=context.at}) end
    end
    return bytes
end

local function Transmit(id,vote)
    local supports=type(CatQuest335_BridgeReady)=="table" and CatQuest335_BridgeReady.voteContext
    local bytes=ns.QuestVoteBytes(id,vote,supports and ns.db.questVoteContext[id] or nil)
    return bytes and ns.SendMessageBytes and ns.SendMessageBytes(6,bytes)
end

function ns.SubmitQuestVote(vote)
    if not current or (vote~=1 and vote~=-1) then return false end
    local id=current.id
    ns.db.questVotes[id]=vote
    ns.db.questVotePending[id]=vote
    ns.db.questVoteContext[id]={id=ns.NewActionID(),at=time and time() or 0,character=ns.CharacterSnapshot()}
    Transmit(id,vote)
    ns.Print(L.RATE_SAVED)
    Dismiss()
    return true
end

local function Button(name,value,texture,anchor)
    local button=CreateFrame("Button",name,frame,"UIPanelButtonTemplate")
    button:SetWidth(142);button:SetHeight(32)
    button:SetPoint("TOPLEFT",frame.objective,"BOTTOMLEFT",anchor,-9)
    local icon=button:CreateTexture(nil,"ARTWORK")
    icon:SetWidth(26);icon:SetHeight(26);icon:SetPoint("LEFT",5,0)
    icon:SetTexture("Interface\\AddOns\\CatQuest\\"..texture)
    local label=button:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    label:SetPoint("LEFT",icon,"RIGHT",3,0);label:SetWidth(102);label:SetJustifyH("CENTER")
    label:SetText(value==1 and L.RATE_LIKE or L.RATE_DISLIKE)
    button.label=label
    button:SetScript("OnClick",function() ns.SubmitQuestVote(value) end)
    return button
end
frame.up=Button("CatQuest335QuestLike",1,"VoteUp.tga",0)
frame.down=Button("CatQuest335QuestDislike",-1,"VoteDown.tga",152)
frame.report=CreateFrame("Button","CatQuest335QuestRatingReport",frame,"UIPanelButtonTemplate")
frame.report:SetWidth(300);frame.report:SetHeight(22)
frame.report:SetPoint("BOTTOMLEFT",18,32);frame.report:SetText(L.RATE_REPORT_VOICE)
frame.report:SetScript("OnClick",function()
    if not current or not ns.OpenFeedback then return end
    local item
    for _,candidate in ipairs({ns.state.active or false,ns.state.lastItem or false}) do
        if candidate and candidate.questID==current.id and (candidate.kind=="quest" or candidate.kind=="turnin") then
            item=candidate;break
        end
    end
    ns.OpenFeedback(item or {questID=current.id,kind="turnin",title=current.title})
end)
frame.close=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
frame.close:SetPoint("TOPRIGHT",-4,-4);frame.close:SetScript("OnClick",Dismiss)

local function QueueCompleted(id,title,objective)
    id=tonumber(id)
    if not id or id<=0 or id>=10000000 then return end
    ns.db.lastQuestForRating={id=id,title=title,objective=objective}
    if seen[id] or ns.db.questVotes[id] or ns.db.questRatings==false or not ns.db.enabled then return end
    seen[id]=true
    queue[#queue+1]={id=id,title=title,objective=objective}
    ShowNext()
end

function ns.OpenQuestRating(id,title)
    local last=ns.db.lastQuestForRating
    id=tonumber(id) or (last and last.id)
    if not id or id<=0 or id>=10000000 or id~=math.floor(id) then ns.Print(L.RATE_NOTHING);return false end
    title=title or (last and last.id==id and last.title)
        or (ns.StoryTitle and ns.StoryTitle(id)) or string.format(L.QUEST_N,tostring(id))
    if current and current.id~=id then table.insert(queue,1,current) end
    Dismiss()
    local item={id=id,title=title,objective=last and last.id==id and last.objective,manual=true}
    if CanShow(true) then Display(item) else table.insert(queue,1,item) end
    return true
end

local function InLog(id)
    if not GetNumQuestLogEntries or not GetQuestLogTitle then return false end
    for index=1,GetNumQuestLogEntries() do
        if select(9,GetQuestLogTitle(index))==id then return true end
    end
    return false
end

local function CompletedList()
    local list={}
    if GetQuestsCompleted then GetQuestsCompleted(list) end
    return list
end

-- GetObjectiveText is a global UI value and can still belong to the quest
-- shown immediately before QUEST_COMPLETE. Read the objective from the log
-- entry selected by this exact quest ID first; only fall back to the visible
-- frame when the client has no matching log entry (auto-complete quests).
local function QuestLogObjective(id)
    if not GetNumQuestLogEntries or not GetQuestLogTitle
        or not GetQuestLogQuestText or not SelectQuestLogEntry then return nil end
    for index=1,GetNumQuestLogEntries() do
        if select(9,GetQuestLogTitle(index))==id then
            local previous=GetQuestLogSelection and GetQuestLogSelection() or 0
            local ok,_,objective=pcall(function()
                SelectQuestLogEntry(index)
                return GetQuestLogQuestText()
            end)
            SelectQuestLogEntry(previous)
            if ok and objective and objective~="" then return objective end
            return nil
        end
    end
end

local function Capture()
    local id,title=ns.QuestIDForDialog()
    if id then
        if not title or title=="" then
            title=(ns.StoryTitle and ns.StoryTitle(id)) or string.format(L.QUEST_N,tostring(id))
        end
        local objective=QuestLogObjective(id)
        if not objective or objective=="" then
            objective=GetObjectiveText and GetObjectiveText() or nil
        end
        if objective then objective=objective:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("%s+"," ") end
        snapshot={id=id,title=title,objective=objective,at=GetTime(),inLog=InLog(id),wasCompleted=CompletedList()[id] and true or false}
    else snapshot=nil end
end

function ns.CheckQuestRatingCompletion(confirmedList)
    for id,item in pairs(pending) do
        if GetTime()-item.at>60 then pending[id]=nil
        elseif (item.inLog and not InLog(id))
            or (not item.inLog and not item.wasCompleted and confirmedList and confirmedList[id]) then
            pending[id]=nil
            QueueCompleted(id,item.title,item.objective)
        end
    end
end

local function RewardClaimed()
    if not snapshot or GetTime()-snapshot.at>60 then return end
    local item={}
    for key,value in pairs(snapshot) do item[key]=value end
    item.at=GetTime()
    pending[item.id]=item
    ns.After(0.3,function() ns.CheckQuestRatingCompletion() end)
    if not item.inLog and not item.wasCompleted and QueryQuestsCompleted then QueryQuestsCompleted() end
end
if hooksecurefunc and GetQuestReward then hooksecurefunc("GetQuestReward",RewardClaimed) end
if hooksecurefunc and AbandonQuest then
    hooksecurefunc("AbandonQuest",function() pending={} end)
end

local events=CreateFrame("Frame","CatQuest335QuestRatingEvents")
for _,event in ipairs({"QUEST_COMPLETE","QUEST_LOG_UPDATE","QUEST_QUERY_COMPLETE","QUEST_FINISHED","PLAYER_LOGIN"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent",function(_,event)
    if event=="QUEST_COMPLETE" then Capture()
    elseif event=="QUEST_QUERY_COMPLETE" then ns.CheckQuestRatingCompletion(CompletedList())
    elseif event=="PLAYER_LOGIN" then
        -- Bridge votes acknowledge durable browser storage. Retry any local
        -- click that did not reach it before a reload, after startup markers.
        local delay=8
        for id,vote in pairs(ns.db.questVotePending) do
            local quest,value=id,vote
            ns.After(delay,function() Transmit(quest,value) end);delay=delay+5
        end
    else ns.CheckQuestRatingCompletion() end
end)
local elapsed=0
events:SetScript("OnUpdate",function(_,dt)
    elapsed=elapsed+dt
    if elapsed<0.5 then return end
    elapsed=0
    if not ns.db.enabled or (ns.db.questRatings==false and current and not current.manual) then Dismiss() end
    ShowNext()
    ns.CheckQuestRatingCompletion()
end)

SLASH_CATQUEST335RATE1="/cqrate"
SlashCmdList.CATQUEST335RATE=function(text) ns.OpenQuestRating(tonumber(text)) end
local oldRefresh=ns.RefreshTexts
ns.RefreshTexts=function()
    if oldRefresh then oldRefresh() end
    frame.up.label:SetText(L.RATE_LIKE);frame.down.label:SetText(L.RATE_DISLIKE)
    frame.report:SetText(L.RATE_REPORT_VOICE)
    if current and frame:IsShown() then Display(current) end
end
