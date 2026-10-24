#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "1.0.1"
#define GAMEDATA_FILE "l4d_flow_fallback"

public Plugin myinfo =
{
	name = "[L4D2] Flow Fallback",
	author = "Northstar",
	description = "Preserve complete flow results when round-restart initialization fails.",
	version = PLUGIN_VERSION
};

enum
{
	Mesh_MaxFlow,
	Mesh_MaxFlowOutsideCheckpoint,
	Mesh_MinBattleStationFlow,
	Mesh_StartArea,
	Mesh_RescueVehicleArea,
	Mesh_GoalArea,
	MeshResult_Count
};

static const char MESH_RESULT_KEYS[][] =
{
	"TerrorNavMesh::MaxFlow",
	"TerrorNavMesh::MaxFlowOutsideCheckpoint",
	"TerrorNavMesh::MinBattleStationFlow",
	"TerrorNavMesh::StartArea",
	"TerrorNavMesh::RescueVehicleArea",
	"TerrorNavMesh::GoalArea"
};

enum struct AreaResult
{
	Address area;
	int flow0;
	int flow1;
	int escapeBit;
}

enum struct ComputeFrame
{
	Address mesh;
	Address previousStart;
	int mapEpoch;
	int meshResults[MeshResult_Count];
	ArrayList areas;
	ArrayList routeInputs;
	ArrayList routeNodes;
	int pathLength;
}

enum struct RouteBuildFrame
{
	Address start;
	int mapEpoch;
	ArrayList inputs;
	ArrayList previousAreas;
	ArrayList previousInputs;
	ArrayList previousNodes;
	int previousLength;
}

DynamicDetour g_RestartHook;
DynamicDetour g_ComputeHook;
DynamicDetour g_BuildRouteHook;
DynamicDetour g_AddAreaHook;
ArrayList g_ComputeFrames;
ArrayList g_BuildFrames;
Handle g_ResetPath;
Handle g_AddArea;
Handle g_FinishPath;
int g_RouteCountOffset;
int g_RouteAreasOffset;
int g_RouteLengthOffset;
int g_RouteCapacity;
ArrayList g_SavedRouteInputs;
ArrayList g_SavedRouteNodes;
Address g_SavedRouteStart;
Address g_SavedRouteGoal;
Address g_SavedRouteMesh;
int g_SavedRouteLength;
ArrayList g_PendingAreas;
ArrayList g_PendingRouteInputs;
ArrayList g_PendingRouteNodes;
Address g_PendingStart;
int g_PendingLength;
bool g_ReplayingRoute;
int g_AreaFlowOffsets[2];
int g_AreaSpawnAttributesOffset;
int g_MeshResultOffsets[MeshResult_Count];
bool g_MapReady;
int g_MapEpoch;
int g_NavRestartDepth;
Address g_LastSuccessStart;
Address g_LastSuccessMesh;

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_Left4Dead2)
		SetFailState("This plugin requires Left 4 Dead 2");

	GameData data = new GameData(GAMEDATA_FILE);
	if (data == null)
		SetFailState("Missing gamedata \"" ... GAMEDATA_FILE ... "\"");
	if (data.GetOffset("OS") != 1)
		SetFailState("Unsupported platform: verified Linux x86 only; Windows is unsupported");

	g_AreaFlowOffsets[0] = GetOffsetOrFail(data, "TerrorNavArea::Flow0");
	g_AreaFlowOffsets[1] = GetOffsetOrFail(data, "TerrorNavArea::Flow1");
	g_AreaSpawnAttributesOffset = GetOffsetOrFail(data, "TerrorNavArea::SpawnAttributes");
	for (int i = 0; i < MeshResult_Count; i++)
		g_MeshResultOffsets[i] = GetOffsetOrFail(data, MESH_RESULT_KEYS[i]);
	g_RouteCountOffset = GetOffsetOrFail(data, "CEscapeRoute::NodeCount");
	g_RouteAreasOffset = GetOffsetOrFail(data, "CEscapeRoute::NodeAreas");
	g_RouteLengthOffset = GetOffsetOrFail(data, "CEscapeRoute::PathLength");
	g_RouteCapacity = GetOffsetOrFail(data, "CEscapeRoute::NodeCapacity");
	g_ResetPath = PrepareRouteCall(data, "CEscapeRoute::ResetPath");
	g_AddArea = PrepareRouteCall(data, "CEscapeRoute::AddArea", true);
	g_FinishPath = PrepareRouteCall(data, "CEscapeRoute::FinishPath");

	g_ComputeFrames = new ArrayList(sizeof(ComputeFrame));
	g_BuildFrames = new ArrayList(sizeof(RouteBuildFrame));
	g_RestartHook = DynamicDetour.FromConf(data, "TerrorNavMesh::OnRoundRestart");
	g_ComputeHook = DynamicDetour.FromConf(data, "TerrorNavMesh::ComputeFlowDistances");
	g_BuildRouteHook = DynamicDetour.FromConf(data, "ZombieManager::BuildEscapeRoute");
	g_AddAreaHook = DynamicDetour.FromConf(data, "CEscapeRoute::AddArea");
	delete data;
	if (g_RestartHook == null || g_ComputeHook == null || g_BuildRouteHook == null || g_AddAreaHook == null)
		SetFailState("Cannot resolve flow fallback detours");
	if (!g_RestartHook.Enable(Hook_Pre, RestartPre)
		|| !g_RestartHook.Enable(Hook_Post, RestartPost)
		|| !g_ComputeHook.Enable(Hook_Pre, ComputePre)
		|| !g_ComputeHook.Enable(Hook_Post, ComputePost)
		|| !g_BuildRouteHook.Enable(Hook_Pre, BuildRoutePre)
		|| !g_BuildRouteHook.Enable(Hook_Post, BuildRoutePost)
		|| !g_AddAreaHook.Enable(Hook_Pre, AddAreaPre))
		SetFailState("Cannot enable flow fallback detours");
}

Handle PrepareRouteCall(GameData data, const char[] name, bool takesArea = false)
{
	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetFromConf(data, SDKConf_Signature, name))
		SetFailState("Missing signature \"%s\"", name);
	if (takesArea)
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	// ResetPath, AddArea and FinishPath are void instance methods.
	Handle call = EndPrepSDKCall();
	if (call == null)
		SetFailState("Cannot prepare SDKCall \"%s\"", name);
	return call;
}

int GetOffsetOrFail(GameData data, const char[] key)
{
	int offset = data.GetOffset(key);
	if (offset == -1)
		SetFailState("Missing offset \"%s\"", key);
	return offset;
}

public void OnMapStart()
{
	// Initial Compute may already have succeeded. Retain its real return value,
	// but wait for this forward before enumerating areas through Left4DHooks.
	// Failures before this point cannot be restored. Late loading also requires
	// an observed complete success; positive existing maxflow is not a baseline.
	g_MapReady = true;
}

public void OnMapEnd()
{
	g_MapReady = false;
	g_MapEpoch++;
	g_NavRestartDepth = 0;
	RememberResult(Address_Null, Address_Null);
	ClearFrames();
	ClearRouteState();
}

public void OnPluginEnd()
{
	if (g_RestartHook != null)
	{
		g_RestartHook.Disable(Hook_Pre, RestartPre);
		g_RestartHook.Disable(Hook_Post, RestartPost);
	}
	if (g_ComputeHook != null)
	{
		g_ComputeHook.Disable(Hook_Pre, ComputePre);
		g_ComputeHook.Disable(Hook_Post, ComputePost);
	}
	if (g_BuildRouteHook != null)
	{
		g_BuildRouteHook.Disable(Hook_Pre, BuildRoutePre);
		g_BuildRouteHook.Disable(Hook_Post, BuildRoutePost);
	}
	if (g_AddAreaHook != null)
		g_AddAreaHook.Disable(Hook_Pre, AddAreaPre);
	delete g_RestartHook;
	delete g_ComputeHook;
	delete g_BuildRouteHook;
	delete g_AddAreaHook;
	delete g_ResetPath;
	delete g_AddArea;
	delete g_FinishPath;
	ClearFrames();
	ClearRouteState();
	delete g_ComputeFrames;
	delete g_BuildFrames;
}

public MRESReturn RestartPre(Address mesh)
{
	g_NavRestartDepth++;
	// Run the original Reset and the entire restart initialization unchanged.
	return MRES_Ignored;
}

public MRESReturn RestartPost(Address mesh)
{
	if (g_NavRestartDepth > 0)
		g_NavRestartDepth--;
	if (g_NavRestartDepth == 0)
		ClearPendingRoute();
	return MRES_Ignored;
}

public MRESReturn ComputePre(Address mesh, DHookReturn result)
{
	if (!g_MapReady)
		return MRES_Ignored;

	ComputeFrame frame;
	frame.mesh = mesh;
	frame.mapEpoch = g_MapEpoch;
	if (g_NavRestartDepth > 0 && mesh != Address_Null
		&& g_LastSuccessMesh == mesh && g_LastSuccessStart != Address_Null
		&& g_SavedRouteInputs != null && g_SavedRouteMesh == mesh
		&& g_SavedRouteStart == g_LastSuccessStart
		&& g_SavedRouteGoal == view_as<Address>(LoadFromAddress(mesh + view_as<Address>(g_MeshResultOffsets[Mesh_GoalArea]), NumberType_Int32))
		&& ValidMaxFlow(ReadMaxFlow(mesh)))
	{
		frame.previousStart = g_LastSuccessStart;
		SaveResults(frame);
		frame.routeInputs = g_SavedRouteInputs.Clone();
		frame.routeNodes = g_SavedRouteNodes.Clone();
		frame.pathLength = g_SavedRouteLength;
	}

	// Pair every Compute, including unprotected nested calls, in LIFO order.
	g_ComputeFrames.PushArray(frame);
	return MRES_Ignored;
}

public MRESReturn ComputePost(Address mesh, DHookReturn result)
{
	Address actualStart = view_as<Address>(result.Value);
	if (!g_MapReady)
	{
		// No field reads or NAV enumeration before OnMapStart. A failed result
		// invalidates the baseline even if type0 left a positive maxflow.
		RememberResult(mesh, actualStart);
		ClearSavedRoute();
		ClearPendingRoute();
		return MRES_Ignored;
	}
	if (g_ComputeFrames.Length == 0)
	{
		RememberResult(mesh, actualStart);
		ClearSavedRoute();
		ClearPendingRoute();
		return MRES_Ignored;
	}

	ComputeFrame frame;
	int top = g_ComputeFrames.Length - 1;
	g_ComputeFrames.GetArray(top, frame);
	g_ComputeFrames.Erase(top);
	if (frame.mapEpoch != g_MapEpoch || frame.mesh != mesh)
	{
		DeleteComputeFrame(frame);
		RememberResult(Address_Null, Address_Null);
		ClearSavedRoute();
		ClearPendingRoute();
		LogError("Flow computation frame mismatch; no fallback applied");
		return MRES_Ignored;
	}

	if (actualStart != Address_Null)
	{
		// The native start-area return confirms both directions completed.
		// Always accept successful new routes rather than freezing the first one.
		RememberResult(mesh, actualStart);
		ClearSavedRoute();
		ClearPendingRoute();
		DeleteComputeFrame(frame);
		return MRES_Ignored;
	}

	float failedMax = ReadMaxFlow(mesh);
	if (frame.areas == null || g_NavRestartDepth <= 0)
	{
		RememberResult(Address_Null, Address_Null);
		ClearSavedRoute();
		ClearPendingRoute();
		LogFailure(false, failedMax, failedMax);
		DeleteComputeFrame(frame);
		return MRES_Ignored;
	}

	RestoreResults(frame);
	RememberResult(mesh, frame.previousStart);
	ClearPendingRoute();
	g_PendingAreas = frame.areas;
	g_PendingRouteInputs = frame.routeInputs;
	g_PendingRouteNodes = frame.routeNodes;
	g_PendingStart = frame.previousStart;
	g_PendingLength = frame.pathLength;
	// Initialize expects the selected valid start-area pointer, not bool 1.
	result.Value = view_as<int>(frame.previousStart);
	LogFailure(true, failedMax, ReadMaxFlow(mesh));
	return MRES_Override;
}

public MRESReturn BuildRoutePre(Address manager, DHookParam params)
{
	RouteBuildFrame frame;
	frame.start = view_as<Address>(params.Get(1));
	frame.mapEpoch = g_MapEpoch;
	if (g_NavRestartDepth > 0 && g_PendingRouteInputs != null && frame.start == g_PendingStart)
	{
		frame.previousAreas = g_PendingAreas;
		frame.previousInputs = g_PendingRouteInputs;
		frame.previousNodes = g_PendingRouteNodes;
		frame.previousLength = g_PendingLength;
		g_PendingAreas = null;
		g_PendingRouteInputs = null;
		g_PendingRouteNodes = null;
		g_PendingStart = Address_Null;
	}
	else
		frame.inputs = new ArrayList();
	g_BuildFrames.PushArray(frame);
	// Run the native builder so a deleted escape_route is recreated normally.
	return MRES_Ignored;
}

public MRESReturn AddAreaPre(Address route, DHookParam params)
{
	if (g_ReplayingRoute || g_BuildFrames.Length == 0)
		return MRES_Ignored;
	RouteBuildFrame frame;
	g_BuildFrames.GetArray(g_BuildFrames.Length - 1, frame);
	if (frame.inputs != null)
		frame.inputs.Push(params.Get(1));
	return MRES_Ignored;
}

public MRESReturn BuildRoutePost(Address manager, DHookParam params)
{
	if (g_BuildFrames.Length == 0)
		return MRES_Ignored;
	RouteBuildFrame frame;
	int top = g_BuildFrames.Length - 1;
	g_BuildFrames.GetArray(top, frame);
	g_BuildFrames.Erase(top);
	if (frame.mapEpoch != g_MapEpoch)
	{
		DeleteBuildFrame(frame);
		return MRES_Ignored;
	}

	int entity = FindEntityByClassname(-1, "escape_route");
	Address route = entity != -1 ? GetEntityAddress(entity) : Address_Null;
	if (frame.previousInputs != null)
	{
		if (route == Address_Null)
		{
			ClearSavedRoute();
			LogError("Escape route fallback failed: native builder did not create an entity");
		}
		else
		{
			// ResetPath does not remove ESCAPE_ROUTE marks added by the failed
			// native build. Restore the same ComputePre bit set before replaying.
			RestoreEscapeBits(frame.previousAreas);
			g_ReplayingRoute = true;
			SDKCall(g_ResetPath, route);
			for (int i = 0; i < frame.previousInputs.Length; i++)
				SDKCall(g_AddArea, route, frame.previousInputs.Get(i));
			SDKCall(g_FinishPath, route);
			g_ReplayingRoute = false;
			if (!RouteMatches(route, frame.previousNodes, frame.previousLength))
			{
				ClearSavedRoute();
				LogError("Escape route fallback mismatch: node sequence or path length differs");
			}
			else
				LogMessage("Escape route fallback restored %d nodes with unchanged path length", frame.previousNodes.Length);
		}
		DeleteBuildFrame(frame);
		return MRES_Ignored;
	}

	// Build can precede OnMapStart. Read only this entity's inline node array;
	// no Left4DHooks area enumeration or retained entity address is needed.
	if (route != Address_Null && frame.inputs.Length > 0
		&& frame.start == g_LastSuccessStart && g_LastSuccessMesh != Address_Null)
	{
		Address goal = view_as<Address>(LoadFromAddress(g_LastSuccessMesh + view_as<Address>(g_MeshResultOffsets[Mesh_GoalArea]), NumberType_Int32));
		if (view_as<Address>(frame.inputs.Get(0)) == goal
			&& view_as<Address>(frame.inputs.Get(frame.inputs.Length - 1)) == frame.start)
		{
			ArrayList nodes = ReadRouteNodes(route);
			if (nodes != null)
			{
				ClearSavedRoute();
				g_SavedRouteInputs = frame.inputs;
				frame.inputs = null;
				g_SavedRouteNodes = nodes;
				g_SavedRouteStart = frame.start;
				g_SavedRouteGoal = goal;
				g_SavedRouteMesh = g_LastSuccessMesh;
				g_SavedRouteLength = LoadFromAddress(route + view_as<Address>(g_RouteLengthOffset), NumberType_Int32);
			}
		}
	}
	DeleteBuildFrame(frame);
	return MRES_Ignored;
}

ArrayList ReadRouteNodes(Address route)
{
	int count = LoadFromAddress(route + view_as<Address>(g_RouteCountOffset), NumberType_Int32);
	if (count <= 0 || count > g_RouteCapacity)
		return null;
	ArrayList nodes = new ArrayList();
	for (int i = 0; i < count; i++)
		nodes.Push(LoadFromAddress(route + view_as<Address>(g_RouteAreasOffset + i * 4), NumberType_Int32));
	return nodes;
}

bool RouteMatches(Address route, ArrayList expected, int length)
{
	if (LoadFromAddress(route + view_as<Address>(g_RouteCountOffset), NumberType_Int32) != expected.Length
		|| LoadFromAddress(route + view_as<Address>(g_RouteLengthOffset), NumberType_Int32) != length)
		return false;
	for (int i = 0; i < expected.Length; i++)
		if (LoadFromAddress(route + view_as<Address>(g_RouteAreasOffset + i * 4), NumberType_Int32) != expected.Get(i))
			return false;
	return true;
}

void RememberResult(Address mesh, Address start)
{
	g_LastSuccessStart = start;
	g_LastSuccessMesh = start != Address_Null ? mesh : Address_Null;
}

void SaveResults(ComputeFrame frame)
{
	for (int i = 0; i < MeshResult_Count; i++)
		frame.meshResults[i] = LoadFromAddress(frame.mesh + view_as<Address>(g_MeshResultOffsets[i]), NumberType_Int32);

	ArrayList allAreas = new ArrayList();
	L4D_GetAllNavAreas(allAreas);
	frame.areas = new ArrayList(sizeof(AreaResult));
	AreaResult row;
	for (int i = 0; i < allAreas.Length; i++)
	{
		row.area = view_as<Address>(allAreas.Get(i));
		row.flow0 = LoadFromAddress(row.area + view_as<Address>(g_AreaFlowOffsets[0]), NumberType_Int32);
		row.flow1 = LoadFromAddress(row.area + view_as<Address>(g_AreaFlowOffsets[1]), NumberType_Int32);
		row.escapeBit = LoadFromAddress(row.area + view_as<Address>(g_AreaSpawnAttributesOffset), NumberType_Int32) & NAV_SPAWN_ESCAPE_ROUTE;
		frame.areas.PushArray(row);
	}
	delete allAreas;
}

void RestoreResults(ComputeFrame frame)
{
	// Restore only computed results. Keep physical blockers, other attributes,
	// search state, timers and consumed processing queues as the engine left them.
	AreaResult row;
	for (int i = 0; i < frame.areas.Length; i++)
	{
		frame.areas.GetArray(i, row);
		StoreToAddress(row.area + view_as<Address>(g_AreaFlowOffsets[0]), row.flow0, NumberType_Int32);
		StoreToAddress(row.area + view_as<Address>(g_AreaFlowOffsets[1]), row.flow1, NumberType_Int32);
	}
	RestoreEscapeBits(frame.areas);
	for (int i = 0; i < MeshResult_Count; i++)
		StoreToAddress(frame.mesh + view_as<Address>(g_MeshResultOffsets[i]), frame.meshResults[i], NumberType_Int32);
}

void RestoreEscapeBits(ArrayList areas)
{
	AreaResult row;
	for (int i = 0; i < areas.Length; i++)
	{
		areas.GetArray(i, row);
		Address attributes = row.area + view_as<Address>(g_AreaSpawnAttributesOffset);
		int current = LoadFromAddress(attributes, NumberType_Int32);
		StoreToAddress(attributes, (current & ~NAV_SPAWN_ESCAPE_ROUTE) | row.escapeBit, NumberType_Int32);
	}
}

void DeleteComputeFrame(ComputeFrame frame)
{
	delete frame.areas;
	delete frame.routeInputs;
	delete frame.routeNodes;
}

void DeleteBuildFrame(RouteBuildFrame frame)
{
	delete frame.inputs;
	delete frame.previousAreas;
	delete frame.previousInputs;
	delete frame.previousNodes;
}

void ClearSavedRoute()
{
	delete g_SavedRouteInputs;
	delete g_SavedRouteNodes;
	g_SavedRouteStart = Address_Null;
	g_SavedRouteGoal = Address_Null;
	g_SavedRouteMesh = Address_Null;
}

void ClearPendingRoute()
{
	delete g_PendingAreas;
	delete g_PendingRouteInputs;
	delete g_PendingRouteNodes;
	g_PendingStart = Address_Null;
}

void ClearRouteState()
{
	ClearSavedRoute();
	ClearPendingRoute();
	g_ReplayingRoute = false;
	if (g_BuildFrames == null)
		return;
	RouteBuildFrame frame;
	for (int i = 0; i < g_BuildFrames.Length; i++)
	{
		g_BuildFrames.GetArray(i, frame);
		DeleteBuildFrame(frame);
	}
	g_BuildFrames.Clear();
}

void ClearFrames()
{
	if (g_ComputeFrames == null)
		return;
	ComputeFrame frame;
	for (int i = 0; i < g_ComputeFrames.Length; i++)
	{
		g_ComputeFrames.GetArray(i, frame);
		DeleteComputeFrame(frame);
	}
	g_ComputeFrames.Clear();
}

float ReadMaxFlow(Address mesh)
{
	return view_as<float>(LoadFromAddress(mesh + view_as<Address>(g_MeshResultOffsets[Mesh_MaxFlow]), NumberType_Int32));
}

bool ValidMaxFlow(float value)
{
	return value > 0.0 && value < view_as<float>(0x7F7FFFFF);
}

void LogFailure(bool restored, float before, float after)
{
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	LogMessage("Flow computation failed: map=%s curtime=%.3f fallback=%d maxflow=%f -> %f",
		map, GetGameTime(), restored, before, after);
}
