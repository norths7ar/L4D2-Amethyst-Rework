#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#define DEBUG 0

enum WeaponID
{
	ID_NONE,
	ID_PISTOL,
	ID_DUAL_PISTOL,
	ID_SMG,
	ID_PUMPSHOTGUN,
	ID_RIFLE,
	ID_AUTOSHOTGUN,
	ID_HUNTING_RIFLE,
	ID_SMG_SILENCED,
	ID_SMG_MP5,
	ID_CHROMESHOTGUN,
	ID_MAGNUM,
	ID_AK47,
	ID_RIFLE_DESERT,
	ID_SNIPER_MILITARY,
	ID_GRENADE,
	ID_SG552,
	ID_M60,
	ID_AWP,
	ID_SCOUT,
	ID_SPASSHOTGUN
}
char Weapon_Name[WeaponID][32];
int WeaponAmmoOffest[WeaponID];
int WeaponMaxClip[WeaponID];

//cvars
Handle hEnableReloadClipCvar;
Handle hEnableClipRecoverCvar;
Handle hSmgTimeCvar;
Handle hRifleTimeCvar;
Handle hHuntingRifleTimeCvar;
Handle hPistolTimeCvar;
Handle hDualPistolTimeCvar;
Handle hSmgSilencedTimeCvar;
Handle hSmgMP5TimeCvar;
Handle hAK47TimeCvar;
Handle hRifleDesertTimeCvar;
Handle hSniperMilitaryTimeCvar;
Handle hGrenadeTimeCvar;
Handle hSG552TimeCvar;
Handle hAWPTimeCvar;
Handle hScoutTimeCvar;
Handle hMangumTimeCvar;

float g_EnableReloadClipCvar;
float g_EnableClipRecoverCvar;
float g_SmgTimeCvar;
float g_RifleTimeCvar;
float g_HuntingRifleTimeCvar;
float g_PistolTimeCvar;
float g_DualPistolTimeCvar;
float g_SmgSilencedTimeCvar;
float g_SmgMP5TimeCvar;
float g_AK47TimeCvar;
float g_RifleDesertTimeCvar;
float g_SniperMilitaryTimeCvar;
float g_GrenadeTimeCvar;
float g_SG552TimeCvar;
float g_AWPTimeCvar;
float g_ScoutTimeCvar;
float g_MangumTimeCvar;

//value
static	Handle g_hClientReload_Timer[MAXPLAYERS+1]	= {INVALID_HANDLE};	

//offest
int ammoOffset;	
											
public Plugin:myinfo = 
{
	name = "L4D2 weapon csgo reload",
	author = "Harry Potter",
	description = "reload like csgo weapon",
	version = "1.0",
	url = "Harry Potter myself,you bitch shit"
};

public void OnPluginStart()
{
	hEnableReloadClipCvar	= CreateConVar("l4d2_enable_reload_clip", 				"1", 	"enable this plugin?[1-Enable,0-Disable]" , FCVAR_NOTIFY, true, 0.0, true, 1.0);
	hEnableClipRecoverCvar	= CreateConVar("l4d2_enable_clip_recover", 				"1", 	"enable previous clip recover?"			  , FCVAR_NOTIFY, true, 0.0, true, 1.0);
	hSmgTimeCvar			= CreateConVar("l4d2_smg_reload_clip_time", 			"1.2", "reload time for smg clip"				  , FCVAR_NOTIFY);
	hRifleTimeCvar			= CreateConVar("l4d2_rifle_reload_clip_time", 			"1.2",  "reload time for rifle clip"			  , FCVAR_NOTIFY);
	hHuntingRifleTimeCvar   = CreateConVar("l4d2_huntingrifle_reload_clip_time", 	"2.6", "reload time for hunting rifle clip"		  , FCVAR_NOTIFY);
	hPistolTimeCvar 		= CreateConVar("l4d2_pistol_reload_clip_time", 			"1.2",  "reload time for pistol clip"		      , FCVAR_NOTIFY);
	hDualPistolTimeCvar 	= CreateConVar("l4d2_dualpistol_reload_clip_time", 		"1.75", "reload time for dual pistol clip"        , FCVAR_NOTIFY);
	hSmgSilencedTimeCvar	= CreateConVar("l4d2_smgsilenced_reload_clip_time", 	"1.1",  "reload time for smg silenced clip"       , FCVAR_NOTIFY);
	hSmgMP5TimeCvar			= CreateConVar("l4d2_smgmp5_reload_clip_time", 			"1.7",  "reload time for smg mp5 clip"      	  , FCVAR_NOTIFY);
	hAK47TimeCvar			= CreateConVar("l4d2_ak47_reload_clip_time", 			"1.2",  "reload time for ak47 clip"      		  , FCVAR_NOTIFY);
	hRifleDesertTimeCvar	= CreateConVar("l4d2_rifledesert_reload_clip_time", 	"1.8",  "reload time for rifledesert clip"        , FCVAR_NOTIFY);
	hSniperMilitaryTimeCvar	= CreateConVar("l4d2_snipermilitary_reload_clip_time", 	"1.8",  "reload time for sniper military clip"    , FCVAR_NOTIFY);
	hGrenadeTimeCvar		= CreateConVar("l4d2_grenade_reload_clip_time", 		"2.5",  "reload time for grenade clip"  		  , FCVAR_NOTIFY);
	hSG552TimeCvar			= CreateConVar("l4d2_sg552_reload_clip_time", 			"1.3",  "reload time for sg552 clip" 			  , FCVAR_NOTIFY);
	hAWPTimeCvar			= CreateConVar("l4d2_awp_reload_clip_time", 			"2.0",  "reload time for awp clip" 				  , FCVAR_NOTIFY);
	hScoutTimeCvar			= CreateConVar("l4d2_scout_reload_clip_time", 			"1.45", "reload time for scout clip"  			  , FCVAR_NOTIFY);
	hMangumTimeCvar			= CreateConVar("l4d2_mangum_reload_clip_time", 			"1.18", "reload time for mangum clip"  			  , FCVAR_NOTIFY);
	
	g_EnableReloadClipCvar  = GetConVarFloat(hEnableReloadClipCvar);
	g_EnableClipRecoverCvar = GetConVarFloat(hEnableClipRecoverCvar);
	g_SmgTimeCvar 			= GetConVarFloat(hSmgTimeCvar);
	g_RifleTimeCvar 		= GetConVarFloat(hRifleTimeCvar);
	g_HuntingRifleTimeCvar	= GetConVarFloat(hHuntingRifleTimeCvar);
	g_PistolTimeCvar 		= GetConVarFloat(hPistolTimeCvar);
	g_DualPistolTimeCvar 	= GetConVarFloat(hDualPistolTimeCvar);
	g_SmgSilencedTimeCvar	= GetConVarFloat(hSmgSilencedTimeCvar);
	g_SmgMP5TimeCvar		= GetConVarFloat(hSmgMP5TimeCvar);
	g_AK47TimeCvar			= GetConVarFloat(hAK47TimeCvar);
	g_RifleDesertTimeCvar	= GetConVarFloat(hRifleDesertTimeCvar);
	g_SniperMilitaryTimeCvar= GetConVarFloat(hSniperMilitaryTimeCvar);
	g_GrenadeTimeCvar		= GetConVarFloat(hGrenadeTimeCvar);
	g_SG552TimeCvar			= GetConVarFloat(hSG552TimeCvar);
	g_AWPTimeCvar			= GetConVarFloat(hAWPTimeCvar);
	g_ScoutTimeCvar			= GetConVarFloat(hScoutTimeCvar);
	g_MangumTimeCvar		= GetConVarFloat(hMangumTimeCvar);
	
	HookConVarChange(hEnableReloadClipCvar, ConVarChange_hEnableReloadClipCvar);
	HookConVarChange(hEnableClipRecoverCvar, ConVarChange_hEnableClipRecoverCvar);
	HookConVarChange(hSmgTimeCvar, ConVarChange_hSmgTimeCvar);
	HookConVarChange(hRifleTimeCvar, ConVarChange_hRifleTimeCvar);
	HookConVarChange(hHuntingRifleTimeCvar, ConVarChange_hHuntingRifleTimeCvar);
	HookConVarChange(hPistolTimeCvar, ConVarChange_hPistolTimeCvar);
	HookConVarChange(hDualPistolTimeCvar, ConVarChange_hDualPistolTimeCvar);
	HookConVarChange(hSmgSilencedTimeCvar, ConVarChange_hSmgSilencedTimeCvar);
	HookConVarChange(hSmgMP5TimeCvar, ConVarChange_hSmgMP5TimeCvar);
	HookConVarChange(hAK47TimeCvar, ConVarChange_hAK47TimeCvar);
	HookConVarChange(hRifleDesertTimeCvar, ConVarChange_hRifleDesertTimeCvar);
	HookConVarChange(hSniperMilitaryTimeCvar, ConVarChange_hSniperMilitaryTimeCvar);
	HookConVarChange(hGrenadeTimeCvar, ConVarChange_hGrenadeTimeCvar);
	HookConVarChange(hSG552TimeCvar, ConVarChange_hSG552TimeCvar);
	HookConVarChange(hAWPTimeCvar, ConVarChange_hAWPTimeCvar);
	HookConVarChange(hScoutTimeCvar, ConVarChange_hScoutTimeCvar);
	HookConVarChange(hMangumTimeCvar, ConVarChange_hMangumTimeCvar);
	
	HookEvent("weapon_reload", OnWeaponReload_Event, EventHookMode_Post);
	HookEvent("round_start", RoundStart_Event);
	
	ammoOffset = FindSendPropInfo("CCSPlayer", "m_iAmmo");
	
	SetWeapon();
	
	AutoExecConfig(true, "l4d2_weapon_csgo_reload");
}

public Action:RoundStart_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	for(new i = 1; i <= MaxClients; i++)
	{
		g_hClientReload_Timer[i] = INVALID_HANDLE;
	}
}

public void SetWeapon()
{
	Weapon_Name[ID_NONE] = "";
	Weapon_Name[ID_PISTOL] = "weapon_pistol";
	Weapon_Name[ID_DUAL_PISTOL] = "weapon_pistol";
	Weapon_Name[ID_SMG] = "weapon_smg";
	Weapon_Name[ID_PUMPSHOTGUN] = "weapon_pumpshotgun";
	Weapon_Name[ID_RIFLE] = "weapon_rifle";
	Weapon_Name[ID_AUTOSHOTGUN] = "weapon_autoshotgun";
	Weapon_Name[ID_HUNTING_RIFLE] = "weapon_hunting_rifle";
	Weapon_Name[ID_SMG_SILENCED] = "weapon_smg_silenced";
	Weapon_Name[ID_SMG_MP5] = "weapon_smg_mp5";
	Weapon_Name[ID_CHROMESHOTGUN] = "weapon_shotgun_chrome";
	Weapon_Name[ID_MAGNUM] = "weapon_pistol_magnum";
	Weapon_Name[ID_AK47] = "weapon_rifle_ak47";
	Weapon_Name[ID_RIFLE_DESERT] = "weapon_rifle_desert";
	Weapon_Name[ID_SNIPER_MILITARY] = "weapon_sniper_military";
	Weapon_Name[ID_GRENADE] = "weapon_grenade_launcher";
	Weapon_Name[ID_SG552] = "weapon_rifle_sg552";
	Weapon_Name[ID_M60] = "weapon_rifle_m60";
	Weapon_Name[ID_AWP] = "weapon_sniper_awp";
	Weapon_Name[ID_SCOUT] = "weapon_sniper_scout";
	Weapon_Name[ID_SPASSHOTGUN] = "weapon_shotgun_spas";
	
	WeaponAmmoOffest[ID_NONE] = 0;
	WeaponAmmoOffest[ID_PISTOL] = 0;
	WeaponAmmoOffest[ID_DUAL_PISTOL] = 0;
	WeaponAmmoOffest[ID_SMG] = 5;
	WeaponAmmoOffest[ID_PUMPSHOTGUN] = 7;
	WeaponAmmoOffest[ID_RIFLE] = 3;
	WeaponAmmoOffest[ID_AUTOSHOTGUN] = 8;
	WeaponAmmoOffest[ID_HUNTING_RIFLE] = 9;
	WeaponAmmoOffest[ID_SMG_SILENCED] = 5;
	WeaponAmmoOffest[ID_SMG_MP5] = 5;
	WeaponAmmoOffest[ID_CHROMESHOTGUN] = 7;
	WeaponAmmoOffest[ID_MAGNUM] = 0;
	WeaponAmmoOffest[ID_AK47] = 3;
	WeaponAmmoOffest[ID_RIFLE_DESERT] = 3;
	WeaponAmmoOffest[ID_SNIPER_MILITARY] = 10;
	WeaponAmmoOffest[ID_GRENADE] = 17;
	WeaponAmmoOffest[ID_SG552] = 3;
	WeaponAmmoOffest[ID_M60] = 0;
	WeaponAmmoOffest[ID_AWP] = 10;
	WeaponAmmoOffest[ID_SCOUT] = 10;
	WeaponAmmoOffest[ID_SPASSHOTGUN] = 8;
	
	WeaponMaxClip[ID_NONE] = 0;
	WeaponMaxClip[ID_PISTOL] = 15;
	WeaponMaxClip[ID_DUAL_PISTOL] = 30;
	WeaponMaxClip[ID_SMG] = 50;
	WeaponMaxClip[ID_PUMPSHOTGUN] = 8;
	WeaponMaxClip[ID_RIFLE] = 50;
	WeaponMaxClip[ID_AUTOSHOTGUN] = 10;
	WeaponMaxClip[ID_HUNTING_RIFLE] = 15;
	WeaponMaxClip[ID_SMG_SILENCED] = 50;
	WeaponMaxClip[ID_SMG_MP5] = 50;
	WeaponMaxClip[ID_CHROMESHOTGUN] = 8;
	WeaponMaxClip[ID_MAGNUM] = 8;
	WeaponMaxClip[ID_AK47] = 40;
	WeaponMaxClip[ID_RIFLE_DESERT] = 60;
	WeaponMaxClip[ID_SNIPER_MILITARY] = 30;
	WeaponMaxClip[ID_GRENADE] = 1;
	WeaponMaxClip[ID_SG552] = 50;
	WeaponMaxClip[ID_M60] = 150;
	WeaponMaxClip[ID_AWP] = 20;
	WeaponMaxClip[ID_SCOUT] = 15;
	WeaponMaxClip[ID_SPASSHOTGUN] = 10;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if(g_EnableReloadClipCvar == 0 || g_EnableClipRecoverCvar == 0)	return Plugin_Continue;
	
	if (IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client) && buttons & IN_RELOAD) //If survivor alive player is holding weapon and wants to reload
	{
		int iCurrentWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"); //抓人類目前裝彈的武器
		if (iCurrentWeapon == -1 || !IsValidEntity(iCurrentWeapon))
		{
			return Plugin_Continue;
		}
		int previousclip = GetWeaponClip(iCurrentWeapon);
		if(GetEntProp(iCurrentWeapon, Prop_Send, "m_bInReload") == 0)
		{
			char sWeaponName[32];
			GetClientWeapon(client, sWeaponName, sizeof(sWeaponName));
			#if DEBUG
				PrintToChatAll("%N - %s clip:%d",client,sWeaponName,previousclip);
			#endif
			WeaponID weaponid = GetWeaponID(iCurrentWeapon,sWeaponName);
			int MaxClip = WeaponMaxClip[weaponid];
			
			switch(weaponid)
			{
				case (WeaponID:ID_SMG),(WeaponID:ID_RIFLE),(WeaponID:ID_HUNTING_RIFLE),(WeaponID:ID_SMG_SILENCED),(WeaponID:ID_SMG_MP5),
				(WeaponID:ID_AK47),(WeaponID:ID_RIFLE_DESERT),(WeaponID:ID_AWP),(WeaponID:ID_GRENADE),(WeaponID:ID_SCOUT),(WeaponID:ID_SG552),
				(WeaponID:ID_SNIPER_MILITARY):
				{
					if (0 < previousclip && previousclip < MaxClip)	//If the his current mag equals the maximum allowed, remove reload from buttons
					{
						Handle pack;
						CreateDataTimer(0.1, RecoverWeaponClip, pack, TIMER_FLAG_NO_MAPCHANGE);
						WritePackCell(pack, client);
						WritePackCell(pack, iCurrentWeapon);
						WritePackCell(pack, previousclip);
						WritePackCell(pack, weaponid);
					}
				}
				default:
					return Plugin_Continue;
			}
		}
	}
	return Plugin_Continue;
}

public Action RecoverWeaponClip(Handle timer, Handle pack)
{
	ResetPack(pack);
	int client = ReadPackCell(pack);
	int CurrentWeapon = ReadPackCell(pack);
	int previousclip = ReadPackCell(pack);
	WeaponID weaponid = ReadPackCell(pack);
	int nowweaponclip;
	
	if (CurrentWeapon == -1 || //CurrentWeapon drop
	!IsValidEntity(CurrentWeapon) ||
	client == 0 || //client disconnected
	!IsClientInGame(client) || 
	!IsPlayerAlive(client) ||
	GetClientTeam(client)!=2 ||
	GetEntProp(CurrentWeapon, Prop_Send, "m_bInReload") == 0 || //reload interrupted
	(nowweaponclip = GetWeaponClip(CurrentWeapon)) == WeaponMaxClip[weaponid] || //CurrentWeapon complete reload finished
	nowweaponclip == previousclip //CurrentWeapon clip has been recovered
	)
	{
		return Plugin_Handled;
	}
	
	if (nowweaponclip < WeaponMaxClip[weaponid] && nowweaponclip == 0)
	{
		int ammo = GetWeaponAmmo(client, WeaponAmmoOffest[weaponid]);
		ammo -= previousclip;
		#if DEBUG
			PrintToChatAll("CurrentWeapon clip recovered");
		#endif
		SetWeaponAmmo(client,WeaponAmmoOffest[weaponid],ammo);
		SetWeaponClip(CurrentWeapon,previousclip);
	}
	return Plugin_Handled;
}

public Action OnWeaponReload_Event(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
		
	if (client < 1 || 
		client > MaxClients ||
		!IsClientInGame(client) ||
		IsFakeClient(client) ||
		GetClientTeam(client) != 2||
		g_EnableReloadClipCvar == 0) //disable this plugin
		return Plugin_Continue;
	

	int iCurrentWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"); //抓人類目前裝彈的武器
	if (iCurrentWeapon == -1 || !IsValidEntity(iCurrentWeapon))
	{
		return Plugin_Continue;
	}
	char sWeaponName[32];
	GetClientWeapon(client, sWeaponName, sizeof(sWeaponName));
	WeaponID weaponid = GetWeaponID(iCurrentWeapon,sWeaponName);
	int ammo = GetWeaponAmmo(client, WeaponAmmoOffest[weaponid]);
	#if DEBUG
		PrintToChatAll("%N - %s ammo:%d - weaponid: %d",client,sWeaponName,ammo,weaponid);
		for (int i = 0; i < 32; i++)
		{
			PrintToConsole(client, "Offset: %i - Count: %i", i, GetEntData(client, ammoOffset+(i*4)));
		} 
	#endif
	
	
	if (g_hClientReload_Timer[client] != INVALID_HANDLE)
	{
		KillTimer(g_hClientReload_Timer[client]);
	}
	
	Handle pack;
	switch(weaponid)
	{
		case (WeaponID:ID_SMG): g_hClientReload_Timer[client] = CreateDataTimer(g_SmgTimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_RIFLE): g_hClientReload_Timer[client] = CreateDataTimer(g_RifleTimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_HUNTING_RIFLE): g_hClientReload_Timer[client] = CreateDataTimer(g_HuntingRifleTimeCvar, WeaponReloadClip, pack,TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_PISTOL): g_hClientReload_Timer[client] = CreateDataTimer(g_PistolTimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_DUAL_PISTOL): g_hClientReload_Timer[client] = CreateDataTimer(g_DualPistolTimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_SMG_SILENCED): g_hClientReload_Timer[client] = CreateDataTimer(g_SmgSilencedTimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_SMG_MP5): g_hClientReload_Timer[client] = CreateDataTimer(g_SmgMP5TimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_AK47): g_hClientReload_Timer[client] = CreateDataTimer(g_AK47TimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_RIFLE_DESERT): g_hClientReload_Timer[client] = CreateDataTimer(g_RifleDesertTimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_AWP): g_hClientReload_Timer[client] = CreateDataTimer(g_AWPTimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_SCOUT): g_hClientReload_Timer[client] = CreateDataTimer(g_ScoutTimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_GRENADE): g_hClientReload_Timer[client] = CreateDataTimer(g_GrenadeTimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_SG552): g_hClientReload_Timer[client] = CreateDataTimer(g_SG552TimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_SNIPER_MILITARY): g_hClientReload_Timer[client] = CreateDataTimer(g_SniperMilitaryTimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		case (WeaponID:ID_MAGNUM): g_hClientReload_Timer[client] = CreateDataTimer(g_MangumTimeCvar, WeaponReloadClip, pack, TIMER_FLAG_NO_MAPCHANGE);
		default: return Plugin_Continue;
	}
	WritePackCell(pack, client);
	WritePackCell(pack, iCurrentWeapon);
	WritePackCell(pack, ammo);
	WritePackCell(pack, weaponid);
	
	
	return Plugin_Continue;
}

public Action WeaponReloadClip(Handle timer, Handle pack)
{
	ResetPack(pack);
	int client = ReadPackCell(pack);
	int CurrentWeapon = ReadPackCell(pack);
	int ammo = ReadPackCell(pack);
	WeaponID weaponid = ReadPackCell(pack);
	int nowsmgclip;
	
	if (CurrentWeapon == -1 || //CurrentWeapon drop
	!IsValidEntity(CurrentWeapon) || 
	client == 0 || //client disconnected
	!IsClientInGame(client) ||
	!IsPlayerAlive(client) ||
	GetClientTeam(client)!=2 ||
	GetEntProp(CurrentWeapon, Prop_Send, "m_bInReload") == 0 || //reload interrupted
	(nowsmgclip = GetWeaponClip(CurrentWeapon)) == WeaponMaxClip[weaponid] //CurrentWeapon complete reload finished
	)
	{
		g_hClientReload_Timer[client] = INVALID_HANDLE;
		return Plugin_Handled;
	}
	
	if (nowsmgclip < WeaponMaxClip[weaponid])
	{
		switch(weaponid)
		{
			case (WeaponID:ID_SMG),(WeaponID:ID_RIFLE),(WeaponID:ID_HUNTING_RIFLE),(WeaponID:ID_SMG_SILENCED),(WeaponID:ID_SMG_MP5),
			(WeaponID:ID_AK47),(WeaponID:ID_RIFLE_DESERT),(WeaponID:ID_AWP),(WeaponID:ID_GRENADE),(WeaponID:ID_SCOUT),(WeaponID:ID_SG552),
			(WeaponID:ID_SNIPER_MILITARY):
			{
				ammo -= WeaponMaxClip[weaponid];
				#if DEBUG
					PrintToChatAll("CurrentWeapon reload clip completed");
				#endif
				SetWeaponAmmo(client,WeaponAmmoOffest[weaponid],ammo);
				SetWeaponClip(CurrentWeapon,WeaponMaxClip[weaponid]);
			}
			case (WeaponID:ID_PISTOL),(WeaponID:ID_DUAL_PISTOL),(WeaponID:ID_MAGNUM),(WeaponID:ID_M60):
			{
				#if DEBUG
					PrintToChatAll("Pistol reload clip completed");
				#endif
				SetWeaponClip(CurrentWeapon,WeaponMaxClip[weaponid]);
			}
			default:
			{
				g_hClientReload_Timer[client] = INVALID_HANDLE;
				return Plugin_Handled;
			}
		}
	}
	g_hClientReload_Timer[client] = INVALID_HANDLE;
	return Plugin_Handled;
}
stock GetWeaponAmmo(int client, int offest)
{
    return GetEntData(client, ammoOffset+(offest*4));
} 

stock GetWeaponClip(int weapon)
{
    return GetEntProp(weapon, Prop_Send, "m_iClip1");
} 

stock void SetWeaponAmmo(int client, int offest, int ammo)
{
    SetEntData(client, ammoOffset+(offest*4), ammo);
} 
stock void SetWeaponClip(int weapon, int clip)
{
	SetEntProp(weapon, Prop_Send, "m_iClip1", clip);
} 
stock WeaponID GetWeaponID(int weapon,const char[] weapon_name)
{
	if(StrEqual(weapon_name,Weapon_Name[ID_DUAL_PISTOL],false) && GetEntProp(weapon, Prop_Send, "m_hasDualWeapons"))
	{
		return WeaponID:ID_DUAL_PISTOL;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_PISTOL],false))
	{
		return WeaponID:ID_PISTOL;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_SMG],false))
	{
		return WeaponID:ID_SMG;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_PUMPSHOTGUN],false))
	{
		return WeaponID:ID_PUMPSHOTGUN;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_RIFLE],false))
	{
		return WeaponID:ID_RIFLE;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_AUTOSHOTGUN],false))
	{
		return WeaponID:ID_AUTOSHOTGUN;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_HUNTING_RIFLE],false))
	{
		return WeaponID:ID_HUNTING_RIFLE;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_AK47],false))
	{
		return WeaponID:ID_AK47;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_AWP],false))
	{
		return WeaponID:ID_AWP;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_GRENADE],false))
	{
		return WeaponID:ID_GRENADE;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_CHROMESHOTGUN],false))
	{
		return WeaponID:ID_CHROMESHOTGUN;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_M60],false))
	{
		return WeaponID:ID_M60;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_MAGNUM],false))
	{
		return WeaponID:ID_MAGNUM;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_RIFLE_DESERT],false))
	{
		return WeaponID:ID_RIFLE_DESERT;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_SCOUT],false))
	{
		return WeaponID:ID_SCOUT;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_SG552],false))
	{
		return WeaponID:ID_SG552;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_SMG_MP5],false))
	{
		return WeaponID:ID_SMG_MP5;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_SMG_SILENCED],false))
	{
		return WeaponID:ID_SMG_SILENCED;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_SNIPER_MILITARY],false))
	{
		return WeaponID:ID_SNIPER_MILITARY;
	}
	else if(StrEqual(weapon_name,Weapon_Name[ID_SPASSHOTGUN],false))
	{
		return WeaponID:ID_SPASSHOTGUN;
	}
	return WeaponID:ID_NONE;
}
public void ConVarChange_hEnableReloadClipCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_EnableReloadClipCvar  = GetConVarFloat(hEnableReloadClipCvar);
}
public void ConVarChange_hEnableClipRecoverCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_EnableClipRecoverCvar = GetConVarFloat(hEnableClipRecoverCvar);
}
public void ConVarChange_hSmgTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_SmgTimeCvar = GetConVarFloat(hSmgTimeCvar);
}
public void ConVarChange_hRifleTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_RifleTimeCvar = GetConVarFloat(hRifleTimeCvar);
}
public void ConVarChange_hHuntingRifleTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_HuntingRifleTimeCvar = GetConVarFloat(hHuntingRifleTimeCvar);
}
public void ConVarChange_hPistolTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_PistolTimeCvar = GetConVarFloat(hPistolTimeCvar);
}
public void ConVarChange_hDualPistolTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_DualPistolTimeCvar = GetConVarFloat(hDualPistolTimeCvar);
}
public void ConVarChange_hSmgSilencedTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_SmgSilencedTimeCvar = GetConVarFloat(hSmgSilencedTimeCvar);
}
public void ConVarChange_hSmgMP5TimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_SmgMP5TimeCvar = GetConVarFloat(hSmgMP5TimeCvar);
}
public void ConVarChange_hAK47TimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_AK47TimeCvar = GetConVarFloat(hAK47TimeCvar);
}
public void ConVarChange_hRifleDesertTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_RifleDesertTimeCvar = GetConVarFloat(hRifleDesertTimeCvar);
}
public void ConVarChange_hSniperMilitaryTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_SniperMilitaryTimeCvar = GetConVarFloat(hSniperMilitaryTimeCvar);
}
public void ConVarChange_hGrenadeTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_GrenadeTimeCvar = GetConVarFloat(hGrenadeTimeCvar);
}
public void ConVarChange_hSG552TimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_SG552TimeCvar = GetConVarFloat(hSG552TimeCvar);
}
public void ConVarChange_hAWPTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_AWPTimeCvar = GetConVarFloat(hAWPTimeCvar);
}
public void ConVarChange_hScoutTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_ScoutTimeCvar = GetConVarFloat(hScoutTimeCvar);
}
public void ConVarChange_hMangumTimeCvar(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_MangumTimeCvar = GetConVarFloat(hMangumTimeCvar);
}