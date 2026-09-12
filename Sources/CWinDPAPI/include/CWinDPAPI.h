#ifndef OPC_CWIN_DPAPI_H
#define OPC_CWIN_DPAPI_H
// Header-only shim exposing DPAPI to Swift (mirrors the CSQLite pattern).
// windows.h must come first; dpapi.h declares CryptProtectData/CryptUnprotectData
// and pulls the CRYPT_DATA_BLOB types from wincrypt.h.
#include <windows.h>
#include <dpapi.h>
#endif
