#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <HanWeaponSystem>

native bool QuickMelee_IsCombat(int client);

#define EF_NODRAW 32
public Plugin myinfo =
{
    name = "Han VM Cross Fix", 
    author = "H-AN",
    version = "1.1.2",
    description = "HanWeaponSystem 通用切换动画修复，兼容可选的快速近战插件"
};
ConVar g_Enable, g_DrawTicks, g_KnifeTicks, g_Log;
ConVar g_Hide;
bool g_HideOwned[MAXPLAYERS+1];
int g_HideUser[MAXPLAYERS+1];
float g_HideDeadline[MAXPLAYERS+1];
int g_LastMode[MAXPLAYERS+1], g_LastVM[MAXPLAYERS+1];
int g_LastWeapon[MAXPLAYERS+1];
int g_AttackWeapon[MAXPLAYERS+1], g_AttackTick[MAXPLAYERS+1];
bool g_Wait[MAXPLAYERS+1], g_Hold[MAXPLAYERS+1], g_Quick[MAXPLAYERS+1];
int g_Weapon[MAXPLAYERS+1], g_VM[MAXPLAYERS+1], g_Source[MAXPLAYERS+1];
int g_Mode[MAXPLAYERS+1], g_Seq[MAXPLAYERS+1], g_Parity[MAXPLAYERS+1];
int g_Start[MAXPLAYERS+1], g_CrossTick[MAXPLAYERS+1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("QuickMelee_IsCombat");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_Enable = CreateConVar("han_crossfix_enable", "1", "是否开启武器切换动画修复（含可选快速近战兼容）", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_DrawTicks = CreateConVar("han_crossfix_draw_ticks", "2", "武器切换动画修复持续的 tick 数", 0, true, 1.0, true, 8.0);
    g_KnifeTicks = CreateConVar("han_crossfix_melee_ticks", "3", "快速近战动画修复持续的 tick 数（安装 QuickMelee 时生效）", 0, true, 1.0, true, 8.0);
    g_Log = CreateConVar("han_crossfix_log", "0", "是否输出动画修复诊断日志", 0, true, 0.0, true, 1.0);
    g_Hide = CreateConVar("han_crossfix_hide", "1", "动画修复期间隐藏第一人称模型，避免临时修复序列闪现", 0, true, 0.0, true, 1.0);
    g_Hide.AddChangeHook(HideChanged);
    g_Enable.AddChangeHook(EnableChanged);
    HookEvent("player_death", ResetEvent);
    HookEvent("player_spawn", ResetEvent);
    HookEvent("round_start", RoundStart, EventHookMode_PostNoCopy);
    for (int c = 1; c <= MaxClients; c++) Reset(c);
}

bool Alive(int c) { return c > 0 && c <= MaxClients && IsClientInGame(c) && IsPlayerAlive(c); }

void ShowAgain(int c)
{
    if (!g_HideOwned[c]) return;
    g_HideOwned[c] = false;
    if (IsClientInGame(c) && GetClientUserId(c) == g_HideUser[c]
        && HasEntProp(c, Prop_Send, "m_bDrawViewmodel"))
        SetEntProp(c, Prop_Send, "m_bDrawViewmodel", 1);
}

void HideIntermediate(int c)
{
    if (!g_Hide.BoolValue) { ShowAgain(c); return; }
    if (!HasEntProp(c, Prop_Send, "m_bDrawViewmodel")) return;
    // 不要获取已被其他系统隐藏的视图模型（viewmodel）。
    if (!g_HideOwned[c])
    {
        if (!GetEntProp(c, Prop_Send, "m_bDrawViewmodel")) return;
        g_HideOwned[c] = true;
        g_HideUser[c] = GetClientUserId(c);
    }
    SetEntProp(c, Prop_Send, "m_bDrawViewmodel", 0);
    // 若指令处理在正常释放前停止，则进入故障安全状态。
    g_HideDeadline[c] = GetGameTime() + 0.5;
}

public void HideChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (!convar.BoolValue)
        for (int c = 1; c <= MaxClients; c++) ShowAgain(c);
}
public void EnableChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (!convar.BoolValue)
        for (int c = 1; c <= MaxClients; c++) Stop(c, true);
}
public void OnGameFrame()
{
    for (int c = 1; c <= MaxClients; c++)
        if (g_HideOwned[c] && (!Alive(c) || GetGameTime() >= g_HideDeadline[c]))
            Stop(c, true);
}
bool Quick(int c)
{
    return GetFeatureStatus(FeatureType_Native, "QuickMelee_IsCombat") == FeatureStatus_Available && QuickMelee_IsCombat(c);
}

// 武器系统是必需依赖；每回合仅在 QuickMelee API 和 CVar 存在时统一设置。
public void RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (GetFeatureStatus(FeatureType_Native, "QuickMelee_IsCombat") != FeatureStatus_Available)
        return;
    ConVar fixMode = FindConVar("sm_quickmelee_fix_viewmodel");
    if (fixMode == null || fixMode.IntValue == 1)
        return;
    fixMode.IntValue = 1;
    if (g_Log.BoolValue)
        LogMessage("[CrossFix] round_start: sm_quickmelee_fix_viewmodel set to 1");
}
bool Busy(int c)
{
    return Han_IsClientCustomAnim(c) || Han_IsClientInspecting(c) || Han_IsClientZooming(c)
        || Han_IsClientSideAiming(c) || Han_IsClientRunning(c);
}

// 仅识别配置登记的新武器；原始 classname 相同的原版武器不属于此例外。
// 1=M3/XM1014 模板，2=已装消音器的 USP 模板，0=其他。
int SpecialSwitchKind(int weapon)
{
    if (weapon <= MaxClients || !IsValidEntity(weapon)) return 0;
    char base[64], classname[64];
    if (!Han_IsManagedWeapon(weapon) || !Han_GetWeaponBaseClass(weapon, base, sizeof(base))) return 0;
    GetEntityClassname(weapon, classname, sizeof(classname));
    if (StrEqual(classname, base, false)) return 0;
    if (StrEqual(base, "weapon_m3", false) || StrEqual(base, "weapon_xm1014", false)) return 1;
    if (StrEqual(base, "weapon_usp", false) && HasEntProp(weapon, Prop_Send, "m_bSilencerOn")
        && GetEntProp(weapon, Prop_Send, "m_bSilencerOn") != 0) return 2;
    return 0;
}

bool SpecialSwitchPair(int previous, int current)
{
    int from = SpecialSwitchKind(previous);
    if (from == 0) return false;
    int to = SpecialSwitchKind(current);
    return (from == 1 && to == 2) || (from == 2 && to == 1);
}

bool Valid(int c)
{
    if (!Alive(c)) return false;
    int w = EntRefToEntIndex(g_Weapon[c]), vm = EntRefToEntIndex(g_VM[c]);
    int source = EntRefToEntIndex(g_Source[c]);
    return w > MaxClients && IsValidEntity(w) && vm > MaxClients && IsValidEntity(vm)
        && source > MaxClients && IsValidEntity(source)
        && GetEntPropEnt(c, Prop_Send, "m_hActiveWeapon") == w
        && GetEntPropEnt(vm, Prop_Send, "m_hOwner") == c
        && GetEntPropEnt(source, Prop_Send, "m_hOwner") == c
        && GetClientViewModel(c, g_Mode[c]) == vm && GetClientViewModel(c, 0) == source;
}
void Stop(int c, bool restore)
{
    if (restore && g_Hold[c] && Valid(c))
    {
        int vm = EntRefToEntIndex(g_VM[c]), source = EntRefToEntIndex(g_Source[c]);
        int separator = g_Seq[c] == 0 ? 1 : 0;
        if (GetEntProp(vm, Prop_Send, "m_nSequence") == separator
            && GetEntProp(source, Prop_Send, "m_nAnimationParity") == g_Parity[c])
        {
            int seq = g_Mode[c] == 0 ? g_Seq[c] : GetEntProp(source, Prop_Send, "m_nSequence");
            SetEntProp(vm, Prop_Send, "m_nSequence", seq);
        }
    }
    g_Hold[c] = false;
    g_Wait[c] = false;
    ShowAgain(c);
}
void Reset(int c)
{
    Stop(c, true);
    g_LastMode[c] = -1;
    g_LastVM[c] = INVALID_ENT_REFERENCE;
    g_LastWeapon[c] = INVALID_ENT_REFERENCE;
    g_AttackWeapon[c] = INVALID_ENT_REFERENCE;
    g_AttackTick[c] = -1;
}
public void OnClientPutInServer(int c) { Reset(c); }
public void OnClientDisconnect(int c) { Reset(c); }
public void OnMapEnd() { for (int c = 1; c <= MaxClients; c++) Reset(c); }
public void OnPluginEnd() { for (int c = 1; c <= MaxClients; c++) Reset(c); }
public void ResetEvent(Event event, const char[] name, bool dontBroadcast)
{
    int c = GetClientOfUserId(event.GetInt("userid"));
    if (c > 0) Reset(c);
}
public void Han_OnKnifeAttack(int c, int weapon, int attackId, HanKnifeAttackType type)
{
    if (!Alive(c) || !Quick(c)) return;
    // 记录真实刀攻击；最终攻击序列仍留到 RunCmdPost 捕获。
    g_AttackWeapon[c] = EntIndexToEntRef(weapon);
    g_AttackTick[c] = GetGameTickCount();
}

public void OnPlayerRunCmdPost(int c, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (!Alive(c)) { Reset(c); return; }
    // 必须先于模式校验和 EF_NODRAW 中断判断，快速近战可能尚未被主体确认切枪。
    int mode = view_as<int>(Han_GetClientViewModelMode(c));
    if (mode < 0 || mode > 1) { Stop(c, true); return; }
    int vm = GetClientViewModel(c, mode), source = GetClientViewModel(c, 0);
    int active = GetEntPropEnt(c, Prop_Send, "m_hActiveWeapon");
    if (vm <= MaxClients || source <= MaxClients || active <= MaxClients
        || !IsValidEntity(vm) || !IsValidEntity(source) || !IsValidEntity(active)) { Reset(c); return; }
    bool cross = g_LastMode[c] >= 0 && g_LastMode[c] != mode
        && EntRefToEntIndex(g_LastVM[c]) == GetClientViewModel(c, g_LastMode[c]);
    // VM1 -> VM1 只开放这两个双向组合，复用跨 VM 的隐藏和序列恢复流程。
    bool special = false;
    if (g_LastMode[c] == 1 && mode == 1 && EntRefToEntIndex(g_LastVM[c]) == vm
        && g_LastWeapon[c] != EntIndexToEntRef(active))
        special = SpecialSwitchPair(EntRefToEntIndex(g_LastWeapon[c]), active);
    g_LastMode[c] = mode;
    g_LastVM[c] = EntIndexToEntRef(vm);
    g_LastWeapon[c] = EntIndexToEntRef(active);
    if (!g_Enable.BoolValue) { Stop(c, true); return; }
    if (cross || special)
    {
        Stop(c, true);
        g_Wait[c] = true;
        g_Mode[c] = mode;
        g_Weapon[c] = EntIndexToEntRef(active);
        g_VM[c] = EntIndexToEntRef(vm);
        g_Source[c] = EntIndexToEntRef(source);
        g_CrossTick[c] = GetGameTickCount();
        g_Quick[c] = !special && Quick(c);
        if (g_Log.BoolValue)
            LogMessage("[CrossFix] cross client=%d tick=%d ->VM%d weapon=%d quick=%d special=%d", c, GetGameTickCount(), mode, active, g_Quick[c], special);
    }
    if (!g_Wait[c] && !g_Hold[c]) return;
    if (!Valid(c) || mode != g_Mode[c]) { Stop(c, true); return; }
    if (Busy(c) || (GetEntProp(vm, Prop_Send, "m_fEffects") & EF_NODRAW)) { Stop(c, false); return; }
    int seq = GetEntProp(source, Prop_Send, "m_nSequence");
    int parity = GetEntProp(source, Prop_Send, "m_nAnimationParity");
    int display = GetEntProp(vm, Prop_Send, "m_nSequence");
    if (g_Wait[c])
    {
        if (GetGameTickCount() - g_CrossTick[c] > 16) { Stop(c, false); return; }
        if (g_Quick[c] && (!Quick(c) || GetGameTickCount() - g_CrossTick[c] > 16))
        {
            if (g_Log.BoolValue) LogMessage("[CrossFix] cancelled waiting for knife attack client=%d", c);
            Stop(c, false); return;
        }
        if (g_Quick[c] && (g_AttackWeapon[c] != g_Weapon[c] || g_AttackTick[c] < g_CrossTick[c])) return;
        if (GetEntPropEnt(source, Prop_Send, "m_hWeapon") != active) return;
        // 此时，VM1 可能包含旧的内置单 Tick 分隔符。
        int separator = seq == 0 ? 1 : 0;
        if (mode == 1 && display != seq && display != separator) { Stop(c, false); return; }
        g_Seq[c] = seq;
        g_Parity[c] = parity;
        g_Start[c] = GetGameTickCount();
        g_Wait[c] = false;
        g_Hold[c] = true;
        if (g_Log.BoolValue)
            LogMessage("[CrossFix] capture client=%d tick=%d VM%d seq=%d parity=%d quick=%d", c, GetGameTickCount(), mode, seq, parity, g_Quick[c]);
    }
    int separator = g_Seq[c] == 0 ? 1 : 0;
    // VM0 也是动画源：其中间序列即为我们的序列。
    bool sourceChanged = seq != g_Seq[c] && !(mode == 0 && seq == separator);
    if (parity != g_Parity[c] || sourceChanged || (display != g_Seq[c] && display != separator))
    {
        if (g_Log.BoolValue) LogMessage("[CrossFix] superseded client=%d tick=%d seq=%d parity=%d", c, GetGameTickCount(), seq, parity);
        Stop(c, false); return;
    }
    int ticks = g_Quick[c] ? g_KnifeTicks.IntValue : g_DrawTicks.IntValue;
    int elapsed = GetGameTickCount() - g_Start[c];
    if (elapsed >= ticks)
    {
        SetEntProp(vm, Prop_Send, "m_nSequence", g_Seq[c]);
        SetEntPropFloat(vm, Prop_Data, "m_flCycle", 0.0);
        g_Hold[c] = false;
        ShowAgain(c);
        if (g_Log.BoolValue) LogMessage("[CrossFix] restore client=%d tick=%d VM%d seq=%d held=%d", c, GetGameTickCount(), mode, g_Seq[c], elapsed);
    }
    else
    {
        SetEntProp(vm, Prop_Send, "m_nSequence", separator);
        HideIntermediate(c);
    }
}
