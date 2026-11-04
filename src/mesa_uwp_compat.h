/* Compatibility shim for building Mesa with clang-cl, force-included through /FI.
 *
 * Two gaps, both in src/util/u_atomic.h and its users:
 *
 *  1. Mesa calls _InterlockedAdd and _InterlockedAdd64, which Microsoft only provides on ARM.
 *     On x64 they do not exist, in MSVC either; they are written here in terms of
 *     _InterlockedExchangeAdd, which returns the value *before* adding.
 *
 *  2. Mesa also uses the all-lowercase spellings of several interlocked intrinsics. MSVC
 *     declares those as well as the CamelCase ones; clang-cl only the CamelCase ones.
 */
#pragma once

/* __ASSEMBLER__: a force-include reaches the .S files too (blake3's SIMD kernels), and the
 * assembler cannot read C -- it chokes inside <intrin.h> with "unexpected token in argument
 * list". Everything below is for the C and C++ compilers only. */
#ifndef __ASSEMBLER__

#include <intrin.h>

/* Esta compilacion va dentro de un AppContainer: no hay ventanas de escritorio ni
 * DirectComposition de escritorio, y la cadena de intercambio se crea sobre el CoreWindow.
 * Lo lee src/vulkan/wsi/wsi_common_win32.cpp. */
#define MESA_WSI_UWP 1

#ifndef MESA_UWP_COMPAT_INTERLOCKED
#define MESA_UWP_COMPAT_INTERLOCKED 1

/* Only these two: Mesa's own u_atomic.h already writes _InterlockedAdd8 and _InterlockedAdd16
 * the same way, and defining them here as well is a redefinition. */
#if defined(_M_X64) || defined(_M_IX86)
static inline long _InterlockedAdd(long volatile *target, long value) {
    return _InterlockedExchangeAdd(target, value) + value;
}
static inline __int64 _InterlockedAdd64(__int64 volatile *target, __int64 value) {
    return _InterlockedExchangeAdd64(target, value) + value;
}
#endif

/* The lowercase spellings Mesa expects from MSVC. */
#define _interlockedadd _InterlockedAdd
#define _interlockedadd8 _InterlockedAdd8
#define _interlockedadd16 _InterlockedAdd16
#define _interlockedadd64 _InterlockedAdd64
#define _interlockeddecrement64 _InterlockedDecrement64
#define _interlockedexchange64 _InterlockedExchange64
#define _interlockedexchangeadd64 _InterlockedExchangeAdd64
#define _interlockedincrement64 _InterlockedIncrement64

#endif /* MESA_UWP_COMPAT_INTERLOCKED */

#endif /* __ASSEMBLER__ */
