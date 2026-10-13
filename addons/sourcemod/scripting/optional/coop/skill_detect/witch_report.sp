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
// Migrated from Witch Damage Announce 1.4 by Sir.
// https://github.com/SirPlease/L4D2-Competitive-Rework
/*
* Version 0.1b
* - Catches Damage done to Witch
* - Prints to Chat on Witch Death.
*
* Version 0.2b
* - Fixed Percentages not adding up to 100 because Damage doesn't equal Witch's health.
* - Prints Damage and Remaining Health when Witch Survives (Both when someone gets killed or when Witch incaps last person alive)
*
* Version 1.0 <Public Release>
* - Fixed Damage Prints either being over or under Witch's Health
* - Only Show people that did damage to the Witch, the Witch is not something you need to gang up on.
*
* Version 1.0a
* - Blocked SI Damage to Witch (Except for Tank) - This also fixes less than 1000 Damage/100 %
* - Allows Console Witch Spawns. (Doesn't support Multiple Witches at the same time)
*
* Version 1.1
* - Added "Tank-Kill" Notifier when Tank kills Witch.
* - Added Cvar to enable or disable SI from causing the witch to get startled. (FF to Witch is always blocked)
*
* Version 1.1b
* - Last Fix for Damage/Percentages; not adding up to 1000/100%.
* - Changed print format a bit.
*
* Version 1.1c
* - Removed the witch FF code since it logically belongs to the si_ff_block plugin
*
* Version 1.2
* - Color Prints!
*
* Version 1.3
* - Syntax Update
* - Remove comments for self explanatory code
* - Removed unnecessary code
* - Fix issues caused by relying on hardcoded values
*
* Version 1.4
* - Resolve errors for setups that don't remove the upperbound value for survivor_limit while still having over 4 Survivors.
* - Officially support damage recording for multiple witches at the same time.
* - Updated IsTank check to account for L4D1 Servers running this plugin.
* - Add a ConVar to control whether we print on incaps or not (Default OFF).
* - Add a ConVar to control whether we combine percentages lower than a minimum percentage (Default OFF).
* - Add a ConVar to limit the total amount of damage lines printed (Default OFF).
*   - Setting this to "5" would limit the prints to either 5 Survivors or 4 (+ "The Other Survivors") when 6 players damaged the witch.
* - Add a ConVar for the combination name (Default: "The Other Survivors").
*/

int g_WdaSortDamage[MAXPLAYERS + 1];
void WitchPrintDamage(WitchRecord record, bool witchAlive = false)
{
    int printMinimum = g_WdaMinimum.IntValue;
    int printMaxLines = g_WdaMaxLines.IntValue;
    char combinationName[32];
    g_WdaCombination.GetString(combinationName, sizeof(combinationName));
    int visibleTotal;
    for (int i = 1; i <= MaxClients; i++) g_WdaSortDamage[i] = 0;
    WitchContribution contribution;
    for (int i; i < record.contributions.Length; i++)
    {
        record.contributions.GetArray(i, contribution);
        int client = GetClientOfUserId(contribution.userid);
        if (!IsValidSurvivor(client)) continue;
        g_WdaSortDamage[client] = contribution.actual;
        visibleTotal += contribution.actual;
    }
    // Unlike WDA's inferred missing-damage fill, only measured HP loss belongs
    // to a survivor. Environmental damage must not be credited to the killer.

    if (!g_WitchRoundLive || record.printed)
        return;

    if (witchAlive)
        CPrintToChatAll("{default}[{green}!{default}] {blue}Witch {default}had {olive}%d {default}health remaining", record.remaining);
    else
        CPrintToChatAll("{default}[{green}!{default}] {blue}Damage {default}dealt to {blue}Witch:");

    int
        totalPercent,
        survivorIndex,
        percentDamage,
        damage,
        percentAdjustment,
        adjustedPercentDamage;

    int[] survivorClients = new int[MaxClients];

    int lastPercent = 100;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != 2 || g_WdaSortDamage[i] == 0)
            continue;

        survivorClients[survivorIndex++] = i;
        damage = g_WdaSortDamage[i];
        percentDamage = WitchDamagePercent(damage, record.maxHealth);
        totalPercent += percentDamage;
    }


    SortCustom1D(survivorClients, survivorIndex, WitchSortDamage);

    // Percents add up to less than 100% AND > 99.5% damage was dealt to witch
    if ((totalPercent < 100 && float(visibleTotal) > (float(record.maxHealth) - (float(record.maxHealth) / 200.0))))
    {
        percentAdjustment = 100 - totalPercent;
    }

    int restDamage;
    int restPercent;

    for (int k; k < survivorIndex; k++)
    {
        int client = survivorClients[k];
        damage = g_WdaSortDamage[client];
        percentDamage = WitchDamagePercent(damage, record.maxHealth);

        if (percentAdjustment != 0 && damage > 0 && !WitchExactPercent(damage, record.maxHealth))
        {
            adjustedPercentDamage = percentDamage + percentAdjustment;
            if (adjustedPercentDamage <= lastPercent)
            {
                percentDamage = adjustedPercentDamage;
                percentAdjustment = 0;
            }
        }

        lastPercent = percentDamage;

        /*
            Minimum damage percentage (cvarPrintMinimum):
            - When damage is lower than minimum, get combined.

            Maximum damage lines (cvarPrintMaxLines):
            - Check if Survivor count that has damaged the witch would exceed the max lines, if so combine the ones with the lowest damage.
        */

        if ((printMinimum && percentDamage < printMinimum)
        || printMaxLines && survivorIndex > printMaxLines && k + 1 >= printMaxLines)
        {
            restDamage += damage;
            restPercent += percentDamage;
            continue;
        }

        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                CPrintToChat(i, "{blue}[{default}%d{blue}] ({default}%i%%{blue}) {olive}%N", damage, percentDamage, client);
            }
        }
    }

    if (restDamage)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                CPrintToChat(i, "{blue}[{default}%d{blue}] ({default}%i%%{blue}) {green}%s", restDamage, restPercent, combinationName);
            }
        }
    }
}

int WitchDamagePercent(int damage, int maxHealth)
{
    return RoundToNearest((damage / float(maxHealth)) * 100.0);
}
bool WitchExactPercent(int damage, int maxHealth)
{
    float percent = (damage / float(maxHealth)) * 100.0;
    return FloatAbs(float(WitchDamagePercent(damage, maxHealth)) - percent) < 0.001;
}
int WitchSortDamage(int elem1, int elem2, const int[] array, Handle hndl)
{
    // By damage, then by client index, descending (original WDA tie order).
    if (g_WdaSortDamage[elem1] > g_WdaSortDamage[elem2]) return -1;
    if (g_WdaSortDamage[elem2] > g_WdaSortDamage[elem1]) return 1;
    if (elem1 > elem2) return -1;
    if (elem2 > elem1) return 1;
    return 0;
}