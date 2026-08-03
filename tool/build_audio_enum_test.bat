@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
if errorlevel 1 (
  echo VCVARS_FAILED
  exit /b 1
)
cl /nologo /EHsc /std:c++17 /DUNICODE /D_UNICODE /Iwindows\runner /Fe:C:\KikoFlu\build\audio_enum_test.exe tool\audio_device_enum_test.cpp windows\runner\audio_device_enum.cpp ole32.lib
if errorlevel 1 (
  echo COMPILE_FAILED
  exit /b 1
)
C:\KikoFlu\build\audio_enum_test.exe
