#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define INSTRUCTOR_FILE "scripts/instructor_lessons.txt"
#define EXACT_FILE_DATA_SIZE 17

char g_OriginalData[EXACT_FILE_DATA_SIZE];
bool g_HasOriginalData;

public Plugin myinfo =
{
    name = "Instructor Filter Support",
    author = "norths7ar",
    description = "Allows optional client instructor filters without disabling other consistency checks.",
    version = "1.0.0"
};

public void OnMapStart()
{
    g_HasOriginalData = false;
    AllowInstructorFilter(false);
}

public void OnConfigsExecuted()
{
    AllowInstructorFilter(true);
}

void AllowInstructorFilter(bool reportMissing)
{
    if (g_HasOriginalData)
        return;

    int table = FindStringTable("downloadables");
    int index = table == INVALID_STRING_TABLE ? INVALID_STRING_INDEX : FindStringIndex(table, INSTRUCTOR_FILE);
    if (index == INVALID_STRING_INDEX)
    {
        if (reportMissing)
            LogError("Instructor consistency entry not found; no file checks changed.");
        return;
    }

    int length = GetStringTableDataLength(table, index);
    if (length == 0)
        return;

    // ForceExactFile stores a one-byte consistency type followed by a 16-byte MD5.
    // Only this entry is relaxed; sv_consistency and the whitelist stay untouched.
    if (length != sizeof(g_OriginalData))
    {
        LogError("Unexpected instructor consistency data size %d; no file checks changed.", length);
        return;
    }
    GetStringTableData(table, index, g_OriginalData, sizeof(g_OriginalData));
    if ((g_OriginalData[0] & 0xFF) != 1)
    {
        LogError("Unexpected instructor consistency type; no file checks changed.");
        return;
    }

    bool locked = LockStringTables(false);
    SetStringTableData(table, index, "", 0);
    LockStringTables(locked);
    g_HasOriginalData = true;
}

public void OnMapEnd()
{
    // The next map has a newly built table and its own original checksum.
    g_HasOriginalData = false;
}

public void OnPluginEnd()
{
    if (!g_HasOriginalData)
        return;

    int table = FindStringTable("downloadables");
    if (table == INVALID_STRING_TABLE)
        return;
    int index = FindStringIndex(table, INSTRUCTOR_FILE);
    if (index == INVALID_STRING_INDEX || GetStringTableDataLength(table, index) != 0)
        return;

    // Mode unloading restores the original check, including its binary MD5.
    bool locked = LockStringTables(false);
    SetStringTableData(table, index, g_OriginalData, sizeof(g_OriginalData));
    LockStringTables(locked);
}
