#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name = "Witch Control",
    author = "norths7ar",
    description = "Blocks future Witch spawns for the active profile.",
    version = "1.0.0"
};

ConVar g_cvBlock;

public void OnPluginStart()
{
    g_cvBlock = CreateConVar("witch_block", "1", "Block future Witch spawns for the active profile.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (g_cvBlock.BoolValue && (StrEqual(classname, "witch") || StrEqual(classname, "witch_bride")))
    {
        RequestFrame(Frame_RemoveWitch, EntIndexToEntRef(entity));
    }
}

public void Frame_RemoveWitch(any entityReference)
{
    int entity = EntRefToEntIndex(entityReference);
    if (g_cvBlock.BoolValue && entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
    {
        AcceptEntityInput(entity, "Kill");
    }
}
