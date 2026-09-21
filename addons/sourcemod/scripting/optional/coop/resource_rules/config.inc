// Resource policy, region overrides and existing chapter ItemLimits.
// No resource creation or entity removal belongs in this file.
#define SUPPLY_COUNT 7
char g_supplyNames[SUPPLY_COUNT][] = {"pain_pills", "adrenaline", "first_aid_kit", "defibrillator", "molotov", "pipe_bomb", "vomitjar"};
StringMap g_regionRules[3]; // start, end (including configured finale), along
StringMap g_selections;
int g_defaultLimits[SUPPLY_COUNT], g_limits[SUPPLY_COUNT];
ConVar g_flowMin, g_flowMax, g_flowSeparation, g_flowFinale, g_flowVisualize;
float g_chapterFlow[3];

void InitPolicy()
{
	for (int i = 0; i < 3; i++) g_regionRules[i] = new StringMap();
	g_selections = new StringMap();
	g_flowMin = CreateConVar("resource_pills_flow_min", "0", "Minimum pill flow fraction.", _, true, 0.0, true, 1.0);
	g_flowMax = CreateConVar("resource_pills_flow_max", "1", "Maximum pill flow fraction.", _, true, 0.0, true, 1.0);
	g_flowSeparation = CreateConVar("resource_pills_flow_separation", "0", "Minimum gap between pill flow fractions.", _, true, 0.0, true, 1.0);
	g_flowFinale = CreateConVar("resource_pills_flow_finale", "0", "Apply pill flow filtering on finales.", _, true, 0.0, true, 1.0);
	g_flowVisualize = CreateConVar("resource_pills_flow_visualize", "0", "0: off; 1: preview using glow; 2: remove and glow retained pills.", _, true, 0.0, true, 2.0);
}

void ReadRuleSection(KeyValues kv, const char[] section, StringMap target)
{
	target.Clear();
	if (!kv.JumpToKey(section)) return;
	if (kv.GotoFirstSubKey(false))
	{
		do {
			char name[64], value[256];
			kv.GetSectionName(name, sizeof(name));
			kv.GetString(NULL_STRING, value, sizeof(value));
			target.SetString(name, value);
		} while (kv.GotoNextKey(false));
		kv.GoBack();
	}
	kv.GoBack();
}

void LoadRules()
{
	char file[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	g_rulesFile.GetString(file, sizeof(file));
	BuildPath(Path_SM, path, sizeof(path), "configs/%s", file);
	KeyValues rules = new KeyValues("ResourceRules");
	if (!rules.ImportFromFile(path)) SetFailState("Cannot read resource policy %s", path);
	g_meleePickups = rules.GetNum("melee_pickups", 1);
	ReadRuleSection(rules, "rules", g_rules);
	ReadRuleSection(rules, "weapon_selections", g_selections);
	static char regions[][] = {"start", "end", "along"};
	for (int i = 0; i < 3; i++) g_regionRules[i].Clear();
	if (rules.JumpToKey("regions"))
	{
		for (int i = 0; i < 3; i++) ReadRuleSection(rules, regions[i], g_regionRules[i]);
		rules.GoBack();
	}
	for (int i = 0; i < SUPPLY_COUNT; i++) g_defaultLimits[i] = -1;
	if (rules.JumpToKey("ItemLimits"))
	{
		for (int i = 0; i < SUPPLY_COUNT; i++) g_defaultLimits[i] = rules.GetNum(g_supplyNames[i], -1);
		rules.GoBack();
	}
	delete rules;
}

void LoadChapterLimits()
{
	KeyValues limits = new KeyValues("ItemLimits");
	if (LGO_IsMapDataAvailable()) LGO_CopyMapSubsection(limits, "ItemLimits");
	for (int i = 0; i < SUPPLY_COUNT; i++) g_limits[i] = limits.GetNum(g_supplyNames[i], g_defaultLimits[i]);
	delete limits;
	g_chapterFlow[0] = LGO_IsMapDataAvailable() ? LGO_GetMapValueFloat("pillflow_min", -1.0) : -1.0;
	g_chapterFlow[1] = LGO_IsMapDataAvailable() ? LGO_GetMapValueFloat("pillflow_max", -1.0) : -1.0;
	g_chapterFlow[2] = LGO_IsMapDataAvailable() ? LGO_GetMapValueFloat("pillflow_separation", -1.0) : -1.0;
}

// -1 is unknown, not automatically "along". Start/end data are independent.
int GetResourceRegion(int entity)
{
	float point[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", point);
	return GetRegionAtPoint(point);
}

int GetRegionAtPoint(const float point[3])
{
	SafeDetectResult start = SAFEDETECT_QueryPoint(point, SafeDetect_Start, SafeDetect_MapInfoFirst);
	if (start == SafeDetect_Inside) return 0;
	SafeDetectResult end = SAFEDETECT_QueryPoint(point, SafeDetect_End, SafeDetect_MapInfoFirst);
	if (end == SafeDetect_Inside) return 1;
	return start == SafeDetect_Outside && end == SafeDetect_Outside ? 2 : -1;
}

bool GetResourceRule(int entity, const char[] name, char[] target, int maxlen)
{
	return GetRuleInRegion(GetResourceRegion(entity), name, target, maxlen);
}

bool GetRuleInRegion(int region, const char[] name, char[] target, int maxlen)
{
	if (region >= 0 && g_regionRules[region].GetString(name, target, maxlen)) return true;
	return g_rules.GetString(name, target, maxlen);
}
