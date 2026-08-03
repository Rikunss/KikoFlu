#include "audio_device_enum.h"

#include <windows.h>
#include <mmdeviceapi.h>
#include <combaseapi.h>

#include <string>

namespace {

// ── Property keys ───────────────────────────────────────────────────────────
// Defined locally to avoid INITGUID/macro quirks of the SDK headers.

// PKEY_Device_FriendlyName = {A45C254E-DF1C-4EFD-8020-67D146A850E0}, 14
static const PROPERTYKEY kPkeyDeviceFriendlyName = {
    {0xa45c254e, 0xdf1c, 0x4efd, {0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0}},
    14};

// PKEY_Device_DeviceDesc = {A45C254E-DF1C-4EFD-8020-67D146A850E0}, 2
static const PROPERTYKEY kPkeyDeviceDeviceDesc = {
    {0xa45c254e, 0xdf1c, 0x4efd, {0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0}},
    2};

// Device (interface) friendly name stored by the MMDevice property store —
// carries the vendor/model name (e.g. "TempoTec HD USB AUDIO",
// "JadeAudio JA11"). GUID from the device Properties registry subkey.
static const PROPERTYKEY kPkeyDeviceInterfaceFriendlyName = {
    {0xb3f8fa53, 0x0004, 0x438e, {0x90, 0x03, 0x51, 0xa4, 0x6e, 0x13, 0x9b, 0xfc}},
    6};

// PKEY_AudioEndpoint_FormFactor = {1DA5D803-D492-4EDD-8C23-E0C0FFEE7F0E}, 0
static const PROPERTYKEY kPkeyAudioEndpointFormFactor = {
    {0x1da5d803, 0xd492, 0x4edd, {0x8c, 0x23, 0xe0, 0xc0, 0xff, 0xee, 0x7f, 0x0e}},
    0};

// ── JSON helpers ────────────────────────────────────────────────────────────

std::wstring JsonEscape(const std::wstring& s) {
  std::wstring out;
  out.reserve(s.size() + 8);
  wchar_t buf[8];
  for (wchar_t c : s) {
    switch (c) {
      case L'"':
        out += L"\\\"";
        break;
      case L'\\':
        out += L"\\\\";
        break;
      case L'\n':
        out += L"\\n";
        break;
      case L'\r':
        out += L"\\r";
        break;
      case L'\t':
        out += L"\\t";
        break;
      default:
        if (c < 0x20) {
          swprintf_s(buf, 8, L"\\u%04x", static_cast<unsigned>(c));
          out += buf;
        } else {
          out += c;
        }
    }
  }
  return out;
}

// ── Core Audio accessors ────────────────────────────────────────────────────

std::wstring GetDeviceId(IMMDevice* device) {
  LPWSTR id = nullptr;
  if (FAILED(device->GetId(&id)) || id == nullptr) return L"";
  std::wstring result(id);
  CoTaskMemFree(id);
  return result;
}

std::wstring GetFriendlyName(IMMDevice* device) {
  IPropertyStore* store = nullptr;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &store)) || store == nullptr) {
    return L"";
  }
  std::wstring result;
  PROPVARIANT pv;
  PropVariantInit(&pv);
  if (SUCCEEDED(store->GetValue(kPkeyDeviceFriendlyName, &pv)) &&
      pv.vt == VT_LPWSTR && pv.pwszVal != nullptr) {
    result = pv.pwszVal;
  }
  PropVariantClear(&pv);
  store->Release();
  return result;
}

std::wstring GetDeviceInterfaceName(IMMDevice* device) {
  IPropertyStore* store = nullptr;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &store)) || store == nullptr) {
    return L"";
  }
  std::wstring result;
  PROPVARIANT pv;
  PropVariantInit(&pv);
  if (SUCCEEDED(store->GetValue(kPkeyDeviceInterfaceFriendlyName, &pv)) &&
      pv.vt == VT_LPWSTR && pv.pwszVal != nullptr) {
    result = pv.pwszVal;
  }
  PropVariantClear(&pv);
  store->Release();
  return result;
}

std::wstring GetDeviceDesc(IMMDevice* device) {
  IPropertyStore* store = nullptr;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &store)) || store == nullptr) {
    return L"";
  }
  std::wstring result;
  PROPVARIANT pv;
  PropVariantInit(&pv);
  if (SUCCEEDED(store->GetValue(kPkeyDeviceDeviceDesc, &pv)) &&
      pv.vt == VT_LPWSTR && pv.pwszVal != nullptr) {
    result = pv.pwszVal;
  }
  PropVariantClear(&pv);
  store->Release();
  return result;
}

int GetFormFactor(IMMDevice* device) {
  IPropertyStore* store = nullptr;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &store)) || store == nullptr) {
    return -1;
  }
  int form_factor = -1;
  PROPVARIANT pv;
  PropVariantInit(&pv);
  if (SUCCEEDED(store->GetValue(kPkeyAudioEndpointFormFactor, &pv)) &&
      pv.vt == VT_UI4) {
    form_factor = static_cast<int>(pv.ulVal);
  }
  PropVariantClear(&pv);
  store->Release();
  return form_factor;
}

}  // namespace

// ── Exported API ────────────────────────────────────────────────────────────

extern "C" __declspec(dllexport) wchar_t* kikoflu_enumerate_audio_devices(void) {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool co_initialized_here = SUCCEEDED(hr);
  // RPC_E_CHANGED_MODE means the thread was already initialized (MTA) — the
  // COM calls below are still safe, we just must not CoUninitialize here.
  if (!co_initialized_here && hr != RPC_E_CHANGED_MODE) return nullptr;

  IMMDeviceEnumerator* enumerator = nullptr;
  hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                        __uuidof(IMMDeviceEnumerator),
                        reinterpret_cast<void**>(&enumerator));
  if (FAILED(hr) || enumerator == nullptr) {
    if (co_initialized_here) CoUninitialize();
    return nullptr;
  }

  // Default render endpoint.
  std::wstring default_full_id;
  IMMDevice* default_device = nullptr;
  if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia,
                                                    &default_device)) &&
      default_device != nullptr) {
    default_full_id = GetDeviceId(default_device);
    default_device->Release();
  }

  std::wstring json;
  json += L"{\"default\":\"" + JsonEscape(default_full_id) + L"\",\"devices\":[";

  IMMDeviceCollection* collection = nullptr;
  hr = enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &collection);
  if (SUCCEEDED(hr) && collection != nullptr) {
    UINT count = 0;
    if (SUCCEEDED(collection->GetCount(&count))) {
      bool first = true;
      for (UINT i = 0; i < count; ++i) {
        IMMDevice* device = nullptr;
        if (FAILED(collection->Item(i, &device)) || device == nullptr) continue;

        const std::wstring full_id = GetDeviceId(device);
        const std::wstring name = GetFriendlyName(device);
        const std::wstring desc = GetDeviceDesc(device);
        const std::wstring iface = GetDeviceInterfaceName(device);
        const int form_factor = GetFormFactor(device);
        const bool is_default = !full_id.empty() && full_id == default_full_id;

        if (!first) json += L",";
        first = false;
        json += L"{\"fullId\":\"" + JsonEscape(full_id) +
                L"\",\"name\":\"" + JsonEscape(name) +
                L"\",\"desc\":\"" + JsonEscape(desc) +
                L"\",\"iface\":\"" + JsonEscape(iface) +
                L"\",\"formFactor\":" + std::to_wstring(form_factor) +
                L",\"isDefault\":" + (is_default ? L"true" : L"false") + L"}";
        device->Release();
      }
    }
    collection->Release();
  }
  json += L"]}";

  enumerator->Release();
  if (co_initialized_here) CoUninitialize();

  // Caller frees via kikoflu_free_string.
  const size_t chars = json.size() + 1;
  wchar_t* out = static_cast<wchar_t*>(CoTaskMemAlloc(chars * sizeof(wchar_t)));
  if (out == nullptr) return nullptr;
  wcscpy_s(out, chars, json.c_str());
  return out;
}

extern "C" __declspec(dllexport) void kikoflu_free_string(wchar_t* ptr) {
  if (ptr != nullptr) CoTaskMemFree(ptr);
}
