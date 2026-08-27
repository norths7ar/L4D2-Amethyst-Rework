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
	Enabled				= true		// 新版波次由 astredux/wave_spawner.smx 执行
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

function update_diff_new()
{
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
		// HUD
		local name = HUDInfo.si_names[zombieType];
		HUDInfo.si_count[name]++;
		UpdateHUD();
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
	if (victimEnt == null) return;
	local victimTeam = GetClientTeam(victimEnt);
	local zombieType = victimEnt.GetZombieType();

	if ( victimTeam == 3 && zombieType < ZOMBIE_WITCH )
	{
		// HUD
		local name = HUDInfo.si_names[zombieType];
		HUDInfo.si_count[name]--;
		UpdateHUD();
	}
}

function OnGameEvent_round_start( params )
{
	if (!Waves.Enabled) return;

	foreach (name in HUDInfo.si_names)
	{
		HUDInfo.si_count[name] = 0;
	}
	UpdateHUD();
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
