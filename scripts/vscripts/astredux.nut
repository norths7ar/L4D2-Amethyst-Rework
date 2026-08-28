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
	PreferredSpecialDirection 		= 4
	cm_HeadshotOnly 				= 0

	RelaxMaxInterval 				= 0 // Maximum time to spend in the RELAX tempo.
	RelaxMinInterval 				= 0 // Minimum time to spend in the RELAX tempo.


	DominatorLimit 			= 12
	cm_BaseSpecialLimit 	= 12
	cm_MaxSpecials 			= 12
	BoomerLimit 			= 1
	SpitterLimit 			= 0
	HunterLimit 			= 1
	JockeyLimit 			= 1
	ChargerLimit 			= 1
	SmokerLimit 			= 0
}

// ModeData 两个值不直接控制特感刷新，可以理解成上限
ModeData <-{
	g_nSI				= 24		// 数值必须比所有特感 Limit 加起来都要大（包含 Tank），总之越大越好
	g_nTime				= 0			// 0秒，保证需要时能尽快刷出
}

// 特感刷新参数
::Waves <- {
	Enabled				= true		// 新版特感刷新机制开关
	MaxSILimit 			= 3			// 同场特感数量
	SpawnTime 			= 3			// 复活间隔
	SpawnedSICount 		= 0			// 用于脚本判断，不需要修改。当前波次刷出的特感数量
	AliveSICount 		= 0			// 用于脚本判断，不需要修改。当前场上的特感数量
	HasFirstDeath 		= false		// 用于脚本判断，不需要修改。当前波次是否有特感已经死亡
	FirstDeathTime		= -1		// 用于脚本判断，不需要修改。第一只的死亡时间
	BonusSpawnTime		= 0			// 用于脚本判断，不需要修改。击杀的奖励时间
}

::HUDInfo <- {
    si_count = { normal=0, smoker=0, boomer=0, hunter=0, spitter=0, jockey=0, charger=0 }
    si_names = [ "normal", "smoker", "boomer", "hunter", "spitter", "jockey", "charger"]
	si_text = ""
	wave_text = ""
}

function update_diff()
{
	Waves.Enabled = Convars.GetStr("ast_wave_spawn").tointeger();

	Waves.Enabled ? update_diff_new() : update_diff_old();

	g_ModeScript.UpdateHUDWave(); // 刷新安全区的 HUD
}

//-----------------------------------------------------------------------------------------------------------------------------
// Function
//-----------------------------------------------------------------------------------------------------------------------------

// ::CheckBonusTime <- function() {
// 	if (Waves.BonusSpawnTime = 0.0) {
// 		// 奖励时间结束，强制刷新
// 		// EntFire("worldspawn", "CallScriptFunction", "ResetWave", Waves.BonusSpawnTime);
// 		ResetWave();
// 		// SendToServerConsole(format("say time: %.2f", Time()));
// 	} else {
// 		// 等待奖励时间
// 		// SendToServerConsole( format("say BonusTime: %.2f, time: %.2f", Waves.BonusSpawnTime, Time()) );
// 		EntFire("worldspawn", "CallScriptFunction", "CheckBonusTime", Waves.BonusSpawnTime);
// 		Waves.BonusSpawnTime = 0.0;
// 	}
// };

// ::ResetWave <- function() {
// 	// 记录存活的特感数量
// 	Waves.SpawnedSICount = Waves.AliveSICount;
// 	Waves.HasFirstDeath = false;
// 	// 强制刷新
// 	Director.ResetSpecialTimers();
// };

function update_diff_new()
{
	local difficulty = Convars.GetStr("astredux_profile_current");
	local timer_new = Convars.GetStr("ast_sitimer_new").tofloat();
	local limit_new = Convars.GetStr("ast_silimit_new").tointeger();

	DirectorOptions.HunterLimit = Convars.GetStr("astredux_si_hunter_limit").tointeger();
	DirectorOptions.SmokerLimit = Convars.GetStr("astredux_si_smoker_limit").tointeger();
	DirectorOptions.BoomerLimit = Convars.GetStr("astredux_si_boomer_limit").tointeger();
	DirectorOptions.SpitterLimit = Convars.GetStr("astredux_si_spitter_limit").tointeger();
	DirectorOptions.JockeyLimit = Convars.GetStr("astredux_si_jockey_limit").tointeger();
	DirectorOptions.ChargerLimit = Convars.GetStr("astredux_si_charger_limit").tointeger();
	DirectorOptions.PreferredSpecialDirection = Convars.GetStr("astredux_si_preferred_direction").tointeger();

	DirectorOptions.cm_BaseSpecialLimit 					= ModeData.g_nSI
	DirectorOptions.cm_MaxSpecials 							= ModeData.g_nSI
	DirectorOptions.DominatorLimit 							= ModeData.g_nSI
	DirectorOptions.cm_SpecialRespawnInterval 				= ModeData.g_nTime
	DirectorOptions.cm_SpecialSlotCountdownTime 			= ModeData.g_nTime
	Waves.MaxSILimit										= limit_new
	Waves.SpawnTime											= timer_new
}

// 旧版本刷新机制
// 替换时注意修改 MapData 为 ModeData
function update_diff_old()
{
	local difficulty = Convars.GetStr("astredux_profile_current");
	local timer = Convars.GetStr("ast_sitimer");
	DirectorOptions.HunterLimit = Convars.GetStr("astredux_si_hunter_limit").tointeger();
	DirectorOptions.SmokerLimit = Convars.GetStr("astredux_si_smoker_limit").tointeger();
	DirectorOptions.BoomerLimit = Convars.GetStr("astredux_si_boomer_limit").tointeger();
	DirectorOptions.SpitterLimit = Convars.GetStr("astredux_si_spitter_limit").tointeger();
	DirectorOptions.JockeyLimit = Convars.GetStr("astredux_si_jockey_limit").tointeger();
	DirectorOptions.ChargerLimit = Convars.GetStr("astredux_si_charger_limit").tointeger();
	DirectorOptions.PreferredSpecialDirection = Convars.GetStr("astredux_si_preferred_direction").tointeger();
	switch (difficulty) {
		case "1":
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

function UpdateHUDWave()
{
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
		// if ( Waves.SpawnedSICount >= Waves.MaxSILimit ) { // 超过一波数量
		// 	// 直接 Kill 掉会导致原地留下烟雾口水之类的特效，可能需要提早，不过影响不大
		// 	clientEnt.Kill();
		// 	// Say(clientEnt, "Blocked from spawning.", false);
		// 	return;
		// }
		// Waves.SpawnedSICount++;
		// Waves.AliveSICount++;
		// // Say(clientEnt, "SpawnedSICount: " + Waves.SpawnedSICount, false);

		// HUD
		local name = HUDInfo.si_names[zombieType];
		HUDInfo.si_count[name]++;
		UpdateHUDSI();
	}
	// if (team == 3 && zombieType == ZOMBIE_TANK) // 克局特感 -1
	// {
	// 	if (Waves.MaxSILimit > 0)
	// 		Waves.MaxSILimit--;
	// }
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
		// Waves.AliveSICount--;
		// HUD
		local name = HUDInfo.si_names[zombieType];
		HUDInfo.si_count[name]--;
		UpdateHUDSI();

		// // 获取当前时间
		// local time = Time();
		// // 如果是第一只死的
		// if (!Waves.HasFirstDeath)
		// {
		// 	Waves.HasFirstDeath = true;
		// 	Waves.FirstDeathTime = time;
		// 	// 计时重置波次
		// 	if (Waves.SpawnTime > 0)
		// 	{
		// 		// EntFire("worldspawn", "CallScriptFunction", "ResetWave", Waves.SpawnTime);
		// 		// 到复活时间时，先检查有无奖励时间
		// 		EntFire("worldspawn", "CallScriptFunction", "CheckBonusTime", Waves.SpawnTime);
		// 	} else
		// 	{
		// 		// 特感速递直接复活，无奖励时间
		// 		ResetWave();
		// 	}
		// }
		// else // 后面死的
		// {
		// 	// 减去第一只死的时间，计算还有多久下一波
		// 	local interval = time - Waves.FirstDeathTime;
		// 	// 剩余复活时间 = 设定复活时间 - 当前时间 + 奖励时间
		// 	local remainTime = Waves.SpawnTime - interval + Waves.BonusSpawnTime;
		// 	local timeDiv = remainTime / Waves.SpawnTime;
		// 	// Say(victimEnt, format("time: %.2f, last: %.2f, remainTime: %.2f, timeDiv: %.3f", time, Waves.FirstDeathTime, remainTime, timeDiv), false);

		// 	// 分段发放奖励时间，特感越多，理论上奖励时间就越长
		// 	if (timeDiv <= 0.25) {
		// 		Waves.BonusSpawnTime += 5.0;
		// 	} else if (timeDiv <= 0.5) {
		// 		Waves.BonusSpawnTime += 3.0;
		// 	} else if (timeDiv <= 0.8) {
		// 		Waves.BonusSpawnTime += 2.0;
		// 	}
		// }
	}

	// if (victimTeam == 3 && zombieType == ZOMBIE_TANK)
	// {
	// 	Waves.MaxSILimit++;
	// }
}

function OnGameEvent_round_start( params )
{
	if (!Waves.Enabled) return;

	// local timer_new = Convars.GetStr("ast_sitimer_new").tofloat();
	// local limit_new = Convars.GetStr("ast_silimit_new").tointeger();

	// Waves.AliveSICount = 0;
	// Waves.SpawnTime = timer_new;
	// Waves.MaxSILimit = limit_new;

	// EntFire("worldspawn", "KillScriptFunction", "ResetWave");
	// EntFire("worldspawn", "KillScriptFunction", "CheckBonusTime");

	// ResetWave();
	UpdateHUDWave();
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
Msg("======== astredux.nut: Reload Complete. ========\n");
