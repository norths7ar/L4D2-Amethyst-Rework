// Ready audio from Competitive Rework readyup/sound.inc (CanadaRox, Target).
// Keep the manual-ready sounds; automatic start and cosmetic effects are separate.
#define DEFAULT_NOTIFY_SOUND "buttons/button14.wav"
#define DEFAULT_COUNTDOWN_SOUND "weapons/hegrenade/beep.wav"
#define DEFAULT_LIVE_SOUND "ui/survival_medal.wav"

static char s_notifySound[PLATFORM_MAX_PATH], s_countdownSound[PLATFORM_MAX_PATH], s_liveSound[PLATFORM_MAX_PATH];

void PrecacheSounds()
{
	char szPath[PLATFORM_MAX_PATH];

	l4d_ready_notify_sound.GetString(s_notifySound, sizeof(s_notifySound));
	l4d_ready_countdown_sound.GetString(s_countdownSound, sizeof(s_countdownSound));
	l4d_ready_live_sound.GetString(s_liveSound, sizeof(s_liveSound));

	FormatEx(szPath, sizeof(szPath), "sound/%s", s_notifySound);
	if (!FileExists(szPath, true)) {
		strcopy(s_notifySound, sizeof(s_notifySound), DEFAULT_NOTIFY_SOUND);
	}

	FormatEx(szPath, sizeof(szPath), "sound/%s", s_countdownSound);
	if (!FileExists(szPath, true)) {
		strcopy(s_countdownSound, sizeof(s_countdownSound), DEFAULT_COUNTDOWN_SOUND);
	}

	FormatEx(szPath, sizeof(szPath), "sound/%s", s_liveSound);
	if (!FileExists(szPath, true)) {
		strcopy(s_liveSound, sizeof(s_liveSound), DEFAULT_LIVE_SOUND);
	}

	PrecacheSound(s_notifySound);
	PrecacheSound(s_countdownSound);
	PrecacheSound(s_liveSound);

}

void PlayLiveSound()
{
	if (l4d_ready_enable_sound.BoolValue) EmitSoundToAll(s_liveSound, .volume = 0.5);
}

void PlayCountdownSound()
{
	if (l4d_ready_enable_sound.BoolValue)
	{
		EmitSoundToAll(s_countdownSound, .volume = 0.5);
	}
}

void PlayNotifySound(int client)
{
	if (l4d_ready_enable_sound.BoolValue)
	{
		EmitSoundToClient(client, s_notifySound);
	}
}
