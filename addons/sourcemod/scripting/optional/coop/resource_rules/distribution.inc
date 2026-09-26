// Generalized from Confogl ItemTracking's pill-flow selector. Preserve the
// window -> spacing -> evenly distributed limit order and flowless accounting.
#define PF_KEEP        0
#define PF_CULL_WINDOW 1
#define PF_CULL_SEP    2
#define PF_CULL_LIMIT  3
#define PF_NO_FLOW    -1

bool ApplyDistribution(ArrayList hSpawns, ResourcePolicy policy, int[] reasons)
{
    float fFlowMin = policy.flowMin, fFlowMax = policy.flowMax, fSep = policy.spacing;
    int iLimit = policy.limit;
    if (fFlowMin <= 0.0 && fFlowMax >= 1.0 && fSep <= 0.0) return false;
    if (fFlowMax < fFlowMin) {
        LogError("[ResourceRules] %s: flow_max < flow_min; using count limit only", policy.name);
        return false;
    }
    if (!policy.finale && L4D_IsMissionFinalMap()) return false;
    float fMaxFlowDist = L4D2Direct_GetMapMaxFlowDistance();
    if (fMaxFlowDist <= 0.0) return false;

    int iCount = hSpawns.Length;
    if (!iCount) {
        return true;
    }

    int entity;
    float fOrigins[3];

    // Resolve each stored resource point to a flow fraction and apply the window.
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
        Enforce the resource limit here, evenly spaced by flow.
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

    // A virtual removal excludes this point from all later groups, including
    // preview mode. Physical removal/glow happens once after the final rule.
    for (int i = iCount - 1; i >= 0; i--) {
        if (iReason[i] <= PF_KEEP) continue;
        entity = EntRefToEntIndex(hSpawns.Get(i));
        if (entity != INVALID_ENT_REFERENCE)
            MarkResourceCull(entity, iReason[i], policy.name, reasons);
        hSpawns.Erase(i);
    }
    return true;
}
