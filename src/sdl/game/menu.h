#ifndef FORCE_MENU_H
#define FORCE_MENU_H

#include "core/screen.h"
#include "core/types.h"
#include "generated/force_data.h"

/* Read build/c64/campaign.prg. A missing file starts a fresh campaign. */
void force_campaign_load(void);

/* Arm a save when the last commit asked for one. Does not draw. */
void force_menu_open(void);

/* One menu edge. Returns 1 when the selected mission should start. */
int force_menu_tick(const force_input *in);

void force_menu_paint(force_screen *screen, uint32_t *pixels);

const force_mission *force_menu_mission(void);

/* outcome is FORCE_SCRIPT_WIN / LOSE. snap_flag is 1 when snap_score is live. */
void force_menu_commit(uint8_t outcome, uint8_t snap_flag, uint8_t snap_score);

/* Campaign rules against the linked catalog. 1 = pass. Does not write the progress file. */
int force_menu_selftest(void);

#endif
