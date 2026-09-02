#if defined _Forgetest_gamedatawrapper_included_
	#endinput
#endif
#define _Forgetest_gamedatawrapper_included_

#include <sourcemod>

methodmap GameDataWrapper < GameData {
	public GameDataWrapper(const char[] file) {
		GameData gd = new GameData(file);
		if (!gd) SetFailState("Missing gamedata \"%s\"", file);
		return view_as<GameDataWrapper>(gd);
	}

	property GameData Super {
		public get() { return view_as<GameData>(this); }
	}

	public int GetOffset(const char[] key) {
		int offset = this.Super.GetOffset(key);
		if (offset == -1) SetFailState("Missing offset \"%s\"", key);
		return offset;
	}

	public Address GetAddress(const char[] key) {
		Address ptr = this.Super.GetAddress(key);
		if (ptr == Address_Null) SetFailState("Missing address \"%s\"", key);
		return ptr;
	}

	public Address GetMemSig(const char[] key) {
		Address ptr = this.Super.GetMemSig(key);
		if (ptr == Address_Null) SetFailState("Missing signature \"%s\"", key);
		return ptr;
	}

#if defined __sourcescramble_ext_included
	public MemoryPatch CreatePatchOrFail(const char[] name, bool enable = false) {
		MemoryPatch patch = MemoryPatch.CreateFromConf(this, name);
		if (!(enable ? patch.Enable() : patch.Validate()))
			SetFailState("Failed to patch \"%s\"", name);
		return patch;
	}
#endif
}
