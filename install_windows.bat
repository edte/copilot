@echo off
echo begin

cd ..
set plugin_directory_path="vim"

set nvim_directory_path=%USERPROFILE%\AppData\Local\nvim\pack\gongfeng\start\vim\
if exist "%nvim_directory_path%" (
  rmdir /s /q "%nvim_directory_path%"
) 

echo Creating file(overwrite):%nvim_directory_path%
xcopy /s /e /y %plugin_directory_path% %nvim_directory_path%

set vim_directory_path=%USERPROFILE%\vimfiles\pack\gongfeng\start\vim\
if exist "%vim_directory_path%" (
  rmdir /s /q "%vim_directory_path%"
) 

echo Creating file(overwrite):%vim_directory_path%
xcopy /s /e /y %plugin_directory_path% %vim_directory_path%
echo Install success!
pause
