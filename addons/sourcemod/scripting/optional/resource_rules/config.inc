// Resource policy overlay: global defaults < maps/<map>.
enum struct ResourcePolicy
{
	char name[64];
	char members[2048]; // Canonical comma-delimited names; empty for an item.
	int limit;
	float flowMin;
	float flowMax;
	float density;
	float minDistance;
	bool finale;
	int regions;

	void Init(const char[] key)
	{
		strcopy(this.name, sizeof(this.name), key);
		this.members[0] = '\0';
		this.limit = -1;
		this.flowMin = 0.0;
		this.flowMax = 1.0;
		this.density = 0.0;
		this.minDistance = 0.0;
		this.finale = false;
		this.regions = (1 << 2) | (1 << 3); // along + unknown; saferooms exempt
	}
}

StringMap g_regionRules[4]; // start, end, along, finale replacement override
ArrayList g_itemPolicies, g_categoryPolicies;
StringMap g_resourceDecisions, g_distributionWarnings;
ConVar g_visualize;

void InitPolicy()
{
	for (int i = 0; i < 4; i++) g_regionRules[i] = new StringMap();
	g_itemPolicies = new ArrayList(sizeof(ResourcePolicy));
	g_categoryPolicies = new ArrayList(sizeof(ResourcePolicy));
	g_resourceDecisions = new StringMap();
	g_distributionWarnings = new StringMap();
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
	if (kv.GetDataType("flow_spacing") != KvData_None)
		SetFailState("flow_spacing is no longer supported; use flow_density and min_distance");
	policy.flowMin = ReadFraction(kv, "flow_min", policy.flowMin);
	policy.flowMax = ReadFraction(kv, "flow_max", policy.flowMax);
	policy.density = ReadNonNegative(kv, "flow_density", policy.density);
	policy.minDistance = ReadNonNegative(kv, "min_distance", policy.minDistance);
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

float ReadNonNegative(KeyValues kv, const char[] key, float fallback)
{
	char value[32];
	kv.GetString(key, value, sizeof(value), "");
	if (!value[0]) return fallback;
	TrimString(value);
	float number;
	if (StringToFloatEx(value, number) != strlen(value) || !(number >= 0.0 && number < 3.402823466e38))
		SetFailState("Invalid resource value %s: %s (expected finite non-negative number)", key, value);
	return number;
}

bool HasItemPolicy(const char[] name)
{
	ResourcePolicy policy;
	for (int index = 0; index < g_itemPolicies.Length; index++)
	{
		g_itemPolicies.GetArray(index, policy);
		if (StrEqual(name, policy.name)) return true;
	}
	return false;
}

void ValidateCategoryOwners()
{
	StringMap owners = new StringMap();
	ResourcePolicy policy;
	for (int index = 0; index < g_categoryPolicies.Length; index++)
	{
		g_categoryPolicies.GetArray(index, policy);
		char members[66][64];
		int count = ExplodeString(policy.members, ",", members, sizeof(members), sizeof(members[]));
		for (int member = 0; member < count; member++)
		{
			if (!members[member][0] || HasItemPolicy(members[member])) continue;
			char previous[64];
			if (owners.GetString(members[member], previous, sizeof(previous)) && !StrEqual(previous, policy.name))
				SetFailState("Resource %s belongs to both categories %s and %s", members[member], previous, policy.name);
			owners.SetString(members[member], policy.name);
		}
	}
	delete owners;
}

void ReadPolicyLayer(KeyValues kv)
{
	ReadRuleSection(kv, "rules", g_rules);
	g_meleePickups = kv.GetNum("melee_pickups", g_meleePickups);
	if (g_meleePickups < 1) SetFailState("melee_pickups must be positive");
	if (kv.JumpToKey("regions"))
	{
		static const char names[][] = {"start", "end", "along", "finale"};
		for (int i = 0; i < sizeof(names); i++) ReadRuleSection(kv, names[i], g_regionRules[i]);
		kv.GoBack();
	}
	if (kv.JumpToKey("ItemLimits"))
	{
		SetFailState("ItemLimits is no longer supported; use distribution/<resource>/limit");
		return;
	}
	if (kv.JumpToKey("distribution"))
	{
		if (kv.GotoFirstSubKey())
		{
			do {
				char name[64];
				kv.GetSectionName(name, sizeof(name));
				if (!IsResourceName(name)) SetFailState("Unsupported distribution resource: %s", name);
				static const char fields[][] = {"limit", "flow_min", "flow_max", "flow_density", "min_distance", "flow_finale", "regions"};
				bool configured;
				for (int field = 0; field < sizeof(fields); field++)
					if (kv.GetDataType(fields[field]) != KvData_None) configured = true;
				if (!configured) SetFailState("Empty distribution policy for %s; use limit -1 for an explicit unrestricted policy", name);
				int index = PolicyIndex(g_itemPolicies, name);
				ResourcePolicy policy;
				g_itemPolicies.GetArray(index, policy);
				policy.limit = ParseLimit(kv, "limit", policy.limit);
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

void LoadRules(const char[] incomingMap = "")
{
	g_rules.Clear();
	for (int i = 0; i < 4; i++) g_regionRules[i].Clear();
	g_itemPolicies.Clear();
	g_categoryPolicies.Clear();
	g_meleePickups = 1;

	char file[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH], map[128];
	g_rulesFile.GetString(file, sizeof(file));
	g_policyFile = file[0] != '\0';
	if (!g_policyFile) return;
	BuildPath(Path_SM, path, sizeof(path), "configs/%s", file);
	KeyValues rules = new KeyValues("ResourceRules");
	if (!rules.ImportFromFile(path)) SetFailState("Cannot read resource policy %s", path);
	if (!rules.JumpToKey("global")) SetFailState("Resource policy %s needs a global section", path);
	ReadPolicyLayer(rules);
	rules.GoBack();
	if (incomingMap[0]) strcopy(map, sizeof(map), incomingMap);
	else GetCurrentMap(map, sizeof(map));
	if (rules.JumpToKey("maps") && rules.JumpToKey(map)) ReadPolicyLayer(rules);
	delete rules;
	ResourcePolicy policy;
	for (int i = 0; i < g_itemPolicies.Length; i++)
	{
		g_itemPolicies.GetArray(i, policy);
		if (policy.flowMax < policy.flowMin) SetFailState("Resource %s: flow_max must be >= flow_min", policy.name);
	}
	for (int i = 0; i < g_categoryPolicies.Length; i++)
	{
		g_categoryPolicies.GetArray(i, policy);
		if (policy.flowMax < policy.flowMin) SetFailState("Category %s: flow_max must be >= flow_min", policy.name);
	}
	ValidateCategoryOwners();
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
	// Finale supplies share the established end area, not the whole finale map.
	if (region == 1 && L4D_IsMissionFinalMap() && g_regionRules[3].GetString(name, target, maxlen)) return true;
	if (region >= 0 && g_regionRules[region].GetString(name, target, maxlen)) return true;
	return g_rules.GetString(name, target, maxlen);
}
