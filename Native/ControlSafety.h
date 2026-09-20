#pragma once
#include <stdbool.h>
#include <stdint.h>
static inline bool powerControlBlocked(uint32_t vendor,uint32_t model) { return vendor == 25001 && model == 10162; }

static inline bool canDisableDisplay(unsigned activeCount, bool targetActive, bool identityMatches) { return activeCount > 1 && targetActive && identityMatches; }

static inline bool canRestoreCachedDisplay(bool sameBoot, bool sameUUID, bool unavailableUUID, bool online, bool active) { return sameBoot && (sameUUID || (unavailableUUID && !online && !active)); }
