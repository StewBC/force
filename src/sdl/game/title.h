#ifndef FORCE_TITLE_H
#define FORCE_TITLE_H

#include "sdl/host.h"

#include <stdbool.h>
#include <stdint.h>

/* Draw the title and wait for a key. False when the window closes.
 * Comment out the call in main to boot straight into the mission. */
bool force_title_show(force_host *host, uint32_t *pixels);

#endif
