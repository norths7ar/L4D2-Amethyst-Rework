/*
	SourcePawn is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	SourceMod is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	Pawn and SMALL are Copyright (C) 1997-2008 ITB CompuPhase.
	Source is Copyright (C) Valve Corporation.
	All trademarks are property of their respective owners.

	This program is free software: you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the
	Free Software Foundation, either version 3 of the License, or (at your
	option) any later version.

	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// The shared resource coordinator owns round/config readiness.
int g_GlobalWeaponRules[WEPID_SIZE] = {-1, ...};

void FrameworkRules_Init()
{
    RegServerCmd("l4d2_addweaponrule", AddWeaponRuleCb);
    RegServerCmd("l4d2_resetweaponrules", ResetWeaponRulesCb);
    ResetWeaponRules();
}

Action ResetWeaponRulesCb(int args)
{
	ResetWeaponRules();

	return Plugin_Handled;
}

void ResetWeaponRules()
{
	for (int i = 0; i < WEPID_SIZE; i++) {
		g_GlobalWeaponRules[i] = -1;
	}
}

Action AddWeaponRuleCb(int args)
{
	if (args < 2) {
		PrintToServer("Usage: l4d2_addweaponrule <match> <replace>");
		return Plugin_Handled;
	}
	
	char weaponbuf[64];

	GetCmdArg(1, weaponbuf, sizeof(weaponbuf));
	int match = FrameworkWeaponId(weaponbuf);

	GetCmdArg(2, weaponbuf, sizeof(weaponbuf));
	int to = FrameworkWeaponId(weaponbuf);

	AddWeaponRule(match, to);

	return Plugin_Handled;
}


void AddWeaponRule(int match, int to)
{
	if (IsValidWeaponId(match) && (to == -1 || IsValidWeaponId(to))) {
		g_GlobalWeaponRules[match] = to;
		#if 0
		PrintToServer("Added weapon rule: %d to %d", match, to);
		#endif
	}
}

void FrameworkRules_Scan()
{
	int entcnt = GetEntityCount();
	for (int ent = 1; ent <= entcnt; ent++) {
		int source = IdentifyWeapon(ent);
		if (source > WEPID_NONE && g_GlobalWeaponRules[source] != -1) {
			if (g_GlobalWeaponRules[source] == WEPID_NONE) {
				AcceptEntityInput(ent, "kill");
				#if 0
				PrintToServer("Found Weapon %d, killing", source);
				#endif
			} else {
				#if 0
				PrintToServer("Found Weapon %d, converting to %d", source, g_GlobalWeaponRules[source]);
				#endif
				ConvertWeaponSpawn(ent, g_GlobalWeaponRules[source]);
			}
		}
	}
}

int FrameworkWeaponId(const char[] name)
{
    int id = WeaponNameToId(name);
    return id == WEPID_NONE ? WeaponNameToId2(name) : id;
}
