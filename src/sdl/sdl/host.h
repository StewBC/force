#ifndef FORCE_HOST_H
#define FORCE_HOST_H

#include "core/types.h"

typedef struct force_host force_host;

bool force_host_init(force_host **out);
void force_host_shutdown(force_host *host);

/* Returns false when the window should close. */
bool force_host_pump(force_host *host, force_input *in);
void force_host_present(force_host *host, const force_screen *screen);

#endif
