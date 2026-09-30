#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>
#include <left4dhooks>
#define L4D2UTIL_STOCKS_ONLY
#include <l4d2util>

// Presentation from Visor/Forgetest/xoxo's spawn announcer, Griffin and
// Blade/Sir's damage announcer, and Forgetest's facts announcer.
// Replacement lifecycle follows MoYu's multi-Tank damage announcer: explicit
// user-ID relationships, never a scan that adopts an unrelated live Tank.
// Damage source history: 0.6.6 added the dying Tank's name and improved output;
// Sir's 0.6.6b prevented printing the previous map's surviving Tank twice;
// Sir's 0.6.7 added campaign difficulty support. Entity health now supplies the
// difficulty/mode-adjusted denominator, including custom spawn-controller HP.
public Plugin myinfo =
{
	name = "Tank Announcer",
	author = "Visor, Forgetest, xoxo, Griffin, Blade, Sir, Amethyst contributors",
	description = "Independent spawn, incoming damage and outgoing facts announcements",
	version = "1.0.0",
	url = "https://github.com/SirPlease/L4D2-Competitive-Rework"
};

#define DANG "ui/pickup_secret01.wav"

enum struct Contribution
{
	int userid;
	int damage;
}

enum struct Encounter
{
	int serial;
	int index;
	int userid;
	bool indexed;
	bool born;
	bool dead;
	int health;
	int maxHealth;
	float since;
	char owner[MAX_NAME_LENGTH];
	char human[MAX_NAME_LENGTH];
	bool ai;
	ArrayList damage;
	int punch;
	int rock;
	int hittable;
	int incap;
	int death;
	int outgoing;
}

Encounter g_Tank[MAXPLAYERS + 1];
int g_Serial;
int g_Index;
int g_Round;
bool g_Ended;
bool g_Late;
ConVar g_Spawn, g_Damage, g_Facts, g_Lottery;
GlobalForward g_OnTankDeath;

// A pre-hit snapshot belongs to both a survivor user ID and an encounter,
// not merely to reusable client slots. Inflictor 0 is legal for iron damage.
int g_HitUser[MAXPLAYERS + 1];
int g_HitTank[MAXPLAYERS + 1];
int g_HitHealth[MAXPLAYERS + 1];
int g_HitTick[MAXPLAYERS + 1];
bool g_HitCounted[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
	g_Late = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("l4d2_tank_announce.phrases");
	LoadTranslations("l4d2_tank_facts_announce.phrases");
	LoadTranslations("tank_announcer.phrases");
	g_Spawn = CreateConVar("tank_announce_spawn", "1", "Announce Tank birth, its sound, and confirmed human control", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Damage = CreateConVar("tank_announce_damage", "1", "Announce survivor damage to each Tank", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Facts = CreateConVar("tank_announce_facts", "0", "Announce each Tank's outgoing combat facts", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Lottery = FindConVar("director_tank_lottery_selection_time");
	g_OnTankDeath = new GlobalForward("OnTankDeath", ET_Event);
	HookEvent("tank_spawn", Event_Spawn);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_bot_replace", Event_Replace);
	HookEvent("bot_player_replace", Event_Replace);
	HookEvent("player_hurt", Event_Hurt);
	HookEvent("player_incapacitated_start", Event_Incap);
	HookEvent("player_death", Event_Death);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client)) continue;
		OnClientPutInServer(client);
	}
	PrecacheSound(DANG);
}

public void OnMapStart()
{
	ResetEncounters();
	PrecacheSound(DANG);
	// SourceMod also calls OnMapStart after a late OnPluginStart; initialize
	// here so that the map reset does not erase the adopted encounters.
	if (g_Late)
	{
		for (int client = 1; client <= MaxClients; client++)
			if (IsLiveTank(client)) EnsureTank(client, true);
		g_Late = false;
	}
}

public void OnMapEnd() { ResetEncounters(); }
public void OnPluginEnd() { ResetEncounters(); }

void ResetEncounters()
{
	++g_Round;
	g_Index = 0;
	g_Ended = false;
	for (int slot = 1; slot <= MaxClients; slot++)
	{
		ClearEncounter(slot);
		g_HitUser[slot] = 0;
		g_HitTank[slot] = 0;
	}
}

void ClearEncounter(int slot)
{
	delete g_Tank[slot].damage;
	Encounter empty;
	g_Tank[slot] = empty;
}

bool ValidClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client);
}

bool IsLiveTank(int client)
{
	return ValidClient(client) && GetClientTeam(client) == 3
		&& GetEntProp(client, Prop_Send, "m_zombieClass") == 8 && IsPlayerAlive(client);
}

int FindUser(int userid)
{
	if (!userid) return 0;
	for (int slot = 1; slot <= MaxClients; slot++)
		if (g_Tank[slot].serial && g_Tank[slot].userid == userid) return slot;
	return 0;
}

int FindSerial(int serial)
{
	for (int slot = 1; slot <= MaxClients; slot++)
		if (g_Tank[slot].serial == serial) return slot;
	return 0;
}

void RememberOwner(int slot, int client)
{
	if (!ValidClient(client)) return;
	g_Tank[slot].ai = IsFakeClient(client);
	if (g_Tank[slot].ai) strcopy(g_Tank[slot].owner, MAX_NAME_LENGTH, "AI");
	else
	{
		GetClientName(client, g_Tank[slot].owner, MAX_NAME_LENGTH);
		GetClientName(client, g_Tank[slot].human, MAX_NAME_LENGTH);
	}
}

void MarkAmbiguousAI()
{
	// Persist the label once needed: the first AI may die before the second's
	// delayed facts arrive. Provisional handoff records are reconciled first.
	for (int a = 1; a <= MaxClients; a++)
	{
		if (!g_Tank[a].serial || !g_Tank[a].ai) continue;
		for (int b = a + 1; b <= MaxClients; b++)
		{
			if (!g_Tank[b].serial || !g_Tank[b].ai) continue;
			g_Tank[a].indexed = true;
			g_Tank[b].indexed = true;
		}
	}
}

void TankLabel(int slot, bool facts, char[] label, int length)
{
	if (facts && g_Tank[slot].ai && g_Tank[slot].human[0])
		FormatEx(label, length, "AI [%s]", g_Tank[slot].human);
	else strcopy(label, length, g_Tank[slot].owner);
	if (g_Tank[slot].ai && g_Tank[slot].indexed)
		Format(label, length, "%s #%d", label, g_Tank[slot].index);
}

int EnsureTank(int client, bool late = false)
{
	if (g_Ended || !IsLiveTank(client)) return 0;
	int userid = GetClientUserId(client);
	int slot = FindUser(userid);
	if (slot) return slot;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_Tank[i].serial) continue;
		slot = i;
		break;
	}
	if (!slot) return 0;
	g_Tank[slot].serial = ++g_Serial;
	g_Tank[slot].index = ++g_Index;
	g_Tank[slot].userid = userid;
	g_Tank[slot].damage = new ArrayList(sizeof(Contribution));
	g_Tank[slot].born = late;
	g_Tank[slot].health = GetClientHealth(client);
	g_Tank[slot].maxHealth = g_Tank[slot].health;
	g_Tank[slot].since = GetGameTime();
	// Preserve the facts source's lottery-time exclusion, including its use in
	// coop. A late adoption has no historical spawn time to adjust.
	if (!late && g_Lottery != null)
		g_Tank[slot].since += g_Lottery.FloatValue;
	RememberOwner(slot, client);
	// Spawn controllers may set final HP in their own next-frame callback.
	RequestFrame(Frame_QueueHealth, g_Tank[slot].serial);
	// Replacement can itself emit tank_spawn. Give explicit transfer events and
	// the ReplaceTank pre-hook confirmation time to merge the provisional birth.
	CreateTimer(0.1, Timer_Birth, g_Tank[slot].serial, TIMER_FLAG_NO_MAPCHANGE);
	return slot;
}

void Event_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	EnsureTank(GetClientOfUserId(event.GetInt("userid")));
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	RequestFrame(Frame_PlayerSpawn, event.GetInt("userid"));
}

public void Frame_PlayerSpawn(int userid)
{
	EnsureTank(GetClientOfUserId(userid));
}

public void L4D_OnSpawnTank_Post(int client, const float pos[3], const float ang[3])
{
	EnsureTank(client);
}

public void Frame_QueueHealth(int serial) { RequestFrame(Frame_Health, serial); }

public void Frame_Health(int serial)
{
	int slot = FindSerial(serial);
	if (!slot || g_Tank[slot].dead) return;
	int client = GetClientOfUserId(g_Tank[slot].userid);
	if (!IsLiveTank(client) || GetEntProp(client, Prop_Send, "m_isIncapacitated")) return;
	int health = GetClientHealth(client);
	int maximum = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	g_Tank[slot].maxHealth = maximum > health ? maximum : health;
	g_Tank[slot].health = health;
}

public Action Timer_Birth(Handle timer, int serial)
{
	int slot = FindSerial(serial);
	if (slot) AnnounceBirth(slot);
	return Plugin_Stop;
}

void AnnounceBirth(int slot)
{
	MarkAmbiguousAI();
	if (g_Tank[slot].born) return;
	g_Tank[slot].born = true;
	if (!g_Spawn.BoolValue) return;
	// Selection is a candidate, not proof of ownership. Only the encounter's
	// actual controller is named; no tank-selection native is required.
	RememberOwner(slot, GetClientOfUserId(g_Tank[slot].userid));
	char label[MAX_NAME_LENGTH * 2];
	TankLabel(slot, false, label, sizeof(label));
	CPrintToChatAll("%t", "Spawned", label);
	EmitSoundToAll(DANG);
}

void Event_Replace(Event event, const char[] name, bool dontBroadcast)
{
	bool toBot = StrEqual(name, "player_bot_replace");
	Transfer(event.GetInt(toBot ? "player" : "bot"), event.GetInt(toBot ? "bot" : "player"));
}

public void L4D_OnReplaceTank(int tank, int newtank)
{
	if (!ValidClient(tank) || !ValidClient(newtank) || tank == newtank) return;
	// A failed attempt to replace onto an already active, independent Tank
	// must not combine their encounters merely because the target is a Tank.
	if (IsLiveTank(newtank) && FindUser(GetClientUserId(newtank))) return;
	int slot = FindUser(GetClientUserId(tank));
	if (slot) RememberOwner(slot, tank);
	// This forward is a pre-hook. Do not adopt the new player until the engine
	// has actually made them a Tank (as in the mature MoYu implementation).
	DataPack pack = new DataPack();
	pack.WriteCell(g_Round);
	pack.WriteCell(GetClientUserId(tank));
	pack.WriteCell(GetClientUserId(newtank));
	RequestFrame(Frame_Transfer, pack);
}

public void Frame_Transfer(DataPack pack)
{
	pack.Reset();
	int round = pack.ReadCell();
	int oldUser = pack.ReadCell();
	int newUser = pack.ReadCell();
	delete pack;
	if (round == g_Round) Transfer(oldUser, newUser);
}

void Transfer(int oldUser, int newUser)
{
	int slot = FindUser(oldUser);
	int client = GetClientOfUserId(newUser);
	if (!slot || oldUser == newUser || !IsLiveTank(client)) return;
	char previousLabel[MAX_NAME_LENGTH * 2];
	TankLabel(slot, false, previousLabel, sizeof(previousLabel));
	int provisional = FindUser(newUser);
	if (provisional && provisional != slot)
	{
		// Events may have already recorded a hit on the new controller.
		Contribution entry;
		for (int i = 0; i < g_Tank[provisional].damage.Length; i++)
		{
			g_Tank[provisional].damage.GetArray(i, entry);
			AddDamage(slot, entry.userid, entry.damage);
		}
		g_Tank[slot].punch += g_Tank[provisional].punch;
		g_Tank[slot].rock += g_Tank[provisional].rock;
		g_Tank[slot].hittable += g_Tank[provisional].hittable;
		g_Tank[slot].incap += g_Tank[provisional].incap;
		g_Tank[slot].death += g_Tank[provisional].death;
		g_Tank[slot].outgoing += g_Tank[provisional].outgoing;
		for (int i = 1; i <= MaxClients; i++)
			if (g_HitTank[i] == g_Tank[provisional].serial) g_HitTank[i] = g_Tank[slot].serial;
		ClearEncounter(provisional);
	}
	g_Tank[slot].userid = newUser;
	g_Tank[slot].dead = false;
	g_Tank[slot].health = GetClientHealth(client);
	RememberOwner(slot, client);
	// Normal PvP assignment may happen well after birth. Report confirmed
	// human control separately rather than pairing a global selection candidate
	// with one of several Tanks. An unannounced birth will name this owner itself.
	if (g_Tank[slot].born && g_Spawn.BoolValue && !IsFakeClient(client))
		CPrintToChatAll("%t", "Tank_ConfirmedControl", previousLabel, g_Tank[slot].owner);
}

public void OnClientPutInServer(int client)
{
	g_HitUser[client] = 0;
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
	int slot = FindUser(GetClientUserId(client));
	if (slot)
	{
		RememberOwner(slot, client);
		QueueFinish(slot);
	}
	g_HitUser[client] = 0;
}

void QueueFinish(int slot)
{
	DataPack pack;
	CreateDataTimer(0.1, Timer_Finish, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(g_Tank[slot].serial);
	pack.WriteCell(g_Tank[slot].userid);
}

public Action Timer_Finish(Handle timer, DataPack pack)
{
	pack.Reset();
	int slot = FindSerial(pack.ReadCell());
	int userid = pack.ReadCell();
	if (!slot || g_Tank[slot].userid != userid) return Plugin_Stop;
	Finish(slot, false);
	// The historical no-argument forward means the Tank phase has ended,
	// not that one particular Tank died. Settle every encounter independently,
	// but notify legacy consumers only after the last one is gone.
	for (int other = 1; other <= MaxClients; other++)
		if (g_Tank[other].serial) return Plugin_Stop;
	Call_StartForward(g_OnTankDeath);
	Call_Finish();
	return Plugin_Stop;
}

void AddDamage(int slot, int userid, int amount)
{
	if (amount <= 0 || !userid) return;
	Contribution entry;
	for (int i = 0; i < g_Tank[slot].damage.Length; i++)
	{
		g_Tank[slot].damage.GetArray(i, entry);
		if (entry.userid != userid) continue;
		entry.damage += amount;
		g_Tank[slot].damage.SetArray(i, entry);
		return;
	}
	entry.userid = userid;
	entry.damage = amount;
	g_Tank[slot].damage.PushArray(entry);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (!ValidClient(victim)) return Plugin_Continue;
	g_HitUser[victim] = 0;
	if (GetClientTeam(victim) != 2 || GetEntProp(victim, Prop_Send, "m_isIncapacitated")) return Plugin_Continue;
	if (!IsLiveTank(attacker)) return Plugin_Continue;
	int slot = EnsureTank(attacker);
	if (!slot) return Plugin_Continue;
	// Do not reject inflictor 0: hittable control deliberately clears it.
	g_HitUser[victim] = GetClientUserId(victim);
	g_HitCounted[victim] = false;
	g_HitTank[victim] = g_Tank[slot].serial;
	g_HitHealth[victim] = GetSurvivorPermanentHealth(victim) + GetSurvivorTemporaryHealth(victim);
	g_HitTick[victim] = GetGameTickCount();
	return Plugin_Continue;
}

bool HasHit(int victim, int slot)
{
	return g_HitUser[victim] == GetClientUserId(victim)
		&& g_HitTank[victim] == g_Tank[slot].serial && g_HitTick[victim] == GetGameTickCount();
}

void CountAttack(int slot, const char[] weapon, int damage)
{
	if (StrEqual(weapon, "tank_claw")) g_Tank[slot].punch++;
	else if (StrEqual(weapon, "tank_rock")) g_Tank[slot].rock++;
	else g_Tank[slot].hittable++; // Preserve hittable-control's inflictor-0 workaround.
	if (damage > 0) g_Tank[slot].outgoing += damage;
}

void Event_Hurt(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!ValidClient(victim)) return;
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int slot = FindUser(event.GetInt("userid"));
	if (slot)
	{
		// The death event awards the exact remaining HP, not overkill damage.
		if (g_Tank[slot].dead || GetEntProp(victim, Prop_Send, "m_isIncapacitated")) return;
		int health = event.GetInt("health");
		int damage = event.GetInt("dmg_health");
		if (damage > g_Tank[slot].health) damage = g_Tank[slot].health;
		if (ValidClient(attacker) && GetClientTeam(attacker) == 2)
			AddDamage(slot, event.GetInt("attacker"), damage);
		// World/fire/infected damage must also update the killing-blow remainder.
		g_Tank[slot].health = health > 0 ? health : 0;
		return;
	}
	if (GetClientTeam(victim) != 2 || GetEntProp(victim, Prop_Send, "m_isIncapacitated")) return;
	slot = FindUser(event.GetInt("attacker"));
	if (!slot) return;
	if (HasHit(victim, slot) && g_HitCounted[victim]) return;
	int damage = event.GetInt("dmg_health");
	// As in the facts source, ordinary hits use the event's damage; only an
	// incapacitating hit substitutes the survivor's pre-hit remaining health.
	if (damage <= 0) return;
	char weapon[64];
	event.GetString("weapon", weapon, sizeof(weapon));
	CountAttack(slot, weapon, damage);
	g_HitCounted[victim] = true;
}

void Event_Incap(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int slot = FindUser(event.GetInt("attacker"));
	if (!slot || !ValidClient(victim) || GetClientTeam(victim) != 2) return;
	g_Tank[slot].incap++;
	if (HasHit(victim, slot) && g_HitCounted[victim]) return;
	int health = HasHit(victim, slot) ? g_HitHealth[victim]
		: GetSurvivorPermanentHealth(victim) + GetSurvivorTemporaryHealth(victim);
	char weapon[64];
	event.GetString("weapon", weapon, sizeof(weapon));
	CountAttack(slot, weapon, health);
	g_HitCounted[victim] = true;
}

void Event_Death(Event event, const char[] name, bool dontBroadcast)
{
	if (event.GetBool("abort")) return; // Engine's synthetic death during a handoff.
	int slot = FindUser(event.GetInt("userid"));
	if (slot)
	{
		if (g_Tank[slot].dead) return;
		int attacker = GetClientOfUserId(event.GetInt("attacker"));
		if (ValidClient(attacker) && GetClientTeam(attacker) == 2)
			AddDamage(slot, event.GetInt("attacker"), g_Tank[slot].health);
		g_Tank[slot].health = 0;
		g_Tank[slot].dead = true;
		RememberOwner(slot, GetClientOfUserId(event.GetInt("userid")));
		QueueFinish(slot);
		return;
	}
	int victim = GetClientOfUserId(event.GetInt("userid"));
	slot = FindUser(event.GetInt("attacker"));
	if (slot && ValidClient(victim) && GetClientTeam(victim) == 2) g_Tank[slot].death++;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) { ResetEncounters(); }

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (g_Ended) return;
	g_Ended = true;
	for (int slot = 1; slot <= MaxClients; slot++)
		if (g_Tank[slot].serial) Finish(slot, !g_Tank[slot].dead);
}

void Finish(int slot, bool remaining)
{
	AnnounceBirth(slot);
	int client = GetClientOfUserId(g_Tank[slot].userid);
	RememberOwner(slot, client);
	if (remaining && IsLiveTank(client)) g_Tank[slot].health = GetClientHealth(client);
	if (g_Damage.BoolValue) PrintDamage(slot, remaining);
	if (g_Facts.BoolValue) QueueFacts(slot);
	ClearEncounter(slot);
}

void PrintDamage(int slot, bool remaining)
{
	char label[MAX_NAME_LENGTH * 2];
	TankLabel(slot, false, label, sizeof(label));
	if (remaining)
		CPrintToChatAll("{default}[{green}!{default}] {blue}Tank {default}({olive}%s{default}) had {green}%d {default}health remaining", label, g_Tank[slot].health);
	else
		CPrintToChatAll("{default}[{green}!{default}] {blue}Damage {default}dealt to {blue}Tank {default}({olive}%s{default})", label);

	// Preserve the old current-survivor output policy, but not its fixed-size
	// survivor_limit array or slot-reuse attribution. Sort only actual entries.
	int clients[MAXPLAYERS + 1], damages[MAXPLAYERS + 1], count;
	int percentTotal, damageTotal;
	float maximum = float(g_Tank[slot].maxHealth > 0 ? g_Tank[slot].maxHealth : 1);
	Contribution entry;
	for (int i = 0; i < g_Tank[slot].damage.Length; i++)
	{
		g_Tank[slot].damage.GetArray(i, entry);
		int client = GetClientOfUserId(entry.userid);
		if (!ValidClient(client) || GetClientTeam(client) != 2 || entry.damage <= 0) continue;
		int at = count++;
		while (at > 0 && (entry.damage > damages[at - 1] || (entry.damage == damages[at - 1] && client > clients[at - 1])))
		{
			clients[at] = clients[at - 1];
			damages[at] = damages[at - 1];
			--at;
		}
		clients[at] = client;
		damages[at] = entry.damage;
		damageTotal += entry.damage;
		percentTotal += RoundToNearest(entry.damage / maximum * 100.0);
	}
	int adjustment;
	if (percentTotal < 100 && float(damageTotal) > maximum - maximum / 200.0) adjustment = 100 - percentTotal;
	int lastPercent = 100;
	for (int i = 0; i < count; i++)
	{
		float exact = damages[i] / maximum * 100.0;
		int percent = RoundToNearest(exact);
		if (adjustment != 0 && FloatAbs(float(percent) - exact) >= 0.001 && percent + adjustment <= lastPercent)
		{
			percent += adjustment;
			adjustment = 0;
		}
		lastPercent = percent;
		CPrintToChatAll("{blue}[{default}%d{blue}] ({default}%i%%{blue}) {olive}%N", damages[i], percent, clients[i]);
	}
}

void QueueFacts(int slot)
{
	char label[MAX_NAME_LENGTH * 2];
	TankLabel(slot, true, label, sizeof(label));
	int duration = RoundToFloor(GetGameTime() - g_Tank[slot].since);
	DataPack pack;
	CreateDataTimer(3.0, Timer_Facts, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(g_Round);
	pack.WriteString(label);
	pack.WriteCell(duration);
	pack.WriteCell(g_Tank[slot].punch);
	pack.WriteCell(g_Tank[slot].rock);
	pack.WriteCell(g_Tank[slot].hittable);
	pack.WriteCell(g_Tank[slot].incap);
	pack.WriteCell(g_Tank[slot].death);
	pack.WriteCell(g_Tank[slot].outgoing);
}

public Action Timer_Facts(Handle timer, DataPack pack)
{
	pack.Reset();
	if (pack.ReadCell() != g_Round || !g_Facts.BoolValue) return Plugin_Stop;
	char label[MAX_NAME_LENGTH * 2];
	pack.ReadString(label, sizeof(label));
	int duration = pack.ReadCell();
	int punch = pack.ReadCell(), rock = pack.ReadCell(), hittable = pack.ReadCell();
	int incap = pack.ReadCell(), death = pack.ReadCell(), damage = pack.ReadCell();
	// Preserve the translation color prefixes: the original uses them to keep
	// asynchronously processed chat messages in order.
	CPrintToChatAll("%t", "Announce_Title", label);
	CPrintToChatAll("%t", "Announce_TankAttack", punch, rock, hittable);
	CPrintToChatAll("%t", "Announce_AttackResult", incap, death);
	if (duration >= 60) CPrintToChatAll("%t", "Announce_Summary_WithMinute", duration / 60, duration % 60, damage);
	else CPrintToChatAll("%t", "Announce_Summary_WithoutMinute", duration, damage);
	return Plugin_Stop;
}
