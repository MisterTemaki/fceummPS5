// NES FCEUmm PS5: the payloads (NESFCEUmmPS5.elf and NESFCEUmmPS5-helper.elf).
//
// NESFCEUmmPS5.elf, sent with the PS5 Payload Manager / the ELF loader (port 9021), is what PS5SX2's installer and
// helper are together:
//   1. it installs or updates the dashboard app in /data/homebrew/PPSA99013 (eboot.bin = FCEUmm itself,
//      sce_module/libc.prx, sce_sys/param.json, icon0.png, pic0.dds, pic1.dds), built into it (install_data.cpp);
//   2. then it stays running as the helper that lets the app out of its sandbox (ProsperoJailbreak.h), until
//      the console is turned off. A second copy sent while one runs only installs.
// NESFCEUmmPS5-helper.elf (FCEUMM_HELPER_ONLY) is step 2 alone: the app carries it and sends it to the ELF
// loader itself when no helper answers (after a reboot, for instance).
//
// Nothing here writes outside /data/fceumm, the app's folder and /user/appmeta/<TITLE_ID>. 1.2 (Snes9x PS5 2.10's fix,
// as FBNeo PS5 2.2 has it): the app's folder is the one the console runs it from (ShadowMount+ may mount it from a USB
// drive, an extended drive or another folder: ProsperoAppPlace.h), written through its mount
// /system_ex/app/<TITLE_ID>; /data/homebrew/<TITLE_ID> when nothing runs it yet, or when the place can't be told for
// sure (never worse than 1.1).
//
// SPDX-License-Identifier: MIT

#include "OrbisPaths.h"
#include "ProsperoJailbreak.h"
#include "ProsperoNotify.h"
#ifndef FCEUMM_HELPER_ONLY
#include "ProsperoAppPlace.h"
#include "ProsperoInstall.h"
#endif

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unistd.h>

#ifndef FCEUMM_PS5_VERSION
#define FCEUMM_PS5_VERSION "dev"
#endif

namespace
{
std::string g_ready_message;

#ifndef FCEUMM_HELPER_ONLY
// where the payload installs when nothing else runs the app
std::string DefaultAppDir()
{
	const char* env = getenv("FCEUMM_PS5_HOMEBREW");
	return std::string(env && *env ? env : "/data/homebrew") + "/" FCEUMM_TITLE_ID;
}
#endif

void OnReady()
{
	if (!g_ready_message.empty())
		ProsperoNotify("%s", g_ready_message.c_str());
	ProsperoNotifyFlush();
}
} // namespace

int main()
{
	setvbuf(stdout, nullptr, _IOLBF, 0);
	const bool have_data = OrbisPathsInit();
#ifdef FCEUMM_HELPER_ONLY
	OrbisLogOpen("helper");
	OrbisLog("[helper] NES FCEUmm PS5 helper %s (built %s %s), pid %d%s", FCEUMM_PS5_VERSION, __DATE__, __TIME__,
		int(getpid()), have_data ? "" : " (no /data: no log file)");
#else
	OrbisLogOpen("installer");
	OrbisLog("[installer] NES FCEUmm PS5 %s (built %s %s), pid %d", FCEUMM_PS5_VERSION, __DATE__, __TIME__, int(getpid()));
	if (!have_data)
		OrbisLog("[installer] can't create %s", OrbisRoot().c_str());

	const char* open_hint = "Open it from the NES FCEUmm PS5 icon on the home screen.";
	char msg[1024];
	const InstallResult installed = InstallApp();
	switch (installed)
	{
		case InstallResult::Installed:
			snprintf(msg, sizeof(msg), "NES FCEUmm PS5 %s installed. %s", FCEUMM_PS5_VERSION, open_hint);
			break;
		case InstallResult::Updated:
			if ((!AppInstallPlace().mount.empty() || AppInstallPlace().via_link) &&
				AppInstallPlace().source != DefaultAppDir())
				snprintf(msg, sizeof(msg), "NES FCEUmm PS5 updated to %s (in %s, the copy ShadowMount+ runs). %s",
					FCEUMM_PS5_VERSION, AppInstallPlace().source.c_str(), open_hint);
			else
				snprintf(msg, sizeof(msg), "NES FCEUmm PS5 updated to %s. %s", FCEUMM_PS5_VERSION, open_hint);
			break;
		case InstallResult::UpToDate:
			snprintf(msg, sizeof(msg), "NES FCEUmm PS5 %s is ready. %s", FCEUMM_PS5_VERSION, open_hint);
			break;
		case InstallResult::NewerInstalled:
			snprintf(msg, sizeof(msg),
				"NES FCEUmm PS5: a newer version is installed (updated from the app); this payload (%s) left it as it is. "
				"Put the newer payload in your autoload. %s",
				FCEUMM_PS5_VERSION, open_hint);
			break;
		case InstallResult::CantWrite:
			// 1.2: ShadowMount+ runs the app from an image or a read-only folder: not written, and no second copy made
			snprintf(msg, sizeof(msg), "%s (This payload is %s; the helper runs.)", AppInstallPlace().reason.c_str(),
				FCEUMM_PS5_VERSION);
			break;
		case InstallResult::Failed:
			snprintf(msg, sizeof(msg), "NES FCEUmm PS5: could not install the app in %s (see %s/logs/installer.log)",
				AppInstallDir().c_str(), OrbisRoot().c_str());
			break;
		default:
			snprintf(msg, sizeof(msg), "NES FCEUmm PS5: nothing to install");
			break;
	}
	if (installed != InstallResult::NewerInstalled && installed != InstallResult::CantWrite &&
		!AppInstallPlace().image_pending && SyncAppMeta() > 0)
	{
		const size_t len = strlen(msg);
		snprintf(msg + len, sizeof(msg) - len, " Home screen art updated (restart the PS5 if it doesn't show).");
	}
	OrbisLog("[installer] %s", msg);
	g_ready_message = msg;
#endif

	// the helper: runs until the console is turned off, or returns at once when one already runs
	if (!jailbreak::ServeHelper(OnReady))
	{
#ifndef FCEUMM_HELPER_ONLY
		ProsperoNotify("%s", g_ready_message.c_str());
#endif
		OrbisLog("[helper] another helper is running: leaving");
	}
	ProsperoNotifyFlush();
	OrbisLogClose();
	return 0;
}
