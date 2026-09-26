// Policy overlay: plugin global < framework mapinfo < plugin maps/<map>.
enum struct ResourcePolicy
{
	char name[64];
	char members[2048]; // Canonical comma-delimited names; empty for an item.
	int limit;
	float flowMin;
	float flowMax;
	float spacing;
	bool finale;
	int regions;

	void Init(const char[] key)
	{
		strcopy(this.name, sizeof(this.name), key);
		this.members[0] = '\0';
		this.limit = -1;
		this.flowMin = 0.0;
		this.flowMax = 1.0;
		this.spacing = 0.0;
		this.finale = false;
		this.regions = (1 << 2) | (1 << 3); // along + unknown; saferooms exempt
	}
}

StringMap g_regionRules[3];
StringMap g_selections;
ArrayList g_itemPolicies, g_categoryPolicies;
ConVar g_visualize;

void InitPolicy()
{
	for (int i = 0; i < 3; i++) g_regionRules[i] = new StringMap();
	g_selections = new StringMap();
	g_itemPolicies = new ArrayList(sizeof(ResourcePolicy));
	g_categoryPolicies = new ArrayList(sizeof(ResourcePolicy));
	g_visualize = CreateConVar("resource_rules_visualize", "0",
		"Limit preview: 0 normal; 1 glow/log without culling; 2 cull and glow kept points. Replacement still applies.",
		_, true, 0.0, true, 2.0);
}

// Overlay only supplied entries; never clear a lower layer here.
void ReadRuleSection(KeyValues kv, const char[] section, StringMap target)
{
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

bool IsResourceName(const char[] name)
{
	return WeaponNameToId2(name) > WEPID_NONE || StrEqual(name, "ammo")
		|| StrEqual(name, "fireworkcrate") || StrEqual(name, "propanetank")
		|| StrEqual(name, "oxygentank") || StrEqual(name, "mounted_gun")
		|| StrEqual(name, "upgrade_item");
}

int PolicyIndex(ArrayList policies, const char[] name)
{
	ResourcePolicy policy;
	for (int i = 0; i < policies.Length; i++)
	{
		policies.GetArray(i, policy);
		if (StrEqual(policy.name, name)) return i;
	}
	policy.Init(name);
	return policies.PushArray(policy);
}

int ParseLimit(KeyValues kv, const char[] key, int fallback)
{
	char value[32];
	kv.GetString(key, value, sizeof(value), "");
	if (!value[0]) return fallback;
	TrimString(value);
	int number;
	if (StringToIntEx(value, number) != strlen(value) || number < -1)
		SetFailState("Invalid resource limit %s: %s (expected -1 or non-negative integer)", key, value);
	return number;
}

float ReadFraction(KeyValues kv, const char[] key, float fallback)
{
	char value[32];
	kv.GetString(key, value, sizeof(value), "");
	if (!value[0]) return fallback;
	TrimString(value);
	float number;
	if (StringToFloatEx(value, number) != strlen(value) || !(number >= 0.0 && number <= 1.0))
		SetFailState("Invalid resource fraction %s: %s (expected 0..1)", key, value);
	return number;
}

void ReadDistribution(KeyValues kv, ResourcePolicy policy)
{
	policy.flowMin = ReadFraction(kv, "flow_min", policy.flowMin);
	policy.flowMax = ReadFraction(kv, "flow_max", policy.flowMax);
	policy.spacing = ReadFraction(kv, "flow_spacing", policy.spacing);
	int finale = kv.GetNum("flow_finale", policy.finale ? 1 : 0);
	if (finale != 0 && finale != 1) SetFailState("flow_finale must be 0 or 1");
	policy.finale = finale != 0;

	char regions[128];
	kv.GetString("regions", regions, sizeof(regions), "");
	if (regions[0])
	{
		policy.regions = 0;
		char names[8][32];
		int count = ExplodeString(regions, ",", names, sizeof(names), sizeof(names[]));
		for (int i = 0; i < count; i++)
		{
			TrimString(names[i]);
			if (StrEqual(names[i], "start")) policy.regions |= 1 << 0;
			else if (StrEqual(names[i], "end")) policy.regions |= 1 << 1;
			else if (StrEqual(names[i], "along")) policy.regions |= 1 << 2;
			else if (StrEqual(names[i], "unknown")) policy.regions |= 1 << 3;
			else SetFailState("Unknown resource limit region: %s", names[i]);
		}
	}
}

void ReadItemLimits(KeyValues kv)
{
	if (!kv.GotoFirstSubKey(false)) return;
	do {
		char name[64];
		kv.GetSectionName(name, sizeof(name));
		if (!IsResourceName(name)) SetFailState("Unsupported ItemLimits resource: %s", name);
		int index = PolicyIndex(g_itemPolicies, name);
		ResourcePolicy policy;
		g_itemPolicies.GetArray(index, policy);
		policy.limit = ParseLimit(kv, NULL_STRING, policy.limit);
		g_itemPolicies.SetArray(index, policy);
	} while (kv.GotoNextKey(false));
	kv.GoBack();
}

void ReadPolicyLayer(KeyValues kv)
{
	ReadRuleSection(kv, "rules", g_rules);
	ReadRuleSection(kv, "weapon_selections", g_selections);
	g_meleePickups = kv.GetNum("melee_pickups", g_meleePickups);
	if (g_meleePickups < 1) SetFailState("melee_pickups must be positive");
	if (kv.JumpToKey("regions"))
	{
		static const char names[][] = {"start", "end", "along"};
		for (int i = 0; i < 3; i++) ReadRuleSection(kv, names[i], g_regionRules[i]);
		kv.GoBack();
	}
	if (kv.JumpToKey("ItemLimits"))
	{
		ReadItemLimits(kv);
		kv.GoBack();
	}
	if (kv.JumpToKey("distribution"))
	{
		if (kv.GotoFirstSubKey())
		{
			do {
				char name[64];
				kv.GetSectionName(name, sizeof(name));
				if (!IsResourceName(name)) SetFailState("Unsupported distribution resource: %s", name);
				int index = PolicyIndex(g_itemPolicies, name);
				ResourcePolicy policy;
				g_itemPolicies.GetArray(index, policy);
				ReadDistribution(kv, policy);
				g_itemPolicies.SetArray(index, policy);
			} while (kv.GotoNextKey());
			kv.GoBack();
		}
		kv.GoBack();
	}
	if (kv.JumpToKey("categories"))
	{
		if (kv.GotoFirstSubKey())
		{
			do {
				char name[64], members[2048];
				kv.GetSectionName(name, sizeof(name));
				int index = PolicyIndex(g_categoryPolicies, name);
				ResourcePolicy policy;
				g_categoryPolicies.GetArray(index, policy);
				// Presence matters: an explicit empty list disables an inherited group.
				if (kv.GetDataType("members") != KvData_None)
				{
					kv.GetString("members", members, sizeof(members));
					policy.members[0] = '\0';
					if (members[0])
					{
						char names[64][64];
						int count = ExplodeString(members, ",", names, sizeof(names), sizeof(names[]));
						StrCat(policy.members, sizeof(policy.members), ",");
						for (int i = 0; i < count; i++)
						{
							TrimString(names[i]);
							if (!IsResourceName(names[i])) SetFailState("Unsupported category member: %s", names[i]);
							StrCat(policy.members, sizeof(policy.members), names[i]);
							StrCat(policy.members, sizeof(policy.members), ",");
						}
					}
				}
				policy.limit = ParseLimit(kv, "limit", policy.limit);
				ReadDistribution(kv, policy);
				g_categoryPolicies.SetArray(index, policy);
			} while (kv.GotoNextKey());
			kv.GoBack();
		}
		kv.GoBack();
	}
}

void ReadMapInfoPolicy()
{
	if (!LGO_IsMapDataAvailable()) return;
	KeyValues limits = new KeyValues("ItemLimits");
	LGO_CopyMapSubsection(limits, "ItemLimits");
	ReadItemLimits(limits);
	delete limits;
	static const char keys[][] = {"pillflow_min", "pillflow_max", "pillflow_separation"};
	for (int i = 0; i < sizeof(keys); i++)
	{
		float value = LGO_GetMapValueFloat(keys[i], -1.0);
		if (value < 0.0) continue; // Framework's absent/disabled override sentinel.
		int index = PolicyIndex(g_itemPolicies, "pain_pills");
		ResourcePolicy policy;
		g_itemPolicies.GetArray(index, policy);
		if (i == 0) policy.flowMin = value;
		else if (i == 1) policy.flowMax = value;
		else policy.spacing = value;
		g_itemPolicies.SetArray(index, policy);
	}
}

void LoadRules(const char[] incomingMap = "", bool withMapInfo = false)
{
	g_rules.Clear();
	g_selections.Clear();
	for (int i = 0; i < 3; i++) g_regionRules[i].Clear();
	g_itemPolicies.Clear();
	g_categoryPolicies.Clear();
	g_meleePickups = 1;

	char file[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH], map[128];
	g_rulesFile.GetString(file, sizeof(file));
	BuildPath(Path_SM, path, sizeof(path), "configs/%s", file);
	KeyValues rules = new KeyValues("ResourceRules");
	if (!rules.ImportFromFile(path)) SetFailState("Cannot read resource policy %s", path);
	if (!rules.JumpToKey("global")) SetFailState("Resource policy %s needs a global section", path);
	ReadPolicyLayer(rules);
	rules.GoBack();
	// OnMapInit runs before Confogl selects the incoming map; do not import
	// the previous map's limits there. Generation only needs replacement rules.
	if (withMapInfo) ReadMapInfoPolicy();
	if (incomingMap[0]) strcopy(map, sizeof(map), incomingMap);
	else GetCurrentMap(map, sizeof(map));
	if (rules.JumpToKey("maps") && rules.JumpToKey(map)) ReadPolicyLayer(rules);
	delete rules;
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
