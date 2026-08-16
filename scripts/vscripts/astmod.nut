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
}

HUDInfo <- {
    si_count = { normal=0, smoker=0, boomer=0, hunter=0, spitter=0, jockey=0, charger=0 }
    si_names = [ "normal", "smoker", "boomer", "hunter", "spitter", "jockey", "charger"]
	wave_countdown = 0
	text = ""
}

function update_diff()
{
	Waves.Enabled = Convars.GetStr("ast_wave_spawn").tointeger();

	Waves.Enabled ? update_diff_new() : update_diff_old();
}

//-----------------------------------------------------------------------------------------------------------------------------
// Function
//-----------------------------------------------------------------------------------------------------------------------------

::ResetWave <- function() {
	// 记录存活的特感数量
	Waves.SpawnedSICount = Waves.AliveSICount;
	Waves.HasFirstDeath = false;
	// 强制刷新
	Director.ResetSpecialTimers();
	// SendToServerConsole("say Time to GO!!! remains: " + Waves.SpawnedSICount);
};

function update_diff_new()
{
	local difficulty = Convars.GetStr("das_fakedifficulty");
	local timer_new = Convars.GetStr("ast_sitimer_new").tofloat();
	local limit_new = Convars.GetStr("ast_silimit_new").tointeger();

	switch (difficulty) {
		case "1":
			DirectorOptions.HunterLimit = 1
			DirectorOptions.SmokerLimit = 1
			DirectorOptions.BoomerLimit = 0
			DirectorOptions.SpitterLimit = 0
			DirectorOptions.JockeyLimit = 1
			DirectorOptions.ChargerLimit = 1
			DirectorOptions.PreferredSpecialDirection = 4
			break;
		case "2":
			DirectorOptions.HunterLimit = 2
			DirectorOptions.SmokerLimit = 0
			DirectorOptions.BoomerLimit = 1
			DirectorOptions.SpitterLimit = 0
			DirectorOptions.JockeyLimit = 1
			DirectorOptions.ChargerLimit = 1
			DirectorOptions.PreferredSpecialDirection = 4
			break;
		case "3":
			DirectorOptions.HunterLimit = 3
			DirectorOptions.SmokerLimit = 1
			DirectorOptions.BoomerLimit = 1
			DirectorOptions.SpitterLimit = 1
			DirectorOptions.JockeyLimit = 2
			DirectorOptions.ChargerLimit = 2
			DirectorOptions.PreferredSpecialDirection = 1
			break;
		case "4":
			DirectorOptions.HunterLimit = 4
			DirectorOptions.SpitterLimit = 1
			DirectorOptions.SmokerLimit = 1
			DirectorOptions.BoomerLimit = 1
			DirectorOptions.JockeyLimit = 2
			DirectorOptions.ChargerLimit = 2
			DirectorOptions.PreferredSpecialDirection = 1
			break;
		default:
			break;
	}

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
			DirectorOptions.JockeyLimit = 2 
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
			DirectorOptions.JockeyLimit = 2
			DirectorOptions.ChargerLimit = 2
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
				special = HUD_SPECIAL_TIMER0,
				flags = HUD_FLAG_NOBG,
				dataval = HUDInfo.text,
				name = "siInfo"
			}
		}
	}

	// load the ModeHUD table
	HUDSetLayout(ModeHUD);
}

function UpdateHUD()
{
    // 显示特感
	HUDInfo.text = "";
    foreach (name in HUDInfo.si_names)
    {
        local count = HUDInfo.si_count[name];
		if (count == 0) continue;

    	// 名称首字母大写
    	local displayName = name.slice(0, 1).toupper() + name.slice(1);

		if (count == 1) {
			HUDInfo.text += format("%s  ", displayName);
		} else {
			HUDInfo.text += format("%s * %d  ", displayName, count);
		}
    }

	InitHUD();
}

//-----------------------------------------------------------------------------------------------------------------------------
// Hook Game Events
//-----------------------------------------------------------------------------------------------------------------------------

function OnGameplayStart()
{
}

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
		if ( Waves.SpawnedSICount >= Waves.MaxSILimit ) { // 超过一波数量
			// 直接 Kill 掉会导致原地留下烟雾口水之类的特效，可能需要提早，不过影响不大
			clientEnt.Kill();
			// Say(clientEnt, "Blocked from spawning.", false);
			return;
		}
		Waves.SpawnedSICount++;
		Waves.AliveSICount++;
		// Say(clientEnt, "SpawnedSICount: " + Waves.SpawnedSICount, false);

		// HUD
		local name = HUDInfo.si_names[zombieType];
		HUDInfo.si_count[name]++;
		UpdateHUD();
	}
	if (team == 3 && zombieType == ZOMBIE_TANK) // 克局特感 -1
	{
		if (Waves.MaxSILimit > 0)
			Waves.MaxSILimit--;
	}
}

function OnGameEvent_player_death( params )
{
	if (!Waves.Enabled) return;

	local attacker = GetParamsItem(params, "attacker");
	local victimname = GetParamsItem(params, "victimname");
	if (victimname == "Infected") return; // 普通感染者

	local victim = GetParamsItem(params, "userid");
	local victimEnt = GetPlayerFromUserID(victim);
	local victimTeam = GetClientTeam(victimEnt);
	local zombieType = victimEnt.GetZombieType();

	if ( victimTeam == 3 && zombieType < ZOMBIE_WITCH )
	{
		Waves.AliveSICount--;
		// HUD
		local name = HUDInfo.si_names[zombieType];
		HUDInfo.si_count[name]--;
		UpdateHUD();

		if (Waves.HasFirstDeath) return;
		Waves.HasFirstDeath = true;
		// 计时重置波次
		if (Waves.SpawnTime > 0)
		{
			EntFire("worldspawn", "CallScriptFunction", "ResetWave", Waves.SpawnTime);
		} else
		{
			ResetWave();
		}
	}

	if (victimTeam == 3 && zombieType == ZOMBIE_TANK)
	{
		Waves.MaxSILimit++;
	}
}

function OnGameEvent_round_start( params )
{
	if (!Waves.Enabled) return;

	local timer_new = Convars.GetStr("ast_sitimer_new").tofloat();
	local limit_new = Convars.GetStr("ast_silimit_new").tointeger();

	Waves.AliveSICount = 0;
	Waves.SpawnTime = timer_new;
	Waves.MaxSILimit = limit_new;
	ResetWave();
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
