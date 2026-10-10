// Based on Kiop AcidVisual 0.4, Workshop 3806318059.
// AstRedux integration: mode-scoped lifecycle; original visual algorithm retained.
// AcidVisual 0.4：补充地面酸液放大 50%
if ("AcidVisual" in getroottable()) {
    ::AcidVisual.Enabled = false;
    foreach (item in ::AcidVisual.Items)
        if (item.ent != null && item.ent.IsValid()) item.ent.Kill();
    if (::AcidVisual.Runner != null && ::AcidVisual.Runner.IsValid()) {
        AddThinkToEnt(::AcidVisual.Runner, null);
        ::AcidVisual.Runner.Kill();
    }
}
::AcidVisual <- {
    Version = "0.4-native-particles-r75-scale150"
    Radius = 75.0 // 控制外围补充点的布置半径，不修改游戏伤害
    RingFraction = 0.65 // 外围补充点位于参考半径的 65%
    RingPoints = 0 // 每节点一个补充效果；放大由 PCF 完成，无需外围叠加
    Effect = "spitter_areaofdenial" // 直接使用原版名称；本地配套 PCF 将地面效果放大 1.5 倍
    EffectChoices = ["spitter_areaofdenial"] // 仅保留原版名称；不再提供原尺寸切换
    EffectChoice = 0
    FirstSpawnTime = -1.0
    AutoReported = false
    CachedEffects = {}
    Lift = 2.0
    Interval = 0.20
    MaxNodes = 128
    MaxParticles = 256 // 仅限制本脚本创建的粒子实体
    MaxWorldEntities = 1800 // 保守计数保护，不是引擎上限，也不限制地图生成实体
    Items = []
    Runner = null
    Enabled = false
    Fault = null
    Reason = "none"
    LastNodes = 0
    LastPools = 0
    LastWorld = 0
    LastWanted = 0
    LastStatus = -100.0

    // 默认正常显示只读模式用于区分节点读取与实体创建引发的问题
    ReadOnly = false
    AllowRemoteDiagnostics = false // 默认仅本地房主可切换模式；状态查询不受限
    TraceArmed = false
    TraceFrames = 0
    TraceActive = false
    TraceSpawned = false
    LastPhase = "idle"

    function Mark(phase) {
        LastPhase=phase;
        if (TraceActive) printl("[Acid4 TRACE] "+phase);
    }
    function BeginTrace(nodes) {
        if (TraceArmed && nodes>0) { TraceArmed=false; TraceFrames=2; }
        TraceActive=TraceFrames>0;
        TraceSpawned=false;
        if (TraceActive) TraceFrames--;
    }
    function SpawnVisual(classname, kv) {
        local data=clone kv;
        local pos=("origin" in data)?data.origin:Vector(0,0,0);
        data.origin <- format("%.6f %.6f %.6f",pos.x,pos.y,pos.z);
        local traceThis=TraceActive && !TraceSpawned;
        if (traceThis) { TraceSpawned=true; Mark("spawn.begin "+classname); }
        local e=SpawnEntityFromTable(classname,data);
        if (traceThis) Mark("spawn.return "+classname);
        if (e!=null && e.IsValid()) {
            e.SetOrigin(pos);
            if (traceThis) Mark("position.set "+classname);
        }
        return e;
    }
    function CanControl(p) {
        if (AllowRemoteDiagnostics) return true;
        if (!("userid" in p) || !("GetPlayerFromUserID" in getroottable()) || !("GetListenServerHost" in getroottable())) return false;
        local player=GetPlayerFromUserID(p.userid);
        return player!=null && player==GetListenServerHost();
    }
    function HandleChat(p) {
        if (!("text" in p)) return;
        local text=p.text.tolower();
        if (text=="!acid4status") { ChatStatus(); return; }
        if (text!="!acid4off" && text!="!acid4read" && text!="!acid4on" && text!="!acid4trace" && text!="!acid4next") return;
        if (!CanControl(p)) return;
        if (text=="!acid4off") { Stop(); printl("[Acid4] OFF: no polling or effects. Compare the next acid pool."); }
        else if (text=="!acid4read") { Start(); ReadOnly=true; Clear(); printl("[Acid4] READ ONLY: node polling, no visual entities."); }
        else if (text=="!acid4on") { ReadOnly=false; Start(); }
        else if (text=="!acid4trace") { TraceArmed=true; printl("[Acid4] Trace armed for two ticks with acid nodes."); }
        else if (text=="!acid4next") { printl("[Acid4] Native effect only; size is controlled by the client PCF. Restart after changing PCF."); }
        ChatStatus();
    }

    Required = ["m_fireCount", "m_fireXDelta", "m_fireYDelta", "m_fireZDelta"]

    function Remove(e) {
        if (e != null && e.IsValid()) {
            // 直接删除本脚本的粒子实体，不再依赖实体输入接口进行异常清理
            // 客户端粒子的消散动画仍可能短暂残留
            e.Kill();
        }
    }
    function Clear() {
        foreach (item in Items) Remove(item.ent);
        Items.clear();
    }
    function Stop() {
        Enabled = false;
        Clear();
        if (Runner != null && Runner.IsValid()) {
            AddThinkToEnt(Runner, null);
            Runner.Kill();
        }
        Runner = null;
    }
    function ReadNodes() {
        local nodes = [], e = null;
        LastPools = 0; LastNodes = 0;
        while ((e = Entities.FindByClassname(e, "insect_swarm")) != null) {
            LastPools++;
            foreach (key in Required)
                if (!NetProps.HasProp(e, key)) throw "Missing netprop: " + key;
            local n = NetProps.GetPropInt(e, "m_fireCount");
            if (n < 0 || n > MaxNodes) throw "Unsupported node count: " + n;
            foreach (key in Required)
                if (key != "m_fireCount" && NetProps.GetPropArraySize(e, key) < n)
                    throw "Short node array: " + key;
            for (local i = 0; i < n; i++) {
                local p = e.GetOrigin() + Vector(
                    NetProps.GetPropIntArray(e, "m_fireXDelta", i),
                    NetProps.GetPropIntArray(e, "m_fireYDelta", i),
                    NetProps.GetPropIntArray(e, "m_fireZDelta", i));
                nodes.append({ owner=e, index=i, p=p });
            }
        }
        LastNodes = nodes.len();
        return nodes;
    }
    function Same(a,b) {
        return fabs(a.x-b.x)<0.1 && fabs(a.y-b.y)<0.1 && fabs(a.z-b.z)<0.1;
    }
    function Build(nodes) {
        local wanted = [];
        foreach (node in nodes) {
            // 默认只放中心，启用外围点时按75参考半径布点
            for (local slot=0; slot<=RingPoints; slot++) {
                local p = node.p + Vector(0,0,Lift);
                if (slot>0) {
                    local angle = 6.283185307179586*(slot-1)/RingPoints;
                    p += Vector(cos(angle),sin(angle),0)*(Radius*RingFraction);
                }
                wanted.append({ owner=node.owner, index=node.index, slot=slot, p=p });
            }
        }
        return wanted;
    }
    function Matches(item,w) {
        return item.owner==w.owner && item.index==w.index && item.slot==w.slot && Same(item.p,w.p);
    }
    function CountWorld() {
        local n=0, e=Entities.First();
        while (e!=null) { n++; e=Entities.Next(e); }
        return n;
    }
    function Limit(reason) {
        Clear();
        if (Reason!=reason) printl("[Acid4] paused: "+reason);
        Reason=reason;
    }
    function Sync(wanted) {
        // 先清理消失或移动的节点；不移动已经播放的粒子，以免拖出绿色尾迹
        for (local i=Items.len()-1; i>=0; i--) {
            local keep=false;
            if (Items[i].ent!=null && Items[i].ent.IsValid())
                foreach (w in wanted) if (Matches(Items[i],w)) { keep=true; break; }
            if (!keep) { Remove(Items[i].ent); Items.remove(i); }
        }
        local need=wanted.len()-Items.len();
        Mark("world_count.begin");
        LastWorld=CountWorld();
        Mark("world_count.end");
        if (need>0 && LastWorld+need>MaxWorldEntities) {
            Limit("world_entity_budget"); return;
        }
        foreach (w in wanted) {
            local found=false;
            foreach (item in Items) if (Matches(item,w)) { found=true; break; }
            if (found) continue;
            local e=SpawnVisual("info_particle_system", {
                targetname="acid4_visual_particle", origin=w.p,
                effect_name=Effect, start_active=0
            });
            if (e==null || !e.IsValid()) throw "Cannot create particle entity";
            Items.append({ ent=e, owner=w.owner, index=w.index, slot=w.slot, p=w.p });
            // !self 指向最后一个参数 caller，精确启动当前粒子实体
            // 延迟到实体创建之后再发送启动输入，给初始化留出时间
            DoEntFire("!self","Start","",0.10,null,e);
            if (FirstSpawnTime<0) FirstSpawnTime=Time();
        }
        Reason="none";
    }
    function Tick() {
        if (Convars.GetStr("mp_gamemode") != "astredux") {
            Stop(); Reason="mode_inactive"; return Interval;
        }
        if (!Enabled) return Interval;
        try {
            if (Radius<=0 || Radius>300 || RingPoints<0 || RingPoints>12 || RingFraction<0 || RingFraction>1)
                throw "Invalid visual configuration";
            TraceActive=TraceFrames>0 || (TraceArmed && LastNodes>0);
            Mark("read.begin");
            local nodes=ReadNodes();
            Mark("read.end");
            BeginTrace(nodes.len());
            LastWanted=nodes.len()*(RingPoints+1);
            if (ReadOnly) { Mark("read_only"); TraceActive=false; return Interval; }
            Mark("sync.begin");
            if (nodes.len()>MaxNodes) Limit("node_budget");
            else if (LastWanted>MaxParticles) Limit("particle_budget");
            else Sync(Build(nodes));
            Mark("sync.end");
            TraceActive=false;
            // 第一次生成后自动输出诊断，聊天回调被其他模组拦截时也可查看
            if (!AutoReported && FirstSpawnTime>=0 && Time()-FirstSpawnTime>=0.5) {
                AutoReported=true; printl(Status()); PrintParticleState();
            }
        } catch(err) {
            Fault=err.tostring();
            Stop();
            printl("[Acid4] stopped: "+Fault);
        }
        return Interval;
    }
    function Status() {
        local s="[Acid4 "+Version+"] enabled="+Enabled+" radius="+Radius
            +" pools="+LastPools+" nodes="+LastNodes+" particles="+Items.len()
            +" wanted="+LastWanted+" world="+LastWorld+" paused="+Reason
            +" readOnly="+ReadOnly+" phase="+LastPhase+" effect="+Effect;
        if (Fault!=null) s+=" error="+Fault;
        return s;
    }
    function ChatStatus() {
        if (Time()-LastStatus<2.0) return;
        LastStatus=Time();
        printl(Status());
        PrintParticleState();
        Say(null,Status(),false);
    }
    function PrintParticleState() {
        // 这里只读取服务器状态，不能据此保证客户端画面已显示
        local printed=0;
        foreach (item in Items) {
            if (item.ent==null || !item.ent.IsValid()) continue;
            local e=item.ent;
            local line="[Acid4 particle]";
            foreach (key in ["m_bActive","m_iEffectIndex"]) {
                if (NetProps.HasProp(e,key)) line+=" "+key+"="+NetProps.GetPropInt(e,key);
                else line+=" "+key+"=unavailable";
            }
            local p=e.GetOrigin();
            line+=" positionOK="+Same(p,item.p);
            printl(line);
            if (++printed>=3) break;
        }
        if (printed==0) printl("[Acid4 particle] none; check enabled/nodes/paused/error.");
    }
    function CycleEffect() {
        EffectChoice=(EffectChoice+1)%EffectChoices.len();
        Effect=EffectChoices[EffectChoice];
        ReadOnly=false;
        Start();
        printl("[Acid4] Trying effect: "+Effect);
    }
    function Start() {
        if (Convars.GetStr("mp_gamemode") != "astredux") {
            Stop(); Reason="mode_inactive"; return;
        }
        Stop(); Fault=null; Reason="none";
        LastNodes=0; LastPools=0; LastWanted=0; LastWorld=0;
        FirstSpawnTime=-1.0; AutoReported=false;
        try {
            if (!("DoEntFire" in getroottable())) throw "Missing API: DoEntFire";
            if (!(Effect in CachedEffects)) {
                PrecacheEntityFromTable({ classname="info_particle_system", effect_name=Effect, origin="0 0 0" });
                CachedEffects[Effect] <- true;
            }
            Runner=SpawnVisual("info_target", { targetname="acid4_visual_runner" });
            if (Runner==null || !Runner.IsValid()) throw "Cannot create updater";
            Runner.ValidateScriptScope();
            Runner.GetScriptScope().Acid4Think <- function() { return ::AcidVisual.Tick(); };
            Enabled=true;
            AddThinkToEnt(Runner,"Acid4Think");
            printl("[Acid4] Console: say !acid4status | say !acid4next | say !acid4trace | say !acid4off | say !acid4read | say !acid4on");
            printl("[Acid4] Loaded "+Version+"; chat !acid4status; ground PCF scale=1.5; visual boundary is NOT a damage hitbox.");
        } catch(err) { Fault=err.tostring(); Stop(); printl("[Acid4] stopped: "+Fault); }
    }
};
// 每个脚本虚拟机只注册一次回调，重复加载不会叠加监听器
if (!("AcidVisualEvents" in getroottable())) {
    ::AcidVisualEvents <- {
        function OnGameEvent_round_start(p) { ::AcidVisual.Start(); }
        function OnGameEvent_round_end(p) { ::AcidVisual.Stop(); }
        function OnGameEvent_map_transition(p) { ::AcidVisual.Stop(); }
        function OnGameEvent_player_say(p) {
            ::AcidVisual.HandleChat(p);
        }
    };
    __CollectEventCallbacks(::AcidVisualEvents,"OnGameEvent_","GameEventCallbacks",RegisterScriptGameEventListener);
}
::AcidVisual.Start();
