#include "audio_device_enum.h"
#include <cstdio>
#include <cwchar>

int main() {
  wchar_t* json = kikoflu_enumerate_audio_devices();
  if (json == nullptr) {
    wprintf(L"RESULT=NULL\n");
    return 1;
  }
  wprintf(L"%ls\n", json);
  kikoflu_free_string(json);
  return 0;
}
