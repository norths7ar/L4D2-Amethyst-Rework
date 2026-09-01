//-----------------------------------------------------------------------------------------------------------------------------
// SETTINGS loaded at the start of the game
//-----------------------------------------------------------------------------------------------------------------------------
DirectorOptions <-
{
	ActiveChallenge 				= 1
	cm_AggressiveSpecials 			= true
	cm_ShouldHurry 					= 1
	ShouldAllowSpecialsWithTank 	= 1
	ShouldAllowMobsWithTank 		= 0
	cm_SpecialRespawnInterval 		= 0 // Time for an SI spawn slot to become available
	cm_SpecialSlotCountdownTime 	= 0
	SpecialRespawnInterval			= 0
	SpecialInitialSpawnDelayMin 	= 0 // 出门后多久刷特感
	SpecialInitialSpawnDelayMax 	= 0
	cm_HeadshotOnly 				= 0

	// SPAWN_NO_PREFERENCE = -1, SPAWN_BEHIND_SURVIVORS = 1, SPAWN_BATTLEFIELD = 2, SPAWN_POSITIONAL = 3, SPAWN_SPECIALS_ANYWHERE = 4
	PreferredSpecialDirection 		= 2

	RelaxMaxInterval 				= 0 // Maximum time to spend in the RELAX tempo.
	RelaxMinInterval 				= 0 // Minimum time to spend in the RELAX tempo.

	// 这三个参数是旧版刷新机制用的，新版不要修改！！！
	DominatorLimit 			= 12
	cm_BaseSpecialLimit 	= 12
	cm_MaxSpecials 			= 12

	// 这里不用管，仅初始化。
	BoomerLimit 			= 1
	SpitterLimit 			= 0
	HunterLimit 			= 1
	JockeyLimit 			= 1
	ChargerLimit 			= 1
	SmokerLimit 			= 0
}

// 新版特感刷新参数
::Waves <- {
	Enabled				= true		// 新版特感刷新机制开关
}

// 旧版特感刷新参数
// 到 update_diff_old() 中修改，此处仅初始化。
ModeData <-{
	g_nSI				= 24		// 特感数量
	g_nTime				= 0			// 特感复活间隔
}

// 插件修改特感刷新参数时会重新读取/执行整个脚本文件。
// 如果这里每次都用 <- 重新创建 HUDInfo，会把正在游戏中靠事件累积的
// si_count 直接清零，导致后续 player_death 里的 si_count[name]--
// 从 0 减到 -1，数量计算就错乱了。所以只在 HUDInfo 尚不存在时才初始化，
// 脚本被重载时保留已有的存活特感计数。
if (!("HUDInfo" in getroottable()))
{
	::HUDInfo <- {
		si_count = { normal=0, smoker=0, boomer=0, hunter=0, spitter=0, jockey=0, charger=0 }
		si_names = [ "normal", "smoker", "boomer", "hunter", "spitter", "jockey", "charger"]
		si_text = ""
		hud_mode = "stats"
	}
}

function update_diff()
{
	Waves.Enabled = Convars.GetStr("ast_wave_spawn").tointeger();

	Waves.Enabled ? update_diff_new() : update_diff_old();

	if (HUDInfo.hud_mode == "stats") {
		g_ModeScript.UpdateHUDStats();
	} else {
		g_ModeScript.UpdateHUDSI();
	}
}

//-----------------------------------------------------------------------------------------------------------------------------
// Function
//-----------------------------------------------------------------------------------------------------------------------------
function update_diff_new()
{
    local difficulty = Convars.GetStr("das_fakedifficulty");
    local timer_new = Convars.GetStr("ast_sitimer_new").tofloat();
    local limit_new = Convars.GetStr("ast_silimit_new").tointeger();

    local hunterLimit = 0;
    local smokerLimit = 0;
    local boomerLimit = 0;
    local spitterLimit = 0;
    local jockeyLimit = 0;
    local chargerLimit = 0;

	// 设置特感数量基准
    switch (difficulty) {
        case "1":
            hunterLimit = 1;
            smokerLimit = 1;
            boomerLimit = 0;
            spitterLimit = 0;
            jockeyLimit = 1;
            chargerLimit = 1;
            DirectorOptions.PreferredSpecialDirection = 2;
            break;

        case "2":
            hunterLimit = 2;
            smokerLimit = 0;
            boomerLimit = 1;
            spitterLimit = 0;
            jockeyLimit = 1;
            chargerLimit = 1;
            DirectorOptions.PreferredSpecialDirection = 2;
            break;

        case "3":
            hunterLimit = 3;
            smokerLimit = 1;
            boomerLimit = 1;
            spitterLimit = 1;
            jockeyLimit = 2;
            chargerLimit = 2;
            DirectorOptions.PreferredSpecialDirection = 2;
            break;

        case "4":
            hunterLimit = 4;
            smokerLimit = 1;
            boomerLimit = 1;
            spitterLimit = 1;
            jockeyLimit = 2;
            chargerLimit = 2;
            DirectorOptions.PreferredSpecialDirection = 2;
            break;
    }
	// 计算 baseTotal 为各特感上限之和
	local baseTotal = hunterLimit + smokerLimit + boomerLimit + spitterLimit + jockeyLimit + chargerLimit;
    local scale = 1.0;
    if (limit_new > 0 && baseTotal > 0) {
        if (limit_new <= baseTotal) {
            scale = 1.0;
        } else {
            scale = limit_new.tofloat() / baseTotal.tofloat();
        }
    }

    // 以 case 中原始 limit 为基准，按 ast_silimit_new 的目标值做比例放大。
    if (limit_new <= baseTotal) {
        DirectorOptions.HunterLimit = hunterLimit > 0 ? hunterLimit : 0;
        DirectorOptions.SmokerLimit = smokerLimit > 0 ? smokerLimit : 0;
        DirectorOptions.BoomerLimit = boomerLimit > 0 ? boomerLimit : 0;
        DirectorOptions.SpitterLimit = spitterLimit > 0 ? spitterLimit : 0;
        DirectorOptions.JockeyLimit = jockeyLimit > 0 ? jockeyLimit : 0;
        DirectorOptions.ChargerLimit = chargerLimit > 0 ? chargerLimit : 0;
    } else {
        DirectorOptions.HunterLimit = hunterLimit > 0 ? ((hunterLimit * scale) + 0.999999).tointeger() : 0;
        DirectorOptions.SmokerLimit = smokerLimit > 0 ? ((smokerLimit * scale) + 0.999999).tointeger() : 0;
        DirectorOptions.BoomerLimit = boomerLimit > 0 ? ((boomerLimit * scale) + 0.999999).tointeger() : 0;
        DirectorOptions.SpitterLimit = spitterLimit > 0 ? ((spitterLimit * scale) + 0.999999).tointeger() : 0;
        DirectorOptions.JockeyLimit = jockeyLimit > 0 ? ((jockeyLimit * scale) + 0.999999).tointeger() : 0;
        DirectorOptions.ChargerLimit = chargerLimit > 0 ? ((chargerLimit * scale) + 0.999999).tointeger() : 0;
    }
}

// 旧版本刷新机制
function update_diff_old()
{
	local difficulty = Convars.GetStr("das_fakedifficulty");
	local timer = Convars.GetStr("ast_sitimer");
	switch (difficulty) {
		case "1":
			DirectorOptions.HunterLimit = 1
			DirectorOptions.SmokerLimit = 1
			DirectorOptions.BoomerLimit = 0
			DirectorOptions.SpitterLimit = 0
			DirectorOptions.JockeyLimit = 1
			DirectorOptions.ChargerLimit = 1
			DirectorOptions.PreferredSpecialDirection = 4
			switch (timer) {
				case "0":
					ModeData.g_nTime = 6
					ModeData.g_nSI = 2
					break;
				case "1":
					ModeData.g_nTime = 3
					ModeData.g_nSI = 3
					break;
				case "2":
					ModeData.g_nTime = 2
					ModeData.g_nSI = 3
					break;
				case "3":
					ModeData.g_nTime = 0
					ModeData.g_nSI = 3
					break;
				default:
					ModeData.g_nTime = 3
					ModeData.g_nSI = 3
					break;
			}
			break;
		case "2":
			DirectorOptions.HunterLimit = 2
			DirectorOptions.SmokerLimit = 0
			DirectorOptions.BoomerLimit = 1
			DirectorOptions.SpitterLimit = 0
			DirectorOptions.JockeyLimit = 1
			DirectorOptions.ChargerLimit = 1
			DirectorOptions.PreferredSpecialDirection = 4
			switch (timer) {
				case "0":
					ModeData.g_nTime = 10
					ModeData.g_nSI = 3
					break;
				case "1":
					ModeData.g_nTime = 8
					ModeData.g_nSI = 4
					break;
				case "2":
					ModeData.g_nTime = 6
					ModeData.g_nSI = 4
					break;
				case "3":
					ModeData.g_nTime = 0
					ModeData.g_nSI = 4
					break;
				default:
					ModeData.g_nTime = 8
					ModeData.g_nSI = 4
					break;
			}
			break;
		case "3":
			DirectorOptions.HunterLimit = 3
			DirectorOptions.SmokerLimit = 1
			DirectorOptions.BoomerLimit = 1
			DirectorOptions.SpitterLimit = 1
			DirectorOptions.JockeyLimit = 1
			DirectorOptions.ChargerLimit = 1
			DirectorOptions.PreferredSpecialDirection = 1
			ModeData.g_nSI = 6
			switch (timer) {
				case "0":
					ModeData.g_nTime = 26
					break;
				case "1":
					ModeData.g_nTime = 22
					break;
				case "2":
					ModeData.g_nTime = 18
					break;
				case "3":
					ModeData.g_nTime = 0
					break;
				default:
					ModeData.g_nTime = 22
					break;
			}
			break;
		case "4":
			DirectorOptions.HunterLimit = 4
			DirectorOptions.SpitterLimit = 1
			DirectorOptions.SmokerLimit = 1
			DirectorOptions.BoomerLimit = 1
			DirectorOptions.JockeyLimit = 1
			DirectorOptions.ChargerLimit = 1
			DirectorOptions.PreferredSpecialDirection = 1
			ModeData.g_nSI = 6
			switch (timer) {
				case "0":
					ModeData.g_nTime = 22
					break;
				case "1":
					ModeData.g_nTime = 17
					break;
				case "2":
					ModeData.g_nTime = 14
					break;
				case "3":
					ModeData.g_nTime = 0
					break;
				default:
					ModeData.g_nTime = 17
					break;
			}
			break;
		default:
			break;
	}

	DirectorOptions.cm_BaseSpecialLimit 					= ModeData.g_nSI
	DirectorOptions.cm_MaxSpecials 							= ModeData.g_nSI
	DirectorOptions.DominatorLimit 							= ModeData.g_nSI
	DirectorOptions.cm_SpecialRespawnInterval 				= ModeData.g_nTime
	DirectorOptions.cm_SpecialSlotCountdownTime 			= ModeData.g_nTime
}

function InitHUD() {
	// HUD setup
	ModeHUD <- {
		Fields = {
			SIInfo = {
				slot = HUD_TICKER,
				flags = HUD_FLAG_NOBG | HUD_FLAG_ALIGN_CENTER,
				dataval = HUDInfo.si_text,
				name = "siInfo"
			}
		}
	}

	// load the ModeHUD table
	HUDSetLayout(ModeHUD);
}

function UpdateHUDSI()
{
	HUDInfo.hud_mode = "si";

    // 显示特感
	HUDInfo.si_text = "";
    foreach (name in HUDInfo.si_names)
    {
        local count = HUDInfo.si_count[name];
		if (count == 0) continue;

    	// 名称首字母大写
    	local displayName = name.slice(0, 1).toupper() + name.slice(1);

		if (count == 1) {
			HUDInfo.si_text += format("%s  ", displayName);
		} else {
			HUDInfo.si_text += format("%s * %d  ", displayName, count);
		}
    }

	InitHUD();
}

function UpdateHUDStats()
{
	HUDInfo.hud_mode = "stats";
	local timer_new = Convars.GetStr("ast_sitimer_new").tofloat();
	local limit_new = Convars.GetStr("ast_silimit_new").tointeger();

	HUDInfo.si_text = format("当前特感刷新速度：%.1f秒%d特", timer_new, limit_new);
	HUDInfo.si_text += "\n使用 !si 修改";

	InitHUD();
}

//-----------------------------------------------------------------------------------------------------------------------------
// Hook Game Events
//-----------------------------------------------------------------------------------------------------------------------------

// function OnGameEvent_player_connect( params )
// 无法获取 team

// function OnGameEvent_player_team( params )
// 无法获取 ZombieType

//        ZOMBIE_NORMAL = 0
//        ZOMBIE_SMOKER = 1
//        ZOMBIE_BOOMER = 2
//        ZOMBIE_HUNTER = 3
//        ZOMBIE_SPITTER = 4
//        ZOMBIE_JOCKEY = 5
//        ZOMBIE_CHARGER = 6
//        ZOMBIE_WITCH = 7
//        ZOMBIE_TANK = 8
//        ZSPAWN_MOB = 10
//        ZSPAWN_MUDMEN = 12
//        ZSPAWN_WITCHBRIDE = 11

function OnGameEvent_player_first_spawn( params )
{
	if (!Waves.Enabled) return;

	local client = GetParamsItem(params, "userid");
	local clientEnt = GetPlayerFromUserID(client);
	local isBot = GetParamsItem(params, "isbot");

	if (clientEnt == null) return;
	local team = GetClientTeam(clientEnt);
	local zombieType = clientEnt.GetZombieType();

	// AI 特感
	if (team == 3 && isBot && zombieType < ZOMBIE_WITCH)
	{
		// HUD
		local name = HUDInfo.si_names[zombieType];
		HUDInfo.si_count[name]++;
		UpdateHUDSI();
	}
}

function OnGameEvent_player_death( params )
{
	if (!Waves.Enabled) return;

	local attacker = GetParamsItem(params, "attacker");
	local victimname = GetParamsItem(params, "victimname");
	if (victimname == "Infected" || victimname == "Witch") return; // 普通感染者 / Witch

	local victim = GetParamsItem(params, "userid");
	local victimEnt = GetPlayerFromUserID(victim);
	local victimTeam = GetClientTeam(victimEnt);
	local zombieType = victimEnt.GetZombieType();

	if ( victimTeam == 3 && zombieType < ZOMBIE_WITCH )
	{
		// HUD
		local name = HUDInfo.si_names[zombieType];
		HUDInfo.si_count[name]--;
		UpdateHUDSI();
	}
}

function OnGameEvent_round_start( params )
{
	if (!Waves.Enabled) return;

	foreach (name in HUDInfo.si_names)
	{
        HUDInfo.si_count[name] = 0;
    }

	UpdateHUDStats();
}

//-----------------------------------------------------------------------------------------------------------------------------
// Utils
//-----------------------------------------------------------------------------------------------------------------------------

// 1: Spectator
// 2: Survivor
// 3: Infected
function GetClientTeam( clientEnt )
{
	return NetProps.GetPropIntArray(clientEnt, "m_iTeamNum", 0);
}

function GetParamsItem( params, item ) {
	if (params[item] != null && params[item] != "")
		return params[item];
	else return null;
}

//-----------------------------------------------------------------------------------------------------------------------------
// gogo
//-----------------------------------------------------------------------------------------------------------------------------
update_diff();
if ("update_diff" in g_ModeScript)
{
	g_ModeScript.update_diff();
}
Msg("======== astmod.nut: Reload Complete. ========\n");
