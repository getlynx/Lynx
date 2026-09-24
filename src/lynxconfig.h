#ifndef LYNXCONFIG_H
#define LYNXCONFIG_H

#include <util/system.h>

/** Write a default conf file if none exists. Returns true if one was written. */
bool check_lynx_config(const ArgsManager& args);

#endif // LYNXCONFIG_H
