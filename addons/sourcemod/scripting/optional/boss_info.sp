#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <colors>
#include <builtinvotes>
#include <vote_policy>
#define L4D2UTIL_STOCKS_ONLY
#include <l4d2util_rounds>
#include <boss_spawn_rules>
#undef REQUIRE_PLUGIN
#include <confogl>
#include <readyup>
#include <l4d_tank_control_eq>

#define TEAM_SURVIVORS 2

public Plugin myinfo =
{
	name = "[L4D2] Boss Info",
	author = "CanadaRox, Visor, Spoon, Forgetest",
	description = "Boss percentages, survivor progress and boss voting",
	version = "1.0.0",
	url = "https://github.com/SirPlease/L4D2-Competitive-Rework"
};

#include "boss_info/current.sp"
#include "boss_info/percents.sp"
#include "boss_info/vote.sp"

public void OnPluginStart()
{
	LoadTranslation("boss_info.phrases");
	Cur_OnPluginStart();
	BP_OnPluginStart();
	BV_OnPluginStart();
}
