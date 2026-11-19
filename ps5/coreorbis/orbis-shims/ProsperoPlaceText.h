// NES FCEUmm PS5 1.2 (FBNeo PS5 2.2, Snes9x PS5 2.10): why an update can't go where the console runs the app (ProsperoAppPlace.cpp, in the payloads), as
// format strings with one %s (the folder). The helper sends the reason in English; the app's Settings, Updates row
// recognises these and shows them translated (fe_menu.cpp, fe_i18n.cpp), wrapped to two lines.
// SPDX-License-Identifier: MIT
#pragma once

namespace placetext
{
constexpr const char* kImage =
	"NES FCEUmm PS5 runs from an image ShadowMount+ mounted (%s): an update can't be written into it. Update the image with "
	"the new version's folder.";
constexpr const char* kReadOnly =
	"NES FCEUmm PS5 runs from %s, which is read-only: an update can't be written there. Update that folder by hand.";
constexpr const char* kNoWrite =
	"NES FCEUmm PS5 runs from %s, where no file can be written: the update can't be installed. Update that folder by hand.";
constexpr const char* kGone =
	"ShadowMount+ runs NES FCEUmm PS5 from %s, which isn't there now (a drive not connected?). Nothing was written: try "
	"again once it is.";
constexpr const char* const kAll[] = {kImage, kReadOnly, kNoWrite, kGone};
} // namespace placetext
