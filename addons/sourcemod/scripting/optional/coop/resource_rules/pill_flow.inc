// Adapted from Confogl ItemTracking pill-flow selection; keeps its ordering and debug colors.
#define PF_KEEP        0
#define PF_CULL_WINDOW 1
#define PF_CULL_SEP    2
#define PF_CULL_LIMIT  3
#define PF_NO_FLOW     -1   // no nav/flow data: always kept, excluded from spacing

static int PF_GLOW_KEEP[3] = {255, 255, 255};   // white
static int PF_GLOW_CULL[4][3] = {
    {0, 0, 0},          // PF_KEEP (unused)
    {255, 0, 0},        // PF_CULL_WINDOW: red
    {255, 165, 0},      // PF_CULL_SEP: orange
    {0, 255, 255}       // PF_CULL_LIMIT: cyan
};

// Returns true when the filter is active (= it owns the pills limit this round).
bool ApplyPillFlowFilter(ArrayList hSpawns, int iLimit)
{
    float fFlowMin = (g_chapterFlow[0] >= 0.0 ? g_chapterFlow[0] : g_flowMin.FloatValue);
    float fFlowMax = (g_chapterFlow[1] >= 0.0 ? g_chapterFlow[1] : g_flowMax.FloatValue);
    float fSep = (g_chapterFlow[2] >= 0.0 ? g_chapterFlow[2] : g_flowSeparation.FloatValue);

    if (fFlowMin <= 0.0 && fFlowMax >= 1.0 && fSep <= 0.0) {
        return false;
    }

    if (fFlowMax < fFlowMin) {
        LogError("[%s] pillflow_max (%.2f) < pillflow_min (%.2f); pill flow filter disabled.", "ResourceRules", fFlowMax, fFlowMin);
        return false;
    }

    if (!g_flowFinale.BoolValue && L4D_IsMissionFinalMap()) {
        if ((g_flowVisualize.IntValue > 0)) {
            LogMessage("[%s] Finale map, pill flow filter skipped.", "ResourceRules");
        }
        return false;
    }

    float fMaxFlowDist = L4D2Direct_GetMapMaxFlowDistance();
    if (fMaxFlowDist <= 0.0) {
        return false;
    }

    int iCount = hSpawns.Length;
    if (!iCount) {
        return true;
    }

    int iVisualize = g_flowVisualize.IntValue;
    bool bVisualize = (iVisualize == 1);   // mode 1 glows instead of removing; mode 2 removes and glows survivors
    int entity;
    float fOrigins[3];

    // Resolve each stored pill spawn to a flow fraction and apply the window.
    float[] fPct = new float[iCount];
    int[] iReason = new int[iCount];

    for (int i = 0; i < iCount; i++) {
        entity = EntRefToEntIndex(hSpawns.Get(i));
        GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", fOrigins);

        Address pNav = L4D_GetNearestNavArea(fOrigins, 120.0, true, false, false, 2);
        if (pNav == Address_Null) {
            pNav = L4D2Direct_GetTerrorNavArea(fOrigins);
        }

        float fFlow = (pNav != Address_Null) ? L4D2Direct_GetTerrorNavAreaFlow(pNav) : -1.0;
        if (fFlow < 0.0) {
            fPct[i] = -1.0;
            iReason[i] = PF_NO_FLOW;
            continue;
        }

        fPct[i] = fFlow / fMaxFlowDist;
        if (fPct[i] > 1.0) {
            fPct[i] = 1.0;
        }

        if (fPct[i] < fFlowMin || fPct[i] > fFlowMax) {
            iReason[i] = PF_CULL_WINDOW;
        }
    }

    // Index order sorted by ascending flow (spacing passes walk the map start->end).
    int[] iOrder = new int[iCount];
    for (int i = 0; i < iCount; i++) {
        iOrder[i] = i;
    }
    for (int i = 1; i < iCount; i++) {
        int tmp = iOrder[i];
        int j = i - 1;
        while (j >= 0 && fPct[iOrder[j]] > fPct[tmp]) {
            iOrder[j + 1] = iOrder[j];
            j--;
        }
        iOrder[j + 1] = tmp;
    }

    // Minimum flow separation; of a too-close cluster the earliest spawn wins.
    if (fSep > 0.0) {
        float fLastKept = -1.0;
        for (int k = 0; k < iCount; k++) {
            int i = iOrder[k];
            if (iReason[i] != PF_KEEP) {
                continue;
            }
            if (fLastKept >= 0.0 && fPct[i] - fLastKept < fSep) {
                iReason[i] = PF_CULL_SEP;
            } else {
                fLastKept = fPct[i];
            }
        }
    }

    /*
        Enforce the pills limit here, evenly spaced by flow.
        Spawns without flow data can't be spaced, so they occupy limit slots off the top.
    */
    if (iLimit >= 0) {
        int iKept = 0, iNoFlow = 0;
        for (int i = 0; i < iCount; i++) {
            if (iReason[i] == PF_KEEP) {
                iKept++;
            } else if (iReason[i] == PF_NO_FLOW) {
                iNoFlow++;
            }
        }

        int iSlots = iLimit - iNoFlow;
        if (iSlots < 0) {
            /*
                More flowless spawns than the limit alone allows: remove the extra.
                No flow data means there is nothing to space them by, so array order decides
            */
            int iExcess = -iSlots;
            for (int i = iCount - 1; i >= 0 && iExcess > 0; i--) {
                if (iReason[i] == PF_NO_FLOW) {
                    iReason[i] = PF_CULL_LIMIT;
                    iExcess--;
                }
            }
            iSlots = 0;
        }

        if (iSlots < iKept) {
            bool[] bSelected = new bool[iCount];
            for (int slot = 0; slot < iSlots; slot++) {
                // Ideal flow for this slot
                float fWant = fFlowMin + (fFlowMax - fFlowMin) * (float(slot) + 0.5) / float(iSlots);

                int best = -1;
                float fBestDist = 0.0;
                for (int i = 0; i < iCount; i++) {
                    if (iReason[i] != PF_KEEP || bSelected[i]) {
                        continue;
                    }
                    float d = fPct[i] - fWant;
                    if (d < 0.0) {
                        d = -d;
                    }
                    if (best == -1 || d < fBestDist) {
                        best = i;
                        fBestDist = d;
                    }
                }
                if (best != -1) {
                    bSelected[best] = true;
                }
            }

            for (int i = 0; i < iCount; i++) {
                if (iReason[i] == PF_KEEP && !bSelected[i]) {
                    iReason[i] = PF_CULL_LIMIT;
                }
            }
        }
    }

    // Apply: kill+erase culled spawns (descending so indices stay valid), or
    // just glow everything in visualize mode.
    int iRemoved[4] = {0, ...};   // indexed by PF_CULL_* reason

    for (int i = iCount - 1; i >= 0; i--) {
        entity = EntRefToEntIndex(hSpawns.Get(i));

        if (iReason[i] <= PF_KEEP) {
            if ((g_flowVisualize.IntValue > 0)) {
                LogMessage("[%s] Pill spawn %d flow=%.1f%% KEPT%s", "ResourceRules", entity,
                    fPct[i] * 100.0, iReason[i] == PF_NO_FLOW ? " (no flow data)" : "");
            }
            if (iVisualize > 0) {
                L4D2_SetEntityGlow(entity, L4D2Glow_Constant, 0, 0, PF_GLOW_KEEP, false);
            }
            continue;
        }

        if ((g_flowVisualize.IntValue > 0)) {
            static const char sReasons[4][] = {"", "outside window", "separation", "limit spacing"};
            LogMessage("[%s] Pill spawn %d flow=%.1f%% %s (%s)", "ResourceRules", entity,
                fPct[i] * 100.0, bVisualize ? "WOULD REMOVE" : "REMOVED", sReasons[iReason[i]]);
        }
        iRemoved[iReason[i]]++;

        if (bVisualize) {
            L4D2_SetEntityGlow(entity, L4D2Glow_Constant, 0, 0, PF_GLOW_CULL[iReason[i]], false);
        } else {
            if (IsValidEdict(entity)) {
                RemoveEntity(entity);
            }
            hSpawns.Erase(i);
        }
    }

    if ((g_flowVisualize.IntValue > 0)) {
        LogMessage("[%s] Pill flow window %.0f%%-%.0f%% sep %.1f%%: %d kept, %d %s (window), %d (separation), %d (limit spacing).%s",
            "ResourceRules", fFlowMin * 100.0, fFlowMax * 100.0, fSep * 100.0,
            iCount - iRemoved[PF_CULL_WINDOW] - iRemoved[PF_CULL_SEP] - iRemoved[PF_CULL_LIMIT],
            iRemoved[PF_CULL_WINDOW], bVisualize ? "flagged" : "removed",
            iRemoved[PF_CULL_SEP], iRemoved[PF_CULL_LIMIT],
            bVisualize ? " (visualize: nothing deleted; white = kept, red = window, orange = separation, cyan = limit)" : "");
    }

    return true;
}
